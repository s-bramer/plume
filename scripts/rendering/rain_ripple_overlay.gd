extends Node2D

## Expanding circular ripples on water tiles during rain (user's ask,
## 2026-10-29) -- a DIFFERENT effect from shoreline_ripple_overlay.gd's dashed
## washes along the shore edge: these are plain, randomly-placed, outward-
## growing rings scattered across the open water surface itself, one per
## raindrop impact, same spirit as real rain hitting a pond.
##
## Configured once with the real water cell centers (world/local positions,
## same to_local(ground.to_global(ground.map_to_local(...))) convention every
## other overlay in this project uses) and a reference to RainController, so
## it can read .intensity every frame without a signal -- same "configure
## once, read a shared data source every frame" pattern GridOutline/
## HexSelection already use for grid_size.
##
## CPU-driven, not shader-driven (unlike CloudShadowOverlay/WaterShimmerOverlay):
## ripples are born, grow and die at specific times and positions decided on
## the CPU (when to spawn one, where), so this DOES need a per-frame
## queue_redraw() -- same category as FlowOverlay/ShorelineRippleOverlay, per
## the project's now-established "queue_redraw() is only needed when the CPU
## itself must recompute different draw commands" rule.

const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")

@export_range(0, 200) var max_concurrent_ripples: int = 40
@export_range(0.0, 20.0) var spawn_rate_per_s_at_full_intensity: float = 7.0 ## ripples/second spawned across the whole water surface when rain_intensity == 1.0
@export_range(0.1, 6.0) var ripple_lifetime_s: float = 1.4
@export_range(4.0, 120.0) var ripple_max_radius_px: float = 24.0
@export_range(0.3, 6.0) var ripple_line_width: float = 1.3
@export var ripple_color: Color = Color(0.92, 0.96, 1.0, 0.5)
@export_range(0.0, 60.0) var spawn_jitter_px: float = 20.0 ## random offset from a water cell's exact center, keeps ripples off a visible grid

var _rain_controller: Node # reads .intensity -- no other dependency on RainController's shape
var _water_cell_positions: PackedVector2Array = PackedVector2Array()
var _rng := RandomNumberGenerator.new()
var _ripples: Array[Dictionary] = [] # each: {"pos": Vector2, "age": float}
var _spawn_accum: float = 0.0

func configure(ground: TileMapLayer, cells: Array[Vector2i], rain_controller: Node) -> void:
	_rain_controller = rain_controller
	_water_cell_positions = PackedVector2Array()
	for axial in cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		_water_cell_positions.append(to_local(ground.to_global(ground.map_to_local(offset))))
	_rng.randomize()

func _process(delta: float) -> void:
	if _water_cell_positions.is_empty():
		return
	var intensity: float = 0.0 if _rain_controller == null else _rain_controller.intensity
	if intensity > 0.0 and _ripples.size() < max_concurrent_ripples:
		_spawn_accum += delta * spawn_rate_per_s_at_full_intensity * intensity
		while _spawn_accum >= 1.0 and _ripples.size() < max_concurrent_ripples:
			_spawn_accum -= 1.0
			_spawn_ripple()
	else:
		_spawn_accum = 0.0

	var alive: Array[Dictionary] = []
	for r in _ripples:
		r.age += delta
		if r.age < ripple_lifetime_s:
			alive.append(r)
	_ripples = alive
	queue_redraw()

func _spawn_ripple() -> void:
	var base: Vector2 = _water_cell_positions[_rng.randi_range(0, _water_cell_positions.size() - 1)]
	var jitter := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * spawn_jitter_px
	_ripples.append({"pos": base + jitter, "age": 0.0})

## Pure growth/fade curves, split out from _draw() so they're covered by a
## headless test (per the project's "separate the math from the drawing"
## practice -- see ShorelineRippleOverlay/CloudShadowOverlay). Radius grows
## linearly from 0 to max_radius across the ripple's lifetime; alpha fades
## linearly from base_alpha to 0 over the same span, so a ripple is born
## as a point at full opacity and dies as a faint, fully-grown ring.
static func _ripple_radius(age: float, lifetime: float, max_radius: float) -> float:
	if lifetime <= 0.0:
		return 0.0
	return max_radius * clamp(age / lifetime, 0.0, 1.0)

static func _ripple_alpha(age: float, lifetime: float, base_alpha: float) -> float:
	if lifetime <= 0.0:
		return 0.0
	return base_alpha * (1.0 - clamp(age / lifetime, 0.0, 1.0))

func _draw() -> void:
	for r in _ripples:
		var radius: float = _ripple_radius(r.age, ripple_lifetime_s, ripple_max_radius_px)
		if radius <= 0.0:
			continue
		var col := ripple_color
		col.a = _ripple_alpha(r.age, ripple_lifetime_s, ripple_color.a)
		draw_arc(r.pos, radius, 0.0, TAU, 32, col, ripple_line_width, true)
