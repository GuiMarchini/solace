shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;
// A long cloth banner hanging from a crossbar, rippling in the wind (vertex waves that
// grow toward the free end), woven in the colours of the pilgrims: deep wine with an
// ochre border, a column of diamond motifs and a faded golden glyph. UV.y = 0 at the bar.

uniform vec3 cloth : source_color = vec3(0.5, 0.12, 0.13);
uniform vec3 border : source_color = vec3(0.86, 0.55, 0.22);
uniform vec3 motif : source_color = vec3(0.95, 0.78, 0.45);
uniform vec2 wind_dir = vec2(0.42, 0.91);
uniform float wind_strength = 1.0;
instance uniform float seed = 0.0;

void vertex() {
	float hang = UV.y;
	float t = TIME * 2.2 + seed * 3.7;
	float wave = sin(t + hang * 4.5) * 0.5 + sin(t * 1.7 + hang * 9.0 + UV.x * 2.0) * 0.18;
	// The cloth streams with the wind and ripples across its face.
	vec3 off = vec3(0.0);
	off.z += wave * hang * 0.55 * wind_strength;
	off.x += sin(t * 0.8 + hang * 3.0) * hang * 0.15 * wind_strength;
	off.y += hang * hang * 0.08 * wind_strength * (0.5 + 0.5 * sin(t * 0.5));
	VERTEX += off;
}

float hash12(vec2 p) {
	vec3 a = fract(vec3(p.xyx) * 0.1031);
	a += dot(a, a.yzx + 33.33);
	return fract((a.x + a.y) * a.z);
}

void fragment() {
	vec2 uv = UV;
	// Frayed, torn free end.
	float tear = 0.94 - hash12(vec2(floor(uv.x * 14.0), seed)) * 0.12;
	if (uv.y > tear) {
		discard;
	}
	vec3 col = cloth;
	float b = step(uv.x, 0.09) + step(0.91, uv.x) + step(uv.y, 0.05);
	col = mix(col, border, clamp(b, 0.0, 1.0));
	// A column of diamonds down the middle.
	vec2 d = vec2(abs(uv.x - 0.5) * 2.4, abs(fract(uv.y * 5.0) - 0.5));
	float dia = step(d.x + d.y, 0.42) - step(d.x + d.y, 0.3);
	col = mix(col, motif, dia * step(0.1, uv.y) * step(uv.y, 0.85));
	// Sun-faded toward the free end, with a woven grain.
	col = mix(col, col * 1.25 + 0.05, uv.y * 0.35);
	col *= 0.92 + 0.08 * hash12(floor(uv * vec2(60.0, 200.0)));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = col * 0.5;
}
