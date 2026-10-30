extends RefCounted

## Generates a soft, radially-fading dark blob for a feature's contact
## shadow -- same "compute it from math, not an imported asset" approach as
## hex_tile_texture.gd, so a shadow never needs its own art pass and scales
## cleanly to whatever feature it sits under. Caller squashes it into an
## oval with Sprite2D.scale rather than baking an ellipse here -- keeps this
## generator reusable for any future non-tree feature too. `color`'s alpha
## is the falloff's peak strength (1.0 = fully opaque at the center); overall
## shadow strength is controlled separately via the caller's Sprite2D.modulate
## (world.gd's tree_shadow_opacity export), not baked in here, so there's one
## tunable knob instead of two multiplying each other.

static func generate(diameter_px: float, color: Color = Color(0, 0, 0, 1.0)) -> ImageTexture:
	var size: int = maxi(int(ceil(diameter_px)), 2)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var center := Vector2(size, size) / 2.0
	var radius: float = size / 2.0
	for y in range(size):
		for x in range(size):
			var p := Vector2(x + 0.5, y + 0.5) - center
			var t: float = p.length() / radius
			if t <= 1.0:
				# Quadratic falloff, not a hard-edged disc -- blends into the
				# ground instead of reading as a sticker.
				var a: float = (1.0 - t * t) * color.a
				image.set_pixel(x, y, Color(color.r, color.g, color.b, a))

	return ImageTexture.create_from_image(image)
