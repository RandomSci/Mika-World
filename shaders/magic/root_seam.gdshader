shader_type spatial;
// A line of light racing along the ground from the caster (UV.x = 0) to the aimed point (1), drawn up to
// `reach`. With `wobble` it wanders like a root finding its way (Mika's Verdant Bind); with wobble 0 it is a
// ruled gold line that snaps to its mark (Luna's Umbral Rift). Additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.55, 0.95, 0.5);
uniform vec3 tip_color : source_color = vec3(0.95, 1.0, 0.7);
uniform float intensity = 1.0;
uniform float reach : hint_range(0.0, 1.0) = 0.0;
uniform float wobble = 1.0;

void fragment() {
	float x = UV.x;
	float yc = UV.y - 0.5 + sin(x * 31.0 + TIME * 3.0) * 0.08 * wobble + sin(x * 7.0 - TIME * 1.5) * 0.05 * wobble;
	float y = abs(yc) * 2.0;
	float core = exp(-y * y * 22.0);
	float halo = exp(-y * y * 4.0) * 0.25;
	float behind = smoothstep(reach, reach - 0.03, x);
	float trail_fade = 0.3 + 0.7 * smoothstep(reach - 0.4, reach, x);
	float tip = exp(-pow((x - reach) * 30.0, 2.0)) * 2.0;
	float beads = mix(1.0, 0.7 + 0.3 * step(0.5, fract(x * 22.0)), wobble);
	ALBEDO = (color * (core + halo) * behind * trail_fade * beads + tip_color * tip * core) * intensity;
}
