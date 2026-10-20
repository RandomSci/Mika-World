shader_type spatial;
// The orb behind her (ref v4 7.0 / 12.0 s): a flat disc of sun-lit cloud - a warm cream-gold core breaking into cool
// blue cloud at the edge, slowly churning, with a hot centre that blooms (bloom 0..1 for the build-up).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D noise_tex : repeat_enable;
uniform vec3 core_color : source_color = vec3(1.0, 0.86, 0.63);
uniform vec3 edge_color : source_color = vec3(0.25, 0.45, 0.95);
uniform float bloom = 0.0;
uniform float alpha_scale = 1.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	vec2 q = vec2(a / 6.28318 * 3.0 + TIME * 0.01, r * 1.2 - TIME * 0.02);
	float n = texture(noise_tex, q).r * 0.6 + texture(noise_tex, p * 1.7 + vec2(TIME * 0.015, 0.0)).r * 0.4;
	float cloud = smoothstep(0.38, 0.68, n + (1.0 - r) * 0.3);
	vec3 col = mix(edge_color * 0.45, core_color * (0.55 + 0.6 * cloud), smoothstep(1.0, 0.1, r) * (0.35 + 0.65 * cloud));
	col += core_color * pow(1.0 - r, 4.0) * (0.5 + bloom * 3.0);
	col += vec3(1.0) * pow(1.0 - r, 10.0) * bloom * 6.0;
	float edge = smoothstep(1.0, 0.82, r);
	ALBEDO = col * (1.0 + bloom * 0.8);
	ALPHA = edge * clamp(0.45 + cloud * 0.55, 0.0, 1.0) * alpha_scale;
}
