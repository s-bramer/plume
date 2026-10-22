extends Node2D

## X-ray-only subsurface geology fill (user's ask, 2026-10-21; brief SS12.5:
## "toggle geology/K"). A flat, semi-transparent color per cell keyed by
## GridModel.get_geology() -- deliberately simple (no texture/pattern), since
## this is a diagnostic subsurface-data layer, not surface art. Only ever
## visible during x-ray mode (World.set_xray_mode); the legend that makes the
## three colors readable is built by World (_build_xray_legend) as part of
## the screen-space HUD, not drawn here.

const HexMath = preload("res://scripts/rendering/hex_math.gd")
const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const GridModel = preload("res://scripts/simulation/grid_model.gd")
const World = preload("res://scripts/rendering/world.gd")

## Colors come from GridModel.GEOLOGY_COLOR, not a local table -- shared with
## World._build_xray_legend() so the fill and its legend can never drift out
## of sync with each other.
const FALLBACK_COLOR := Color.MAGENTA # loudly wrong if a 4th geology value is ever added and GridModel.GEOLOGY_COLOR isn't updated to match

@export_range(0.0, 1.0) var fill_alpha: float = 0.55

var _ground: TileMapLayer
var _model: GridModel
var _cells: Array[Vector2i] = []

func configure(ground: TileMapLayer, model: GridModel, cells: Array[Vector2i]) -> void:
	_ground = ground
	_model = model
	_cells = cells
	queue_redraw()

## Same hex-corner geometry GridOutline/HeadContourOverlay use, scaled to
## World.TILE_SIZE (the true, non-overlapping hex shape -- see world.gd's own
## header comment on why TILE_SIZE, not GROUND art's footprint, is the right
## size for anything geometric like this).
static func _hex_points() -> PackedVector2Array:
	var unit := HexMath.hex_points(1.0)
	var scale_x: float = World.TILE_SIZE.x / 2.0
	var scale_y: float = World.TILE_SIZE.y / sqrt(3.0)
	var points := PackedVector2Array()
	for p in unit:
		points.append(Vector2(p.x * scale_x, p.y * scale_y))
	return points

func _draw() -> void:
	if _model == null:
		return
	var points := _hex_points()
	for axial in _cells:
		var geo: int = _model.get_geology(axial)
		var color: Color = GridModel.GEOLOGY_COLOR.get(geo, FALLBACK_COLOR)
		var offset := GodotHexOffset.axial_to_offset(axial)
		var center: Vector2 = to_local(_ground.to_global(_ground.map_to_local(offset)))
		var poly := PackedVector2Array()
		for p in points:
			poly.append(center + p)
		draw_colored_polygon(poly, Color(color.r, color.g, color.b, fill_alpha))
