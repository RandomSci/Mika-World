shader_type spatial;
// Distant scenery (mountains, landmark silhouettes): rock/grass by slope, snow by height,
// heavy aerial perspective toward `haze` so cheap geometry reads as kilometres away.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, shadows_disabled;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_col : source_color = vec3(0.42, 0.42, 0.44);
uniform vec3 green_col : source_color = vec3(0.2, 0.28, 0.16);
uniform vec3 snow_col : source_color = vec3(0.92, 0.94, 0.98);
uniform vec3 haze : source_color = vec3(0.62, 0.7, 0.8);
uniform float haze_start = 300.0;
uniform float haze_end = 3200.0;
uniform float max_haze = 0.85;
uniform float snow_line = 400.0;
uniform vec3 window_col : source_color = vec3(0.0);
uniform float window_glow = 0.0;
varying vec3 wpos;
varying vec3 wn;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float slope = clamp(wn.y, 0.0, 1.0);
	float n = texture(noise_tex, wpos.xz * 0.004).r;
	vec3 tex = texture(rock_tex, wpos.xz * 0.01 + wpos.y * 0.01).rgb;
	vec3 col = mix(rock_col, green_col, smoothstep(0.65, 0.85, slope + n * 0.2)) * (0.6 + tex * 0.8);
	col = mix(col, snow_col, smoothstep(snow_line - 60.0, snow_line + 40.0, wpos.y + n * 120.0) * smoothstep(0.35, 0.6, slope));
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(wpos - cam);
	float h = smoothstep(haze_start, haze_end, d) * max_haze;
	ALBEDO = mix(col, haze, h);
	EMISSION = haze * h * 0.35 + window_col * window_glow * COLOR.r;
	ROUGHNESS = 1.0;
}
