shader_type spatial;
// Duel light sprite (2026-10-19): a camera-facing quad with the reference's three-layer light - a white-hot core in
// the shape of a Brackeys CC0 particle (a star for Mika, a crescent for Luna), a coloured glow round it and a wide
// faint haze. HDR + additive, so the bloom carries it. The shape occupies `shape_scale` of the quad (the rest is glow).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float energy = 3.0;
uniform float shape_scale = 0.45;
uniform float glow = 1.0;
uniform float haze = 0.35;
uniform float spin = 0.0;
uniform float fade = 1.0;
uniform bool billboard = true;

void vertex() {
	if (billboard) {
		mat4 bb = mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
			INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	}
}

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float cs = cos(spin), sn = sin(spin);
	vec2 q = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y) / shape_scale + 0.5;
	float shape = 0.0;
	if (q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0) {
		vec4 t = texture(tex, q);
		shape = t.a * dot(t.rgb, vec3(0.333));
	}
	float g = exp(-r * r * 9.0) * glow;
	float h = exp(-r * 3.2) * haze * (1.0 - smoothstep(0.85, 1.0, r));
	vec3 col = core.rgb * pow(shape, 1.4) * 1.8 + color.rgb * (shape * 0.9 + g) + color.rgb * h;
	ALBEDO = clamp(col * energy * fade * COLOR.rgb * COLOR.a, vec3(0.0), vec3(64.0));   // (never a NaN into the glow pass)
}
