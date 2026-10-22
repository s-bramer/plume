extends Node2D

## World root, per godot_hex_map_spec.md: Ground is a real TileMapLayer with
## a hex TileSet -- map_to_local()/local_to_map() are the single source of
## truth for cell positions. No hand-rolled axial-to-pixel math for
## placement; that's what caused every alignment bug earlier this session
## (selection-ring offset, hit-test drift, the zigzag gap).
##
## Map coordinates are NOT axial (q, r) directly: Godot's TILE_LAYOUT_STACKED
## is a discrete "odd-r" offset scheme, confirmed empirically across a wide
## (q, r) range (tests/run_tests.gd). GodotHexOffset converts explicitly at
## this boundary, per the spec's instruction not to mix hand-coded axial
## math with TileMapLayer coordinates.
##
## GROUND TILES: real hand-cut art where available, procedurally generated
## fallback otherwise (GROUND_TEXTURES below) -- not Kenney art. The Kenney
## "Hexagon Tiles" pack's silhouette doesn't taper like a true hexagon -- it
## sits at full width for more than half its height, so it needs far more
## row overlap than true hexagon math predicts to stay gap-free, which then
## can't be matched by any single "correct" grid outline size (measured and
## explained at length in DECISIONS.md). That was never a coordinate bug to
## fix; it was the wrong art for a simple flat grid.
##
## The real art (art/pretty_tiles/tiles/) is cut with
## hex_cutting_mask_1000x866.png (art/, generated from this file's own
## HEX_SIZE/hex_math.gd -- see DECISIONS.md) so its silhouette is a true hex
## to within a fraction of a percent, not guessed by eye -- it tiles
## edge-to-edge the same way the generated fallback tiles always did.
## TILE_SIZE below now matches that real art's own pixel dimensions exactly
## (the art is the source of truth once it exists for a terrain; HEX_SIZE is
## derived FROM it, not the other way round). Any terrain with no real art
## yet keeps using the generated fallback (hex_tile_texture.gd) at the same
## TILE_SIZE, so the grid stays one consistent geometry regardless of which
## terrains have real art.
##
## Trees/rocks/decals also now use real art (art/pretty_tiles/features/),
## replacing the Kenney art entirely as of 2026-10-19 -- still separate
## Features sprites, not ground tiles, not subject to the silhouette problem
## above (see DEPTH/OVERLAP RULE below). TERRAIN_ROCKY is a real terrain id,
## not just a decoration: a cell that rolls a boulder feature gets its ground
## tile swapped to the rocky-ground art too (see _terrain_for), so a boulder
## reads as standing on broken rock, not floating on plain snow.
##
## FLAT-TOP, not pointy-top: switched per user request (2026-10-15) -- reads
## more "map-like" and matches most off-the-shelf hex terrain art. Requires
## TILE_OFFSET_AXIS_VERTICAL + GodotHexOffset's odd-q scheme below, not the
## odd-r scheme a pointy-top/HORIZONTAL-axis setup would use.

const HexMath = preload("res://scripts/rendering/hex_math.gd")
const GridModel = preload("res://scripts/simulation/grid_model.gd")
const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const HexTileTexture = preload("res://scripts/rendering/hex_tile_texture.gd")

const GROUND_ART_DIR := "res://art/pretty_tiles/tiles/"
const FEATURE_ART_DIR := "res://art/pretty_tiles/features/"

const TILE_SIZE := Vector2i(122, 106) # real ground art's own pixel size (art/pretty_tiles/tiles/), no margin -- the hex fills this canvas exactly
const HEX_SIZE := TILE_SIZE.y / 1.7320508075688772 # circumradius, derived from TILE_SIZE's height (sqrt(3) inlined, see HexMath)
const TEXTURE_CANVAS_SIZE := Vector2i(TILE_SIZE.x, TILE_SIZE.y + 1) # only used by the generated FALLBACK source -- 1px safety margin so its border doesn't clip

const BORDER_COLOR := Color("5a5a5a") # even grey, per user reference
const BORDER_WIDTH := 1.5

const TINT_VARIANT_COUNT := 4 # alternative tiles per terrain, same texture, jittered modulate

const GRASS_COLOR := Color("8ea86b") # calm, desaturated green -- NOT the brief's reserved "toxic green"
const SAND_COLOR := Color("e6d2a3") # brief's own sandy beige
const WATER_COLOR := Color("6ca0c9") # calm blue -- NOT the brief's reserved dark aquifer blue
const SNOW_COLOR := Color("dfe7ea") # pale, close to the brief's vapor grey
const ROCKY_COLOR := Color("9a958f") # fallback only -- real art (rocky_01.png) always covers this terrain today

const TERRAIN_GRASS := 0
const TERRAIN_SAND := 1
const TERRAIN_WATER := 2
const TERRAIN_SNOW := 3
const TERRAIN_ROCKY := 4 # ground under a boulder feature -- see _terrain_for's coupling with _build_features

const TERRAIN_NAMES := {
	TERRAIN_GRASS: "Grass",
	TERRAIN_SAND: "Sand/Dirt",
	TERRAIN_WATER: "Water",
	TERRAIN_SNOW: "Snow",
	TERRAIN_ROCKY: "Rocky",
}

## Real ground art, keyed by TERRAIN_* id. Multiple entries per terrain are
## real painted variants (not modulate jitter) -- _build_terrain picks among
## them with an independent hash, same spirit as DECAL_SETS below. A terrain
## with no entry here falls back to the generated hex (_add_generated_source)
## at the same TILE_SIZE, so the grid geometry never depends on which
## terrains have real art yet.
const GRASS_ART: Array[Texture2D] = [
	preload(GROUND_ART_DIR + "grass_01.png"),
	preload(GROUND_ART_DIR + "grass_02.png"),
	preload(GROUND_ART_DIR + "grass_03.png"),
]
const WATER_ART: Array[Texture2D] = [
	preload(GROUND_ART_DIR + "water_01.png"),
]
const SNOW_ART: Array[Texture2D] = [
	preload(GROUND_ART_DIR + "ice_01.png"), # "ice" art mapped to the existing TERRAIN_SNOW slot
]
const SAND_ART: Array[Texture2D] = [
	preload(GROUND_ART_DIR + "dirt_01.png"), # "dirt" art mapped to the existing TERRAIN_SAND slot (both read as low/dry ground), per user decision
]
const ROCKY_ART: Array[Texture2D] = [
	preload(GROUND_ART_DIR + "rocky_01.png"),
]
static var GROUND_TEXTURES := {
	TERRAIN_GRASS: GRASS_ART,
	TERRAIN_WATER: WATER_ART,
	TERRAIN_SNOW: SNOW_ART,
	TERRAIN_SAND: SAND_ART,
	TERRAIN_ROCKY: ROCKY_ART,
}

## Trees/boulders/decals: real hand-cut art (art/pretty_tiles/features/), not
## Kenney art, as of 2026-10-19. Anchors are computed per-texture at
## placement time (_build_features/_maybe_add_decal), not a single shared
## constant like the old Kenney ROCK_CENTER_ANCHOR was -- these vary in
## canvas size per asset (trunk-based trees: bottom-center; "sitting" rocks:
## geometric center, same reasoning DECAL_SETS already uses below).
const TREES: Array[Texture2D] = [
	preload(FEATURE_ART_DIR + "tree_oak_large.png"),
	preload(FEATURE_ART_DIR + "tree_oak_small.png"),
	preload(FEATURE_ART_DIR + "tree_pine_large.png"),
	preload(FEATURE_ART_DIR + "tree_autumn.png"), # re-cut 2026-10-19 with real transparency, no longer the broken white-background export
]
const ROCKS: Array[Texture2D] = [
	preload(FEATURE_ART_DIR + "boulder_large.png"),
	preload(FEATURE_ART_DIR + "boulder_medium.png"),
	preload(FEATURE_ART_DIR + "boulder_small.png"),
]
## A separate, larger landmark tier above the regular boulders -- see
## MOUNTAIN_THRESHOLD. "Sitting" object, same center-anchor reasoning as ROCKS.
const MOUNTAINS: Array[Texture2D] = [
	preload(FEATURE_ART_DIR + "mountain_large.png"),
]

