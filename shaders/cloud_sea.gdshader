shader_type spatial;
// Sea of clouds seen from above: layered drifting noise with sun-side brightening and soft fade at distance.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 lit_col : source_color = vec3(1.0, 0.92, 0.84);
uniform vec3 shade_col : source_color = vec3(0.45, 0.52, 0.66);
uniform vec2 sun_dir = vec2(0.6, -0.8);
uniform float scale = 0.0012;
uniform float opacity = 0.95;
uniform float radius = 3000.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * scale;
	float a = texture(noise_tex, p + TIME * 0.002).r;
	float b = texture(noise_tex, p * 2.7 - TIME * 0.003 + 0.4).r;
	float c = texture(noise_tex, p * 7.0 + TIME * 0.004 + 0.1).r;
	float dens = a * 0.6 + b * 0.3 + c * 0.15;
	float hx = texture(noise_tex, p + sun_dir * 0.01).r - a;
	vec3 col = mix(shade_col, lit_col, clamp(0.55 + dens * 0.6 - hx * 6.0, 0.0, 1.0));
	float dist = length(wpos.xz - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz);
	ALBEDO = col;
	ALPHA = opacity * smoothstep(0.32, 0.55, dens) * (1.0 - smoothstep(radius * 0.6, radius, dist));
}
