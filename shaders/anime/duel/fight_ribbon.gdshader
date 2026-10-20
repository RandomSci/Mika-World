shader_type spatial;
// The duel's light ribbons (hand sweeps, projectile trails, crescent slashes): as the dance ribbon (white-hot core,
// coloured glow, a long fade to the tail; UV.x = 0 head -> 1 tail, UV.y across), clamped so a bad value can never put
// a NaN into the frame (a NaN pixel turns into a black block in the glow pass).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.75, 0.55, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float energy = 3.0;
uniform float fade_all = 1.0;

void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float across = clamp(abs(UV.y - 0.5) * 2.0, 0.0, 1.0);
	float fade = pow(max(1.0 - u, 0.0), 1.25) * smoothstep(0.0, 0.03, u + 0.01);
	float c = exp(-across * across * 38.0);
	float g = exp(-across * across * 4.5) * (1.0 - across);
	float k = clamp(fade_all, 0.0, 1.0);
	vec3 col = (core.rgb * c * 1.6 + color.rgb * g) * fade * clamp(energy, 0.0, 20.0) * k;
	ALBEDO = clamp(col, vec3(0.0), vec3(64.0));
}
