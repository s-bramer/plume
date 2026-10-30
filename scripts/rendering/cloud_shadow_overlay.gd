extends Node2D

## Slow-moving cloud shadows (user's ask, 2026-10-29) -- the brief's §6
## "lights for mood" family, same spirit as mood_lighting.gd's day/night
## cycle and water_shimmer_overlay.gd's glints, just drifting cloud shade
## instead. A SINGLE world-space overlay spanning the whole map, not a
## per-hex shaded pass: one static rect covering the map's full bounding box,
## with a canvas_item fragment shader (cloud_shadow.gdshader) painting soft
## drifting shadow patches via fractal value noise sampled in WORLD space --
## same "one continuous field, no hex boundary to restart at" reasoning as
## the glint shader, just at a much larger, slower scale, and spanning many
## hexes under one shape instead of being re-evaluated per tile.
##
## Unlike every other animated overlay in this project, this one does NOT
## call queue_redraw() every frame: its one rect never changes shape, and a
## CanvasItem's attached ShaderMaterial is re-evaluated by the GPU on every
## rendered frame regardless of whether _draw() was called again -- TIME
## updates on its own. Per-frame queue_redraw() is only needed when the CPU
## itself must recompute different draw commands each frame (FlowOverlay's
## dash positions, ShorelineRippleOverlay's inset/alpha) -- that's not the
## case here, so skipping it is a real (if minor) efficiency win, not an
## oversight.
##
## Drawn ABOVE Features (trees/rocks/decals) per the user's explicit ask
## (2026-10-29: "cloud shadows need to be the top layer - on top of trees,
## decals, rocks, etc.") -- placed in scenes/main.tscn's tree right after
## Features, but still BELOW every x-ray data overlay (GeologyOverlay,
## HeadContourOverlay, PlumeOverlay, FlowOverlay, HexSelection, DebugOverlay),
## so a passing cloud now visibly darkens tree/rock/decal silhouettes too,
## while still never obscuring plume/geology/head-contour data (brief §6:
## ambient mood must never obscure critical simulation information). Always
## visible, NOT x-ray-gated, same reasoning as water_shimmer_overlay.gd:
## ambient-only, never simulation data.
##
## set_rain_intensity() (added 2026-10-29 for rainfall events): "clouds
## covers all tiles" during rain is implemented as lerping cloud_coverage/
## cloud_color toward storm_coverage/storm_color as intensity rises, rather
## than a separate rain-specific cloud layer -- this overlay already covers
## the whole map and already controls "how much sky is shadowed," so a storm
## is just this same mechanism pushed to its extreme (storm_coverage defaults
## to 1.0: fully overcast), not a new concept.

const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const CLOUD_SHADER = preload("res://scripts/rendering/shaders/cloud_shadow.gdshader")

@export var cloud_color: Color = Color(0.05, 0.08, 0.14, 0.35) ## dark wash at a cloud's densest point, on a clear/partly-cloudy day
@export_range(0.0003, 0.02) var cloud_scale: float = 0.0025 ## world-space noise frequency -- smaller = larger clouds
@export var cloud_speed_px_s: Vector2 = Vector2(6.0, 2.5) ## drift velocity, world px/sec -- deliberately slow per the user's ask
@export_range(0.0, 1.0) var cloud_coverage: float = 0.45 ## how much of the sky is covered on a clear/partly-cloudy day -- higher = more/bigger shadow patches
@export_range(0.01, 1.0) var cloud_softness: float = 0.35 ## edge blur of a cloud's silhouette
@export_range(0.0, 1.0) var storm_coverage: float = 1.0 ## cloud_coverage at rain_intensity == 1.0 -- 1.0 means "clouds covers all tiles" (the user's literal ask)
@export var storm_color: Color = Color(0.03, 0.04, 0.07, 0.75) ## cloud_color at rain_intensity == 1.0 -- darker/denser than the clear-day default

var _rain_intensity: float = 0.0

## Extra world-space margin added around the map's own bounding box, so
## clouds still cover the ground right up to the map's edge even though the
## rect itself is static -- all the apparent MOTION happens inside the
## shader (noise coordinates scroll with TIME), never by moving this shape.
const _MARGIN_PX := 128.0

var _bounds_rect: Rect2 = Rect2()

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	material = mat
	_push_shader_params()

func _push_shader_params() -> void:
	if material == null:
		return
	material.set_shader_parameter("cloud_color", cloud_color.lerp(storm_color, _rain_intensity))
	material.set_shader_parameter("cloud_scale", cloud_scale)
	material.set_shader_parameter("cloud_speed_px_s", cloud_speed_px_s)
	material.set_shader_parameter("cloud_coverage", lerp(cloud_coverage, storm_coverage, _rain_intensity))
	material.set_shader_parameter("cloud_softness", cloud_softness)

## Called once per frame from World (RainController.intensity changes
## continuously while fading in/out) -- re-pushes every shader param, not
## just coverage/color, so an Inspector edit to any other export (scale,
## speed, softness) also takes effect live during play, same "live-tuning"
## benefit _refresh_geology_parameters already established elsewhere.
func set_rain_intensity(t: float) -> void:
	_rain_intensity = clamp(t, 0.0, 1.0)
	_push_shader_params()

## Pure, testable: the smallest Rect2 containing every one of `positions`,
## inflated by `margin` on every side. Split out from configure() so the
## bounding-box math is verifiable without a Viewport -- same "drawn, not
## tested headlessly" split as every other overlay here: the SHAPE covering
## the map is pure/testable, the noise shader painted onto it isn't.
static func _bounding_rect(positions: PackedVector2Array, margin: float) -> Rect2:
	if positions.is_empty():
		return Rect2()
	var rect := Rect2(positions[0], Vector2.ZERO)
	for p in positions:
		rect = rect.expand(p)
	return rect.grow(margin)

func configure(ground: TileMapLayer, cells: Array[Vector2i]) -> void:
	var positions := PackedVector2Array()
	for axial in cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		positions.append(to_local(ground.to_global(ground.map_to_local(offset))))
	_bounds_rect = _bounding_rect(positions, _MARGIN_PX)
	queue_redraw()

func _draw() -> void:
	if _bounds_rect.size == Vector2.ZERO:
		return
	draw_rect(_bounds_rect, Color.WHITE) # the shader supplies the real color/alpha; this is just the geometry it paints onto
