// Photoreal leaf-twig cards (realism pass): scanned leaves (ambientCG CC0) with their normal map, light through
// the leaves (BACKLIGHT), ambient occlusion deep in the crown (vertex colour R), per-twig colour variation (B),
// wind that grows toward the crown's top and edges, and a fine flutter. Gusts (wingbeats, blasts) bend the whole
// crown with its trunk (gust.gdshaderinc) and set the leaves thrashing.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/nature/gust.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.45;
uniform vec3 tint : source_color = vec3(0.78, 0.88, 0.64);
uniform float translucency = 0.42;
uniform float wind_strength = 0.05;
uniform float crown_height = 20.0;
uniform float ao_strength = 0.8;

varying float v_ao;
varying float v_var;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(crown_height, 1.0), 0.0, 1.0);
	float t = TIME;
	vec3 sway = vec3(sin(t * 0.9 + wp.x * 0.11 + wp.z * 0.07), 0.0, cos(t * 0.75 + wp.z * 0.09)) * wind_strength * h * h * 1.6;
	float gusting = 0.0;
	if (gust_on > 0.5) {
		vec3 root = MODEL_MATRIX[3].xyz;
		vec2 push = gust_push(root);
		sway += gust_offset(push, wp.y - root.y, 14.0);
		gusting = min(length(push), 2.0);
	}
	float ph = dot(wp, vec3(3.1, 2.7, 1.9));
	float flutter = (sin(t * 6.3 + ph) * (1.0 + 4.0 * gusting) + sin(t * 15.0 + ph * 1.7) * 3.0 * gusting) * 0.02 * h;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * sway) + NORMAL * flutter;
	v_ao = COLOR.r;
	v_var = COLOR.b;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 c = t.rgb * tint * mix(vec3(0.9, 0.97, 0.88), vec3(1.06, 1.0, 0.84), v_var);
	float ao = mix(1.0, v_ao, ao_strength);
	ALBEDO = c * (0.55 + 0.45 * ao);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.6;
	SPECULAR = 0.32;
	BACKLIGHT = c * translucency * (0.4 + 0.6 * ao);
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
}
