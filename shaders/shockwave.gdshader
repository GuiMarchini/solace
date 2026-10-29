shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// A shockwave rolling out over the sand (Shockwave: a quad lying on the ground, UV
// centred). A ring of thrown-up sand, bright on its leading edge, dark smoke trailing
// inside it, thinning and fading as it spreads; a faint amber flash at the start.

#include "res://shaders/smoke_common.gdshaderinc"

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sand_color : source_color = vec3(0.95, 0.68, 0.42);
uniform vec3 smoke_color : source_color = vec3(0.05, 0.04, 0.045);
uniform vec3 ember_color : source_color = vec3(1.0, 0.5, 0.2);
uniform float strength = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float n = noise3(vec3(cos(ang) * 3.0, sin(ang) * 3.0, progress * 3.0)) - 0.5;
	float front = pow(progress, 0.6);
	float width = mix(0.08, 0.22, progress);
	float d = r - front + n * 0.06;
	float ring = smoothstep(-width, 0.0, d) * (1.0 - smoothstep(0.0, width * 0.35, d));
	float inner = smoothstep(-width * 2.2, -width * 0.4, d) * (1.0 - smoothstep(-width * 0.4, 0.0, d));
	float fade = (1.0 - smoothstep(0.55, 1.0, progress)) * strength;
	vec3 c = mix(smoke_color, sand_color, ring);
	c += ember_color * (1.0 - smoothstep(0.0, 0.25, progress)) * ring * 0.8;
	ALBEDO = c;
	ALPHA = clamp((ring * 0.85 + inner * 0.45) * fade * step(r, 1.0), 0.0, 1.0);
}
