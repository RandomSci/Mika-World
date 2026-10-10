shader_type spatial;
// TWO-SIDED variant of stone_triplanar (cave shells). Weathered photogrammetry stone.
// - World-space triplanar albedo / normal / roughness / AO (no UV seams on bevelled blocks)
// - Whiteout normal blending (Golus), OpenGL-convention normal maps (Poly Haven nor_gl)
// - Per-block variation from COLOR.r, moss bias COLOR.g, grime bias COLOR.b
// - Moss accumulates on up-facing surfaces, broken up with a world-space noise
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D breakup_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float tiling = 0.45;
uniform float moss_tiling = 0.7;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec3 stone_tint : source_color = vec3(1.0);
uniform float tint_variation : hint_range(0.0, 0.5) = 0.18;
uniform float moss_amount : hint_range(0.0, 1.5) = 0.75;
uniform float moss_sharpness : hint_range(1.0, 16.0) = 5.0;
uniform vec3 moss_tint : source_color = vec3(0.86, 0.95, 0.72);
uniform float grime_height = 0.9;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
// Magic light bounce: the spell sets these so carved stone picks up a cool rim tint.
uniform vec3 magic_pos = vec3(0.0, -100.0, 0.0);
uniform vec3 magic_color : source_color = vec3(0.45, 0.65, 1.0);
uniform float magic_strength = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z + 1e-5);
}

// Planes with negligible weight are skipped (coherent on block faces → real savings on iGPUs).
vec4 tri_sample(sampler2D tex, vec3 p, vec3 w, float s) {
	vec4 acc = vec4(0.0);
	if (w.x > 0.02) acc += texture(tex, p.zy * s) * w.x;
	if (w.y > 0.02) acc += texture(tex, p.xz * s) * w.y;
	if (w.z > 0.02) acc += texture(tex, p.xy * s) * w.z;
	return acc / max(dot(step(vec3(0.02), w), w), 1e-4);
}

vec3 tri_normal(sampler2D tex, vec3 p, vec3 n, vec3 w, float s, float strength) {
	vec3 acc = vec3(0.0);
	if (w.x > 0.02) {
		vec3 tx = texture(tex, p.zy * s).xyz * 2.0 - 1.0;
		tx.xy *= strength; tx.x *= sign(n.x);
		tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
		acc += tx.zyx * w.x;
	}
	if (w.y > 0.02) {
		vec3 ty = texture(tex, p.xz * s).xyz * 2.0 - 1.0;
		ty.xy *= strength; ty.x *= sign(n.y);
		ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
		acc += ty.xzy * w.y;
	}
	if (w.z > 0.02) {
		vec3 tz = texture(tex, p.xy * s).xyz * 2.0 - 1.0;
		tz.xy *= strength; tz.x *= -sign(n.z);
		tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
		acc += tz.xyz * w.z;
	}
	return normalize(acc + n * 1e-4);
}

void fragment() {
	vec3 n = normalize(wnrm) * (FRONT_FACING ? 1.0 : -1.0);  // two-sided: cave shells seen from inside and outside
	vec3 w = tri_weights(n);
	vec3 p = wpos;

	vec3 alb = tri_sample(stone_albedo, p, w, tiling).rgb;
	float rough = tri_sample(stone_rough, p, w, tiling).r;
	float ao = tri_sample(stone_ao, p, w, tiling).r;
	vec3 nrm = tri_normal(stone_normal, p, n, w, tiling, normal_strength);

	// per-block tint: lighter/darker and slightly warm/cool
	float v = COLOR.r - 0.5;
	alb *= stone_tint * (1.0 + v * tint_variation * 2.0);
	alb *= mix(vec3(1.0), vec3(1.04, 1.0, 0.94), clamp(v * 2.0, 0.0, 1.0));
	alb *= mix(vec3(1.0), vec3(0.94, 0.98, 1.04), clamp(-v * 2.0, 0.0, 1.0));

	// large-scale breakup noise
	float nz = texture(breakup_noise, p.xz * 0.045 + p.y * 0.02).r;
	float nz2 = texture(breakup_noise, p.zy * 0.11 + vec2(0.37, 0.11)).r;

	// grime / dampness creeping up from the ground and in crevices
	float grime = (1.0 - smoothstep(0.0, grime_height, p.y + nz2 * 0.6)) * (0.55 + COLOR.b * 0.45);
	grime = max(grime, (1.0 - ao) * 0.6);
	alb *= mix(1.0, 0.62, grime);
	rough = mix(rough, rough * 0.75, grime * 0.6);

	// moss on up-facing surfaces + crevices, strongest where the per-block bias says so
	float up = clamp(nrm.y * 0.65 + n.y * 0.35, 0.0, 1.0);
	float moss_mask = pow(up, 1.0 / max(moss_amount, 0.01)) * 1.15 + (1.0 - ao) * 0.35;
	moss_mask = moss_mask * (0.35 + COLOR.g) * moss_amount + (nz - 0.55) * 1.4;
	moss_mask += (1.0 - smoothstep(0.0, 1.4, p.y)) * 0.25 * moss_amount;
	moss_mask = clamp((moss_mask - 0.5) * moss_sharpness + 0.5, 0.0, 1.0);
	if (moss_mask > 0.01) {
		vec3 m_alb = tri_sample(moss_albedo, p, w, moss_tiling).rgb * moss_tint;
		vec3 m_nrm = tri_normal(moss_normal, p, n, w, moss_tiling, 1.0);
		alb = mix(alb, m_alb, moss_mask);
		nrm = normalize(mix(nrm, m_nrm, moss_mask));
		rough = mix(rough, 0.92, moss_mask);
	}
	rough = mix(rough, rough * 0.45, wetness);

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	SPECULAR = 0.42;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

	// subtle magical bounce (cheap, no extra light): falls off with distance, rims surfaces facing the spell
	if (magic_strength > 0.001) {
		vec3 to_m = magic_pos - p;
		float d = length(to_m);
		float facing = clamp(dot(nrm, to_m / max(d, 1e-3)), 0.0, 1.0);
		EMISSION = magic_color * magic_strength * facing * alb * (1.0 / (1.0 + d * d * 0.18));
	}
}
