extends Node2D

## X-ray-only equipotential contour lines (user's ask, 2026-10-21; brief
## section 4: "Display equipotential contours... as learning aids"). Proper
## "marching triangles" contouring, NOT lines bound to hex cell edges (the
## user's follow-up ask, 2026-10-21: the first version's lines ran along
## hex edges and looked "blocky" -- an artifact of drawing on the grid
## itself rather than contouring the underlying continuous head FIELD, which
## the hex grid is just a discrete sample of).
##
## Hex cell CENTERS form a triangular lattice (the dual of a hex grid): each
## hex corner is shared by exactly 3 mutually-adjacent cells, i.e. one small
## triangle of the lattice. _TRIANGLE_OFFSETS' consecutive pairs enumerate
## those triangles. Treating head as linearly varying across each triangle
## (the standard assumption marching-triangles/marching-squares contouring
## makes everywhere) and finding where a given level crosses each triangle's
## edges by linear interpolation produces contour lines that cut through
## cells at whatever angle the head field actually has -- not forced to run
## along a hex boundary -- which is what reads as smooth/rounded instead of
## hexagonal. This is still piecewise-linear (short straight segments, not a
## true spline), but each segment is short relative to a cell and the
## overall line reads as continuously curving, the standard look of a real
## contour/topographic map.
##
## LABELS (user's ask, 2026-10-21): each contour level gets a "42.3 m"-style
## label, like a real topographic map, placed periodically along its lines
## (greedy minimum-spacing selection, _select_label_points) rather than once
## per tiny segment (unreadable clutter) or once per line (a single label
## can land off-screen or somewhere illegible) -- see show_labels' doc
## comment.
##
## BAND WIDTH IS AUTO-SCALED, not a fixed meters-per-band constant --
## target_contour_count's doc comment explains why (a fixed interval picked
## for today's K/well tuning silently stops working, with the whole grid
## reading as a solid wash instead of distinct lines, the moment the scenario
## is tuned differently). Only ever visible during x-ray mode
## (World.set_xray_mode).

const HexMath = preload("res://scripts/rendering/hex_math.gd")
const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const GridModel = preload("res://scripts/simulation/grid_model.gd")

## Six neighbor offsets in the same cyclic hex winding order GridOutline's
## shore-edge code establishes (SE, S, SW, NW, N, NE). Consecutive pairs
## (k, k+1 mod 6), together with the cell itself, are the three corners of
## one small triangle of the hex-center lattice -- confirmed geometrically
## (each consecutive pair is a genuine 1-hex-step neighbor of the other, so
## all three corners really are mutually adjacent) by
## _test_head_contour_overlay_triangle_offsets_are_mutually_adjacent, the
## same "don't just assert a hand-derived mapping" discipline
## grid_outline.gd's own shore-edge offsets needed. Each unique lattice
## triangle gets generated 3 times (once per its 3 corner cells) -- accepted
## as harmless, deterministic redundancy rather than added bookkeeping to
## dedupe it, given this project's map sizes (a few hundred cells).
const _TRIANGLE_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]

## Bright, highly saturated cyan -- deliberately NOT a pale/washed-out tint
## close to GridOutline's own grey (#5a5a5a) or HexSelection's blue, which is
## what made an earlier version of this overlay hard to tell apart from the
## plain grid at a glance once lines got dense. Must read unmistakably as "a
## different, informative layer," not a tinted grid.
@export var contour_color: Color = Color(0.1, 0.95, 1.0, 0.9)
@export var line_width: float = 2.0
## How many contour levels to spread across the CURRENT scenario's actual
## head range (max - min across every visible cell, recomputed every draw --
## cheap, and this never runs more than once per redraw). A FIXED
## meters-per-level value was tried first and silently broke: this project's
## default well_pumping_rate_m3_s (0.05 m3/s) against its clay-heavy
## geology produces roughly 25m of drawdown at the well alone, on top of the
## existing ~35m regional gradient -- a fixed 1m interval crossed ~80% of
## every triangle on the map, reading as a uniformly tinted grid, not a
## legible contour map. Auto-scaling means retuning K or the well's rate can
## never silently return to that same broken state.
@export_range(3, 40) var target_contour_count: int = 15
## Floor on the auto-scaled interval above, so a near-flat scenario (a tiny
## head range) can't produce an absurdly fine, GPU-wasteful interval.
@export var min_interval_m: float = 0.05

## Per-level head labels (e.g. "42.3 m"), like a real topographic map.
## Placed periodically along each level's lines rather than once per
## segment (every triangle crossing would be unreadable clutter) or once per
## line (a single label can scroll off-screen or land somewhere illegible) --
## see _select_label_points's doc comment for how spacing is chosen.
@export var show_labels: bool = true
@export var label_font_size: int = 14
@export var label_color: Color = Color.WHITE
@export var label_outline_color: Color = Color(0.0, 0.0, 0.0, 0.85)
## Minimum on-screen distance (px) between two labels on the SAME contour
## level, so a long, winding line gets a label every so often rather than
## either one single label or an unreadable cluster of them.
@export_range(40.0, 400.0) var label_min_spacing_px: float = 160.0

var _ground: TileMapLayer
var _model: GridModel
var _cells: Array[Vector2i] = []

func configure(ground: TileMapLayer, model: GridModel, cells: Array[Vector2i]) -> void:
	_ground = ground
	_model = model
	_cells = cells
	queue_redraw()

