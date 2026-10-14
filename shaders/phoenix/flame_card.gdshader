// Oriel's flame tongues (v3): additive cards that trail from every flight feather, tail plume and crest plume
// (atlas cell (3,0)). The tongue is re-drawn every frame from the atlas through two scrolling noise
// distortions, so it licks, splits and rises like fire instead of hanging as a picture of fire. Seen edge-on
// a card fades out (no hard lines). UV2.x = position along the card + seed, UV2.y = strength.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float strength = 1.0;
uniform float heat = 0.0;
uniform float dissolve = 0.0;
uniform vec3 dissolve_origin = vec3(0.0, 1.6, 0.0);
uniform float dissolve_radius = 6.0;
uniform vec3 hot_col : source_color = vec3(1.0, 0.86, 0.5);

varying float s_along;
varying float seed;
varying float gw;
varying vec3 vcol;
varying vec3 world_pos;

void vertex() {
	s_along = fract(UV2.x);
	seed = floor(UV2.x) / 16.0;
	gw = UV2.y;
	vcol = COLOR.rgb;
	float w = sin(TIME * (4.5 + seed * 3.0) + seed * 50.0 + s_along * 5.0) * 0.07 * s_along * s_along;
	VERTEX += NORMAL * w;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = clamp(UV.x * 4.0 - 3.0, 0.0, 1.0);
	float s = s_along;
	vec2 q = vec2(u * 0.6 + seed * 3.1, s * 1.4 - TIME * (1.3 + 0.6 * seed));
	float n1 = texture(noise_tex, q).r - 0.5;
	float n2 = texture(noise_tex, q * 2.3 + vec2(0.37, -TIME * 0.9)).r - 0.5;
	float uu = clamp(u + (n1 * 0.5 + n2 * 0.25) * (0.15 + 0.85 * s), 0.0, 1.0);
	float ss = clamp(s + n2 * 0.12 * s - 0.04, 0.0, 1.0);
	vec4 t = texture(atlas, vec2((3.0 + uu) * 0.25, 1.0 - ss * 0.5));
	float inten = t.r;
	float core = t.g;
	float facing = smoothstep(0.04, 0.4, abs(dot(normalize(NORMAL), normalize(VIEW))));
	float fade = 1.0;
	if (dissolve > 0.0) {
		float d = clamp(distance(world_pos, dissolve_origin) / dissolve_radius, 0.0, 1.0);
		fade = clamp((1.0 - dissolve * 1.1) - d * 0.6 + 0.4, 0.0, 1.0);
	}
	// saturated fire: scarlet at the licking ends, orange in the body, a small gold-white core at the root
	vec3 c = mix(vec3(1.0, 0.42, 0.04), vec3(0.95, 0.1, 0.02), smoothstep(0.3, 0.95, s));
	c = mix(c, hot_col, core * core * 0.6);
	// unshaded: ALBEDO is the output (HDR); EMISSION is ignored in unshaded mode
	ALBEDO = c * (0.55 + 1.1 * core) * strength * gw * (1.0 + 1.5 * heat);
	ALPHA = clamp(inten * facing * fade * 0.85, 0.0, 1.0);
}
