// The magic path over Lantern Lake (2026-10-23): walking on water is always magic. Mika's strip is frost (ice cells
// with stars caught in them), Luna's is moonlight (slow silver ripples), the circle at its end where they dance has
// both and its own rings. It grows out from the shore when cast, glows and rings out under every step, and fades
// when they have left it. Additive glow, drawn just above the water.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform int style = 0;                    // 0 frost (Mika), 1 moonlight (Luna), 2 the circle
uniform vec3 col_a : source_color = vec3(0.55, 0.85, 1.0);
uniform vec3 col_b : source_color = vec3(0.92, 0.97, 1.0);
uniform float grow = 0.0;                 // 0..1: how far out it has formed (along the strip, or out from the circle's middle)
uniform float fade = 1.0;                 // 1 lit .. 0 gone
uniform float energy = 1.0;
uniform vec4 steps[8];                    // xz (world), start time, 0/1 used
uniform float now = 0.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// distance to the nearest cell edge (frost crystals)
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

float stars(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = hash(i);
	if (h < 0.82) {
		return 0.0;
	}
	float tw = 0.5 + 0.5 * sin(t * (2.0 + h * 5.0) + h * 40.0);
	return smoothstep(0.09, 0.0, length(f)) * tw;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float along;
	float across;
	if (style == 2) {
		vec2 c = UV * 2.0 - 1.0;
		along = length(c);                 // out from the middle
		across = along;
		if (along > 1.0) { discard; }
	} else {
		along = UV.y;
		across = abs(UV.x * 2.0 - 1.0);
	}
	if (along > grow) { discard; }
	float t = now;
	vec2 p = wpos.xz;
	float edge = smoothstep(1.0, 0.82, across);
	float core = 0.18 + 0.5 * pow(1.0 - across, 1.6);
	float pat = 0.0;
	if (style == 0) {
		float e = cells(p * 2.4);
		pat = smoothstep(0.08, 0.0, e) * 0.9 + smoothstep(0.3, 0.0, e) * 0.25;
		pat += stars(p * 7.0, t) * 1.8;
	} else if (style == 1) {
		float w = sin(p.x * 3.1 + t * 0.9) * sin(p.y * 2.3 - t * 0.7) + sin((p.x + p.y) * 5.2 + t * 1.3) * 0.5;
		pat = smoothstep(0.55, 1.2, w) * 0.8 + 0.12;
		pat += stars(p * 6.0 + 3.0, t) * 1.3;
	} else {
		// the circle: rings and a ring of ticks, slowly turning, the two lights mixed
		float r = along;
		float ang = atan(UV.y * 2.0 - 1.0, UV.x * 2.0 - 1.0) + t * 0.12;
		float rings = smoothstep(0.018, 0.0, abs(r - 0.96)) + smoothstep(0.012, 0.0, abs(r - 0.86)) * 0.8
			+ smoothstep(0.01, 0.0, abs(r - 0.5)) * 0.5 + smoothstep(0.01, 0.0, abs(r - 0.28)) * 0.4;
		float ticks = step(0.75, fract(ang * 24.0 / 6.2832)) * smoothstep(0.0, 0.01, r - 0.87) * smoothstep(0.0, 0.01, 0.95 - r);
		pat = rings * 1.4 + ticks * 0.8 + smoothstep(0.08, 0.0, cells(p * 2.2)) * 0.35;
		pat += stars(p * 6.5, t) * 1.5;
		core = 0.1 + 0.25 * (1.0 - r);
		edge = 1.0;
	}
	// the leading edge as it forms: a bright seam
	float seam = smoothstep(0.05, 0.0, abs(along - grow)) * step(grow, 0.999);
	// under each step: a glow where the foot came down and a ring running out from it
	float stepg = 0.0;
	for (int i = 0; i < 8; i++) {
		if (steps[i].w < 0.5) { continue; }
		float age = t - steps[i].z;
		if (age < 0.0 || age > 2.2) { continue; }
		float d = length(p - steps[i].xy);
		stepg += exp(-d * d * 9.0) * exp(-age * 2.6) * 1.6;
		stepg += exp(-pow((d - age * 1.3) * 7.0, 2.0)) * exp(-age * 1.4) * 0.9;
	}
	vec3 col = mix(col_a, col_b, clamp(pat * 0.6 + stepg * 0.5, 0.0, 1.0));
	float a = (core + pat * 0.55 + seam * 1.6 + stepg) * edge * fade * energy;
	ALBEDO = col * a;
}
