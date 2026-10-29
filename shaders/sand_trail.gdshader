shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Carved groove in the sand: multiplies the sand underneath, darker in the furrow,
// slightly brighter on the two raised rims, fading with age (vertex alpha).

uniform vec3 furrow : source_color = vec3(0.72, 0.68, 0.7);
uniform float rim_brightness = 1.12;

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float groove = 1.0 - smoothstep(0.15, 0.65, across);
	float rim = smoothstep(0.55, 0.78, across) * (1.0 - smoothstep(0.82, 1.0, across));
	vec3 tint = mix(vec3(1.0), furrow, groove) * mix(1.0, rim_brightness, rim);
	ALBEDO = mix(vec3(1.0), tint, COLOR.a);
}
