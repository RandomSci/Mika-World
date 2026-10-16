shader_type spatial;
// A soft blossom petal drawn analytically on a quad (UV 0..1, base at the bottom, notched tip); the particle colour
// tints it (paler toward the tip). Unshaded with a little glow so it reads in shade; tumbles in 3D (no billboard).
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled, depth_draw_never;

uniform float glow = 0.35;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float y = 1.0 - UV.y;                          // 0 base .. 1 tip
	float w = 0.62 * sin(3.14159 * clamp(y * 0.92 + 0.04, 0.0, 1.0)) * (0.55 + 0.45 * y) + 0.02;
	float a = 1.0 - smoothstep(w - 0.10, w, abs(p.x));
	float notch = smoothstep(0.0, 0.12, (1.0 - y) * 1.6 + abs(p.x) * 1.2 - 0.02);
	a *= notch * smoothstep(0.0, 0.06, y);
	vec3 c = mix(COLOR.rgb * 0.92, mix(COLOR.rgb, vec3(1.0), 0.45), y);
	ALBEDO = c * (1.0 + glow);
	ALPHA = a * COLOR.a;
}
