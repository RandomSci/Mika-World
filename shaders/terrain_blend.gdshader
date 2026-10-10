shader_type spatial;
// Forest-clearing terrain: three photogrammetry layers (meadow grass / leaf litter / stony path),
// height-aware blending, two-scale sampling to hide tiling, and macro colour variation.
// COLOR.r = path mask, COLOR.g = forest-floor mask (set per vertex by the terrain builder).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_height : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass2_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_height : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_height : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D breakup_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float grass_tiling = 0.33;
uniform float leaves_tiling = 0.4;
uniform float path_tiling = 0.42;
uniform vec3 grass_tint : source_color = vec3(0.92, 0.98, 0.86);
uniform vec3 leaves_tint : source_color = vec3(0.5, 0.56, 0.4);
uniform float blend_sharpness = 9.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec4 two_scale(sampler2D t, vec2 uv, float mixv) {
	// sample at two rotated scales to break visible repetition
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 0.37 + vec2(0.31, 0.77);
	return mix(texture(t, uv), texture(t, uv2), mixv);
}

void fragment() {
	vec2 xz = wpos.xz;
	float macro = texture(breakup_noise, xz * 0.012).r;
	float macro2 = texture(breakup_noise, xz * 0.05 + vec2(0.5)).r;
	float mixv = smoothstep(0.35, 0.65, macro2) * 0.45;

	vec2 guv = xz * grass_tiling, luv = xz * leaves_tiling, puv = xz * path_tiling;
	// coarse layer weights from vertex masks first; only sample layers that contribute
	float path_m = COLOR.r;
	float leaf_m = COLOR.g * (0.75 + macro * 0.5);
	float wg = (1.0 - path_m) * (1.0 - leaf_m);
	float wl = leaf_m * (1.0 - path_m);
	float wp = path_m;
	float g_h = wg > 0.001 ? texture(grass_height, guv).r : 0.0;
	float l_h = wl > 0.001 ? texture(leaves_height, luv).r : 0.0;
	float p_h = wp > 0.001 ? texture(path_height, puv).r : 0.0;
	vec3 hw = vec3(wg + g_h * 0.6, wl + l_h * 0.6, wp + p_h * 0.8) * step(vec3(0.001), vec3(wg, wl, wp));
	float mx = max(hw.x, max(hw.y, hw.z));
	hw = max(hw - mx + 1.0 / blend_sharpness, 0.0);
	hw /= (hw.x + hw.y + hw.z + 1e-5);

	vec3 alb = vec3(0.0);
	float rough = 0.0;
	vec3 n = vec3(0.0);
	if (hw.x > 0.001) {
		vec3 g_alb = mix(two_scale(grass_albedo, guv, mixv).rgb, texture(grass2_albedo, guv * 1.3).rgb, smoothstep(0.45, 0.75, macro)) * grass_tint;
		alb += g_alb * hw.x; rough += texture(grass_rough, guv).r * hw.x; n += texture(grass_normal, guv).xyz * hw.x;
	}
	if (hw.y > 0.001) {
		alb += two_scale(leaves_albedo, luv, mixv).rgb * leaves_tint * hw.y; rough += texture(leaves_rough, luv).r * hw.y; n += texture(leaves_normal, luv).xyz * hw.y;
	}
	if (hw.z > 0.001) {
		alb += two_scale(path_albedo, puv, mixv).rgb * hw.z; rough += texture(path_rough, puv).r * hw.z; n += texture(path_normal, puv).xyz * hw.z;
	}

	// macro colour variation: patches of drier / lusher ground
	alb *= mix(vec3(0.86, 0.9, 0.8), vec3(1.06, 1.04, 0.96), macro);
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.3, 1.0);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.2;
	SPECULAR = 0.35;
}
