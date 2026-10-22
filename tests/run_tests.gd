extends SceneTree

## Deterministic, headless tests for hex coordinate math and grid data. Run with:
##   Godot --headless --script res://tests/run_tests.gd

const HexMath = preload("res://scripts/rendering/hex_math.gd")
const GridModel = preload("res://scripts/simulation/grid_model.gd")
const World = preload("res://scripts/rendering/world.gd")
const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const GridOutline = preload("res://scripts/rendering/grid_outline.gd")
const HexSelection = preload("res://scripts/rendering/hex_selection.gd")
const HexTileTexture = preload("res://scripts/rendering/hex_tile_texture.gd")
const FlowOverlay = preload("res://scripts/rendering/flow_overlay.gd")
const PlumeOverlay = preload("res://scripts/rendering/plume_overlay.gd")
const GeologyOverlay = preload("res://scripts/rendering/geology_overlay.gd")
const HeadContourOverlay = preload("res://scripts/rendering/head_contour_overlay.gd")

func _init() -> void:
	var failures := 0
	failures += _test_origin()
	failures += _test_round_trip()
	failures += _test_neighbors()
	failures += _test_cells_in_radius_count()
	failures += _test_elevation_deterministic()
	failures += _test_elevation_bounded()
	failures += _test_elevation_neighbors_smooth()
	failures += _test_grid_model_cell_data_fields()
	failures += _test_grid_model_geology_overrides()
	failures += _test_grid_model_apply_geology_parameters_live()
	failures += _test_grid_model_head_gradient_uniform_k_benchmark()
	failures += _test_grid_model_heterogeneous_k_head_solve_conserves_water()
	failures += _test_grid_model_face_flux()
	failures += _test_grid_model_concentration()
	failures += _test_grid_model_transport_conservation()
	failures += _test_grid_model_zero_gradient_no_transport()
	failures += _test_grid_model_pure_diffusion_spreads_at_zero_velocity()
	failures += _test_grid_model_diffusion_included_in_cfl_bound()
	failures += _test_grid_model_transport_direction()
	failures += _test_grid_model_south_boundary_outflow()
	failures += _test_grid_model_reset_mass()
	failures += _test_grid_model_well_capture()
	failures += _test_grid_model_well_changes_flow_field()
	failures += _test_world_cell_info()
	failures += _test_hex_selection_format_cell_info()
	failures += _test_flow_overlay_vector()
	failures += _test_plume_overlay_fraction()
	failures += _test_plume_overlay_clip()
	failures += _test_plume_overlay_triangle_key_order_independent()
	failures += _test_plume_overlay_union_polygons()
	failures += _test_plume_overlay_chaikin_smooth()
	failures += _test_plume_overlay_edge_key_order_independent()
	failures += _test_plume_overlay_build_adjacency()
	failures += _test_plume_overlay_dedupe_points()
	failures += _test_plume_overlay_triangulates()
	failures += _test_world_turn_advance_transport()
	failures += _test_world_xray_mode()
	failures += _test_world_hold_to_repeat_timer()
	failures += _test_world_geology_setter_refreshes_live_model()
	failures += _test_world_diffusion_setter_refreshes_live_model()
	failures += _test_world_well_setter_refreshes_live_model()
	failures += _test_world_continuing_source_leak()
	failures += _test_world_reset_scenario()
	failures += _test_godot_hex_offset_round_trip()
	failures += _test_tileset_matches_axial_spacing()
	failures += _test_tilemap_hit_testing_round_trip()
	failures += _test_generated_hex_texture()
	failures += _test_generated_hex_shading_and_tint_variants()
	failures += _test_real_ground_art_variants()
	failures += _test_world_river_path()
	failures += _test_world_terrain_assignment()
	failures += _test_world_feature_centre_matches_ground()
	failures += _test_world_minimal_test_mode()
	failures += _test_hex_selection_matches_grid_outline()
	failures += _test_feature_overlap_depth_rule()
	failures += _test_rocky_terrain_boulder_coupling()
	failures += _test_mountains_concentrate_north()
	failures += _test_major_feature_scatter()
	failures += _test_grid_outline_shore_edges()
	failures += _test_world_decals()
	failures += _test_decal_clustering_and_scatter()
	failures += _test_world_scenario_markers_placed()
	failures += _test_world_receptor_marker_placed()
	failures += _test_world_win_condition()
	failures += _test_world_loss_condition()
	failures += _test_world_status_label_text()
	failures += _test_geology_overlay_colors_cover_all_geologies()
	failures += _test_head_contour_overlay_triangle_offsets_are_mutually_adjacent()
	failures += _test_head_contour_overlay_triangle_crossing()
	failures += _test_head_contour_overlay_nice_interval()
	failures += _test_head_contour_overlay_drawdown()
	failures += _test_head_contour_overlay_label_spacing()

	if failures == 0:
		print("HEX MATH TESTS: ALL PASSED")
	else:
		print("HEX MATH TESTS: %d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)

func _check(condition: bool, label: String) -> int:
	if condition:
		print("  PASS: %s" % label)
		return 0
	print("  FAIL: %s" % label)
	return 1

func _test_origin() -> int:
	return _check(HexMath.axial_to_pixel(Vector2i(0, 0), 32.0) == Vector2.ZERO,
		"origin maps to pixel (0,0)")

func _test_round_trip() -> int:
	var f := 0
	var samples: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(3, -2), Vector2i(-4, 1), Vector2i(5, 5), Vector2i(-8, 8),
	]
	for axial in samples:
		var pixel := HexMath.axial_to_pixel(axial, 32.0)
		var back := HexMath.pixel_to_axial(pixel, 32.0)
		f += _check(back == axial, "round-trip %s -> pixel -> %s" % [axial, back])
	return f

func _test_neighbors() -> int:
	var f := 0
	var origin := Vector2i(2, -1)
	var n := HexMath.neighbors(origin)
	f += _check(n.size() == 6, "a cell has 6 neighbors")
	var all_distance_one := true
	for neighbor in n:
		if HexMath.axial_distance(origin, neighbor) != 1:
			all_distance_one = false
	f += _check(all_distance_one, "every neighbor is exactly 1 hex-step away")
	return f

func _test_cells_in_radius_count() -> int:
	var cells := HexMath.cells_in_radius(8)
	var expected := 3 * 8 * 8 + 3 * 8 + 1 # hex map of radius N has 3N^2+3N+1 cells
	return _check(cells.size() == expected,
		"radius-8 hex map has %d cells (3N^2+3N+1)" % expected)

func _test_elevation_deterministic() -> int:
	var a := GridModel.new(8)
	var b := GridModel.new(8)
	var identical := true
	for axial in a.top_elevation_m.keys():
		if a.get_elevation(axial) != b.get_elevation(axial):
			identical = false
	return _check(identical, "elevation generation is deterministic across separate GridModel instances")

func _test_elevation_bounded() -> int:
	var f := 0
	var model := GridModel.new(8)
	var bounds := model.elevation_range()
	var lo: float = bounds.x
	var hi: float = bounds.y

	var max_slope_term: float = GridModel.SLOPE_M_PER_ROW * 8.0
	var max_ripple_term: float = 2.0 * GridModel.UNDULATION_M
	var envelope_lo: float = GridModel.BASE_ELEVATION_M - max_slope_term - max_ripple_term
	var envelope_hi: float = GridModel.BASE_ELEVATION_M + max_slope_term + max_ripple_term

	f += _check(lo >= envelope_lo - 0.001 and hi <= envelope_hi + 0.001,
		"elevation stays within the theoretical slope+ripple envelope [%.1f, %.1f]" % [envelope_lo, envelope_hi])
	f += _check(hi > lo, "elevation actually varies across the map, not flat")
	f += _check(is_finite(lo) and is_finite(hi), "elevation values are finite (no NaN/Inf)")
	return f

func _test_elevation_neighbors_smooth() -> int:
	var f := 0
	var model := GridModel.new(8)
	# Lipschitz-style bound: one hex-step changes the slope term by at most
	# SLOPE_M_PER_ROW, and each ripple term's rate of change is bounded by
	# its own amplitude x frequency; generous margin keeps this a smoke test,
	# not a precise derivative proof.
	var max_step_delta: float = GridModel.SLOPE_M_PER_ROW + 2.0 * GridModel.UNDULATION_M
	var samples: Array[Vector2i] = [Vector2i(0, 0), Vector2i(4, -3), Vector2i(-5, 2)]
	var all_smooth := true
	for axial in samples:
		for neighbor in HexMath.neighbors(axial):
			if model.top_elevation_m.has(neighbor):
				var delta: float = abs(model.get_elevation(axial) - model.get_elevation(neighbor))
				if delta > max_step_delta:
					all_smooth = false
	f += _check(all_smooth, "neighboring cells never differ in elevation by more than %.1fm" % max_step_delta)
	return f

## Phase 1 step 1 (PLUME_PROJECT_BRIEF.md SS4/SS8): geology_id/k_m_s/porosity
## must be deterministic (same reasoning as elevation), must actually look up
## to their geology's table values (not drift independently), and must be
## genuinely heterogeneous across a real-size map -- a map that's secretly
## all-sand would silently defeat the whole point of this step.
func _test_grid_model_cell_data_fields() -> int:
	var f := 0
	var a := GridModel.new(8)
	var b := GridModel.new(8)

	var identical := true
	var consistent_with_table := true
	var geologies_seen := {}
	for axial in a.top_elevation_m.keys():
		if a.get_geology(axial) != b.get_geology(axial) or a.get_k(axial) != b.get_k(axial) or a.get_porosity(axial) != b.get_porosity(axial):
			identical = false
		var geo: int = a.get_geology(axial)
		geologies_seen[geo] = true
		if a.get_k(axial) != GridModel.DEFAULT_GEOLOGY_K_M_S[geo] or a.get_porosity(axial) != GridModel.DEFAULT_GEOLOGY_POROSITY[geo]:
			consistent_with_table = false
	f += _check(identical, "geology/K/porosity generation is deterministic across separate GridModel instances")
	f += _check(consistent_with_table, "with no overrides, every cell's K/porosity exactly matches the default table value")
	f += _check(geologies_seen.size() >= 2, "a radius-8 map contains more than one geology unit (heterogeneous K, not secretly uniform)")
	return f

## User's ask: adjustable transport model parameters, so the severity of
## "contamination gets stuck in clay" can be tuned without a code change.
## Confirms _init's k_overrides/porosity_overrides/diffusion_overrides
## actually take effect (one geology overridden, the others left at their
## defaults), and that a geology with NO override still falls back to the
## default rather than silently becoming 0/missing.
func _test_grid_model_geology_overrides() -> int:
	var f := 0
	var model := GridModel.new(8, {GridModel.Geology.CLAY: 1.0e-5}, {GridModel.Geology.CLAY: 0.4}, {GridModel.Geology.CLAY: 2.0e-9})

	f += _check(model.geology_k_m_s[GridModel.Geology.CLAY] == 1.0e-5, "an overridden geology's K takes effect")
	f += _check(model.geology_porosity[GridModel.Geology.CLAY] == 0.4, "an overridden geology's porosity takes effect")
	f += _check(model.geology_diffusion_m2_s[GridModel.Geology.CLAY] == 2.0e-9, "an overridden geology's diffusion coefficient takes effect")
	f += _check(model.geology_k_m_s[GridModel.Geology.SAND] == GridModel.DEFAULT_GEOLOGY_K_M_S[GridModel.Geology.SAND],
		"a geology with no override keeps its default K")
	f += _check(model.geology_porosity[GridModel.Geology.SAND] == GridModel.DEFAULT_GEOLOGY_POROSITY[GridModel.Geology.SAND],
		"a geology with no override keeps its default porosity")
	f += _check(model.geology_diffusion_m2_s[GridModel.Geology.SAND] == GridModel.DEFAULT_GEOLOGY_DIFFUSION_M2_S[GridModel.Geology.SAND],
		"a geology with no override keeps its default diffusion coefficient")

	var any_clay := false
	var all_clay_cells_use_override := true
	for axial: Vector2i in model.geology_id.keys():
		if model.get_geology(axial) != GridModel.Geology.CLAY:
			continue
		any_clay = true
		if model.get_k(axial) != 1.0e-5 or model.get_porosity(axial) != 0.4 or model.get_diffusion_m2_s(axial) != 2.0e-9:
			all_clay_cells_use_override = false
	f += _check(any_clay, "at least one clay cell exists on a radius-8 map, for this check to be meaningful")
	f += _check(all_clay_cells_use_override, "every clay cell's actual per-cell K/porosity/diffusion reflects the override, not the default")

	return f

## apply_geology_parameters is the "hot swap" a live Inspector tweak relies
## on (see World's geology export setters, below) -- it must re-derive K/
## porosity for every cell's EXISTING geology without resetting anything
## else (elevation, geology_id, mass_kg -- a mid-game parameter tweak must
## never silently wipe out the plume's current position or the turn in
## progress), while head_m is the ONE thing it's now EXPECTED to change: per
## brief SS12.6 Gate A, head is solved from the conductance network
## (_solve_heads()), and K is exactly what defines that network's
## conductances -- a K tweak changing the solved head field is the whole
## point of replacing the old imposed-everywhere formula, not a bug.
func _test_grid_model_apply_geology_parameters_live() -> int:
	var f := 0
	var model := GridModel.new(8)
	var clay_axial := Vector2i(0, 0) # confirmed clay at the map's exact center elsewhere in this file (_geology_at peaks there by construction)
	model.seed_mass_kg(clay_axial, 500.0)

	var elevation_before: float = model.get_elevation(clay_axial)
	var geology_before: int = model.get_geology(clay_axial)
	var mass_before: float = model.get_mass_kg(clay_axial)

	model.apply_geology_parameters({GridModel.Geology.CLAY: 1.0e-5}, {GridModel.Geology.CLAY: 0.4}, {GridModel.Geology.CLAY: 2.0e-9})

	f += _check(model.get_k(clay_axial) == 1.0e-5, "apply_geology_parameters updates K for the affected geology")
	f += _check(model.get_porosity(clay_axial) == 0.4, "apply_geology_parameters updates porosity for the affected geology")
	f += _check(model.get_diffusion_m2_s(clay_axial) == 2.0e-9, "apply_geology_parameters updates the diffusion coefficient for the affected geology")
	f += _check(model.get_elevation(clay_axial) == elevation_before, "apply_geology_parameters never touches elevation")
	f += _check(model.get_geology(clay_axial) == geology_before, "apply_geology_parameters never touches geology_id")
	f += _check(model.get_mass_kg(clay_axial) == mass_before, "apply_geology_parameters never touches mass_kg (no progress lost on a live tweak)")
	f += _check(model.last_head_solve["converged"], "apply_geology_parameters re-solves heads for the new K, and that solve converges")

	return f

