shader_type spatial;
// Magical blade: polished steel body with an engraved, glowing rune channel and luminous edges.
// `element` colour + `charge` (0..1) drive the glow; flowing noise suggests energy in the fuller.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
uniform vec3 steel : source_color = vec3(0.62, 0.64, 0.68);
uniform vec3 element : source_color = vec3(0.35, 0.65, 1.0);
uniform float charge : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// UV.x across the blade (0..1, 0.5 = spine), UV.y along it (0 = guard, 1 = tip)
void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float fuller = 1.0 - smoothstep(0.08, 0.18, across);
	float edge = smoothstep(0.82, 1.0, across);
	float flow = texture(noise_tex, vec2(UV.x * 0.5, UV.y * 2.0 - TIME * 0.6)).r;
	float runes = step(0.55, fract(UV.y * 22.0)) * step(fract(UV.y * 22.0), 0.85) * fuller;
	METALLIC = 1.0;
	ROUGHNESS = mix(0.18, 0.35, flow * 0.5);
	ALBEDO = steel * mix(1.0, 0.55, fuller);
	float glow = (fuller * (0.25 + flow * 0.6) + runes * 0.8 + edge * 0.6) * (0.2 + charge * 1.8);
	EMISSION = element * glow * 2.5;
}
