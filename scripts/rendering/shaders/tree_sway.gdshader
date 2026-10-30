shader_type canvas_item;

// Bends a tree sprite's canopy back and forth from a fixed trunk base,
// instead of rotating/translating the whole sprite uniformly -- the trunk
// (UV.y = 1.0, the bottom of the texture, which _add_feature's ground_anchor
// places at this node's local origin) never moves, and the lean grows toward
// the canopy (UV.y = 0.0) the way a real trunk only bends near its crown.
// `phase` is set per-tree from a deterministic hash of its cell (world.gd's
// _pseudo_random01) so a forest doesn't sway in lockstep.

uniform float sway_amount_px : hint_range(0.0, 20.0) = 5.0;
uniform float sway_speed : hint_range(0.0, 3.0) = 0.6;
uniform float phase = 0.0;

void vertex() {
	float lean = sin(TIME * sway_speed + phase) * sway_amount_px;
	VERTEX.x += lean * (1.0 - UV.y);
}
