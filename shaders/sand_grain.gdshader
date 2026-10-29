shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
// A grain (or tiny clump) of sand thrown up by the sword, for GPUParticles3D: a small,
// sunlit speck in the particle's colour, only faintly rounded (a strongly shaded sphere
// reads as a bead up close), so a spray reads as real grains catching the light. Opaque (alpha scissor): thousands cost little and
// need no sorting. It shrinks away at the end of its life (scale curve), no fading.

varying float shade;

void vertex() {
	shade = 0.85 + 0.3 * fract(INSTANCE_CUSTOM.z * 91.7);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = dot(p, p);
	// Lit like the dunes themselves (facing up): under the low sun a camera-facing speck
	// would catch it full on and glow white against the sand it came from.
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(up * 0.6 + vec3(0.0, 0.0, 1.0) * 0.4 + vec3(p.x, -p.y, 0.0) * 0.2);
	ALBEDO = COLOR.rgb * shade;
	// Slightly irregular outline: grains are not perfect discs.
	float edge = 1.0 - 0.25 * fract(sin(dot(floor(UV * 4.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALPHA = step(r, edge) * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
