shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
// Moonbloom flower (MultiMesh): UV.x = part (0 stem, 0.5 core, 1 petal), UV.y = sway weight (0 root .. 1 head),
// COLOR.g = position along a petal. INSTANCE_CUSTOM = (phase, brightness, hue, 0).
uniform vec3 petal_color : source_color = vec3(0.42, 0.62, 1.0);
uniform vec3 glow_a : source_color = vec3(0.22, 0.52, 1.0);
uniform vec3 glow_b : source_color = vec3(0.45, 0.42, 1.0);
uniform vec3 glow_c : source_color = vec3(0.2, 0.85, 1.0);
uniform float glow_energy = 4.5;
uniform vec3 stem_color : source_color = vec3(0.04, 0.10, 0.08);
uniform vec2 wind_dir = vec2(0.82, 0.35);
uniform float wind_strength = 0.05;

varying float v_part;
varying float v_pulse;
varying float v_bright;
varying vec3 v_glow;

void vertex() {
	v_part = UV.x;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float gust = sin(TIME * 1.1 + dot(o.xz, vec2(0.17, 0.11))) * 0.65 + sin(TIME * 2.6 + o.x * 0.7 + ph) * 0.3;
	float w = UV.y * UV.y;
	vec3 off_w = vec3(wind_dir.x, 0.0, wind_dir.y) * gust * wind_strength * w;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off_w;
	v_pulse = 0.78 + 0.22 * sin(TIME * 0.55 + ph);
	v_bright = INSTANCE_CUSTOM.y;
	float hue = INSTANCE_CUSTOM.z;
	v_glow = hue < 0.5 ? mix(glow_a, glow_b, hue * 2.0) : mix(glow_a, glow_c, hue * 2.0 - 1.0);
}

void fragment() {
	ROUGHNESS = 0.55;
	if (v_part > 0.75) {
		float g = COLOR.g;
		ALBEDO = petal_color * (0.45 + 0.55 * g);
		EMISSION = v_glow * glow_energy * v_pulse * v_bright * (0.3 + 0.7 * g);
		BACKLIGHT = v_glow * 0.4;
	} else if (v_part > 0.25) {
		ALBEDO = vec3(0.85, 0.95, 1.0);
		EMISSION = mix(v_glow, vec3(0.85, 0.95, 1.0), 0.6) * glow_energy * 1.7 * v_pulse * v_bright;
	} else {
		ALBEDO = stem_color;
		EMISSION = v_glow * 0.06 * UV.y;
		ROUGHNESS = 0.8;
	}
}
