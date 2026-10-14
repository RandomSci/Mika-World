// A single feather for particles (the transformation veil, the reform's falling sparks): the contour cell of
// the feather atlas, tinted by the particle colour, glowing at the tip.
shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;

void vertex() {
	// face the camera around the particle's own axis (billboard, keeping the per-particle rotation)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// the contour cell is the lower-right quarter of the atlas (Godot UV: v grows downward)
	vec2 uv = vec2(0.5 + UV.x * 0.5, 0.5 + UV.y * 0.5);
	vec4 t = texture(atlas, uv);
	ALPHA = t.a * COLOR.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	// unshaded: ALBEDO is the whole output (EMISSION is ignored in unshaded mode)
	ALBEDO = COLOR.rgb * (0.35 + 0.65 * t.r) + COLOR.rgb * (0.25 + 1.3 * t.b * t.b) * (0.4 + 0.6 * COLOR.a);
}