## Shared by both head-solve tests below: the governing equation itself
## (brief SS12.4 test 10, "solved head field obeys water balance") --
## for every non-Dirichlet cell, net volumetric flow across its real
## interior faces, plus any fixed sinks (south-boundary outflow, the well),
## must be ~0 m3/s in steady state. Computed from first principles
## (face_flux_m_s), not from the solver's own internal state, so this is a
## genuine independent check, not just re-reading what the solver assumed.
func _max_water_balance_imbalance_m3_s(model: GridModel) -> float:
	var worst := 0.0
	for axial: Vector2i in model.top_elevation_m.keys():
		if axial.y == -model.radius:
			continue # Dirichlet boundary cell -- not subject to the balance (its head is fixed by definition, not solved)
		var net_out := 0.0
		for neighbor in HexMath.neighbors(axial):
			if model.top_elevation_m.has(neighbor):
				net_out += model.face_flux_m_s(axial, neighbor) * GridModel.FACE_AREA_M2
		for boundary_offset in GridModel._SOUTH_OUTFLOW_OFFSETS:
			if not model.top_elevation_m.has(axial + boundary_offset):
				net_out += model._south_boundary_outflow_m3_s(axial)
		if axial == model.well_axial and model.well_pumping_rate_m3_s > 0.0:
			net_out += model.well_pumping_rate_m3_s
		worst = maxf(worst, absf(net_out))
	return worst

## Brief SS12.6 Gate A, first half: "uniform-K benchmark." The textbook
## expectation -- a purely row-dependent linear head field -- turns out NOT
## to be an exact solution on THIS SPECIFIC finite hexagonal domain, even
## under uniform K: the hex's slanted east/west edges have cells missing a
## single neighbor in a direction that ISN'T one of the two designated
## north/south boundary types, so their "no-flow" treatment there doesn't
## exactly match what a pure 1D column's linear field would imply crossing
## that face -- and because the governing equation is elliptic (globally
## coupled), that geometric mismatch doesn't stay local to the edge, it
## diffuses across the whole domain (confirmed numerically: even the exact
## center cell (0,0) differs from the hand-derived formula by several
## meters). This is a real, now-understood property of modeling a bounded,
## irregularly-shaped domain with simple no-flow side edges -- not a solver
## bug, and not unique to this project (any finite-difference/finite-volume
## groundwater model has some version of this at an irregular boundary).
##
## What a uniform-K solve SHOULD still show, and what this test actually
## checks: the governing water balance holds everywhere (same check as the
## heterogeneous case below), the head field is smooth and monotonically
## decreasing north-to-south along a column (no reversals, since there's no
## heterogeneity to cause one), and -- the real point of a "uniform-K
## benchmark" -- head varies only slightly across columns (q) at a fixed
## row, in sharp contrast to the heterogeneous case, where a real clay lens
## produces a much larger q-wise spread (quantified in the test below). That
## contrast is "no preferential paths/deflection when there's nothing to
## deflect around" (brief section 4), actually demonstrated, not assumed.
func _test_grid_model_head_gradient_uniform_k_benchmark() -> int:
	var f := 0
	var uniform_k := 3.0e-4
	var model := GridModel.new(8, {
		GridModel.Geology.SAND: uniform_k, GridModel.Geology.SILT: uniform_k, GridModel.Geology.CLAY: uniform_k,
	})

	f += _check(model.last_head_solve["converged"], "the uniform-K solve converges within its iteration budget")
	f += _check(_max_water_balance_imbalance_m3_s(model) < 1.0e-6,
		"every non-Dirichlet cell's net volumetric flow is ~0 m3/s under uniform K too")

	var monotonic := true
	for r in range(-8, 8):
		if model.get_head(Vector2i(0, r)) <= model.get_head(Vector2i(0, r + 1)):
			monotonic = false
	f += _check(monotonic, "under uniform K, head strictly decreases every single row heading south along a column, no reversals")

	var lo := INF
	var hi := -INF
	for q in range(-3, 4):
		var h: float = model.get_head(Vector2i(q, 2))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	f += _check(hi - lo < 1.0,
		"under uniform K, head varies by less than 1m across an entire row's worth of columns -- no artificial deflection with nothing to deflect around (actual spread: %.3fm)" % (hi - lo))
	return f

## Brief SS12.6 Gate A, second half: "heterogeneous-K head solver" -- the
## actual new capability. Confirms the water balance (same governing check
## as the uniform-K benchmark above -- this is the property that must hold
## regardless of K pattern), that the overall driving direction is preserved
## (north still generally higher than south), AND the signature heterogeneous
## effect the uniform-K test above explicitly contrasts against: a real clay
## lens produces a MUCH larger head spread across one row's columns than the
## uniform case did (brief section 4: "different K values create
## preferential flow and deflection"), plus a visibly steep head drop
## specifically across the low-K band along one column (the actual "a clay
## lens needs a disproportionately large driving head to push the same flow
## through it" physics -- Darcy's law applied to a real heterogeneity, not
## asserted, measured directly on the solved field).
func _test_grid_model_heterogeneous_k_head_solve_conserves_water() -> int:
	var f := 0
	var model := GridModel.new(8) # default heterogeneous sand/silt/clay geology
	f += _check(model.last_head_solve["converged"], "the heterogeneous-K solve converges within its iteration budget")
	f += _check(_max_water_balance_imbalance_m3_s(model) < 1.0e-6,
		"every non-Dirichlet cell's net volumetric flow (interior faces + south outflow + well) is ~0 m3/s -- the solved heterogeneous-K field genuinely obeys the water balance everywhere")

	var north_avg := (model.get_head(Vector2i(0, -7)) + model.get_head(Vector2i(2, -7)) + model.get_head(Vector2i(-2, -7))) / 3.0
	var south_avg := (model.get_head(Vector2i(0, 7)) + model.get_head(Vector2i(2, 7)) + model.get_head(Vector2i(-2, 7))) / 3.0
	f += _check(north_avg > south_avg,
		"heterogeneous K still trends from higher head in the north to lower head in the south overall, same driving direction as the uniform-K benchmark")

	var lo := INF
	var hi := -INF
	for q in range(-3, 4):
		var h: float = model.get_head(Vector2i(q, 2))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	f += _check(hi - lo > 2.0,
		"heterogeneous K produces a much larger head spread across one row's columns than uniform K did (<1m there) -- real K-driven deflection, not geometric noise (actual spread: %.3fm)" % (hi - lo))

	# A column that crosses the clay band (q=0, confirmed clay at the exact
	# center elsewhere in this file) should show its steepest head drop
	# WITHIN the clay rows, not spread evenly -- the disproportionate
	# driving-head requirement a real low-K confining layer imposes.
	var clay_drop: float = model.get_head(Vector2i(0, -2)) - model.get_head(Vector2i(0, 2))
	var sand_drop: float = model.get_head(Vector2i(0, -7)) - model.get_head(Vector2i(0, -4))
	f += _check(clay_drop > sand_drop,
		"crossing the clay band drops head more, over fewer rows, than an equal-length run through sand upstream of it")
	return f

## Brief SS4 MVP: "compute face fluxes from head differences and conductance"
## -- Darcy flux q = -K dh/dL. Confirms the three properties that matter for
## any future transport step to be trustworthy: antisymmetry (flux a->b is
## exactly -flux b->a, a basic conservation sanity check), correct direction
## (flow runs from higher head to lower head), and that the implementation
## matches the harmonic-mean-K formula the brief specifies, not some other
## averaging that would silently misrepresent a low-K lens's effect.
func _test_grid_model_face_flux() -> int:
	var f := 0
	var model := GridModel.new(8)

	var a := Vector2i(0, 0)
	var b := Vector2i(0, 1) # straight south neighbor -- head(a) > head(b) by construction
	var flux_ab := model.face_flux_m_s(a, b)
	var flux_ba := model.face_flux_m_s(b, a)
	f += _check(is_equal_approx(flux_ab, -flux_ba), "face flux is antisymmetric: flux(a,b) == -flux(b,a)")
	f += _check(flux_ab > 0.0, "flux runs from the higher-head cell to the lower-head cell")

	var k_a := model.get_k(a)
	var k_b := model.get_k(b)
	var expected_k_h: float = 2.0 * k_a * k_b / (k_a + k_b) if (k_a + k_b) > 0.0 else 0.0
	var expected_flux: float = expected_k_h * (model.get_head(a) - model.get_head(b)) / GridModel.CELL_SPACING_M
	f += _check(is_equal_approx(flux_ab, expected_flux),
		"face flux matches harmonic-mean-K * head-difference / cell spacing")

	var expected_velocity: float = expected_flux / ((model.get_porosity(a) + model.get_porosity(b)) / 2.0)
	f += _check(is_equal_approx(model.pore_velocity_m_s(a, b), expected_velocity),
		"pore velocity matches flux / average effective porosity (v = q / n_e)")

	var fluxes := model.neighbor_fluxes_m_s(a)
	f += _check(fluxes.size() == 6, "an interior cell's neighbor_fluxes_m_s covers all 6 neighbors")
	var all_match := true
	for neighbor in fluxes.keys():
		if not is_equal_approx(fluxes[neighbor], model.face_flux_m_s(a, neighbor)):
			all_match = false
	f += _check(all_match, "neighbor_fluxes_m_s entries match face_flux_m_s for each neighbor")
	return f

## Concentration is just mass / pore volume -- confirms the plumbing (seeding
## adds rather than overwrites, zero-mass cells read as zero concentration,
## pore volume is strictly positive given the current geology table so this
## never silently divides by zero).
func _test_grid_model_concentration() -> int:
	var f := 0
	var model := GridModel.new(8)
	var axial := Vector2i(0, 0)

	f += _check(model.get_mass_kg(axial) == 0.0 and model.get_concentration_kg_m3(axial) == 0.0,
		"an unseeded cell has zero mass and zero concentration")

	model.seed_mass_kg(axial, 10.0)
	model.seed_mass_kg(axial, 5.0)
	f += _check(model.get_mass_kg(axial) == 15.0, "seed_mass_kg adds to existing mass rather than overwriting it")

	var expected_volume: float = GridModel.CELL_AREA_M2 * GridModel.CELL_THICKNESS_M * model.get_porosity(axial)
	f += _check(is_equal_approx(model.pore_volume_m3(axial), expected_volume),
		"pore volume matches cell area x thickness x porosity")
	f += _check(is_equal_approx(model.get_concentration_kg_m3(axial), 15.0 / expected_volume),
		"concentration matches mass / pore volume")
	return f

## Brief SS9's non-negotiable guardrail: "mass conservation" -- no contaminant
## may appear or vanish during transport. Confirms total_mass_kg() is exactly
## preserved (within float tolerance) across repeated step_transport() calls,
## using a dt safely under max_stable_dt_s() so the explicit scheme stays
## physical (no cell driven negative, which would itself be a conservation
## violation of a different kind).
func _test_grid_model_transport_conservation() -> int:
	var f := 0
	var model := GridModel.new(8)
	model.seed_mass_kg(Vector2i(0, 0), 1000.0)
	var initial_total := model.total_mass_kg()

	var stable_dt: float = model.max_stable_dt_s()
	f += _check(is_finite(stable_dt) and stable_dt > 0.0, "max_stable_dt_s() returns a finite, positive bound")
	var dt: float = stable_dt * 0.5 # safety margin under the CFL bound

	var all_conserved := true
	var all_nonnegative := true
	for i in range(10):
		model.step_transport(dt)
		if not is_equal_approx(model.total_mass_kg(), initial_total):
			all_conserved = false
		for axial: Vector2i in model.mass_kg.keys():
			if model.get_mass_kg(axial) < -0.0001:
				all_nonnegative = false
	f += _check(all_conserved, "total mass is exactly conserved across 10 transport steps")
	f += _check(all_nonnegative, "no cell's mass goes negative when stepping within max_stable_dt_s()")
	# Not exactly 0.0: an explicit upwind scheme has no literal propagation
	# speed limit -- any nonzero flux at all touches a neighbor with a
	# formally-nonzero (if astronomically tiny) mass, so after 10 steps even
	# a cell 8 hex-steps away (the nearest real boundary cell to the map's
	# own center) has picked up a non-zero trace, and so has "escaped" an
	# equally negligible trace. Confirms that trace stays physically
	# meaningless (<< a billionth of the seeded mass), not that it's
	# literally zero.
	f += _check(model.escaped_mass_kg < 1.0e-6,
		"a source seeded deep in the interior (0,0) has no physically meaningful escape after 10 small steps")
	return f

## Brief SS12.4 test 1: "No-flow/no-gradient: no advective transport;
## diffusion only if concentration gradients exist." With every cell's head
## forced equal (overridden directly, bypassing the flow solver -- this test
## is about TRANSPORT given a head field, not about whether the solver can
## itself produce a flat one), every face flux is exactly zero. Diffusion is
## ALSO zeroed here (every geology's diffusion coefficient overridden to
## 0.0) specifically to isolate the ADVECTIVE claim this test makes -- the
## complementary half, "diffusion alone genuinely moves mass at zero
## velocity," is _test_grid_model_pure_diffusion_spreads_at_zero_velocity
## below, exactly brief SS12.4 test 5.
func _test_grid_model_zero_gradient_no_transport() -> int:
	var f := 0
	var no_diffusion := {GridModel.Geology.SAND: 0.0, GridModel.Geology.SILT: 0.0, GridModel.Geology.CLAY: 0.0}
	var model := GridModel.new(8, {}, {}, no_diffusion)
	for axial: Vector2i in model.head_m.keys():
		model.head_m[axial] = 50.0 # flat head everywhere -- zero gradient, zero face flux

	var source := Vector2i(0, 0) # well clear of the south open boundary
	model.seed_mass_kg(source, 1000.0)
	var mass_before := model.mass_kg.duplicate()

	var flux_is_zero := true
	for neighbor in HexMath.neighbors(source):
		if model.top_elevation_m.has(neighbor) and not is_zero_approx(model.face_flux_m_s(source, neighbor)):
			flux_is_zero = false
	f += _check(flux_is_zero, "a flat head field produces exactly zero face flux at the source cell")

	model.step_transport(1.0e7) # an arbitrarily large dt -- with zero flux and zero diffusion everywhere nearby, nothing should move regardless of step size
	var all_unchanged := true
	for axial: Vector2i in mass_before.keys():
		if model.get_mass_kg(axial) != mass_before[axial]:
			all_unchanged = false
	f += _check(all_unchanged, "with zero head gradient AND zero diffusion, mass_kg is bit-for-bit unchanged after a transport step -- no advective transport at all, not just a small amount")
	return f