const SMALL_ROCK_DECAL := preload(FEATURE_ART_DIR + "boulder_small.png") # reused on sand/snow -- no dedicated small-rock-per-terrain art yet

## Scenario markers (brief SS8 Phase 1 step 7): the one fixed source and the
## player's one capture well, each a single real-art sprite (no variants --
## there's exactly one of each on the map, unlike TREES/ROCKS). Placed by
## _build_features at source_axial/well_axial, tagged kind="scenario" (not
## "feature" or "decal") so they're excluded from every existing kind-based
## rule (rocky/mountain coupling, decal/feature "don't double-dress" check,
## major-feature scatter) -- those rules are about ordinary procedural
## dressing, not a fixed, precisely-placed gameplay marker.
const WELL_ABSTRACTION := preload(FEATURE_ART_DIR + "well_abstraction.png")
const CONTAMINATION_BARREL := preload(FEATURE_ART_DIR + "contamination_barrel.png")
const RECEPTOR_LAKE := preload(FEATURE_ART_DIR + "receptor_lake.png")

# Small ground-clutter decals, one set per terrain -- CENTER anchored (see
# _maybe_add_decal): unlike a tree (a trunk growing from one ground point),
# every decal here is a small roundish blob sitting ON the ground. Keyed by
# TERRAIN_* id (the cell's actual rendered terrain), not elevation band
# directly, so a decal always matches the ground tile it sits on.
const GRASS_DECALS: Array[Texture2D] = [
	preload(FEATURE_ART_DIR + "flower_pink_medium.png"),
	preload(FEATURE_ART_DIR + "flower_yellow_medium.png"),
	preload(FEATURE_ART_DIR + "bush_small.png"),
	preload(FEATURE_ART_DIR + "bush_large.png"),
]
const SAND_DECALS: Array[Texture2D] = [
	SMALL_ROCK_DECAL,
]
const SNOW_DECALS: Array[Texture2D] = [
	SMALL_ROCK_DECAL,
]
static var DECAL_SETS := {
	TERRAIN_GRASS: GRASS_DECALS,
	TERRAIN_SAND: SAND_DECALS,
	TERRAIN_SNOW: SNOW_DECALS,
	TERRAIN_WATER: [] as Array[Texture2D], # no decals on river cells for now
	TERRAIN_ROCKY: [] as Array[Texture2D], # always carries a major boulder feature instead -- see _build_features
}

const SAND_THRESHOLD := 0.15
const FOREST_THRESHOLD := 0.70
const SNOW_THRESHOLD := 0.85
const MOUNTAIN_THRESHOLD := 0.95 # top slice of the snow band -- see _terrain_for's doc comment
const DECORATION_DENSITY := 0.45

@export var radius: int = 8
@export var show_debug_overlay: bool = true # on by default for Test B -- compare anchors against cell centers
@export var show_flow_overlay: bool = true # Darcy flow-vector arrows (flow_overlay.gd) -- also toggleable at runtime with F
## X-RAY ONLY as of the user's 2026-10-21 ask: the contaminant cloud must
## never be visible on the ordinary surface/terrain view, only inside x-ray
## mode (set_xray_mode) -- unlike show_flow_overlay (still a surface toggle),
## this export now means "enabled whenever x-ray mode is active," not
## "enabled right now." See set_xray_mode's doc comment.
@export var show_plume_overlay: bool = true # contaminant concentration cloud (plume_overlay.gd) -- x-ray only
## X-ray-only subsurface layer (user's 2026-10-21 ask): a flat fill color per
## cell keyed by its geology, plus a legend (_build_xray_legend).
@export var show_geology_overlay: bool = true
## X-ray-only subsurface layer (user's 2026-10-21 ask): equipotential contour
## lines from the solved head field -- see head_contour_overlay.gd.
@export var show_head_contour_overlay: bool = true

## Scenario setup for the transport MVP (brief SS8 Phase 1 step 5) -- where
## and how much contaminant mass starts on the map. No real scenario/source
## system exists yet (a leaking tank, a release event), so this is a single
## fixed seed at _ready(), Inspector-tunable like everything else placeholder
## in this build.
## (0, -5), not the map center: GridModel's geology field (_geology_at) peaks
## exactly at (0, 0) by construction (both its cosine terms hit 1.0 there),
## which deterministically makes the exact center a clay lens every time --
## a poor place to seed a demo source, since clay's K is ~6000x lower than
## sand and the plume would barely move. (0, -5) lands in sand on both the
## test default (radius 8) and scenes/main.tscn's (radius 14), with several
## rows of travel distance south to actually watch the plume advect through.
@export var source_axial: Vector2i = Vector2i(0, -5)
@export var source_mass_kg: float = 500.0

## Brief SS8 Phase 1 step 7: "...and one source behavior that keeps
## threatening the receptor without player input (e.g. a continuing release
## from the source)". Added to source_axial every substep of _advance_turn,
## proportional to that substep's dt -- a steady leak, not a one-time dump
## like source_mass_kg above. Nonzero by default so the behavior is actually
## observable without extra setup; 0.0 disables it entirely (a one-time spill
## with no ongoing threat). Tracked in _total_seeded_mass_kg exactly like the
## initial seed, so the mass-balance display's conservation check covers it
## too.
@export_range(0.0, 1.0e-4, 1.0e-6) var source_leak_rate_kg_s: float = 1.0e-5

## How much simulated time one Space-press advances. Deliberately NOT tied
## to GridModel.max_stable_dt_s() directly -- that CFL bound (tens of days,
## given today's placeholder K/head values) would make a single turn nearly
## invisible if used directly as the turn length; _advance_turn() instead
## substeps WITHIN this duration so the turn can be any length while still
## never violating the stability bound. This is a pure pacing/feel choice
## (how many Space-presses before the plume visibly moves), not a physics
## constant -- tune freely, per memory/feedback_expose_visual_tuning.md.
@export var turn_duration_s: float = 2_592_000.0 # ~30 days

## Holding Space keeps advancing turns rather than requiring a fresh press
## each time -- the initial press (via _unhandled_input's keydown event)
## advances one turn immediately; if Space is still held after
## turn_hold_repeat_delay_s, _process starts firing additional turns every
## turn_hold_repeat_interval_s until released. Mirrors ordinary OS key-repeat
## UX (a delay before repeating, then a faster steady rate) rather than
## repeating at the OS's own (inconsistent, not game-tunable) key-repeat
## rate. Inspector-tunable like every other feel/pacing choice here.
@export var turn_hold_repeat_delay_s: float = 0.4
@export var turn_hold_repeat_interval_s: float = 0.1

## Per-geology transport parameters, passed to GridModel's constructor --
## user-observed behavior: contamination entering a low-K clay cell drains
## back out far slower than it arrived (the same harmonic-mean K throttles
## both directions), and clay's lower porosity means the same mass reads as
## a higher concentration there too, so a clay lens can show a large,
## slow-fading value long after the main plume has passed. That's a real
## phenomenon (see GridModel.step_transport's doc comment), but exactly how
## extreme it looks depends on these placeholder numbers, not a law of
## nature -- exposed here instead of buried in GridModel so they're
## Inspector-tunable without a code change, same spirit as every other
## placeholder constant in this build. "exp" range hint: K spans orders of
## magnitude, where a linear slider would be nearly unusable.
##
## Each has a `set` so changing it WHILE PLAYING actually takes effect
## immediately (user report: turning clay_k_m_s all the way up still showed
## "similar behaviour" -- because _model was built once at _ready() and
## never touched again; a later Inspector edit changed the export variable
## but nothing ever re-read it into the running GridModel, so neither
## transport nor the flow-arrow overlay could possibly reflect it). The
## setter re-derives GridModel's per-cell K/porosity from the new values
## (_refresh_geology_parameters) and forces both overlays to redraw, so the
## effect is visible on the very next frame, not just the next full restart.
@export_range(1.0e-5, 1.0e-2, 1.0e-6, "exp") var sand_k_m_s: float = 3.0e-4:
	set(value):
		sand_k_m_s = value
		_refresh_geology_parameters()
