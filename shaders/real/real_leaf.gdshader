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
// Colour pass (Lantern Lake): off by default, every other area keeps the realistic look.
// INSTANCE_CUSTOM per tree (multimesh): rgb = its crown colour, a = how far the leaves take it (0 = untouched).
uniform float saturation = 0.0;                  // + more saturated
uniform vec3 sheen_color : source_color = vec3(0.55, 0.7, 1.0);
uniform float sheen = 0.0;                       // moonlit crown tops (emission, grows with height)
uniform float self_lit = 0.0;                    // keeps the crown colour readable at night (emission)
uniform float glow_amount = 0.0;                 // share of twigs that glow (spirit blossoms)
uniform float glow_energy = 0.0;
uniform float specular = 0.32;

varying float v_ao;
varying float v_var;
varying vec4 v_pal;
varying float v_seed;
varying float v_h;

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
	v_pal = INSTANCE_CUSTOM;
	v_seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	v_h = h;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 c = t.rgb * tint * mix(vec3(0.9, 0.97, 0.88), vec3(1.06, 1.0, 0.84), v_var);
	if (v_pal.a > 0.0) {
		// the tree's own colour, the leaf texture's light and dark kept (veins, edges, shade)
		float l = dot(t.rgb, vec3(0.3, 0.59, 0.11));
		vec3 pc = v_pal.rgb * (0.35 + 1.1 * l) * mix(vec3(0.92, 0.96, 1.04), vec3(1.08, 1.0, 0.9), v_var);
		c = mix(c, pc, v_pal.a);
	}
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c = max(mix(vec3(lum), c, 1.0 + saturation), vec3(0.0));
	float ao = mix(1.0, v_ao, ao_strength);
	ALBEDO = c * (0.55 + 0.45 * ao);
	vec3 em = c * self_lit * (0.35 + 0.65 * ao) + sheen_color * sheen * v_h * v_h * ao;
	if (glow_amount > 0.0) {
		float k = fract(v_var * 37.17 + v_seed * 13.31);
		if (k < glow_amount) {
			float tw = 0.65 + 0.35 * sin(TIME * (1.1 + v_seed) + k * 61.0);
			vec3 gc = mix(v_pal.a > 0.0 ? v_pal.rgb : c, vec3(1.0, 0.95, 0.85), 0.35);
			em += gc * glow_energy * tw * (0.5 + 0.5 * v_h);
		}
	}
	EMISSION = em;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.6;
	SPECULAR = specular;
	BACKLIGHT = c * translucency * (0.4 + 0.6 * ao);
	AO = ao;
	AO_LIGHT_AFFECT = 0.6;
}
