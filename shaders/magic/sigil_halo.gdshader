// The giant sigil halo behind a caster in an ultimate (2026-10-20, Selwyn's ultimate kit; technique after the halo of
// radial light ticks behind the harpist in his reference Download(4) 2 to 9 s, our own design): a camera facing disc
// of concentric rings, a ring of radial ticks turning one way, a band of rune marks turning the other, and her own
// figure inside (Mika an eight point star of light, Luna six crescent moons round a ring), drawn on clockwise as
// `reveal` goes 0 to 1, flaring with `boost` at the release. Added light, HDR, so the bloom picks it up.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 col : source_color = vec3(1.0, 0.55, 0.78);     // the main colour
uniform vec3 hi : source_color = vec3(1.0, 0.95, 0.97);      // the hot lines
uniform int figure = 0;                                       // 0 Mika star, 1 Luna moons
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float boost = 0.0;
uniform float fade = 1.0;
uniform float intensity = 2.2;
uniform float spin = 0.0;                                     // radians, from the script (time scaled)


float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

float ring(float r, float at, float w) {
	return smoothstep(w, 0.0, abs(r - at));
}

// distance from p to the segment a-b
float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;          // -1..1
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float ang = atan(p.y, p.x);
	// the draw-on: a clockwise sweep from the top, its leading edge hot
	float a01 = fract((PI * 0.5 - ang) / (2.0 * PI));
	float shown = step(a01, reveal);
	float lead = smoothstep(0.05, 0.0, abs(a01 - reveal)) * step(reveal, 0.999);
	// rings
	float v = ring(r, 0.97, 0.008) + ring(r, 0.93, 0.004) * 0.7 + ring(r, 0.66, 0.006) + ring(r, 0.6, 0.003) * 0.6 + ring(r, 0.28, 0.005);
	// radial ticks (72 round, alternating long and short), turning with spin
	float at = ang + spin;
	float n_t = 72.0;
	float cell = floor((at / (2.0 * PI) + 0.5) * n_t);
	float f = fract((at / (2.0 * PI) + 0.5) * n_t);
	float long_t = mod(cell, 3.0) < 0.5 ? 1.0 : 0.0;
	float t_in = mix(0.76, 0.7, long_t);
	float ticks = smoothstep(0.32, 0.12, abs(f - 0.5)) * step(t_in, r) * step(r, 0.9) * (0.55 + 0.45 * long_t);
	// a band of rune marks turning the other way (short strokes of varied length and angle)
	float ar = ang - spin * 1.6;
	float n_r = 40.0;
	float rc = floor((ar / (2.0 * PI) + 0.5) * n_r);
	float rf = fract((ar / (2.0 * PI) + 0.5) * n_r);
	float hr = h1(rc * 3.7);
	vec2 rp = vec2(rf - 0.5, (r - 0.795) / 0.035);
	float glyph = 0.0;
	glyph += smoothstep(0.09, 0.0, abs(rp.x - (hr - 0.5) * 0.4)) * step(abs(rp.y), 0.9);
	glyph += smoothstep(0.1, 0.0, abs(rp.y - (h1(rc + 1.1) - 0.5) * 1.2)) * step(abs(rp.x), 0.32) * step(0.4, hr);
	glyph *= step(abs(r - 0.795), 0.04);
	// her figure
	float fig = 0.0;
	vec2 q = mat2(vec2(cos(spin * 0.5), sin(spin * 0.5)), vec2(-sin(spin * 0.5), cos(spin * 0.5))) * p;
	if (figure == 0) {
		// an eight point star: lines joining every third point of eight on r = 0.58
		for (int i = 0; i < 8; i++) {
			float a1 = float(i) * PI / 4.0;
			float a2 = float(i + 3) * PI / 4.0;
			vec2 pa = vec2(cos(a1), sin(a1)) * 0.58;
			vec2 pb = vec2(cos(a2), sin(a2)) * 0.58;
			fig = max(fig, smoothstep(0.012, 0.0, seg(q, pa, pb)));
		}
	} else {
		// six crescent moons round the inner ring, horns outward
		for (int i = 0; i < 6; i++) {
			float a1 = float(i) * PI / 3.0;
			vec2 c = vec2(cos(a1), sin(a1)) * 0.45;
			float d1 = length(q - c) - 0.11;
			float d2 = length(q - c - normalize(c) * 0.05) - 0.095;
			fig = max(fig, smoothstep(0.012, 0.0, max(d1, -d2)) );
		}
		fig = max(fig, ring(length(q), 0.45, 0.004) * 0.7);
	}
	float lines = v + ticks * 0.9 + glyph * 0.8 + fig;
	float core = exp(-r * 6.0) * (0.25 + boost * 1.2);
	vec3 c3 = mix(col, hi, clamp(lines * 0.6 + lead, 0.0, 1.0));
	vec3 o = c3 * (lines * shown + lead * 2.0) + col * core;
	// a faint fill so the disc reads as one shape
	o += col * 0.05 * smoothstep(1.0, 0.6, r) * shown;
	ALBEDO = o * intensity * (1.0 + boost * 1.5) * fade;
}
