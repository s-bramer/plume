extends RefCounted

## Flat-top axial (q, r) hex coordinate math (flat edges top/bottom, pointy
## corners left/right -- the "map-like" orientation, switched from pointy-top
## per user request: it reads more like terrain tiles and matches most
## off-the-shelf hex art packs).
## Formulas: https://www.redblobgames.com/grids/hexagons/

const SQRT3 := 1.7320508075688772

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func axial_to_pixel(axial: Vector2i, size: float) -> Vector2:
	var x := size * (1.5 * axial.x)
	var y := size * (SQRT3 / 2.0 * axial.x + SQRT3 * axial.y)
	return Vector2(x, y)

static func pixel_to_axial(point: Vector2, size: float) -> Vector2i:
	var q := (2.0 / 3.0 * point.x) / size
	var r := (-1.0 / 3.0 * point.x + SQRT3 / 3.0 * point.y) / size
	return _axial_round(q, r)

static func _axial_round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq: float = round(q)
	var rr: float = round(r)
	var rs: float = round(s)
	var dq: float = abs(rq - q)
	var dr: float = abs(rr - r)
	var ds: float = abs(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))

static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2.0)

static func neighbors(axial: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in NEIGHBOR_OFFSETS:
		result.append(axial + offset)
	return result

## Returns every axial coordinate within `radius` hex-steps of the origin,
## forming a hexagonal map region (cube-coordinate distance filter).
static func cells_in_radius(radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r_min: int = max(-radius, -q - radius)
		var r_max: int = min(radius, -q + radius)
		for r in range(r_min, r_max + 1):
			result.append(Vector2i(q, r))
	return result

## Corner points of a flat-top hex of the given size, centered on the origin.
static func hex_points(size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle_rad := deg_to_rad(60.0 * i)
		points.append(Vector2(size * cos(angle_rad), size * sin(angle_rad)))
	return points
