shader_type spatial;
// Water sigil: concentric rings that expand outward and fade, with a soft caustic shimmer between
// them. No glyphs. `rings` grows with mastery.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.75, 1.0);
uniform float intensity = 1.0;
uniform int rings = 3;
uniform float speed = 0.35;
uniform float draw_progress : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p) / max(draw_progress, 0.001);
	float acc = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= rings) break;
		float ph = fract(TIME * speed + float(i) / float(rings));
		float rad = ph * 0.95;
		acc += smoothstep(0.03, 0.0, abs(r - rad)) * (1.0 - ph) * 1.2;
	}
	float caustic = 0.5 + 0.5 * sin(p.x * 23.0 + TIME * 1.7) * sin(p.y * 19.0 - TIME * 1.3);
	float inner = smoothstep(1.0, 0.0, r) * caustic * 0.18;
	float fade = smoothstep(1.0, 0.85, r);
	ALBEDO = color * (acc + inner) * intensity * fade;
}
