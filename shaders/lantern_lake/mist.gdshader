shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Low mist lying on the lake: a few large horizontal sheets just above the water, slow drifting noise, thicker far
// away (seen edge-on) and gone near the lens, softened wherever it meets the pier, the reeds or the shore.

uniform vec3 color : source_color = vec3(0.32, 0.29, 0.5);
uniform float density = 0.35;
uniform float near_fade = 12.0;
uniform float layer_seed = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 v_world;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = p * 2.07 + vec2(5.3, 1.7);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz * 0.035 + vec2(TIME * 0.006, TIME * 0.002) + layer_seed * 3.1;
	float n = fbm(p) * 0.7 + fbm(p * 3.1 - TIME * 0.004) * 0.3;
	float m = smoothstep(0.35, 0.8, n);
	float d = length(v_world - CAMERA_POSITION_WORLD);
	float edge_on = 1.0 - abs(normalize(v_world - CAMERA_POSITION_WORLD).y);
	float a = m * density * smoothstep(near_fade * 0.4, near_fade, d) * (0.35 + 0.65 * edge_on * edge_on);
	// soft where the sheet cuts through something
	float zd = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zd, 1.0);
	float scene_d = -vp.z / vp.w;
	float soft = clamp((scene_d + VERTEX.z) / 1.2, 0.0, 1.0);
	ALBEDO = color;
	ALPHA = clamp(a * soft, 0.0, 0.9);
}
