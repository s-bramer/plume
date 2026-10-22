extends Node2D

## Diagnostic overlay per godot_hex_map_spec.md: draws each cell's logical
## centre (from Ground.map_to_local(), the single source of truth) as a dot
## and an exact crosshair, plus its coordinates. Toggleable
## (World.show_debug_overlay) -- diagnostic only, not a design element.
## The permanent hex grid line is a separate node (grid_outline.gd), since
## that's a real part of the look, not something to debug with.

const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")

const LABEL_COLOR := Color("3a2f14")
const DOT_COLOR := Color("b34040")
const DOT_RADIUS := 2.5
const CROSSHAIR_COLOR := Color("ff00ff") # bright magenta, deliberately not used anywhere else
const CROSSHAIR_ARM := 10.0

var _ground: TileMapLayer
var _cells: Array[Vector2i] = [] # axial (q, r), converted to Godot offset coords when drawing

func configure(ground: TileMapLayer, cells: Array[Vector2i]) -> void:
	_ground = ground
	_cells = cells
	queue_redraw()

func _draw() -> void:
	if _ground == null:
		return
	for axial in _cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		var center: Vector2 = to_local(_ground.to_global(_ground.map_to_local(offset)))
		draw_circle(center, DOT_RADIUS, DOT_COLOR)
		# A thin, exact crosshair -- the dot has visible radius/fuzziness at a
		# glance; this pins the precise pixel for comparing a feature's anchor
		# against the cell's true logical center without ambiguity.
		draw_line(center + Vector2(-CROSSHAIR_ARM, 0), center + Vector2(CROSSHAIR_ARM, 0), CROSSHAIR_COLOR, 1.0, false)
		draw_line(center + Vector2(0, -CROSSHAIR_ARM), center + Vector2(0, CROSSHAIR_ARM), CROSSHAIR_COLOR, 1.0, false)
		draw_string(ThemeDB.fallback_font, center + Vector2(-16, 4), "%d,%d" % [axial.x, axial.y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LABEL_COLOR)