@export_range(1.0e-7, 1.0e-3, 1.0e-7, "exp") var silt_k_m_s: float = 2.0e-5:
	set(value):
		silt_k_m_s = value
		_refresh_geology_parameters()
## Range widened to 3.0e-4 (sand's own K) rather than stopping at 1.0e-5:
## lets clay be pushed all the way up to "as permeable as sand" (fully
## removing the bottleneck) and, just as importantly, keeps a mid-range test
## value like 1.0e-5 comfortably off the slider's end-stop rather than
## pinned exactly at it -- the previous 1.0e-9..1.0e-5 range meant "the
## highest possible K" (what the user tried) WAS the exact maximum, and a
## slider sitting exactly on its own boundary is the one value worth not
## trusting blindly in any UI, since there's no way to tell "dragged to the
## end" apart from "the drag silently failed to commit and snapped back to
## some other value" just from the number shown.
@export_range(1.0e-9, 3.0e-4, 1.0e-8, "exp") var clay_k_m_s: float = 5.0e-8:
	set(value):
		clay_k_m_s = value
		_refresh_geology_parameters()
@export_range(0.05, 0.5, 0.01) var sand_porosity: float = 0.30:
	set(value):
		sand_porosity = value
		_refresh_geology_parameters()
@export_range(0.05, 0.5, 0.01) var silt_porosity: float = 0.25:
	set(value):
		silt_porosity = value
		_refresh_geology_parameters()
@export_range(0.02, 0.5, 0.01) var clay_porosity: float = 0.12:
	set(value):
		clay_porosity = value
		_refresh_geology_parameters()

## Brief SS12.2/SS12.3 Gate C: effective (tortuosity-corrected) molecular
## diffusion coefficient per geology -- see GridModel.DEFAULT_GEOLOGY_DIFFUSION_M2_S's
## doc comment for why this range is much narrower than the K sliders above
## (a few-x tortuosity effect, not K's orders-of-magnitude pore-throat
## effect -- real physics, not a smaller slider range by oversight). Same
## live-tuning setter pattern as every other geology export here.
@export_range(1.0e-11, 1.0e-8, 1.0e-11, "exp") var sand_diffusion_m2_s: float = 1.0e-9:
	set(value):
		sand_diffusion_m2_s = value
		_refresh_geology_parameters()
@export_range(1.0e-11, 1.0e-8, 1.0e-11, "exp") var silt_diffusion_m2_s: float = 7.0e-10:
	set(value):
		silt_diffusion_m2_s = value
		_refresh_geology_parameters()
@export_range(1.0e-11, 1.0e-8, 1.0e-11, "exp") var clay_diffusion_m2_s: float = 4.0e-10:
	set(value):
		clay_diffusion_m2_s = value
		_refresh_geology_parameters()

## Brief SS8 Phase 1 step 7: "...a physically defensible player remediation
## choice (e.g. a capture well with specified pumping rate)". well_axial is
## where the well is drilled; well_pumping_rate_m3_s is how hard it pumps
## (see GridModel.set_well's doc comment for exactly what this does and
## doesn't model -- a lumped mass sink, no drawdown cone/flow-field bend).
## 0.0 rate means "no well" -- GridModel.get_k's own placeholder magnitudes
## (see that file) put a single interior face's natural flow around
## 1e-3..1e-4 m3/s, so 0.01 m3/s is a well pumping noticeably harder than the
## ambient flow -- enough to visibly intercept a plume without needing an
## unrealistic number.
##
## Same live-tuning setter pattern as the geology exports above (and for the
## identical reason -- an Inspector edit made while playing must actually
## reach the running GridModel on the very next frame).
@export var well_axial: Vector2i = Vector2i(0, 3):
	set(value):
		well_axial = value
		_refresh_well()
@export_range(0.0, 0.05, 0.001) var well_pumping_rate_m3_s: float = 0.01:
	set(value):
		well_pumping_rate_m3_s = value
		_refresh_well()

## Brief SS8 Phase 1 step 8: "a receptor target, win/loss rules". receptor_axial
## is a fixed grass-tile cell near the south edge of the map (the catchment's
## downstream end, same general direction the land slope/head gradient/river
## already point) -- a lake the player is trying to protect. Its location is
## plain data (GridModel.get_concentration_kg_m3 already answers "how
## contaminated is this cell"); no new GridModel sink/source is needed, unlike
## the well -- the receptor doesn't remove or add mass, it's just the cell
## _check_win_loss watches.
##
## receptor_contamination_threshold_kg_m3 is a DIFFERENT number from
## contamination_full_scale_kg_m3 on purpose, even though they share the same
## default -- full_scale is a display-only "what reads as 100% on the overlay/
## inspector" scale (see that export's own doc comment: "not a cleanup
## standard"), while this one is the actual pass/fail regulatory-style limit
## for this one specific cell. Keeping them separate exports means tuning how
## the plume LOOKS never silently changes what counts as a loss.
@export var receptor_axial: Vector2i = Vector2i(0, 6)
@export var receptor_contamination_threshold_kg_m3: float = 0.03
## How many turns the player must survive without the receptor crossing its
## threshold to win. Pure pacing, like turn_duration_s -- tune freely.
@export var max_turns: int = 40

## The concentration that reads as "fully" contaminated (max alpha) in
## PlumeOverlay, and as 100% in the cell inspector's contamination reading
## (hex_selection.gd). Single source of truth for both, since there's no
## real receptor/regulatory threshold yet to derive this from (brief SS4/
## SS9's eventual real source) -- a placeholder scale, not a cleanup
## standard.
@export var contamination_full_scale_kg_m3: float = 0.03
@export var minimal_test_mode: bool = true # godot_hex_map_spec.md Test B: isolate anchors, no crowding/terrain noise

# Fine visual tuning -- Inspector-adjustable rather than something to keep
# recomputing/verifying in code. Standard screen convention: +Y moves the
# sprite DOWN, +X moves it RIGHT. Select "Main" in scenes/main.tscn to edit.
@export var tree_visual_nudge: Vector2 = Vector2.ZERO
@export var rock_visual_nudge: Vector2 = Vector2.ZERO
@export var decal_visual_nudge: Vector2 = Vector2.ZERO
@export var mountain_visual_nudge: Vector2 = Vector2.ZERO
@export var well_visual_nudge: Vector2 = Vector2.ZERO
@export var source_visual_nudge: Vector2 = Vector2.ZERO
@export var receptor_visual_nudge: Vector2 = Vector2.ZERO

## Per-slot chance [0, 1] of a decal appearing, rolled independently up to
## decal_cluster_max times per cell -- NOT "this cell gets exactly one
## decal or none." That independent-roll-per-slot is what produces a
## natural-looking scatter (some cells bare, some with one flower, some with
## a small cluster) from a single slider, rather than a uniform "every
## undecorated cell gets exactly one" look. Only applies to cells that
## didn't already get a major feature (tree/rock) this pass.
@export_range(0.0, 1.0) var decal_density: float = 0.35
## Max decal slots rolled per cell (see decal_density). Expected decal count
## per decorated cell is roughly decal_cluster_max * decal_density.
@export_range(1, 6) var decal_cluster_max: int = 3
## How far (px) each decal may be scattered from the cell's exact center, in
## a random direction -- keeps a cluster from stacking all its decals on
## the same point. Kept well inside HEX_SIZE (now ~61px, real art) so decals
## stay visually on their own tile.
@export_range(0.0, 40.0) var decal_scatter_radius: float = 14.0
## Same idea as decal_scatter_radius, but for the one major feature a cell
## can get (tree/rock/mountain) -- a dead-center tree on every forested cell
## reads as an artificial grid once there are enough of them. Smaller default
## than decals': these sprites are much bigger, so a little scatter goes a
## long way before it starts looking like the feature drifted off its tile.
@export_range(0.0, 40.0) var feature_scatter_radius: float = 15.0

## How "wiggly" the river looks (see _generate_river_path) -- fraction of
## radius for the wander's left-right swing, and how many full S-curves it
## completes across the map's north-south span. Inspector-tunable rather than
## hand-picked, same practice as the exports above.
@export_range(0.0, 1.0) var river_wander_amplitude: float = 0.5
@export_range(0.5, 5.0) var river_wander_frequency: float = 2.0

