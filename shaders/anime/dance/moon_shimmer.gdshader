shader_type spatial;
// The moon's reflection on the lake (Selwyn: "a soft blurred shimmer, not a solid second moon"): a column of soft,
// broken light on the water under the moon, drawn on a strip that runs from the lens toward the moon's bearing
// (UV.x across it, the vertex's local z = distance out). Low-frequency glints drift with the ripples; no hard edges.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.72, 0.8, 1.0, 1.0);
uniform float energy = 0.9;
varying float v_z;

void vertex() {
	v_z = VERTEX.z;
}

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float core = exp(-x * x * 3.2);
	float lz = log(max(v_z, 1.0));
	float n1 = vn(vec2(x * 2.5 + TIME * 0.12, lz * 18.0 - TIME * 0.5));
	float n2 = vn(vec2(x * 5.0 - TIME * 0.2, lz * 36.0 + TIME * 0.8));
	float g = smoothstep(0.3, 0.9, n1 * 0.6 + n2 * 0.5);
	float near = smoothstep(10.0, 40.0, v_z);
	float far = 1.0 - smoothstep(260.0, 420.0, v_z);
	ALBEDO = color.rgb * core * (0.18 + 0.85 * g) * near * far * energy;
}
