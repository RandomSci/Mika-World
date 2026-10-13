shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Churning white water where the falls hit the pool (Milestone K, original): animated noise rings spreading
// outward from the impact line, fading to nothing at the patch edge. UV.y = 0 at the impact, 1 downstream.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(0.94, 0.98, 0.97, 1.0);
uniform float opacity = 0.85;

void fragment() {
	float d = UV.y;
	float x = abs(UV.x - 0.5) * 2.0;
	float n1 = texture(noise_tex, vec2(UV.x * 2.2, d * 1.2 - TIME * 0.35)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 5.0 + 3.0, d * 2.8 - TIME * 0.6)).r;
	float foam = smoothstep(0.42, 0.62, n1 * 0.6 + n2 * 0.6 - d * 0.55);
	float fade = (1.0 - smoothstep(0.55, 1.0, x)) * (1.0 - smoothstep(0.35, 1.0, d));
	ALBEDO = color.rgb * (0.85 + n2 * 0.2);
	ALPHA = foam * fade * opacity;
}
