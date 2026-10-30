extends CanvasModulate

## Ambient day/night mood lighting -- the last item from the trees/water/flow
## "alive, beautiful, precious" look-and-feel pass. A CanvasModulate tints
## every CanvasItem in the main viewport at once, so -- same "the engine does
## the work, GDScript just updates one color" cost profile as the other mood
## passes -- this stays flat no matter how much is on screen, with no
## per-node shader needed.
##
## Cycles day -> dusk -> night -> dusk -> day on a loop. Kept subtle by
## default (strength) and the night color is never fully black, because the
## brief is explicit that ambient/mood effects must never obscure critical
## simulation information (brief §6) -- x-ray overlays, the plume, flow
## arrows etc. all live in this same canvas and get tinted right along with
## the terrain, so this is deliberately gentler than a "real" night.

@export var day_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var dusk_color: Color = Color(1.0, 0.68, 0.48, 1.0)
@export var night_color: Color = Color(0.4, 0.45, 0.65, 1.0)
@export_range(1.0, 600.0) var cycle_duration_sec: float = 90.0
@export_range(0.0, 1.0) var strength: float = 0.5 ## 0 = no tint at all (stays white); 1 = full day/dusk/night palette

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	color = _cycle_color(_time, cycle_duration_sec, day_color, dusk_color, night_color, strength)

## Pure math, split out for headless testability -- same "separate the math
## from the drawing" split as FlowOverlay._dash_segments and
## WaterShimmerOverlay's outline math. phase wraps every 1.0: 0.00 day,
## 0.25 dusk (sunset), 0.50 night, 0.75 dusk (sunrise), back to 1.00 == 0.00.
static func _phase_color(phase: float, day: Color, dusk: Color, night: Color) -> Color:
	var p: float = fposmod(phase, 1.0)
	if p < 0.25:
		return day.lerp(dusk, p / 0.25)
	elif p < 0.5:
		return dusk.lerp(night, (p - 0.25) / 0.25)
	elif p < 0.75:
		return night.lerp(dusk, (p - 0.5) / 0.25)
	else:
		return dusk.lerp(day, (p - 0.75) / 0.25)

static func _cycle_color(time: float, duration: float, day: Color, dusk: Color, night: Color, strength: float) -> Color:
	if duration <= 0.0:
		return day
	var raw := _phase_color(time / duration, day, dusk, night)
	return Color.WHITE.lerp(raw, strength)