# Ground tile richness, same "expose it, don't hand-tune it in code" practice:
# tile_shading_strength is a soft radial vignette baked into each generated
# hex (0 = old flat fill); tile_tint_jitter is how much each cell's color
# brightness can drift (+/-) from a small deterministic set of alternates, so
# a solid-color terrain doesn't read as one stamp repeated across the map.
@export_range(0.0, 0.6) var tile_shading_strength: float = 0.25
@export_range(0.0, 0.3) var tile_tint_jitter: float = 0.08

@onready var ground: TileMapLayer = $Ground
@onready var grid_outline: Node2D = $GridOutline
@onready var features: Node2D = $Features
@onready var debug_overlay: Node2D = $DebugOverlay
@onready var plume_overlay: Node2D = $PlumeOverlay
@onready var flow_overlay: Node2D = $FlowOverlay
@onready var geology_overlay: Node2D = $GeologyOverlay
@onready var head_contour_overlay: Node2D = $HeadContourOverlay
@onready var hex_selection: Node2D = $HexSelection

const MAX_TRANSPORT_SUBSTEPS := 500 # defensive cap against a pathological flow field looping forever -- never expected to bind with today's K/head magnitudes, or with well_pumping_rate_m3_s/source_leak_rate_kg_s at their current default magnitudes

## Brief SS8 Phase 1 step 8's "win/loss rules". PLAYING is the only state
## _advance_turn() actually does anything in -- once WON or LOST, further
## Space presses/hold-repeats are harmless no-ops until Reset.
enum GameState { PLAYING, WON, LOST }

var _model: GridModel
var _river_cells: Dictionary = {} # Vector2i (axial) -> true
var _elevation_lo: float
var _elevation_hi: float
var turn: int = 0
var _turn_label: Label
var _mass_label: Label
var _status_label: Label
var _total_seeded_mass_kg: float = 0.0 # everything ever added via _seed_initial_contamination (and, later, any ongoing-release feature) -- the conservation check the mass-balance display shows against (in-domain + escaped should always equal this)
var game_state: GameState = GameState.PLAYING
var _receptor_prev_concentration_kg_m3: float = 0.0 # last turn's reading at receptor_axial, so the per-turn explanation can say "rising"/"falling", not just a bare number
var xray_mode: bool = false
var _xray_background: ColorRect
var _pre_xray_flow_visible: bool = true # plume/geology/contour have no "prior state" to remember -- they're x-ray-exclusive, always false outside it (see set_xray_mode)
var _xray_legend: Control
var _space_hold_elapsed: float = 0.0 # seconds Space has been continuously held
var _space_next_repeat_at: float = INF # _space_hold_elapsed value at which the next auto-repeat turn fires

func _ready() -> void:
	_build_tileset()
	_model = GridModel.new(radius)
	_refresh_geology_parameters() # applies the current sand/silt/clay K & porosity exports immediately, rather than duplicating the override-dict construction here too
	_refresh_well() # ditto for the capture well's location/pumping rate
	var bounds := _model.elevation_range()
	_elevation_lo = bounds.x
	_elevation_hi = bounds.y

	_river_cells.clear()
	if not minimal_test_mode:
		for axial in _generate_river_path(radius):
			_river_cells[axial] = true
	_seed_initial_contamination()

	_build_terrain()
	grid_outline.configure(ground, HexMath.cells_in_radius(radius))
	_build_features()
	debug_overlay.configure(ground, HexMath.cells_in_radius(radius))
	debug_overlay.visible = show_debug_overlay
	plume_overlay.configure(ground, _model, HexMath.cells_in_radius(radius), contamination_full_scale_kg_m3)
	plume_overlay.visible = false # x-ray only -- see set_xray_mode
	flow_overlay.configure(ground, _model, HexMath.cells_in_radius(radius))
	flow_overlay.visible = show_flow_overlay
	geology_overlay.configure(ground, _model, HexMath.cells_in_radius(radius))
	geology_overlay.visible = false # x-ray only
	head_contour_overlay.configure(ground, _model, HexMath.cells_in_radius(radius))
	head_contour_overlay.visible = false # x-ray only
	hex_selection.configure(self)
	_build_hud()
	_build_xray_legend()
	_refresh_mass_label()
	_refresh_status_label()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_advance_turn()

## Pushes the current sand/silt/clay K, porosity & diffusion exports into the
## running GridModel and forces the two overlays that depend on them to
## redraw -- called from _ready() AND from each geology export's own setter,
## so an Inspector edit made while playing takes effect on the very next
## frame, not just at the next restart (see those exports' doc comment for
## the bug this fixes). GridModel.apply_geology_parameters re-derives
## k_m_s/porosity/diffusion_m2_s per cell from each cell's EXISTING
## geology_id -- it never touches elevation/geology/head/mass_kg, so a live
## tweak doesn't reset the plume's current position or the turn in progress.
func _refresh_geology_parameters() -> void:
	if _model == null:
		return
	_model.apply_geology_parameters({
		GridModel.Geology.SAND: sand_k_m_s,
		GridModel.Geology.SILT: silt_k_m_s,
		GridModel.Geology.CLAY: clay_k_m_s,
	}, {
		GridModel.Geology.SAND: sand_porosity,
		GridModel.Geology.SILT: silt_porosity,
		GridModel.Geology.CLAY: clay_porosity,
	}, {
		GridModel.Geology.SAND: sand_diffusion_m2_s,
		GridModel.Geology.SILT: silt_diffusion_m2_s,
		GridModel.Geology.CLAY: clay_diffusion_m2_s,
	})
	if flow_overlay != null:
		flow_overlay.queue_redraw()
	if plume_overlay != null:
		plume_overlay.queue_redraw()
	if head_contour_overlay != null:
		head_contour_overlay.queue_redraw() # K changed -> the solved head field changed -- contour lines must be redrawn (geology fill doesn't: geology_id itself never changes)

## Pushes the current well_axial/well_pumping_rate_m3_s exports into the
## running GridModel, same live-tuning reason as _refresh_geology_parameters.
## Redraws every overlay that depends on the head/flow field: as of the
## SS12.6 Gate A head solver, GridModel.set_well() re-solves heads with the
## well as a real sink (see that function's doc comment), so FlowOverlay's
## arrows and the head-contour overlay's drawdown rings now genuinely bend/
## tighten toward the well too, not just PlumeOverlay's concentration cloud.
func _refresh_well() -> void:
	if _model == null:
		return
	_model.set_well(well_axial, well_pumping_rate_m3_s)
	if flow_overlay != null:
		flow_overlay.queue_redraw()
	if plume_overlay != null:
		plume_overlay.queue_redraw()
	if head_contour_overlay != null:
		head_contour_overlay.queue_redraw()

## Handles HOLDING Space (the initial press is _unhandled_input's job, above
## -- that fires once per real keydown event, which is the correct behavior
## for a single tap). Checks the physical key state directly
## (Input.is_key_pressed) rather than relying on the OS's own key-repeat
## events, which arrive at the OS's own fixed, not-game-tunable rate.
func _process(delta: float) -> void:
	if _advance_hold_timer(Input.is_key_pressed(KEY_SPACE), delta):
		_advance_turn()

## Pure repeat-timing logic, split from _process() specifically so it's
## testable headlessly: Input.is_key_pressed() reads real OS input state,
## which a test script can't drive, so `held` is passed in instead of read
## here. Returns true exactly on the frames that should fire another turn.
func _advance_hold_timer(held: bool, delta: float) -> bool:
	if not held:
		_space_hold_elapsed = 0.0
		_space_next_repeat_at = turn_hold_repeat_delay_s
		return false
	_space_hold_elapsed += delta
	if _space_hold_elapsed >= _space_next_repeat_at:
		_space_next_repeat_at += turn_hold_repeat_interval_s
		return true
	return false

## Single fixed contaminant source at scenario start -- see source_axial/
## source_mass_kg's doc comments. Skipped in minimal_test_mode, same as the
## river: that mode exists to isolate anchor placement, not to exercise the
## full simulation.
func _seed_initial_contamination() -> void:
	if minimal_test_mode:
		return
	_model.seed_mass_kg(source_axial, source_mass_kg)
	_total_seeded_mass_kg += source_mass_kg

