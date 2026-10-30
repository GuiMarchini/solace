shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// A distant bird: a dark V whose wings beat (vertices move with their distance from the
// body), each instance at its own phase (INSTANCE_CUSTOM.x).

uniform vec3 color : source_color = vec3(0.22, 0.16, 0.16);

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float beat = sin(TIME * 7.0 + phase);
	// Glide now and then.
	float glide = smoothstep(0.2, 0.8, sin(TIME * 0.6 + phase * 0.3));
	VERTEX.y += abs(VERTEX.x) * beat * 0.9 * (1.0 - glide * 0.85);
}

void fragment() {
	ALBEDO = color;
}
