extends RefCounted

## Converts between this project's axial (q, r) hex coordinates (used by
## GridModel/HexMath -- the simulation's source of truth, per the brief's
## §7 coordinate convention) and the "odd-q" offset coordinates Godot's hex
## TileMapLayer actually uses for TILE_LAYOUT_STACKED + TILE_OFFSET_AXIS_
## VERTICAL (the flat-top hex configuration).
##
## This is the flat-top counterpart of the original odd-r scheme used for
## pointy-top hexes: Godot's STACKED layout is a discrete per-column-parity
## offset (odd columns shoved down by half a tile) once TILE_OFFSET_AXIS is
## VERTICAL, not continuous axial scaling. Still never feed axial (q, r)
## straight into set_cell()/map_to_local() -- convert through here first, per
## godot_hex_map_spec.md ("do not mix hand-coded axial-to-pixel formulas with
## TileMapLayer map coordinates"). Verified against HexMath across a wide
## (q, r) range in tests/run_tests.gd.
##
## Formula: https://www.redblobgames.com/grids/hexagons/#conversions-offset

static func axial_to_offset(axial: Vector2i) -> Vector2i:
	var row: int = axial.y + (axial.x - (axial.x & 1)) / 2
	return Vector2i(axial.x, row)

static func offset_to_axial(offset: Vector2i) -> Vector2i:
	var r: int = offset.y - (offset.x - (offset.x & 1)) / 2
	return Vector2i(offset.x, r)
