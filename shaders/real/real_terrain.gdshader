// Photoreal forest floor (realism pass): the terrain's own masks (vertex colour R = trail, G = forest, B = bank)
// choose between leaf litter, moss, bare forest soil, a trodden mud path, a bank of stones, and rock on steep
// slopes - photoscanned PBR sets (Poly Haven / ambientCG, CC0). Albedo is sampled twice (a second rotated,
// rescaled lookup hides the tiling); layers whose weight is zero at a pixel are not sampled at all (the iGPU
// budget); normals are sampled once.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D litter_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D floor_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D bank_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bank_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 0.32;           // 1 / metres per texture

varying vec3 v_wp;
varying vec3 v_wn;
varying vec4 v_mask;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_mask = COLOR;
}

vec2 rot_uv(vec2 p) {
	return mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p * 0.43 + vec2(0.37, 0.11);
}

void fragment() {
	vec2 p = v_wp.xz * tile;
	float big = texture(noise_tex, v_wp.xz * 0.006).r;
	float mid = texture(noise_tex, v_wp.xz * 0.035 + 0.3).r;
	float k = smoothstep(0.35, 0.65, texture(noise_tex, v_wp.xz * 0.02 + 0.7).r) * 0.45;
	float forest = v_mask.g;
	float soil_w = smoothstep(0.45, 0.7, mid) * 0.7;
	float moss_w = smoothstep(0.55, 0.78, big * 0.6 + mid * 0.6) * (0.4 + 0.6 * forest);
	float open_ = 1.0 - smoothstep(0.15, 0.55, forest);
	float bank_w = smoothstep(0.2, 0.7, v_mask.b);
	float trail = smoothstep(0.25, 0.75, v_mask.r + (mid - 0.5) * 0.25);
	// rock takes over from ~32 degrees and is complete by ~48 (steep earth slopes read as bare dunes otherwise)
	float steep = 1.0 - smoothstep(0.67, 0.85, v_wn.y);

	vec3 col = mix(texture(litter_alb, p).rgb, texture(litter_alb, rot_uv(p)).rgb, k);
	vec3 nrm = texture(litter_nrm, p).rgb;
	if (soil_w > 0.01) {
		vec2 q = p * 0.9;
		col = mix(col, mix(texture(floor_alb, q).rgb, texture(floor_alb, rot_uv(q)).rgb, k), soil_w);
		nrm = mix(nrm, texture(floor_nrm, q).rgb, soil_w);
	}
	float mw = max(moss_w, open_ * 0.55);
	if (mw > 0.01) {
		vec2 q = p * 1.4;
		vec3 moss = mix(texture(moss_alb, q).rgb, texture(moss_alb, rot_uv(q)).rgb, k) * vec3(0.5, 0.6, 0.38);
		col = mix(col, moss, moss_w);
		col = mix(col, moss * vec3(1.05, 1.08, 0.92), open_ * 0.55);
		nrm = mix(nrm, texture(moss_nrm, q).rgb, moss_w);
	}
	if (bank_w > 0.01) {
		vec2 q = p * 1.2;
		col = mix(col, mix(texture(bank_alb, q).rgb, texture(bank_alb, rot_uv(q)).rgb, k), bank_w);
		nrm = mix(nrm, texture(bank_nrm, q).rgb, bank_w);
	}
	if (trail > 0.01) {
		vec2 q = p * 1.1;
		col = mix(col, mix(texture(path_alb, q).rgb, texture(path_alb, rot_uv(q)).rgb, k), trail);
		nrm = mix(nrm, texture(path_nrm, q).rgb, trail);
	}
	if (steep > 0.01) {
		// triplanar: a cliff face is textured from the side, not smeared from above
		vec3 bw = pow(abs(v_wn), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec3 wp = v_wp * tile * 0.6;
		vec3 rc = texture(rock_alb, wp.zy).rgb * bw.x + texture(rock_alb, wp.xz).rgb * bw.y + texture(rock_alb, wp.xy).rgb * bw.z;
		vec3 rc2 = texture(rock_alb, rot_uv(wp.zy)).rgb * bw.x + texture(rock_alb, rot_uv(wp.xz)).rgb * bw.y + texture(rock_alb, rot_uv(wp.xy)).rgb * bw.z;
		vec3 rn = texture(rock_nrm, wp.zy).rgb * bw.x + texture(rock_nrm, wp.xz).rgb * bw.y + texture(rock_nrm, wp.xy).rgb * bw.z;
		col = mix(col, mix(rc, rc2, k) * vec3(0.92, 0.94, 0.9), steep);
		nrm = mix(nrm, rn, steep);
	}
	col *= 0.85 + 0.3 * big;
	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.92, 0.8, trail * 0.5 + bank_w * 0.4);
	SPECULAR = 0.3;
}