## Brief SS12.4 test 5: "Pure diffusion: plume spreads at zero groundwater
## velocity." Same flat-head (zero advection) setup as the test above, but
## WITHOUT zeroing diffusion this time -- a source cell's mass must still
## spread into its neighbors via Fick's law alone, with zero water movement
## anywhere, which is exactly what distinguishes diffusion from advection
## (brief SS12.2: "Effective pore-water diffusion, including at zero flow").
func _test_grid_model_pure_diffusion_spreads_at_zero_velocity() -> int:
	var f := 0
	var model := GridModel.new(8) # default (nonzero) diffusion coefficients
	for axial: Vector2i in model.head_m.keys():
		model.head_m[axial] = 50.0 # flat head everywhere -- zero gradient, zero face flux, zero advection

	var source := Vector2i(0, 0)
	var downstream := Vector2i(0, 1) # "downstream" is meaningless with zero flow -- just an arbitrary neighbor
	model.seed_mass_kg(source, 1000.0)
	var initial_total := model.total_mass_kg()

	var flux_is_zero := true
	for neighbor in HexMath.neighbors(source):
		if model.top_elevation_m.has(neighbor) and not is_zero_approx(model.face_flux_m_s(source, neighbor)):
			flux_is_zero = false
	f += _check(flux_is_zero, "sanity check: the flat head field still produces exactly zero face flux (this is a PURE diffusion test)")

	var dt: float = model.max_stable_dt_s() * 0.5
	f += _check(dt > 0.0 and is_finite(dt), "max_stable_dt_s() stays finite and positive from diffusive conductance alone, with zero advective flow anywhere")
	model.step_transport(dt)

	f += _check(model.get_mass_kg(source) < 1000.0, "the seeded cell loses mass to diffusion even though there is zero groundwater velocity anywhere")
	f += _check(model.get_mass_kg(downstream) > 0.0, "a neighboring cell gains mass purely by diffusion, with zero advective transport")
	f += _check(is_equal_approx(model.total_mass_kg(), initial_total), "diffusion conserves mass exactly, same as advection")
	return f

## Diffusive conductance must be included in the CFL stability bound exactly
## like advective flow and the well already are (max_stable_dt_s's own doc
## comment) -- confirms a model with a MUCH larger diffusion coefficient has
## a smaller stable dt than an otherwise-identical baseline, same pattern
## _test_grid_model_well_capture already uses for the well's pumping rate.
func _test_grid_model_diffusion_included_in_cfl_bound() -> int:
	var f := 0
	var baseline := GridModel.new(8)
	var baseline_dt: float = baseline.max_stable_dt_s()

	var huge_diffusion := {GridModel.Geology.SAND: 1.0e-4, GridModel.Geology.SILT: 1.0e-4, GridModel.Geology.CLAY: 1.0e-4}
	var diffusive := GridModel.new(8, {}, {}, huge_diffusion)
	f += _check(diffusive.max_stable_dt_s() < baseline_dt,
		"a much larger diffusion coefficient is included in the CFL stability bound -- it shrinks the stable step, same as a stronger well or higher K would")
	return f

## Confirms transport actually moves mass, and in the physically correct
## direction: brief SS4's "flux(a,b) positive means a->b" was already proven
## for (0,0)->(0,1) (straight south) in _test_grid_model_face_flux -- a seed
## at (0,0) should lose mass overall and (0,1) should gain some, not the
## reverse (brief SS9: "do not equate a plume front with one tile per turn",
## but it must still move the right way).
func _test_grid_model_transport_direction() -> int:
	var f := 0
	var model := GridModel.new(8)
	var source := Vector2i(0, 0)
	var downstream := Vector2i(0, 1)
	model.seed_mass_kg(source, 1000.0)

	var dt: float = model.max_stable_dt_s() * 0.5
	model.step_transport(dt)

	f += _check(model.get_mass_kg(source) < 1000.0, "the seeded cell loses mass after one transport step")
	f += _check(model.get_mass_kg(downstream) > 0.0,
		"the downstream (higher-head-to-lower-head) neighbor gains mass after one transport step")
	return f

## User's explicit ask: contamination should be able to "escape at the
## bottom of the screen" rather than pile up forever against the map edge.
## (0, 8) is a real cell on a radius-8 map (HexMath.cells_in_radius) whose
## both "further downstream" neighbors (q,r+1) and (q-1,r+1) fall outside
## the modeled domain -- confirmed directly, not assumed, since the
## hexagon's slanted edges mean this isn't simply every cell at r == radius.
func _test_grid_model_south_boundary_outflow() -> int:
	var f := 0
	var model := GridModel.new(8)
	var boundary_axial := Vector2i(0, 8)

	var all_offsets_off_map := true
	for offset in GridModel._SOUTH_OUTFLOW_OFFSETS:
		if model.top_elevation_m.has(boundary_axial + offset):
			all_offsets_off_map = false
	f += _check(all_offsets_off_map, "(0, 8) is a genuine open-boundary cell on a radius-8 map (both downstream neighbors are off-map)")

	model.seed_mass_kg(boundary_axial, 1000.0)
	var initial_total: float = model.total_mass_kg()
	f += _check(model.escaped_mass_kg == 0.0, "nothing has escaped before any transport step runs")

	var dt: float = model.max_stable_dt_s() * 0.5
	model.step_transport(dt)

	f += _check(model.escaped_mass_kg > 0.0, "stepping transport at an open-boundary cell actually drains mass out of the domain")
	f += _check(model.get_mass_kg(boundary_axial) < 1000.0, "the boundary cell itself loses mass")
	f += _check(is_equal_approx(model.total_mass_kg() + model.escaped_mass_kg, initial_total),
		"mass remaining in the domain plus escaped mass exactly equals the original total -- conservation still holds in the open-boundary sense")

	var expected_flux: float = model.get_k(boundary_axial) * GridModel.HEAD_GRADIENT_M_PER_ROW / GridModel.CELL_SPACING_M
	var expected_outflow_m3_s: float = expected_flux * GridModel.FACE_AREA_M2
	f += _check(is_equal_approx(model._south_boundary_outflow_m3_s(boundary_axial), expected_outflow_m3_s),
		"_south_boundary_outflow_m3_s matches K * HEAD_GRADIENT_M_PER_ROW / CELL_SPACING_M * FACE_AREA_M2")

	var interior_axial := Vector2i(0, 0)
	var interior_offsets_all_in_map := true
	for offset in GridModel._SOUTH_OUTFLOW_OFFSETS:
		if not model.top_elevation_m.has(interior_axial + offset):
			interior_offsets_all_in_map = false
	f += _check(interior_offsets_all_in_map, "an interior cell's downstream neighbors both exist, so it never contributes boundary outflow")

	return f

## Brief SS8 Phase 1 step 6's "reset" -- replaying a scenario must zero out
## EVERY cell's mass (not just the seeded one, since transport may have since
## spread it elsewhere) and escaped_mass_kg, while leaving the map itself
## (elevation/geology/head/K/porosity) completely untouched, so a reset
## replays the SAME map rather than silently regenerating a new one.
func _test_grid_model_reset_mass() -> int:
	var f := 0
	var model := GridModel.new(8)
	var source := Vector2i(0, -5)
	model.seed_mass_kg(source, 1000.0)
	var dt: float = model.max_stable_dt_s() * 0.5
	for i in range(5):
		model.step_transport(dt)
	f += _check(model.total_mass_kg() > 0.0, "sanity check: mass has actually spread/exists before reset")

	var elevation_before: float = model.get_elevation(source)
	var k_before: float = model.get_k(source)

	model.reset_mass()

	f += _check(model.total_mass_kg() == 0.0, "reset_mass zeroes every cell's mass, not just the original source cell")
	f += _check(model.escaped_mass_kg == 0.0, "reset_mass zeroes escaped_mass_kg too")
	f += _check(model.get_elevation(source) == elevation_before, "reset_mass never touches elevation")
	f += _check(model.get_k(source) == k_before, "reset_mass never touches K (the player's live-tuned geology parameters survive a reset)")
	return f

## Brief SS8 Phase 1 step 7: "one physically defensible player remediation
## choice (e.g. a capture well with specified pumping rate)". Confirms
## set_well's plumbing, that a configured well actually removes mass on a
## transport step (not just a no-op placeholder), that the removed mass is
## tracked (not silently vanishing -- see GridModel.step_transport's doc
## comment on why this is a "physically defensible" sink, not a magic
## delete), and that it's included in the CFL stability bound the same way
## the open boundary already is.
func _test_grid_model_well_capture() -> int:
	var f := 0
	var model := GridModel.new(8)
	var source := Vector2i(0, -5)
	var well := Vector2i(0, 3)
	model.seed_mass_kg(source, 1000.0)

	f += _check(model.well_pumping_rate_m3_s == 0.0, "a fresh GridModel has no well configured (rate 0.0) by default")

	model.set_well(well, 0.02)
	f += _check(model.well_axial == well and model.well_pumping_rate_m3_s == 0.02,
		"set_well updates both the well's location and its pumping rate")

	# Seed some mass directly at the well too, so there's something to
	# capture immediately without waiting on advection to carry it there.
	model.seed_mass_kg(well, 50.0)
	var initial_total: float = model.total_mass_kg()
	var dt: float = model.max_stable_dt_s() * 0.5
	f += _check(dt > 0.0 and is_finite(dt), "max_stable_dt_s stays finite and positive once a well sink exists")
	model.step_transport(dt)

	f += _check(model.captured_mass_kg > 0.0, "a cell with a configured well actually captures mass on a transport step")
	f += _check(is_equal_approx(model.total_mass_kg() + model.escaped_mass_kg + model.captured_mass_kg, initial_total),
		"mass remaining + escaped + captured still equals the pre-step total -- the well is a tracked sink, not a conservation leak")

	model.reset_mass()
	f += _check(model.captured_mass_kg == 0.0, "reset_mass also zeroes captured_mass_kg")
	f += _check(model.well_pumping_rate_m3_s == 0.02 and model.well_axial == well,
		"reset_mass leaves the well's own configuration (location/rate) untouched")

	var baseline_model := GridModel.new(8)
	var baseline_dt: float = baseline_model.max_stable_dt_s()
	baseline_model.set_well(Vector2i(0, 0), 1.0) # a pumping rate far larger than any natural face flow
	f += _check(baseline_model.max_stable_dt_s() < baseline_dt,
		"a well's pumping rate is included in the CFL stability bound -- a strong enough sink shrinks the stable step")
	return f

## Brief SS12.4 test 9: "Well capture: pumping changes flow field and removes
## dissolved mass by extracted-water concentration." The mass-removal half is
## _test_grid_model_well_capture above; this checks the flow-field half,
## which only became true once set_well() started re-solving heads (brief
## SS12.6 Gate A) -- a specified-rate well is now a real sink in the steady-
## state balance, so it must draw down head at its own cell and pull more
## water toward it from its neighbors than an unpumped baseline would,
## compared cell-for-cell against an otherwise-identical model with no well.
func _test_grid_model_well_changes_flow_field() -> int:
	var f := 0
	var no_well := GridModel.new(8)
	var well_axial := Vector2i(0, 3)
	var pumped := GridModel.new(8)
	pumped.set_well(well_axial, 0.05)

	f += _check(pumped.get_head(well_axial) < no_well.get_head(well_axial),
		"a pumping well draws down head at its own cell relative to an otherwise-identical unpumped baseline")

	var no_well_inflow := 0.0
	var pumped_inflow := 0.0
	for neighbor in HexMath.neighbors(well_axial):
		if not no_well.top_elevation_m.has(neighbor):
			continue
		no_well_inflow += maxf(0.0, no_well.face_flux_m_s(neighbor, well_axial)) * GridModel.FACE_AREA_M2
		pumped_inflow += maxf(0.0, pumped.face_flux_m_s(neighbor, well_axial)) * GridModel.FACE_AREA_M2
	f += _check(pumped_inflow > no_well_inflow,
		"pumping measurably increases the net inflow drawn toward the well's cell from its neighbors -- a real capture-zone effect, not a no-op")

	return f

func _make_test_tileset() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
	tile_set.tile_size = World.TILE_SIZE
	return tile_set

## GodotHexOffset's axial<->offset conversion must be exactly invertible, or
## placement and hit-testing would silently diverge for some cells.
func _test_godot_hex_offset_round_trip() -> int:
	var all_match := true
	for q in range(-6, 7):
		for r in range(-6, 7):
			var axial := Vector2i(q, r)
			var offset := GodotHexOffset.axial_to_offset(axial)
			var back := GodotHexOffset.offset_to_axial(offset)
			if back != axial:
				all_match = false
	return _check(all_match, "axial <-> Godot offset-coordinate conversion round-trips for all cells")

## Confirms -- across a WIDE (q, r) range, not just a narrow blind spot --
## that converting through GodotHexOffset before calling map_to_local()
## exactly reproduces HexMath's axial spacing (scaled only for TILE_SIZE.x's
## rounding from the true, irrational column spacing; TILE_SIZE.y is exact
## for this HEX_SIZE, see world.gd). This is the flat-top counterpart of the
## test that caught the original odd-r/odd-q mismatch bug: it samples a wide
## range, not just the handful of cells where a wrong offset scheme might
## coincide with naive axial coordinates by accident.
func _test_tileset_matches_axial_spacing() -> int:
	var layer := TileMapLayer.new()
	layer.tile_set = _make_test_tileset()

	var hex_size: float = World.TILE_SIZE.y / sqrt(3.0)
	var origin_godot: Vector2 = layer.map_to_local(GodotHexOffset.axial_to_offset(Vector2i(0, 0)))
	var origin_hex: Vector2 = HexMath.axial_to_pixel(Vector2i(0, 0), hex_size)
	var x_scale: float = (World.TILE_SIZE.x * 0.75) / (hex_size * 1.5)

	var all_proportional := true
	for q in range(-4, 5):
		for r in range(-5, 6):
			var axial := Vector2i(q, r)
			var offset := GodotHexOffset.axial_to_offset(axial)
			var godot_delta: Vector2 = layer.map_to_local(offset) - origin_godot
			var hex_delta: Vector2 = HexMath.axial_to_pixel(axial, hex_size) - origin_hex
			var expected_x: float = hex_delta.x * x_scale
			var x_matches: bool = is_equal_approx(godot_delta.x, expected_x) or \
				(absf(godot_delta.x) < 0.01 and absf(expected_x) < 0.01)
			var y_matches: bool = is_equal_approx(godot_delta.y, hex_delta.y) or \
				(absf(godot_delta.y) < 0.01 and absf(hex_delta.y) < 0.01)
			if not (x_matches and y_matches):
				all_proportional = false

	layer.free()
	return _check(all_proportional,
		"TileSet (via GodotHexOffset) spacing matches HexMath's axial formulas across a wide (q,r) range")

## local_to_map(map_to_local(axial)) must return axial, or clicking drifts
## from what's actually drawn there -- exactly the bug class this whole
## TileMapLayer rebuild exists to eliminate.
func _test_tilemap_hit_testing_round_trip() -> int:
	var layer := TileMapLayer.new()
	layer.tile_set = _make_test_tileset()

	var all_match := true
	var samples: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(3, -2), Vector2i(-4, 1), Vector2i(5, 5), Vector2i(-8, 8), Vector2i(0, 8),
	]
	for axial in samples:
		var local_pos: Vector2 = layer.map_to_local(axial)
		var back: Vector2i = layer.local_to_map(local_pos)
		if back != axial:
			all_match = false

	layer.free()
	return _check(all_match, "TileMapLayer map_to_local -> local_to_map round-trips correctly")

