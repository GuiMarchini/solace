shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The ancient sword (see SpiritSword; object space: tip toward -Z, grip toward +Z, top
// face at y = 0). Weathered sandstone plates with lighter worn bevels, rust-red stains,
// pits and a few fine cracks around a darker recessed core; a rune line burns in the
// channel down the core from the rune circle below the guard, and a slot underneath
// glows with the spirit's propulsion. Dark wrapped grip, burgundy cloth knots.
// Vertex COLOR tags the pieces (r = part, g = per-piece tone, b = 1 on the underside
// slot). Each flat facet gets a slightly different value, like a painted surface.
// `materialize` 0 -> 1 grows it from a droplet of light (centre first, ends last).

#include "res://shaders/smoke_common.gdshaderinc"

uniform vec3 stone : source_color = vec3(0.5, 0.37, 0.32);
uniform vec3 stone_dark : source_color = vec3(0.27, 0.18, 0.165);
uniform vec3 stain : source_color = vec3(0.38, 0.15, 0.13);
uniform vec3 core_color : source_color = vec3(0.22, 0.085, 0.072);
uniform vec3 grip_color : source_color = vec3(0.1, 0.065, 0.06);
uniform vec3 cloth_color : source_color = vec3(0.42, 0.08, 0.1);
uniform vec3 energy_color : source_color = vec3(1.0, 0.45, 0.25);
uniform float energy = 1.0;
uniform float materialize : hint_range(0.0, 1.0) = 1.0;
uniform float flow_speed = 1.4;
uniform float under_glow = 1.0;
// Blade layout (keep in sync with SpiritSword).
uniform float tip_z = -1.22;
uniform float guard_z = 0.5;
uniform vec3 emblem = vec3(0.0, -0.003, 0.355);
uniform float emblem_radius = 0.046;

varying vec3 obj;
varying vec3 obj_n;
varying float form;

void vertex() {
	obj = VERTEX;
	obj_n = NORMAL;
	vec3 centre = vec3(0.0, -0.027, -0.1);
	float along = abs(VERTEX.z - centre.z) / 1.2;
	float s = clamp(materialize * 1.4 - along * 0.4, 0.0, 1.0);
	s = s * s * (3.0 - 2.0 * s);
	form = s;
	vec3 dir = normalize(VERTEX - centre + vec3(0.0, 0.0001, 0.0));
	vec3 blob = centre + dir * vec3(0.05, 0.03, 0.06) * smoothstep(0.0, 0.18, materialize);
	VERTEX = mix(blob, VERTEX, s);
	NORMAL = normalize(mix(dir, NORMAL, s));
}

// Sparse thin cracks: broken cell borders of a jittered grid (band-limited).
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash3(vec3(i + g, 1.0)), hash3(vec3(i + g, 7.0)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float e = d2 - d1;
	float w = max(0.04, fwidth(e) * 1.5);
	float line = 1.0 - smoothstep(0.0, w, e);
	float fade = 1.0 - smoothstep(0.1, 0.35, fwidth(p.x) + fwidth(p.y));
	float broken = smoothstep(0.5, 0.75, noise3(vec3(p * 1.7, 4.0)));
	return line * fade * broken;
}

// Anti-aliased thin line: 1 where |d| < half width.
float aa_line(float d, float half_w) {
	float fw = max(fwidth(d), 0.0002);
	return 1.0 - smoothstep(half_w, half_w + fw * 1.2, abs(d));
}

void fragment() {
	float part = COLOR.r;
	float tone = COLOR.g;
	float liquid = 1.0 - smoothstep(0.55, 1.0, form);
	float t = clamp((guard_z - obj.z) / (guard_z - tip_z), 0.0, 1.0);
	vec3 albedo;
	vec3 emit = vec3(0.0);
	float rough = 0.84;
	float spec = 0.3;
	float facet = hash3(floor(obj_n * 7.0 + 0.5) + vec3(tone * 13.0));
	if (part < 0.52) {
		// Stone: frame plates, core, tip, collar, claws, ring.
		float n = fbm(obj * vec3(9.0, 9.0, 4.5) + vec3(tone * 17.0));
		float fine = noise3(obj * 70.0);
		vec3 c = mix(stone_dark, stone, 0.45 + 0.55 * smoothstep(0.2, 0.8, n));
		// Bevels and edges face away from the flat: worn lighter.
		float bevel = smoothstep(0.3, 0.75, abs(obj_n.x)) + 0.6 * smoothstep(0.4, 0.85, abs(obj_n.z));
		c = mix(c, stone * 1.1, clamp(bevel, 0.0, 1.0) * 0.4);
		// Rust-red stains creeping over the flats.
		float st = smoothstep(0.52, 0.78, fbm(obj * vec3(5.0, 5.0, 2.2) + vec3(3.1, 0.0, tone * 7.0)));
		c = mix(c, stain, st * 0.55 * (1.0 - bevel * 0.5));
		if (part > 0.1 && part < 0.2) {
			// The recessed core: darker, reddish, grimy.
			c = mix(core_color, stain * 0.8, 0.4 * n) * (0.8 + 0.4 * fine);
		}
		c *= 0.9 + 0.2 * facet;
		c *= 0.86 + 0.14 * fine;
		// Pits and a few fine cracks.
		c *= 1.0 - 0.35 * step(0.82, noise3(obj * 140.0)) * (1.0 - smoothstep(0.003, 0.01, fwidth(obj.x * 140.0)));
		c *= 1.0 - 0.5 * cracks(vec2(obj.x * 18.0 + obj.y * 9.0, obj.z * 9.0) + tone * 11.0);
		albedo = c;
	} else if (part < 0.67) {
		// Grip: dark leather wound in overlapping bands.
		float ang = atan(obj.y + 0.027, obj.x);
		float band = fract(obj.z * 38.0 + ang * 0.16);
		float groove = smoothstep(0.0, 0.12, band) * (1.0 - smoothstep(0.85, 1.0, band));
		albedo = grip_color * (0.55 + 0.6 * groove) * (0.85 + 0.3 * noise3(obj * 90.0));
		rough = 0.66;
		spec = 0.35;
	} else if (part < 0.82) {
		// Cloth knots.
		float ang = atan(obj.y + 0.027, obj.x);
		float fold = noise3(vec3(ang * 2.5, obj.z * 70.0, tone * 9.0));
		albedo = cloth_color * (0.7 + 0.6 * fold);
		rough = 0.95;
		spec = 0.15;
	} else if (part < 0.95) {
		// Boss of the rune circle: a ring, an inner ring, a cross of ticks and a dot.
		albedo = mix(core_color, stone_dark, 0.45) * (0.9 + 0.2 * noise3(obj * 80.0));
		vec2 q = obj.xz - emblem.xz;
		float r = length(q);
		float top = smoothstep(emblem.y - 0.0012, emblem.y - 0.0004, obj.y);
		float R = emblem_radius;
		float ring = aa_line(r - R, 0.0032);
		float inner = aa_line(r - R * 0.36, 0.0022);
		float arms = aa_line(min(abs(q.x), abs(q.y)), 0.0018) * step(R * 0.36, r) * (1.0 - step(R * 1.28, r));
		float centre_dot = 1.0 - smoothstep(0.004, 0.0052, r);
		float sym = max(max(ring, inner), max(arms, centre_dot)) * top;
		float halo = exp(-abs(r - R) * 110.0) * 0.5 + exp(-r * 60.0) * 0.3;
		albedo = mix(albedo, vec3(1.0, 0.82, 0.66), sym);
		emit += energy_color * (sym * 3.2 + halo * top * 0.9) * energy;
		rough = 0.8;
	} else {
		// The rune line and the propulsion slot: burning light, pulsing down the blade.
		float pulse = 0.5 + 0.5 * sin((t * 5.0 - TIME * flow_speed) * 6.2832);
		float under = COLOR.b;
		albedo = vec3(1.0, 0.86, 0.72);
		emit = energy_color * (2.4 + 1.1 * pulse) * energy * mix(1.0, under_glow * 1.2, under);
		emit += vec3(1.0, 0.85, 0.7) * 0.6 * energy;
		rough = 0.4;
	}
	// The line's light bleeds onto the core around the channel and the slot.
	if (part > 0.1 && part < 0.2) {
		float on_line = step(obj.z, emblem.z) * step(-0.93, obj.z);
		float glow = exp(-abs(obj.x) * 140.0) * on_line;
		float top = step(-0.027, obj.y);
		float on_slot = step(obj.z, 0.2) * step(-0.9, obj.z);
		emit += energy_color * glow * (top * 0.7 + (1.0 - top) * on_slot * under_glow) * energy;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emit + (albedo * 2.0 + energy_color * 2.5) * liquid;
}
