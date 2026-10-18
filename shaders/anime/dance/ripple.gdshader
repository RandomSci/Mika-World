shader_type spatial;
// A glowing ripple ring on the lake under her feet: one crisp bright line with a soft halo, and a thin echo inside it,
// widening and fading (t 0..1 over its life). HDR + additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float t = 0.0;
uniform float energy = 3.0;
uniform float sharp = 1.0;              // < 1: a softer, wider line (a gentle water ripple, not a glowing ring)

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float e = 1.0 - pow(1.0 - t, 2.2);                 // fast out, slow settle
	float r1 = mix(0.06, 0.96, e);
	float r2 = r1 * 0.82;
	float d1 = (r - r1) * 90.0 * sharp;
	float d2 = (r - r2) * 120.0 * sharp;
	float line = exp(-d1 * d1) + 0.35 * exp(-d2 * d2);
	float halo = exp(-pow((r - r1) * 18.0, 2.0)) * 0.45;
	float life = (1.0 - t) * smoothstep(0.0, 0.05, t);
	ALBEDO = (core.rgb * line + color.rgb * (halo + line * 0.6)) * life * energy * step(r, 1.0);
}