## Ground tiles are now generated (hex_tile_texture.gd), not Kenney art --
## see DECISIONS.md for why (the Kenney art's silhouette doesn't taper like a
## true hexagon, which is what drove the whole earlier investigation; a
## generated hex has no external silhouette to disagree with the grid math).
## Confirms the generator actually produces a filled hex (opaque center,
## transparent canvas corner) at the expected size, and that GridOutline's
## default grid_size matches World.TILE_SIZE -- the single source of truth
## for grid geometry now that there's no external art to measure against.
func _test_generated_hex_texture() -> int:
	var f := 0
	var texture := HexTileTexture.generate(World.HEX_SIZE, World.TEXTURE_CANVAS_SIZE, Color.WHITE, Color.BLACK, 1.5)
	var image := texture.get_image()
	f += _check(image.get_width() == World.TEXTURE_CANVAS_SIZE.x and image.get_height() == World.TEXTURE_CANVAS_SIZE.y,
		"generated hex texture canvas matches World.TEXTURE_CANVAS_SIZE")

	var center := Vector2i(World.TEXTURE_CANVAS_SIZE.x / 2, World.TEXTURE_CANVAS_SIZE.y / 2)
	f += _check(image.get_pixelv(center).a > 0.5, "generated hex texture is opaque at its center")

	var corner := Vector2i(0, 0)
	f += _check(image.get_pixelv(corner).a < 0.5,
		"generated hex texture is transparent at a canvas corner (a true hex, not a filled rectangle)")

	var outline := GridOutline.new()
	f += _check(outline.grid_size == Vector2(World.TILE_SIZE),
		"GridOutline's default grid_size matches World.TILE_SIZE -- the single source of truth for grid geometry")
	outline.free()
	return f

## Richer-fill feature: a soft vignette baked into the generated texture
## (shading_strength), plus per-cell alternative tiles that only differ by a
## modulate jitter (tile_tint_jitter) so same-terrain neighbors don't look
## like one stamp repeated. Both are Inspector-tunable on World, per
## memory/feedback_expose_visual_tuning.md -- these tests just confirm the
## mechanism works, not any particular look.
func _test_generated_hex_shading_and_tint_variants() -> int:
	var f := 0

	var flat := HexTileTexture.generate(World.HEX_SIZE, World.TEXTURE_CANVAS_SIZE, Color.WHITE, Color.BLACK, 1.5, 0.0)
	var shaded := HexTileTexture.generate(World.HEX_SIZE, World.TEXTURE_CANVAS_SIZE, Color.WHITE, Color.BLACK, 1.5, 0.4)
	var flat_image := flat.get_image()
	var shaded_image := shaded.get_image()
	var center := Vector2i(World.TEXTURE_CANVAS_SIZE.x / 2, World.TEXTURE_CANVAS_SIZE.y / 2)
	var near_edge := Vector2i(center.x, 10) # inside the hex, well away from both centre and the border band

	f += _check(flat_image.get_pixelv(center).r == 1.0 and flat_image.get_pixelv(near_edge).r == 1.0,
		"shading_strength 0.0 keeps the old flat fill (no vignette)")
	f += _check(shaded_image.get_pixelv(center).r > 0.95,
		"shading_strength > 0 still leaves the centre near full brightness")
	f += _check(shaded_image.get_pixelv(near_edge).r < shaded_image.get_pixelv(center).r,
		"shading_strength > 0 darkens a point away from centre more than the centre itself")

	var world = _make_world()
	var source: TileSetAtlasSource = world.ground.tile_set.get_source(World.TERRAIN_GRASS)
	f += _check(source.get_alternative_tiles_count(Vector2i(0, 0)) == World.TINT_VARIANT_COUNT,
		"each terrain source has TINT_VARIANT_COUNT alternative tiles")
	var base_modulate: Color = source.get_tile_data(Vector2i(0, 0), 0).modulate
	var last_modulate: Color = source.get_tile_data(Vector2i(0, 0), World.TINT_VARIANT_COUNT - 1).modulate
	f += _check(base_modulate != last_modulate,
		"tint variants actually differ in modulate, not all identical")
	world.free()

	return f

## Real ground art (GROUND_TEXTURES, art/pretty_tiles/): confirms a terrain
## with multiple real-art variants (grass: grass_01 + grass_03) actually gets
## one atlas tile per variant, and that _build_terrain's independent hash
## (separate from the tint-jitter hash) actually varies which one gets used
## across the map -- not just always atlas column 0, which would silently
## waste the second variant.
func _test_real_ground_art_variants() -> int:
	var f := 0
	var world = _make_world()

	var source: TileSetAtlasSource = world.ground.tile_set.get_source(World.TERRAIN_GRASS)
	f += _check(source.get_tiles_count() == World.GRASS_ART.size(),
		"grass ground source has one atlas tile per real-art variant (GRASS_ART)")

	var seen_atlas_x := {}
	for axial in HexMath.cells_in_radius(world.radius):
		if world._terrain_for(axial) != World.TERRAIN_GRASS:
			continue
		var offset := GodotHexOffset.axial_to_offset(axial)
		var coords: Vector2i = world.ground.get_cell_atlas_coords(offset)
		seen_atlas_x[coords.x] = true
	f += _check(seen_atlas_x.size() > 1,
		"grass cells use more than one real-art variant across the map, not always the same one")

	world.free()
	return f

## Node._ready() is deferred by Godot's normal lifecycle (it does not fire
## synchronously on add_child()), and this script's _init() runs and calls
## quit() before the engine ever processes a frame -- so @onready vars like
## `ground`/`features` would still be null when accessed here, and anything
## gated on them (_model, _elevation_lo/hi, _river_cells) would silently no-op
## instead of erroring. (This is exactly what happened on the first version
## of these tests: they reported PASS while iterating empty/default state.)
## Sidestep the lifecycle question entirely: build the child nodes and call
## World's build methods directly, in the same order _ready() uses.
func _make_world() -> Node:
	var world = World.new()
	world.minimal_test_mode = false # these tests exercise the full terrain/feature system
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	world.add_child(ground_node)
	world.add_child(features_node)
	world.ground = ground_node
	world.features = features_node

	world._build_tileset()
	world._model = GridModel.new(world.radius)
	var bounds: Vector2 = world._model.elevation_range()
	world._elevation_lo = bounds.x
	world._elevation_hi = bounds.y
	world._river_cells.clear()
	for axial in world._generate_river_path(world.radius):
		world._river_cells[axial] = true
	world._build_terrain()
	world._build_features()
	return world

func _test_world_river_path() -> int:
	var f := 0
	var world = _make_world()
	var radius: int = world.radius
	var path_a: Array = world._generate_river_path(radius)
	var path_b: Array = world._generate_river_path(radius)

	var rows_visited := {}
	for axial in path_a:
		rows_visited[axial.y] = true
	var all_rows_present := true
	for r in range(-radius, radius + 1):
		if not rows_visited.has(r):
			all_rows_present = false
	f += _check(all_rows_present, "World river path visits every row from -radius to +radius at least once")

	var valid_cells := {}
	for axial in HexMath.cells_in_radius(radius):
		valid_cells[axial] = true
	var all_on_map := true
	for axial in path_a:
		if not valid_cells.has(axial):
			all_on_map = false
	f += _check(all_on_map, "every World river cell is a real cell of the map")
	f += _check(path_a == path_b, "World river path generation is deterministic")

	# The actual bug the user caught: "one cell per row, on the map" does NOT
	# imply consecutive rows are hex-adjacent. An earlier version of this path
	# computed each row's column independently and had 4 real gaps (hex
	# distance 2) near the map edges, where boundary clamping diverged
	# between neighboring rows.
	var all_adjacent := true
	for i in range(1, path_a.size()):
		if HexMath.axial_distance(path_a[i - 1], path_a[i]) != 1:
			all_adjacent = false
	f += _check(all_adjacent, "every consecutive pair of river cells is an actual hex neighbor (no gaps)")

	# Genuine two-directional wander: a single hex step can only ever move q
	# left or hold while advancing r (there is no "southeast" hex neighbor),
	# so a naive formula silently monotonically drifts instead of actually
	# undulating. Confirms the q sequence both decreases AND increases
	# somewhere, not just one direction.
	var saw_increase := false
	var saw_decrease := false
	for i in range(1, path_a.size()):
		var dq: int = path_a[i].x - path_a[i - 1].x
		if dq > 0:
			saw_increase = true
		elif dq < 0:
			saw_decrease = true
	f += _check(saw_increase and saw_decrease,
		"the river wanders both left and right, not just a monotonic drift")

	world.free()
	return f

func _test_world_terrain_assignment() -> int:
	var f := 0
	var world = _make_world()

	var all_river_is_water := true
	for axial in world._river_cells.keys():
		if world._terrain_for(axial) != World.TERRAIN_WATER:
			all_river_is_water = false
	f += _check(all_river_is_water, "every river cell gets the water terrain")

	var all_valid_terrain := true
	var valid_ids := [World.TERRAIN_GRASS, World.TERRAIN_SAND, World.TERRAIN_WATER, World.TERRAIN_SNOW, World.TERRAIN_ROCKY]
	for axial in HexMath.cells_in_radius(world.radius):
		if not valid_ids.has(world._terrain_for(axial)):
			all_valid_terrain = false
	f += _check(all_valid_terrain, "every cell gets one of the five known terrain ids")

	world.free()
	return f

## Confirms Ground and Features are NOT subject to divergent transforms --
## directly testing the spec's listed root cause #5 ("Different transforms
## on Ground and Features"). A feature's Features-local position should
## round-trip, via Ground, back to the same cell it was placed for.
func _test_world_feature_centre_matches_ground() -> int:
	var f := 0
	var world = _make_world()

	var all_round_trip := true
	var samples: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-4, 1), Vector2i(5, 5)]
	for axial in samples:
		var features_pos: Vector2 = world.cell_centre_in_features(axial)
		var global_pos: Vector2 = world.features.to_global(features_pos)
		var ground_local: Vector2 = world.ground.to_local(global_pos)
		var offset_back: Vector2i = world.ground.local_to_map(ground_local)
		var axial_back: Vector2i = GodotHexOffset.offset_to_axial(offset_back)
		if axial_back != axial:
			all_round_trip = false
	f += _check(all_round_trip,
		"a feature's position round-trips (via Ground) back to the same cell -- Ground/Features share one coordinate space")

	world.free()
	return f

## godot_hex_map_spec.md's Test B, minimal and isolated: exactly one tree,
## one rock, flat grass everywhere else, no river -- confirms the scene this
## mode builds actually matches that description (not the full system).
func _test_world_minimal_test_mode() -> int:
	var f := 0
	var world = World.new() # minimal_test_mode defaults to true -- deliberately not overridden here
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	world.add_child(ground_node)
	world.add_child(features_node)
	world.ground = ground_node
	world.features = features_node

	world._build_tileset()
	world._model = GridModel.new(world.radius)
	var bounds: Vector2 = world._model.elevation_range()
	world._elevation_lo = bounds.x
	world._elevation_hi = bounds.y
	world._river_cells.clear() # _ready() skips populating this in minimal_test_mode; mirrored here
	world._build_terrain()
	world._build_features()

	var all_grass := true
	for axial in HexMath.cells_in_radius(world.radius):
		if world._terrain_for(axial) != World.TERRAIN_GRASS:
			all_grass = false
	f += _check(all_grass, "minimal test mode: every cell is flat grass, no terrain transitions")
	f += _check(features_node.get_child_count() == 2,
		"minimal test mode: exactly one tree and one rock, nothing else")

	world.free()
	return f

## GridOutline (permanent) and HexSelection (hover/click highlight) must use
## the SAME hex shape, or the selection highlight won't visually match the
## permanent grid lines it's meant to sit on top of.
func _test_hex_selection_matches_grid_outline() -> int:
	var selection := HexSelection.new()
	var outline := GridOutline.new()
	var f := _check(selection.grid_size == outline.grid_size,
		"HexSelection's default grid_size matches GridOutline's default -- keep them matched if you tune one")
	selection.free()
	outline.free()
	return f

## The axial cell a feature root belongs to, per World._add_feature's own
## "axial" metadata -- the authoritative value, not a reverse pixel-position
## guess (which would be ambiguous for scattered decals sitting near a
## cell's edge).
func _axial_for_feature_root(world: Node, root: Node2D) -> Vector2i:
	return root.get_meta("axial")

## The user's explicit rule: a tall feature (mountain/tree) must be able to
## visually overlap the tile behind it to read as standing above the ground
## plane, not be clipped to its own hex. Confirms the two mechanisms world.gd
## documents as jointly guaranteeing this: sprites are never region-clipped,
## and Features' y_sort_enabled + monotonically-increasing ground-contact Y
## per row means a feature further south always draws in front of one
## further north.
func _test_feature_overlap_depth_rule() -> int:
	var f := 0
	var world = _make_world()

	f += _check(world.features.y_sort_enabled,
		"Features root has y_sort_enabled -- required for the depth/overlap rule")

	var north: Vector2 = world.cell_centre_in_features(Vector2i(0, 4))
	var south: Vector2 = world.cell_centre_in_features(Vector2i(0, 5))
	f += _check(south.y > north.y,
		"a cell one row further south has a strictly greater ground-contact Y -- y_sort draws it in front")

	var root: Node2D = world._add_feature(Vector2i(0, 4), World.TREES[0],
		Vector2(World.TREES[0].get_width() / 2.0, World.TREES[0].get_height()))
	var sprite: Sprite2D = root.get_child(0)
	f += _check(not sprite.region_enabled,
		"feature sprites are never region-clipped -- a tall image can extend past its own cell's bounds")
	f += _check(root.z_index == 0 and sprite.z_index == 0,
		"no feature gets its own z_index -- godot_hex_map_spec.md: that would break y-sort ordering")

	world.free()
	return f

## TERRAIN_ROCKY couples a cell's ground art to whether it got a boulder
## feature (see _terrain_for's doc comment) -- confirms that coupling
## actually holds (every rocky cell's placed ground tile uses the rocky
## source), and guards the exact near-miss bug this coupling risked: a plain
## snow-band cell (boulder roll failed) must never fall through to the
## forest-band tree branch just because t >= SNOW_THRESHOLD implies
## t >= FOREST_THRESHOLD too.
func _test_rocky_terrain_boulder_coupling() -> int:
	var f := 0
	var world = _make_world()

	var any_rocky := false
	var all_rocky_tiles_use_rocky_source := true
	for axial in HexMath.cells_in_radius(world.radius):
		if world._terrain_for(axial) != World.TERRAIN_ROCKY:
			continue
		any_rocky = true
		var offset := GodotHexOffset.axial_to_offset(axial)
		if world.ground.get_cell_source_id(offset) != World.TERRAIN_ROCKY:
			all_rocky_tiles_use_rocky_source = false
	f += _check(any_rocky, "at least one cell gets the rocky terrain across a radius-%d map" % world.radius)
	f += _check(all_rocky_tiles_use_rocky_source,
		"every rocky-terrain cell's ground tile actually uses the rocky source")

	var all_snow_band_features_are_rocks_or_mountains := true
	for root in world.features.get_children():
		if root.get_meta("kind", "") != "feature":
			continue
		var axial: Vector2i = root.get_meta("axial")
		if world._elevation_t(axial) < World.SNOW_THRESHOLD:
			continue
		var sprite: Sprite2D = root.get_child(0)
		if not (World.ROCKS.has(sprite.texture) or World.MOUNTAINS.has(sprite.texture)):
			all_snow_band_features_are_rocks_or_mountains = false
	f += _check(all_snow_band_features_are_rocks_or_mountains,
		"every major feature at/above the snow threshold is a rock or mountain, never a tree")

	world.free()
	return f

