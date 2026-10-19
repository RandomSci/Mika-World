// Combat v3: the trail a fist or a kick leaves along its own path (a ribbon swept by the forearm / shin, rebuilt every
// frame). UV.x = age along the ribbon (0 = now), UV.y = across it (0 = elbow / knee side, 1 = fist / foot side).
// Bright at the striking end and the newest edge, soft at the sides, eaten by scrolling noise as it ages - a shape,
// never a strip with hard edges.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.92, 0.97, 1.0);
uniform vec3 edge : source_color = vec3(0.35, 0.65, 1.0);
uniform float energy = 2.2;
uniform float fade = 1.0;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

void fragment() {
	float age = clamp(UV.x, 0.0, 1.0);
	float across = clamp(UV.y, 0.0, 1.0);
	float n = texture(noise, vec2(age * 1.4 - TIME * 2.2, across * 0.9)).r;
	float n2 = texture(noise, vec2(age * 3.1 + TIME * 0.7, across * 2.3 + 0.37)).r;
	float body = pow(1.0 - age, 2.2) * smoothstep(0.0, 0.7, across) * smoothstep(1.0, 0.82, across);
	float erode = smoothstep(age * 0.85 - 0.05, age * 0.85 + 0.3, n * 0.7 + n2 * 0.3);
	float a = clamp(body * erode * fade, 0.0, 1.0);
	vec3 c = mix(edge, core, smoothstep(0.6, 0.97, across) * (1.0 - age * 0.8));
	ALBEDO = c * energy * a;
	ALPHA = a;
}
