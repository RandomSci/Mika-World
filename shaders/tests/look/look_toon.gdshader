// Genshin-style toon for body and outfit (test only): half Lambert scaled by the lightmap's shadow threshold (G), looked
// up in a per-material ramp row (A), a hard specular on metal and gems (R strength, B size), a thin rim; no PBR maps.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/tests/look/look_common.gdshaderinc"

uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D ilm_tex : hint_default_black, filter_linear_mipmap;
uniform bool use_ilm = false;
uniform float ramp_row = 1.0;                             // without a lightmap
uniform float threshold = 0.5;
uniform vec4 tint : source_color = vec4(1.0);
uniform float spec_strength = 0.7;

void fragment() {
	vec3 base = texture(base_tex, UV).rgb * tint.rgb;
	vec3 N = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec4 ilm = use_ilm ? texture(ilm_tex, UV) : vec4(0.0, threshold, 0.0, (ramp_row + 0.5) / 16.0);
	float half_l = dot(N, key_dir) * 0.5 + 0.5;
	float lit = clamp(half_l * ilm.g * 2.0, 0.0, 1.0);
	vec3 col = base * look_ramp(lit, floor(ilm.a * 16.0)) * key_color * key_energy + base * ambient_color;
	float nh = max(dot(N, normalize(key_dir + V)), 0.0);
	float spec = smoothstep(1.0 - ilm.b * 0.3, 1.0 - ilm.b * 0.3 + 0.02, nh) * ilm.r * spec_strength * smoothstep(0.45, 0.55, lit);
	col += spec * key_color * mix(vec3(1.0), base, 0.5);
	col += look_rim(N, V, base);
	ALBEDO = col;
}
