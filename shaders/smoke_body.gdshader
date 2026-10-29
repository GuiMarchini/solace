shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx, cull_back;
// The wanderer's body: a figure of dense, billowing black smoke, like ink curling in
// water. Soft billows boil up the body, slowly turning around it as they rise: the
// surface itself swells and churns in the vertex stage, with matching normals so their
// crowns catch the light while the folds between them fall into near black. Thin
// swirling sheets trace lighter filaments over it, and the feet come apart into smoke.
// A translucent outer layer (smoke_shell.gdshader, the next pass) blurs the outline into
// boiling smoke. Patterns are band-limited so nothing shimmers at a distance.
// UV.xy + COLOR.r hold the rest-pose position (the smoke flows up the body in that
// space); COLOR.b marks the head, which stays pure darkness inside the hood.

#include "res://shaders/smoke_common.gdshaderinc"

uniform vec3 core_color : source_color = vec3(0.012, 0.012, 0.014);
uniform vec3 billow_color : source_color = vec3(0.07, 0.069, 0.073);
uniform vec3 highlight : source_color = vec3(0.3, 0.3, 0.32);
uniform vec3 undertone : source_color = vec3(0.12, 0.03, 0.04);
uniform vec3 ember_color : source_color = vec3(1.0, 0.5, 0.18);
uniform float flow_speed = 0.5;
// Billows: spatial frequency (1/m), how far the surface swells (m), how strongly their
// shape bends the light, how fast they rise (m per unit of flow) and how much they turn
// around the body as they climb (rad/m).
uniform float billow_scale = 9.0;
uniform float billow_depth = 0.019;
uniform float billow_light = 1.5;
uniform float rise = 0.25;
uniform float swirl = 2.5;
uniform float filaments = 0.8;
// How much of the outline frays (the shell does most of the softening).
uniform float fray = 0.8;
// Bind-pose height (m) below which the feet come apart into smoke.
uniform float dissolve_height = 0.09;
// Raised briefly by impacts / focus: embers glow through the smoke.
uniform float energy = 0.0;
// The smoke faintly scatters light of its own, so it stays readable in the cloak's
// shadow instead of going flat brown.
uniform float self_light = 0.15;
// Bind-pose height above which the body is pure darkness (neck and head, seen only
// through the hood's opening). Set by SmokeBody from the skeleton.
uniform float void_height = 1.36;

varying vec3 rest;
varying float head;
varying float crown;

// Rising smoke, slowly turning around the body's axis as it climbs.
vec3 domain(vec3 p, float t) {
	float a = p.y * swirl + t * 0.15;
	vec2 xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p.xz;
	return vec3(xz.x, p.y - t * rise, xz.y);
}

float billows(vec3 p, float t) {
	vec3 q = domain(p, t) * billow_scale;
	return noise3(q + vec3(0.0, 0.0, t * 0.35)) * 0.68 + noise3(q * 2.13 + vec3(5.1, -t * 0.9, 1.7)) * 0.32;
}

void vertex() {
	rest = vec3(UV.x, UV.y, COLOR.r - 0.5);
	head = COLOR.b;
	float t = TIME * flow_speed;
	float h = billows(rest, t);
	float e = 0.006;
	vec3 g = (vec3(billows(rest + vec3(e, 0.0, 0.0), t), billows(rest + vec3(0.0, e, 0.0), t),
			billows(rest + vec3(0.0, 0.0, e), t)) - h) / e;
	// No swelling at the neck (inside the hood); less on the slim shins and ankles.
	float amp = billow_depth * (1.0 - smoothstep(void_height - 0.12, void_height - 0.02, rest.y)) * (1.0 - head)
			* mix(0.55, 1.0, smoothstep(0.1, 0.45, rest.y));
	crown = h;
	VERTEX += NORMAL * (h - 0.5) * 2.0 * amp;
	// The rest-space gradient stands in for the posed one: on smoke, a slightly turned
	// light direction just reads as churning.
	vec3 gt = g - NORMAL * dot(g, NORMAL);
	NORMAL = normalize(NORMAL - gt * 2.0 * amp * billow_light);
}

// 1 while a pattern with this screen-space rate is resolvable, 0 near the pixel.
float band(float fw) {
	return 1.0 - smoothstep(0.12, 0.35, fw);
}

void fragment() {
	float t = TIME * flow_speed;
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(fres, 2.2);
	// Swirling sheets: a flowing, warped field whose contours draw thin lighter filaments
	// (one smooth octave each, so the band limit keeps working).
	vec3 q = domain(rest, t * 1.6) * 20.0;
	float warp = noise3(q * 0.45 + vec3(0.0, -t * 0.5, 0.0));
	float sheet = noise3(q + vec3(warp * 2.2, 0.0, warp * 1.6));
	float fw = fwidth(sheet);
	float fil = (1.0 - smoothstep(0.0, max(fw * 1.2, 0.015), abs(sheet - 0.55))) * band(fw * 6.0);
	float patches = smoothstep(0.35, 0.7, noise3(q * 0.3 + vec3(3.0, -t * 0.4, 0.0)));
	// Dense core, lit billow crowns, near-black folds.
	float k = smoothstep(0.3, 0.8, crown);
	vec3 c = mix(core_color, billow_color, k);
	c = mix(c, highlight, k * k * 0.2);
	c = mix(c, highlight, fil * filaments * patches * (0.45 + 0.55 * k));
	// Thin smoke at the outline and at the rolled edges of each billow: lighter, with
	// the faint warm undertone of the cloak.
	c = mix(c, billow_color * 1.8, edge * 0.5);
	c += undertone * (0.1 + 0.35 * fres) * (1.0 - k);
	// The feet come apart into smoke (SmokeBody's particles take over).
	float low = smoothstep(dissolve_height, 0.0, rest.y);
	float n2 = noise3(domain(rest, t * 2.0) * 16.0) * 0.7 + noise3(rest * 40.0 + vec3(0.0, -t * 2.5, 0.0)) * 0.3;
	ALPHA = 1.0 - low * (0.5 + 0.9 * n2) - edge * fray * (1.0 - k) * (0.4 + 0.8 * n2) + head;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = rest.xy * 600.0;
	// Inside the hood there is only darkness.
	float hood = max(smoothstep(0.3, 0.6, head), smoothstep(void_height - 0.03, void_height + 0.04, rest.y));
	ALBEDO = c * (1.0 - hood * 0.97);
	ROUGHNESS = 0.9;
	SPECULAR = 0.15 * (1.0 - hood);
	BACKLIGHT = vec3(0.06, 0.06, 0.07) * (1.0 - hood) * edge;
	float spark = step(0.993 - energy * 0.02, noise3(vec3(rest.x, rest.y - t * 0.2, rest.z) * 60.0)) * (1.0 - k);
	EMISSION = (ember_color * spark * (0.5 + energy * 2.0) + undertone * fres * 0.1
			+ c * self_light * vec3(0.9, 0.95, 1.1)) * (1.0 - hood);
}
