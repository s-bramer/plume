extends RefCounted

## Authoritative simulation-side cell data, independent of rendering.
## Phase 1 step 1 (PLUME_PROJECT_BRIEF.md SS4/SS8): elevation plus the first
## slice of the cell-data table -- geology_id, K_m_s, porosity, head_m.
## specific_yield, recharge_m_s, bulk_density_kg_m3, dispersivity_*,
## mass_kg_by_species land here as later, separate tasks (transport/reactions).

const HexMath = preload("res://scripts/rendering/hex_math.gd")
const FlowSolver = preload("res://scripts/simulation/flow_solver.gd")

const BASE_ELEVATION_M := 100.0
const SLOPE_M_PER_ROW := 1.5 # land surface drops toward +r, where the flagship receptor sits
const UNDULATION_M := 2.0 # amplitude of each of the two cosine ripple terms

## Three geological units, standing in for a real site survey until Phase 2
## scenario data exists -- same spirit as the elevation formula below.
## K_m_s spans five orders of magnitude (brief SS4: "may become a tensor
## later", but even a scalar heterogeneous K is the MVP's whole point: a
## clay lens should visibly slow/divert flow once transport exists).
enum Geology { SAND, SILT, CLAY }

const GEOLOGY_NAME := {
	Geology.SAND: "Sand aquifer",
	Geology.SILT: "Silty sand",
	Geology.CLAY: "Clay lens",
}
## Shared by geology_overlay.gd (the x-ray fill) and World's x-ray legend --
## lives here, not in either rendering script, specifically so both read the
## exact same table and can never drift apart (one updated, the other not).
## Deliberately distinct from any surface-terrain color (World.GRASS_COLOR
## etc.) -- geology is a different concept from surface terrain.
const GEOLOGY_COLOR := {
	Geology.SAND: Color("d9c282"),
	Geology.SILT: Color("b98b56"),
	Geology.CLAY: Color("5b5f6b"),
}
## Defaults, used when GridModel is constructed with no overrides (every
## existing caller). _init() accepts k_overrides/porosity_overrides so a
## host (World) can expose these per-geology as Inspector-tunable "transport
## model parameters" instead of hand-editing code -- user's explicit
## observation: contamination entering a low-K clay cell gets stuck there
## with a large concentration, which is partly real physics (a real clay
## lens genuinely does retard and locally concentrate contamination -- see
## step_transport's doc comment) but whose exact severity depends on this
## project's own placeholder K-contrast (6000x, sand:clay) and porosity
## values, not a law of nature -- worth being able to dial without a code
## round-trip.
const DEFAULT_GEOLOGY_K_M_S := {
	Geology.SAND: 3.0e-4,
	Geology.SILT: 2.0e-5,
	Geology.CLAY: 5.0e-8,
}
const DEFAULT_GEOLOGY_POROSITY := {
	Geology.SAND: 0.30,
	Geology.SILT: 0.25,
	Geology.CLAY: 0.12,
}
## Effective (tortuosity-corrected) molecular diffusion coefficient for the
## dissolved species (brief SS12.2: "Effective pore-water diffusion...
## Tortuosity and porosity matter"; SS12.3's `D_m_effective` term). A SINGLE
## lumped parameter, not split into a free-water D_m and a separate
## tortuosity factor -- there's no real site data yet to constrain those
## independently, and the brief's own governing-equation section already
## writes it as one combined term.
##
## Deliberately a MUCH NARROWER range than K's 6000x sand:clay contrast --
## this is real physics, not an oversight: free-water diffusion coefficients
## for dissolved solutes are typically ~1e-9 m2/s regardless of what medium
## they're diffusing through; only TORTUOSITY (how much longer/windier the
## actual pore path is than a straight line) reduces that, and tortuosity
## effects are mild (roughly 2-5x) compared to how violently K depends on
## pore throat size (K depends on the pore radius squared or worse, which is
## why a clay's tiny pores throttle ADVECTIVE flow by orders of magnitude).
## A good teaching moment in its own right: clay resists water FLOWING
## through it far more than it resists a dissolved molecule WANDERING
## through it by diffusion -- which is exactly why diffusion/matrix-diffusion
## into low-K zones is a real, significant long-term contamination pathway
## (brief SS12.2's "Matrix diffusion / back-diffusion... major driver of
## long-term persistence", not yet modeled here -- see step_transport's doc
## comment on the scope of what this first diffusion pass covers).
const DEFAULT_GEOLOGY_DIFFUSION_M2_S := {
	Geology.SAND: 1.0e-9,
	Geology.SILT: 7.0e-10,
	Geology.CLAY: 4.0e-10,
}

## Brief SS12.2/SS12.3/SS12.6 Gate D: linear equilibrium sorption distribution
## coefficient, `Kd` [m3/kg] -- "depends on species and sediment" (brief
## SS12.2's own caveat). Species is still fixed/implicit (this MVP is still
## single-contaminant), so, same as K/porosity/diffusion above, Kd is a
## per-geology lookup: a clay/fine-grained unit's higher surface area and clay
## mineral content genuinely does sorb a typical organic solute more strongly
## than sand, independent of anything this project invented -- real physics,
## not a difficulty-tuning knob. Defaults chosen so clay's resulting
## retardation factor (see retardation_factor, derived below) is large enough
## to visibly matter without being a second, redundant "nothing ever moves"
## story on top of clay's existing 6000x K contrast.
const DEFAULT_GEOLOGY_KD_M3_KG := {
	Geology.SAND: 2.0e-4,
	Geology.SILT: 8.0e-4,
	Geology.CLAY: 3.0e-3,
}

## Average mineral grain (particle) density, used only to derive each cell's
## BULK density from its already-established porosity (rho_b = rho_particle *
## (1 - n_e), the standard relation) rather than inventing a second,
## independent per-geology bulk-density table that could silently drift out
## of sync with porosity. ~2650 kg/m3 is the standard textbook value for
## common quartz/silicate sediments and is deliberately NOT varied by
## geology: unlike porosity (which depends heavily on grain packing/sorting,
## the real reason sand/silt/clay differ), the mineral grains THEMSELVES are
## similar densities across these three placeholder units.
const PARTICLE_DENSITY_KG_M3 := 2650.0

## Regional head gradient used ONLY to define this model's two boundary
## conditions (brief SS12.6 Gate A: "conservative heterogeneous-K head
## solver" -- the prior MVP imposed this formula at EVERY cell, which the
## brief explicitly flags as not conserving water once K is heterogeneous;
## see _solve_heads()'s doc comment for the replacement). Head drops toward
## +r, the same general direction as the land-surface slope and the
## river/receptor:
## - North row (r == -radius): fixed (Dirichlet) head, this formula exactly
##   -- the domain's upgradient inflow boundary.
## - Every cell with an open south-outflow face (_SOUTH_OUTFLOW_OFFSETS):
##   a specified, head-INDEPENDENT outflow (see _south_boundary_outflow_m3_s)
##   derived from this same regional gradient -- the downgradient boundary.
## Every interior/other-edge cell's head is now SOLVED, not imposed from
## this formula -- see _solve_heads().
const BASE_HEAD_M := 50.0
const HEAD_GRADIENT_M_PER_ROW := 0.8

