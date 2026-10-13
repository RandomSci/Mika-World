shader_type spatial;
// Weathered rune-stone for the Hollow Sentinel: world-aligned (triplanar) mottling and chips, moss on
// upward faces, darker crevices. Original procedural material (no textures).

uniform vec3 stone_a : source_color = vec3(0.30, 0.29, 0.27);
uniform vec3 stone_b : source_color = vec3(0.17, 0.165, 0.16);
uniform vec3 moss : source_color = vec3(0.24, 0.33, 0.16);
uniform float moss_amount = 0.75;
uniform float hurt = 0.0;            // brief warm flash where a spell lands
uniform vec3 hurt_color : source_color = vec3(1.0, 0.75, 0.45);

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
	               mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
	               mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// model-space-ish coordinates would swim when it walks; world-space is fine for a slow, heavy creature
	vec3 p = wpos * 1.3;
	float n = fbm(p);
	float chips = smoothstep(0.55, 0.8, fbm(p * 2.3 + 7.0));
	vec3 col = mix(stone_b, stone_a, smoothstep(0.3, 0.75, n));
	col = mix(col, col * 1.18, chips * 0.5);
	float up = clamp(wnorm.y, 0.0, 1.0);
	float m = smoothstep(0.3, 0.8, up) * smoothstep(0.35, 0.65, fbm(p * 1.7 + 3.0)) * moss_amount;
	col = mix(col, moss, m);
	float cavity = smoothstep(0.25, 0.05, n);
	col *= 1.0 - cavity * 0.35;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, m);
	EMISSION = hurt_color * hurt * 0.4;
}
