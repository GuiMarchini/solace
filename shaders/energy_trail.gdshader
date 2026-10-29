shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Additive ribbon for magical trails. UV.x = age (0 head .. 1 tail), UV.y = across.
// Vertex alpha carries the per-point fade computed on the CPU.

uniform vec3 color : source_color = vec3(0.55, 0.86, 1.0);
uniform float intensity = 2.5;
uniform float core_sharpness = 2.0;

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float core = pow(across, core_sharpness);
	float hot = pow(across, 8.0) * (1.0 - UV.x);
	ALBEDO = (color * core + vec3(1.0) * hot * 0.6) * intensity;
	ALPHA = clamp(COLOR.a * core, 0.0, 1.0);
}
