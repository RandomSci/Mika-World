shader_type spatial;
// Mika's ground sign for growing magic: not a circle of glyphs but a wreath of leaves drawn analytically
// round her feet, each leaf a lens with a vein, unfolding outward as `draw_progress` rises, turning slowly.
// A thin woven ring inside and a soft glow at the centre. Additive, no texture.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.6, 0.95, 0.5);
uniform vec3 vein_color : source_color = vec3(0.95, 0.9, 0.6);
uniform float intensity = 1.0;
uniform int leaves = 12;
uniform float spin = 0.25;
uniform float draw_progress : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * spin;
	float n = float(max(leaves, 3));
	float sector = 6.2831853 / n;
	float k = floor(a / sector + 0.5);
	float local = a - k * sector;                       // angle from this leaf's axis
	float r0 = 0.30;
	float r1 = r0 + 0.6 * draw_progress;
	float u = clamp((r - r0) / max(r1 - r0, 0.001), 0.0, 1.0);
	float half_w = 0.5 * sector * pow(sin(u * 3.14159), 0.8) * (0.35 + 0.65 * draw_progress);
	float inside = step(r0, r) * step(r, r1) * (1.0 - smoothstep(half_w * 0.8, half_w, abs(local)));
	float vein = inside * (1.0 - smoothstep(0.0, 0.014, abs(local) * r));
	float side_vein = inside * (1.0 - smoothstep(0.0, 0.6, abs(fract(u * 4.0 + 0.5) - 0.5) * 2.0 + abs(local) / max(half_w, 0.001) * 0.4)) * 0.18;
	float body = inside * (0.28 + 0.42 * u);
	float edge = inside * smoothstep(half_w * 0.55, half_w * 0.95, abs(local)) * 0.9;
	float ring = exp(-pow((r - 0.26) / 0.012, 2.0)) * 0.8 * draw_progress;
	float ring2 = exp(-pow((r - 0.22) / 0.008, 2.0)) * 0.4 * draw_progress;
	float glow = exp(-r * r * 14.0) * 0.3 * draw_progress;
	vec3 col = color * (body + edge + ring + ring2 + glow + side_vein) + vein_color * vein;
	float fade = 1.0 - smoothstep(0.92, 1.0, r);
	ALBEDO = col * intensity * fade;
}
