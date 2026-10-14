shader_type spatial;
// Luna's Gilded Mirror: a hexagonal pane of dark glass held before her. A gold rim, hairline gold tracery,
// faceted sectors that catch a slow sheen, violet at grazing angles; `hit_flash` lights the whole pane when a
// bolt strikes it. Alpha-blended (a pane of shadow, not a glow), the rim and flash bright.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 gold : source_color = vec3(1.0, 0.8, 0.35);
uniform vec3 violet : source_color = vec3(0.6, 0.3, 1.0);
uniform vec3 glass : source_color = vec3(0.05, 0.02, 0.1);
uniform float intensity = 1.0;
uniform float hit_flash = 0.0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;

float hex(vec2 p, float r) {
	p = abs(p);
	return max(dot(p, vec2(0.866025, 0.5)), p.x) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = hex(p, 0.9 * reveal);
	float inside = 1.0 - smoothstep(-0.01, 0.01, d);
	float rim = exp(-pow(d / 0.03, 2.0));
	float ang = atan(p.y, p.x);
	float sector = floor((ang + 3.14159) / 1.0472);
	float facet = 0.07 * fract(sin(sector * 7.3 + floor(TIME * 0.5)) * 43758.5);
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float sheen = exp(-pow((p.x + p.y * 0.4 - sin(TIME * 0.9) * 1.4) / 0.25, 2.0)) * 0.35;
	float web = 0.0;
	for (int i = 0; i < 3; i++) {
		float a = float(i) * 1.0472;
		vec2 dir = vec2(cos(a), sin(a));
		float dist = abs(dot(p, vec2(-dir.y, dir.x)));
		web = max(web, 1.0 - smoothstep(0.004, 0.012, dist));
	}
	vec3 col = glass + facet * 0.6 + violet * (fres * 0.35 + 0.04) * intensity
		+ gold * (rim * 3.4 + web * 0.6 + sheen * 0.8 + hit_flash * 2.5) * intensity;
	ALBEDO = col;
	ALPHA = inside * (0.8 + 0.2 * fres + hit_flash * 0.2) * clamp(intensity, 0.0, 1.0);
}
