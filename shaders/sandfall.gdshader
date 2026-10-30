shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Sand pouring off a ledge: streaks of falling grains scrolling down a ribbon (UV.y = 0
// at the lip, 1 at the ground), thicker in the middle of the fall, fraying at its edges
// and spreading into dust near the bottom. Lit by hand: sunlit sand on the bright side.

uniform vec3 sand_lit : source_color = vec3(0.94, 0.7, 0.5);
uniform vec3 sand_shade : source_color = vec3(0.7, 0.47, 0.38);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float speed = 0.55;
uniform float opacity = 0.75;
global uniform vec3 sun_direction;

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float streaks = texture(noise_tex, vec2(uv.x * 3.0, uv.y * 0.6 - t)).r;
	float fine = texture(noise_tex, vec2(uv.x * 9.0 + 0.3, uv.y * 1.8 - t * 1.7)).r;
	float body = smoothstep(0.0, 0.35, uv.x) * smoothstep(1.0, 0.65, uv.x);
	float a = body * smoothstep(0.35, 0.75, streaks * 0.7 + fine * 0.5);
	// Thins as it falls, then billows into dust at the bottom.
	a *= mix(1.0, 0.55, uv.y) + smoothstep(0.8, 1.0, uv.y) * 0.5;
	a *= smoothstep(0.0, 0.04, uv.y);
	float lit = clamp(dot(normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), sun_direction) * 0.5 + 0.6, 0.0, 1.0);
	ALBEDO = mix(sand_shade, sand_lit, lit) * (0.9 + 0.2 * fine);
	ALPHA = clamp(a * opacity, 0.0, 1.0);
}
