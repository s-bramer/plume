extends Node2D

## Permanent, always-visible hex outline for every ground cell -- a real
## design element, not a debug tool. Distinct from DebugOverlay (dots/labels/
## crosshair, toggleable, diagnostic only).
##
## grid_size defaults to World.TILE_SIZE, which (as of the move to generated
## ground tiles, see world.gd/hex_tile_texture.gd and DECISIONS.md) is the
## TRUE regular-hexagon proportions the ground tiles are actually drawn at --
## so this outline traces the real tile edges exactly, with no overlap and
## no gap. Still exported in case the look ever needs hand-tuning, but there
## is no longer a tension between "non-overlapping" and "matches the art":
## the art IS this exact shape now.

const GodotHexOffset = preload("res://scripts/rendering/godot_hex_offset.gd")
const HexMath = preload("res://scripts/rendering/hex_math.gd")
const World = preload("res://scripts/rendering/world.gd")

@export var grid_size: Vector2 = Vector2(World.TILE_SIZE)
@export var line_color: Color = Color("5a5a5a") # even grey, per user reference
@export var line_width: float = 1.0

## "Sunken water" cue: a water cell's shore edge gets a darker, thicker line
## where it borders land -- but ONLY on the edges that would actually be
## visible, per the game's implied camera convention (looking south to
## north, i.e. the viewer sits south of the map looking up/north across it).
## A drop from land down to water shows its vertical "cliff face" on the side
## that faces the camera -- the SOUTH side of the land, which is the SAME
## edge as the NORTH side of the water. So only a water cell's three
## NORTH-facing edges (N, NE, NW -- the hex's upper half) can ever show a
## visible cliff; its three SOUTH-facing edges (S, SE, SW) face away from the
## camera and must stay plain, even where they also border land -- drawing a
## shore line there would be a cliff face pointed AT the unseen north side,
## which this camera could never actually see. This is why the fix is
## direction-aware, not "thicken every water/land boundary."
@export var shore_line_color: Color = Color("3a3a3a") # dark grey, noticeably darker than line_color's 5a5a5a without reading as black
## The straight-north shore edge -- most directly face-on to a south-facing
## camera, so the thickest of the three.
@export var shore_line_width: float = 5.0
## The two diagonal (NW/NE) shore edges -- foreshortened from this camera
## angle compared to the straight-north edge, so thinner reads as more
## correct depth rather than all three shore edges looking equally "flat."
@export var shore_line_width_diagonal: float = 3.0

## hex_points() order (see HexMath/_outline_points): corner i -> i+1 is edge
## i. For a flat-top hex these are, in order: SE, S, SW, NW, N, NE (edge0
## through edge5) -- verified against GodotHexOffset's own neighbor-offset
## derivation (DECISIONS.md, the flat-top switch), not re-guessed here.
## Only the three north-facing edges are shore candidates (see above).
const _SHORE_EDGE_INDICES: Array[int] = [3, 4, 5] # NW, N, NE
const _SHORE_EDGE_NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)] # must stay index-matched to _SHORE_EDGE_INDICES
const _SHORE_NORTH_EDGE_INDEX := 4 # the straight-north entry of _SHORE_EDGE_INDICES -- gets shore_line_width, not shore_line_width_diagonal

var _ground: TileMapLayer
var _cells: Array[Vector2i] = [] # axial (q, r), converted to Godot offset coords when drawing

func configure(ground: TileMapLayer, cells: Array[Vector2i]) -> void:
	_ground = ground
	_cells = cells
	queue_redraw()

func _outline_points() -> PackedVector2Array:
	var unit := HexMath.hex_points(1.0)
	var scale_x: float = grid_size.x / 2.0
	var scale_y: float = grid_size.y / sqrt(3.0)
	var points := PackedVector2Array()
	for p in unit:
		points.append(Vector2(p.x * scale_x, p.y * scale_y))
	return points

## True if `offset` is a real, placed water cell -- not an unset/off-map cell
## (get_cell_source_id returns -1 for those, which must NOT count as "land
## bordering this edge": the map's own outer boundary isn't a visible cliff,
## just where the world stops).
func _is_water(offset: Vector2i) -> bool:
	return _ground.get_cell_source_id(offset) == World.TERRAIN_WATER

## Pure query, no drawing -- _draw() and tests both call this directly, so
## the camera-facing rule (header comment above) is independently verifiable
## without needing to inspect actual rendered draw calls. True only when ALL
## of: this cell is water, edge_index is one of the three north-facing edges,
## and the neighbor across that specific edge is a real, placed, non-water
## cell.
func _is_shore_edge(axial: Vector2i, offset: Vector2i, edge_index: int) -> bool:
	if not _is_water(offset):
		return false
	var shore_idx := _SHORE_EDGE_INDICES.find(edge_index)
	if shore_idx == -1:
		return false
	var neighbor_axial := axial + _SHORE_EDGE_NEIGHBOR_OFFSETS[shore_idx]
	var neighbor_offset := GodotHexOffset.axial_to_offset(neighbor_axial)
	var neighbor_source := _ground.get_cell_source_id(neighbor_offset)
	return neighbor_source != -1 and neighbor_source != World.TERRAIN_WATER

## Pure query, same reasoning as _is_shore_edge -- directly testable, no
## rendering involved. Only meaningful when _is_shore_edge(..., edge_index)
## is already true.
func _shore_edge_width(edge_index: int) -> float:
	return shore_line_width if edge_index == _SHORE_NORTH_EDGE_INDEX else shore_line_width_diagonal

func _draw() -> void:
	if _ground == null:
		return
	var outline := _outline_points()
	for axial in _cells:
		var offset := GodotHexOffset.axial_to_offset(axial)
		var center: Vector2 = to_local(_ground.to_global(_ground.map_to_local(offset)))
		for i in range(6):
			var a: Vector2 = center + outline[i]
			var b: Vector2 = center + outline[(i + 1) % 6]
			if _is_shore_edge(axial, offset, i):
				draw_line(a, b, shore_line_color, _shore_edge_width(i), false)
			else:
				draw_line(a, b, line_color, line_width, false)
