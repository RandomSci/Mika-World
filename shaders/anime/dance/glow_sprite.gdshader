shader_type spatial;
// A camera-facing particle sprite that really shines (HDR, additive, so the bloom picks it up): motes, sparkles,
// star bursts, splash droplets. Texture: a Brackeys CC0 particle (its alpha is the shape).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float energy = 3.0;

void vertex() {
	// billboard each particle, keeping its own scale
	mat4 bb = mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

void fragment() {
	vec4 t = texture(tex, UV);
	float a = max(t.a * dot(t.rgb, vec3(0.333)), 0.0);
	ALBEDO = color.rgb * COLOR.rgb * a * energy * COLOR.a;
}
