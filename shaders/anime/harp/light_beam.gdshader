shader_type spatial;
// A string / slat / spoke of light (Starlit Harp, ref v4 0.6-2.0 s): a white-hot core across the width, a coloured
// glow around it (HDR, so the bloom adds the haze), a pluck flare that travels along it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 core_color : source_color = vec3(1.0);
uniform vec3 glow_color : source_color = vec3(0.43, 0.7, 1.0);
uniform float intensity = 2.5;
uniform float flare = 0.0;             // 0..1, a pluck
uniform float flare_pos = 0.5;         // along the string (UV.y)
uniform float fade_ends = 0.15;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;                       // 0 at the centre line
	float core = smoothstep(0.22, 0.0, x);
	float glow = pow(1.0 - x, 5.0);
	float ends = smoothstep(0.0, fade_ends, UV.y) * smoothstep(1.0, 1.0 - fade_ends, UV.y);
	float f = flare * exp(-pow((UV.y - flare_pos) * 6.0, 2.0)) * 3.0 + flare * 0.6;
	vec3 c = core_color * core * (intensity + f * 4.0) + glow_color * glow * (intensity * 0.6 + f * 2.0);
	ALBEDO = c * ends;
}
