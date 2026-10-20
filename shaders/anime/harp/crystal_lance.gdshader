shader_type spatial;
// The light-lance (ref v4 16.0 s): translucent crystal with engraved filigree lines, a white-hot rim where the
// light catches the faces (fresnel), an inner glow, and a forming wipe (form 0..1 along its length).
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled;
uniform vec3 body_color : source_color = vec3(0.35, 0.6, 1.0);
uniform vec3 line_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float intensity = 1.6;
uniform float form = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	// engraving: a filigree of curved lines along the blade (UV.y along the length)
	float u = UV.x * 6.28318 * 3.0;
	float v = UV.y * 40.0;
	float l1 = smoothstep(0.08, 0.0, abs(sin(v + sin(u) * 1.6) * 0.5));
	float l2 = smoothstep(0.05, 0.0, abs(sin(v * 0.5 - u * 0.5 + 1.3) * 0.5)) * 0.7;
	float lines = max(l1, l2) * step(0.12, UV.y) * step(UV.y, 0.92);
	float wipe = smoothstep(form, form - 0.04, 1.0 - UV.y);
	vec3 c = body_color * (0.5 + fres * 1.6) + line_color * lines * 1.8 + vec3(1.0) * pow(fres, 3.0) * 2.0;
	ALBEDO = c * intensity;
	ALPHA = clamp(0.35 + fres * 0.65 + lines * 0.5, 0.0, 1.0) * wipe;
}