## Straight-line distance (m) between adjacent cell centers. The hex grid has
## no real-world scale defined anywhere else yet (map extent/DEM is a later,
## separate task) -- this is a placeholder assumption solely so face fluxes
## have a concrete denominator, documented here rather than buried in a
## formula so it's easy to find and replace later.
const CELL_SPACING_M := 100.0

## One-layer transport MVP (brief SS8 Phase 1 step 5): a single saturated
## thickness and planview cell area, same "placeholder, documented, easy to
## find and replace" spirit as CELL_SPACING_M above -- there is no real DEM
## or layer geometry yet. CELL_AREA_M2 treats each hex cell as if it were a
## CELL_SPACING_M x CELL_SPACING_M square for volume purposes (its exact
## shape doesn't matter for a lumped mass balance, only its area does).
## FACE_AREA_M2 is the cross-sectional area water/mass crosses through one
## face -- thickness x an assumed face width equal to the cell spacing
## itself (the standard simplification simple grid flow models use when the
## true face geometry isn't modeled).
const CELL_THICKNESS_M := 10.0
const CELL_AREA_M2 := CELL_SPACING_M * CELL_SPACING_M
const FACE_AREA_M2 := CELL_THICKNESS_M * CELL_SPACING_M

## Half of HexMath.NEIGHBOR_OFFSETS -- each is the exact opposite of one of
## the other three ((1,0)<->(-1,0), (1,-1)<->(-1,1), (0,-1)<->(0,1)), so
## iterating every cell against just these three visits every edge of the
## grid exactly once (same pattern GridOutline's shore-edge code uses for
## the same reason: processing an edge from both sides would double-count
## the mass transfer across it).
const _TRANSPORT_EDGE_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1)]

## The two neighbor directions that mean "further downstream" (south and
## southwest, i.e. toward +r) -- the outflow-side counterpart of the same
## south-facing-camera convention GridOutline's shore-edge code already uses
## for the cliff side (grid_outline.gd's _SHORE_EDGE_NEIGHBOR_OFFSETS), just
## pointed the opposite way. A cell whose neighbor in one of these
## directions falls outside the modeled hexagonal domain sits on the map's
## open downstream boundary (user's explicit ask: contamination should be
## able to "escape at the bottom of the screen"). Every OTHER edge of the
## map stays implicitly no-flow, exactly as before -- step_transport/
## max_stable_dt_s already just skip any neighbor that doesn't exist, and
## this only adds new behavior for these two specific directions.
const _SOUTH_OUTFLOW_OFFSETS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 1)]

var radius: int
var top_elevation_m: Dictionary = {} # Vector2i (q, r) -> float meters
var geology_id: Dictionary = {} # Vector2i (q, r) -> Geology enum value
var k_m_s: Dictionary = {} # Vector2i (q, r) -> float, hydraulic conductivity
var porosity: Dictionary = {} # Vector2i (q, r) -> float, effective porosity
var diffusion_m2_s: Dictionary = {} # Vector2i (q, r) -> float, effective molecular diffusion coefficient (brief SS12.2/SS12.3's D_m_effective)
var kd_m3_kg: Dictionary = {} # Vector2i (q, r) -> float, linear equilibrium sorption distribution coefficient (brief SS12.2/SS12.6 Gate D)
## Vector2i (q, r) -> float. Derivation of R_f = 1 + rho_b*Kd/n_e (brief
## SS12.3) from linear equilibrium sorption, S = Kd*C (S: mass sorbed per
## mass of dry solid [kg/kg], C: aqueous concentration [kg/m3 water]):
##   M_total = M_aqueous + M_sorbed = C*V_water + S*rho_b*V_total
##           = C*V_water + Kd*C*rho_b*V_total
##           = C*V_water * (1 + Kd*rho_b*V_total/V_water)
## and V_total/V_water = 1/n_e (V_water = n_e*V_total by definition), so:
##   M_total = C*V_water * (1 + rho_b*Kd/n_e) = C * V_pore * R_f
## i.e. M_total = R_f * C * V_pore -- see get_concentration_kg_m3's doc
## comment for why dividing BY R_f there is this project's entire
## implementation of Gate D (brief SS12.3's "represent total equilibrium
## inventory with retardation" option, not the separate-dissolved/sorbed-pools
## one, which is kinetic sorption's job if that's ever built).
var retardation_factor: Dictionary = {}
var head_m: Dictionary = {} # Vector2i (q, r) -> float, hydraulic head -- SOLVED by _solve_heads(), not an imposed formula (see BASE_HEAD_M's doc comment)
var last_head_solve: Dictionary = {} # diagnostics from the most recent _solve_heads() call: {heads, iterations, max_residual_m, converged} -- surfaced for tests/UI, not required for the physics itself
var mass_kg: Dictionary = {} # Vector2i (q, r) -> float, TOTAL contaminant mass (dissolved + sorbed, single species, MVP) -- see get_concentration_kg_m3's doc comment for how Gate D's retardation splits this into aqueous/sorbed shares without a second dictionary
var escaped_mass_kg: float = 0.0 # contaminant that has left the modeled domain through the open downstream boundary -- tracked, not discarded, so total mass stays auditable (mass_kg's sum + escaped_mass_kg should always equal everything ever seeded)
var captured_mass_kg: float = 0.0 # contaminant removed by the capture well (see set_well/step_transport) -- tracked the same way as escaped_mass_kg, not silently discarded
var geology_k_m_s: Dictionary # Geology enum value -> float, the table actually in use (defaults merged with any overrides)
var geology_porosity: Dictionary # Geology enum value -> float, ditto
var geology_diffusion_m2_s: Dictionary # Geology enum value -> float, ditto
var geology_kd_m3_kg: Dictionary # Geology enum value -> float, ditto

