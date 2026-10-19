// Anime impact frame (docs/VFX_STYLE_GUIDE.md section 3): a few one-frame passes over the whole picture - a white flash
// with radial speed lines, an inverted negative, an element-coloured tint - driven by `stage` from ImpactFrame.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform int stage = 0;                      // 0 off, 1 flash + lines, 2 negative, 3 tint
uniform vec3 tint : source_color = vec3(0.55, 0.62, 1.0);
uniform vec2 center = vec2(0.5, 0.5);

float lines(vec2 uv) {
	vec2 d = uv - center;
	float ang = atan(d.y, d.x);
	float r = length(d);
	float l = step(0.86, fract(sin(floor(ang * 64.0) * 91.3) * 437.5));       // random radial rays
	return l * smoothstep(0.12, 0.7, r);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 o = c;
	if (stage == 1) {
		o = mix(vec3(1.0), tint, 0.18) * (0.75 + 0.25 * step(0.35, lum));
		o = mix(o, vec3(0.05), lines(SCREEN_UV) * 0.85);
	} else if (stage == 2) {
		o = vec3(1.0) - vec3(step(0.42, lum));                                 // the inverted, two-tone silhouette
		o = mix(o, tint * 0.25, 0.25);
	} else if (stage == 3) {
		o = mix(c, tint * (0.6 + lum), 0.45) + vec3(lines(SCREEN_UV) * 0.25);
	}
	COLOR = vec4(o, stage == 0 ? 0.0 : 1.0);
}
