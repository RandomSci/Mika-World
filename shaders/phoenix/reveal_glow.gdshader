// The light-body of Oriel's transformation (a pass on top of every humanoid surface): at `glow` 1 she is a
// silhouette of flowing white-gold light - the pass covers her completely (mix, not add), so no detail of the
// body shows, only a rim of fire; as each part of her is made the light cools away and the garment shows.
// Only the parts already made glow (the same reveal mask as the garments); the burning seam is brighter still.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

#include "res://shaders/phoenix/reveal_mask.gdshaderinc"

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float glow = 0.0;
uniform vec3 glow_col : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 rim_col : source_color = vec3(1.0, 0.45, 0.12);

void vertex() {
	rv_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * 0.004;
}

void fragment() {
	float e = 0.0;
	if (rv_on > 0.5 && rv_eval(rv_wp, e) < 0.0) {
		discard;
	}
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	// light flowing up through her
	float flow = texture(noise_tex, vec2(rv_wp.x * 0.9 + rv_wp.z * 0.7, rv_wp.y * 0.8 - TIME * 0.6)).r;
	float flow2 = texture(noise_tex, vec2(rv_wp.z * 1.7 - rv_wp.x * 0.4, rv_wp.y * 1.9 - TIME * 1.1)).r;
	vec3 c = glow_col * (2.2 + 0.9 * flow + 0.5 * flow2) + rim_col * fres * 3.0;
	ALBEDO = c * max(glow, 0.0001) + rv_edge_col * e * 3.0;   // unshaded: ALBEDO is the output (HDR)
	ALPHA = clamp(glow * (0.94 + 0.06 * fres) + e * 0.8, 0.0, 1.0);
}
