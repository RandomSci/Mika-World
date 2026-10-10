shader_type spatial;
// Procedural flame sprite (camera-facing): layered scrolling noise shaped into a teardrop, hot core.
// `heat` 0..2 brightens/enlarges; `hue_shift` 0 = natural fire, 1 = arcane blue flame.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float heat = 1.0;
uniform float hue_shift = 0.0;
uniform float intensity = 1.0;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV;
	uv.y = 1.0 - uv.y;
	float n1 = texture(noise_tex, vec2(uv.x * 1.3, uv.y * 0.9 - TIME * 1.4)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 2.7 + 0.3, uv.y * 1.8 - TIME * 2.3)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float x = (uv.x - 0.5) * 2.0;
	float shape = 1.0 - smoothstep(0.0, 1.0, abs(x) / max(0.08, (1.0 - uv.y) * 0.85 + 0.05));
	shape *= smoothstep(0.0, 0.12, uv.y) * smoothstep(1.0, 0.35, uv.y + (n - 0.5) * 0.5);
	float f = clamp(shape * (0.55 + n * 0.9) * (0.7 + 0.3 * heat), 0.0, 2.0);
	vec3 fire = mix(vec3(1.0, 0.25, 0.03), vec3(1.0, 0.8, 0.35), smoothstep(0.35, 1.0, f));
	fire = mix(fire, vec3(1.0, 0.97, 0.85), smoothstep(1.0, 1.5, f));
	vec3 arcane = mix(vec3(0.25, 0.35, 1.0), vec3(0.75, 0.9, 1.0), smoothstep(0.4, 1.2, f));
	ALBEDO = mix(fire, arcane, hue_shift) * f * intensity * (0.8 + 0.4 * heat);
}
