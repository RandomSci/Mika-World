// Shields and auras (scripts/vfx/spell_fx.gd): a shell that glows at its rim (fresnel) in the element's colours,
// with energy flowing over it; additive, per-instance alpha so one material serves every caster of an element.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0);
uniform vec3 body_color : source_color = vec3(0.72, 0.77, 1.0);
uniform vec3 edge_color : source_color = vec3(0.12, 0.16, 0.47);
uniform float glow = 2.0;
uniform float rim_power = 2.6;
uniform sampler2D flow_mask : source_color, repeat_enable;
uniform vec2 flow_speed = vec2(0.05, 0.35);
instance uniform float alpha : hint_range(0.0, 1.0) = 1.0;
instance uniform float boost = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float flow = texture(flow_mask, UV * vec2(3.0, 2.0) + flow_speed * TIME).r;
	float i = clamp(rim * 0.9 + flow * rim * 0.6 + flow * 0.08, 0.0, 1.0);
	vec3 col = mix(edge_color, body_color, smoothstep(0.0, 0.5, i));
	col = mix(col, core_color, smoothstep(0.7, 1.0, i));
	ALBEDO = col * glow * boost * i;
	ALPHA = clamp(i * alpha, 0.0, 1.0);
}
