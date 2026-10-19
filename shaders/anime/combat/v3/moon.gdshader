// Combat v3 magic: a full moon conjured as a spell (Download(9) 1:27.4-1:30.2): a pale disc of the moon - soft maria
// and craters from layered noise - glowing at its rim, emissive, with a soft halo; dissolve 1 -> 0 grows it in.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.85, 0.92, 1.0);
uniform vec3 edge : source_color = vec3(0.35, 0.55, 1.0);
uniform float energy = 1.6;
uniform float dissolve = 0.0;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float m = texture(noise, UV * vec2(2.0, 1.0)).r;
	float c = texture(noise, UV * vec2(9.0, 4.5) + 0.31).r;
	float maria = smoothstep(0.35, 0.65, m);
	float craters = smoothstep(0.55, 0.75, c) - smoothstep(0.75, 0.85, c) * 0.5;
	float surf = mix(1.0, 0.55, maria) + craters * 0.2;
	float rim = pow(1.0 - facing, 2.5);
	float keep = smoothstep(dissolve - 0.05, dissolve + 0.05, m * 0.5 + facing * 0.5);
	// blue moon: the maria deep in her colour, the highlands pale, darker toward the limb, a bright glowing rim
	vec3 col = mix(edge * 0.55, mix(edge, core, 0.55), surf) * (0.35 + 0.65 * pow(facing, 0.7)) + core * rim * 2.2;
	float a = clamp((0.6 * facing + rim) * keep, 0.0, 1.0);
	ALBEDO = col * energy * keep;
	ALPHA = a;
}
