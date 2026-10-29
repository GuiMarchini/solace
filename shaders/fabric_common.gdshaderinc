// Worn-cloth patterns shared by the cloak, hood and strips. Coordinates are in metres
// on the cloth (2D) or in object space (3D), so the scale is the same everywhere.

float fab_h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float fab_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fab_h21(i), fab_h21(i + vec2(1, 0)), f.x), mix(fab_h21(i + vec2(0, 1)), fab_h21(i + vec2(1, 1)), f.x), f.y);
}

float fab_fbm(vec2 p) {
	return (fab_noise(p) * 0.5 + fab_noise(p * 2.07 + 3.1) * 0.3 + fab_noise(p * 4.13 + 7.7) * 0.2);
}

// Burgundy cloth: large faded patches, mid-scale mottling and a fine fibre grain.
// `wear` (0..1) fades and lightens it (edges, ridges, sun-bleached areas).
vec3 fab_color(vec2 p, vec3 base, vec3 faded, float wear) {
	float big = fab_fbm(p * 1.4);
	float mid = fab_noise(p * 6.5);
	float grain = fab_noise(p * vec2(140.0, 60.0)) * 0.6 + fab_noise(p * 31.0) * 0.4;
	vec3 c = mix(base, faded, clamp(smoothstep(0.4, 0.85, big) * 0.55 + wear * 0.75, 0.0, 1.0));
	return c * (0.88 + 0.16 * mid + 0.1 * (grain - 0.5));
}

// Faint light marks like worn embroidery or fine cracks: thin isolines of a noise
// field, appearing in patches.
float fab_marks(vec2 p) {
	float n = fab_fbm(p * 14.0 + 1.3);
	float line = 1.0 - smoothstep(0.0, 0.004, abs(n - 0.5));
	float patch = smoothstep(0.62, 0.85, fab_noise(p * 2.2 + 5.0));
	return line * patch;
}

// Worn, cracked cloth: thin light lines along the edges of irregular cells (Voronoi
// F2 - F1), in patches, faded out before they get thinner than a pixel.
float fab_cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(fab_h21(i + g), fab_h21(i + g + 17.31));
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float e = sqrt(d2) - sqrt(d1);
	float w = max(0.03, fwidth(e) * 1.5);
	float line = 1.0 - smoothstep(0.0, w, e);
	float fade = 1.0 - smoothstep(0.08, 0.3, fwidth(p.x) + fwidth(p.y));
	// Broken, sparse lines: only some stretches of some cell edges survive.
	float broken = smoothstep(0.45, 0.7, fab_noise(p * 2.3 + 11.0));
	return line * fade * broken * smoothstep(0.4, 0.7, fab_noise(p * 0.35 + 3.0));
}

// Dashed stitching `d` metres from a seam, `along` metres along it.
float fab_stitch(float d, float along) {
	return (1.0 - smoothstep(0.0018, 0.0042, abs(d))) * step(0.5, fract(along * 48.0));
}
