// One shader for every spell shape (scripts/vfx/spell_fx.gd): a greyscale mask (assets/vfx/masks) is mapped through
// the element's three colours - edge (dark falloff) -> body (the element) -> core (white-hot) - additive, so bloom
// catches the core. Recolouring an effect for another element = new colours, never new effect work.
// progress drives a soft dissolve-out; spin turns the mask (magic circles, shields); billboard faces the camera.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D mask : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 core_color : source_color = vec3(1.0);
uniform vec3 body_color : source_color = vec3(0.72, 0.77, 1.0);
uniform vec3 edge_color : source_color = vec3(0.12, 0.16, 0.47);
uniform float glow = 2.4;
instance uniform float alpha : hint_range(0.0, 1.0) = 1.0;       // per instance: one shared material per element + mask
instance uniform float progress : hint_range(0.0, 1.0) = 0.0;    // 0 = full, 1 = dissolved away
instance uniform float boost = 1.0;
uniform float spin = 0.0;                                // radians / s
uniform float flicker = 0.0;
uniform bool billboard = false;
uniform vec2 uv_scroll = vec2(0.0);

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float a = spin * TIME;
	uv = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * uv + 0.5 + uv_scroll * TIME;
	float i = texture(mask, uv).r;
	// dissolve: a noisy threshold that eats the faint parts first, the core last
	float n = hash(floor(UV * 48.0));
	float keep = smoothstep(progress - 0.08, progress + 0.08, i * 0.85 + n * 0.15);
	vec3 col = mix(edge_color, body_color, smoothstep(0.0, 0.45, i));
	col = mix(col, core_color, smoothstep(0.62, 1.0, i));
	float fl = 1.0 + flicker * (sin(TIME * 31.0) * 0.5 + sin(TIME * 17.0) * 0.5);
	ALBEDO = col * glow * boost * fl * i;
	ALPHA = clamp(i * alpha * keep, 0.0, 1.0);
}
