// A ribbon of flame for Oriel's transformation (it spirals around a limb as the garment there is made).
// UV.x runs along the ribbon (0 = the fading tail, 1 = the burning head), UV.y across it. Additive, HDR.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 col_head : source_color = vec3(1.0, 0.86, 0.5);
uniform vec3 col_tail : source_color = vec3(1.0, 0.3, 0.06);
uniform float strength = 2.4;
uniform float fade = 1.0;

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float n = texture(noise_tex, vec2(UV.x * 3.0 - TIME * 2.2, UV.y * 0.8 + TIME * 0.3)).r;
	float a = smoothstep(0.0, 0.6, across) * smoothstep(0.0, 0.45, UV.x) * (0.5 + 0.5 * n) * fade;
	vec3 c = mix(col_tail, col_head, UV.x * UV.x);
	ALBEDO = c * strength * (0.6 + 0.9 * n * across);   // unshaded: ALBEDO is the output
	ALPHA = clamp(a, 0.0, 1.0);
}
