shader_type spatial;
// A ribbon of moving air (Mika's Gale Spiral): the mesh is a strip laid along the path the gust has really
// travelled, UV.x = 0 at the head and 1 at the tail. Soft edges, a bright core, streaks that flow back along
// the ribbon, fading toward the tail. Additive, so two ribbons crossing read as one braided current.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.78, 1.0, 0.9);
uniform vec3 color2 : source_color = vec3(0.5, 0.95, 0.62);
uniform float intensity = 1.0;
uniform float flow = 6.0;

void fragment() {
	float x = UV.x;
	float y = abs(UV.y - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.45, 1.0, y);
	float core = exp(-y * y * 6.0);
	float taper = pow(1.0 - x, 0.75);
	float streak = 0.72 + 0.28 * sin((x * 8.0 - TIME * flow) * 6.2831853);
	vec3 col = mix(color, color2, x);
	ALBEDO = col * (edge * 0.55 + core) * streak * taper * intensity;
}