## MOUNTAIN_THRESHOLD is meant to put mountain_large where the user can
## actually see/test it: the far north (GridModel's slope makes elevation
## highest toward -radius). Confirms at least one mountain feature exists,
## and that it actually concentrates in the northern half of the map (r < 0),
## not scattered uniformly -- which would defeat the point of "test
## mountainous areas in the north."
func _test_mountains_concentrate_north() -> int:
	var f := 0
	var world = _make_world()

	var mountain_axials: Array[Vector2i] = []
	for root in world.features.get_children():
		if root.get_meta("kind", "") != "feature":
			continue
		var sprite: Sprite2D = root.get_child(0)
		if World.MOUNTAINS.has(sprite.texture):
			mountain_axials.append(root.get_meta("axial"))

	f += _check(mountain_axials.size() > 0,
		"at least one mountain feature appears across a radius-%d map" % world.radius)

	var all_north := true
	for axial in mountain_axials:
		if axial.y >= 0:
			all_north = false
	f += _check(all_north, "every mountain feature sits in the northern half of the map (r < 0)")

	world.free()
	return f

## The user's ask: trees/rocks/mountains (not just decals) should scatter
## within their cell too, so a forested or rocky area doesn't read as a grid
## of dead-center trunks. Confirms at least one major feature's root sits
## away from its cell's exact center -- minimal_test_mode's isolated Test B
## placements must stay exact for anchor comparison (see _test_world_minimal_test_mode's
## intent), so this only checks the full procedural build, not that mode.
func _test_major_feature_scatter() -> int:
	var f := 0
	var world = _make_world()

	var any_scattered := false
	for root in world.features.get_children():
		if root.get_meta("kind", "") != "feature":
			continue
		var axial: Vector2i = root.get_meta("axial")
		var center: Vector2 = world.cell_centre_in_features(axial)
		if root.position.distance_to(center) > 1.0:
			any_scattered = true
	f += _check(any_scattered,
		"at least one major feature (tree/rock/mountain) is scattered away from its cell's exact center")

	world.free()
	return f

## GridOutline's "sunken water" shore edges: the user's explicit requirement
## was camera-aware, not "every water/land boundary" -- only a water cell's
## three NORTH-facing edges (where a south-facing camera would actually see
## the bordering land's cliff face) should ever get the shore treatment, and
## its three SOUTH-facing edges must stay plain even when they also border
## land. First confirms the index/direction mapping itself geometrically
## (_SHORE_EDGE_NEIGHBOR_OFFSETS[i] must point toward _SHORE_EDGE_INDICES[i]'s
## actual edge-midpoint direction -- the exact kind of hand-derived mapping
## that produced real bugs earlier this project), then exercises
## _is_shore_edge directly against known, hand-placed terrain.
func _test_grid_outline_shore_edges() -> int:
	var f := 0

	var points := HexMath.hex_points(1.0)
	var all_aligned := true
	for i in range(GridOutline._SHORE_EDGE_INDICES.size()):
		var edge_index: int = GridOutline._SHORE_EDGE_INDICES[i]
		var edge_mid: Vector2 = (points[edge_index] + points[(edge_index + 1) % 6]) * 0.5
		var neighbor_dir: Vector2 = HexMath.axial_to_pixel(GridOutline._SHORE_EDGE_NEIGHBOR_OFFSETS[i], 1.0)
		if edge_mid.normalized().dot(neighbor_dir.normalized()) < 0.99:
			all_aligned = false
	f += _check(all_aligned, "_SHORE_EDGE_NEIGHBOR_OFFSETS entries actually point toward their matching edge")

	var world = _make_world()
	var outline := GridOutline.new()
	outline.configure(world.ground, HexMath.cells_in_radius(world.radius))

	# Hand-placed, independent of wherever the procedural river/elevation put
	# water: a water cell at the origin with land directly north AND south.
	var origin_axial := Vector2i(0, 0)
	var origin_offset := GodotHexOffset.axial_to_offset(origin_axial)
	world.ground.set_cell(origin_offset, World.TERRAIN_WATER, Vector2i(0, 0))
	world.ground.set_cell(GodotHexOffset.axial_to_offset(Vector2i(0, -1)), World.TERRAIN_GRASS, Vector2i(0, 0))
	world.ground.set_cell(GodotHexOffset.axial_to_offset(Vector2i(0, 1)), World.TERRAIN_GRASS, Vector2i(0, 0))

	f += _check(outline._is_shore_edge(origin_axial, origin_offset, 4),
		"a water cell's north edge IS a shore edge when land borders it there")
	f += _check(not outline._is_shore_edge(origin_axial, origin_offset, 1),
		"a water cell's south edge is NOT a shore edge even when land borders it there -- camera-facing rule, not 'every water/land boundary'")

	# North neighbor is water, not land -- no cliff between two same-level cells.
	world.ground.set_cell(GodotHexOffset.axial_to_offset(Vector2i(0, -1)), World.TERRAIN_WATER, Vector2i(0, 0))
	f += _check(not outline._is_shore_edge(origin_axial, origin_offset, 4),
		"a water cell's north edge is NOT a shore edge when the neighbor there is also water")

	# The map's own outer boundary isn't a visible cliff -- a water cell at
	# the northernmost row has no real cell north of it at all.
	var edge_axial := Vector2i(0, -world.radius)
	var edge_offset := GodotHexOffset.axial_to_offset(edge_axial)
	world.ground.set_cell(edge_offset, World.TERRAIN_WATER, Vector2i(0, 0))
	f += _check(not outline._is_shore_edge(edge_axial, edge_offset, 4),
		"a water cell at the map's own edge gets no shore line toward the off-map side")

	# The straight-north shore edge reads most face-on to a south-facing
	# camera and should be thickest; the two diagonal (NW/NE) shore edges are
	# foreshortened from this angle and should be thinner.
	f += _check(outline._shore_edge_width(4) == outline.shore_line_width,
		"the straight-north shore edge uses shore_line_width")
	f += _check(outline._shore_edge_width(3) == outline.shore_line_width_diagonal
			and outline._shore_edge_width(5) == outline.shore_line_width_diagonal,
		"the NW/NE diagonal shore edges use shore_line_width_diagonal, not the straight-north width")

	outline.free()
	world.free()
	return f

## Decals (flowers/bushes/pebbles) are the new ground-clutter layer: should
## appear, should always match the terrain they're sitting on (DECAL_SETS),
## and should never double up with a major feature (tree/rock) on the same
## cell -- that's the "don't over-dress a cell" rule _build_features applies.
func _test_world_decals() -> int:
	var f := 0
	var world = _make_world()

	var feature_axials := {}
	var decal_axials := {}
	var all_decals_match_terrain := true
	for root in world.features.get_children():
		var axial := _axial_for_feature_root(world, root)
		var kind: String = root.get_meta("kind", "")
		if kind == "feature":
			feature_axials[axial] = true
		elif kind == "decal":
			decal_axials[axial] = true
			var sprite: Sprite2D = root.get_child(0)
			var expected: Array = World.DECAL_SETS.get(world._terrain_for(axial), [])
			if not expected.has(sprite.texture):
				all_decals_match_terrain = false

	f += _check(decal_axials.size() > 0,
		"minimal_test_mode=false places at least one decal across a radius-%d map" % world.radius)
	f += _check(all_decals_match_terrain,
		"every decal's texture belongs to its cell's actual terrain's DECAL_SETS entry")

	var any_double_dressed := false
	for axial in decal_axials.keys():
		if feature_axials.has(axial):
			any_double_dressed = true
	f += _check(not any_double_dressed,
		"no cell carries both a major feature and a decal (don't over-dress a single cell)")

	world.free()
	return f

## The user's explicit ask: multiple decals per cell (0/1/2/3, not a uniform
## one-per-tile look), scattered at random positions rather than stacked on
## the exact same point. Forces decal_density to 1.0 so every slot fires
## deterministically, removing randomness from whether clustering CAN happen
## -- isolates whether the mechanism works from whether a particular seed
## happens to roll it.
##
## Builds its own World rather than using _make_world(): that helper already
## calls _build_features() once with default settings, and Node.queue_free()
## is deferred (never flushes in this script's single-frame, non-looping
## _init()), so a second _build_features() call here would leave the first
## pass's now-orphaned-but-still-attached children mixed into the count.
func _test_decal_clustering_and_scatter() -> int:
	var f := 0
	var world = World.new()
	world.minimal_test_mode = false
	world.decal_density = 1.0
	world.decal_cluster_max = 3
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	world.add_child(ground_node)
	world.add_child(features_node)
	world.ground = ground_node
	world.features = features_node
	world._build_tileset()
	world._model = GridModel.new(world.radius)
	var bounds: Vector2 = world._model.elevation_range()
	world._elevation_lo = bounds.x
	world._elevation_hi = bounds.y
	world._river_cells.clear()
	for axial in world._generate_river_path(world.radius):
		world._river_cells[axial] = true
	world._build_terrain()
	world._build_features()

	var decals_per_axial := {}
	for root in world.features.get_children():
		if root.get_meta("kind", "") != "decal":
			continue
		var axial: Vector2i = _axial_for_feature_root(world, root)
		decals_per_axial[axial] = decals_per_axial.get(axial, 0) + 1

	var any_cell_with_multiple := false
	for count in decals_per_axial.values():
		if count >= 2:
			any_cell_with_multiple = true
	f += _check(any_cell_with_multiple,
		"with decal_density=1.0, at least one cell gets more than one decal (real clustering, not one-per-tile)")

	var any_scattered_away_from_center := false
	for root in world.features.get_children():
		if root.get_meta("kind", "") != "decal":
			continue
		var axial: Vector2i = _axial_for_feature_root(world, root)
		var center: Vector2 = world.cell_centre_in_features(axial)
		if root.position.distance_to(center) > 1.0:
			any_scattered_away_from_center = true
	f += _check(any_scattered_away_from_center,
		"decals are actually offset from the cell's exact center, not all stacked on one point")

	world.free()
	return f

## World.cell_info() is the single source of truth any UI (the cell
## inspector) reads from -- confirms it actually reflects _model's data and
## _terrain_for's own decision, rather than drifting out of sync with either.
func _test_world_cell_info() -> int:
	var f := 0
	var world = _make_world()

	var axial := Vector2i(2, -3)
	var info: Dictionary = world.cell_info(axial)
	f += _check(info["axial"] == axial, "cell_info echoes back the axial it was asked about")
	f += _check(info["terrain"] == world._terrain_for(axial), "cell_info's terrain matches _terrain_for")
	f += _check(info["terrain_name"] == World.TERRAIN_NAMES[world._terrain_for(axial)],
		"cell_info's terrain_name matches TERRAIN_NAMES")
	f += _check(is_equal_approx(info["elevation_m"], world._model.get_elevation(axial)),
		"cell_info's elevation matches GridModel")
	f += _check(info["geology_id"] == world._model.get_geology(axial), "cell_info's geology_id matches GridModel")
	f += _check(info["geology_name"] == GridModel.GEOLOGY_NAME[world._model.get_geology(axial)],
		"cell_info's geology_name matches GridModel.GEOLOGY_NAME")
	f += _check(is_equal_approx(info["k_m_s"], world._model.get_k(axial)), "cell_info's k_m_s matches GridModel")
	f += _check(is_equal_approx(info["porosity"], world._model.get_porosity(axial)), "cell_info's porosity matches GridModel")
	f += _check(is_equal_approx(info["diffusion_m2_s"], world._model.get_diffusion_m2_s(axial)), "cell_info's diffusion_m2_s matches GridModel")
	f += _check(is_equal_approx(info["head_m"], world._model.get_head(axial)), "cell_info's head_m matches GridModel")
	f += _check(is_equal_approx(info["concentration_kg_m3"], world._model.get_concentration_kg_m3(axial)),
		"cell_info's concentration_kg_m3 matches GridModel")
	f += _check(is_equal_approx(info["contamination_percent"],
			world._model.get_concentration_kg_m3(axial) / world.contamination_full_scale_kg_m3 * 100.0),
		"cell_info's contamination_percent matches concentration / contamination_full_scale_kg_m3 * 100")

	world.free()
	return f

## The user's ask: a way to interrogate cell data via an info box on
## hover/click. The actual on-screen panel needs a live Viewport/mouse input
## to drive (not practical headlessly, same reasoning as GridOutline's shore
## edges) -- but _format_cell_info is pure text formatting, split out
## specifically so the content can be tested without either.
func _test_hex_selection_format_cell_info() -> int:
	var selection := HexSelection.new()
	var info := {
		"axial": Vector2i(2, -3),
		"terrain_name": "Grass",
		"elevation_m": 91.2345,
		"geology_name": "Sand aquifer",
		"k_m_s": 3.0e-4,
		"porosity": 0.3,
		"diffusion_m2_s": 1.0e-9,
		"head_m": 47.6,
		"contamination_percent": 12.345,
	}
	var text: String = selection._format_cell_info(info)
	var f := 0
	f += _check(text.contains("(2, -3)"), "formatted cell info names the axial coordinate")
	f += _check(text.contains("Grass"), "formatted cell info names the terrain")
	f += _check(text.contains("Sand aquifer"), "formatted cell info names the geology unit")
	f += _check(text.contains("91.2"), "formatted cell info includes elevation")
	f += _check(text.contains("47.6"), "formatted cell info includes head")
	f += _check(text.contains("e-04") or text.contains("e-4"),
		"formatted cell info shows K in scientific notation (spans orders of magnitude)")
	f += _check(text.contains("e-09") or text.contains("e-9"),
		"formatted cell info shows the diffusion coefficient in scientific notation too")
	f += _check(text.contains("12.3") and text.contains("%"),
		"formatted cell info includes the contamination percentage")
	selection.free()
	return f

## FlowOverlay's arrow geometry is drawn, not tested headlessly (same
## reasoning as GridOutline's shore edges) -- but _flow_vector is pure math,
## split out specifically so it's testable without a Viewport. Confirms it
## actually matches a from-scratch recomputation of "sum of outward face
## flux * direction over every real neighbor", catching any accidental sign
## flip or wrong-direction bug in the reconstruction.
func _test_flow_overlay_vector() -> int:
	var f := 0
	var world = _make_world()
	var overlay := FlowOverlay.new()
	overlay.configure(world.ground, world._model, HexMath.cells_in_radius(world.radius))

	var axial := Vector2i(1, -2)
	var expected := Vector2.ZERO
	for face_offset in HexMath.NEIGHBOR_OFFSETS:
		var neighbor := axial + face_offset
		if not world._model.top_elevation_m.has(neighbor):
			continue
		var flux: float = world._model.face_flux_m_s(axial, neighbor)
		var dir: Vector2 = HexMath.axial_to_pixel(face_offset, 1.0).normalized()
		expected += dir * flux
	f += _check(overlay._flow_vector(axial).is_equal_approx(expected),
		"FlowOverlay._flow_vector matches a from-scratch sum of outward face flux * direction")

	overlay.free()
	world.free()
	return f

