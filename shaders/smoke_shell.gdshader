shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert_wrap, specular_disabled;
// Smoke boiling off the body: soft translucent volumes around smoke_body.gdshader (its
// next passes; `layer` 0 -> 1 from the inside out). Each layer is the same skinned mesh
// pushed out along its normals by rolling billows. Its opacity follows how much smoke
// the view crosses: little face-on, most just beside the body, fading to nothing at the
// layer's own outline (so no hard shell edge or stacked rings show). A rising, curling
// noise carves it into wisps and gaps. Dark smoke absorbs: over bright sand it reads
// as a dark veil, a little greyer where thin (it catches some light, like ink smoke).
// Thinner on the torso (it stays under the cloak), none in the hood.

#include "res://shaders/smoke_common.gdshaderinc"

uniform vec3 smoke_color : source_color = vec3(0.012, 0.012, 0.014);
uniform vec3 thin_color : source_color = vec3(0.1, 0.098, 0.104);
// This layer's place in the stack (0 = against the body, 1 = outermost).
uniform float layer = 0.5;
// How far out the outermost layer floats (m) and how dense the smoke gets.
uniform float thickness = 0.065;
uniform float density = 0.9;
uniform float flow_speed = 0.5;
// How fast the wisps climb (in units of flow) and how much they curl around the body.
uniform float rise = 1.6;
uniform float swirl = 3.0;
// Bind-pose height of the hips: above it the smoke thins (under the cloak).
uniform float torso_height = 0.95;
uniform float void_height = 1.36;

varying vec3 rest;
varying float mask;
varying float bulge;

void vertex() {
	rest = vec3(UV.x, UV.y, COLOR.r - 0.5);
	float t = TIME * flow_speed;
	float head = COLOR.b;
	mask = (1.0 - smoothstep(void_height - 0.16, void_height - 0.05, rest.y)) * (1.0 - head);
	float torso = 1.0 - 0.65 * smoothstep(torso_height - 0.05, torso_height + 0.1, rest.y);
	// The smoke bulges and thins as it rolls up the body.
	bulge = noise3(rest * 7.0 + vec3(0.0, -t * 0.7, t * 0.25)) * 0.7 + noise3(rest * 15.0 + vec3(2.0, -t * 1.2, 0.0)) * 0.3;
	VERTEX += NORMAL * thickness * (0.35 + 0.65 * layer) * (0.3 + 1.4 * bulge * bulge) * mask * torso;
}

void fragment() {
	float t = TIME * flow_speed;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Wisps: rising noise turning around the body as it climbs, bent by a slow warp so
	// the smoke curls.
	float a = rest.y * swirl + t * 0.2;
	vec2 xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * rest.xz;
	vec3 q = vec3(xz.x * 11.0, rest.y * 8.0 - t * rise, xz.y * 11.0) + vec3(layer * 5.0);
	vec3 w = vec3(noise3(q * 0.5 + vec3(1.7, -t * 0.4, 0.0)), noise3(q * 0.5 + vec3(8.3, -t * 0.4, 2.9)), 0.0) - 0.5;
	float n = noise3(q + vec3(w.x * 3.5, w.y * 2.0, w.x * -2.5)) * 0.65 + noise3(q * 2.2 + vec3(0.0, -t, 3.1)) * 0.35;
	float wisp = smoothstep(mix(0.3, 0.45, layer), mix(0.62, 0.75, layer), n * 0.75 + bulge * 0.35);
	// Smoke crossed by the view: none at this layer's outline, most just inside it,
	// less face-on (there only this layer's own thin front).
	float path = smoothstep(0.0, 0.45, ndv) * (1.0 - 0.85 * smoothstep(0.6, 1.0, ndv));
	ALBEDO = mix(smoke_color, thin_color, clamp(0.25 + layer * 0.45 + (1.0 - wisp) * 0.3, 0.0, 1.0));
	ALPHA = clamp(wisp * path * density * (1.0 - 0.35 * layer) * mask, 0.0, 1.0);
	ROUGHNESS = 1.0;
	BACKLIGHT = thin_color * 0.25;
}
