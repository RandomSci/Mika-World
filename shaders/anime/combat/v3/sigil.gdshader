// Combat v3 magic: a rune sigil (the glowing glyph disc that appears at the caster's hand / over her head before a
// spell in the reference, Download(9) 0:00.6 and 1:27.0): concentric thin rings, a ring of rune dashes, tick marks, an
// inscribed star, each band turning its own way; it is wiped in from the centre (reveal 0 -> 1) and fades (fade).
// Drawn on a flat disc mesh (UV 0..1 across), additive.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 edge : source_color = vec3(0.35, 0.62, 1.0);
uniform float energy = 3.0;
uniform float reveal = 1.0;
uniform float fade = 1.0;
uniform float spin = 0.0;
uniform float points = 6.0;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

float ring(float r, float at, float w) { return smoothstep(w, 0.0, abs(r - at)); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float a1 = a + spin;
	float a2 = a - spin * 1.7;
	float lines = ring(r, 0.96, 0.012) + ring(r, 0.9, 0.006) + ring(r, 0.62, 0.01) + ring(r, 0.56, 0.005) + ring(r, 0.28, 0.008);
	// rune dashes between 0.66 and 0.86: noise-chosen glyph segments on 48 cells round the ring
	float cell = floor((a1 / 6.2832 + 0.5) * 48.0);
	float glyph = step(0.45, texture(noise, vec2(cell / 48.0, 0.37)).r);
	float band = step(0.68, r) * step(r, 0.84);
	float dash = band * glyph * smoothstep(0.08, 0.0, abs(fract((a1 / 6.2832 + 0.5) * 48.0) - 0.5) - 0.32);
	float rows = step(0.5, fract(r * 30.0)) * 0.5 + 0.5;
	// ticks on the outer band
	float ticks = step(0.9, r) * step(r, 0.95) * smoothstep(0.1, 0.0, abs(fract((a2 / 6.2832 + 0.5) * 96.0) - 0.5) - 0.38);
	// an inscribed star polygon between the inner rings
	float star = 0.0;
	float n = points;
	float seg = 6.2832 / n;
	float ang = mod(a2 + seg * 0.5, seg) - seg * 0.5;
	float d = r * cos(ang);
	star = ring(d, 0.55 * cos(seg * 0.5), 0.008) * step(r, 0.62);
	float g = lines + dash * rows * 0.9 + ticks * 0.8 + star;
	float wipe = smoothstep(reveal * 1.1, reveal * 1.1 - 0.08, r);
	float a_ = clamp(g * wipe * fade, 0.0, 1.0) * step(r, 1.0);
	ALBEDO = mix(edge, core, clamp(g * 0.6, 0.0, 1.0)) * energy * a_;
	ALPHA = a_;
}
