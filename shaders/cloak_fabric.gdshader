shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Loose strips of torn cloak fabric (Ribbons: UV.x along the strip, UV.y across).
// Same worn burgundy cloth as the cloak; both long edges are ragged and the end
// narrows to a torn point. Cut with alpha scissor (no sorting).

#include "res://shaders/fabric_common.gdshaderinc"

uniform vec3 cloth : source_color = vec3(0.165, 0.046, 0.08);
uniform vec3 cloth_faded : source_color = vec3(0.44, 0.23, 0.275);
uniform vec3 mark_color : source_color = vec3(0.72, 0.52, 0.54);
// Approximate strip size (m): length, width.
uniform vec2 strip_size = vec2(1.0, 0.25);
uniform float seed = 5.0;
// Golden runes painted down the middle of the strip (the sword's cloth strips).
uniform float runes = 0.0;
uniform vec3 rune_color : source_color = vec3(0.82, 0.58, 0.24);

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// One rune in a cell (q: -0.5..0.5, x across, y along): a spine with chevron branches
// and either a ring or a forked foot, varying from cell to cell.
float glyph(vec2 q, float id) {
	float d = seg(q, vec2(0.0, -0.38), vec2(0.0, 0.38));
	d = min(d, seg(q, vec2(0.0, 0.08), vec2(0.27, 0.32)));
	d = min(d, seg(q, vec2(0.0, 0.08), vec2(-0.27, 0.32)));
	if (fract(id * 7.13) > 0.5) {
		d = min(d, abs(length(q - vec2(0.0, -0.17)) - 0.15));
	} else {
		d = min(d, seg(q, vec2(0.0, -0.22), vec2(0.24, -0.4)));
		d = min(d, seg(q, vec2(0.0, -0.22), vec2(-0.24, -0.4)));
	}
	return d;
}

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	vec2 m = vec2(UV.y * strip_size.y, along * strip_size.x);
	// Ragged sides that bite deeper toward the tip, and a torn point at the end.
	float bite = fab_noise(vec2(along * 38.0 + seed, UV.y > 0.5 ? 3.0 : 9.0)) * 0.35
			+ fab_noise(vec2(along * 110.0, seed)) * 0.15;
	float width = 1.0 - bite * (0.35 + 0.65 * along) - smoothstep(0.75, 1.0, along) * 0.9;
	ALPHA = step(across, width);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float wear = 1.0 - smoothstep(0.0, 0.18, width - across);
	// Thin strips catch more light than the heavy mantle: a touch more faded.
	vec3 c = fab_color(m, cloth, cloth_faded, wear * 0.8 + 0.18) * 1.12;
	c = mix(c, mark_color, clamp(fab_marks(m * 1.5) * 0.15 + fab_cracks(m * 5.5) * 0.12, 0.0, 0.5));
	if (runes > 0.0) {
		// A few thin symbols, spaced down the strip (some cells left bare).
		float cells = along * strip_size.x / 0.3;
		vec2 q = vec2((UV.y - 0.5) * strip_size.y / 0.3 * 2.2, fract(cells) - 0.5);
		float d = glyph(q * 1.25, floor(cells) + seed);
		float ink = 1.0 - smoothstep(0.022, 0.022 + fwidth(d) * 1.5, d);
		ink *= step(0.35, fab_h21(vec2(floor(cells), seed)));
		// Faded and broken like old paint, and gone near the torn end.
		ink *= smoothstep(0.2, 0.5, fab_noise(m * 18.0 + 4.0)) * (1.0 - smoothstep(0.65, 0.85, along));
		c = mix(c, rune_color, ink * runes * 0.6);
	}
	// A thin strip is the same cloth on both sides, just a little darker behind.
	if (!FRONT_FACING) {
		c *= 0.88;
	}
	ALBEDO = c;
	ROUGHNESS = 0.88;
	SPECULAR = 0.2;
	RIM = 0.5;
	RIM_TINT = 0.6;
	BACKLIGHT = cloth * 0.35;
}
