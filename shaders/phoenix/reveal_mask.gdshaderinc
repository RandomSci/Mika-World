// Oriel's transformation reveal (visual pass 2): which part of her humanoid body is "made" yet. Every garment
// surface belongs to a group (hair, crown, top, arms, skirt, legs, body) - fixed per material, or (-1) found
// per fragment from the nearest body part (head / torso / arms / lower legs) so the gold and the gems scattered
// over her (circlet, bracelets, anklets, collar) appear with the part they sit on. Each group materialises
// along its own sweep (hair from the crown down, skirt from the waist down, sandals from the feet up, top
// outward from the heart, arms from the shoulders to the hands, the circlet outward from the brow) with a
// burning edge. Joint positions are fed every frame (world space). Included by the MToon reveal variant
// (mtoon_reveal.gdshaderinc) and by the glow pass (reveal_glow.gdshader).

uniform float rv_on = 0.0;
uniform int rv_group = -1;            // -1 classify; 0 hair, 1 crown, 2 top, 3 arms, 4 skirt, 5 legs, 6 body
uniform vec4 rv_p0 = vec4(1.0);       // progress 0..1: hair, crown, top, arms
uniform vec4 rv_p1 = vec4(1.0);       // skirt, legs, body, -
uniform vec3 rv_head = vec3(0.0, 1.6, 0.0);
uniform vec3 rv_chest = vec3(0.0, 1.32, 0.0);
uniform vec3 rv_hips = vec3(0.0, 0.95, 0.0);
uniform vec3 rv_lsh = vec3(0.2, 1.4, 0.0);
uniform vec3 rv_lhand = vec3(0.55, 0.85, 0.0);
uniform vec3 rv_rsh = vec3(-0.2, 1.4, 0.0);
uniform vec3 rv_rhand = vec3(-0.55, 0.85, 0.0);
uniform vec3 rv_lknee = vec3(0.1, 0.5, 0.0);
uniform vec3 rv_lfoot = vec3(0.1, 0.06, 0.0);
uniform vec3 rv_rknee = vec3(-0.1, 0.5, 0.0);
uniform vec3 rv_rfoot = vec3(-0.1, 0.06, 0.0);
uniform vec3 rv_edge_col : source_color = vec3(1.0, 0.62, 0.22);

varying vec3 rv_wp;

float rv_seg(vec3 p, vec3 a, vec3 b, out float t) {
	vec3 ab = b - a;
	t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(p - (a + ab * t));
}

// > 0: made (visible); `edge` = the burning seam (0..1)
float rv_eval(vec3 p, out float edge) {
	int g = rv_group;
	if (g < 0) {
		float tt;
		float dh = length(p - rv_head) - 0.13;
		float dt = rv_seg(p, rv_hips, rv_chest, tt) - 0.12;
		float dl = rv_seg(p, rv_lsh, rv_lhand, tt) - 0.05;
		float dr = rv_seg(p, rv_rsh, rv_rhand, tt) - 0.05;
		float dk = min(rv_seg(p, rv_lknee, rv_lfoot, tt), rv_seg(p, rv_rknee, rv_rfoot, tt)) - 0.06;
		float m = min(min(dh, dt), min(min(dl, dr), dk));
		if (m == dh) {
			g = 1;
		} else if (m == dl || m == dr) {
			g = 3;
		} else if (m == dk) {
			g = 5;
		} else {
			g = (p.y > rv_hips.y + 0.1) ? 2 : 4;
		}
	}
	float pr = 1.0;
	float c = 0.5;
	if (g == 0) {
		pr = rv_p0.x;
		c = (rv_head.y + 0.16 - p.y) / 0.95;
	} else if (g == 1) {
		pr = rv_p0.y;
		c = length(p - rv_head) / 0.42;
	} else if (g == 2) {
		pr = rv_p0.z;
		c = length(p - rv_chest) / 0.5;
	} else if (g == 3) {
		pr = rv_p0.w;
		float t1;
		float t2;
		float a1 = rv_seg(p, rv_lsh, rv_lhand, t1);
		float a2 = rv_seg(p, rv_rsh, rv_rhand, t2);
		c = a1 < a2 ? t1 : t2;
	} else if (g == 4) {
		pr = rv_p1.x;
		c = (rv_hips.y + 0.12 - p.y) / 0.9;
	} else if (g == 5) {
		pr = rv_p1.y;
		c = (p.y - min(rv_lfoot.y, rv_rfoot.y) + 0.05) / 0.65;
	} else {
		pr = rv_p1.z;
	}
	float n = fract(sin(dot(floor(p * 40.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float front = pr * 1.25 - 0.1;
	float v = clamp(c, 0.0, 1.0) + (n - 0.5) * 0.06;
	edge = (1.0 - smoothstep(0.0, 0.07, front - v)) * step(0.001, pr) * step(pr, 0.999);
	return front - v;
}
