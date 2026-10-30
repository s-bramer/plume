shader_type canvas_item;

// Companion to tree_sway.gdshader: the contact shadow shifts sideways in
// sync with its own tree's canopy lean (same `phase`/`sway_speed`, a
// smaller `sway_amount_px`) instead of staying static underneath a moving
// canopy -- a flat ground shadow doesn't bend like the trunk shader above,
// it just slides, the way a canopy's shadow would track the canopy itself.

uniform float sway_amount_px : hint_range(0.0, 20.0) = 1.5;
uniform float sway_speed : hint_range(0.0, 3.0) = 0.6;
uniform float phase = 0.0;
// A visual-only "nudge down from the trunk" (world.gd's tree_shadow_offset).
// Deliberately NOT applied via Sprite2D.position: Y-sort reads the node's
// own position directly, and a south-shifted shadow node would sort as
// "further forward" than its own tree and paint over the trunk instead of
// under it on the grass (the actual bug this shader version fixes). A
// vertex-shader offset is invisible to Y-sort -- it only ever moves pixels.
uniform vec2 offset_px = vec2(0.0, 0.0);

void vertex() {
	VERTEX.x += sin(TIME * sway_speed + phase) * sway_amount_px;
	VERTEX += offset_px;
}
