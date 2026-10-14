// Photoreal bark (realism pass): photoscanned bark (Poly Haven CC0) with its normal and roughness maps, moss
// climbing the base and the upper sides of limbs (ambientCG CC0 moss), broken by noise. Gusts bend the trunk and
// limbs on the same curve as the crown (gust.gdshaderinc).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/nature/gust.gdshaderinc"

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D bark_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float moss_height = 2.2;
uniform float moss_amount = 0.75;

varying vec3 v_lp;
varying vec3 v_ln;

void vertex() {
	v_lp = VERTEX;
	v_ln = NORMAL;
	if (gust_on > 0.5) {
		vec3 root = MODEL_MATRIX[3].xyz;
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * gust_offset(gust_push(root), wp.y - root.y, 14.0);
	}
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 b = texture(bark_albedo, uv).rgb * tint;
	float n = texture(noise_tex, uv * 0.29 + v_lp.xz * 0.05).r;
	float m = (1.0 - smoothstep(moss_height * 0.3, moss_height, v_lp.y)) * 0.85 + smoothstep(0.35, 0.95, v_ln.y) * 0.55;
	m = smoothstep(0.42, 0.7, m * moss_amount + (n - 0.5) * 0.7);
	vec3 mo = texture(moss_albedo, uv * 1.6).rgb * vec3(0.46, 0.56, 0.34);
	ALBEDO = mix(b, mo, m);
	NORMAL_MAP = mix(texture(bark_normal, uv).rgb, texture(moss_normal, uv * 1.6).rgb, m);
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = mix(texture(bark_rough, uv).r, 0.95, m);
	SPECULAR = 0.3;
}
