shader_type spatial;
// The hill's ground at night, from real photo-scanned textures (Poly Haven, CC0): leafy grass over the hill, the
// forest floor with fallen leaves round the tree's roots (blend by distance from the trunk + noise), two scales of the
// same texture against tiling. Its real colours; the night comes from the light and the grade.
uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaf_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaf_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 trunk = vec3(0.0);
uniform float litter_r = 7.0;
uniform float brightness = 0.75;

varying vec3 v_wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_wp.xz / 2.2;
	vec3 g = texture(grass_alb, uv).rgb * mix(0.75, 1.15, vnoise(v_wp.xz * 0.11));
	vec3 l = texture(leaf_alb, v_wp.xz / 1.6).rgb;
	float d = length(v_wp.xz - trunk.xz);
	float w = 1.0 - smoothstep(litter_r * 0.45, litter_r, d + (vnoise(v_wp.xz * 0.7) - 0.5) * 2.5);
	ALBEDO = mix(g, l, w) * brightness;
	NORMAL_MAP = mix(texture(grass_nor, uv).rgb, texture(leaf_nor, v_wp.xz / 1.6).rgb, w);
	ROUGHNESS = 0.92;
}
