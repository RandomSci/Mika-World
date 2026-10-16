shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Faraway village windows (MultiMesh of camera-facing dots): warm, steady with a slow candle flicker, seen through
// the valley mist (scene fog still applies).
uniform vec3 color : source_color = vec3(1.0, 0.68, 0.32);
uniform float energy = 3.5;

varying float v_f;

void vertex() {
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	float id = float(INSTANCE_ID);
	v_f = 0.8 + 0.2 * sin(TIME * (0.7 + fract(id * 0.618) * 1.3) + id * 2.4) * sin(TIME * 3.1 + id);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = dot(p, p);
	ALBEDO = color * energy * v_f * (exp(-r * 10.0) + exp(-r * 2.5) * 0.15);
}
