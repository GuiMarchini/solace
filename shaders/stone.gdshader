shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Weathered stone for the ruins and the sandstone formations, painted rather than
// photographic. Everything is in world space (no UVs, no tiling):
//   * sandstone: soft horizontal strata in cream, rose and burnt orange, warped so the
//     layers wander, with darker seams between them;
//   * masonry (ruins): pale limestone, block joints in world space, faded carvings;
//   * erosion: broad colour drift and fine pitting from 3D noise, faded with distance
//     before it can shimmer; cavities (vertex colour R) darkened, worn edges (G) paler;
//   * sand: settles on upward faces and climbs the foot of every piece from the dunes
//     (`bury_y`, per instance), in the same colour as the dunes;
//   * a faint cool bounce in the shade and a soft warm rim toward the low sun.

uniform vec3 stone_light : source_color = vec3(0.93, 0.77, 0.62);
uniform vec3 stone_mid : source_color = vec3(0.82, 0.58, 0.44);
uniform vec3 stone_dark : source_color = vec3(0.6, 0.38, 0.3);
uniform vec3 seam_color : source_color = vec3(0.42, 0.26, 0.22);
uniform vec3 sand_color : source_color = vec3(0.93, 0.6, 0.38);
// 0 = masonry (ruins), 1 = sandstone strata.
uniform float strata = 1.0;
uniform float strata_scale = 0.32;
uniform float block_size = 1.6;
uniform float sand_on_top = 0.8;
uniform float sand_at_foot = 2.2;
uniform float detail_distance = 90.0;
uniform float roughness_base = 0.88;
uniform vec3 shade_bounce : source_color = vec3(0.45, 0.42, 0.62);
uniform float glyph_glow = 0.0;
uniform vec3 glyph_color : source_color = vec3(0.45, 0.85, 1.0);

instance uniform float bury_y = -10000.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(detail_distance * 0.4, detail_distance, dist);
	vec3 n = normalize(wnrm);

	// Broad drift of colour over the whole piece (metres to tens of metres).
	float broad = fbm(wpos * 0.035, 3);
	float mid = fbm(wpos * 0.22 + vec3(5.0), 3);

	vec3 col;
	if (strata > 0.5) {
		// Strata: horizontal layers, warped, alternating tones, with dark seams.
		float y = wpos.y * strata_scale + (broad - 0.5) * 3.0 + (mid - 0.5) * 0.6;
		float layer = fract(y);
		float id = floor(y);
		float tone = hash13(vec3(id, 3.1, 7.7));
		col = mix(stone_mid, stone_light, smoothstep(0.25, 0.85, tone));
		col = mix(col, stone_dark, smoothstep(0.82, 1.0, tone) * 0.7);
		float seam = smoothstep(0.06, 0.0, layer) + smoothstep(0.94, 1.0, layer) * 0.5;
		col = mix(col, seam_color, seam * 0.55 * (0.4 + 0.6 * smoothstep(0.3, 0.9, 1.0 - abs(n.y))));
	} else {
		// Masonry: pale stone, faint joints between blocks laid in courses.
		col = mix(stone_mid, stone_light, smoothstep(0.3, 0.75, broad + (mid - 0.5) * 0.4));
		vec3 q = wpos / block_size;
		q.x += floor(q.y) * 0.5;
		q.z += floor(q.y) * 0.37;
		vec3 jf = abs(fract(q) - 0.5);
		float jx = (abs(n.x) > abs(n.z)) ? jf.z : jf.x;
		float joint = max(smoothstep(0.47, 0.5, jf.y), smoothstep(0.475, 0.5, jx)) * (1.0 - abs(n.y));
		col = mix(col, seam_color, joint * 0.4 * near);
		col = mix(col, stone_dark, smoothstep(0.55, 0.85, mid) * 0.3);
	}

	// Fine pitting and wear, only up close.
	float fine = fbm(wpos * 2.3, 3);
	col *= 1.0 + (fine - 0.5) * 0.35 * near;
	// Cavities darker, worn edges paler (vertex colour from the builders).
	col *= mix(0.62, 1.0, COLOR.r);
	col = mix(col, stone_light * 1.05, COLOR.g * 0.35);

	// Sand settled on the tops and drifted against the foot.
	float top = smoothstep(0.55, 0.9, n.y + (mid - 0.5) * 0.5);
	float foot = 1.0 - smoothstep(0.0, sand_at_foot, wpos.y - bury_y + (mid - 0.5) * 1.6);
	float sand = clamp(top * sand_on_top + foot, 0.0, 1.0);
	col = mix(col, sand_color * (0.95 + 0.1 * fine), sand);

	// Faint carved glyphs (ruins that still hold a little light).
	if (glyph_glow > 0.0) {
		vec2 g = vec2(atan(wpos.x, wpos.z) * 6.0, wpos.y * 1.3);
		float line = smoothstep(0.08, 0.0, abs(fract(g.y) - 0.5) - 0.42) * step(0.6, hash13(floor(vec3(g, 1.0))));
		EMISSION = glyph_color * line * glyph_glow * (1.0 - sand);
	}

	ALBEDO = col;
	ROUGHNESS = roughness_base - sand * 0.08;
	SPECULAR = 0.25;
	// Shade bounce: surfaces facing away from the sky catch a cool light from it, and
	// downward faces a warm bounce from the sand.
	vec3 sky_bounce = shade_bounce * 0.03 * (0.5 + 0.5 * n.y);
	vec3 sand_bounce = sand_color * 0.08 * clamp(1.0 - n.y, 0.0, 1.0) * 0.5;
	EMISSION += (sky_bounce + sand_bounce) * col;
}
