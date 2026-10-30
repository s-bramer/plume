extends Node

## Rainfall events (user's ask, 2026-10-29): "add rainfall events ... ambient
## sound changes (later)". This node owns ONLY the timing/intensity state --
## no drawing, no water/tree/ground knowledge -- every reactive system
## (CloudShadowOverlay, RainOverlay, RainRippleOverlay, Ground's wet tint,
## tree sway) reads `intensity` (0..1) from a shared reference, the same
## "configure once, read a shared data source every frame" pattern GridOutline/
## HexSelection already use for grid_size, rather than a signal fan-out.
##
## A rain event ramps intensity 0 -> 1 over fade_s, holds at 1, then ramps
## back 1 -> 0 over fade_s -- see _intensity_for, a pure function so the
## ramp shape is covered by a headless test without waiting on a real timer.
## Between events, auto_events schedules the next one after a random real-time
## wait in [min_interval_s, max_interval_s]; force_rain is a manual Inspector
## trigger for testing/tuning without waiting on the random schedule, same
## "expose it, don't hand-tune blind" practice as the rest of this project
## (memory/feedback_expose_visual_tuning.md).

@export var rain_enabled: bool = true ## master switch -- false disables auto events AND the manual trigger below

@export_range(5.0, 300.0) var min_interval_s: float = 25.0 ## real-time gap between rain events, lower bound
@export_range(5.0, 600.0) var max_interval_s: float = 70.0 ## real-time gap between rain events, upper bound
@export_range(2.0, 120.0) var min_duration_s: float = 12.0 ## how long one event lasts (including its fade in/out), lower bound
@export_range(2.0, 240.0) var max_duration_s: float = 28.0 ## how long one event lasts (including its fade in/out), upper bound
@export_range(0.1, 15.0) var fade_s: float = 2.5 ## real seconds to ramp intensity in at the start and back out at the end
@export var auto_events: bool = true ## random scheduling on/off -- turn off to rely solely on force_rain while tuning

## Manual one-shot trigger for testing/tuning: ticking this box in the
## Inspector (or setting it from a script/probe) starts a rain event
## immediately, bypassing the random schedule. Always resets itself back to
## false right away so it reads as a button press, not a held toggle.
@export var force_rain: bool = false:
	set(value):
		force_rain = false
		if value and rain_enabled:
			start_rain()

var intensity: float = 0.0 # 0..1, read by every rain-reactive system every frame

var _is_raining: bool = false
var _timer_s: float = 0.0 # counts up through whichever state we're in
var _wait_s: float = 0.0 # WAITING: how long until the next auto event (ignored if auto_events is false)
var _duration_s: float = 0.0 # RAINING: this event's total length, fade in/out included

func _ready() -> void:
	_wait_s = randf_range(min_interval_s, max_interval_s)

func _process(delta: float) -> void:
	if not rain_enabled:
		_is_raining = false
		intensity = 0.0
		return
	_timer_s += delta
	if _is_raining:
		intensity = _intensity_for(_timer_s, _duration_s, fade_s)
		if _timer_s >= _duration_s:
			_is_raining = false
			_timer_s = 0.0
			_wait_s = randf_range(min_interval_s, max_interval_s)
	else:
		intensity = 0.0
		if auto_events and _timer_s >= _wait_s:
			start_rain()

## Starts a rain event right now. duration_s <= 0.0 (the default) rolls a
## random duration from min_duration_s/max_duration_s, same as an auto event --
## exposed as an explicit argument so a test or probe can force an exact,
## reproducible length instead of a random one.
func start_rain(duration_s: float = -1.0) -> void:
	_is_raining = true
	_timer_s = 0.0
	_duration_s = duration_s if duration_s > 0.0 else randf_range(min_duration_s, max_duration_s)

## Pure ramp shape: 0 at elapsed=0, rises to 1 by elapsed=fade_s, holds at 1
## until duration_s - fade_s, then falls back to 0 by elapsed=duration_s.
## min(fade_in, fade_out) is what makes a short event (duration_s < 2*fade_s)
## degrade gracefully into a single triangular pulse that never actually
## reaches 1.0, rather than snapping straight to full intensity then holding
## it for a moment that doesn't exist.
static func _intensity_for(elapsed_s: float, duration_s: float, fade_s: float) -> float:
	if duration_s <= 0.0 or elapsed_s < 0.0 or elapsed_s > duration_s:
		return 0.0
	if fade_s <= 0.0:
		return 1.0
	var fade_in: float = clamp(elapsed_s / fade_s, 0.0, 1.0)
	var fade_out: float = clamp((duration_s - elapsed_s) / fade_s, 0.0, 1.0)
	return min(fade_in, fade_out)
