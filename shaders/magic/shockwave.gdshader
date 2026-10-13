shader_type spatial;
// Expanding impact ring drawn analytically (scale the quad to grow it). Additive, unshaded.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.4);
uniform float intensity = 3.0;
uniform float thickness = 0.08;

void fragment() {
	float r = length((UV - 0.5) * 2.0);
	float ring = exp(-pow((r - 0.9) / thickness, 2.0));
	float inner = smoothstep(0.9, 0.2, r) * 0.12;
	ALBEDO = color * (ring * 1.6 + inner) * intensity * (1.0 - smoothstep(0.97, 1.0, r));
}
