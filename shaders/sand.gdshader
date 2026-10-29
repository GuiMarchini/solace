shader_type spatial;
// Desert sand, art-directed as a sea of sand: a rich warm orange that deepens into red-
// brown shade, broad soft tonal drifts across the dunes, paler wind-sorted crests and
// darker troughs, a soft "hammered" mottling and a fine grain near the camera, faint
// wind ripples only on the gentle windward flats, and a velvety custom light() (soft
// terminator, broad low sheen toward the sun, sparse glints). Fine detail is band-
// limited (faded before it gets smaller than a pixel) so the dunes never shimmer.

uniform vec3 sand_light : source_color = vec3(0.98, 0.7, 0.43);
uniform vec3 sand_mid : source_color = vec3(0.93, 0.56, 0.31);
uniform vec3 sand_dark : source_color = vec3(0.8, 0.42, 0.22);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// Slopes turned away from the low sun shift toward this (warm red-brown) shade.
uniform vec3 shade_tint : source_color = vec3(0.8, 0.46, 0.4);
uniform float shade_strength = 0.4;
global uniform vec3 sun_direction;

uniform vec2 wind_dir = vec2(0.42, 0.91);
uniform float ripple_frequency = 9.0;
uniform float ripple_strength = 0.05;
uniform float ripple_fade_start = 8.0;
uniform float ripple_fade_end = 38.0;
// Soft hammered mottling: size of its cells (m), how much it bends the light, and how
// far from the camera it fades out (m).
uniform float mottle_size = 1.1;
uniform float mottle_strength = 0.45;
uniform float mottle_distance = 45.0;
uniform float grain_strength = 0.07;

uniform float crest_highlight = 0.45;
uniform float wrap = 0.08;
uniform float sheen_strength = 0.14;
uniform float rim_strength = 0.3;
uniform float glitter_density = 0.999;
uniform float glitter_strength = 3.0;
uniform float glitter_distance = 18.0;
// Patches of deep, loose sand (baked by DuneTerrain from softness_at): smoother, a
// little richer and paler, finely rippled and glinting, so the places where the sword
// throws up the most sand can be read from afar.
uniform sampler2D soft_map : filter_linear, repeat_disable;
uniform vec2 soft_map_origin = vec2(-640.0, -640.0);
uniform float soft_map_size = 1280.0;

varying vec3 world_pos;
varying float crest;
varying float glitter;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec2 hash22(vec2 p) {
	vec3 a = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	a += dot(a, a.yzx + 33.33);
	return fract((a.xx + a.yz) * a.zy);
}

