shader_type canvas_item;

// Screen-space falling streaks, drawn on a full-viewport ColorRect
// (rain_overlay.gd). FRAGCOORD is real screen pixels, independent of camera
// zoom/pan, so streak size/speed/density read consistently regardless of
// how far the player is zoomed in -- same reasoning as every HUD element in
// this project being screen-space, not world-space.
//
// One vertical "lane" of pixels every lane_width_px; each lane is either
// empty or carries exactly one falling streak, decided by a per-lane hash
// gated against density*rain_intensity (fewer active lanes = lighter rain).
// Within an active lane, the streak's vertical position cycles through a
// tile_height_px-tall repeating window over time (TIME * fall_speed_px_s),
// so it falls continuously and loops seamlessly, with its own random
// horizontal offset and phase so lanes don't all show a streak at the same
// height.
//
// fall_speed_px_s's sign IS the fall direction -- positive falls down
// (increasing screen Y, the normal case), negative falls up. The range
// below is deliberately signed/symmetric so that's a slider to drag, not a
// code change (user's ask, 2026-10-29: "is there a way to change its
// direction (add handle)" -- the streaks were falling bottom-to-top because
// the y math below used to ADD fall_speed_px_s*TIME instead of subtracting
// it, which moves the active window toward smaller Y -- up the screen --
// as TIME increases, regardless of fall_speed_px_s's own sign).
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 drop_color : source_color = vec4(0.75, 0.82, 0.92, 0.55);
uniform float lane_width_px : hint_range(4.0, 60.0) = 14.0;
uniform float tile_height_px : hint_range(40.0, 400.0) = 160.0;
uniform float fall_speed_px_s : hint_range(-3000.0, 3000.0) = 1100.0;
uniform float streak_length_px : hint_range(4.0, 80.0) = 24.0;
uniform float streak_width_px : hint_range(0.5, 6.0) = 1.5;
uniform vec2 wind_px_s = vec2(-60.0, 0.0);
uniform float slant : hint_range(-1.0, 1.0) = -0.15; // shears the lane grid sideways per unit of screen Y, for a wind-blown look
uniform float density : hint_range(0.0, 1.0) = 0.6; // fraction of lanes carrying a streak at rain_intensity == 1.0

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = FRAGCOORD.xy;
	p.x += p.y * slant;
	p += wind_px_s * TIME;

	float lane = floor(p.x / lane_width_px);
	float lane_h = hash12(vec2(lane, 0.0));
	float lane_mask = step(lane_h, density * rain_intensity); // 1.0 if this lane is active, else 0.0 -- no early return (Godot's fragment() doesn't allow one)

	float local_x = mod(p.x, lane_width_px);
	float offset_x = hash12(vec2(lane, 1.0)) * max(lane_width_px - streak_width_px, 0.0);
	float dx = abs(local_x - offset_x - streak_width_px * 0.5);
	float line_mask = 1.0 - smoothstep(streak_width_px * 0.5 - 0.5, streak_width_px * 0.5 + 0.5, dx);

	float phase = hash12(vec2(lane, 2.0)) * tile_height_px;
	float y = mod(p.y - fall_speed_px_s * TIME + phase, tile_height_px);
	float in_streak = step(y, streak_length_px);
	float taper = smoothstep(0.0, 4.0, y) * smoothstep(0.0, 4.0, streak_length_px - y);

	COLOR = drop_color;
	COLOR.a *= lane_mask * line_mask * in_streak * taper * rain_intensity;
}
