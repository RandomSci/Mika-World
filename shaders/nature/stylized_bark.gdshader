shader_type spatial;
render_mode diffuse_lambert_wrap;
// Stylized bark (Milestone K): the pack's painted bark texture, tinted per tree type, darker at the root,
// a moss band on the up-facing side low on the trunk, and the same wind sway as the crown (so trunk and leaves
// move together). Normal map kept subtle.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 moss_color : source_color = vec4(0.32, 0.45, 0.2, 1.0);
uniform float moss_amount = 0.45;
uniform float canopy_bottom = 1.5;
uniform float canopy_top = 7.0;
#include "res://shaders/nature/gust.gdshaderinc"

uniform float wind_strength = 0.12;
uniform float wind_speed = 1.1;

varying vec3 v_local;
varying vec3 v_wn;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
	float h = clamp((VERTEX.y - canopy_bottom) / max(canopy_top - canopy_bottom, 0.01), 0.0, 1.0);
	float ph = wp.x * 0.21 + wp.z * 0.17 + INSTANCE_CUSTOM.g * 6.2831;
	float sway = sin(TIME * wind_speed + ph) * 0.6 + sin(TIME * wind_speed * 2.3 + ph * 1.7) * 0.25;
	VERTEX.x += sway * wind_strength * h * h;
	VERTEX.z += sway * wind_strength * 0.6 * h * h;
	if (gust_on > 0.5) {
		vec3 root = MODEL_MATRIX[3].xyz;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * gust_offset(gust_push(root), wp.y - root.y, max(canopy_top, 2.0));
	}
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
	float root = smoothstep(0.0, 1.2, v_local.y);
	c *= mix(0.55, 1.0, root);
	float moss = smoothstep(0.1, 0.7, v_wn.y + 0.35) * (1.0 - smoothstep(0.4, 2.2, v_local.y)) * moss_amount;
	c = mix(c, moss_color.rgb, moss);
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = 0.92;
}