## Rounds a raw interval up to the nearest "nice" number -- 1, 2 or 5 times a
## power of 10 (1, 2, 5, 10, 20, 50, 100, ...), the same convention real
## chart/contour-map axis ticks use. User's ask (2026-10-21): raw
## range/target_contour_count produced arbitrary values like 2.97m, so every
## contour label read as an odd number (32.7, 29.7, 26.8m...) instead of
## something a reader can actually use as a reference scale. Pure, directly
## testable rather than folded into _current_interval_m() itself.
static func _nice_interval(raw: float) -> float:
	if raw <= 0.0:
		return raw
	var magnitude: float = pow(10.0, floor(log(raw) / log(10.0)))
	var fraction: float = raw / magnitude
	var nice_fraction := 10.0
	if fraction <= 1.0:
		nice_fraction = 1.0
	elif fraction <= 2.0:
		nice_fraction = 2.0
	elif fraction <= 5.0:
		nice_fraction = 5.0
	return nice_fraction * magnitude

## The interval actually used this draw: the current head range spread
## across roughly target_contour_count levels, rounded to a nice number
## (_nice_interval) and floored at min_interval_m.
func _current_interval_m() -> float:
	var lo := INF
	var hi := -INF
	for axial in _cells:
		var h: float = _model.get_head(axial)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if not (hi > lo):
		return min_interval_m
	var raw: float = (hi - lo) / float(target_contour_count)
	return maxf(min_interval_m, _nice_interval(raw))

## Pure "marching triangles" primitive, split out from _draw() for headless
## testability (same reasoning as every other overlay's math/draw split in
## this project). Given one triangle's 3 (position, head) pairs and a
## contour level, returns the 0 or 2 points where that level crosses the
## triangle's edges (linear interpolation along whichever edges have one
## vertex above the level and one below) -- exactly 2 in every case that
## matters for drawing a line (a level passing exactly through a vertex, or
## not touching the triangle at all, are both measure-zero/no-op cases for a
## continuously-varying real head field).
static func _triangle_crossing(positions: Array, heads: Array, level: float) -> Array:
	var points: Array = []
	for i in range(3):
		var j := (i + 1) % 3
		var h_i: float = heads[i]
		var h_j: float = heads[j]
		if (h_i < level) == (h_j < level):
			continue # both vertices on the same side of this level -- this edge isn't crossed
		var t: float = (level - h_i) / (h_j - h_i)
		points.append(positions[i].lerp(positions[j], t))
	return points

func _cell_centers() -> Dictionary:
	var centers := {}
	for axial in _cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		centers[axial] = to_local(_ground.to_global(_ground.map_to_local(offset)))
	return centers

## Greedy "furthest point first, in encounter order" spacing: walks
## `candidates` once, keeping a point only if it's at least `min_spacing`
## away from every point already kept. Pure and order-dependent on purpose
## (not sorted/clustered first) -- the caller feeds it crossing midpoints in
## the same raster order _draw() generates them, which is spatially coherent
## enough in practice to read as "roughly evenly spaced along the line,"
## without needing to reconstruct actual polyline connectivity from the
## segment soup (triangle crossings aren't linked into ordered curves here).
static func _select_label_points(candidates: Array, min_spacing: float) -> Array:
	var selected: Array = []
	for p in candidates:
		var far_enough := true
		for s in selected:
			if (p as Vector2).distance_to(s) < min_spacing:
				far_enough = false
				break
		if far_enough:
			selected.append(p)
	return selected

func _draw_label(position: Vector2, level: float) -> void:
	var font := ThemeDB.fallback_font
	var text := "%.1f m" % level
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
	var baseline: Vector2 = position + Vector2(-size.x / 2.0, size.y * 0.3)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, 3, label_outline_color)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, label_color)

func _draw() -> void:
	if _model == null or _cells.is_empty():
		return
	var interval := _current_interval_m()
	var centers := _cell_centers()
	# level (as a "%.6f" key, to group exact-equal floats) -> {"level": float, "points": Array[Vector2]}
	# -- every triangle's crossing midpoint for that level, collected while
	# drawing the lines themselves, then spaced out into label positions in
	# a second pass once the full set for each level is known.
	var candidates_by_level: Dictionary = {}
	for axial in _cells:
		var h0: float = _model.get_head(axial)
		for k in range(6):
			var n1: Vector2i = axial + _TRIANGLE_OFFSETS[k]
			var n2: Vector2i = axial + _TRIANGLE_OFFSETS[(k + 1) % 6]
			if not (_model.top_elevation_m.has(n1) and _model.top_elevation_m.has(n2)):
				continue
			var h1: float = _model.get_head(n1)
			var h2: float = _model.get_head(n2)
			var lo: float = minf(h0, minf(h1, h2))
			var hi: float = maxf(h0, maxf(h1, h2))
			# Every multiple of `interval` strictly inside (lo, hi) -- a
			# steep triangle (e.g. straddling the clay band, or close to the
			# well) can legitimately cross several levels at once, each
			# getting its own line, unlike the old edge-bound version which
			# could only ever draw one line per cell face regardless of how
			# big the jump was.
			var level: float = ceilf(lo / interval) * interval
			if level <= lo:
				level += interval
			while level < hi:
				var crossing := _triangle_crossing(
					[centers[axial], centers[n1], centers[n2]],
					[h0, h1, h2],
					level)
				if crossing.size() == 2:
					draw_line(crossing[0], crossing[1], contour_color, line_width, true)
					if show_labels:
						var key := "%.6f" % level
						if not candidates_by_level.has(key):
							candidates_by_level[key] = {"level": level, "points": []}
						candidates_by_level[key]["points"].append((crossing[0] + crossing[1]) * 0.5)
				level += interval

	if not show_labels:
		return
	for entry in candidates_by_level.values():
		var points: Array = _select_label_points(entry["points"], label_min_spacing_px)
		for p in points:
			_draw_label(p, entry["level"])
