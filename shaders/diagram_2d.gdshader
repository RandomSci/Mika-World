shader_type canvas_item;
// Ink diagrams for book pages: 0 = star sigil with `sides` points in a circle, 1 = wind arcs,
// 2 = concentric rings, 3 = recipe (two vessels pouring into a bowl). Drawn in ink with a faint glow.
uniform int mode = 0;
uniform int sides = 6;
uniform vec3 ink : source_color = vec3(0.32, 0.2, 0.1);
uniform vec3 glow : source_color = vec3(0.45, 0.7, 1.0);
uniform float glow_amount = 0.35;

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return smoothstep(w, w * 0.4, length(pa - ba * h));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float d = 0.0;
	if (mode == 0) {
		d += smoothstep(0.02, 0.008, abs(r - 0.82));
		d += smoothstep(0.012, 0.005, abs(r - 0.74)) * 0.7;
		float n = float(sides);
		for (int i = 0; i < 12; i++) {
			if (i >= sides) break;
			float a0 = 6.2831853 * float(i) / n - 1.5708;
			float a1 = 6.2831853 * float((i + 2) % sides) / n - 1.5708;
			d += seg(p, 0.72 * vec2(cos(a0), sin(a0)), 0.72 * vec2(cos(a1), sin(a1)), 0.018);
		}
		d += smoothstep(0.06, 0.04, r) * 0.8;
	} else if (mode == 1) {
		for (int i = 0; i < 4; i++) {
			if (i >= sides) break;
			float rad = 0.3 + float(i) * 0.17;
			float ang = mod(a + float(i) * 1.7, 6.2831853);
			d += smoothstep(0.02, 0.008, abs(r - rad)) * step(ang, 2.4);
		}
	} else if (mode == 2) {
		for (int i = 0; i < 5; i++) {
			if (i >= sides) break;
			d += smoothstep(0.018, 0.007, abs(r - (0.2 + float(i) * 0.17))) * (1.0 - float(i) * 0.15);
		}
	} else {
		// two flasks pouring into a bowl
		d += seg(p, vec2(-0.75, -0.6), vec2(-0.55, -0.6), 0.02) + seg(p, vec2(-0.65, -0.6), vec2(-0.65, -0.25), 0.02);
		d += smoothstep(0.02, 0.008, abs(length(p - vec2(-0.65, -0.05)) - 0.2));
		d += seg(p, vec2(0.75, -0.6), vec2(0.55, -0.6), 0.02) + seg(p, vec2(0.65, -0.6), vec2(0.65, -0.25), 0.02);
		d += smoothstep(0.02, 0.008, abs(length(p - vec2(0.65, -0.05)) - 0.2));
		vec2 q = p - vec2(0.0, 0.45);
		d += smoothstep(0.02, 0.008, abs(length(q) - 0.35)) * step(0.0, q.y);
		d += seg(p, vec2(-0.35, 0.45), vec2(0.35, 0.45), 0.02);
		d += seg(p, vec2(-0.45, 0.15), vec2(-0.15, 0.35), 0.012) + seg(p, vec2(0.45, 0.15), vec2(0.15, 0.35), 0.012);
	}
	d = clamp(d, 0.0, 1.0);
	float halo = clamp(d * 1.5, 0.0, 1.0) * glow_amount;
	COLOR = vec4(mix(ink, glow, halo), d);
}
