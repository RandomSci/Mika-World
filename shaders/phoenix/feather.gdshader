// Oriel's feathers (v3, visual pass 2). Colour is per-vertex (molten gold -> orange -> scarlet -> crimson /
// magenta tips; violet train); the 4x2 atlas carries R = luminance (barbs, shaft, engraving), G = shaft / metal
// mask, B = glow mask (flame tips, rims), A = silhouette (alpha scissor). UV2.x = position along the feather
// (fract) + a per-feather seed (floor / 16), UV2.y = how strongly this feather burns.
// She burns from within: each feather glows toward its end with a slow flicker, the silhouette carries a rim of
// fire, the outer third sways like a flame, and the very tips flicker in and out like flame licks.
// `metal` = 1 turns the gold-filigree cell metallic (her gorget, crown, marginal coverts). `dissolve` burns the
// plumage away from the far ends toward `dissolve_origin` with a white-gold edge (the transformation).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tint = 1.0;
uniform float glow = 1.0;            // overall fire strength
uniform float heat = 0.0;            // 0 calm .. 1 blazing (casting, transformation)
uniform float hurt = 0.0;
uniform float flutter = 0.0;         // flight: the feather ends ripple
uniform float flicker = 1.0;         // the flame licks at the tips
uniform float metal = 0.0;
uniform float dissolve = 0.0;        // 0 whole .. 1 gone
uniform vec3 dissolve_origin = vec3(0.0, 1.6, 0.0);
uniform float dissolve_radius = 6.0;
uniform float alpha_cut = 0.42;

varying vec3 world_pos;
varying float s_along;
varying float seed;
varying float gw;
varying vec3 vcol;

float hash3(vec3 p) {
	return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	s_along = fract(UV2.x);
	seed = floor(UV2.x) / 16.0;
	gw = UV2.y;
	vcol = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s3 = s_along * s_along * s_along;
	// a living flame: the outer third of every feather sways a little even at rest (more in flight)
	float sway = sin(TIME * (2.0 + seed * 1.8) + seed * 40.0 + wp.y * 1.3 + wp.x * 0.7);
	VERTEX += NORMAL * sway * (0.018 * flicker + 0.03 * flutter) * s3 * gw;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(atlas, UV);
	float lum = t.r;
	float shaft = t.g;
	float tipm = t.b;
	float a = t.a;
	float n = texture(noise_tex, vec2(seed * 7.3 + UV.x * 5.0, s_along * 2.2 - TIME * (0.45 + 0.5 * seed))).r;
	// flame licks: the ends of the burning feathers flicker in and out
	float lick = smoothstep(0.82, 1.0, s_along) * flicker * gw * (1.0 - metal);
	a *= 1.0 - lick * smoothstep(0.5, 0.85, n);
	float edge = 0.0;
	if (dissolve > 0.0) {
		float d = clamp(distance(world_pos, dissolve_origin) / dissolve_radius, 0.0, 1.0);
		float hn = hash3(world_pos * 28.0 + vec3(0.37));
		float v = d * 0.72 + hn * 0.28;
		float gone = 1.0 - dissolve * 1.08;
		if (v > gone) {
			a = 0.0;
		}
		edge = 1.0 - smoothstep(0.0, 0.09, gone - v);
	}
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 base = vcol * (0.06 + 0.42 * lum * lum * lum) * tint;  // dark plumage albedo: her colour is her own fire (below)
	base = mix(base, vec3(1.0, 0.95, 0.75), heat * tipm * 0.45);
	float m = metal * shaft;
	ALBEDO = mix(base, vcol * (0.5 + 0.65 * lum), m);
	METALLIC = m * 0.92;
	ROUGHNESS = mix(0.74 - 0.12 * shaft, 0.26 + 0.12 * (1.0 - lum), m);
	SPECULAR = mix(0.14, 0.5, m);          // feathers barely mirror the sky (that sheen turned her red to coral)
	BACKLIGHT = vcol * vec3(1.0, 0.55, 0.4) * (0.05 + 0.08 * lum) * (1.0 - m);   // a little light through the thin vanes
	// the fire within: strongest toward the feather's end, pulsing, brighter and whiter with heat
	float pulse = 0.72 + 0.28 * sin(TIME * 1.4 + seed * 30.0 + world_pos.y * 0.8);
	float fl = (0.55 + 0.45 * n) * pulse;
	// fire colour: the feather's own colour pushed toward red-orange (AgX turns bright pale colours to pastel,
	// so the fire stays saturated and moderate; only heat whitens it)
	// her fire: every feather glows from within in a SATURATED red-orange (independent of the sun, so she reads
	// as a bird of fire from every side; moderate, so AgX keeps it red instead of washing it to coral)
	float vl = dot(vcol, vec3(0.3, 0.59, 0.11));
	vec3 sat = clamp(vcol + (vcol - vec3(vl)) * 0.6, 0.0, 1.0);
	vec3 fire = sat * vec3(1.0, 0.55, 0.35);
	fire = mix(fire, vec3(1.0, 0.4, 0.04), tipm * 0.6);
	fire = mix(fire, vec3(1.0, 0.8, 0.45), heat * 0.5);
	vec3 em = fire * gw * glow * ((0.22 + 0.38 * s_along) * (0.6 + 0.4 * lum) + 0.75 * tipm * tipm * tipm * fl) * (1.0 + 2.2 * heat) * (1.0 - m);
	em += vcol * vec3(1.0, 0.7, 0.4) * m * tipm * 0.35 * glow;              // gold filigree catches the fire
	em += vec3(1.0, 0.92, 0.7) * edge * 3.0 * step(0.001, dissolve);
	em += vec3(1.0, 0.85, 0.6) * hurt * 1.2;
	EMISSION = em;
}
