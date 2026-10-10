shader_type spatial;
// Glowing rune beam along UV.x (0 = caster, 1 = target), drawn up to `reach`, with travelling
// glyph-like bands and a soft core. Used by Rune Activation.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.55, 0.8, 1.0);
uniform float intensity = 1.0;
uniform float reach : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float x = UV.x;
	float y = abs(UV.y - 0.5) * 2.0;
	float core = exp(-y * y * 18.0);
	float halo = exp(-y * y * 3.0) * 0.35;
	float bands = 0.65 + 0.35 * step(0.55, fract(x * 14.0 - TIME * 4.0));
	float head = smoothstep(reach, reach - 0.03, x);
	float tip = exp(-pow((x - reach) * 25.0, 2.0)) * 1.5;
	ALBEDO = color * ((core * bands + halo) * head + tip * core) * intensity;
}