## PlumeOverlay's actual fill rendering needs a real Viewport to drive (same
## reasoning as every other overlay's draw call in this project) -- but the
## concentration -> fraction mapping is pure math, split out specifically so
## it's testable without one.
func _test_plume_overlay_fraction() -> int:
	var overlay := PlumeOverlay.new()
	overlay._model = GridModel.new(1)
	overlay._full_scale_kg_m3 = 0.03

	var f := 0
	f += _check(overlay._fraction(Vector2i(0, 0)) == 0.0, "zero concentration is a zero fraction")
	overlay._model.mass_kg[Vector2i(0, 0)] = 0.03 * GridModel.CELL_AREA_M2 * GridModel.CELL_THICKNESS_M * overlay._model.get_porosity(Vector2i(0, 0))
	f += _check(is_equal_approx(overlay._fraction(Vector2i(0, 0)), 1.0),
		"concentration exactly at full_scale is a fraction of 1.0")
	overlay._model.mass_kg[Vector2i(0, 0)] *= 2.0
	f += _check(is_equal_approx(overlay._fraction(Vector2i(0, 0)), 2.0),
		"concentration above full_scale is NOT clamped -- the top band's upper bound is +inf, so it must keep climbing")

	overlay.free()
	return f

## Sutherland-Hodgman clip against a linear scalar threshold -- the primitive
## that turns one lattice triangle into a filled isoband polygon. Checked
## directly against a hand-worked triangle (values 0, 1, 2 at its 3 corners)
## rather than only through a full _draw() round-trip, same reasoning as
## head_contour_overlay's _triangle_crossing test.
func _test_plume_overlay_clip() -> int:
	var triangle: Array = [
		{"pos": Vector2(0, 0), "val": 0.0},
		{"pos": Vector2(10, 0), "val": 1.0},
		{"pos": Vector2(10, 10), "val": 2.0},
	]
	var f := 0

	var whole := PlumeOverlay._clip(triangle, -1.0, true)
	f += _check(whole.size() == 3, "a threshold below every vertex keeps the whole triangle untouched")

	var none := PlumeOverlay._clip(triangle, 3.0, true)
	f += _check(none.is_empty(), "a threshold above every vertex clips away the whole triangle")

	# threshold 0.5 excludes exactly one vertex (the val=0.0 corner) -- cutting
	# one vertex off a triangle always produces a quad (the 2 remaining
	# original vertices plus 2 interpolated crossing points), never a triangle.
	var above_half := PlumeOverlay._clip(triangle, 0.5, true)
	f += _check(above_half.size() == 4,
		"clipping one vertex off a triangle produces a quad: the 2 untouched vertices plus 2 interpolated crossing points")
	for v in above_half:
		f += _check(v["val"] >= 0.5 - 0.001, "every surviving vertex (original or interpolated) satisfies the kept half-plane")

	# The band [0.5, 1.5] keeps the val=1.0 vertex itself (it's inside the
	# band) AND both cuts land on the same original edge (val=0 -> val=2 spans
	# the whole range), so this band is a pentagon, not a quad: cut-on-AB,
	# vertex B, cut-on-BC, cut-on-CA (upper), cut-on-CA (lower).
	var band: Array = PlumeOverlay._clip(PlumeOverlay._clip(triangle, 0.5, true), 1.5, false)
	f += _check(band.size() == 5, "a band that retains a middle vertex and double-crosses one edge clips to a pentagon")
	for v in band:
		f += _check(v["val"] >= 0.5 - 0.001 and v["val"] <= 1.5 + 0.001, "every vertex of a doubly-clipped band lies within [lo, hi]")

	return f

## The dedup key _draw() uses so a lattice triangle shared by 3 cells is only
## ever filled once (unlike head_contour_overlay's lines, a filled polygon
## drawn twice over itself visibly double-darkens) -- confirms the key is the
## same regardless of which of the 3 corners it's computed from.
func _test_plume_overlay_triangle_key_order_independent() -> int:
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(0, 1)
	var f := 0
	f += _check(PlumeOverlay._triangle_key(a, b, c) == PlumeOverlay._triangle_key(b, c, a),
		"triangle key doesn't depend on which corner it's computed from (rotation)")
	f += _check(PlumeOverlay._triangle_key(a, b, c) == PlumeOverlay._triangle_key(c, b, a),
		"triangle key doesn't depend on winding direction")
	f += _check(PlumeOverlay._triangle_key(a, b, c) != PlumeOverlay._triangle_key(a, b, Vector2i(2, 2)),
		"different triangles get different keys")
	return f

## _union_polygons() has to actually merge touching pieces into one connected
## boundary (Chaikin smoothing only makes sense on a single closed loop) while
## leaving genuinely disjoint pieces alone -- both directions checked
## directly, since a bug that silently left everything separate (or
## over-merged everything into one) wouldn't be obvious from a screenshot.
func _test_plume_overlay_union_polygons() -> int:
	var f := 0

	# Two right triangles sharing the edge (10,0)-(10,10) -- together they
	# exactly form the 10x10 square [0,10]x[0,10].
	var tri_a := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var tri_b := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(0, 10)])
	var touching := PlumeOverlay._union_polygons([tri_a, tri_b])
	f += _check(touching.size() == 1, "two triangles sharing an edge merge into a single connected polygon")

	# Two triangles nowhere near each other.
	var tri_c := PackedVector2Array([Vector2(1000, 1000), Vector2(1010, 1000), Vector2(1010, 1010)])
	var tri_d := PackedVector2Array([Vector2(-1000, -1000), Vector2(-990, -1000), Vector2(-990, -990)])
	var disjoint := PlumeOverlay._union_polygons([tri_c, tri_d])
	f += _check(disjoint.size() == 2, "two triangles that never touch stay as 2 separate polygons, not forced into 1")

	# A piece that bridges two otherwise-separate blobs should fold all 3
	# into a single polygon, not just merge with whichever it's tested
	# against first.
	var bridge := PackedVector2Array([Vector2(10, 0), Vector2(20, 0), Vector2(20, 10), Vector2(10, 10)])
	var far := PackedVector2Array([Vector2(20, 0), Vector2(30, 0), Vector2(30, 10), Vector2(20, 10)])
	var bridged := PlumeOverlay._union_polygons([tri_a, tri_b, bridge, far])
	f += _check(bridged.size() == 1, "a piece touching two separate blobs merges all of them into one connected polygon")

	# Direct regression test for the user's reported bug (2026-10-21): "the
	# plume seems to be breaking up into smaller ellipses." Root cause: an
	# earlier version of _union_polygons swept the input exactly ONCE, so a
	# piece that only touches the growing region through a LATER piece in the
	## input order was permanently judged "doesn't touch" and wrongly split
	# off as its own separate polygon, even though the true region is one
	# connected chain. A, B, C here are 3 squares in a row (A-B touch, B-C
	# touch, A and C do NOT touch each other directly) fed in the specific
	# order [A, C, B] that exposed the bug -- C is tested before B (the only
	# thing connecting it) has been merged in.
	var chain_a := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var chain_b := PackedVector2Array([Vector2(10, 0), Vector2(20, 0), Vector2(20, 10), Vector2(10, 10)])
	var chain_c := PackedVector2Array([Vector2(20, 0), Vector2(30, 0), Vector2(30, 10), Vector2(20, 10)])
	var chained := PlumeOverlay._union_polygons([chain_a, chain_c, chain_b])
	f += _check(chained.size() == 1,
		"a 3-piece chain merges into 1 polygon even when fed in an order where the connecting middle piece comes last")

	return f

## Lattice-topology edge key _build_adjacency uses to find which triangles
## share a full edge -- order-independent for the same reason _triangle_key
## is (an edge (a, b) must hash the same as (b, a)).
func _test_plume_overlay_edge_key_order_independent() -> int:
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var f := 0
	f += _check(PlumeOverlay._edge_key(a, b) == PlumeOverlay._edge_key(b, a), "edge key doesn't depend on argument order")
	f += _check(PlumeOverlay._edge_key(a, b) != PlumeOverlay._edge_key(a, Vector2i(2, 2)), "different edges get different keys")
	return f

## _build_adjacency connects two triangles that genuinely share 2 of their 3
## corner cells (a real lattice edge), and does NOT connect two triangles
## that merely share a single corner cell (no shared edge) -- the graph
## _band_loops walks to group a band's triangles before folding them, so a
## wrong edge here would either wrongly fuse unrelated regions or (the
## reported bug) fail to connect pieces that really are one region.
func _test_plume_overlay_build_adjacency() -> int:
	# Two triangles sharing the edge (1,0)-(0,1): {(0,0),(1,0),(0,1)} and
	# {(1,0),(0,1),(1,1)}.
	var tri_a := {"axials": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]}
	var tri_b := {"axials": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]}
	# A third triangle sharing only the single corner cell (0,0) with tri_a,
	# no full edge.
	var tri_c := {"axials": [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1)]}

	var overlay := PlumeOverlay.new()
	var adjacency: Array = overlay._build_adjacency([tri_a, tri_b, tri_c])
	overlay.free()

	var f := 0
	f += _check(adjacency[0].has(1), "triangles sharing a real lattice edge are adjacent")
	f += _check(adjacency[1].has(0), "adjacency is symmetric")
	f += _check(not adjacency[0].has(2), "triangles sharing only a single corner (no full edge) are NOT adjacent")
	return f

## Chaikin corner-cutting: confirms each pass doubles the vertex count
## (standard behavior for a closed loop), that no surviving point sits
## exactly on an original sharp corner (the whole point -- corners get CUT,
## not kept), and that the smoothed loop never leaves the original polygon's
## bounding box (corner-cutting on a convex shape can only move points
## inward, never outward/overshoot).
func _test_plume_overlay_chaikin_smooth() -> int:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var f := 0

	var once: PackedVector2Array = PlumeOverlay._chaikin_smooth(square, 1)
	f += _check(once.size() == square.size() * 2, "one Chaikin pass doubles the vertex count of a closed loop")

	var corner_survives := false
	for p in once:
		for c in square:
			if p.is_equal_approx(c):
				corner_survives = true
	f += _check(not corner_survives, "no smoothed point sits exactly on an original sharp corner -- the corner got cut off")

	var twice: PackedVector2Array = PlumeOverlay._chaikin_smooth(square, 2)
	f += _check(twice.size() == square.size() * 4, "a second Chaikin pass doubles the vertex count again")
	var all_inside_bounds := true
	for p in twice:
		if p.x < -0.001 or p.x > 10.001 or p.y < -0.001 or p.y > 10.001:
			all_inside_bounds = false
	f += _check(all_inside_bounds, "corner-cutting a convex polygon never produces a point outside its original bounding box")

	f += _check(PlumeOverlay._chaikin_smooth(square, 0).size() == square.size(),
		"0 iterations returns the input unchanged -- smoothing_iterations = 0 is a real off switch")

	return f

## _dedupe_points: collapses near-duplicate consecutive points (including the
## wrap-around closing edge), which is the most common cause of a degenerate
## polygon that fails Godot's triangulator (see the "indented plume edges"
## fix, 2026-10-22).
func _test_plume_overlay_dedupe_points() -> int:
	var f := 0

	var with_dupe := PackedVector2Array([Vector2(0, 0), Vector2(0, 0.001), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var deduped: PackedVector2Array = PlumeOverlay._dedupe_points(with_dupe)
	f += _check(deduped.size() == 4, "a near-duplicate consecutive point collapses away")

	var wrap_dupe := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10), Vector2(0.001, 0.001)])
	var wrap_deduped: PackedVector2Array = PlumeOverlay._dedupe_points(wrap_dupe)
	f += _check(wrap_deduped.size() == 4, "a point that nearly coincides with the FIRST point (wrap-around) also collapses away")

	var clean_square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var unchanged: PackedVector2Array = PlumeOverlay._dedupe_points(clean_square)
	f += _check(unchanged.size() == 4, "a polygon with no near-duplicate points is left unchanged")

	return f

## _triangulates: mirrors the exact check Godot's own renderer does before
## draw_colored_polygon fills a shape, so this fix can catch a degenerate
## polygon BEFORE it reaches the renderer (and silently fails to draw,
## logging "Invalid polygon data, triangulation failed.") instead of after.
func _test_plume_overlay_triangulates() -> int:
	var f := 0

	var simple_triangle := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(5, 10)])
	f += _check(PlumeOverlay._triangulates(simple_triangle), "a simple, non-degenerate triangle triangulates fine")

	var too_few_points := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	f += _check(not PlumeOverlay._triangulates(too_few_points), "fewer than 3 points can never triangulate")

	# A degenerate "bowtie" self-intersecting quad (crossed edges) -- the
	# kind of shape Geometry2D.merge_polygons or Chaikin smoothing on a tight
	# concave notch can occasionally produce.
	var bowtie := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
	f += _check(not PlumeOverlay._triangulates(bowtie), "a self-intersecting (bowtie) polygon fails triangulation, as the real renderer would reject it too")

	return f

## The turn loop (brief SS8 Phase 1 step 6: "Add Next Turn (Space), turn
## counter... "): confirms _advance_turn() actually substeps GridModel's
## transport (the user's "should not just jump from cell to cell" ask is
## already satisfied at the GridModel level -- _test_grid_model_transport_*
## covers that), increments the turn counter, and that the substep loop
## itself still conserves mass exactly, not just a single step_transport()
## call in isolation.
func _test_world_turn_advance_transport() -> int:
	var f := 0
	var world := World.new()
	world.minimal_test_mode = false
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	var plume_node := Node2D.new() # stand-in for PlumeOverlay -- only .queue_redraw() is called on it
	world.add_child(ground_node)
	world.add_child(features_node)
	world.add_child(plume_node)
	world.ground = ground_node
	world.features = features_node
	world.plume_overlay = plume_node
	world._build_tileset()
	world._model = GridModel.new(world.radius)
	var bounds: Vector2 = world._model.elevation_range()
	world._elevation_lo = bounds.x
	world._elevation_hi = bounds.y
	world._river_cells.clear()
	world._seed_initial_contamination()
	world._build_terrain()
	world._build_features()

	f += _check(world._model.total_mass_kg() == world.source_mass_kg,
		"the scenario seeds source_mass_kg at source_axial on start")

	var initial_turn: int = world.turn
	world._advance_turn()
	f += _check(world.turn == initial_turn + 1, "_advance_turn() increments the turn counter")
	# NOT a strict before/after equality any more: source_leak_rate_kg_s (the
	# brief's own "continuing release" source behavior, step 7) adds mass
	# every substep, and well_pumping_rate_m3_s (the capture well) can remove
	# some. The strong invariant that must still hold is domain + escaped +
	# captured == everything ever seeded, substep loop included, not just a
	# single step_transport() call.
	f += _check(is_equal_approx(world._model.total_mass_kg() + world._model.escaped_mass_kg + world._model.captured_mass_kg, world._total_seeded_mass_kg),
		"advancing a turn conserves mass in the strong sense: in-domain + escaped + captured == everything ever seeded (including the continuing leak)")

	world.free()
	return f

