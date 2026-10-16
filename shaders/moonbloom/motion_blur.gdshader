shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
// Camera motion blur: every pixel is reprojected into the previous frame's camera (depth -> world -> prev view) and
// the colour is gathered along that screen-space path. Slight (shutter < 1), capped, drawn first among transparents.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform mat4 prev_view;
uniform float shutter = 0.5;
uniform float max_uv = 0.018;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float d = max(texture(depth_tex, SCREEN_UV).x, 1e-5);
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	vec4 w = INV_VIEW_MATRIX * vec4(v.xyz, 1.0);
	vec4 pc = PROJECTION_MATRIX * (prev_view * w);
	vec2 puv = pc.w > 0.0 ? (pc.xy / pc.w) * 0.5 + 0.5 : SCREEN_UV;
	vec2 vel = (SCREEN_UV - puv) * shutter;
	float len = length(vel);
	if (len > max_uv) {
		vel *= max_uv / len;
	}
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		acc += texture(screen_tex, SCREEN_UV + vel * (float(i) / 7.0 - 0.5)).rgb;
	}
	ALBEDO = acc / 8.0;
}
