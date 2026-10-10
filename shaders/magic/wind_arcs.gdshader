shader_type spatial;
// Wind sigil: no closed circle. Several thin crescent arcs sweep around the centre at different radii
// and speeds, with streaming dashes, like air drawn into a spiral. `arcs` grows with mastery.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.7, 1.0, 0.85);
uniform float intensity = 1.0;
uniform float spin = 1.4;
uniform int arcs = 3;
uniform float draw_progress : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float acc = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= arcs) break;
		float fi = float(i);
		float rad = 0.32 + fi * 0.13;
		float ang = a + TIME * spin * (1.0 + fi * 0.35) * (mod(fi, 2.0) < 0.5 ? 1.0 : -0.7) + fi * 1.7;
		float seg = fract(ang / 6.2831853);
		float len = 0.38 * draw_progress;
		float on = smoothstep(0.0, 0.04, seg) * smoothstep(len, len - 0.12, seg);
		float taper = smoothstep(0.0, len, seg);
		float width = 0.012 + 0.012 * taper;
		float ring = smoothstep(width, 0.0, abs(r - rad - 0.04 * sin(seg * 9.0 + TIME)));
		float dash = 0.6 + 0.4 * step(0.5, fract(seg * 18.0 - TIME * 3.0));
		acc += ring * on * dash * taper;
	}
	float core = exp(-r * r * 30.0) * 0.25;
	float fade = smoothstep(1.0, 0.8, r);
	ALBEDO = color * (acc + core) * intensity * fade;
}