## Advances the simulation by turn_duration_s, substepping internally so no
## single step ever exceeds GridModel's CFL stability bound (brief SS4:
## "Time step must obey stability/nonnegative-mass constraints; substep
## within a player turn if required" -- this is that substep loop). Each
## substep's dt is the smaller of what's left this turn and what's
## currently stable; if nothing is flowing anywhere, max_stable_dt_s()
## returns INF and the whole remaining duration is applied in one step.
func _advance_turn() -> void:
	if minimal_test_mode:
		return
	if game_state != GameState.PLAYING:
		return # brief SS8 step 8: once won/lost, further turns are no-ops until Reset
	var remaining := turn_duration_s
	var steps := 0
	while remaining > 1.0 and steps < MAX_TRANSPORT_SUBSTEPS:
		var stable_dt: float = _model.max_stable_dt_s()
		var dt: float = remaining if not is_finite(stable_dt) else minf(stable_dt, remaining)
		if dt <= 0.0:
			break
		if source_leak_rate_kg_s > 0.0:
			# The continuing-release source behavior (brief SS8 Phase 1 step 7):
			# released steadily over this substep's dt rather than dumped all at
			# once per turn, so it advects the same way the rest of the plume
			# does, substep by substep. Tracked in _total_seeded_mass_kg so the
			# mass-balance display's conservation check covers it too.
			var leaked_kg: float = source_leak_rate_kg_s * dt
			_model.seed_mass_kg(source_axial, leaked_kg)
			_total_seeded_mass_kg += leaked_kg
		_model.step_transport(dt)
		remaining -= dt
		steps += 1
	turn += 1
	_refresh_turn_label()
	_refresh_mass_label()
	_check_win_loss()
	_refresh_status_label()
	plume_overlay.queue_redraw()

## Replays the current scenario from turn 0 without rebuilding the map or
## discarding the player's live K/porosity tuning (brief SS8 Phase 1 step 6's
## remaining piece: "...mass-balance display and reset"). Only the mass
## balance and turn counter return to scenario start -- useful on its own,
## and essential once a remediation action exists to test (step 7), so trying
## a different choice doesn't require relaunching the whole game.
func reset_scenario() -> void:
	if minimal_test_mode:
		return
	_model.reset_mass()
	_total_seeded_mass_kg = 0.0
	_seed_initial_contamination()
	turn = 0
	game_state = GameState.PLAYING
	_receptor_prev_concentration_kg_m3 = 0.0
	_refresh_turn_label()
	_refresh_mass_label()
	_refresh_status_label()
	flow_overlay.queue_redraw()
	plume_overlay.queue_redraw()

## A minimal always-on HUD: turn counter, the one control that advances it,
## and the x-ray toggle button. A CanvasLayer child (screen-space, ignores
## World's own Node2D transform) so it stays fixed regardless of camera pan/
## zoom -- same pattern hex_selection.gd's cell-inspector panel already
## uses, pinned to the opposite corner (top-left) so the two never overlap.
func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	_turn_label = Label.new()
	_turn_label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(_turn_label)
	_refresh_turn_label()

	_mass_label = Label.new()
	_mass_label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(_mass_label)

	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(_status_label)

	var button_row := HBoxContainer.new()
	box.add_child(button_row)

	var xray_button := Button.new()
	xray_button.toggle_mode = true
	xray_button.text = "X-Ray View"
	# Buttons respond to the engine's default "ui_accept" action when
	# focused, and ui_accept is bound to both Enter AND Space -- a clicked
	# Button keeps keyboard focus afterward, so without this, pressing Space
	# for the next turn would ALSO re-press (and so re-toggle) this button,
	# silently undoing x-ray mode every turn. FOCUS_NONE means it only ever
	# responds to an actual mouse click, which is what "on a button click"
	# (the user's own words) asked for anyway.
	xray_button.focus_mode = Control.FOCUS_NONE
	xray_button.toggled.connect(set_xray_mode)
	button_row.add_child(xray_button)

	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.focus_mode = Control.FOCUS_NONE # same ui_accept/Space-retrigger hazard as xray_button above, even though this one isn't toggle_mode -- a focused Button still re-fires on every Space press otherwise
	reset_button.pressed.connect(reset_scenario)
	button_row.add_child(reset_button)

	# Backdrop for x-ray mode, brief SS6's reserved "dark aquifer blue"
	# #0D1B2A -- a CanvasLayer at layer -1 (screen-space, always drawn behind
	# the default layer-0 world content regardless of camera pan/zoom, unlike
	# a Node2D/ColorRect placed in world-space which would need to track the
	# camera's exact bounds to always cover the screen). mouse_filter=IGNORE
	# is required, not optional: a full-screen Control defaults to STOP,
	# which would silently swallow every mouse click/hover across the entire
	# viewport once visible, breaking hex_selection's hover/click and
	# camera_zoom's drag-pan.
	var xray_canvas := CanvasLayer.new()
	xray_canvas.layer = -1
	add_child(xray_canvas)
	_xray_background = ColorRect.new()
	_xray_background.color = Color("0d1b2a")
	_xray_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xray_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xray_background.visible = false
	xray_canvas.add_child(_xray_background)

## Legend for GeologyOverlay's x-ray fill (user's 2026-10-21 ask: "legend of
## the 3 types") -- top-right corner, screen-space (CanvasLayer, same pattern
## as _build_hud's top-left panel), so it never overlaps the turn/mass/status
## panel (top-left) or the cell inspector (bottom-left, hex_selection.gd).
## Reads colors/names straight from GridModel.GEOLOGY_COLOR/GEOLOGY_NAME, the
## exact same tables geology_overlay.gd's fill uses, so the legend can never
## show a color the fill doesn't actually use. Hidden by default; set_xray_mode
## shows it alongside the geology fill itself (and only if show_geology_overlay
## is enabled).
func _build_xray_legend() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	_xray_legend = panel
	panel.visible = false

	var box := VBoxContainer.new()
	panel.add_child(box)

	var title := Label.new()
	title.text = "Geology"
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	for geo in [GridModel.Geology.SAND, GridModel.Geology.SILT, GridModel.Geology.CLAY]:
		var row := HBoxContainer.new()
		box.add_child(row)

		var swatch := ColorRect.new()
		swatch.color = GridModel.GEOLOGY_COLOR[geo]
		swatch.custom_minimum_size = Vector2(14, 14)
		row.add_child(swatch)

		var label := Label.new()
		label.text = " " + GridModel.GEOLOGY_NAME[geo]
		label.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(label)

	# Anchored AFTER every child exists, not before (as _build_hud's top-left
	# panel does) -- PRESET_MODE_KEEP_SIZE computes its offsets from the
	# panel's size AT THE MOMENT this is called. For a RIGHT-anchored preset
	# (anchor point on the far edge, offsets growing leftward/upward from an
	# empty-size panel) that produced a zero-width/zero-height rect pinned to
	# a single point -- invisible despite `visible = true`, the actual cause
	# of the reported "no legend" bug. _build_hud's top-LEFT panel never hit
	# this: its anchor point doesn't depend on the panel's own size at all
	# (offsets measured from the corner outward), so computing it early
	# happened to work there by coincidence, not because the ordering was
	# actually safe in general.
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 12)

func _refresh_turn_label() -> void:
	if _turn_label == null:
		return
	_turn_label.text = "Turn: %d\n(Space: next turn)" % turn

## Brief SS8 Phase 1 step 6: "mass-balance display" -- the brief's own SS9
## conservation guardrail, made visible to the player instead of only proven
## in tests. "In domain" + "Escaped" + "Captured" should always sum to
## "Seeded total" (within float tolerance) -- the same invariant
## _test_grid_model_south_boundary_outflow/_test_grid_model_well_capture
## check numerically, now readable during play.
func _refresh_mass_label() -> void:
	if _mass_label == null or _model == null:
		return
	_mass_label.text = "In domain: %.1f kg\nEscaped: %.1f kg\nCaptured: %.1f kg\nSeeded total: %.1f kg" % [
		_model.total_mass_kg(), _model.escaped_mass_kg, _model.captured_mass_kg, _total_seeded_mass_kg]

