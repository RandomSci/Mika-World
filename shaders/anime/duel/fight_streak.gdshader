shader_type spatial;
// (duel copy, clamped: never a NaN into the glow pass) A light streak (the finale's rays, splash droplets): a diamond-shaped glow line drawn along the particle's velocity
// (GPUParticles3D transform_align Y to velocity), white-hot core, coloured edges. HDR + additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform vec4 core : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float energy = 4.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float along = clamp(1.0 - abs(UV.y - 0.35) / 0.65, 0.0, 1.0);
	float w = exp(-x * x * 9.0);
	float c = exp(-x * x * 70.0);
	ALBEDO = clamp((color.rgb * w + core.rgb * c * 1.3) * pow(max(along, 0.0), 1.5) * energy * COLOR.rgb * COLOR.a, vec3(0.0), vec3(64.0));
}
