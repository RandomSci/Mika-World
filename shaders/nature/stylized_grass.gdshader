shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;
// Stylized grass tufts (Milestone K, original). Normals point UP (a meadow shades like one surface — no
// per-blade noise), colour runs from a cool root to a warm, sunlit tip; wind waves roll across the field in
// world space (gusts), each tuft fluttering a little on top. Far tufts dissolve into the ground (dither) before
// the distance cull, so there is no visible line. INSTANCE_CUSTOM.r = colour variation, COLOR tints per patch.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform vec4 root_color : source_color = vec4(0.18, 0.33, 0.12, 1.0);
uniform vec4 tip_color : source_color = vec4(0.62, 0.84, 0.32, 1.0);
uniform float tuft_height = 0.7;
uniform float wind_strength = 0.22;
uniform float gust_scale = 0.045;
uniform float fade_start = 26.0;
uniform float fade_end = 34.0;
uniform float translucency = 0.35;

#include "res://shaders/nature/gust.gdshaderinc"

varying float v_h;
varying float v_var;
varying float v_dist;
varying vec3 v_tint;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(tuft_height, 0.01), 0.0, 1.0);
	v_h = h;
	v_var = INSTANCE_CUSTOM.r;
	v_tint = COLOR.rgb;
	// rolling gusts across the field + local flutter
	float gust = sin(TIME * 1.3 - (wp.x + wp.z * 0.6) * gust_scale * 6.2831) * 0.5 + 0.5;
	float flut = sin(TIME * 4.3 + wp.x * 2.1 + wp.z * 1.7) * 0.25;
	float bend = (gust * 0.85 + flut) * wind_strength * h * h;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.45;
	if (gust_on > 0.5) {
		vec3 root = MODEL_MATRIX[3].xyz;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * gust_offset(gust_push(root) * 0.35, max(wp.y - root.y, 0.0), max(tuft_height, 0.2));
	}
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// distance dissolve (ordered dither)
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);
	float dither = fract(dot(FRAGCOORD.xy, vec2(0.0671, 0.00583)) * 52.9829);
	if (t.a < alpha_cut || fade < dither) {
		discard;
	}
	vec3 col = mix(root_color.rgb, tip_color.rgb, smoothstep(0.0, 1.0, v_h));
	col *= v_tint * (1.0 + v_var * 0.12);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	BACKLIGHT = tip_color.rgb * translucency * v_h;
	AO = mix(0.6, 1.0, v_h);
	AO_LIGHT_AFFECT = 0.3;
}
