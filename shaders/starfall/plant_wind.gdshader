shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
// Scanned ground plants (Poly Haven grass_medium_02, periwinkle_plant, fern_02 - CC0) as MultiMesh instances, swaying
// with the meadow wind (height above the clump's own root, in mesh space). For the periwinkles, only the petals (the
// blue / violet / white parts of the texture) give off a soft glow - leaves and stems stay dark and natural.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float alpha_cut = 0.4;
uniform vec3 tint : source_color = vec3(1.0);
uniform float root_y = 0.0;                    // mesh-space height of the clump's root
uniform float amp = 0.12;                      // metres of sway per metre of height
uniform vec2 wind_dir = vec2(0.82, 0.35);
uniform float petal_glow = 0.0;                // > 0: petals glow
uniform vec3 petal_glow_color : source_color = vec3(0.55, 0.62, 1.0);
uniform vec3 back_light : source_color = vec3(0.04, 0.06, 0.1);

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float hgt = max(VERTEX.y - root_y, 0.0);
	float gust = sin(TIME * 0.9 + dot(o.xz, wind_dir) * 0.22) * 0.55 + 0.45;
	float flutter = sin(TIME * 2.7 + o.x * 3.1 + o.z * 2.3 + VERTEX.y * 4.0) * 0.2;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (gust + flutter) * amp * hgt * hgt * 2.0;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb * tint;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	vec3 arm = texture(arm_tex, UV).rgb;
	AO = arm.r;
	ROUGHNESS = arm.g;
	BACKLIGHT = back_light;
	if (petal_glow > 0.0) {
		float petal = smoothstep(0.02, 0.12, a.b - a.g) + smoothstep(0.6, 0.85, min(a.r, min(a.g, a.b)));
		EMISSION = petal_glow_color * clamp(petal, 0.0, 1.0) * petal_glow;
	}
}
