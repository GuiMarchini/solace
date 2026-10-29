shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// The single point of light inside the hood: a warm amber four-pointed star with a
// long vertical ray, a shorter horizontal one and a soft core. Billboarded.

uniform vec3 color : source_color = vec3(1.0, 0.52, 0.16);
uniform float intensity = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float core = exp(-r * 44.0) * 2.6 + exp(-r * 18.0) * 0.1;
	float vray = exp(-abs(p.x) * 90.0) * exp(-abs(p.y) * 6.5);
	float hray = exp(-abs(p.y) * 90.0) * exp(-abs(p.x) * 11.0) * 0.7;
	vec2 d = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	float diag = (exp(-abs(d.x) * 120.0) * exp(-abs(d.y) * 26.0) + exp(-abs(d.y) * 120.0) * exp(-abs(d.x) * 26.0)) * 0.25;
	float a = (core + vray + hray + diag) * (1.0 - smoothstep(0.42, 0.5, r));
	ALBEDO = mix(color, vec3(1.0, 0.92, 0.75), clamp(core * 0.3, 0.0, 1.0)) * a * intensity;
}
