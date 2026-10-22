extends Camera2D

## Mouse-wheel zoom, clamped so the view can't collapse to zero or run away
## to an unreadable scale -- plus panning, two ways: arrow keys, and
## middle-mouse-button drag (same convention Godot's own 2D editor uses, so
## it should feel familiar). Left-click is reserved for tile selection
## (hex_selection.gd), so dragging to pan deliberately does NOT use it.
##
## min_zoom/max_zoom are plain @export_range, not hardcoded, specifically so
## they can be retuned from the Inspector if the ground art's own scale
## changes (e.g. the jump from 64x55 procedural tiles to 122x106 real art) --
## same "expose it, don't hand-pick a magic number" practice as World's
## tuning knobs (memory/feedback_expose_visual_tuning.md).

@export var zoom_step: float = 0.15
@export_range(0.01, 10.0) var min_zoom: float = 0.4
@export_range(0.01, 10.0) var max_zoom: float = 3.5

## World-units/second at zoom = 1.0. Actual movement is divided by the
## current zoom level so arrow-key panning feels like a constant SCREEN
## speed, not a constant world speed -- otherwise panning is painfully slow
## zoomed out and uncontrollably fast zoomed in.
@export var pan_speed: float = 800.0

var _dragging := false

func _process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction != Vector2.ZERO:
		position += direction * (pan_speed / zoom.x) * delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		# Content follows the cursor while dragging (the map moves the way
		# you drag it, like Google Maps or Godot's own 2D editor) -- so the
		# camera's own center point moves the OPPOSITE way.
		position -= event.relative / zoom.x

func _zoom_by(delta: float) -> void:
	var new_zoom: float = clampf(zoom.x + delta, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
