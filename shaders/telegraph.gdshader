shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;
// Ground telegraph for a creature's coming attack: an outline that is clear from the first frame and an
// inner fill that grows toward the edge as the blow approaches (progress 0 -> 1). Sector mode for sweeps.

uniform vec4 color : source_color = vec4(1.0, 0.55, 0.25, 1.0);
uniform float progress = 0.0;
uniform float intensity = 1.0;
uniform float half_angle = 3.2;     // radians; >= PI = full circle

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = abs(atan(p.x, p.y));            // 0 = straight ahead (+V)
	float inside_sector = step(a, half_angle);
	float edge = smoothstep(0.86, 0.94, r) * smoothstep(1.0, 0.95, r);
	float fill = smoothstep(progress + 0.02, progress - 0.02, r) * 0.35;
	float pulse = 0.75 + 0.25 * sin(TIME * 18.0 * (0.5 + progress));
	float alpha = (edge * pulse + fill) * inside_sector * step(r, 1.0);
	ALBEDO = color.rgb * intensity;
	ALPHA = alpha * color.a;
}
