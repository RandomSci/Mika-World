shader_type spatial;
// Umbral Lance body: a dark, slowly churning interior (alpha-blended, so it reads as SHADOW, not light)
// with a hot gold rim from the view angle and gold veins crawling along its length.
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform vec3 shadow_color : source_color = vec3(0.06, 0.02, 0.12);
uniform vec3 rim_color : source_color = vec3(1.0, 0.76, 0.3);
uniform vec3 vein_color : source_color = vec3(0.65, 0.35, 1.0);
uniform float intensity = 1.0;
uniform float flow = 3.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float n = noise(vec2(UV.x * 6.0, UV.y * 18.0 - TIME * flow));
	float vein = smoothstep(0.62, 0.7, n) - smoothstep(0.7, 0.78, n);
	ALBEDO = shadow_color + rim_color * fres * 3.0 * intensity + vein_color * vein * 2.0 * intensity;
	ALPHA = clamp(0.82 + fres * 0.18, 0.0, 1.0) * clamp(intensity, 0.0, 1.0);
}
