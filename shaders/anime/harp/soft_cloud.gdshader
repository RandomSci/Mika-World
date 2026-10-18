shader_type spatial;
// Night cloud banks for the sky set: soft fbm alpha, lit from the orb side.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable;
uniform vec3 color : source_color = vec3(0.12, 0.2, 0.42);
uniform vec3 lit_color : source_color = vec3(0.5, 0.65, 1.0);
uniform float drift = 0.01;
uniform float opacity = 0.85;

void fragment() {
	vec2 p = UV;
	float n = texture(noise_tex, p * 1.3 + vec2(TIME * drift, 0.0)).r * 0.65 + texture(noise_tex, p * 3.1 - vec2(0.0, TIME * drift)).r * 0.35;
	float edge = smoothstep(0.0, 0.25, p.x) * smoothstep(1.0, 0.75, p.x) * smoothstep(0.0, 0.3, p.y) * smoothstep(1.0, 0.7, p.y);
	float a = smoothstep(0.42, 0.7, n) * edge;
	ALBEDO = mix(color, lit_color, smoothstep(0.55, 0.85, n));
	ALPHA = a * opacity;
}
