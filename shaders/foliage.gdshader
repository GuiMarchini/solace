shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;
// Oasis plants, stylized: palm trunks (ringed bark), palm fronds (leaflets cut out of
// a strip) and reed tufts (thin blades), all swaying in the wind from the vertex colour:
// COLOR.r = position along the leaf/blade (0 base .. 1 tip), COLOR.g = across it
// (0 .. 1, 0.5 the midrib), COLOR.a = how much the wind moves that point.

// 0 = bark, 1 = palm frond, 2 = reed blades.
uniform int mode = 1;
uniform vec3 leaf_dark : source_color = vec3(0.12, 0.26, 0.13);
uniform vec3 leaf_light : source_color = vec3(0.42, 0.56, 0.24);
uniform vec3 leaf_dry : source_color = vec3(0.72, 0.6, 0.32);
uniform vec3 bark_dark : source_color = vec3(0.3, 0.21, 0.15);
uniform vec3 bark_light : source_color = vec3(0.58, 0.45, 0.32);
uniform vec2 wind_dir = vec2(0.42, 0.91);
uniform float wind_strength = 0.35;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 a = fract(vec3(p.xyx) * 0.1031);
	a += dot(a, a.yzx + 33.33);
	return fract((a.x + a.y) * a.z);
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = COLOR.a;
	float phase = dot(w.xz, wind_dir) * 0.08 + TIME * 1.3;
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + w.x * 0.01);
	vec2 push = wind_dir * (sin(phase) * 0.5 + 0.7) * gust;
	float flutter = sin(TIME * 7.0 + w.x * 1.7 + w.z * 1.3 + COLOR.r * 6.0) * 0.12;
	vec3 off = vec3(push.x, -0.15 * abs(sin(phase)), push.y) * wind_strength * sway * sway;
	off.y += flutter * sway * wind_strength;
	// Into model space (the mesh is built in world space, so this is the identity here).
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	wpos = w;
}

void fragment() {
	float along = COLOR.r;
	float across = COLOR.g * 2.0 - 1.0;
	vec3 col;
	if (mode == 0) {
		// Ringed bark: the scars of old fronds, spiralling a little.
		float ring = fract(wpos.y * 3.2 + atan(wpos.x, wpos.z) * 0.1);
		col = mix(bark_dark, bark_light, smoothstep(0.1, 0.6, ring) * (0.7 + 0.3 * hash12(floor(wpos.xz * 4.0))));
		ROUGHNESS = 0.9;
	} else if (mode == 1) {
		// A frond: leaflets slanting out from the midrib, cut apart, tips drying.
		float leaflet = fract(along * 34.0 - abs(across) * 1.6);
		float gap = smoothstep(0.62, 0.75, leaflet);
		float edge = smoothstep(0.75, 1.0, abs(across) + gap * 0.6);
		if (edge > 0.5 || (along > 0.94 && abs(across) > 0.15)) {
			discard;
		}
		col = mix(leaf_dark, leaf_light, 0.35 + 0.65 * (1.0 - abs(across)) * (0.6 + 0.4 * along));
		col = mix(col, leaf_dry, smoothstep(0.75, 1.0, along) * 0.6);
		col = mix(col, leaf_dark * 0.7, step(abs(across), 0.05) * 0.5);
		ROUGHNESS = 0.7;
	} else {
		// Reeds: thin blades, darker at the foot, sun-bleached toward the tips.
		if (abs(across) > 1.0 - along * 0.85) {
			discard;
		}
		col = mix(leaf_dark, leaf_light, smoothstep(0.0, 0.6, along));
		col = mix(col, leaf_dry, smoothstep(0.55, 1.0, along) * 0.7);
		ROUGHNESS = 0.75;
	}
	ALBEDO = col;
	SPECULAR = 0.2;
	// Leaves let the low sun through a little.
	BACKLIGHT = (mode == 0) ? vec3(0.0) : col * 0.6;
}
