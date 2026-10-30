shader_type canvas_item;

// Slow drifting cloud shadows across the whole map -- a single static rect
// (see cloud_shadow_overlay.gd) with THIS shader painting soft, irregular
// shadow patches via fractal value noise sampled in WORLD space (not UV), so
// the pattern reads as one continuous sky's worth of cloud cover drifting
// overhead, never restarting or visibly tiling at any boundary.

uniform vec4 cloud_color : source_color = vec4(0.05, 0.08, 0.14, 0.35);
uniform float cloud_scale : hint_range(0.0003, 0.02) = 0.0025; // world-space noise frequency -- smaller = larger clouds
uniform vec2 cloud_speed_px_s = vec2(6.0, 2.5); // drift velocity, world px/sec
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45; // higher = more of the sky covered
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.35; // edge blur of a cloud's silhouette

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Same cheap, deterministic hash family as water_shimmer.gdshader's glint
// field -- no texture lookup, no RNG/seed to manage.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Classic bilinear value noise: hash the 4 corners of the unit cell `p`
// falls in, smoothstep-interpolate between them.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian motion: layers value_noise at doubling frequency and
// halving amplitude -- the standard way to turn blocky single-octave value
// noise into the softer, more organic/cloud-like shapes this needs.
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * value_noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 p = (world_pos + cloud_speed_px_s * TIME) * cloud_scale;
	float n = fbm(p);
	// cloud_coverage shifts the threshold band: higher coverage = more of
	// the noise field clears it = more sky in shadow. cloud_softness widens
	// or narrows the smoothstep band that blurs a cloud's edge rather than
	// giving it a hard, unrealistic silhouette line.
	float edge0 = 1.0 - cloud_coverage - cloud_softness * 0.5;
	float edge1 = 1.0 - cloud_coverage + cloud_softness * 0.5;
	float shadow = smoothstep(edge0, edge1, n);
	COLOR = cloud_color;
	COLOR.a *= shadow;
}
