extends CanvasLayer

## Visible rain drops/streaks (user's ask, 2026-10-29). Screen-space, not
## world-space -- a full-viewport ColorRect with rain_streaks.gdshader, same
## reasoning as the HUD/x-ray background CanvasLayers already in this scene:
## streak size/speed must read consistently regardless of camera zoom, and a
## CanvasLayer at the default layer (0) draws on top of ordinary world
## content but stays wherever this node sits relative to the HUD/legend
## CanvasLayers that are added later, in code, during World._ready() -- see
## scenes/main.tscn's node order (RainOverlay is declared before those are
## built), so rain streaks fall over the game world but stay UNDER the
## turn/mass/status HUD text, which must stay readable.
##
## No per-frame queue_redraw() needed, same reasoning as CloudShadowOverlay:
## the ColorRect's shape never changes, and its ShaderMaterial animates
## itself every frame via TIME. set_intensity() is the only thing that needs
## to be pushed from the outside, once per frame, from World (RainController's
## intensity changes continuously while fading in/out).

const RAIN_SHADER := preload("res://scripts/rendering/shaders/rain_streaks.gdshader")

@export var drop_color: Color = Color(0.75, 0.82, 0.92, 0.55)
@export_range(4.0, 60.0) var lane_width_px: float = 14.0
@export_range(40.0, 400.0) var tile_height_px: float = 160.0
@export_range(-3000.0, 3000.0) var fall_speed_px_s: float = 1100.0 ## sign is the fall direction -- positive falls down (normal), negative falls up; see rain_streaks.gdshader's header comment
@export_range(4.0, 80.0) var streak_length_px: float = 24.0
@export_range(0.5, 6.0) var streak_width_px: float = 1.5
@export var wind_px_s: Vector2 = Vector2(-60.0, 0.0)
@export_range(-1.0, 1.0) var slant: float = -0.15
@export_range(0.0, 1.0) var density: float = 0.6

var _rect: ColorRect

func _ready() -> void:
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # must not swallow clicks -- same hazard _xray_background's doc comment already covers
	_rect.color = Color.WHITE # the shader supplies the real color/alpha; this is just the geometry it paints onto, same convention as CloudShadowOverlay's draw_rect
	var mat := ShaderMaterial.new()
	mat.shader = RAIN_SHADER
	_rect.material = mat
	_rect.visible = false
	add_child(_rect)
	_push_shader_params()

func _push_shader_params() -> void:
	if _rect == null or _rect.material == null:
		return
	var mat: ShaderMaterial = _rect.material
	mat.set_shader_parameter("drop_color", drop_color)
	mat.set_shader_parameter("lane_width_px", lane_width_px)
	mat.set_shader_parameter("tile_height_px", tile_height_px)
	mat.set_shader_parameter("fall_speed_px_s", fall_speed_px_s)
	mat.set_shader_parameter("streak_length_px", streak_length_px)
	mat.set_shader_parameter("streak_width_px", streak_width_px)
	mat.set_shader_parameter("wind_px_s", wind_px_s)
	mat.set_shader_parameter("slant", slant)
	mat.set_shader_parameter("density", density)

## Called once per frame from World, mirroring CloudShadowOverlay.set_rain_intensity.
## Hides the rect entirely below a tiny threshold rather than just leaving
## rain_intensity at 0.0 -- skips the shader's per-pixel work completely while
## no rain is happening, which is most of the time.
func set_intensity(t: float) -> void:
	if _rect == null or _rect.material == null:
		return
	t = clamp(t, 0.0, 1.0)
	_rect.visible = t > 0.001
	(_rect.material as ShaderMaterial).set_shader_parameter("rain_intensity", t)
