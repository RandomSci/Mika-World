shader_type spatial;
render_mode diffuse_lambert_wrap;
// Stylized rocks (Milestone K): the pack's painted rock texture tinted toward the area's palette, with soft
// moss on up-facing surfaces (world space, broken by noise) and a cool cavity darkening low down.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D noise_tex : filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform vec4 moss_color : source_color = vec4(0.36, 0.5, 0.22, 1.0);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint.rgb;
	float n = texture(noise_tex, v_wp.xz * 0.15).r;
	float moss = smoothstep(0.45, 0.8, v_wn.y + (n - 0.5) * 0.5) * moss_amount;
	c = mix(c, moss_color.rgb * (0.85 + n * 0.3), moss);
	ALBEDO = c;
	ROUGHNESS = mix(0.88, 0.95, moss);
}