## Brief SS8 Phase 1 step 8: "win/loss rules". LOSS takes priority over WIN if
## both would somehow trigger on the same turn (crossing the threshold on
## exactly the final allowed turn should read as a loss, not a last-second
## win) -- checked in that order below. Only evaluated while still PLAYING: a
## WON/LOST game doesn't flip states again just because the receptor's
## concentration keeps drifting after the fact (e.g. the plume still slowly
## draining toward it post-loss).
func _check_win_loss() -> void:
	if game_state != GameState.PLAYING:
		return
	var receptor_conc := _model.get_concentration_kg_m3(receptor_axial)
	if receptor_conc >= receptor_contamination_threshold_kg_m3:
		game_state = GameState.LOST
	elif turn >= max_turns:
		game_state = GameState.WON

## Brief SS8 Phase 1 step 8: "a short on-screen explanation of each turn" --
## the receptor's own reading (as a percentage of its loss threshold, same
## "% of a scale" convention the cell inspector already uses), which way it's
## trending since last turn, and progress toward the turn budget, so the
## player always has a plain-language read on how the scenario is going
## without needing to interpret the mass-balance numbers or the plume cloud
## themselves. Once the game has ended, this becomes the win/loss banner
## instead.
func _refresh_status_label() -> void:
	if _status_label == null or _model == null:
		return
	if game_state == GameState.WON:
		_status_label.text = "SAFE: the lake stayed below its contamination limit for %d turns." % max_turns
		return
	if game_state == GameState.LOST:
		_status_label.text = "FAILED: the lake crossed its contamination limit on turn %d." % turn
		return
	var receptor_conc: float = _model.get_concentration_kg_m3(receptor_axial)
	var percent_of_limit := 0.0
	if receptor_contamination_threshold_kg_m3 > 0.0:
		percent_of_limit = receptor_conc / receptor_contamination_threshold_kg_m3 * 100.0
	var trend := "steady"
	if receptor_conc > _receptor_prev_concentration_kg_m3 + 1.0e-12:
		trend = "rising"
	elif receptor_conc < _receptor_prev_concentration_kg_m3 - 1.0e-12:
		trend = "falling"
	_status_label.text = "Lake contamination: %.1f%% of limit (%s)\nTurn %d of %d" % [percent_of_limit, trend, turn, max_turns]
	_receptor_prev_concentration_kg_m3 = receptor_conc

## The user's ask: terrain art was obscuring the plume cloud. Hides Ground
## (surface terrain tiles) and Features (trees/rocks/decals) entirely rather
## than just dimming them -- those two are exactly what obscures the cloud,
## and a translucent cloud glow still competes visually with anything drawn
## under it. GridOutline is left alone (its grid lines read its own data
## straight from Ground, independent of Ground's own `visible` flag, and
## thin grey lines don't meaningfully compete with the cloud) so there's
## still a spatial reference grid to read coordinates against.
##
## Four subsurface overlays are x-ray-gated, but in two different ways:
## - FlowOverlay is forced visible while x-ray is active, remembering
##   whatever it was set to beforehand (Inspector default, or a previous
##   F-key toggle) and restoring that exact state on exit -- it's also a
##   normal surface toggle outside x-ray.
## - PlumeOverlay, GeologyOverlay and HeadContourOverlay (the user's
##   2026-10-21 ask) have NO surface existence at all: they are shown only
##   while x-ray is active (gated by their own show_*_overlay export) and
##   unconditionally hidden the instant x-ray ends -- there is no "prior
##   state" to restore for a layer that's never visible outside x-ray.
func set_xray_mode(enabled: bool) -> void:
	if enabled == xray_mode:
		return
	xray_mode = enabled
	ground.visible = not enabled
	features.visible = not enabled
	if _xray_background != null:
		_xray_background.visible = enabled
	if _xray_legend != null:
		_xray_legend.visible = enabled and show_geology_overlay
	if enabled:
		_pre_xray_flow_visible = flow_overlay.visible
		flow_overlay.visible = true
	else:
		flow_overlay.visible = _pre_xray_flow_visible
	if plume_overlay != null:
		plume_overlay.visible = enabled and show_plume_overlay
	if geology_overlay != null:
		geology_overlay.visible = enabled and show_geology_overlay
	if head_contour_overlay != null:
		head_contour_overlay.visible = enabled and show_head_contour_overlay

func _build_tileset() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
	tile_set.tile_size = TILE_SIZE

	_add_source(tile_set, TERRAIN_GRASS, GRASS_COLOR)
	_add_source(tile_set, TERRAIN_SAND, SAND_COLOR)
	_add_source(tile_set, TERRAIN_WATER, WATER_COLOR)
	_add_source(tile_set, TERRAIN_SNOW, SNOW_COLOR)
	_add_source(tile_set, TERRAIN_ROCKY, ROCKY_COLOR)

	ground.tile_set = tile_set

## Dispatches to real art (GROUND_TEXTURES) when this terrain has any,
## otherwise the generated fallback -- so swapping in real art for one
## terrain at a time never touches the others.
func _add_source(tile_set: TileSet, source_id: int, fallback_color: Color) -> void:
	var art: Array = GROUND_TEXTURES.get(source_id, [])
	if art.is_empty():
		_add_generated_source(tile_set, source_id, fallback_color)
	else:
		_add_real_art_source(tile_set, source_id, art)

## Creates one shared texture (so it stays one real hex, not per-cell art)
## plus TINT_VARIANT_COUNT alternative tiles that only differ by a modulate
## brightness jitter -- picked deterministically per cell in _build_terrain
## so neighboring same-terrain cells don't look like one stamp repeated.
func _add_generated_source(tile_set: TileSet, source_id: int, fill_color: Color) -> void:
	var texture := HexTileTexture.generate(HEX_SIZE, TEXTURE_CANVAS_SIZE, fill_color, BORDER_COLOR, BORDER_WIDTH, tile_shading_strength)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = TEXTURE_CANVAS_SIZE
	source.create_tile(Vector2i(0, 0))
	for variant in range(1, TINT_VARIANT_COUNT):
		source.create_alternative_tile(Vector2i(0, 0), variant)
		var jitter: float = lerpf(-tile_tint_jitter, tile_tint_jitter, float(variant) / float(TINT_VARIANT_COUNT - 1))
		source.get_tile_data(Vector2i(0, 0), variant).modulate = Color(1.0 + jitter, 1.0 + jitter, 1.0 + jitter)
	tile_set.add_source(source, source_id)

## Real art source: one atlas column per hand-cut variant (textures, laid out
## side by side on a combined texture -- TileSetAtlasSource needs one texture
## per source, atlas coordinates index into it), each with its own
## TINT_VARIANT_COUNT modulate-jitter alternative tiles, same as the
## generated fallback. _build_terrain picks both independently, so a 2-variant
## terrain effectively gets 2 x TINT_VARIANT_COUNT distinct looks from one
## density slider's worth of hashing, no extra export needed.
func _add_real_art_source(tile_set: TileSet, source_id: int, textures: Array) -> void:
	var count := textures.size()
	var combined := Image.create(TILE_SIZE.x * count, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	combined.fill(Color(0, 0, 0, 0))
	for i in range(count):
		var tex: Texture2D = textures[i]
		var img := tex.get_image()
		if img.get_format() != Image.FORMAT_RGBA8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		combined.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height())), Vector2i(i * TILE_SIZE.x, 0))

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(combined)
	source.texture_region_size = TILE_SIZE
	for i in range(count):
		var coord := Vector2i(i, 0)
		source.create_tile(coord)
		for variant in range(1, TINT_VARIANT_COUNT):
			source.create_alternative_tile(coord, variant)
			var jitter: float = lerpf(-tile_tint_jitter, tile_tint_jitter, float(variant) / float(TINT_VARIANT_COUNT - 1))
			source.get_tile_data(coord, variant).modulate = Color(1.0 + jitter, 1.0 + jitter, 1.0 + jitter)
	tile_set.add_source(source, source_id)