## Brief SS8 Phase 1 step 7 / SS12.4 test 9 ("pumping changes flow field and
## removes dissolved mass by extracted-water concentration"). Modeled as a
## specified-rate volumetric sink at one cell -- the well withdraws water
## (and whatever concentration of contaminant that water currently carries)
## at well_pumping_rate_m3_s, the same way the open downstream boundary
## already withdraws water via _south_boundary_outflow_m3_s (see
## max_stable_dt_s/step_transport, which treat both sinks identically for
## transport purposes).
##
## AS OF the SS12.6 Gate A head solver (_solve_heads()), the well's rate IS
## now one of the fixed sinks in the steady-state head balance (set_well()
## re-solves heads), so it DOES draw down head near well_axial and bend
## face_flux_m_s/the flow-arrow overlay toward it -- a real, if still
## simplified, capture-zone effect (a specified-RATE well, not a
## specified-DRAWDOWN one; the rate is fixed regardless of the head there,
## which is the correct idealization for a pump operating well within its
## capacity, not for one being asked to pump faster than the aquifer can
## locally deliver). Earlier versions of this file documented this as
## deliberately NOT modeled; that limitation is resolved as of this change.
var well_axial: Vector2i = Vector2i(0, 0)
var well_pumping_rate_m3_s: float = 0.0 # 0.0 means "no well" -- World pushes its own Inspector-tunable well_axial/well_pumping_rate_m3_s in via set_well, same live-tuning pattern as apply_geology_parameters

## Brief SS12.2/SS12.3/SS12.6 Gate C's second half: mechanical dispersion --
## the velocity-dependent, longitudinal/transverse spreading that molecular
## diffusion (above) deliberately left out. Unlike K/porosity/diffusion_m2_s,
## dispersivity is NOT treated as a per-geology lookup here: real dispersivity
## is primarily SCALE-dependent (how far/heterogeneously the plume has
## traveled), not a clean function of lithology the way K is, and the brief's
## own caveat says so directly ("Dispersivity is scale dependent"). A single
## scenario-wide pair of values is the honest simplification for this MVP --
## see World's dispersivity_longitudinal_m/dispersivity_transverse_m exports
## for the Inspector-tunable live-swap (set_dispersivity(), below).
##
## Default ratio (10:1, longitudinal:transverse) is the commonly cited rule of
## thumb (e.g. Gelhar et al.) for a conservative tracer; the absolute
## magnitude (10 m longitudinal) is deliberately a small fraction of
## CELL_SPACING_M (100 m) -- large enough to visibly broaden/elongate the
## plume without swamping advection, which is still the dominant transport
## process at this grid's velocities.
const DEFAULT_DISPERSIVITY_LONGITUDINAL_M := 10.0
const DEFAULT_DISPERSIVITY_TRANSVERSE_M := 1.0
var dispersivity_longitudinal_m: float = DEFAULT_DISPERSIVITY_LONGITUDINAL_M
var dispersivity_transverse_m: float = DEFAULT_DISPERSIVITY_TRANSVERSE_M

## Unit direction (Cartesian) of each of HexMath's 6 neighbor offsets, built
## once in _init() rather than per-call: _cell_velocity_vector_m_s() and
## _face_dispersion_conductance_m3_s() below both need these every substep,
## and they never change once the grid exists (they depend only on the hex
## grid's geometry, not on anything about THIS scenario). Deliberately reuses
## HexMath.axial_to_pixel's own flat-top geometry (via preload above, already
## used for cells_in_radius/neighbors) rather than re-deriving the same
## angles independently in this file, so the two can never silently drift
## apart if the hex orientation convention is ever revisited again (it
## already has been once, per that file's own header comment). The "size"
## argument (1.0) is irrelevant beyond normalization -- only the DIRECTION
## is used, never a physical length from it; CELL_SPACING_M is this file's
## own, separate source of truth for actual distance.
var _direction_unit_vectors: Dictionary = {} # Vector2i (one of HexMath.NEIGHBOR_OFFSETS) -> Vector2 unit direction

## k_overrides/porosity_overrides/diffusion_overrides/kd_overrides replace
## individual entries of DEFAULT_GEOLOGY_K_M_S/DEFAULT_GEOLOGY_POROSITY/
## DEFAULT_GEOLOGY_DIFFUSION_M2_S/DEFAULT_GEOLOGY_KD_M3_KG (keyed by the
## Geology enum) -- any geology not mentioned keeps its default. Every
## existing caller passes none of these and gets exactly the old hardcoded
## behavior.
func _init(p_radius: int, k_overrides: Dictionary = {}, porosity_overrides: Dictionary = {}, diffusion_overrides: Dictionary = {}, kd_overrides: Dictionary = {}) -> void:
	radius = p_radius
	for axial in HexMath.cells_in_radius(radius):
		top_elevation_m[axial] = _elevation_at(axial)
		geology_id[axial] = _geology_at(axial)
		mass_kg[axial] = 0.0
	for offset: Vector2i in HexMath.NEIGHBOR_OFFSETS:
		_direction_unit_vectors[offset] = HexMath.axial_to_pixel(offset, 1.0).normalized()
	apply_geology_parameters(k_overrides, porosity_overrides, diffusion_overrides, kd_overrides) # also solves the initial head field, see that function

## Live "hot swap" for the mechanical-dispersion parameters, same spirit as
## set_well/apply_geology_parameters -- called from World's own
## dispersivity_longitudinal_m/dispersivity_transverse_m exports' setters, so
## an Inspector edit made while playing takes effect on the very next
## transport step. Unlike set_well/apply_geology_parameters, this does NOT
## need to re-solve heads: dispersivity has no effect on the flow/head field
## at all, only on how transport spreads mass once the flow field exists.
func set_dispersivity(longitudinal_m: float, transverse_m: float) -> void:
	dispersivity_longitudinal_m = longitudinal_m
	dispersivity_transverse_m = transverse_m

