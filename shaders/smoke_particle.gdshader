shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled;
// Billboarded puff of ink-like smoke for GPUParticles3D: a dense, dark, lumpy core that
// thins into lighter translucent sheets at its edge, curling around a slow vortex, with
// a faint brighter filament where a sheet folds. Dense smoke absorbs (darker), thin
// smoke scatters (lighter), and a rounded "volume" normal lets the sun shade it (darker
// underside, lit top). Rotated per particle; colour and fade come from the particle
// colour ramp. No proximity fade, so puffs can be born inside the body.

uniform float softness = 0.5;
uniform float churn = 0.5;
uniform float lumpiness = 0.9;
// How far the puff's inside turns relative to its rim (rad): noise curls into scrolls.
uniform float curl = 1.6;
// Thin sheets and filaments trailing past the dense core.
uniform float sheets = 0.7;
// How much denser parts darken (1 = ink-like smoke; low = bright, sunlit sand puffs).
uniform float absorb = 1.0;
// 0 = shaded as a rounded puff facing the camera; 1 = lit like the ground it rose from
// (sand dust: matches the dunes' tone under a low sun instead of glowing white).
uniform float ground_lit = 0.0;

varying float seed;
varying float spin;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 5.3) * 0.3 + vnoise(p * 4.3 + 1.7) * 0.15;
}

void vertex() {
	seed = INSTANCE_CUSTOM.z * 37.0 + float(INSTANCE_ID) * 0.37;
	spin = INSTANCE_CUSTOM.x;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p0 = UV - 0.5;
	float t = TIME * churn;
	float r0 = min(length(p0) * 2.0, 1.0);
	// Vortex: the inside turns further than the rim, so the noise curls into scrolls.
	float a = spin * 6.2832 + seed + curl * (1.0 - r0) * (1.0 - r0) * sin(t * 0.7 + seed);
	vec2 p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p0;
	vec2 warp = vec2(fbm2(p * 3.0 + vec2(seed, t)), fbm2(p * 3.0 + vec2(t, seed * 1.3))) - 0.5;
	float n = fbm2(p * 4.5 + warp * 1.8 + vec2(seed * 0.7, -t));
	float d = length(p0 + warp * 0.2) * 2.0;
	float body = d + (n - 0.5) * lumpiness;
	float density = (1.0 - smoothstep(1.0 - softness, 1.0, body)) * (0.5 + 0.5 * n);
	// A thin sheet trailing past the core, with a brighter filament along its fold.
	float sn = fbm2(p * 7.0 + warp * 3.0 + vec2(-t * 0.6, seed));
	float sheet = (1.0 - smoothstep(0.85, 1.2, body)) * smoothstep(0.45, 0.7, sn) * sheets;
	float fw = max(fwidth(sn), 0.002);
	float fil = (1.0 - smoothstep(0.0, fw * 2.0, abs(sn - 0.58))) * (1.0 - smoothstep(0.75, 1.15, body)) * sheets;
	float dens = max(density, sheet * 0.35);
	vec2 q = p0 * 2.0 + warp * 0.6;
	vec3 puff_n = normalize(vec3(q.x, -q.y, sqrt(max(0.0, 1.0 - min(dot(q, q), 1.0))) + 0.25));
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(puff_n, normalize(up + puff_n * 0.35), ground_lit));
	ALBEDO = COLOR.rgb * mix(1.0 + 0.6 * absorb, 1.0 - 0.4 * absorb, smoothstep(0.1, 0.8, dens)) + COLOR.rgb * 2.0 * fil;
	ALPHA = COLOR.a * clamp(dens + fil * 0.25, 0.0, 1.0);
}
