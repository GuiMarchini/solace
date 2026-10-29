shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;
// The spectral blade of the Last Spirit: the sword's shape grown huge, made of dark
// condensed smoke that boils along it, its edges and the rune line burning amber.
// `form` 0 -> 1 condenses it (smoke gathering from the grip outward), back to 0 frays it.

#include "res://shaders/smoke_common.gdshaderinc"

uniform vec3 smoke_color : source_color = vec3(0.02, 0.018, 0.02);
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.2);
uniform float form : hint_range(0.0, 1.0) = 0.0;
uniform float glow = 1.0;

varying vec3 obj;

void fragment() {
	float t = TIME;
	float n = fbm(obj * vec3(7.0, 7.0, 3.0) + vec3(0.0, 0.0, -t * 1.6));
	// Condenses from the grip (+Z) toward the tip (-Z).
	float along = clamp((1.0 - obj.z) / 2.4, 0.0, 1.0);
	float shown = smoothstep(along - 0.15, along, form * 1.2 - 0.1 + (n - 0.5) * 0.3);
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = smoothstep(0.45, 0.95, fres);
	float rune = 1.0 - smoothstep(0.004, 0.012, abs(obj.x));
	ALBEDO = smoke_color * (0.6 + 0.8 * n);
	EMISSION = glow_color * (edge * 1.6 + rune * 2.5 + smoothstep(0.65, 0.9, n) * 0.6) * glow * shown;
	ALPHA = clamp(shown * (0.75 + 0.25 * n), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}

void vertex() {
	obj = VERTEX;
}
