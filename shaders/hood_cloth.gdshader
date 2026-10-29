shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// The hood (see Cloak.hood_sdf; object space = head joint, -Z = face). Same worn
// burgundy cloth as the cloak: fold crests caught by the light and faded, darker
// valleys (the same fold field as the geometry), a stitched seam over the crown, a
// lighter frayed rim around the face opening, an inside that falls into darkness with
// depth, and the warm glow of the star reaching only the nearest inner folds.

#include "res://shaders/fabric_common.gdshaderinc"

uniform vec3 cloth : source_color = vec3(0.165, 0.046, 0.08);
uniform vec3 cloth_faded : source_color = vec3(0.44, 0.23, 0.275);
uniform vec3 inside : source_color = vec3(0.06, 0.018, 0.026);
uniform vec3 mark_color : source_color = vec3(0.72, 0.52, 0.54);
uniform vec3 star_pos = vec3(0.0, 0.065, -0.085);
uniform vec3 star_color : source_color = vec3(1.0, 0.5, 0.15);
uniform float star_glow = 1.0;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	// Cylindrical cloth coordinates around the head (metres).
	vec2 m = vec2(atan(obj.x, obj.z) * 0.14, obj.y);
	// Distance to the face opening's boundary (same ellipsoid as the SDF).
	vec3 q = (obj - vec3(0.0, 0.035, -0.175)) / vec3(0.105, 0.155, 0.15);
	float to_rim = abs(length(q) - 1.0);
	float rim = 1.0 - smoothstep(0.0, 0.22, to_rim);
	// Inner surface: inside the hood's base volume.
	vec3 b = (obj - vec3(0.0, 0.07, 0.02)) / vec3(0.128, 0.138, 0.15);
	float inner = 1.0 - smoothstep(0.88, 0.97, length(b));
	inner = max(inner, FRONT_FACING ? 0.0 : 1.0);
	// Same fold field as Cloak.hood_folds.
	float ang = atan(obj.x, obj.z + 0.02);
	float folds = sin(ang * 4.0 + obj.y * 7.0 + 0.6) * 0.55 + sin(ang * 7.0 - obj.y * 10.0 + 1.3) * 0.3
			+ sin(ang * 11.0 + obj.y * 14.0 + 2.1) * 0.15;
	float side = smoothstep(-0.06, 0.06, obj.z + 0.02 - abs(obj.x) * 0.2);
	float crest = smoothstep(0.25, 0.85, folds) * side;
	float valley = smoothstep(-0.2, -0.8, folds) * side;
	vec3 c = fab_color(m, cloth, cloth_faded, rim * 0.7 + crest * 0.55);
	c *= 0.85 + 0.25 * fab_fbm(m * 6.0);
	c *= 1.0 - valley * 0.4;
	// The seam over the crown: a darker line with stitches on both sides.
	float seam_zone = smoothstep(0.0, 0.1, obj.y);
	float seam = (1.0 - smoothstep(0.0015, 0.004, abs(obj.x))) * seam_zone;
	float stitches = (fab_stitch(abs(obj.x) - 0.007, obj.z) * seam_zone);
	c *= 1.0 - seam * 0.35;
	c = mix(c, mark_color, clamp(fab_marks(m * 1.3) * 0.12 + fab_cracks(m * 6.0) * 0.08 + stitches * 0.3, 0.0, 0.5));
	// Darkness deepens toward the back of the hood.
	float depth = smoothstep(-0.18, 0.08, obj.z);
	vec3 dark = inside * (0.4 + 0.6 * (1.0 - depth)) * (0.8 + 0.4 * fab_noise(m * 9.0));
	c = mix(c, dark, inner * (1.0 - rim * 0.5));
	ALBEDO = c;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	RIM = 0.3 * (1.0 - inner);
	RIM_TINT = 0.6;
	float near = exp(-length(obj - star_pos) * 16.0);
	EMISSION = star_color * near * star_glow * 0.55 * inner;
}
