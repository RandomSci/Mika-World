shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;
// The lake basin and its banks (Poly Haven photo textures, CC0): dark wet mud at the waterline, grass on the banks,
// forest floor under the pines. Anything under the water is clipped away for the mirrored reflection camera
// (it sits below the water: CAMERA_POSITION_WORLD.y < water_y), so the lake bed never hides the reflection.

uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float water_y = 0.0;
uniform float brightness = 0.55;
uniform float forest_from = 6.0;      // metres above the water where the forest floor takes over

varying vec3 v_world;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (CAMERA_POSITION_WORLD.y < water_y && v_world.y < water_y + 0.02) {
		discard;
	}
	vec2 uv = v_world.xz / 2.2;
	float n = vnoise(v_world.xz * 0.15) * 0.6 + vnoise(v_world.xz * 0.6) * 0.4;
	float above = v_world.y - water_y;
	float mud = 1.0 - smoothstep(0.15, 0.75 + n * 0.5, above);
	float forest = smoothstep(forest_from - 2.0, forest_from + 2.0, above + (n - 0.5) * 4.0);
	vec3 a = texture(grass_alb, uv).rgb;
	vec3 an = texture(grass_nor, uv).rgb;
	vec3 fa = texture(floor_alb, uv * 0.8).rgb;
	vec3 fn = texture(floor_nor, uv * 0.8).rgb;
	a = mix(a, fa, forest);
	an = mix(an, fn, forest);
	vec3 ma = texture(mud_alb, uv * 0.7).rgb;
	vec3 mn = texture(mud_nor, uv * 0.7).rgb;
	a = mix(a, ma * 0.55, mud);
	an = mix(an, mn, mud);
	ALBEDO = a * brightness * (0.85 + 0.3 * n);
	NORMAL_MAP = an;
	ROUGHNESS = mix(0.95, 0.55, mud * (1.0 - smoothstep(0.0, 0.3, above)));
	SPECULAR = 0.2;
}
