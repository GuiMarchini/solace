shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The swept trail of a sword stroke (BladeTrail: UV.x = age 0 newest .. 1 oldest,
// UV.y = 0 at the grip .. 1 at the tip). Curling black smoke that thins and frays as it
// ages, with a thin amber edge where the blade has just passed (strongest at the tip).

#include "res://shaders/smoke_common.gdshaderinc"

uniform vec3 smoke_color : source_color = vec3(0.025, 0.022, 0.025);
uniform vec3 ember_color : source_color = vec3(1.0, 0.52, 0.22);
uniform float intensity = 1.0;

void fragment() {
	float age = UV.x;
	float along = UV.y;
	float n = fbm(vec3(age * 5.0 - TIME * 1.5, along * 6.0, TIME * 0.7));
	// Thicker toward the tip, fraying with age.
	float body = smoothstep(0.0, 0.35, along) * (1.0 - smoothstep(0.25, 1.0, age + (n - 0.5) * 0.6));
	float edge = (1.0 - smoothstep(0.0, 0.2, age)) * smoothstep(0.45, 1.0, along);
	ALBEDO = mix(smoke_color * (0.7 + 0.6 * n), ember_color * 2.2, edge * 0.9);
	ALPHA = clamp((body * (0.45 + 0.4 * n) + edge * 0.6) * intensity * COLOR.a, 0.0, 1.0);
}
