extends Node2D

## Shoreline ripples (user's ask, 2026-10-29): small, pale, broken lines
## animated just inside the water's edge, but ONLY along edges that actually
## border land -- open water-to-water edges stay plain.
##
## Checks all 6 neighbors, not just GridOutline's camera-facing 3 -- a ripple
## is a real physical effect that happens on every side of water touching
## land, unlike GridOutline's "shore_line" cliff cue, which is deliberately
## restricted to the three north-facing edges (a depth illusion valid only
## from this game's specific viewing angle -- see grid_outline.gd's header
## comment).
##
## That cliff cue IS one dependency this file deliberately takes on
## GridOutline, though (2026-10-29 amendment): on the three edges where
## GridOutline draws its own dark cliff line, a ripple must not start
## underneath/overlapping it -- it needs to begin just past where that line
## ends and wash inward from there. Reads GridOutline's actual tuned
## shore_line_width/shore_line_width_diagonal (via a live node reference, not
## a duplicated guess) so retuning the cliff line's width in the Inspector
## keeps the ripple start position correct without a second value to update.

const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const HexMath = preload("res://scripts/rendering/hex_math.gd")
const World = preload("res://scripts/rendering/world.gd")
const GridOutline = preload("res://scripts/rendering/grid_outline.gd")

@export var grid_size: Vector2 = Vector2(World.TILE_SIZE)
@export var ripple_color: Color = Color(0.93, 0.97, 1.0, 0.55) ## pale, near-white blue-white
@export_range(0.5, 8.0) var ripple_width: float = 2.0
@export_range(2.0, 20.0) var ripple_dash_length_px: float = 5.0
@export_range(1.0, 20.0) var ripple_dash_gap_px: float = 4.0
@export_range(0.5, 10.0) var ripple_max_expand_px: float = 2.0 ## how far inward (toward shore) a ripple washes over its active window, in px -- user's ask: "one or two pixels"
@export_range(0.05, 3.0) var ripple_cycle_speed: float = 0.5 ## ripples per second, per dash segment
@export_range(0.05, 1.0) var ripple_active_fraction: float = 0.4 ## fraction of each cycle a ripple is actually visible (appear -> expand -> fade); the rest is a quiet gap before that same segment ripples again

var _ground: TileMapLayer
var _cells: Array[Vector2i] = []
var _grid_outline: Node2D
var _time: float = 0.0

## grid_outline is optional (defaults to null, same "degrade gracefully, no
## cliff inset applied" behavior as before this feature existed) so existing
## callers/tests that don't care about the cliff-line interaction still work
## unchanged.
func configure(ground: TileMapLayer, cells: Array[Vector2i], grid_outline: Node2D = null) -> void:
	_ground = ground
	_cells = cells
	_grid_outline = grid_outline
	queue_redraw()

func _process(delta: float) -> void:
	if not visible or _ground == null:
		return
	_time += delta
	queue_redraw()

func _outline_points() -> PackedVector2Array:
	var unit := HexMath.hex_points(1.0)
	var scale_x: float = grid_size.x / 2.0
	var scale_y: float = grid_size.y / sqrt(3.0)
	var points := PackedVector2Array()
	for p in unit:
		points.append(Vector2(p.x * scale_x, p.y * scale_y))
	return points

func _is_water(offset: Vector2i) -> bool:
	return _ground.get_cell_source_id(offset) == World.TERRAIN_WATER

## Pure query -- true iff `axial` is water AND the neighbor across edge_index
## is a real, placed, non-water cell. Unlike GridOutline's _is_shore_edge,
## not restricted to any subset of edges: a ripple belongs on any of the 6
## sides a water cell actually touches land on.
func _is_shore_edge(axial: Vector2i, offset: Vector2i, edge_index: int) -> bool:
	if not _is_water(offset):
		return false
	var neighbor_axial := axial + GridOutline._ALL_EDGE_NEIGHBOR_OFFSETS[edge_index]
	var neighbor_offset := GodotHexOffset.axial_to_offset(neighbor_axial)
	var neighbor_source := _ground.get_cell_source_id(neighbor_offset)
	return neighbor_source != -1 and neighbor_source != World.TERRAIN_WATER

