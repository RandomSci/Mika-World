shader_type spatial;
render_mode diffuse_lambert_wrap;
// Weathered stonework for the Whispering Woods ruins (Milestone K, original). Painted palette (warm grey stone,
// cool shadowed tone, a little ochre), a photographic texture used ONLY for luminance grain (triplanar, so no UVs),
// thick moss on top faces and ruined crowns (vertex COLOR.g bias + noise), damp darker bases (COLOR.b = height in
// the structure), per-block tone (COLOR.r) (the chamfers catch light).

uniform sampler2D grain_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 stone_a : source_color = vec4(0.72, 0.68, 0.60, 1.0);
uniform vec4 stone_b : source_color = vec4(0.54, 0.55, 0.53, 1.0);
uniform vec4 stone_warm : source_color = vec4(0.66, 0.58, 0.46, 1.0);
uniform vec4 moss_a : source_color = vec4(0.27, 0.39, 0.19, 1.0);
uniform vec4 moss_b : source_color = vec4(0.40, 0.50, 0.25, 1.0);
uniform vec4 damp : source_color = vec4(0.30, 0.34, 0.30, 1.0);
uniform float moss_amount : hint_range(0.0, 1.5) = 0.8;
uniform float grain_scale = 0.45;
uniform float grain_strength = 0.9;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

void fragment() {
	vec3 w = pow(abs(v_wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float g = lum(texture(grain_tex, v_wp.zy * grain_scale).rgb) * w.x + lum(texture(grain_tex, v_wp.xz * grain_scale).rgb) * w.y
		+ lum(texture(grain_tex, v_wp.xy * grain_scale).rgb) * w.z;
	float n1 = texture(noise_tex, v_wp.xz * 0.05 + v_wp.y * 0.03).r;
	float n2 = texture(noise_tex, (v_wp.xz + v_wp.y) * 0.31).r;
	vec3 col = mix(stone_b.rgb, stone_a.rgb, COLOR.r);
	col = mix(col, stone_warm.rgb, smoothstep(0.55, 0.85, n1) * 0.45);
	col *= 1.0 + (g - 0.45) * grain_strength * 1.6;
	col *= 0.86 + COLOR.r * 0.28;                                   // per-block value
	// damp, darker base
	col = mix(col, damp.rgb * (0.8 + g * 0.4), (1.0 - smoothstep(0.0, 0.35, COLOR.b)) * 0.55);
	// moss: up-facing + crown bias, broken by noise; also creeps down faces a little
	float up = smoothstep(0.35, 0.85, v_wn.y);
	float m = up * (0.35 + COLOR.g) + COLOR.g * 0.35 * smoothstep(0.4, 0.8, n2);
	m = smoothstep(0.45, 0.75, m * moss_amount + (n2 - 0.5) * 0.5);
	vec3 moss = mix(moss_a.rgb, moss_b.rgb, n1) * (0.7 + g * 0.6);   // grainy, not a flat green slab
	col = mix(col, moss, m);
	ALBEDO = col;
	ROUGHNESS = mix(0.86, 0.95, m);
	AO = mix(0.7, 1.0, smoothstep(0.0, 0.3, COLOR.b));
	AO_LIGHT_AFFECT = 0.4;
}
