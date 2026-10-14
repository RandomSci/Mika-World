// SWORD WAVE: the crescent of cutting light a sword technique throws (anime "zangeki"). On a flat quad: a thin bright
// arc bulging forward (UV v = 0 is the leading edge), hot white core, coloured rim, tapered tips, flickering.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float energy = 3.0;
uniform float width = 0.07;

void fragment() {
	vec2 p = UV - vec2(0.5, 0.82);
	float r = length(p);
	float band = 1.0 - smoothstep(0.0, width, abs(r - 0.62));
	float ang = atan(p.x, -p.y);                     // 0 straight ahead
	float tips = 1.0 - smoothstep(0.55, 1.15, abs(ang));
	float trail = smoothstep(0.62 - width * 3.5, 0.62, r);   // a soft wake behind the edge
	float core = 1.0 - smoothstep(0.0, width * 0.35, abs(r - 0.62));
	float flick = 0.85 + 0.15 * sin(TIME * 60.0 + ang * 7.0);
	float a = (band * 0.8 + core * 1.2) * tips * trail * flick;
	ALBEDO = mix(color.rgb, vec3(1.0), core * 0.7) * energy * a;
}
