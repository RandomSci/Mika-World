shader_type spatial;
// Floating geometric sigil drawn analytically on a quad (UV 0..1). Additive light, no texture.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(0.45, 0.7, 1.0);
uniform float intensity = 1.0;
uniform float spin = 0.4;
uniform int sides = 6;
uniform float seed = 1.0;
uniform float draw_progress : hint_range(0.0, 1.0) = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * spin;
	float ang01 = fract((atan(p.y, p.x) + 3.14159) / 6.28318);
	float d = 1e3;
	d = min(d, abs(r - 0.96));
	d = min(d, abs(r - 0.88));
	d = min(d, abs(r - 0.42));
	// polygon
	float n = float(sides);
	for (int k = 0; k < 12; k++) {
		if (k >= sides) break;
		float a0 = float(k) * 6.28318 / n + TIME * spin;
		float a1 = float(k + 2) * 6.28318 / n + TIME * spin;
		d = min(d, seg(p, 0.84 * vec2(cos(a0), sin(a0)), 0.84 * vec2(cos(a1), sin(a1))));
	}
	// glyph ticks in the outer ring
	float cells = 36.0;
	float c = floor(fract(a / 6.28318) * cells);
	float u = fract(fract(a / 6.28318) * cells) - 0.5;
	if (r > 0.88 && r < 0.96 && hash(c + seed) > 0.35) d = min(d, abs(u) * 0.16);
	float px = fwidth(r) * 1.5;
	float line = 1.0 - smoothstep(0.006, 0.006 + px, d);
	float glow = exp(-d * d * 900.0) * 0.5;
	float visible = step(ang01, draw_progress);
	float edge_fade = 1.0 - smoothstep(0.97, 1.0, r);
	ALBEDO = color * (line * 2.2 + glow) * intensity * visible * edge_fade;
}
