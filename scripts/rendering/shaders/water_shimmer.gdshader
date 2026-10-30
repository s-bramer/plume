shader_type canvas_item;

// Sparse "sunlight glints on water" effect (replaces an earlier version that
// scrolled one continuous diagonal brightness band -- the user reported that
// read as too static/mechanical, since a single band sliding at constant
// speed is the same motion forever). Instead, scatters a field of point
// glints across WORLD space (not UV space -- water_shimmer_overlay.gd draws
// one flat translucent hex polygon per water cell, not a single textured
// quad, so there's no shared UV to drive this with) using a jittered-grid
// hash (classic "Worley/point noise" scatter): each world-space cell gets
// one random point, each point flashes briefly on its own randomized cycle.
// Reading each pixel's own world position means the whole lake/river is ONE
// continuous field -- a glint never restarts or resets at a hex boundary,
// it's simply wherever its own lattice cell places it, independent of which
// polygon happens to be drawn under it.

uniform float glint_cell_size : hint_range(8.0, 200.0) = 40.0; // world px per lattice cell -- controls how sparse the glints are
uniform float glint_radius_px : hint_range(1.0, 40.0) = 6.0; // size of one glint
uniform float glint_frequency : hint_range(0.02, 3.0) = 0.35; // flashes per second, per point
uniform float glint_duration : hint_range(0.02, 0.9) = 0.25; // fraction of each point's own cycle it's visible for
uniform float glint_strength : hint_range(0.0, 1.0) = 0.6; // peak opacity boost at a glint's centre
uniform vec4 glint_tint : source_color = vec4(1.0, 0.98, 0.85, 1.0); // warm pale highlight colour a glint shifts toward
uniform float glint_tint_strength : hint_range(0.0, 1.0) = 0.35; // how much a glint also shifts colour, not just opacity

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Cheap, standard hashes (no texture lookup needed) -- same "deterministic
// from input alone, no RNG/seed to manage" reasoning as World._pseudo_random01
// on the GDScript side, just in GLSL form since this runs per-pixel on the GPU.
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

void fragment() {
	vec2 cell_size = vec2(glint_cell_size);
	vec2 base_cell = floor(world_pos / cell_size);

	float brightness = 0.0;
	// Check the 3x3 neighborhood of lattice cells, not just the pixel's own
	// cell -- a point jittered near a cell's edge still needs to light up
	// pixels in the NEXT cell over, or glints would visibly clip at lattice
	// boundaries.
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 cell = base_cell + vec2(float(dx), float(dy));
			vec2 jitter = hash22(cell);
			vec2 point_pos = (cell + jitter) * cell_size;
			float dist = length(world_pos - point_pos);

			float point_phase = hash11(dot(cell, vec2(12.9898, 78.233)));
			float cycle = fract(TIME * glint_frequency + point_phase);
			float active = 1.0 - step(glint_duration, cycle); // 1 while cycle < glint_duration, else 0
			float t = clamp(cycle / max(glint_duration, 0.0001), 0.0, 1.0);
			float pulse = active * sin(t * PI); // smooth rise-then-fall within the active window

			float falloff = 1.0 - smoothstep(0.0, glint_radius_px, dist);
			brightness = max(brightness, falloff * pulse);
		}
	}

	// Modulate ALPHA for the opacity flare (the established fix for additive
	// RGB brightening clamping invisibly against a near-white base -- see
	// docs/DECISIONS.md), plus a modest colour mix toward glint_tint, which
	// stays visible even on a near-white base because it shifts HUE, not just
	// brightness.
	COLOR.rgb = mix(COLOR.rgb, glint_tint.rgb, brightness * glint_tint_strength);
	COLOR.a = clamp(COLOR.a + brightness * glint_strength, 0.0, 1.0);
}
