shader_type spatial;
// Luminous mineral crystal: dark glassy body, inner glow from fresnel + height, subtle pulse.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(0.3, 0.85, 1.0);
uniform float glow = 2.5;
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float pulse = 0.85 + 0.15 * sin(TIME * 0.9 + wp.x * 0.7 + wp.z * 0.5);
	float core = smoothstep(0.0, 1.0, lpos.y) * 0.6 + 0.4;
	ALBEDO = tint * 0.08;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = tint * glow * pulse * (0.25 + core * 0.45 + fres * 1.4);
	BACKLIGHT = tint * 0.6;
}
