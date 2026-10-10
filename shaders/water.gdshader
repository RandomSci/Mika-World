shader_type spatial;
// Natural/cave water: two scrolling noise normal layers, fresnel tint, depth-based colour and soft shore fade.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
uniform vec3 shallow : source_color = vec3(0.18, 0.32, 0.30);
uniform vec3 deep : source_color = vec3(0.02, 0.06, 0.08);
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow = 0.0;
uniform vec2 flow = vec2(0.02, 0.05);
uniform float wave_scale = 0.08;
uniform float clarity = 2.5;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec3 nrm_from(vec2 uv) {
	float e = 0.004;
	float h = texture(noise_tex, uv).r;
	return vec3(h - texture(noise_tex, uv + vec2(e, 0.0)).r, h - texture(noise_tex, uv + vec2(0.0, e)).r, 0.02);
}
void fragment() {
	vec2 uv1 = wpos.xz * wave_scale + TIME * flow;
	vec2 uv2 = wpos.xz * wave_scale * 2.3 - TIME * flow.yx * 1.3;
	vec3 n = normalize(nrm_from(uv1) + nrm_from(uv2) * 0.7);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	float scene_depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	vpos.xyz /= vpos.w;
	float thickness = clamp(VERTEX.z - vpos.z, 0.0, 50.0);
	float d = 1.0 - exp(-thickness / clarity);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow, deep, d);
	ALPHA = clamp(0.35 + d * 0.65 + fres * 0.3, 0.0, 0.97) * smoothstep(0.0, 0.15, thickness);
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
	EMISSION = glow_color * glow * (0.4 + 0.6 * (1.0 - d));
}
