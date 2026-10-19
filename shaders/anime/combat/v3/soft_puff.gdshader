// Combat v3 magic: one soft billow of a light explosion (Download(9) 1:30.2, 2:59.3): a sphere drawn as glowing
// vapour - dense and white where it faces the eye, thinning to nothing at its silhouette, broken by drifting noise;
// `life` 0 -> 1 thins it out. Additive.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 edge : source_color = vec3(0.35, 0.62, 1.0);
uniform float energy = 2.0;
uniform float life = 0.0;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = texture(noise, UV * vec2(3.0, 2.0) + vec2(TIME * 0.05, life * 0.4)).r;
	float n2 = texture(noise, UV * vec2(7.0, 5.0) - vec2(life * 0.3, TIME * 0.08)).r;
	float body = pow(facing, 1.6) * smoothstep(life * 0.9 - 0.1, life * 0.9 + 0.35, n * 0.6 + n2 * 0.4);
	float a = clamp(body * (1.0 - life), 0.0, 1.0);
	ALBEDO = mix(edge, core, pow(facing, 3.0) * (1.0 - life * 0.6)) * energy * a;   // tinted at the edges, cooling to her colour as it thins
	ALPHA = a;
}
