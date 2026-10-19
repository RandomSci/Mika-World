// Magical mist round her feet during the build-up, after Profesor Shader's "magical mist" (MIT,
// https://github.com/profesorshader/shader-magical-mist): density = scrolling noise x a vertical gradient, emitted in
// the element's colour - here on camera-facing quads (the stream profile has no volumetric fog), with twinkling
// sparkles in it. Additive.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 mist_color : source_color = vec3(0.72, 0.77, 1.0);
uniform vec3 sparkle_color : source_color = vec3(1.0);
uniform float strength = 0.6;
uniform float scroll = 0.08;
instance uniform float alpha : hint_range(0.0, 1.0) = 1.0;
instance uniform float seed = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float n1 = texture(noise_tex, uv * 0.9 + vec2(seed, TIME * scroll)).r;
	float n2 = texture(noise_tex, uv * 1.7 + vec2(-TIME * scroll * 0.7, seed * 2.0)).r;
	float dens = n1 * n2 * 1.8;
	float grad = smoothstep(1.0, 0.35, 1.0 - uv.y) * smoothstep(0.0, 0.25, 1.0 - uv.y);   // thick low, thin high
	float radial = 1.0 - smoothstep(0.25, 0.5, length(uv - vec2(0.5)));
	float m = dens * grad * radial * strength;
	// sparkles: a few cells blink on and off
	vec2 cell = floor(uv * 26.0);
	float h = hash(cell + seed);
	float tw = step(0.965, h) * pow(max(0.0, sin(TIME * (2.0 + h * 5.0) + h * 40.0)), 8.0);
	float dotm = 1.0 - smoothstep(0.0, 0.35, length(fract(uv * 26.0) - 0.5));
	vec3 col = mist_color * m + sparkle_color * tw * dotm * radial * 2.5;
	ALBEDO = col;
	ALPHA = clamp((m + tw * dotm) * alpha, 0.0, 1.0);
}
