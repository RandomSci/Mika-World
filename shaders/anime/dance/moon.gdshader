shader_type spatial;
// The full moon over the lake (a camera-facing disc far out in the sky): pale silver with soft grey maria and a
// gentle limb darkening, a soft halo round it. Bright enough for the bloom to give it a glow; mirrored in the lake.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 disc_color : source_color = vec4(0.93, 0.95, 1.0, 1.0);
uniform vec4 halo_color : source_color = vec4(0.55, 0.68, 1.0, 1.0);
uniform float energy = 1.7;
uniform float disc = 0.34;                 // disc radius in quad UV units (0..1 = centre..edge)

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { s += vn(p) * a; p = p * 2.07 + 3.1; a *= 0.5; }
	return s;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float inside = smoothstep(disc, disc - 0.012, r);
	vec2 q = p / disc;
	float limb = sqrt(max(1.0 - dot(q, q), 0.0));
	float maria = smoothstep(0.48, 0.66, fbm(q * 2.3 + vec2(4.0, 1.0)));
	float crat = smoothstep(0.62, 0.8, fbm(q * 7.0 + 11.0)) * 0.25;
	vec3 moon = disc_color.rgb * (1.0 - 0.32 * maria - crat) * mix(0.78, 1.0, pow(limb, 0.5));
	float halo = exp(-max(r - disc, 0.0) * 9.0) * (1.0 - inside) * 0.55;
	ALBEDO = (moon * inside + halo_color.rgb * halo) * energy;
	ALPHA = clamp(inside + halo, 0.0, 1.0);
}
