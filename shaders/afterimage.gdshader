shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_back, shadows_disabled;
// Dash afterimage: a fading blue-white silhouette with a bright fresnel edge.

uniform vec3 color : source_color = vec3(0.55, 0.82, 1.0);
uniform float alpha = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color * (0.6 + 1.4 * fres);
	ALPHA = clamp(alpha * (0.25 + 0.6 * fres), 0.0, 1.0);
}
