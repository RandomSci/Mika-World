shader_type spatial;
// Falling water sheet: vertically streaking noise, white foam, translucent edges. UV.y = 0 top, 1 bottom.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float speed = 1.4;
uniform vec3 water_col : source_color = vec3(0.82, 0.9, 0.94);
void fragment() {
	vec2 uv = vec2(UV.x * 3.0, UV.y * 0.6 - TIME * speed);
	float s1 = texture(noise_tex, uv * vec2(1.0, 0.25)).r;
	float s2 = texture(noise_tex, uv * vec2(2.7, 0.5) + 0.37).r;
	float streak = smoothstep(0.35, 0.8, s1 * 0.6 + s2 * 0.6);
	float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
	float foam = smoothstep(0.7, 1.0, UV.y) * 0.8 + streak * 0.6;
	ALBEDO = mix(water_col * 0.55, vec3(0.95), clamp(foam, 0.0, 1.0));
	ALPHA = clamp((0.7 + streak * 0.3) * edge, 0.0, 0.97);
	ROUGHNESS = 0.2;
	EMISSION = vec3(0.25, 0.3, 0.33) * (0.4 + foam);
}
