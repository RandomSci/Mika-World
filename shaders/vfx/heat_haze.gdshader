// Heat haze / shock refraction (the cinematic pass): the scene behind is displaced through scrolling noise, a
// shimmer over fire (mode 0, a camera-facing disc) or an expanding ring of shocked air (mode 1, `ring` 0..1 is
// the ring's radius as a fraction of the card). Strength fades it; it adds no colour of its own.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform int mode = 0;
uniform float rise = 0.6;
instance uniform float strength = 0.0;
instance uniform float ring = 0.5;

void vertex() {
	mat4 bb = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 off;
	float w;
	if (mode == 0) {
		vec2 q = UV * 2.3 + vec2(0.0, -TIME * rise);
		off = vec2(texture(noise_tex, q).r - 0.5, texture(noise_tex, q * 1.7 + 0.37).r - 0.5);
		w = (1.0 - smoothstep(0.35, 1.0, r));
	} else {
		float band = 1.0 - smoothstep(0.0, 0.16, abs(r - ring));
		off = (p / max(r, 0.001)) * band * 0.6;
		w = band * (1.0 - smoothstep(0.85, 1.0, r));
	}
	// fade where the card meets geometry (the ground cuts the ring card: no straight seam)
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	w *= clamp(((-vp.z / vp.w) - (-VERTEX.z)) / 3.0, 0.0, 1.0);
	vec2 uv = SCREEN_UV + off * strength * 0.035 * w;
	ALBEDO = textureLod(screen_tex, uv, 0.0).rgb;
	ALPHA = clamp(w * strength * 3.0, 0.0, 1.0);
}
