extends Node2D

## Simple, always-fully-revealed flow-vector overlay: one resultant arrow per
## cell, reconstructed from GridModel's face fluxes (sum of outward Darcy
## flux * direction over all 6 neighbor faces) -- the brief's own "Display
## equipotential contours and flow arrows as learning aids" (SS6), built now
## as a cheap visual sanity check on the Darcy flux math while it's fresh.
##
## Deliberately NOT tied to fog-of-war/characterization -- every cell's true
## flow is shown regardless of what the player has "measured" (there is no
## characterize action or turn loop yet to gate that on). The user's bigger
## idea -- a separate "x-ray" subsurface view (geology/head/flow/plume) that
## reveals more as you characterize, varying by difficulty -- is parked in
## docs/BACKLOG.md, to build once that state actually exists.

const HexMath = preload("res://scripts/rendering/hex_math.gd")
const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const GridModel = preload("res://scripts/simulation/grid_model.gd")

@export var arrow_color: Color = Color(0.3, 0.85, 1.0, 0.85)
@export var arrow_width: float = 2.0
## Pixels of arrow length per (m/s) of resultant cell-center flow -- flux
## magnitudes are tiny (~1e-5 to 1e-4 m/s for these placeholder K/head
## values), so this needs a large multiplier to read as a visible arrow.
## Inspector-tunable rather than hand-picked (memory/feedback_expose_visual_tuning.md).
@export_range(1.0e5, 1.0e8, 1.0e5) var arrow_scale: float = 4.0e6
@export_range(4.0, 80.0) var arrow_max_length: float = 40.0

## Animated shaft (brief SS6: "animated flow arrows"): dashes scroll from
## the cell center toward the arrowhead -- i.e. toward where the water is
## actually going, not just a generic sparkle -- at a rate scaled by the
## arrow's own (already-clamped) length, so a fast well-capture cell's
## dashes visibly race while a clay-constrained cell's dashes barely creep.
## That ties the animation's speed to real relative flow magnitude instead
## of decorating every cell identically, in the same "make the reason
## visible" spirit as the arrow's length already being physically meaningful
## (design guardrail 6). Inspector-tunable per the usual practice
## (memory/feedback_expose_visual_tuning.md).
@export_range(2.0, 20.0) var dash_length_px: float = 6.0
@export_range(1.0, 20.0) var dash_gap_px: float = 5.0
@export_range(0.0, 5.0) var dash_speed_factor: float = 1.5

var _ground: TileMapLayer
var _model: GridModel
var _cells: Array[Vector2i] = []
var _time: float = 0.0

func configure(ground: TileMapLayer, model: GridModel, cells: Array[Vector2i]) -> void:
	_ground = ground
	_model = model
	_cells = cells
	queue_redraw()

## Only animates while actually shown -- this node's own `visible` flag
## (toggled by World.set_xray_mode indirectly and the F key below) is enough
## to gate it; no point re-issuing hundreds of draw calls a frame for an
## overlay nobody can see.
func _process(delta: float) -> void:
	if not visible or _model == null:
		return
	_time += delta
	queue_redraw()

## Runtime toggle, independent of World.show_flow_overlay's Inspector
## default -- useful since this overlay and the surface art compete visually.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		visible = not visible
		queue_redraw()

## Resultant flow vector at a cell: sum, over all 6 neighbor faces, of that
## face's signed Darcy flux times the unit direction toward that neighbor.
## A crude (not RT0-accurate) reconstruction of a cell-center velocity from
## face fluxes, but enough to read direction/relative magnitude at a glance
## -- exactly this overlay's job, nothing more rigorous is needed yet.
func _flow_vector(axial: Vector2i) -> Vector2:
	var result := Vector2.ZERO
	for face_offset in HexMath.NEIGHBOR_OFFSETS:
		var neighbor := axial + face_offset
		if not _model.top_elevation_m.has(neighbor):
			continue
		var flux: float = _model.face_flux_m_s(axial, neighbor)
		var dir: Vector2 = HexMath.axial_to_pixel(face_offset, 1.0).normalized()
		result += dir * flux
	return result

func _draw() -> void:
	if _model == null:
		return
	for axial in _cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		var center: Vector2 = to_local(_ground.to_global(_ground.map_to_local(offset)))
		var flow := _flow_vector(axial)
		var length: float = minf(flow.length() * arrow_scale, arrow_max_length)
		if length < 2.0:
			continue
		_draw_arrow(center, flow.normalized() * length)

func _draw_arrow(center: Vector2, vec: Vector2) -> void:
	var tip := center + vec
	var shaft_len: float = vec.length()
	_draw_dashed_line(center, tip, dash_length_px, dash_gap_px, _time * shaft_len * dash_speed_factor)
	var angle := vec.angle()
	var head_len: float = minf(shaft_len * 0.35, 8.0)
	var left := tip + Vector2.from_angle(angle + PI - 0.4) * head_len
	var right := tip + Vector2.from_angle(angle + PI + 0.4) * head_len
	draw_line(tip, left, arrow_color, arrow_width)
	draw_line(tip, right, arrow_color, arrow_width)

## Pure segment math, deliberately split from the actual draw_line calls
## (same "separate the math from the drawing" discipline flow_solver.gd
## follows for the numerics) so the dash pattern itself is testable without
## a live Viewport/draw context. Returns [start, end] pairs along the
## from->to axis (each already clipped to [0, total_len]) for a dash pattern
## that scrolls toward `total_len` (i.e. toward `to`, the arrowhead) as
## `phase` increases -- phase is normally _time * shaft_len * dash_speed_factor,
## so this is also where "faster flow -> faster-scrolling dashes" actually
## happens, not just a cosmetic wobble.
static func _dash_segments(total_len: float, dash_len: float, gap_len: float, phase: float) -> Array[Vector2]:
	var segments: Array[Vector2] = []
	if total_len <= 0.0 or dash_len <= 0.0:
		return segments
	var period: float = dash_len + gap_len
	if period <= 0.0:
		segments.append(Vector2(0.0, total_len))
		return segments
	var start: float = fposmod(phase, period) - period # in [-period, 0) -- increasing phase shifts every dash toward larger t, i.e. toward `to`
	var t := start
	while t < total_len:
		var seg_a: float = maxf(t, 0.0)
		var seg_b: float = minf(t + dash_len, total_len)
		if seg_b > seg_a:
			segments.append(Vector2(seg_a, seg_b))
		t += period
	return segments

func _draw_dashed_line(from: Vector2, to: Vector2, dash_len: float, gap_len: float, phase: float) -> void:
	var diff := to - from
	var total_len: float = diff.length()
	if total_len <= 0.0:
		return
	var dir := diff / total_len
	for seg in _dash_segments(total_len, dash_len, gap_len, phase):
		draw_line(from + dir * seg.x, from + dir * seg.y, arrow_color, arrow_width)
