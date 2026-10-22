extends RefCounted

## Generates a flat-color hex tile texture at runtime (a solid flat-top
## hexagon, optional border), instead of using third-party art for the
## ground. This exists specifically to eliminate the class of problem that
## took up most of this session: external art whose silhouette doesn't
## match true hexagon geometry needs empirically-tuned overlap to tile
## without gaps, which then can't be matched by any single "correct" grid
## outline size. A hex generated from HexMath's own formulas has no
## silhouette to disagree with -- it IS the math, by construction.

const HexMath = preload("res://scripts/rendering/hex_math.gd")

static func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq: float = ab.length_squared()
	var t: float = 0.0 if len_sq == 0.0 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)

static func _min_distance_to_edges(p: Vector2, points: PackedVector2Array) -> float:
	var min_dist: float = INF
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		min_dist = minf(min_dist, _point_to_segment_distance(p, a, b))
	return min_dist

## canvas_size should be big enough to contain a hex of hex_size with a
## little margin (caller's responsibility -- this just rasterizes).
##
## shading_strength adds a soft radial vignette to the fill (full fill_color
## at the centre, darkening smoothly toward the edge/border) so a flat
## terrain color doesn't read as a dead-flat sprite -- purely a per-pixel
## brightness falloff computed from the same hex math, not an external
## texture, so it can't introduce a silhouette mismatch. 0.0 (default) keeps
## the old flat fill.
static func generate(hex_size: float, canvas_size: Vector2i, fill_color: Color,
		border_color: Color = Color(0, 0, 0, 0), border_width: float = 0.0,
		shading_strength: float = 0.0) -> ImageTexture:
	var points := HexMath.hex_points(hex_size)
	var image := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var center := Vector2(canvas_size.x / 2.0, canvas_size.y / 2.0)
	for y in range(canvas_size.y):
		for x in range(canvas_size.x):
			var p := Vector2(x + 0.5, y + 0.5) - center
			if Geometry2D.is_point_in_polygon(p, points):
				if border_width > 0.0 and _min_distance_to_edges(p, points) < border_width:
					image.set_pixel(x, y, border_color)
				else:
					var t: float = clampf(p.length() / hex_size, 0.0, 1.0)
					var shade: float = 1.0 - shading_strength * t
					image.set_pixel(x, y, Color(fill_color.r * shade, fill_color.g * shade, fill_color.b * shade, fill_color.a))

	return ImageTexture.create_from_image(image)