## Re-derives k_m_s/porosity/diffusion_m2_s for every cell from its EXISTING
## geology_id (left untouched) and the given override tables -- a cheap "hot
## swap" of just the transport parameters, not a full rebuild. Deliberately
## does NOT touch elevation/geology_id/head_m/mass_kg/escaped_mass_kg, so a
## live Inspector tweak while playing re-prices the whole map's K/porosity/
## diffusion without resetting the plume's current position or the turn in
## progress -- exactly the live-tuning workflow this exists for (user: "even
## if I choose the highest possible K for clay... I am getting similar
## behaviour", because nothing had ever re-applied the change -- see
## World._refresh_geology_parameters, which calls this on every edit).
func apply_geology_parameters(k_overrides: Dictionary, porosity_overrides: Dictionary, diffusion_overrides: Dictionary = {}, kd_overrides: Dictionary = {}) -> void:
	geology_k_m_s = DEFAULT_GEOLOGY_K_M_S.duplicate()
	geology_k_m_s.merge(k_overrides, true)
	geology_porosity = DEFAULT_GEOLOGY_POROSITY.duplicate()
	geology_porosity.merge(porosity_overrides, true)
	geology_diffusion_m2_s = DEFAULT_GEOLOGY_DIFFUSION_M2_S.duplicate()
	geology_diffusion_m2_s.merge(diffusion_overrides, true)
	geology_kd_m3_kg = DEFAULT_GEOLOGY_KD_M3_KG.duplicate()
	geology_kd_m3_kg.merge(kd_overrides, true)
	for axial: Vector2i in geology_id.keys():
		var geo: int = geology_id[axial]
		k_m_s[axial] = geology_k_m_s[geo]
		porosity[axial] = geology_porosity[geo]
		diffusion_m2_s[axial] = geology_diffusion_m2_s[geo]
		kd_m3_kg[axial] = geology_kd_m3_kg[geo]
		# R_f = 1 + rho_b*Kd/n_e (brief SS12.2/SS12.3's retardation formula),
		# rho_b derived from THIS cell's own porosity (see
		# PARTICLE_DENSITY_KG_M3's doc comment) rather than a separate table --
		# recomputed here, not cached as its own export, so it always reflects
		# the porosity/Kd values actually in effect right now.
		var n_e: float = porosity[axial]
		if n_e > 0.0:
			var bulk_density_kg_m3: float = PARTICLE_DENSITY_KG_M3 * (1.0 - n_e)
			retardation_factor[axial] = 1.0 + bulk_density_kg_m3 * kd_m3_kg[axial] / n_e
		else:
			retardation_factor[axial] = 1.0 # no pore space to sort dissolved/sorbed between; get_concentration_kg_m3 already returns 0 for this cell regardless
	_solve_heads() # K changed -> every face conductance changed -> the steady-state head field must be re-solved, not just the K/porosity/diffusion/Kd tables

func get_elevation(axial: Vector2i) -> float:
	return top_elevation_m.get(axial, 0.0)

func get_geology(axial: Vector2i) -> int:
	return geology_id.get(axial, Geology.SAND)

func get_k(axial: Vector2i) -> float:
	return k_m_s.get(axial, 0.0)

func get_porosity(axial: Vector2i) -> float:
	return porosity.get(axial, 0.0)

func get_diffusion_m2_s(axial: Vector2i) -> float:
	return diffusion_m2_s.get(axial, 0.0)

func get_kd_m3_kg(axial: Vector2i) -> float:
	return kd_m3_kg.get(axial, 0.0)

## Bulk (dry) density -- derived from porosity, not a stored table; see
## PARTICLE_DENSITY_KG_M3's doc comment.
func get_bulk_density_kg_m3(axial: Vector2i) -> float:
	return PARTICLE_DENSITY_KG_M3 * (1.0 - get_porosity(axial))

## R_f = 1 + rho_b*Kd/n_e (brief SS12.2/SS12.3/SS12.6 Gate D). 1.0 (no
## retardation) for a cell apply_geology_parameters hasn't priced yet,
## matching every other get_*/default convention in this file.
func get_retardation_factor(axial: Vector2i) -> float:
	return retardation_factor.get(axial, 1.0)

func get_head(axial: Vector2i) -> float:
	return head_m.get(axial, 0.0)

## Live "hot swap" for the capture well's location/rate, same spirit as
## apply_geology_parameters -- a host (World) calls this from its own
## well_axial/well_pumping_rate_m3_s exports' setters, so an Inspector edit
## made while playing takes effect on the very next transport step rather
## than requiring a restart (see that bug's history on the geology exports).
func set_well(axial: Vector2i, pumping_rate_m3_s: float) -> void:
	well_axial = axial
	well_pumping_rate_m3_s = pumping_rate_m3_s
	_solve_heads() # the well is a fixed sink in the head balance -- its location/rate changing must re-solve heads, same reasoning as apply_geology_parameters

## Volumetric withdrawal (m3/s) at this cell from the capture well -- nonzero
## only at well_axial, and only if a rate has actually been configured.
func _well_outflow_m3_s(axial: Vector2i) -> float:
	if well_pumping_rate_m3_s <= 0.0 or axial != well_axial:
		return 0.0
	return well_pumping_rate_m3_s

## Returns Vector2(lowest, highest) elevation across the whole grid.
func elevation_range() -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	for value in top_elevation_m.values():
		lo = minf(lo, value)
		hi = maxf(hi, value)
	return Vector2(lo, hi)

## Deterministic synthetic terrain: a gentle downhill slope (toward the
## receptor side of the map) plus smooth cosine ripple, standing in for a
## real DEM/geology survey until Phase 2 scenario data exists.
static func _elevation_at(axial: Vector2i) -> float:
	var slope: float = BASE_ELEVATION_M - SLOPE_M_PER_ROW * axial.y
	var ripple_a: float = cos(axial.x * 0.6)
	var ripple_b: float = cos((axial.x + axial.y) * 0.4)
	var ripple: float = UNDULATION_M * (ripple_a + ripple_b)
	return slope + ripple

## Smooth function of (q, r), thresholded into bands -- a contiguous "lens"
## shape rather than independent per-cell noise, which is how real geological
## contacts actually look (sharp boundaries between blobs/bands, not static).
## Clay is deliberately the rarest band (hardest to avoid once you know it's
## there, easy to miss while characterizing -- exactly the fog-of-war tension
## brief SS9 wants).
static func _geology_at(axial: Vector2i) -> int:
	var n: float = cos(axial.x * 0.35 + axial.y * 0.5) + cos((axial.x - axial.y) * 0.25)
	if n > 1.1:
		return Geology.CLAY
	if n > 0.3:
		return Geology.SILT
	return Geology.SAND

## Pure linear gradient, no noise -- brief SS4 MVP is explicit that this
## first pass should be an IMPOSED gradient, not a solved balance (that's
## Phase 2's "solve a conservative steady-state groundwater-flow balance").
static func _head_at(axial: Vector2i) -> float:
	return BASE_HEAD_M - HEAD_GRADIENT_M_PER_ROW * axial.y

