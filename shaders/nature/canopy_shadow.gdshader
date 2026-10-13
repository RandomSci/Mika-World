shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded, shadows_disabled;
// Shadow-only caster for tree crowns (Milestone K environment pass). The detailed crowns are thousands of
// alpha-tested leaf cards; rendering those again into the shadow map costs more than the whole colour pass on the
// stream machine's iGPU. Instead each tree casts its shadow from a 200-triangle crown blob whose surface is
// punched with noise holes, so the ground still receives dappled light. The blob is never drawn in colour.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float gaps : hint_range(0.0, 1.0) = 0.46;

void fragment() {
	float n = texture(noise_tex, UV * vec2(4.0, 2.5)).r;
	float n2 = texture(noise_tex, UV * vec2(11.0, 7.0) + 0.37).r;
	if (n * 0.65 + n2 * 0.35 < gaps) {
		discard;
	}
	ALBEDO = vec3(0.0);
}
