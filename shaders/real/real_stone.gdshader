// Photoreal masonry and boulders (realism pass): triplanar photoscanned stone (Poly Haven CC0) with its normal map,
// per-block tone from StoneBuilder's vertex colour (R tone, G moss bias, B damp base), moss on the tops and in a
// creeping band down the faces (ambientCG CC0 moss), a damp darker foot.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D stone_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 0.55;
uniform float moss_amount = 0.7;
uniform vec3 tint : source_color = vec3(1.0);
uniform bool use_vertex_color = true;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}



void fragment() {
	vec3 w = pow(abs(v_wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_wp * tile;
	vec3 s = (texture(stone_alb, (p).zy) * w.x + texture(stone_alb, (p).xz) * w.y + texture(stone_alb, (p).xy) * w.z).rgb * tint;
	vec3 ns = (texture(stone_nrm, (p).zy) * w.x + texture(stone_nrm, (p).xz) * w.y + texture(stone_nrm, (p).xy) * w.z).rgb;
	vec4 vc = use_vertex_color ? COLOR : vec4(0.5, 0.3, 1.0, 1.0);
	s *= 0.82 + vc.r * 0.36;
	float n1 = texture(noise_tex, v_wp.xz * 0.11 + v_wp.y * 0.05).r;
	float n2 = texture(noise_tex, (v_wp.xz + v_wp.y) * 0.45).r;
	float up = smoothstep(0.3, 0.85, v_wn.y);
	float m = up * (0.45 + vc.g) + vc.g * 0.4 * smoothstep(0.45, 0.8, n2) + (1.0 - smoothstep(0.0, 0.5, vc.b)) * 0.25;
	m = smoothstep(0.42, 0.72, m * moss_amount + (n1 - 0.5) * 0.55);
	vec3 mo = (texture(moss_alb, (p * 2.2).zy) * w.x + texture(moss_alb, (p * 2.2).xz) * w.y + texture(moss_alb, (p * 2.2).xy) * w.z).rgb * vec3(0.46, 0.56, 0.34);
	vec3 col = mix(s, mo, m);
	col = mix(col, col * 0.62, (1.0 - smoothstep(0.0, 0.35, vc.b)) * 0.6);   // damp foot
	ALBEDO = col;
	NORMAL_MAP = mix(ns, (texture(moss_nrm, (p * 2.2).zy) * w.x + texture(moss_nrm, (p * 2.2).xz) * w.y + texture(moss_nrm, (p * 2.2).xy) * w.z).rgb, m);
	NORMAL_MAP_DEPTH = 1.1;
	ROUGHNESS = mix(0.82, 0.96, m);
	SPECULAR = 0.35;
}
