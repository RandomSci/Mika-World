// Anime hair (test only): the toon ramp plus a controlled angel ring, a band of highlight around the head computed in
// head space (it does not depend on the hair's UVs, which Tripo scatters), centred a little toward the viewer and
// broken into strands; strength, height, width and colour are uniforms.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
#include "res://shaders/tests/look/look_common.gdshaderinc"

uniform sampler2D base_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float ramp_row = 5.0;
uniform mat4 head_inv;                                    // world -> head space, set by the rig
uniform vec3 ring_color : source_color = vec3(1.0, 0.98, 1.0);
uniform float ring_strength = 0.8;
uniform float ring_height = 0.62;                         // head-space normal height of the band
uniform float ring_width = 0.07;
uniform float ring_follow = 0.3;                          // how much the band follows the view's height

void fragment() {
	vec3 base = texture(base_tex, UV).rgb * tint.rgb;
	vec3 N = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 V = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float lit = clamp(dot(N, key_dir) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = base * look_ramp(lit, ramp_row) * key_color * key_energy + base * ambient_color;
	vec3 nh = normalize((head_inv * vec4(N, 0.0)).xyz);
	vec3 vh = normalize((head_inv * vec4(V, 0.0)).xyz);
	float c = ring_height + vh.y * ring_follow;
	float band = 1.0 - smoothstep(0.0, ring_width, abs(nh.y - c));
	float az = atan(nh.x, nh.z);
	float strands = 0.55 + 0.45 * sin(az * 46.0 + sin(az * 9.0) * 2.5);
	band *= strands * smoothstep(0.15, 0.55, dot(N, V)) * mix(0.4, 1.0, smoothstep(0.4, 0.6, lit));
	col += band * ring_strength * ring_color * key_color;
	col += look_rim(N, V, base);
	ALBEDO = col;
}
