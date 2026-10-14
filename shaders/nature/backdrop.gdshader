// The painted mountain backdrop (WoodsHero.backdrop): unshaded, drawn behind the world, its own aerial haze
// already painted in; follows the camera horizontally so it is always "at the horizon" (no parallax: 1.5 km+).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float brightness = 1.0;
uniform vec3 night_tint = vec3(1.0);

void vertex() {
	// keep the cylinder centred on the camera (x,z): an infinitely distant painting
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	VERTEX.xz += (inverse(MODEL_MATRIX) * vec4(cam, 1.0)).xz;
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb * brightness * night_tint;
	ALPHA = c.a;
}
