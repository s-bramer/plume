extends Node2D

## Animated water surface (brief §6: "...pixel-art terrain..."/"lights for
## mood" -- trees already got their own wind-sway pass, this is water's).
## A translucent hex drawn over every water cell, with a canvas_item
## fragment shader (water_shimmer.gdshader) scattering sparse point glints in
## world space -- same "GPU does the animating, GDScript just redraws flat
## shapes every frame" split as tree_sway.gdshader, so the cost of animating
## stays flat no matter how many water cells are on screen.
##
## Redesigned 2026-10-29 (user's ask: the original single continuously
## scrolling diagonal band "looks too static" -- the same band sliding at a
## constant speed forever reads as mechanical, not alive). The shader now
## scatters a jittered-grid field of point glints across world space instead;
## each point flashes briefly on its own randomized cycle, so what's visible
## at any moment is a handful of occasional, independently-timed sparkles
## rather than one coherent shape in constant motion. Reading world position
## (not local/UV space) is what keeps a glint from restarting at a hex
## boundary -- which lattice cell a glint belongs to, and when it flashes,
## depends only on world position and TIME, never on which polygon happens to
## be drawn under it.
##
## Always visible, NOT x-ray-gated -- ambient mood only, never simulation
## data, so it stays on in both modes (brief §6: "...never obscure critical
## simulation information").
##
## Hex outline math is the same HexMath.hex_points()-plus-grid_size scaling
## grid_outline.gd already uses, so this overlay's polygons align exactly
## with the real tile edges -- deliberately not re-derived independently.
## GridOutline itself (not this file) is what keeps water-water seams
## invisible: it skips drawing a grid line across any edge where both cells
## are water, so a connected lake/river reads as one open surface rather than
## a lattice of individually outlined hexes.

const HexMath = preload("res://scripts/rendering/hex_math.gd")
const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const World = preload("res://scripts/rendering/world.gd")
const SHIMMER_SHADER = preload("res://scripts/rendering/shaders/water_shimmer.gdshader")

@export var grid_size: Vector2 = Vector2(World.TILE_SIZE)
@export var shimmer_color: Color = Color(1.0, 1.0, 1.0, 0.18) ## base translucent wash drawn over every water cell, before the shader's glints add further brightness

## Inspector-tunable per the usual practice (memory/feedback_expose_visual_tuning.md).
@export_range(8.0, 200.0) var glint_cell_size: float = 40.0 ## world px per lattice cell -- larger = sparser glints
@export_range(1.0, 40.0) var glint_radius_px: float = 6.0 ## size of one glint
@export_range(0.02, 3.0) var glint_frequency: float = 0.35 ## flashes per second, per point
@export_range(0.02, 0.9) var glint_duration: float = 0.25 ## fraction of each point's own cycle it's visible for
@export_range(0.0, 1.0) var glint_strength: float = 0.6 ## peak opacity boost at a glint's centre
@export var glint_tint: Color = Color(1.0, 0.98, 0.85, 1.0) ## warm pale highlight colour a glint shifts toward
@export_range(0.0, 1.0) var glint_tint_strength: float = 0.35 ## how much a glint also shifts colour, not just opacity

var _ground: TileMapLayer
var _cells: Array[Vector2i] = []

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHIMMER_SHADER
	material = mat
	_push_shader_params()

func _push_shader_params() -> void:
	if material == null:
		return
	material.set_shader_parameter("glint_cell_size", glint_cell_size)
	material.set_shader_parameter("glint_radius_px", glint_radius_px)
	material.set_shader_parameter("glint_frequency", glint_frequency)
	material.set_shader_parameter("glint_duration", glint_duration)
	material.set_shader_parameter("glint_strength", glint_strength)
	material.set_shader_parameter("glint_tint", glint_tint)
	material.set_shader_parameter("glint_tint_strength", glint_tint_strength)

func configure(ground: TileMapLayer, cells: Array[Vector2i]) -> void:
	_ground = ground
	_cells = cells
	queue_redraw()

## Only redraws while actually shown, same reasoning as flow_overlay.gd's
## guard -- no point reissuing a polygon per water cell every frame for an
## overlay nobody can see (not that this one is ever hidden today, but the
## guard costs nothing and matches the sibling overlays' convention).
func _process(_delta: float) -> void:
	if not visible or _ground == null:
		return
	queue_redraw()

func _outline_points() -> PackedVector2Array:
	var unit := HexMath.hex_points(1.0)
	var scale_x: float = grid_size.x / 2.0
	var scale_y: float = grid_size.y / sqrt(3.0)
	var points := PackedVector2Array()
	for p in unit:
		points.append(Vector2(p.x * scale_x, p.y * scale_y))
	return points

func _draw() -> void:
	if _ground == null:
		return
	var outline := _outline_points()
	for axial in _cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		var center: Vector2 = to_local(_ground.to_global(_ground.map_to_local(offset)))
		var points := PackedVector2Array()
		for p in outline:
			points.append(center + p)
		draw_colored_polygon(points, shimmer_color)