## Brief SS12.1/SS12.6 Gate A: "solve a conservative steady-state
## groundwater-flow balance with fixed-head/no-flow boundaries... and well
## sinks." Replaces the old "head_m = _head_at(axial) everywhere" MVP with an
## actual solve, delegated to FlowSolver (kept generic/GridModel-agnostic --
## see that file's own doc comment for the governing equation and method).
## This function's only job is ASSEMBLING this specific domain's boundary
## conditions and face conductances for the solver:
##
## - Dirichlet (fixed head): every cell in the north row (r == -radius),
##   held at _head_at's formula value -- the domain's upgradient inflow
##   boundary.
## - Specified flux (fixed, head-independent sink): every open south-outflow
##   face (_south_boundary_outflow_m3_s, summed per cell -- a corner cell can
##   have up to two such faces) PLUS the capture well's pumping rate at
##   well_axial, if configured.
## - No-flow: every other missing-neighbor face, by simple omission -- the
##   solver only ever sees faces it's explicitly given.
## - Interior faces: harmonic-mean-K conductance between every pair of
##   EXISTING neighbors, the same formula face_flux_m_s uses for a known head
##   field, just assembled into a linear system instead of applied to an
##   already-known one.
##
## Called from apply_geology_parameters() (K changed -> conductances changed)
## and set_well() (the well sink moved/changed rate) -- both "hot swap"
## triggers, same live-tuning discipline as the rest of this file. The
## result (and solver diagnostics) are stored in head_m/last_head_solve.
func _solve_heads() -> void:
	# Integer indexing (see FlowSolver's doc comment on why): assign every
	# cell a stable position in one array, build adjacency/sinks/initial
	# heads against that, solve, then translate the result back to
	# head_m's normal Vector2i keying -- everything outside this function
	# still only ever sees axial coordinates.
	var all_axials: Array[Vector2i] = []
	for axial: Vector2i in top_elevation_m.keys():
		all_axials.append(axial)
	var index_of: Dictionary = {}
	for i in range(all_axials.size()):
		index_of[all_axials[i]] = i

	var unknown_indices := PackedInt32Array()
	var heads := PackedFloat64Array()
	var fixed_sinks := PackedFloat64Array()
	var neighbor_indices: Array = []
	var neighbor_conductances: Array = []
	heads.resize(all_axials.size())
	fixed_sinks.resize(all_axials.size())
	neighbor_indices.resize(all_axials.size())
	neighbor_conductances.resize(all_axials.size())

	for i in range(all_axials.size()):
		var axial: Vector2i = all_axials[i]
		heads[i] = _head_at(axial) # a reasonable starting guess everywhere, not just the Dirichlet row -- speeds convergence
		if axial.y == -radius:
			continue # Dirichlet: heads[i] keeps this fixed value, never added to unknown_indices, never updated by the solver

		unknown_indices.append(i)

		var neighbor_idx := PackedInt32Array()
		var neighbor_c := PackedFloat64Array()
		for neighbor in HexMath.neighbors(axial):
			if not index_of.has(neighbor):
				continue
			var k_a := get_k(axial)
			var k_b := get_k(neighbor)
			var k_h := 0.0
			if k_a + k_b > 0.0:
				k_h = 2.0 * k_a * k_b / (k_a + k_b)
			neighbor_idx.append(index_of[neighbor])
			neighbor_c.append(k_h * FACE_AREA_M2 / CELL_SPACING_M)
		neighbor_indices[i] = neighbor_idx
		neighbor_conductances[i] = neighbor_c

		var sink := 0.0
		for boundary_offset in _SOUTH_OUTFLOW_OFFSETS:
			if not index_of.has(axial + boundary_offset):
				sink += _south_boundary_outflow_m3_s(axial)
		if well_pumping_rate_m3_s > 0.0 and axial == well_axial:
			sink += well_pumping_rate_m3_s
		fixed_sinks[i] = sink

	var result := FlowSolver.solve(unknown_indices, neighbor_indices, neighbor_conductances, heads, fixed_sinks)
	var solved_heads: PackedFloat64Array = result["heads"]
	for i in range(all_axials.size()):
		head_m[all_axials[i]] = solved_heads[i]
	last_head_solve = {
		"iterations": result["iterations"],
		"max_residual_m": result["max_residual_m"],
		"converged": result["converged"],
	}

## Darcy face flux (m/s) across the shared face between two adjacent cells.
## q = -K dh/dL; returned as a signed value, positive meaning flow from
## axial_a toward axial_b (i.e. head_a > head_b). Uses the harmonic mean of
## the two cells' K -- the correct way to average conductivity for two media
## in series along the flow path between the two cell centers, so a single
## low-K cell (e.g. a clay lens) dominates the face conductance the way it
## should physically, not gets diluted by an average with its sandy neighbor.
func face_flux_m_s(axial_a: Vector2i, axial_b: Vector2i) -> float:
	var k_a := get_k(axial_a)
	var k_b := get_k(axial_b)
	var k_h := 0.0
	if k_a + k_b > 0.0:
		k_h = 2.0 * k_a * k_b / (k_a + k_b)
	var dh := get_head(axial_a) - get_head(axial_b)
	return k_h * dh / CELL_SPACING_M

## Pore-water velocity magnitude (m/s) across that same face: v = q / n_e
## (brief SS4), using the average effective porosity of the two cells.
func pore_velocity_m_s(axial_a: Vector2i, axial_b: Vector2i) -> float:
	var q := face_flux_m_s(axial_a, axial_b)
	var n_e := (get_porosity(axial_a) + get_porosity(axial_b)) / 2.0
	if n_e <= 0.0:
		return 0.0
	return q / n_e

## Brief SS12.2/SS12.3 Gate C: molecular diffusion. "Effective pore-water
## diffusion, including at zero flow" -- Fick's law applied face-to-face,
## the diffusive analogue of face_flux_m_s/_volumetric_flow_m3_s:
##   F_diff_face = -n_e * A_face * D_normal * (C_j - C_i) / distance   [kg/s]
## (brief SS12.3's own formula). This returns the CONDUCTANCE part of that
## (everything except the concentration difference itself, which varies by
## direction/timestep and so isn't baked in here):
##   G_diff_face = n_e_face * A_face * D_face / distance   [m3/s]
## -- dimensionally a volumetric-flow-equivalent, exactly like a face's
## advective Q, which is what lets step_transport() and max_stable_dt_s()
## fold it into the SAME accumulators advection already uses (a diffusive
## "conductance" multiplied by a concentration gives kg/s, same as
## Q * concentration does).
##
## D_face: harmonic mean of the two cells' diffusion_m2_s -- same "two media
## in series" reasoning face_flux_m_s already uses for K (a low-diffusion
## cell should dominate the face the way it physically does, not get diluted
## by averaging with a high-diffusion neighbor). n_e_face: ARITHMETIC mean
## porosity -- porosity isn't a series resistance the way K/D are, it's a
## cross-sectional-area fraction, the same averaging pore_velocity_m_s
## already uses for n_e.
func _face_diffusion_conductance_m3_s(axial_a: Vector2i, axial_b: Vector2i) -> float:
	var d_a := get_diffusion_m2_s(axial_a)
	var d_b := get_diffusion_m2_s(axial_b)
	var d_h := 0.0
	if d_a + d_b > 0.0:
		d_h = 2.0 * d_a * d_b / (d_a + d_b)
	var n_e := (get_porosity(axial_a) + get_porosity(axial_b)) / 2.0
	return n_e * FACE_AREA_M2 * d_h / CELL_SPACING_M

