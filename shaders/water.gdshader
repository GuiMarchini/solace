shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;
// Oasis water, painterly: clear turquoise in the shallows deepening to teal over the
// drowned stones, which show through (refraction of the scene behind, absorbed with
// depth); soft foam where the water meets the sand and the ruins; the sky mirrored at
// grazing angles (Fresnel); a sun path of glittering sparkles. Unshaded: everything is
// composed here so the look stays under control in the low warm light.

uniform vec3 shallow_color : source_color = vec3(0.22, 0.78, 0.74);
uniform vec3 deep_color : source_color = vec3(0.02, 0.22, 0.31);
uniform vec3 sky_horizon : source_color = vec3(0.62, 0.78, 0.8);
uniform vec3 sky_zenith : source_color = vec3(0.32, 0.52, 0.78);
uniform vec3 foam_color : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 sun_color : source_color = vec3(1.0, 0.85, 0.62);
uniform float clarity = 2.8;
uniform float foam_width = 0.55;
uniform float refraction = 0.035;
uniform float wave_height = 0.05;
uniform vec2 center = vec2(0.0);
uniform float radius = 100.0;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform vec3 sun_direction;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.21 + TIME * 1.1) * 0.6 + sin(wpos.z * 0.17 - TIME * 0.9) * 0.4
			+ sin((wpos.x + wpos.z) * 0.45 + TIME * 1.7) * 0.25;
	VERTEX.y += w * wave_height;
}

float hash12(vec2 p) {
	vec3 a = fract(vec3(p.xyx) * 0.1031);
	a += dot(a, a.yzx + 33.33);
	return fract((a.x + a.y) * a.z);
}

void fragment() {
	if (length(wpos.xz - center) > radius) {
		discard;
	}
	// Surface normal: two drifting ripple layers.
	vec2 uv = wpos.xz;
	vec3 na = texture(normal_a, uv * 0.045 + vec2(TIME * 0.012, TIME * 0.007)).xyz * 2.0 - 1.0;
	vec3 nb = texture(normal_b, uv * 0.11 - vec2(TIME * 0.018, -TIME * 0.011)).xyz * 2.0 - 1.0;
	vec3 nt = normalize(vec3(na.x + nb.x, 1.0 / 0.35, na.y + nb.y));
	vec3 n = normalize(vec3(nt.x, nt.z, nt.y));

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	float dist = length(CAMERA_POSITION_WORLD - wpos);

	// What lies behind the surface: how far along the view (absorption) and how deep
	// below the surface (shallows, foam), from the depth buffer.
	vec2 suv = SCREEN_UV + n.xz * refraction * clamp(8.0 / dist, 0.2, 1.0);
	float d = texture(depth_tex, suv).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(vec3(suv * 2.0 - 1.0, d), 1.0);
	v.xyz /= v.w;
	float path = -v.z + VERTEX.z;
	// Never refract what is in front of the water.
	if (path < 0.0) {
		suv = SCREEN_UV;
		d = texture(depth_tex, suv).r;
		v = INV_PROJECTION_MATRIX * vec4(vec3(suv * 2.0 - 1.0, d), 1.0);
		v.xyz /= v.w;
		path = -v.z + VERTEX.z;
	}
	path = max(path, 0.0);
	vec3 bed = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).xyz;
	float thick = max(wpos.y - bed.y, 0.0);
	vec3 behind = texture(screen_tex, suv).rgb;
	float absorb = 1.0 - exp(-(thick * 0.75 + path * 0.25) / clarity);
	vec3 body = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, absorb));
	vec3 col = mix(behind * mix(vec3(1.0), shallow_color * 1.15, 0.6), body, clamp(absorb * 1.15, 0.0, 1.0));

	// Sky mirrored at grazing angles.
	vec3 r = reflect(-view_dir, n);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.6, r.y));
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(view_dir, n), 0.0, 1.0), 5.0);
	col = mix(col, sky, fres * 0.42);

	// The sun's path: a broad sheen and glittering sparkles.
	float sd = max(dot(r, normalize(sun_direction)), 0.0);
	col += sun_color * (pow(sd, 60.0) * 0.6);
	float glint = step(0.82, hash12(floor(uv * 6.0 + floor(TIME * 6.0) * 0.37)));
	col += sun_color * pow(sd, 900.0) * 14.0 * (0.4 + glint) * clamp(30.0 / dist, 0.15, 1.0);

	// Foam where the water thins against the sand and the stones.
	float edge = 1.0 - smoothstep(0.0, foam_width, thick);
	float froth = texture(normal_b, uv * 0.35 + TIME * 0.02).r;
	float foam = smoothstep(0.35, 0.75, edge * (0.6 + froth * 0.8) + sin(thick * 9.0 - TIME * 2.0) * 0.08 * edge);
	col = mix(col, foam_color, foam * 0.85);

	ALBEDO = col;
}
