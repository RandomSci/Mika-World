shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
// Thin meadow grass (MultiMesh clumps of single blades). UV.y = 0 root .. 1 tip; UV.x = blade id (phase).
// Wind: a travelling gust field plus per-blade flutter. Tips catch the moon / rim light (backlight, a sheen) and the
// moon flowers' blue light near them (glow_map). Far blades shrink into the ground so nothing pops.
uniform vec3 base_color : source_color = vec3(0.004, 0.02, 0.03);
uniform vec3 tip_color : source_color = vec3(0.05, 0.16, 0.24);
uniform vec3 tip_light : source_color = vec3(0.35, 0.65, 1.0);
uniform sampler2D glow_map : filter_linear, repeat_disable;
uniform float glow_extent = 90.0;
uniform vec3 glow_color : source_color = vec3(0.15, 0.45, 1.0);
uniform vec2 wind_dir = vec2(0.82, 0.35);
uniform float wind_strength = 0.16;
uniform float fade_start = 30.0;
uniform float fade_end = 62.0;

varying float v_glow;
varying float v_shade;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float d = distance(o, CAMERA_POSITION_WORLD);
	float shrink = 1.0 - smoothstep(fade_start, fade_end, d);
	float ph = UV.x * 6.2831 + o.x * 1.7 + o.z * 1.3;
	float gust = sin(TIME * 0.9 + dot(o.xz, wind_dir) * 0.22) * 0.55 + 0.45;
	gust *= 0.7 + 0.3 * sin(TIME * 0.37 + o.z * 0.05);
	float flutter = sin(TIME * 3.1 + ph) * 0.18;
	float w = UV.y * UV.y;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (gust + flutter) * wind_strength * w;
	off.y = -length(off) * 0.35;
	VERTEX.y *= shrink;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * (off * shrink);
	NORMAL = normalize(mix(NORMAL, inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0), 0.45));
	v_glow = texture(glow_map, o.xz / (2.0 * glow_extent) + 0.5).r;
	v_shade = INSTANCE_CUSTOM.x;
}

void fragment() {
	float t = UV.y;
	ALBEDO = mix(base_color, tip_color, t * t) * (0.7 + 0.6 * v_shade);
	ROUGHNESS = 0.45;
	SPECULAR = 0.6;
	BACKLIGHT = tip_light * 0.55 * t * t;
	EMISSION = glow_color * v_glow * 0.16 * t;
}
