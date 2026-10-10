shader_type spatial;
// Arcane orb layers. Use with layer_mode: 0 = hot core, 1 = flowing energy shell, 2 = outer haze.
render_mode blend_add, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform int layer_mode = 1;
uniform vec3 color_a : source_color = vec3(0.35, 0.65, 1.0);
uniform vec3 color_b : source_color = vec3(0.75, 0.45, 1.0);
uniform float intensity = 1.0;
uniform float flow_speed = 0.6;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
	if (layer_mode == 1) {
		// writhing surface
		float n = texture(noise_tex, vec2(atan(VERTEX.z, VERTEX.x) * 0.3 + TIME * 0.2, VERTEX.y * 0.8 - TIME * 0.35)).r;
		VERTEX += NORMAL * (n - 0.5) * 0.06;
	}
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), layer_mode == 0 ? 1.2 : 2.4);
	vec3 col;
	float a;
	if (layer_mode == 0) {
		float centre = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		col = mix(color_a * 1.4, vec3(1.0, 0.98, 1.0), centre) * (2.5 + centre * 4.0);
		a = 1.0;
	} else if (layer_mode == 1) {
		vec3 d = normalize(lpos);
		vec2 uv = vec2(atan(d.z, d.x) / 6.2831 + TIME * flow_speed * 0.15, d.y * 0.5 + 0.5);
		float n1 = texture(noise_tex, uv * vec2(2.0, 1.5) + vec2(0.0, -TIME * flow_speed * 0.3)).r;
		float n2 = texture(noise_tex, uv * vec2(4.0, 3.0) + vec2(TIME * 0.11, TIME * 0.07)).r;
		float bands = smoothstep(0.55, 0.75, n1 * 0.7 + n2 * 0.5);
		float veins = pow(1.0 - abs(n2 - 0.5) * 2.0, 8.0);
		col = mix(color_a, color_b, n1) * (bands * 1.6 + veins * 2.5 + fres * 2.2);
		a = 1.0;
	} else {
		col = mix(color_b, color_a, fres) * fres * 1.2;
		a = 1.0;
	}
	ALBEDO = col * intensity * a;
}
