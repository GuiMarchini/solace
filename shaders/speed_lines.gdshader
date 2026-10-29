shader_type canvas_item;
// Anime-style speed lines at high speed: thin radial streaks flickering at the edges
// of the screen, never over its middle (the rider and the path ahead stay clear).

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.97, 0.92, 1.0);
// Number of angular slots a streak can occupy.
uniform float count = 64.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2832 + 0.5;
	float cell = floor(a * count);
	float f = fract(a * count);
	// Each slot flickers on and off at its own rhythm.
	float tick = floor(TIME * 8.0 + hash(cell) * 10.0);
	float on = step(0.7, hash(cell * 1.37 + tick * 3.1));
	float w = 0.04 + 0.08 * hash(cell + 7.0);
	float line = 1.0 - smoothstep(w * 0.4, w, abs(f - 0.5));
	float start = 0.56 + 0.2 * hash(cell + tick * 0.7 + 3.0);
	float edge = smoothstep(start, start + 0.25, r);
	COLOR = vec4(color.rgb, color.a * line * on * edge * intensity * 0.16);
}