## Pore-water velocity VECTOR (brief SS4's v = q/n_e, generalized from one
## face's scalar magnitude to a full 2D vector), reconstructed from all six
## of a cell's face fluxes -- needed so mechanical dispersion (below) knows
## the LOCAL FLOW DIRECTION, not just one face's own flow rate (brief
## SS12.3: "Use a tensor and face-normal projection for general flow
## directions").
##
## Reconstruction: sum each face's signed Darcy flux times that face's own
## unit direction, then divide by 3. This is EXACT for a locally uniform
## flow field: a flat-top hex's 6 neighbor directions are always evenly
## spaced 60 degrees apart, and for N evenly spaced unit vectors in 2D,
## sum(n_hat (x) n_hat) = (N/2)*I -- here N=6, so dividing by 3 recovers the
## true flux vector exactly whenever all six faces are consistent with one
## uniform vector, and is a reasonable (least-squares-style) estimate
## otherwise. A missing neighbor (map edge) contributes nothing, which is
## exactly the same no-flow-by-omission convention _solve_heads() already
## uses for a missing-neighbor face -- not a new approximation invented for
## this function.
func _cell_velocity_vector_m_s(axial: Vector2i) -> Vector2:
	var flux_vec := Vector2.ZERO
	for offset: Vector2i in HexMath.NEIGHBOR_OFFSETS:
		var neighbor: Vector2i = axial + offset
		if not top_elevation_m.has(neighbor):
			continue
		flux_vec += face_flux_m_s(axial, neighbor) * _direction_unit_vectors[offset]
	var n_e := get_porosity(axial)
	if n_e <= 0.0:
		return Vector2.ZERO
	return (flux_vec / 3.0) / n_e

## Every cell's velocity vector, computed once per step_transport()/
## max_stable_dt_s() call rather than redundantly inside the per-face loop
## (each cell would otherwise be recomputed up to 4 times per call: once as
## the upstream side of its own 3 transport-edge faces, up to 3 more times
## as a neighbor of an adjacent cell's).
func _all_cell_velocity_vectors_m_s() -> Dictionary:
	var result: Dictionary = {}
	for axial: Vector2i in top_elevation_m.keys():
		result[axial] = _cell_velocity_vector_m_s(axial)
	return result

## Brief SS12.2/SS12.3/SS12.6 Gate C's mechanical-dispersion term -- velocity-
## dependent spreading, ADDED on top of (not replacing) molecular diffusion
## above. D_L = alpha_L * |v| (longitudinal, along the local flow direction)
## and D_T = alpha_T * |v| (transverse, perpendicular to it) are projected
## onto THIS face's own normal direction via the standard 2D dispersion-
## tensor projection:
##   D_normal = D_T + (D_L - D_T) * cos(theta)^2
## where theta is the angle between the local flow direction and the face
## normal (brief SS12.3: "Use a tensor and face-normal projection for general
## flow directions"). |v| and the flow direction come from the AVERAGE of
## the two cells' velocity vectors sharing this face -- a representative
## LOCAL flow vector for the face, not just this one face's own flux: real
## dispersion is a property of the bulk flow carrying a parcel of water past
## this face, not of one face's flow rate in isolation.
##
## Returns the same CONDUCTANCE shape _face_diffusion_conductance_m3_s does
## (this IS the same Fickian form -- dispersion spreads down the
## concentration gradient exactly like diffusion does, just with a velocity-
## dependent coefficient instead of a fixed one), so step_transport()/
## max_stable_dt_s() add this straight onto the SAME diffusive accumulator
## diffusion already contributes to, rather than needing a parallel code
## path. Zero when the local flow is stagnant (D_L and D_T both collapse to
## 0 at v=0) -- correct: mechanical dispersion requires flow, unlike
## molecular diffusion, which is already handled as its own unconditional
## term elsewhere.
##
## velocity_vectors: the WHOLE grid's precomputed _all_cell_velocity_vectors_m_s()
## result, passed in rather than recomputed here -- see that function's doc
## comment for why.
func _face_dispersion_conductance_m3_s(axial_a: Vector2i, axial_b: Vector2i, offset: Vector2i, velocity_vectors: Dictionary) -> float:
	var v_a: Vector2 = velocity_vectors[axial_a]
	var v_b: Vector2 = velocity_vectors[axial_b]
	var v_avg := (v_a + v_b) / 2.0
	var speed := v_avg.length()
	if speed <= 0.0:
		return 0.0
	var cos_theta := v_avg.dot(_direction_unit_vectors[offset]) / speed
	var d_l := dispersivity_longitudinal_m * speed
	var d_t := dispersivity_transverse_m * speed
	var d_normal := d_t + (d_l - d_t) * cos_theta * cos_theta
	var n_e := (get_porosity(axial_a) + get_porosity(axial_b)) / 2.0
	return n_e * FACE_AREA_M2 * d_normal / CELL_SPACING_M

## All six neighbor face fluxes for one cell, keyed by neighbor axial --
## convenience for UI (cell inspector) and the future transport step, so
## neither needs to re-derive HexMath.neighbors() + face_flux_m_s() itself.
## Skips neighbors that fall outside the modeled grid.
func neighbor_fluxes_m_s(axial: Vector2i) -> Dictionary:
	var result := {}
	for neighbor in HexMath.neighbors(axial):
		if top_elevation_m.has(neighbor):
			result[neighbor] = face_flux_m_s(axial, neighbor)
	return result

## --- Transport (brief SS8 Phase 1 step 5: "seed a finite contaminant mass
## in one or more cells; implement conservative, one-layer, advection-only
## transport") ---

## Adds contaminant mass to a cell (additive, not a set -- so a later
## leaking-source feature can call this repeatedly without needing to read
## the current value first).
func seed_mass_kg(axial: Vector2i, added_mass_kg: float) -> void:
	mass_kg[axial] = get_mass_kg(axial) + added_mass_kg

func get_mass_kg(axial: Vector2i) -> float:
	return mass_kg.get(axial, 0.0)

## Resets the mass balance back to scenario start -- every cell's mass_kg to
## 0.0, escaped_mass_kg to 0.0, and captured_mass_kg to 0.0. Deliberately
## leaves elevation/geology_id/head_m/k_m_s/porosity AND the well's own
## configuration (well_axial/well_pumping_rate_m3_s) untouched, so a reset
## replays the SAME map (and the player's current live-tuned K/porosity and
## well placement) rather than regenerating a new one or discarding their
## tuning work -- World.reset_scenario() re-seeds the source afterward.
func reset_mass() -> void:
	for axial: Vector2i in mass_kg.keys():
		mass_kg[axial] = 0.0
	escaped_mass_kg = 0.0
	captured_mass_kg = 0.0

func total_mass_kg() -> float:
	var total := 0.0
	for value in mass_kg.values():
		total += value
	return total

## Pore (mobile, water-filled) volume of one cell -- the brief's "effective/
## mobile porosity for transport" applied to this MVP's single layer.
func pore_volume_m3(axial: Vector2i) -> float:
	return CELL_AREA_M2 * CELL_THICKNESS_M * get_porosity(axial)

