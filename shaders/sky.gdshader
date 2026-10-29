shader_type sky;
// Warm low-sun desert sky: amber horizon, cool blue-violet zenith,
// broad forward scattering around the sun and thin high cirrus.

uniform vec3 zenith_color : source_color = vec3(0.16, 0.24, 0.48);
uniform vec3 upper_color : source_color = vec3(0.42, 0.50, 0.74);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.74, 0.52);
uniform vec3 ground_haze : source_color = vec3(0.86, 0.62, 0.46);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.56, 0.26);
uniform vec3 opposite_tint : source_color = vec3(0.62, 0.55, 0.78);
uniform float horizon_falloff = 3.2;
uniform float sun_glow = 1.0;
uniform float sun_disk_size = 0.022;
uniform float sun_disk_energy = 28.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_amount = 0.45;
uniform float brightness = 1.0;

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	float up = clamp(y, 0.0, 1.0);
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = max(dot(d, sun_dir), 0.0);
	float away = max(-dot(d.xz, normalize(sun_dir.xz + vec2(1e-4))), 0.0);

	vec3 horizon = mix(horizon_color, opposite_tint, away * 0.55);
	vec3 col = mix(horizon, upper_color, 1.0 - exp(-up * horizon_falloff));
	col = mix(col, zenith_color, smoothstep(0.3, 1.0, up));

	float band = exp(-abs(y) * 5.0);
	col += sun_glow_color * (pow(sd, 3.0) * 0.45 + pow(sd, 18.0) * 0.8 + pow(sd, 200.0) * 2.0)
			* sun_glow * (0.35 + 0.65 * band);

	if (y > 0.0) {
		vec2 cuv = d.xz / (y + 0.25) * 0.3;
		float n = texture(cloud_noise, cuv + vec2(TIME * 0.0015, 0.0)).r * 0.7
				+ texture(cloud_noise, cuv * 2.7 + vec2(0.0, TIME * 0.002)).r * 0.3;
		float clouds = smoothstep(0.55, 0.8, n) * smoothstep(0.02, 0.12, y) * (1.0 - smoothstep(0.35, 0.8, y));
		vec3 cloud_col = mix(vec3(1.0, 0.84, 0.72), sun_glow_color * 1.6 + 0.3, pow(sd, 4.0));
		cloud_col = mix(cloud_col, opposite_tint * 1.1, away * 0.5);
		col = mix(col, cloud_col, clouds * cloud_amount);
	}

	float ang = acos(clamp(dot(d, sun_dir), -1.0, 1.0));
	col += LIGHT0_COLOR * sun_disk_energy * (1.0 - smoothstep(sun_disk_size * 0.75, sun_disk_size, ang));

	col = mix(col, ground_haze, smoothstep(0.0, -0.1, y));
	COLOR = col * brightness;
}
