// Combat v3: the air burst at a contact - an open cone thrown off the impact along the blow, its surface streaked by
// noise running outward, eroding from the rim as `life` goes 0 -> 1, the grazing edges soft (no hard silhouette).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.92, 0.97, 1.0);
uniform vec3 edge : source_color = vec3(0.35, 0.65, 1.0);
uniform float energy = 2.5;
uniform float life = 0.0;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

void fragment() {
	float along = UV.y;                                   // 0 at the apex (the contact) .. 1 at the open rim
	float streak = texture(noise, vec2(UV.x * 6.0, along * 0.6 - life * 1.4)).r;
	float fine = texture(noise, vec2(UV.x * 17.0 + 0.3, along * 1.7 - life * 2.2)).r;
	float s = smoothstep(0.42, 0.78, streak * 0.65 + fine * 0.35);
	float rim = smoothstep(1.0, 0.45, along) * smoothstep(0.0, 0.12, along);
	float erode = smoothstep(life * 1.1 - 0.1, life * 1.1 + 0.15, 1.0 - along + streak * 0.35);
	float graze = pow(abs(dot(NORMAL, VIEW)), 0.6);
	float a = clamp(s * rim * erode * graze * (1.0 - life * 0.6), 0.0, 1.0);
	ALBEDO = mix(edge, core, 1.0 - along) * energy * a;
	ALPHA = a;
}