## AQUEOUS (dissolved) concentration within a cell: mass_kg[axial] is the
## cell's TOTAL contaminant inventory (dissolved + sorbed, brief SS12.3:
## "either represent total equilibrium inventory with retardation or
## explicitly track dissolved/sorbed pools; do not apply both independently"
## -- this implementation takes the FIRST option, not the second, which is
## why there is no separate "sorbed_mass_kg" dictionary: sorbed mass is a
## derived fraction of mass_kg, not separately tracked state. For linear
## equilibrium sorption, M_total = R_f * C * V_pore (see this file's header
## comment above retardation_factor for the derivation from S = Kd*C), so
## C = M_total / (R_f * V_pore) -- dividing by the ADDITIONAL retardation
## factor on top of the plain mass/volume this always was is the entire
## change Gate D makes to this function. Every caller of this function
## (advective/diffusive/dispersive transfer, well capture, south-boundary
## escape) already wants the AQUEOUS concentration, not the total inventory:
## only dissolved mass moves with flowing water or diffuses, sorbed mass
## stays on the solid matrix -- so retardation correctly falls out of every
## one of those terms for free, without changing any of their own formulas.
## Zero for a cell with no pore volume (shouldn't happen with the current
## geology table, since every porosity > 0, but a real porosity of exactly
## 0.0 is physically valid, so guard it rather than divide by zero).
func get_concentration_kg_m3(axial: Vector2i) -> float:
	var volume := pore_volume_m3(axial)
	if volume <= 0.0:
		return 0.0
	return get_mass_kg(axial) / (get_retardation_factor(axial) * volume)

## The DISSOLVED share of a cell's total inventory (brief SS12.5: "inspect
## each cell's... sorbed inventory" wants both halves inspectable) --
## get_concentration_kg_m3's own numerator, i.e. mass_kg[axial] / R_f, never
## separately stored (see get_concentration_kg_m3's doc comment).
func get_dissolved_mass_kg(axial: Vector2i) -> float:
	return get_mass_kg(axial) / get_retardation_factor(axial)

## The SORBED share: whatever of mass_kg[axial] isn't currently dissolved.
## Always >= 0 since retardation_factor >= 1.0.
func get_sorbed_mass_kg(axial: Vector2i) -> float:
	return get_mass_kg(axial) - get_dissolved_mass_kg(axial)

func _volumetric_flow_m3_s(axial_a: Vector2i, axial_b: Vector2i) -> float:
	return face_flux_m_s(axial_a, axial_b) * FACE_AREA_M2

## Flux (m3/s) draining through ONE open downstream boundary face at this
## cell -- a SPECIFIED-FLUX boundary condition (brief SS12.1's third BC type,
## alongside fixed-head and no-flow), not a Cauchy/general-head one: the
## external head one row south of the modeled domain is defined as
## continuing the SAME regional gradient the whole domain's two boundaries
## are anchored to (BASE_HEAD_M/HEAD_GRADIENT_M_PER_ROW), a fixed, KNOWN
## constant -- so q = K(axial) * HEAD_GRADIENT_M_PER_ROW / CELL_SPACING_M is
## independent of this cell's own (now solved, not imposed) head. This is
## exactly what makes it usable as a fixed sink term in _solve_heads()'s
## linear system rather than needing to be part of the matrix itself. Always
## >= 0 since the regional gradient is positive by construction -- this
## boundary only ever drains outward, never inward.
func _south_boundary_outflow_m3_s(axial: Vector2i) -> float:
	return get_k(axial) * HEAD_GRADIENT_M_PER_ROW / CELL_SPACING_M * FACE_AREA_M2

## The largest time step (s) that keeps every cell's total outflow (interior
## faces AND the open downstream boundary) within its own current mass this
## turn -- the explicit-upwind scheme's CFL stability bound. A caller that
## steps with a larger dt risks driving a cell's mass negative, which would
## silently break the brief SS9 mass-conservation guardrail. step_transport()
## does not clamp to this itself (no flux limiter yet -- out of scope for
## the MVP); the turn loop that calls it should pick dt <= this value.
##
## Diffusive conductance (_face_diffusion_conductance_m3_s) is added
## SYMMETRICALLY to both cells on a face, unlike advective flow (which only
## ever drains the single upstream cell, so only that side accumulates
## outflow): diffusion has no fixed direction, it flows whichever way
## concentration happens to be higher at the time, so EITHER cell could be
## the one losing mass across this face on a given step -- the conservative
## (worst-case-for-stability) treatment is to count the face's full
## diffusive conductance as potential outflow for both of them. Mechanical
## dispersion (_face_dispersion_conductance_m3_s, Gate C's second half) is
## the SAME Fickian shape as diffusion -- no fixed direction either -- so it
## gets the identical symmetric treatment, added onto the same accumulator.
func max_stable_dt_s() -> float:
	# Dictionary.keys() returns a plain (untyped) Array, so its elements are
	# Variant -- explicitly typing the loop variable (not just `for axial in
	# ...`) is what lets `axial + face_offset` below infer a real type. Same
	# underlying lesson as the untyped-const bug documented in
	# grid_outline.gd: an untyped collection poisons type inference for
	# everything derived from its elements.
	var outflow_total: Dictionary = {}
	for axial: Vector2i in top_elevation_m.keys():
		outflow_total[axial] = 0.0
	var velocity_vectors := _all_cell_velocity_vectors_m_s()
	for axial: Vector2i in top_elevation_m.keys():
		for face_offset in _TRANSPORT_EDGE_OFFSETS:
			var neighbor: Vector2i = axial + face_offset
			if not top_elevation_m.has(neighbor):
				continue
			var q := _volumetric_flow_m3_s(axial, neighbor)
			if q > 0.0:
				outflow_total[axial] += q
			elif q < 0.0:
				outflow_total[neighbor] += -q
			var g_diff := _face_diffusion_conductance_m3_s(axial, neighbor)
			outflow_total[axial] += g_diff
			outflow_total[neighbor] += g_diff
			var g_disp := _face_dispersion_conductance_m3_s(axial, neighbor, face_offset, velocity_vectors)
			outflow_total[axial] += g_disp
			outflow_total[neighbor] += g_disp
		for boundary_offset in _SOUTH_OUTFLOW_OFFSETS:
			if top_elevation_m.has(axial + boundary_offset):
				continue # a real cell is there; that face is already counted above, from one side or the other
			outflow_total[axial] += _south_boundary_outflow_m3_s(axial)
		outflow_total[axial] += _well_outflow_m3_s(axial)
	var min_dt := INF
	for axial: Vector2i in top_elevation_m.keys():
		var outflow: float = outflow_total[axial]
		if outflow <= 0.0:
			continue
		# Every term accumulated into outflow_total above eventually multiplies
		# get_concentration_kg_m3(axial) in step_transport(), which Gate D's
		# retardation already shrinks by 1/R_f (see that function's doc
		# comment) -- so the fraction of mass_kg[axial] actually removed per
		# second is outflow/(R_f*pore_volume), not outflow/pore_volume. Scaling
		# the stability bound by R_f here (rather than threading it through
		# every term above) keeps this the one place that has to know it:
		# retardation makes a cell's TOTAL inventory drain slower, so this
		# only ever relaxes (never tightens) the bound.
		min_dt = minf(min_dt, get_retardation_factor(axial) * pore_volume_m3(axial) / outflow)
	return min_dt

