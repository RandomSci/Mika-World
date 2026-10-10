shader_type spatial;
// Soft additive particle sprite. Brightness + colour come from the particle COLOR (fades with lifetime).
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float hdr_boost = 3.0;
uniform bool trail_mode = false;

void vertex() {
	if (!trail_mode) {
		// camera-facing billboard keeping particle scale
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	float fall;
	if (trail_mode) {
		fall = 1.0 - abs(UV.x - 0.5) * 2.0;
		fall = pow(fall, 1.5) * UV.y;
	} else {
		float r = length(UV - 0.5) * 2.0;
		fall = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
		fall += exp(-r * r * 30.0) * 1.5;
	}
	ALBEDO = COLOR.rgb * COLOR.a * fall * hdr_boost;
}
