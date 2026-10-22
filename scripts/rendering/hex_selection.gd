extends Node2D

## Hover/click highlighting for Ground cells. Dropped during the TileMapLayer
## rebuild (godot_hex_map_spec.md) and asked back explicitly -- rebuilt on
## the spec-correct foundation this time: hit-testing goes entirely through
## World.cell_under_mouse() (which itself goes through Ground.local_to_map(),
## the single source of truth), never an independent coordinate computation.
## Drawn last in scenes/main.tscn (after Features/DebugOverlay) so the
## highlight is always visible on top, regardless of what's on the cell --
## the opposite requirement from GridOutline, which must sit BEHIND features.
##
## Also owns the cell-inspector info panel (user request: "a way to
## interrogate the cell data... info box on hover/on click") -- lives here
## rather than a separate node because this script already tracks exactly
## the two states ("hovered", "selected") the panel needs to show, and
## already owns the hit-testing that drives it. A fixed screen-corner panel,
## not a cursor-following tooltip: simpler, never clips off a screen edge,
## and reads naturally as a persistent HUD readout rather than a transient
## hint. Shows the hovered cell's data when the mouse is over the map; falls
## back to the selected cell's data otherwise, so clicking a cell lets you
## move the mouse away and keep reading it.

const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const HexMath = preload("res://scripts/rendering/hex_math.gd")
const World = preload("res://scripts/rendering/world.gd")

const NO_CELL := Vector2i(1 << 20, 1 << 20) # sentinel outside any real map radius

## Keep matched to GridOutline's grid_size -- both default to World.TILE_SIZE,
## the exact proportions the generated ground hex textures are drawn at.
@export var grid_size: Vector2 = Vector2(World.TILE_SIZE)
@export var hover_color: Color = Color(1, 1, 1, 0.25)
@export var selected_color: Color = Color("e03c3c") # red, per user request
@export var selected_width: float = 2.0

var _world: Node
var _valid_cells: Dictionary = {} # Vector2i (axial) -> true
var _hovered := NO_CELL
var _selected := NO_CELL

var _info_panel: PanelContainer
var _info_label: Label

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_info_panel = PanelContainer.new()
	_info_panel.visible = false
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN # expands upward as text grows, since it's pinned to the bottom edge
	_info_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_KEEP_SIZE, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_info_panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(_info_panel)

	_info_label = Label.new()
	_info_label.add_theme_color_override("font_color", Color.WHITE)
	_info_panel.add_child(_info_label)

func configure(world: Node) -> void:
	_world = world
	_valid_cells.clear()
	for axial in HexMath.cells_in_radius(world.radius):
		_valid_cells[axial] = true

func _outline_points() -> PackedVector2Array:
	var unit := HexMath.hex_points(1.0)
	var scale_x: float = grid_size.x / 2.0
	var scale_y: float = grid_size.y / sqrt(3.0)
	var points := PackedVector2Array()
	for p in unit:
		points.append(Vector2(p.x * scale_x, p.y * scale_y))
	return points

func _unhandled_input(event: InputEvent) -> void:
	if _world == null:
		return
	if event is InputEventMouseMotion:
		var cell: Vector2i = _world.cell_under_mouse()
		if not _valid_cells.has(cell):
			cell = NO_CELL
		if cell != _hovered:
			_hovered = cell
			queue_redraw()
			_update_info_panel()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = _world.cell_under_mouse()
		if _valid_cells.has(cell) and cell != _selected:
			_selected = cell
			queue_redraw()
			_update_info_panel()

## Hovered cell takes priority over the selected one -- whatever's under the
## mouse right now is more likely what the user wants to read about. Falls
## back to the selected cell so the panel keeps showing something useful
## after the mouse leaves the map.
func _update_info_panel() -> void:
	if _info_panel == null:
		return
	var axial: Vector2i = _hovered if _valid_cells.has(_hovered) else _selected
	if not _valid_cells.has(axial):
		_info_panel.visible = false
		return
	_info_label.text = _format_cell_info(_world.cell_info(axial))
	_info_panel.visible = true

## Pure formatting, deliberately separate from _update_info_panel so it's
## testable without a Viewport/mouse-input round-trip -- same reasoning as
## GridOutline's _is_shore_edge split from its actual draw_line call.
func _format_cell_info(info: Dictionary) -> String:
	var axial: Vector2i = info["axial"]
	return "Cell (%d, %d)\nTerrain: %s\nElevation: %.1f m\nGeology: %s\nK: %s m/s\nPorosity: %.2f\nDiffusion: %s m2/s\nHead: %.1f m\nContamination: %.1f%%" % [
		axial.x, axial.y,
		info["terrain_name"],
		info["elevation_m"],
		info["geology_name"],
		_format_scientific(info["k_m_s"]),
		info["porosity"],
		_format_scientific(info["diffusion_m2_s"]),
		info["head_m"],
		info["contamination_percent"],
	]

## GDScript's "%" string formatting has no scientific-notation specifier
## (no %e), and String.num_scientific() only switches to exponential form
## below a fixed magnitude threshold (0.0003 prints as "0.0003", not
## "3.00e-04") -- unusable here since K spans orders of magnitude between
## geology units (brief SS4: 3e-4 sand down to 5e-8 clay) and needs one
## consistent, comparable format regardless of which unit a cell has.
static func _format_scientific(value: float) -> String:
	if value == 0.0:
		return "0.00e+00"
	var exponent := int(floor(log(absf(value)) / log(10.0)))
	var mantissa := value / pow(10.0, exponent)
	if absf(mantissa) >= 10.0: # rounding at the boundary (e.g. 9.999 -> 10.0)
		mantissa /= 10.0
		exponent += 1
	var sign_str := "+" if exponent >= 0 else "-"
	return "%.2fe%s%02d" % [mantissa, sign_str, absi(exponent)]

func _cell_polygon(axial: Vector2i, outline: PackedVector2Array) -> PackedVector2Array:
	var offset := GodotHexOffset.axial_to_offset(axial)
	var center: Vector2 = to_local(_world.ground.to_global(_world.ground.map_to_local(offset)))
	var shifted := PackedVector2Array()
	for p in outline:
		shifted.append(center + p)
	return shifted

func _draw() -> void:
	if _world == null:
		return
	var outline := _outline_points()

	if _valid_cells.has(_hovered):
		draw_colored_polygon(_cell_polygon(_hovered, outline), hover_color)

	if _valid_cells.has(_selected):
		var poly := _cell_polygon(_selected, outline)
		draw_polyline(poly + PackedVector2Array([poly[0]]), selected_color, selected_width, false)
