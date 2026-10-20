shader_type spatial;
// A light ribbon trail (hands, hem, the spin spirals): a hot white-gold core along the middle, a coloured glow out to
// the edges, a short taper at the head and a long fade to the tail (UV.x = 0 head -> 1 tail; UV.y across).
// HDR + additive: the bloom makes it shine.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.75, 0.55, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float energy = 3.0;
uniform float fade_all = 1.0;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float fade = pow(1.0 - UV.x, 1.25) * smoothstep(0.0, 0.03, UV.x + 0.01);
	float c = exp(-across * across * 38.0);
	float g = exp(-across * across * 4.5) * (1.0 - across);
	ALBEDO = (core.rgb * c * 1.6 + color.rgb * g) * fade * energy * fade_all;
}
