shader_type canvas_item;
// The MV look over the frame (2026-10-19, the lake MV): a warm/cool split grade (cool shadows, warm highlights), a
// soft vignette, a lens flare and an anamorphic streak from the moon when it is in the frame, a light sweep across
// the frame as the camera passes it, and the white flash on a chorus drop. No blur here (depth of field is the
// camera's own).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float vignette = 0.32;
uniform float grade = 0.6;
uniform float flash = 0.0;
uniform vec2 flare_pos = vec2(-2.0, -2.0);
uniform float flare = 0.0;
uniform float sweep = -1.0;           // -1 off, 0..1 its pass across the frame
uniform float aspect = 1.7778;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 g = mix(vec3(0.9, 0.97, 1.1), vec3(1.08, 1.0, 0.9), smoothstep(0.12, 0.7, l));
	c = mix(c, c * g, grade);
	if (flare > 0.001) {
		vec2 d = (uv - flare_pos) * vec2(aspect, 1.0);
		float glow = exp(-dot(d, d) * 22.0) * 0.18;
		float streak = exp(-abs(d.y) * 140.0) * exp(-abs(d.x) * 1.9) * 0.45;
		vec3 fl = vec3(0.72, 0.84, 1.0) * (glow + streak);
		vec2 axis = vec2(0.5) - flare_pos;
		for (int i = 1; i <= 5; i++) {
			float k = float(i) * 0.42;
			vec2 gp = flare_pos + axis * k * 1.15;
			float r = 0.025 + 0.022 * float(i);
			float dd = length((uv - gp) * vec2(aspect, 1.0));
			float ring = smoothstep(r, r * 0.55, dd) * 0.1 + exp(-pow((dd - r) * 60.0, 2.0)) * 0.06;
			fl += mix(vec3(0.55, 0.72, 1.0), vec3(1.0, 0.78, 0.5), float(i) / 5.0) * ring;
		}
		c += fl * flare;
	}
	if (sweep >= 0.0) {
		float p = (uv.x * 0.85 + uv.y * 0.5) - mix(-0.5, 1.85, sweep);
		float band = exp(-p * p * 30.0);
		c += vec3(1.0, 0.92, 0.8) * band * 0.4 * sin(3.14159 * clamp(sweep, 0.0, 1.0));
	}
	vec2 v = (uv - 0.5) * vec2(1.0, 1.15);
	float vg = smoothstep(0.82, 0.22, length(v));
	c *= mix(1.0 - vignette, 1.0, vg);
	c = mix(c, vec3(1.0), clamp(flash, 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
