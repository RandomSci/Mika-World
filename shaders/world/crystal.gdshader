// CRYSTAL (Crystal Caverns): a faceted mineral crystal, not a glowing toy. What is behind it shows through,
// bent by its facets (screen refraction along the facet normal) and tinted by its colour; light gathers inside
// and leaks out at the thin edges and the tip (an inner glow strongest where the view grazes the facets);
// sharp, bright specular glints on the flat faces; milky inclusions near the base.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec4 core : source_color = vec4(0.6, 0.95, 1.0, 1.0);
uniform float glow = 1.6;
uniform float refraction = 0.05;
uniform float milk = 0.35;
varying float v_h;              // 0 at the base .. 1 at the tip (from vertex colour R)
varying vec3 v_wn;              // world normal (flat per facet: the mesh is faceted)

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	v_h = COLOR.r;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec2 off = NORMAL.xy * refraction * (0.4 + 0.6 * (1.0 - fres));
	vec3 behind = textureLod(screen_tex, SCREEN_UV - off, 1.5).rgb;
	vec3 seen = behind * tint.rgb * 0.85;
	// each facet holds the light differently (a cut stone, not a lamp): a stable per-facet level
	float facet = 0.55 + 0.75 * hash3(floor(v_wn * 6.0 + 0.5));
	// light gathers toward the tip and leaks at the grazing edges; the body between stays deep and saturated
	float inner = 0.1 + 0.55 * pow(v_h, 1.8) + 0.85 * fres;
	vec3 milky = mix(tint.rgb, vec3(0.9, 0.95, 1.0), 0.5) * milk * (1.0 - v_h) * 0.35;
	ALBEDO = seen * 0.5 + milky;
	EMISSION = core.rgb * glow * inner * facet + seen * 0.25;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ALPHA = 0.95;
}
