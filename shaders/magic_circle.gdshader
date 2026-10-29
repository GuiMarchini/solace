shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Summoning circle on the ground: concentric rings and glyph ticks that expand
// and fade as `progress` goes 0 -> 1.

uniform vec3 color : source_color = vec3(0.55, 0.86, 1.0);
uniform float progress = 1.0;
uniform float intensity = 2.0;

float ring(float d, float r, float w) {
	return 1.0 - smoothstep(0.0, w, abs(d - r));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float grow = 0.55 + 0.45 * (1.0 - pow(1.0 - progress, 3.0));
	float r = d / grow;
	float ang = atan(p.y, p.x);
	float spin = TIME * 0.6;
	float rings = ring(r, 0.92, 0.025) + ring(r, 0.78, 0.012) * 0.8 + ring(r, 0.45, 0.02) * 0.7;
	float ticks = step(0.94, abs(sin((ang + spin) * 12.0))) * step(0.79, r) * (1.0 - step(0.91, r));
	float runes = step(0.7, abs(sin((ang - spin * 1.5) * 6.0))) * ring(r, 0.62, 0.03);
	float wave = ring(r, progress * 1.1, 0.08) * (1.0 - progress);
	float fade = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.55, 1.0, progress));
	float a = (rings + ticks * 0.8 + runes * 0.6) * fade + wave * 1.5;
	ALBEDO = color * intensity;
	ALPHA = clamp(a * step(r, 1.05), 0.0, 1.0);
}
