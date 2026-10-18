shader_type spatial;
// The ring of radial light spokes round the orb and the slat fan round the harp (ref v4 1.5 / 7.0 s): many thin
// bars at one radius, each with its own length, brightness and a 24 fps shimmer; spins with `spin`.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 color : source_color = vec3(0.6, 0.85, 1.0);
uniform float intensity = 2.2;
uniform float count = 64.0;
uniform float inner = 0.62;
uniform float outer = 0.92;
uniform float bar_width = 0.25;        // of each cell
uniform float spin = 0.05;             // turns per second
uniform float seed = 1.0;
uniform float reveal = 1.0;            // 0..1 the spokes grow outward

float h(float x) { return fract(sin(x * 127.1 + seed * 31.7) * 43758.5453); }

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float a = fract(atan(p.y, p.x) / 6.28318 + 0.5 + TIME * spin);
	float cell = floor(a * count);
	float f = fract(a * count);
	float hv = h(cell);
	float len = mix(0.45, 1.0, hv) * reveal;
	float r0 = inner;
	float r1 = mix(inner, outer, len);
	float bar = smoothstep(bar_width, bar_width * 0.4, abs(f - 0.5) * 2.0) * step(r0, r) * smoothstep(r1, r1 - 0.02, r);
	float shimmer = 0.65 + 0.35 * step(0.4, h(cell + floor(TIME * 24.0)));
	float tip = smoothstep(r1 - 0.12, r1, r) * 1.5 + 0.6;
	ALBEDO = color * bar * intensity * shimmer * tip * mix(0.6, 1.0, hv);
}
