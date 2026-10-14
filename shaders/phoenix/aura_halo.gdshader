// A soft halo of firelight behind Oriel (and behind her charging nova): a camera-facing quad pushed away from
// the camera so it reads as light around her silhouette, not a fog over her. Additive; pulses slowly.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.52, 0.16);
uniform vec3 core_color : source_color = vec3(1.0, 0.85, 0.55);
uniform float strength = 0.35;
uniform float push = 1.6;
uniform float rays = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;            // 0 none .. 1 a starburst of light rays (the nova at full charge)

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mat4 sc = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * sc;
	VERTEX.z -= push / max(length(MODEL_MATRIX[2].xyz), 0.001);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float halo = exp(-r * r * 3.2) * (1.0 - smoothstep(0.75, 1.0, r));
	float core = exp(-r * r * 18.0);
	float ang = atan(p.y, p.x);
	float ray = pow(max(0.0, sin(ang * 9.0 + TIME * 0.3)) * max(0.0, sin(ang * 5.0 - TIME * 0.2 + 1.3)), 6.0) * exp(-r * 2.2) * rays;
	float pulse = 0.85 + 0.15 * sin(TIME * 1.6);
	ALBEDO = (color * halo + core_color * (core + ray * 1.5)) * strength * pulse;   // unshaded: ALBEDO is the output
	// soft where it meets her (or anything): a camera-facing card must never draw a hard line through a wing
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float soft = clamp(((-vp.z / vp.w) - (-VERTEX.z)) / 1.2, 0.0, 1.0);
	ALBEDO *= soft;
	ALPHA = clamp(halo + core + ray, 0.0, 1.0) * soft;
}
