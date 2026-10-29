shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Soft additive glow. mode 0: radial blob on a quad (board hover cushion, halo glow).
// mode 1: vertical light beam on a cylinder (distant beacon), fading upward.

uniform vec3 color : source_color = vec3(0.55, 0.86, 1.0);
uniform float intensity = 1.0;
uniform int mode = 0;
uniform float beam_fade_power = 1.6;

void fragment() {
	float a = 0.0;
	if (mode == 0) {
		vec2 p = UV * 2.0 - 1.0;
		a = pow(clamp(1.0 - length(p), 0.0, 1.0), 2.2);
	} else {
		float ndv = abs(dot(NORMAL, VIEW));
		a = pow(ndv, 2.0) * pow(1.0 - UV.y, beam_fade_power) * smoothstep(1.0, 0.97, 1.0 - UV.y);
		a *= 0.75 + 0.25 * sin(TIME * 0.7 + UV.y * 9.0);
	}
	ALBEDO = color * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
