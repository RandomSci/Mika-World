shader_type canvas_item;
// Aged parchment for book pages: warm base, paper fibres, a few soft stains, darker deckled edges.
// `tone` 0 = book parchment, 1 = pale scroll, 2 = weathered stone tablet.
uniform int tone = 0;
uniform float seed = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }

void fragment() {
	vec2 uv = UV;
	vec3 base = tone == 0 ? vec3(0.93, 0.86, 0.70) : (tone == 1 ? vec3(0.96, 0.92, 0.80) : vec3(0.45, 0.45, 0.43));
	float fib = fbm(uv * vec2(40.0, 6.0)) * 0.5 + fbm(uv * 9.0) * 0.5;
	vec3 c = base * (0.9 + 0.12 * fib);
	// soft stains
	float st = smoothstep(0.62, 0.8, fbm(uv * 3.0 + seed));
	c *= 1.0 - st * (tone == 2 ? 0.12 : 0.09);
	// darker, slightly ragged edges
	vec2 d = min(uv, 1.0 - uv);
	float edge = smoothstep(0.0, 0.07 + 0.02 * fbm(uv * 30.0), min(d.x, d.y));
	c *= mix(0.72, 1.0, edge);
	COLOR = vec4(c, 1.0);
}