## Single hex-wide, deterministic winding path from north to south edge
## (where the flagship receptor sits) -- a crude placeholder for a real
## stream, not derived from flow accumulation or a DEM (see docs/DECISIONS.md).
##
## Built as an actual walk, every step a genuine hex-neighbor move, so
## consecutive cells are always adjacent (no gaps) -- but NOT "one cell per
## row" any more. That constraint was the reason an earlier version read as
## almost straight: axial hex neighbors only ever allow moving r+1 via q
## unchanged (straight south) or q-1 (diagonal southwest) -- there is no
## single hex step that increases both q and r by 1 ("southeast"). A strict
## one-step-per-row walk can therefore only ever drift left or hold, never
## swing back right, no matter how strong the wander signal is. Fixed by
## allowing an occasional SIDEWAYS step (q+1, r unchanged, neighbor offset
## (1,0)) when the target wants to move right -- a brief same-row jog, still
## single-hex-adjacent the whole way, that lets the path genuinely meander
## both directions. A row can now carry more than one river cell (a jog);
## river_wander_amplitude/river_wander_frequency control how pronounced that
## meander is. Covered by _test_world_river_path.
func _generate_river_path(p_radius: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var q := 0 # valid at r = -p_radius: q range there is [0, p_radius]
	var r := -p_radius
	path.append(Vector2i(q, r))
	var amplitude: float = river_wander_amplitude * p_radius
	var angular_step: float = TAU * river_wander_frequency / maxf(2.0 * p_radius, 1.0)
	while r < p_radius:
		var this_row_q_max: int = mini(p_radius, p_radius - r)
		var next_r := r + 1
		var next_q_min: int = maxi(-p_radius, -p_radius - next_r)
		var next_q_max: int = mini(p_radius, p_radius - next_r)
		var target_q: float = amplitude * sin((r + p_radius) * angular_step)
		var wants_right: bool = target_q > q + 0.5
		var wants_left: bool = target_q < q - 0.5
		var must_go_left: bool = q > next_q_max # straight-down would fall off the map's edge this far from the center row
		if wants_right and not must_go_left and q < this_row_q_max:
			q += 1 # sideways jog east, same row -- see header comment: the only way a single-hex-step river can bend back right
		elif (wants_left or must_go_left) and (q - 1) >= next_q_min:
			q -= 1
			r = next_r # diagonal southwest
		else:
			r = next_r # straight south
		path.append(Vector2i(q, r))
	return path

func _elevation_t(axial: Vector2i) -> float:
	if _elevation_hi <= _elevation_lo:
		return 0.5
	return (_model.get_elevation(axial) - _elevation_lo) / (_elevation_hi - _elevation_lo)

## Cheap deterministic hash -> [0, 1), reproducible per-cell "randomness"
## without an RNG/seed to manage. `salt` picks an independent stream.
static func _pseudo_random01(axial: Vector2i, salt: float) -> float:
	var h: float = sin(float(axial.x) * 12.9898 + float(axial.y) * 78.233 + salt) * 43758.5453
	return h - floor(h)

## Rocky ground (TERRAIN_ROCKY) is NOT a separate elevation band -- it's the
## exact same snow-band cells that _build_features independently decides get
## a boulder, using the identical deterministic roll (same axial, same salt
## 0.0). Computing it here means a cell's ground tile and its boulder feature
## can never drift out of sync, without the two build passes needing to share
## mutable state -- both just ask the same pure function the same question.
##
## MOUNTAIN_THRESHOLD carves out the very top slice of that same snow band for
## the larger MOUNTAINS landmark instead of a regular boulder -- unconditional
## within that slice (no DECORATION_DENSITY roll), since GridModel's slope
## (SLOPE_M_PER_ROW, land drops toward +r) already makes the highest elevation
## -- and so this threshold -- naturally rare and concentrated toward the
## north edge (r close to -radius) on its own; no extra placement logic
## needed to "put mountains in the north." Also rocky ground, same reasoning.
func _terrain_for(axial: Vector2i) -> int:
	if minimal_test_mode:
		return TERRAIN_GRASS
	if _river_cells.has(axial):
		return TERRAIN_WATER
	var t := _elevation_t(axial)
	if t < SAND_THRESHOLD:
		return TERRAIN_SAND
	if t >= SNOW_THRESHOLD:
		if t >= MOUNTAIN_THRESHOLD:
			return TERRAIN_ROCKY
		if _pseudo_random01(axial, 0.0) < DECORATION_DENSITY:
			return TERRAIN_ROCKY
		return TERRAIN_SNOW
	return TERRAIN_GRASS

## Deterministic, uniform-over-disk random offset (sqrt-weighted distance, so
## points don't bunch near the center) -- shared by major features and decal
## clusters alike. `salt_base` picks an independent hash stream per call site
## (angle uses salt_base, distance uses salt_base+1) so different features/
## decals on the same cell don't all scatter in lockstep.
func _scatter_offset(axial: Vector2i, salt_base: float, radius_px: float) -> Vector2:
	var angle: float = _pseudo_random01(axial, salt_base) * TAU
	var dist_t: float = _pseudo_random01(axial, salt_base + 1.0)
	return Vector2.from_angle(angle) * (radius_px * sqrt(dist_t))

func _build_terrain() -> void:
	ground.clear()
	for axial in HexMath.cells_in_radius(radius):
		var terrain := _terrain_for(axial)
		var offset := GodotHexOffset.axial_to_offset(axial)
		var art_count: int = maxi(GROUND_TEXTURES.get(terrain, []).size(), 1)
		var atlas_x := int(_pseudo_random01(axial, 61.0) * art_count) % art_count # which real-art variant (no-op when only the generated fallback exists)
		var variant := int(_pseudo_random01(axial, 29.0) * TINT_VARIANT_COUNT) % TINT_VARIANT_COUNT # modulate jitter, independent of which variant
		ground.set_cell(offset, terrain, Vector2i(atlas_x, 0), variant)

## Features are separate sprites layered on top of ground tiles; elevation
## selects which (if any) feature art a cell gets, it never moves the
## ground tile itself (godot_hex_map_spec.md's non-negotiable rule).
##
## DEPTH/OVERLAP RULE (non-negotiable, like the one above): a tall feature
## (mountain, tree) is allowed -- expected -- to visually overlap the tile(s)
## "behind" it (further up/north, drawn earlier) to read as standing above
## the ground plane, the way a sprite taller than one hex naturally would.
## This is NOT a bug to clip away. It's already guaranteed by two existing
## mechanisms, which must both stay true for any future feature/decal:
##   1. Feature sprites are never region-clipped or resized to fit inside
##      their own hex -- see _add_feature. A tall image simply extends past
##      its cell's bounds in the draw call, the same way it would on paper.
##   2. `features.y_sort_enabled` (scenes/main.tscn) sorts every feature root
##      by its ground-contact Y (cell_centre_in_features), which increases
##      monotonically with row -- so a feature further south always draws
##      in front of one further north, which is exactly "closer occludes
##      farther." Never give an individual feature sprite its own z_index
##      (per godot_hex_map_spec.md); that silently breaks this ordering.
## Covered by _test_feature_overlap_depth_rule.
func _build_features() -> void:
	features.y_sort_enabled = true # enforced here, not just in scenes/main.tscn -- see the depth/overlap rule above
	for child in features.get_children():
		child.queue_free()

	if minimal_test_mode:
		# Test B, literally: one forest (tree), one mountain (rock), on known,
		# well-separated cells -- nothing else on screen to confound the check.
		var tree_anchor := Vector2(TREES[0].get_width() / 2.0, TREES[0].get_height())
		var rock_anchor := Vector2(ROCKS[0].get_width() / 2.0, ROCKS[0].get_height() / 2.0)
		_add_feature(Vector2i(-4, 0), TREES[0], tree_anchor, tree_visual_nudge)
		_add_feature(Vector2i(4, 0), ROCKS[0], rock_anchor, rock_visual_nudge)
		return

	for axial in HexMath.cells_in_radius(radius):
		if _river_cells.has(axial):
			continue
		if axial == source_axial or axial == well_axial or axial == receptor_axial:
			continue # scenario markers only -- placed below, after this loop, never alongside an ordinary tree/rock/decal
		var terrain := _terrain_for(axial)
		var t := _elevation_t(axial)
		var placed_major_feature := false
		if t >= SNOW_THRESHOLD:
			if t >= MOUNTAIN_THRESHOLD:
				var mountain: Texture2D = MOUNTAINS[int(_pseudo_random01(axial, 7.0) * MOUNTAINS.size()) % MOUNTAINS.size()]
				var mountain_anchor := Vector2(mountain.get_width() / 2.0, mountain.get_height() / 2.0) # "sitting" object -- geometric center
				var scatter := _scatter_offset(axial, 71.0, feature_scatter_radius)
				var root := _add_feature(axial, mountain, mountain_anchor, mountain_visual_nudge, scatter)
				root.name = "Feature" # display only -- Godot uniquifies sibling names, don't match on this
				root.set_meta("kind", "feature")
				placed_major_feature = true
			elif terrain == TERRAIN_ROCKY:
				var rock: Texture2D = ROCKS[int(_pseudo_random01(axial, 7.0) * ROCKS.size()) % ROCKS.size()]
				var rock_anchor := Vector2(rock.get_width() / 2.0, rock.get_height() / 2.0) # "sitting" object -- geometric center, not bottom (same reasoning as decals)
				var scatter := _scatter_offset(axial, 73.0, feature_scatter_radius)
				var root := _add_feature(axial, rock, rock_anchor, rock_visual_nudge, scatter)
				root.name = "Feature" # display only -- Godot uniquifies sibling names, don't match on this
				root.set_meta("kind", "feature")
				placed_major_feature = true
		elif t >= FOREST_THRESHOLD:
			if _pseudo_random01(axial, 0.0) < DECORATION_DENSITY:
				var tree: Texture2D = TREES[int(_pseudo_random01(axial, 7.0) * TREES.size()) % TREES.size()]
				var anchor := Vector2(tree.get_width() / 2.0, tree.get_height())
				var scatter := _scatter_offset(axial, 75.0, feature_scatter_radius)
				var root := _add_feature(axial, tree, anchor, tree_visual_nudge, scatter)
				root.name = "Feature" # display only -- Godot uniquifies sibling names, don't match on this
				root.set_meta("kind", "feature")
				placed_major_feature = true
		if not placed_major_feature:
			_maybe_add_decal(axial, terrain)

	_add_scenario_markers()

## The fixed source, the player's one capture well (brief SS8 Phase 1 step 7),
## and the receptor target (step 8) -- placed dead-center on their cells (no
## scatter, unlike ordinary decoration), since these are precise gameplay
## locations the player needs to read accurately, not ambient dressing.
## kind="scenario", not "feature"/"decal" -- see WELL_ABSTRACTION/
## CONTAMINATION_BARREL's doc comment for why.
func _add_scenario_markers() -> void:
	var barrel_anchor := Vector2(CONTAMINATION_BARREL.get_width() / 2.0, CONTAMINATION_BARREL.get_height() / 2.0)
	var barrel_root := _add_feature(source_axial, CONTAMINATION_BARREL, barrel_anchor, source_visual_nudge)
	barrel_root.name = "ContaminationSource"
	barrel_root.set_meta("kind", "scenario")

	var well_anchor := Vector2(WELL_ABSTRACTION.get_width() / 2.0, WELL_ABSTRACTION.get_height() / 2.0)
	var well_root := _add_feature(well_axial, WELL_ABSTRACTION, well_anchor, well_visual_nudge)
	well_root.name = "CaptureWell"
	well_root.set_meta("kind", "scenario")

	var receptor_anchor := Vector2(RECEPTOR_LAKE.get_width() / 2.0, RECEPTOR_LAKE.get_height() / 2.0)
	var receptor_root := _add_feature(receptor_axial, RECEPTOR_LAKE, receptor_anchor, receptor_visual_nudge)
	receptor_root.name = "Receptor"
	receptor_root.set_meta("kind", "scenario")

## Small ground-clutter decal CLUSTER on a cell that didn't already get a
## major feature this pass, so a cell never carries both and looks
## over-dressed. Terrain-keyed (DECAL_SETS) rather than elevation-band-keyed,
## so every decal always matches what _build_terrain actually painted on
## that cell. Up to decal_cluster_max decals, each independently rolled
## (decal_density) and independently scattered (decal_scatter_radius) at its
## own random angle/distance from the cell center -- this, not a single
## "one decal or none" roll, is what gives a natural 0/1/2/3-per-cell spread
## from one slider instead of an even, one-per-tile look.
func _maybe_add_decal(axial: Vector2i, terrain: int) -> void:
	var decals: Array = DECAL_SETS.get(terrain, [])
	if decals.is_empty():
		return
	for slot in range(decal_cluster_max):
		var slot_salt: float = 100.0 * float(slot)
		if _pseudo_random01(axial, 41.0 + slot_salt) >= decal_density:
			continue
		var decal: Texture2D = decals[int(_pseudo_random01(axial, 43.0 + slot_salt) * decals.size()) % decals.size()]
		var anchor := Vector2(decal.get_width() / 2.0, decal.get_height() / 2.0)
		var scatter := _scatter_offset(axial, 47.0 + slot_salt, decal_scatter_radius)
		var root := _add_feature(axial, decal, anchor, decal_visual_nudge, scatter)
		root.name = "Decal" # display only -- Godot uniquifies sibling names, don't match on this
		root.set_meta("kind", "decal")

## Per spec: Features-local position of a cell's ground-contact point.
func cell_centre_in_features(axial: Vector2i) -> Vector2:
	var offset := GodotHexOffset.axial_to_offset(axial)
	return features.to_local(ground.to_global(ground.map_to_local(offset)))

## ground_anchor is the pixel position within the texture that touches the
## ground (per spec); centered=false + offset=-ground_anchor places exactly
## that pixel at the feature root's (the cell's) logical position. `nudge` is
## the Inspector-tunable fine adjustment (tree_visual_nudge/rock_visual_nudge)
## on top of that -- adjust those in the editor rather than asking for
## another code round-trip over a few pixels. `scatter` offsets the root
## itself away from the cell's exact center (used by decal clusters); it
## still keeps the root meaningfully "on" this cell for Y-sort purposes,
## just not dead-center. Stores the owning axial as metadata so tests (and
## any future per-cell lookup) don't need to reverse-map pixel position.
func _add_feature(axial: Vector2i, texture: Texture2D, ground_anchor: Vector2, nudge: Vector2 = Vector2.ZERO, scatter: Vector2 = Vector2.ZERO) -> Node2D:
	var root := Node2D.new()
	root.position = cell_centre_in_features(axial) + scatter
	root.set_meta("axial", axial)
	features.add_child(root)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = -ground_anchor + nudge
	root.add_child(sprite)
	return root

## Returns axial (q, r), not Godot's raw offset coordinate.
func cell_under_mouse() -> Vector2i:
	var offset := ground.local_to_map(ground.to_local(get_global_mouse_position()))
	return GodotHexOffset.offset_to_axial(offset)

## Single source of truth for "what's at this cell" -- any UI that wants to
## show cell data (CellInspector) reads this instead of reaching into
## _model's dictionaries or re-deriving _terrain_for itself, so the
## inspector can never drift out of sync with what's actually rendered there.
func cell_info(axial: Vector2i) -> Dictionary:
	var terrain := _terrain_for(axial)
	var geo: int = _model.get_geology(axial)
	var concentration: float = _model.get_concentration_kg_m3(axial)
	var contamination_percent := 0.0
	if contamination_full_scale_kg_m3 > 0.0:
		contamination_percent = (concentration / contamination_full_scale_kg_m3) * 100.0
	return {
		"axial": axial,
		"terrain": terrain,
		"terrain_name": TERRAIN_NAMES.get(terrain, "?"),
		"elevation_m": _model.get_elevation(axial),
		"geology_id": geo,
		"geology_name": GridModel.GEOLOGY_NAME.get(geo, "?"),
		"k_m_s": _model.get_k(axial),
		"porosity": _model.get_porosity(axial),
		"diffusion_m2_s": _model.get_diffusion_m2_s(axial),
		"head_m": _model.get_head(axial),
		"concentration_kg_m3": concentration,
		"contamination_percent": contamination_percent,
	}