// Soft domes over a jittered grid: each point rises as 1 - d^2 toward its cell centre,
// and neighbouring domes are blended with smooth weights so the seams between them stay
// round (a plain Voronoi crease reads as cracked mud). Returns the analytic gradient of
// the field (xy) and its height (z).
vec3 domes(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float wsum = 0.0;
	vec2 gsum = vec2(0.0);
	float hsum = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = 0.15 + 0.7 * hash22(i + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			float w = exp(-9.0 * d);
			wsum += w;
			// d/dp of (1 - |r|^2) with r = c - p is +2r.
			gsum += w * 2.0 * r;
			hsum += w * (1.0 - d);
		}
	}
	return vec3(gsum / wsum, hsum / wsum);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	crest = COLOR.r;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 xz = world_pos.xz;

	// Broad tonal drifts across the dunes, then mid-scale patches.
	float n_large = texture(noise_tex, xz * 0.0011).r;
	float n_broad = texture(noise_tex, xz * 0.0043 + 0.37).r;
	float n_mid = texture(noise_tex, xz * 0.012).r;
	float n_fine = texture(noise_tex, xz * 0.09).r;
	float soft = texture(soft_map, (xz - soft_map_origin) / soft_map_size).r;
	vec3 col = mix(sand_dark, sand_mid, smoothstep(0.22, 0.78, n_large));
	col = mix(col, sand_light, smoothstep(0.4, 0.85, n_broad) * 0.35);
	col *= 0.93 + 0.12 * smoothstep(0.25, 0.8, n_mid);
	// Wind-sorted fine sand makes crests paler; troughs collect darker grains.
	float c = clamp((crest - 0.5) * 2.0, -1.0, 1.0);
	col = mix(col, sand_light * 1.04, max(c, 0.0) * crest_highlight);
	col = mix(col, sand_dark * 0.88, max(-c, 0.0) * crest_highlight * 0.6);
	col *= mix(0.95, 1.04, n_fine);
	float slope = 1.0 - wn.y;
	col = mix(col, sand_dark * 0.95, smoothstep(0.2, 0.55, slope) * 0.2);
	// Slopes turned away from the low sun read deeper and redder.
	float away = smoothstep(0.15, -0.25, dot(wn, sun_direction));
	float lum = dot(col, vec3(0.3, 0.5, 0.2));
	col = mix(col, vec3(lum) * shade_tint * 1.3, away * shade_strength);
	// Loose sand: fresh and untouched, a richer, smoother orange.
	col = mix(col, col * vec3(1.1, 0.93, 0.8) + vec3(0.025, 0.006, 0.0), soft * 0.85);

	// Fine grain (fades out before it gets smaller than a pixel).
	float gfw = fwidth(xz.x * 7.0) + fwidth(xz.y * 7.0);
	float grain_vis = 1.0 - smoothstep(0.35, 0.9, gfw);
	float grain = hash13(vec3(floor(xz * 7.0), 3.0)) - 0.5;
	col *= 1.0 + grain * grain_strength * 2.0 * grain_vis;

	// Soft hammered mottling and faint ripples bend the normal (analytic, no tiling).
	vec2 grad = vec2(0.0);
	float mfw = fwidth(xz.x / mottle_size) + fwidth(xz.y / mottle_size);
	float mottle_vis = (1.0 - smoothstep(mottle_distance * 0.5, mottle_distance, dist))
			* (1.0 - smoothstep(0.25, 0.6, mfw));
	if (mottle_vis > 0.001) {
		vec3 dm = domes(xz / mottle_size + vec2(n_mid * 2.0));
		vec3 dm2 = domes(xz / (mottle_size * 0.45) + 17.0);
		grad += (dm.xy + dm2.xy * 0.4) * mottle_strength * 0.12 * mottle_vis * (1.0 - 0.6 * soft);
		col *= 1.0 + (dm.z - 0.5) * 0.035 * mottle_vis;
	}
	float fade = 1.0 - smoothstep(ripple_fade_start, ripple_fade_end, dist);
	float flat_ground = 1.0 - smoothstep(0.15, 0.35, slope);
	vec2 wd = normalize(wind_dir);
	float warp = (texture(noise_tex, xz * 0.03).r - 0.5) * 10.0;
	float ph = dot(xz, wd) * ripple_frequency * (1.0 + 1.3 * soft) + warp;
	float d = cos(ph) + 0.7 * cos(2.0 * ph);
	float patches = max(smoothstep(0.45, 0.75, n_mid + 0.15 * n_fine), soft);
	// Loose sand is finely, densely rippled by the wind, even on gentle slopes.
	float ground_ok = max(flat_ground, soft * (1.0 - smoothstep(0.35, 0.55, slope)));
	grad += wd * d * ripple_strength * (1.0 + 0.6 * soft) * fade * ground_ok * patches;
	vec3 pn = normalize(wn - vec3(grad.x, 0.0, grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);

	float g = 0.0;
	if (dist < glitter_distance) {
		vec3 cell = floor(world_pos * 40.0);
		float h = hash13(cell);
		vec3 vd = normalize(CAMERA_POSITION_WORLD - world_pos);
		float tw = hash13(cell + floor(vd * 7.0) * 13.0);
		g = step(glitter_density - 0.003 * soft, h) * step(0.55, tw) * (1.0 - dist / glitter_distance);
	}
	glitter = g;

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff / PI;

	vec3 h = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float lit = step(0.0, ndl);
	// Broad, soft "sea of sand" sheen when facing the sun.
	float sheen = pow(ndh, 36.0) * sheen_strength;
	// Grazing rim on lit crests.
	float rim = pow(1.0 - ndv, 5.0) * clamp(ndl * 2.0 + 0.1, 0.0, 1.0) * rim_strength;
	float sparkle = glitter * glitter_strength * pow(ndh, 6.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (sheen + rim * 0.15 + sparkle) * lit / PI;
}