## Brief SS8 Phase 1 step 6's remaining piece: a Reset that replays the same
## scenario from turn 0, so trying a different approach doesn't require
## relaunching the whole game. Confirms it actually returns turn/mass to
## scenario start, re-seeds the source (not leaves the map empty), and keeps
## the mass-balance invariant (in-domain + escaped + captured == seeded total) intact
## throughout -- not just after a fresh _ready(), but also after it's been
## called a second time following more simulated progress.
func _test_world_reset_scenario() -> int:
	var f := 0
	var world := World.new()
	world.minimal_test_mode = false
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	var flow_node := Node2D.new()
	var plume_node := Node2D.new()
	world.add_child(ground_node)
	world.add_child(features_node)
	world.add_child(flow_node)
	world.add_child(plume_node)
	world.ground = ground_node
	world.features = features_node
	world.flow_overlay = flow_node
	world.plume_overlay = plume_node
	world._build_tileset()
	world._model = GridModel.new(world.radius)
	var bounds: Vector2 = world._model.elevation_range()
	world._elevation_lo = bounds.x
	world._elevation_hi = bounds.y
	world._river_cells.clear()
	world._seed_initial_contamination()
	world._build_terrain()
	world._build_features()

	for i in range(5):
		world._advance_turn()
	f += _check(world.turn == 5, "sanity check: turns actually advanced before reset")

	world.reset_scenario()

	f += _check(world.turn == 0, "reset_scenario returns the turn counter to 0")
	f += _check(is_equal_approx(world._model.total_mass_kg(), world.source_mass_kg),
		"reset_scenario re-seeds source_mass_kg at source_axial, same as scenario start")
	f += _check(world._model.escaped_mass_kg == 0.0, "reset_scenario clears escaped_mass_kg")
	f += _check(is_equal_approx(world._total_seeded_mass_kg, world.source_mass_kg),
		"reset_scenario's own re-seed is tracked exactly once, not accumulated on top of the pre-reset seed")

	world._advance_turn()
	f += _check(is_equal_approx(world._model.total_mass_kg() + world._model.escaped_mass_kg + world._model.captured_mass_kg, world._total_seeded_mass_kg),
		"mass-balance invariant (in-domain + escaped + captured == seeded total) still holds after resetting and advancing again")

	world.free()
	return f

## The user's ask: terrain was obscuring the plume cloud, so x-ray mode must
## actually hide Ground/Features, and -- since its whole point is showing
## the subsurface data -- force FlowOverlay/PlumeOverlay visible regardless
## of whatever they were set to beforehand (Inspector default or a prior
## F-key toggle), then restore that exact prior state on exit rather than
## just leaving them forced on.
func _test_world_xray_mode() -> int:
	var f := 0
	var world := World.new()
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	var flow_node := Node2D.new()
	var plume_node := Node2D.new()
	var geology_node := Node2D.new()
	var contour_node := Node2D.new()
	world.add_child(ground_node)
	world.add_child(features_node)
	world.add_child(flow_node)
	world.add_child(plume_node)
	world.add_child(geology_node)
	world.add_child(contour_node)
	world.ground = ground_node
	world.features = features_node
	world.flow_overlay = flow_node
	world.plume_overlay = plume_node
	world.geology_overlay = geology_node
	world.head_contour_overlay = contour_node

	flow_node.visible = false # simulate the player having toggled flow arrows off with F beforehand
	geology_node.visible = false # x-ray-only overlays start hidden, same as plume
	contour_node.visible = false

	world.set_xray_mode(true)
	f += _check(not ground_node.visible and not features_node.visible,
		"x-ray mode hides Ground and Features")
	f += _check(flow_node.visible and plume_node.visible,
		"x-ray mode forces FlowOverlay visible regardless of its prior state, and shows PlumeOverlay (its ONLY visible context -- see below)")
	f += _check(geology_node.visible and contour_node.visible,
		"x-ray mode also shows the geology-fill and head-contour overlays (the user's 2026-10-21 ask)")

	world.set_xray_mode(false)
	f += _check(ground_node.visible and features_node.visible,
		"leaving x-ray mode restores Ground and Features")
	f += _check(not flow_node.visible,
		"leaving x-ray mode restores FlowOverlay's prior (pre-x-ray) visibility rather than forcing it back on")
	f += _check(not plume_node.visible,
		"the user's ask (2026-10-21): the plume cloud must NEVER show on the surface view, only in x-ray -- unlike FlowOverlay, there is no 'prior state' to restore, leaving x-ray always hides it")
	f += _check(not geology_node.visible and not contour_node.visible,
		"geology-fill and head-contour overlays are x-ray-exclusive too -- hidden again on leaving x-ray")

	world.free()
	return f

## User's ask: holding Space should keep advancing turns, not require a
## fresh press every time. _advance_hold_timer is the pure repeat-timing
## logic split from _process() specifically because Input.is_key_pressed()
## reads real OS input state that a headless test script can't drive --
## `held` is passed in directly here instead.
func _test_world_hold_to_repeat_timer() -> int:
	var world := World.new()
	world.turn_hold_repeat_delay_s = 0.4
	world.turn_hold_repeat_interval_s = 0.1
	var f := 0

	f += _check(not world._advance_hold_timer(false, 0.016), "not holding Space never fires a repeat")

	var fired_before_delay := false
	for i in range(7): # 7 * 0.05 = 0.35s, still under the 0.4s delay
		if world._advance_hold_timer(true, 0.05):
			fired_before_delay = true
	f += _check(not fired_before_delay, "holding Space for less than turn_hold_repeat_delay_s fires no repeat yet")

	f += _check(world._advance_hold_timer(true, 0.1),
		"holding Space past turn_hold_repeat_delay_s fires the first repeat") # elapsed now 0.45s

	f += _check(not world._advance_hold_timer(true, 0.04),
		"part-way through turn_hold_repeat_interval_s after a repeat fires nothing yet") # elapsed now 0.49s
	f += _check(world._advance_hold_timer(true, 0.06),
		"finishing turn_hold_repeat_interval_s after that fires the next repeat") # elapsed now 0.55s, past the 0.5s threshold

	world._advance_hold_timer(false, 0.016)
	f += _check(world._space_hold_elapsed == 0.0 and world._space_next_repeat_at == world.turn_hold_repeat_delay_s,
		"releasing Space resets the hold timer back to its initial delay")

	world.free()
	return f

## User report: changing a geology K/porosity value in the Inspector WHILE
## PLAYING appeared to do nothing -- clay raised to its slider maximum still
## showed "similar behaviour". Root cause: _model was built once at
## _ready() and never revisited, so a later export edit changed the
## variable but nothing ever pushed it into the already-running GridModel
## (neither transport nor the flow-arrow overlay could possibly reflect it).
## Confirms the fix directly: assigning World.clay_k_m_s after _model
## already exists (simulating a live Inspector edit) immediately updates
## the running model's K, with no restart.
func _test_world_geology_setter_refreshes_live_model() -> int:
	var f := 0
	var world := World.new()
	world._model = GridModel.new(world.radius)
	var clay_axial := Vector2i(0, 0)

	f += _check(world._model.get_k(clay_axial) != 1.0e-5,
		"sanity check: the model doesn't already have the test value before the change")

	world.clay_k_m_s = 1.0e-5 # simulates editing the Inspector while the scene is running

	f += _check(world._model.get_k(clay_axial) == 1.0e-5,
		"setting World.clay_k_m_s while _model already exists immediately updates the running model's K")

	world.free()
	return f

## Same live-tuning guarantee, for the Gate C diffusion coefficient exports.
func _test_world_diffusion_setter_refreshes_live_model() -> int:
	var f := 0
	var world := World.new()
	world._model = GridModel.new(world.radius)
	var clay_axial := Vector2i(0, 0)

	f += _check(world._model.get_diffusion_m2_s(clay_axial) != 2.0e-9,
		"sanity check: the model doesn't already have the test value before the change")

	world.clay_diffusion_m2_s = 2.0e-9 # simulates editing the Inspector while the scene is running

	f += _check(world._model.get_diffusion_m2_s(clay_axial) == 2.0e-9,
		"setting World.clay_diffusion_m2_s while _model already exists immediately updates the running model's diffusion coefficient")

	world.free()
	return f

## Same live-tuning guarantee as _test_world_geology_setter_refreshes_live_model,
## for the capture well's own exports -- an Inspector edit to well_axial or
## well_pumping_rate_m3_s made while playing must reach the running GridModel
## immediately, not just at the next restart.
func _test_world_well_setter_refreshes_live_model() -> int:
	var f := 0
	var world := World.new()
	world._model = GridModel.new(world.radius)

	f += _check(world._model.well_pumping_rate_m3_s != 0.03,
		"sanity check: the model doesn't already have the test rate before the change")

	world.well_axial = Vector2i(0, 4) # simulates editing the Inspector while the scene is running
	world.well_pumping_rate_m3_s = 0.03

	f += _check(world._model.well_axial == Vector2i(0, 4) and world._model.well_pumping_rate_m3_s == 0.03,
		"setting World.well_axial/well_pumping_rate_m3_s while _model already exists immediately updates the running model")

	world.free()
	return f

## Brief SS8 Phase 1 step 7: "...one source behavior that keeps threatening
## the receptor without player input (e.g. a continuing release from the
## source)". Confirms the leak actually adds mass over a turn (not just the
## one-time seed), and that it's folded into the SAME conservation invariant
## as everything else -- not some separate, untracked channel that would let
## mass quietly appear from nowhere.
func _test_world_continuing_source_leak() -> int:
	var f := 0
	var world := World.new()
	world.minimal_test_mode = false
	world.source_leak_rate_kg_s = 1.0e-5
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	var plume_node := Node2D.new()
	world.add_child(ground_node)
	world.add_child(features_node)
	world.add_child(plume_node)
	world.ground = ground_node
	world.features = features_node
	world.plume_overlay = plume_node
	world._build_tileset()
	world._model = GridModel.new(world.radius)
	var bounds: Vector2 = world._model.elevation_range()
	world._elevation_lo = bounds.x
	world._elevation_hi = bounds.y
	world._river_cells.clear()
	world._seed_initial_contamination()
	world._build_terrain()
	world._build_features()

	var seeded_after_start: float = world._total_seeded_mass_kg
	f += _check(seeded_after_start == world.source_mass_kg,
		"sanity check: only the one-time seed has been tracked before any turn runs")

	world._advance_turn()

	f += _check(world._total_seeded_mass_kg > seeded_after_start,
		"a turn with source_leak_rate_kg_s > 0 adds more seeded mass -- the source keeps threatening without player input")
	f += _check(is_equal_approx(world._model.total_mass_kg() + world._model.escaped_mass_kg + world._model.captured_mass_kg, world._total_seeded_mass_kg),
		"the leaked mass is tracked in the SAME conservation invariant as everything else, not a separate untracked channel")

	world.free()
	return f

## Brief SS8 Phase 1 step 7's two new scenario markers: confirms exactly one
## of each is placed, at the correct axial, and that source_axial/well_axial
## never ALSO get an ordinary procedural tree/rock/decal (the ground truth a
## player reads the map by must not be ambiguous about where the source and
## the well actually are).
func _test_world_scenario_markers_placed() -> int:
	var f := 0
	var world = _make_world()

	var barrel_roots: Array = []
	var well_roots: Array = []
	for root in world.features.get_children():
		if root.get_meta("kind", "") != "scenario":
			continue
		var sprite: Sprite2D = root.get_child(0)
		if sprite.texture == World.CONTAMINATION_BARREL:
			barrel_roots.append(root)
		elif sprite.texture == World.WELL_ABSTRACTION:
			well_roots.append(root)

	f += _check(barrel_roots.size() == 1, "exactly one contamination-barrel marker is placed")
	f += _check(well_roots.size() == 1, "exactly one capture-well marker is placed")
	if barrel_roots.size() == 1:
		f += _check(barrel_roots[0].get_meta("axial") == world.source_axial, "the barrel marker sits at source_axial")
	if well_roots.size() == 1:
		f += _check(well_roots[0].get_meta("axial") == world.well_axial, "the well marker sits at well_axial")

	var ordinary_feature_at_source := false
	var ordinary_feature_at_well := false
	for root in world.features.get_children():
		var kind: String = root.get_meta("kind", "")
		if kind != "feature" and kind != "decal":
			continue
		var axial: Vector2i = root.get_meta("axial")
		if axial == world.source_axial:
			ordinary_feature_at_source = true
		if axial == world.well_axial:
			ordinary_feature_at_well = true
	f += _check(not ordinary_feature_at_source and not ordinary_feature_at_well,
		"source_axial/well_axial never also get an ordinary tree/rock/decal (no double-dressing)")

	world.free()
	return f

## Brief SS8 Phase 1 step 8's receptor target: confirms exactly one lake
## marker is placed, at receptor_axial, and that cell never ALSO gets an
## ordinary procedural tree/rock/decal -- same "no double-dressing" rule the
## source/well markers already follow.
func _test_world_receptor_marker_placed() -> int:
	var f := 0
	var world = _make_world()

	var receptor_roots: Array = []
	for root in world.features.get_children():
		if root.get_meta("kind", "") != "scenario":
			continue
		var sprite: Sprite2D = root.get_child(0)
		if sprite.texture == World.RECEPTOR_LAKE:
			receptor_roots.append(root)

	f += _check(receptor_roots.size() == 1, "exactly one receptor-lake marker is placed")
	if receptor_roots.size() == 1:
		f += _check(receptor_roots[0].get_meta("axial") == world.receptor_axial, "the receptor marker sits at receptor_axial")

	var ordinary_feature_at_receptor := false
	for root in world.features.get_children():
		var kind: String = root.get_meta("kind", "")
		if kind != "feature" and kind != "decal":
			continue
		if root.get_meta("axial") == world.receptor_axial:
			ordinary_feature_at_receptor = true
	f += _check(not ordinary_feature_at_receptor,
		"receptor_axial never also gets an ordinary tree/rock/decal (no double-dressing)")

	world.free()
	return f

