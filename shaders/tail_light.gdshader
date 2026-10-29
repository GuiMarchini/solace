shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The single point of light behind the sword: a camera-facing glow with a hot white
// core and a soft warm halo, gently flickering. Additive, fog-free (fog over an
// additive quad would show its square).

uniform vec3 color : source_color = vec3(1.0, 0.45, 0.25);
uniform float intensity = 1.3;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float flicker = 0.9 + 0.1 * sin(TIME * 23.0) * sin(TIME * 7.3);
	float core = exp(-r * r * 60.0);
	float halo = pow(clamp(1.0 - r, 0.0, 1.0), 2.4);
	ALBEDO = (vec3(1.0, 0.92, 0.82) * core * 2.2 + color * halo * 0.45) * intensity * flicker;
	ALPHA = clamp(core + halo, 0.0, 1.0);
}
