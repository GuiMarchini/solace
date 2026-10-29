shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// The cloak's cloth layers (mantle, capelet), deformed on the GPU.
//
// Cloak.gd simulates a coarse grid of control points (`ctrl`, row-major, `cols` x
// `rows`, in this mesh's space); this shader turns a dense UV grid into a smooth
// bicubic (Catmull-Rom) surface through them, then adds real fold geometry: rounded
// vertical ridges with sharp valleys, deeper toward the hem, with correct normals.
// The fragment stage paints worn burgundy cloth: faded patches and fibre grain,
// darker fold valleys, sun-caught ridges, frayed lighter edges, faint stitching and
// marks, a dark inside, and a torn hem of pointed shreds of uneven length.

#include "res://shaders/fabric_common.gdshaderinc"

uniform vec3 ctrl[400];
uniform int cols = 24;
uniform int rows = 15;
// Approximate size of the cloth (m): around, and from the shoulders down.
uniform vec2 cloth_size = vec2(2.2, 1.45);
uniform float fold_count = 11.0;
uniform float fold_depth = 0.04;
uniform float seed = 0.0;
uniform vec3 cloth : source_color = vec3(0.165, 0.046, 0.08);
uniform vec3 cloth_faded : source_color = vec3(0.44, 0.23, 0.275);
uniform vec3 inside : source_color = vec3(0.07, 0.02, 0.03);
uniform vec3 mark_color : source_color = vec3(0.72, 0.52, 0.54);
// Hem: most shreds end near `hem_start`, a few reach the full length.
uniform float hem_start = 0.74;
uniform float strip_count = 12.0;
uniform float tear = 1.0;
uniform float seams = 1.0;

varying float ridge;

vec3 cp(int i, int k) {
	return ctrl[clamp(k, 0, rows - 1) * cols + clamp(i, 0, cols - 1)];
}

vec3 cr(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

vec3 surf(vec2 uv) {
	float fu = clamp(uv.x, 0.0, 1.0) * float(cols - 1);
	float fv = clamp(uv.y, 0.0, 1.0) * float(rows - 1);
	int i = min(int(floor(fu)), cols - 2);
	int k = min(int(floor(fv)), rows - 2);
	float tu = fu - float(i);
	float tv = fv - float(k);
	vec3 r0 = cr(cp(i - 1, k - 1), cp(i, k - 1), cp(i + 1, k - 1), cp(i + 2, k - 1), tu);
	vec3 r1 = cr(cp(i - 1, k), cp(i, k), cp(i + 1, k), cp(i + 2, k), tu);
	vec3 r2 = cr(cp(i - 1, k + 1), cp(i, k + 1), cp(i + 1, k + 1), cp(i + 2, k + 1), tu);
	vec3 r3 = cr(cp(i - 1, k + 2), cp(i, k + 2), cp(i + 1, k + 2), cp(i + 2, k + 2), tu);
	return cr(r0, r1, r2, r3, tv);
}

// Hanging-cloth folds: |sin| gives rounded ridges and sharp valleys; the fold lines
// wander and multiply toward the hem, and vanish at the shoulders.
float fold(vec2 uv) {
	float depth = smoothstep(-0.15, 0.45, uv.y);
	float x = uv.x * fold_count;
	float w = x + 0.5 * sin(x * 0.83 + seed) + 0.35 * sin(uv.y * 2.3 + x * 0.37 + seed * 1.7);
	float main = abs(sin(3.14159 * w));
	float fine = abs(sin(3.14159 * (w * 2.2 + uv.y * 1.6 + seed)));
	return (main * 0.78 + fine * 0.22 - 0.58) * depth;
}

void vertex() {
	vec2 uv = UV;
	float e = 0.003;
	vec3 p = surf(uv);
	vec3 pu = surf(uv + vec2(e, 0.0)) - surf(uv - vec2(e, 0.0));
	vec3 pv = surf(uv + vec2(0.0, e)) - surf(uv - vec2(0.0, e));
	vec3 n = cross(pv, pu);
	n = length(n) > 1e-8 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	float f = fold(uv);
	float fu = (fold(uv + vec2(e, 0.0)) - fold(uv - vec2(e, 0.0))) * fold_depth;
	float fv = (fold(uv + vec2(0.0, e)) - fold(uv - vec2(0.0, e))) * fold_depth;
	VERTEX = p + n * f * fold_depth;
	vec3 nn = cross(pv + n * fv, pu + n * fu);
	NORMAL = length(nn) > 1e-8 ? normalize(nn) : n;
	ridge = f;
}

void fragment() {
	vec2 uv = UV;
	vec2 m = uv * cloth_size;
	// Torn hem: shreds of uneven length narrowing to ragged points.
	float x = uv.x * strip_count + 0.7 * fab_noise(vec2(uv.x * 9.0, seed));
	float cell = floor(x);
	float fx = fract(x);
	float r = fab_h21(vec2(cell, seed + 1.0));
	float r2 = fab_h21(vec2(cell, seed + 9.0));
	float len = mix(hem_start, 1.0, pow(r, 1.7));
	float tip = pow(abs(fx - 0.5) * 2.0, 1.1 + r2 * 1.5);
	float hem = len - tip * (0.06 + 0.16 * r) - fab_noise(uv * vec2(90.0, 14.0)) * 0.018;
	float edge_u = min(uv.x, 1.0 - uv.x) * cloth_size.x;
	float fray = fab_noise(vec2(uv.y * 60.0, uv.x * 3.0)) * 0.012;
	float keep = step(uv.y, mix(1.5, hem, tear)) * step(fray * tear, edge_u);
	// A few small worn holes, never near the shoulders.
	keep *= 1.0 - step(0.994, fab_noise(m * 9.0 + seed)) * step(0.45, uv.y) * tear;
	ALPHA = keep;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// Wear: frayed, lighter edges along the hem and front edges; sun on the ridges.
	float near_hem = 1.0 - smoothstep(0.0, 0.05, hem - uv.y);
	float near_edge = 1.0 - smoothstep(0.0, 0.04, edge_u);
	float crest = smoothstep(0.05, 0.3, ridge);
	float valley = smoothstep(-0.1, -0.45, ridge);
	vec3 c = fab_color(m, cloth, cloth_faded, max(near_hem, near_edge) * 0.8 + crest * 0.65);
	c *= 0.9 + 0.15 * fab_fbm(m * 5.0);
	c *= 1.0 - valley * 0.6;
	// Faint stitching along the front edges and a couple of seams, and worn marks.
	float st = fab_stitch(edge_u - 0.025, uv.y * cloth_size.y)
			+ fab_stitch((uv.x - 0.33) * cloth_size.x, uv.y * cloth_size.y)
			+ fab_stitch((uv.x - 0.67) * cloth_size.x, uv.y * cloth_size.y);
	c = mix(c, mark_color, clamp(st * 0.13 * seams + fab_marks(m) * 0.1 + fab_cracks(m * 5.5) * 0.045, 0.0, 0.5));
	if (!FRONT_FACING) {
		c = inside * (0.75 + 0.5 * fab_noise(m * 4.0)) * (1.0 - valley * 0.3);
	}
	ALBEDO = c;
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
	RIM = 0.5;
	RIM_TINT = 0.6;
	BACKLIGHT = cloth * 0.35;
}
