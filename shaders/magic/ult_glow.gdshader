// The glow of an ultimate's giant shapes (2026-10-20): the ring of conjured blades, the ghost weapon, the ghost slash.
// Added light: a hot core along the mesh's centre line, its edges in the girl's colour by fresnel, drawn along the
// mesh's length as `reveal` goes 0 to 1 (UV.y along it), out by `fade`.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 col : source_color = vec3(1.0, 0.55, 0.78);
uniform vec3 hi : source_color = vec3(1.0, 0.95, 0.97);
uniform float intensity = 2.0;
uniform float reveal = 1.0;
uniform float fade = 1.0;
uniform float along_tail = 0.0;           // > 0: the part behind the leading edge fades over this length (a slash)

void fragment() {
	float fr = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(fr, 1.6);
	float core = pow(1.0 - fr, 3.0);
	float y = UV.y;
	float shown = step(y, reveal);
	float tail = along_tail > 0.0 ? smoothstep(reveal - along_tail, reveal, y) : 1.0;
	float lead = smoothstep(0.08, 0.0, abs(y - reveal)) * step(reveal, 0.999);
	vec3 c = mix(col * rim * 1.4, hi, core * 0.7) + hi * lead * 2.0;
	// (a shape right at the lens fades out: a blade passing the close-up must not fill the frame)
	float near_k = smoothstep(0.9, 2.2, length(VERTEX));
	ALBEDO = c * intensity * shown * tail * fade * near_k;
}
