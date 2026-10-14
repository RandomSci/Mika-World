// GUSTS (the cinematic pass, 2026-10-14): wind from great wingbeats, blasts and the Phoenix's transformation
// bends the vegetation. Up to four sources live at once; scripts/world/gusts.gd sets these on every registered
// plant material each frame while one lives (and clears gust_on after). Each is a wave travelling outward from its
// source: a plant it reaches bends AWAY from the source and swings back like a damped spring; the bend grows with
// the square of the height above the plant's root (trunk and crown share the same curve, so they never part).

uniform vec4 gust_pos[4];            // xyz: the source (world), w: its reach (m)
uniform vec4 gust_wave[4];           // x: age (s), y: strength (m of bend at the reference height), z: sway (Hz), w: damping (1/s)
uniform float gust_on = 0.0;

const float GUST_SPEED = 17.0;       // m/s: how fast the wave front runs out from the source

// The horizontal push (world metres at the reference height) at a plant whose root is `root`.
vec2 gust_push(vec3 root) {
	vec2 o = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 w = gust_wave[i];
		vec4 p = gust_pos[i];
		vec2 d = root.xz - p.xz;
		float r = length(d);
		float t = w.x - r / GUST_SPEED;
		if (w.y != 0.0 && t > 0.0 && r < p.w) {
			float fall = (1.0 - smoothstep(p.w * 0.3, p.w, r)) / (1.0 + 0.035 * r);
			float x = w.y * fall * exp(-w.w * t) * sin(6.2831853 * w.z * t);
			o += (d / max(r, 0.05)) * x;
		}
	}
	return o;
}

// World-space offset for a point `h` metres above its root, given the push; `h_ref`: the height that bends by the
// full push (taller parts bend further, up to 1.6x). The point drops a little as it bends (its stem keeps length).
vec3 gust_offset(vec2 push, float h, float h_ref) {
	float k = clamp(h / max(h_ref, 0.01), 0.0, 1.6);
	vec2 b = push * k * k;
	float drop = dot(b, b) / max(2.0 * max(h, 0.3), 0.6);
	return vec3(b.x, -drop, b.y);
}
