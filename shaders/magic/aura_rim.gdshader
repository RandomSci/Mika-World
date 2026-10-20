// Her aura while she gathers a technique (PetalArts.aura): a rim of her colour round her whole silhouette, warming to
// the petals' pink at its edge, shimmering upward like heat. Drawn over her own materials (material_overlay), added.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 col : source_color = vec3(0.6, 0.85, 1.0);
uniform vec3 petal : source_color = vec3(1.0, 0.55, 0.78);
uniform float k = 0.0;

varying float wy;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(f, 3.2);
	float shimmer = 0.75 + 0.25 * sin(TIME * 7.0 - wy * 9.0) * sin(TIME * 3.1 + wy * 4.0);
	vec3 c = mix(col, petal, smoothstep(0.55, 1.0, f) * 0.6);
	ALBEDO = c * rim * k * 0.75 * shimmer;
}
