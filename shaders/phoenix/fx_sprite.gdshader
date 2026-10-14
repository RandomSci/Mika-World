// Particle sprites for Oriel's fire (v3): `cell` 0 = a flame tongue (atlas cell (3,0), distorted by scrolling
// noise so every wisp licks), 1 = a spark glint (cell (3,1)). Camera-facing; colour and fade come from the
// particle colour ramp; additive and HDR so the bloom carries them.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform int cell = 0;
uniform float strength = 2.0;

varying float rnd;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mat4 sc = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * sc;
	rnd = fract(MODEL_MATRIX[3].x * 12.9898 + MODEL_MATRIX[3].z * 78.233);
}

void fragment() {
	vec2 uv = UV;
	float inten;
	float core;
	if (cell == 0) {
		vec2 q = vec2(uv.x * 0.7 + rnd * 5.0, uv.y * 1.2 + TIME * 1.6);
		float n1 = texture(noise_tex, q).r - 0.5;
		float n2 = texture(noise_tex, q * 2.1 + vec2(0.3, TIME)).r - 0.5;
		float s = 1.0 - uv.y;                       // 0 at the base (bottom of the quad), 1 at the tip
		uv.x = clamp(uv.x + (n1 * 0.4 + n2 * 0.2) * (0.2 + 0.8 * s), 0.0, 1.0);
		vec4 t = texture(atlas, vec2((3.0 + uv.x) * 0.25, 0.5 + uv.y * 0.5));
		inten = t.r;
		core = t.g;
	} else {
		vec4 t = texture(atlas, vec2((3.0 + uv.x) * 0.25, uv.y * 0.5));
		inten = t.r;
		core = t.g;
	}
	ALBEDO = (COLOR.rgb + vec3(1.0, 0.9, 0.7) * core * 0.8) * strength;   // unshaded: ALBEDO is the output
	ALPHA = clamp(inten * COLOR.a, 0.0, 1.0);
}
