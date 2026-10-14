shader_type spatial;
// Luna's Umbral Rift on the ground: a six-sided pane of shadow (alpha-blended, so it DARKENS the ground)
// with gold cracks spreading out from the centre as `draw_progress` rises, a gold hex rim and a violet
// glow at the heart. `scorch` = 1 is the cold scar the rift leaves behind: dark, with a faint ember in the cracks.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 gold : source_color = vec3(1.0, 0.78, 0.32);
uniform vec3 violet : source_color = vec3(0.55, 0.25, 0.95);
uniform vec3 dark : source_color = vec3(0.03, 0.01, 0.06);
uniform float intensity = 1.0;
uniform float draw_progress : hint_range(0.0, 1.0) = 1.0;
uniform float scorch : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }

float hex(vec2 p, float r) {
	p = abs(p);
	return max(dot(p, vec2(0.866025, 0.5)), p.x) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float d = hex(p, 0.86);
	float inside = 1.0 - smoothstep(-0.01, 0.01, d);
	float rim = exp(-pow(d / 0.025, 2.0));
	float inner_rim = exp(-pow((d + 0.16) / 0.012, 2.0)) * 0.6;
	float ang = atan(p.y, p.x);
	float cr = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float a0 = fi * 0.8976 + (hash(vec2(fi, 2.0)) - 0.5) * 0.6;
		float da = ang - a0;
		da = atan(sin(da), cos(da));
		float wob = sin(r * 23.0 + fi * 3.0) * 0.05 + sin(r * 41.0 + fi) * 0.02;   // jagged, not ruled
		float dist = abs(da + wob) * r;
		float width = 0.012 + 0.02 * (1.0 - r);
		float line = 1.0 - smoothstep(width * 0.5, width, dist);
		float reach = step(r, 0.12 + 0.78 * draw_progress);
		cr = max(cr, line * reach);
	}
	float pulse = 0.75 + 0.25 * sin(TIME * 5.0);
	float glow = exp(-r * r * 6.0) * 0.5 * draw_progress;
	vec3 live = dark + gold * (cr * 2.2 + rim * 2.5 + inner_rim) * pulse * intensity + violet * glow * intensity;
	vec3 scar = dark * 1.3 + gold * (cr * 0.22 + rim * 0.15) * (0.6 + 0.4 * sin(TIME * 1.3));
	ALBEDO = mix(live, scar, scorch);
	float a = inside * mix(0.82, 0.6, scorch) * (1.0 - smoothstep(0.9, 1.0, r));
	ALPHA = a * clamp(intensity, 0.0, 1.0) * (0.3 + 0.7 * max(draw_progress, scorch));
}
