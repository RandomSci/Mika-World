shader_type spatial;
// A soft water ripple from the boat (the oars' catch, the wake): not a glowing ring - a faint, wide swell of sky
// reflection with a darker trough just inside it, widening and fading (t 0..1 over its life). Mixed, not added, so
// it reads as the water itself moving (Selwyn 2026-10-19: "soft subtle water ripples that only appear when it moves").
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(0.62, 0.68, 0.82, 1.0);   // the sky in the water
uniform vec4 trough : source_color = vec4(0.02, 0.03, 0.06, 1.0);  // the dark side of the swell
uniform float t = 0.0;
uniform float strength = 0.16;          // peak opacity of the crest
uniform float width = 0.075;            // the swell's half width (in ring radii)

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float e = 1.0 - pow(1.0 - t, 1.8);
	float r1 = mix(0.08, 0.95, e);
	float w = width * mix(0.7, 1.6, e);                  // it spreads as it widens
	float crest = exp(-pow((r - r1) / w, 2.0));
	float dip = exp(-pow((r - (r1 - w * 1.6)) / (w * 1.2), 2.0));
	float echo = 0.45 * exp(-pow((r - r1 * 0.72) / (w * 0.9), 2.0));
	float life = pow(1.0 - t, 1.6) * smoothstep(0.0, 0.08, t);
	float edge = 1.0 - smoothstep(0.85, 1.0, r);
	float a_crest = (crest + echo) * strength;
	float a_dip = dip * strength * 0.8;
	ALBEDO = mix(trough.rgb, color.rgb, a_crest / max(a_crest + a_dip, 1e-4));
	ALPHA = clamp((a_crest + a_dip) * life * edge, 0.0, 1.0);
}