## Brief SS8 Phase 1 step 8: "win... rules" -- surviving max_turns without the
## receptor ever crossing its threshold wins the scenario, and the game
## actually stops advancing once won (Space/hold-repeat becomes a harmless
## no-op rather than quietly running turns past the stated budget).
## source_leak_rate_kg_s is disabled here specifically to isolate the TIMING
## rule being tested from whether the default receptor/leak/well placements
## happen to intersect -- that interaction is this project's own tuning, not
## what this test is checking.
func _test_world_win_condition() -> int:
	var f := 0
	var world := World.new()
	world.minimal_test_mode = false
	world.max_turns = 3
	world.source_leak_rate_kg_s = 0.0
	var ground_node := TileMapLayer.new()
	var features_node := Node2D.new()
	var plume_node := Node2D.new()
	world.add_child(ground_node)
	world.add_child(features_node)
	world.add_child(plume_node)
	world.ground = ground_node
	world.features = features_node
	world.plume_overlay = plume_node
	world._build_tileset()
	world._model = GridModel.new(world.radius)
	var bounds: Vector2 = world._model.elevation_range()
	world._elevation_lo = bounds.x
	world._elevation_hi = bounds.y
	world._river_cells.clear()
	world._seed_initial_contamination()
	world._build_terrain()
	world._build_features()

	for i in range(world.max_turns):
		world._advance_turn()
	f += _check(world.game_state == World.GameState.WON,
		"surviving max_turns without the receptor crossing its threshold wins the scenario")

	world._advance_turn()
	f += _check(world.turn == world.max_turns,
		"advancing a turn after the game is already won is a no-op -- the turn counter doesn't keep climbing past the budget")

	world.free()
	return f

## Brief SS8 Phase 1 step 8: "...loss rules" -- the receptor's concentration
## crossing its own threshold (independent of contamination_full_scale_kg_m3,
## see receptor_contamination_threshold_kg_m3's doc comment) loses the
## scenario. Seeds mass directly at receptor_axial and calls _check_win_loss()
## directly -- same spirit as testing other pure per-turn logic (e.g.
## _advance_hold_timer) without needing transport to actually carry a plume
## there first.
func _test_world_loss_condition() -> int:
	var f := 0
	var world := World.new()
	world._model = GridModel.new(world.radius)
	world.receptor_contamination_threshold_kg_m3 = 0.001

	f += _check(world.game_state == World.GameState.PLAYING, "sanity check: a fresh World starts in the PLAYING state")

	world._model.seed_mass_kg(world.receptor_axial, 1000.0) # comfortably clears the low threshold above
	world._check_win_loss()

	f += _check(world.game_state == World.GameState.LOST,
		"the receptor's concentration crossing its threshold loses the scenario")

	world.free()
	return f

## Brief SS8 Phase 1 step 8: "a short on-screen explanation of each turn" --
## confirms the status text actually reports the receptor's reading as a
## percentage of its limit, names the turn/turn-budget, reflects a rising
## trend once the reading increases between two calls, and switches to a
## plain win/loss banner once the game has ended.
func _test_world_status_label_text() -> int:
	var f := 0
	var world := World.new()
	world._model = GridModel.new(world.radius)
	world._status_label = Label.new()
	world.receptor_contamination_threshold_kg_m3 = 0.03
	world.max_turns = 10
	world.turn = 4

	world._refresh_status_label()
	f += _check(world._status_label.text.contains("0.0%"),
		"an uncontaminated receptor reads 0.0% of the limit in the per-turn status text")
	f += _check(world._status_label.text.contains("Turn 4 of 10"), "status text names the current turn and the turn budget")

	world._model.seed_mass_kg(world.receptor_axial, 100.0)
	world._refresh_status_label()
	f += _check(world._status_label.text.contains("rising"),
		"a receptor reading that increased since the last call reports as rising")

	world.game_state = World.GameState.WON
	world._refresh_status_label()
	f += _check(world._status_label.text.contains("SAFE"), "a won game's status text reads as a win banner")

	world.game_state = World.GameState.LOST
	world._refresh_status_label()
	f += _check(world._status_label.text.contains("FAILED"), "a lost game's status text reads as a loss banner")

	world.free()
	return f

## User's ask (2026-10-21): "add geology into xray view, simple cell fill
## colour and legend of the 3 types." The fill (geology_overlay.gd) and the
## legend (World._build_xray_legend) both read GridModel.GEOLOGY_COLOR --
## confirms every Geology enum value actually has an entry, so a future 4th
## geology can't silently fall through to the overlay's MAGENTA fallback (or
## be missing from the legend) without this test catching it.
func _test_geology_overlay_colors_cover_all_geologies() -> int:
	var f := 0
	var all_covered := true
	for geo in [GridModel.Geology.SAND, GridModel.Geology.SILT, GridModel.Geology.CLAY]:
		if not GridModel.GEOLOGY_COLOR.has(geo):
			all_covered = false
		if not GridModel.GEOLOGY_NAME.has(geo):
			all_covered = false
	f += _check(all_covered, "every Geology enum value has both a GEOLOGY_COLOR entry (the x-ray fill) and a GEOLOGY_NAME entry (the legend label)")
	return f

## User's follow-up ask (2026-10-21): the first version's contour lines ran
## along hex cell edges and looked "blocky" -- replaced with proper
## "marching triangles" contouring over the hex-center lattice (see
## head_contour_overlay.gd's header comment). _TRIANGLE_OFFSETS is a
## hand-derived list whose consecutive pairs are meant to each be mutually
## 1-hex-step adjacent (so cell + offset[k] + offset[k+1] really are 3
## mutually-adjacent cells forming one small triangle) -- exactly the kind
## of claim that caused a real bug earlier in this project (GridOutline's
## own shore-edge derivation needed an identical geometric check,
## grid_outline.gd's _test_grid_outline_shore_edges). Confirmed directly via
## HexMath.axial_distance, not just asserted.
func _test_head_contour_overlay_triangle_offsets_are_mutually_adjacent() -> int:
	var f := 0
	var offsets := HeadContourOverlay._TRIANGLE_OFFSETS
	var all_adjacent := true
	for k in range(offsets.size()):
		if HexMath.axial_distance(offsets[k], offsets[(k + 1) % offsets.size()]) != 1:
			all_adjacent = false
	f += _check(all_adjacent,
		"every consecutive pair of _TRIANGLE_OFFSETS is exactly 1 hex-step apart -- cell + offset[k] + offset[k+1] are genuinely 3 mutually-adjacent cells, a valid lattice triangle")
	return f

## _triangle_crossing is the pure "marching triangles" primitive behind every
## line this overlay draws. A simple right-triangle with a known linear head
## field (h=0 at the origin corner, h=10 along both other corners) crossed at
## level=5 should intersect exactly the two edges touching the h=0 corner, at
## their exact midpoints (t=0.5 each, since the field is linear and
## symmetric here) -- confirms interpolation, not just that SOMETHING is
## returned. Also confirms a level entirely above or below every vertex
## produces no crossing at all (the common case for most triangles most of
## the time, since a legible contour map shouldn't draw a line through every
## triangle).
func _test_head_contour_overlay_triangle_crossing() -> int:
	var f := 0
	var positions := [Vector2(0, 0), Vector2(10, 0), Vector2(0, 10)]
	var heads := [0.0, 10.0, 10.0]

	var crossing: Array = HeadContourOverlay._triangle_crossing(positions, heads, 5.0)
	f += _check(crossing.size() == 2, "a level strictly between the triangle's min and max head produces exactly 2 crossing points")
	var has_5_0 := false
	var has_0_5 := false
	for p in crossing:
		if (p as Vector2).is_equal_approx(Vector2(5, 0)):
			has_5_0 = true
		if (p as Vector2).is_equal_approx(Vector2(0, 5)):
			has_0_5 = true
	f += _check(has_5_0 and has_0_5,
		"the crossing points sit at the exact linear-interpolation midpoints of the two edges touching the h=0 corner")

	f += _check(HeadContourOverlay._triangle_crossing(positions, heads, 20.0).is_empty(),
		"a level above every vertex's head produces no crossing")
	f += _check(HeadContourOverlay._triangle_crossing(positions, heads, -1.0).is_empty(),
		"a level below every vertex's head produces no crossing")
	return f

## User's ask (2026-10-21): "why such weird values... why not on full
## numbers" -- the raw head-range/target_contour_count interval (e.g.
## 2.97m) produced contour labels like 32.7, 29.7, 26.8m instead of a usable
## reference scale. _nice_interval rounds UP to the next "nice" number (1, 2
## or 5 times a power of 10), the same convention real chart/contour-map
## axis ticks use -- confirms known raw -> nice mappings, that an
## already-nice value maps to itself (idempotent, so _current_interval_m()
## can apply it unconditionally), and that it always rounds UP (never
## produces MORE than target_contour_count levels across the range, only
## ever fewer/coarser).
func _test_head_contour_overlay_nice_interval() -> int:
	var f := 0
	f += _check(is_equal_approx(HeadContourOverlay._nice_interval(2.97), 5.0), "2.97 (this project's own reported case) rounds up to 5.0")
	f += _check(is_equal_approx(HeadContourOverlay._nice_interval(1.5), 2.0), "1.5 rounds up to 2.0")
	f += _check(is_equal_approx(HeadContourOverlay._nice_interval(3.0), 5.0), "3.0 rounds up to 5.0")
	f += _check(is_equal_approx(HeadContourOverlay._nice_interval(7.0), 10.0), "7.0 rounds up to 10.0")
	f += _check(is_equal_approx(HeadContourOverlay._nice_interval(25.0), 50.0), "25.0 rounds up to 50.0 (scales correctly above 10)")
	f += _check(is_equal_approx(HeadContourOverlay._nice_interval(0.037), 0.05), "0.037 rounds up to 0.05 (scales correctly below 1)")

	var already_nice: Array[float] = [1.0, 2.0, 5.0, 10.0, 0.5, 20.0]
	var all_idempotent := true
	for n in already_nice:
		if not is_equal_approx(HeadContourOverlay._nice_interval(n), n):
			all_idempotent = false
	f += _check(all_idempotent, "an already-nice value maps to itself")

	f += _check(HeadContourOverlay._nice_interval(2.97) >= 2.97, "the rounded interval is never smaller than the raw value -- never more levels than requested, only fewer/coarser")
	return f

## Confirms _current_interval_m() actually auto-scales to the model's real
## head range (brief section 4's "learning aid" is useless if a fixed
## meters-per-level constant silently stops working the moment K/well tuning
## changes the scenario's head range -- see head_contour_overlay.gd's own
## doc comment for the exact bug this replaced), and that a well's drawdown
## still produces MORE contour crossings in its immediate vicinity than an
## equally sized patch of the map far from any well -- the "tightly spaced
## contour lines read as a steep local gradient, i.e. a drawdown cone" claim,
## checked numerically against the actual triangle-crossing machinery
## _draw() uses (dummy positions: existence of a crossing doesn't depend on
## WHERE it's drawn, only on the head values either side of a level).
func _test_head_contour_overlay_drawdown() -> int:
	var f := 0
	var overlay := HeadContourOverlay.new()
	var model := GridModel.new(8)
	model.set_well(Vector2i(0, 3), 0.05)
	overlay._cells = HexMath.cells_in_radius(8)
	overlay._model = model

	var narrow_interval: float = overlay._current_interval_m()
	overlay.target_contour_count = overlay.target_contour_count * 4
	var fine_interval: float = overlay._current_interval_m()
	# NOT exact 4x proportionality any more: both are rounded to the nearest
	# "nice" number (_nice_interval) first, so halving/quartering the raw
	# value doesn't necessarily land on an exact fraction of the other nice
	# value. What must still hold: asking for MORE levels (finer target)
	# never produces a COARSER interval, and both results are themselves
	# already-nice (rounding one again is a no-op).
	f += _check(fine_interval <= narrow_interval,
		"_current_interval_m() never gets coarser when target_contour_count increases, for the same head range")
	f += _check(is_equal_approx(HeadContourOverlay._nice_interval(narrow_interval), narrow_interval)
			and is_equal_approx(HeadContourOverlay._nice_interval(fine_interval), fine_interval),
		"_current_interval_m() always returns an already-nice value (re-rounding it is a no-op)")
	overlay.target_contour_count = int(overlay.target_contour_count / 4)

	var interval: float = overlay._current_interval_m()
	f += _check(interval > 0.0 and is_finite(interval), "the auto-computed interval is finite and positive for a real, varying head field")

	var crossings_near_well := _count_triangle_crossings(model, interval, Vector2i(0, 3), 1)
	var crossings_far_from_well := _count_triangle_crossings(model, interval, Vector2i(0, -6), 1)
	f += _check(crossings_near_well > crossings_far_from_well,
		"a small patch of cells immediately around the pumping well shows more contour-triangle crossings than an equally sized patch far from it -- a real drawdown cone, not just a uniform regional gradient")

	overlay.free()
	return f

## Total number of (triangle, level) crossings among cells within `radius`
## hex-steps of `center_cell` -- the same loop head_contour_overlay.gd's
## _draw() runs, minus the actual draw call (dummy Vector2.ZERO positions,
## since whether a crossing EXISTS depends only on head values, not where
## it's drawn).
func _count_triangle_crossings(model: GridModel, interval: float, center_cell: Vector2i, radius: int) -> int:
	var count := 0
	for offset in HexMath.cells_in_radius(radius):
		var axial: Vector2i = center_cell + offset
		if not model.top_elevation_m.has(axial):
			continue
		var h0: float = model.get_head(axial)
		for k in range(HeadContourOverlay._TRIANGLE_OFFSETS.size()):
			var n1: Vector2i = axial + HeadContourOverlay._TRIANGLE_OFFSETS[k]
			var n2: Vector2i = axial + HeadContourOverlay._TRIANGLE_OFFSETS[(k + 1) % 6]
			if not (model.top_elevation_m.has(n1) and model.top_elevation_m.has(n2)):
				continue
			var h1: float = model.get_head(n1)
			var h2: float = model.get_head(n2)
			var lo: float = minf(h0, minf(h1, h2))
			var hi: float = maxf(h0, maxf(h1, h2))
			var level: float = ceilf(lo / interval) * interval
			if level <= lo:
				level += interval
			while level < hi:
				var crossing: Array = HeadContourOverlay._triangle_crossing(
					[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [h0, h1, h2], level)
				if crossing.size() == 2:
					count += 1
				level += interval
	return count

## User's ask (2026-10-21): "add labels to the contour lines" -- confirms
## _select_label_points' greedy minimum-spacing rule directly: points closer
## together than min_spacing get thinned out (never two labels crowded on
## top of each other), while a point far enough from everything already kept
## is always kept, no matter how many candidates came before it.
func _test_head_contour_overlay_label_spacing() -> int:
	var f := 0
	var candidates: Array = [Vector2(0, 0), Vector2(10, 0), Vector2(0, 200), Vector2(5, 205), Vector2(400, 400)]
	var selected: Array = HeadContourOverlay._select_label_points(candidates, 50.0)

	f += _check(selected.has(Vector2(0, 0)), "the first candidate is always kept (nothing placed yet to be too close to)")
	f += _check(not selected.has(Vector2(10, 0)), "a candidate within min_spacing of an already-kept point is dropped")
	f += _check(selected.has(Vector2(0, 200)), "a candidate far enough from every already-kept point is kept")
	f += _check(not selected.has(Vector2(5, 205)), "a second candidate too close to a just-kept point is also dropped")
	f += _check(selected.has(Vector2(400, 400)), "a candidate far from everything else is kept regardless of how many points came before it")
	f += _check(selected.size() == 3, "exactly the 3 mutually-far-enough-apart points survive thinning")
	return f
