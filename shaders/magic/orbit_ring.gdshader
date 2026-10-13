shader_type spatial;
// An Aether Orbit: a thin ring with `glyphs` bright knots travelling around it (the first orbit of a mage).
// Drawn on a flat quad; tilt the node to incline the orbit.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.86, 0.94);
uniform vec3 accent : source_color = vec3(0.75, 0.9, 1.0);
uniform float intensity = 1.0;
uniform int glyphs = 7;
uniform float spin = 0.35;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ang01 = fract((a + 3.14159) / 6.28318);
	float ring = exp(-pow((r - 0.86) / 0.018, 2.0)) + 0.35 * exp(-pow((r - 0.8) / 0.008, 2.0));
	float g = float(glyphs);
	float k = fract((a / 6.28318) * g - TIME * spin);
	float knot = exp(-pow((k - 0.5) / 0.06, 2.0)) * exp(-pow((r - 0.86) / 0.05, 2.0));
	float shown = step(ang01, reveal);
	ALBEDO = (color * ring + accent * knot * 2.5) * intensity * shown;
}