## 0 on any edge GridOutline wouldn't draw its dark cliff line on (no
## _grid_outline wired, or edge_index isn't one of its 3 camera-facing shore
## edges). On a cliff edge, GridOutline._is_shore_edge uses the exact same
## neighbor-offset table (_ALL_EDGE_NEIGHBOR_OFFSETS is a superset covering
## its _SHORE_EDGE_NEIGHBOR_OFFSETS for those 3 indices), so whenever THIS
## overlay's own _is_shore_edge(..., edge_index) is true for a cliff-edge
## index, GridOutline is guaranteed to have actually drawn its cliff line
## there too -- no separate "is this really a cliff" check needed, only which
## width it used.
func _cliff_inset_px(edge_index: int) -> float:
	if _grid_outline == null or not GridOutline._SHORE_EDGE_INDICES.has(edge_index):
		return 0.0
	if edge_index == GridOutline._SHORE_NORTH_EDGE_INDEX:
		return _grid_outline.shore_line_width
	return _grid_outline.shore_line_width_diagonal

## Same "where do the dashes land on a segment this long, at this phase" math
## as FlowOverlay._dash_segments -- duplicated rather than imported since the
## two overlays have no other shared dependency and this keeps each file
## self-contained (same call already made for grid_size/_outline_points
## above, mirroring GridOutline).
static func _dash_segments(total_len: float, dash_len: float, gap_len: float, phase: float) -> Array[Vector2]:
	var segments: Array[Vector2] = []
	if total_len <= 0.0 or dash_len <= 0.0:
		return segments
	var period: float = dash_len + gap_len
	if period <= 0.0:
		segments.append(Vector2(0.0, total_len))
		return segments
	var start: float = fposmod(phase, period) - period
	var t := start
	while t < total_len:
		var seg_a: float = maxf(t, 0.0)
		var seg_b: float = minf(t + dash_len, total_len)
		if seg_b > seg_a:
			segments.append(Vector2(seg_a, seg_b))
		t += period
	return segments

## One ripple's state at a given time, for a dash segment whose cycle is
## offset by phase01 (a per-segment hash, 0..1) -- NOT a tangential scroll:
## a ripple appears right at the water's edge (inset_px=0), washes inward
## toward shore up to max_expand_px as it plays out, and fades via a
## rise-then-fall envelope (sin(t*PI), 0 at both ends of the active window,
## peak at the middle) rather than a hard cut. Outside its own active window
## it's fully invisible (alpha_mult=0) -- a real gap between ripples, not a
## dimmed floor -- and phase01 is what keeps different segments from ever
## being in the same part of their cycle at the same instant, so the
## shoreline reads as many small independent washes, never a synchronized
## strobe or a single shape sliding along the edge.
## Returns (alpha_mult, inset_px).
static func _ripple_state(time: float, speed: float, phase01: float, active_fraction: float, max_expand_px: float) -> Vector2:
	if active_fraction <= 0.0:
		return Vector2.ZERO
	var cycle: float = fposmod(time * speed + phase01, 1.0)
	if cycle >= active_fraction:
		return Vector2.ZERO
	var t: float = cycle / active_fraction
	return Vector2(sin(t * PI), t * max_expand_px)

func _draw() -> void:
	if _ground == null:
		return
	var outline := _outline_points()
	for axial in _cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		if not _is_water(offset):
			continue
		var center: Vector2 = to_local(_ground.to_global(_ground.map_to_local(offset)))
		for i in range(6):
			if not _is_shore_edge(axial, offset, i):
				continue
			var corner_a: Vector2 = outline[i]
			var corner_b: Vector2 = outline[(i + 1) % 6]
			var a: Vector2 = center + corner_a
			var b: Vector2 = center + corner_b
			var edge_len: float = a.distance_to(b)
			if edge_len <= 0.0:
				continue
			var dir: Vector2 = (b - a) / edge_len
			# Points from the edge toward the hex's own centre -- the
			# direction a ripple washes "toward shore" in, perpendicular to
			# the edge itself, never along it.
			var inward_dir: Vector2 = -(corner_a + corner_b).normalized()
			var base_inset: float = _cliff_inset_px(i) # 0 except on GridOutline's 3 cliff edges -- starts the ripple just past the dark cliff line instead of underneath it
			var dashes := _dash_segments(edge_len, ripple_dash_length_px, ripple_dash_gap_px, 0.0)
			for k in range(dashes.size()):
				var seg: Vector2 = dashes[k]
				var phase01: float = World._pseudo_random01(axial, 101.0 + float(i) * 7.0 + float(k) * 13.3)
				var state := _ripple_state(_time, ripple_cycle_speed, phase01, ripple_active_fraction, ripple_max_expand_px)
				if state.x <= 0.0:
					continue
				var color := ripple_color
				color.a *= state.x
				var drift: Vector2 = inward_dir * (base_inset + state.y)
				draw_line(a + dir * seg.x + drift, a + dir * seg.y + drift, color, ripple_width, false)
