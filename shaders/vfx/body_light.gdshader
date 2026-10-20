// Body of light (the real-time transformation, scripts/transform/transformation_sequence.gd): laid over every mesh of
// her avatar as material_overlay. `cover` 0 -> 1 turns her into a glowing silhouette - a white-hot body, the element's
// colour on her rim (fresnel) and a slow flow of light over her. `reveal_y` (a world height) dissolves the light away
// from the head down: above it the overlay is gone (her new outfit shows), at it a bright ragged seam.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0);
uniform vec3 body_color : source_color = vec3(0.72, 0.77, 1.0);
uniform vec3 rim_color : source_color = vec3(0.55, 0.62, 1.0);
uniform float glow = 2.2;
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform float reveal_y = 1000.0;         // world y: above it the light has dissolved away
uniform float seam = 0.12;               // the seam's height (m)
uniform sampler2D flow : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float fl = texture(flow, vec2(wpos.x * 0.6 + wpos.z * 0.4, wpos.y * 0.5 - TIME * 0.35)).r;
	vec3 col = mix(core_color, body_color, 0.35 + 0.35 * fl);
	col = mix(col, rim_color, fres);
	// the dissolve: a ragged line (noise on the height) moving down; a hot seam just under it
	float n = hash(floor(wpos.xz * 40.0) + floor(wpos.y * 40.0)) * 0.06 + fl * 0.05;
	float d = (reveal_y + n) - wpos.y;                  // > 0 below the line (still light)
	float keep = smoothstep(0.0, 0.02, d);
	float hot = 1.0 - smoothstep(0.0, seam, d);
	col = mix(col, core_color * 1.6, hot * keep);
	ALBEDO = col * glow * (1.0 + hot * 1.5);
	ALPHA = clamp(cover * keep, 0.0, 1.0);
}
