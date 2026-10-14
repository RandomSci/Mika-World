// AFTERIMAGE: a ghost of a body's pose left behind by a very fast dash (anime "zanzo"). Unshaded, additive, bright at
// the silhouette (fresnel), faint inside, fading with `fade` (1 -> 0) and thinning into streaks along the dash.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.25, 0.6, 1.0);
uniform float fade = 1.0;
uniform float energy = 1.6;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float streak = 0.75 + 0.25 * sin(VERTEX.y * 90.0 + fade * 9.0);
	float a = (0.12 + 0.88 * fres) * fade * fade * streak;
	ALBEDO = color.rgb * energy * a;
}