## Advances contaminant mass by dt_s seconds: conservative, one-layer
## advection PLUS molecular diffusion PLUS mechanical dispersion (brief SS8
## Phase 1 step 5 + SS12.6 Gate C), PLUS Gate D's linear equilibrium sorption/
## retardation -- the latter needs no separate term here at all, since it
## only ever acts through get_concentration_kg_m3() shrinking the AQUEOUS
## concentration every term below already uses (see that function's doc
## comment). Reactions/degradation (Gate D's other half) remain unimplemented.
## Advection uses an upwind scheme: mass
## crossing a face moves at that face's volumetric flow rate, carrying the
## UPSTREAM cell's concentration (whichever side the flux actually flows
## from), the standard way to keep an explicit advection scheme stable and
## conservative. Diffusion and dispersion are both added on top of that at
## the SAME face, independently: neither cares about flow direction the way
## advection does, both move mass from higher to lower concentration
## regardless of which way (or, for diffusion alone, whether) water is
## flowing there -- see _face_diffusion_conductance_m3_s/
## _face_dispersion_conductance_m3_s's doc comments for the governing
## equations. Every edge's transfer (all three terms) is computed once from
## pre-step concentrations (into `delta`) and applied only after the full
## pass, so processing order can never let one edge's update affect
## another's within the same step.
##
## SCOPE, same for diffusion and dispersion alike: interior cell-to-cell
## faces only. The open south boundary and the capture well do NOT diffuse or
## disperse (both still only move mass via their existing advective/
## specified-rate terms) -- deliberately deferred rather than guessed at: an
## open boundary needs its own documented assumption (what's the
## concentration/velocity "outside" the modeled domain?) that doesn't yet
## have a clear answer, and nothing in brief SS12.4's required test list
## needs it to exist yet.
##
## Cells on the open downstream boundary (_SOUTH_OUTFLOW_OFFSETS) ALSO lose
## mass through _south_boundary_outflow_m3_s each such face -- that mass
## isn't added to any other cell's delta, it leaves the modeled domain
## entirely (tracked in escaped_mass_kg, not silently discarded). This is a
## deliberate open boundary, not a conservation bug: mass_kg's sum will now
## decrease over time as a plume reaches the edge, but mass_kg's sum PLUS
## escaped_mass_kg is still exactly conserved -- the stronger, physically
## correct sense of "mass balance" real groundwater models use once a
## discharge boundary exists, not the weaker "nothing ever leaves" one a
## fully closed domain would have.
##
## WHY MASS APPEARS TO GET "STUCK" IN CLAY (user-observed, 2026-10-20): the
## harmonic-mean K used by face_flux_m_s is symmetric -- a clay cell's low K
## throttles outflow FROM it just as much as it throttled inflow INTO it, so
## mass that enters a clay lens drains back out far slower than it arrived.
## Combined with clay's lower porosity (same mass, smaller pore volume ->
## higher concentration reading), a clay cell can show a disproportionately
## large, slow-fading concentration long after the main plume has moved on.
## This IS a real phenomenon (low-permeability zones genuinely act as
## long-term secondary sources via back-diffusion/matrix diffusion -- a
## well-documented real remediation headache, not a bug), but its exact
## severity here depends on this MVP's own placeholder K-contrast and
## porosity numbers, not a law of nature. See geology_k_m_s/geology_porosity
## (set via _init's overrides, exposed as Inspector exports on World) to
## tune how extreme this effect looks without a code change.
func step_transport(dt_s: float) -> void:
	var delta: Dictionary = {}
	for axial: Vector2i in top_elevation_m.keys():
		delta[axial] = 0.0
	var velocity_vectors := _all_cell_velocity_vectors_m_s()
	for axial: Vector2i in top_elevation_m.keys():
		for face_offset in _TRANSPORT_EDGE_OFFSETS:
			var neighbor: Vector2i = axial + face_offset
			if not top_elevation_m.has(neighbor):
				continue
			var q := _volumetric_flow_m3_s(axial, neighbor) # positive: axial -> neighbor
			var transfer_kg := 0.0
			if q > 0.0:
				transfer_kg = q * get_concentration_kg_m3(axial) * dt_s
			elif q < 0.0:
				transfer_kg = q * get_concentration_kg_m3(neighbor) * dt_s # q<0 * conc(neighbor) -> negative transfer, i.e. mass actually flows neighbor -> axial
			# Diffusion AND mechanical dispersion: both independent of q/flow
			# direction entirely, always down the CONCENTRATION gradient
			# (Fick's law) -- positive when axial is more concentrated than
			# neighbor, same delta sign convention as the advective term
			# above, so all three simply add.
			var g_diff := _face_diffusion_conductance_m3_s(axial, neighbor)
			if g_diff > 0.0:
				transfer_kg += g_diff * (get_concentration_kg_m3(axial) - get_concentration_kg_m3(neighbor)) * dt_s
			var g_disp := _face_dispersion_conductance_m3_s(axial, neighbor, face_offset, velocity_vectors)
			if g_disp > 0.0:
				transfer_kg += g_disp * (get_concentration_kg_m3(axial) - get_concentration_kg_m3(neighbor)) * dt_s
			delta[axial] -= transfer_kg
			delta[neighbor] += transfer_kg
		for boundary_offset in _SOUTH_OUTFLOW_OFFSETS:
			if top_elevation_m.has(axial + boundary_offset):
				continue # a real cell is there; that face is already handled by the interior loop above
			var escaped_kg: float = _south_boundary_outflow_m3_s(axial) * get_concentration_kg_m3(axial) * dt_s
			delta[axial] -= escaped_kg
			escaped_mass_kg += escaped_kg
		var well_q := _well_outflow_m3_s(axial)
		if well_q > 0.0:
			var captured_kg: float = well_q * get_concentration_kg_m3(axial) * dt_s
			delta[axial] -= captured_kg
			captured_mass_kg += captured_kg
	for axial: Vector2i in delta.keys():
		mass_kg[axial] = get_mass_kg(axial) + delta[axial]
