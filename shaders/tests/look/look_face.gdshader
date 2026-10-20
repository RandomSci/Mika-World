// Anime face (test only), after the MIT godotshaders "Anime-style face shader" idea: the face's shadow is not computed
// from normals but read from a face shadow map (face_sdf.png: per texel, how far the light must swing to her right (R)
// or left (G) before it goes dark), so the shadow edge is a drawn line that sweeps across the face as the light moves.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;
#include "res://shaders/tests/look/look_common.gdshaderinc"

uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D sdf_tex : hint_default_white, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 head_fwd = vec3(0.0, 0.0, 1.0);              // world, set by the rig
uniform vec3 head_right = vec3(-1.0, 0.0, 0.0);           // her right, world
uniform float softness = 0.03;

void fragment() {
	vec3 base = texture(base_tex, UV).rgb * tint.rgb;
	vec2 l = normalize(key_dir.xz + vec2(1e-5));
	float fl = dot(normalize(head_fwd.xz), l);
	float rl = dot(normalize(head_right.xz), l);
	float theta = acos(clamp(fl, -1.0, 1.0)) / (PI * 0.5);   // 0 light in front, 1 from the side, 2 from behind
	vec2 sdf = texture(sdf_tex, UV).rg;
	float g = rl > 0.0 ? sdf.r : sdf.g;
	float t = theta * 0.94;                                   // the near side stays lit up to a full side light
	float lit = smoothstep(t - softness, t + softness, g) * (1.0 - smoothstep(1.0, 1.2, theta));
	vec3 col = base * look_ramp(mix(0.3, 0.75, lit), 0.0) * key_color * key_energy + base * ambient_color;
	vec3 N = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	col += look_rim(N, V, base) * 0.6;
	ALBEDO = col;
}
