shader_type spatial;
// Transformation aura: a soft rising column of light around the mage (a cylinder without caps).
// Bright at the base, streaked upward, open at the top; `rise` grows it from the ground up.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.85, 0.95);
uniform vec3 accent : source_color = vec3(0.7, 0.85, 1.0);
uniform float intensity = 1.0;
uniform float rise : hint_range(0.0, 1.0) = 1.0;
uniform float speed = 0.9;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float h = 1.0 - UV.y;                       // 0 at the base, 1 at the top
	float cols = 48.0;
	float c = floor(UV.x * cols);
	float streak = smoothstep(0.35, 0.0, abs(fract(UV.x * cols) - 0.5)) * (0.4 + 0.6 * hash(c));
	float flowv = fract(h * 2.0 - TIME * speed * (0.6 + hash(c + 7.0)));
	float pulse = smoothstep(0.0, 0.15, flowv) * smoothstep(1.0, 0.4, flowv);
	float body = exp(-h * 2.2) * 0.7 + streak * pulse * (1.0 - h);
	float grown = smoothstep(rise + 0.05, rise - 0.15, h);
	ALBEDO = mix(color, accent, h) * body * grown * intensity;
}
