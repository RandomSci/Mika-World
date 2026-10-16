shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
// The hero tree's leaves and twigs (Poly Haven island_tree_01, CC0) swaying slowly in the night wind. The offset is a
// function of world position only, so leaves and the twigs they hang on move together; nothing below the crown moves.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float alpha_cut = 0.45;
uniform vec3 tint : source_color = vec3(0.7, 0.75, 0.9);
uniform vec3 base_world = vec3(0.0);
uniform float calm_height = 4.0;               // metres above the base where swaying starts
uniform float amp = 0.035;                     // metres of sway per metre above calm_height (capped)
uniform vec3 back_light : source_color = vec3(0.05, 0.06, 0.12);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float hgt = clamp(wp.y - base_world.y - calm_height, 0.0, 10.0);
	float w = hgt * amp;
	vec3 off = vec3(sin(TIME * 0.55 + wp.x * 0.21 + wp.z * 0.13), 0.0, cos(TIME * 0.43 + wp.z * 0.19 - wp.x * 0.07)) * w;
	off += vec3(sin(TIME * 1.9 + wp.y * 2.3 + wp.x), sin(TIME * 2.3 + wp.z * 2.1) * 0.5, cos(TIME * 1.7 + wp.z * 2.7)) * w * 0.12;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * tint;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	vec3 arm = texture(arm_tex, UV).rgb;
	AO = arm.r;
	ROUGHNESS = arm.g;
	BACKLIGHT = back_light;
}
