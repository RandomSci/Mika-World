// NATURAL HAIR (the developer: "follow how natural they look ... don't change Mika and Luna's hairs, just improve how
// the hair looks"). Shading only - the hairstyle (geometry, colours, the model's own strand texture) is kept. What the
// reference photos show and the lab's broad strand ribbons lacked:
//   * fine fibres: thousands of thin strands run along every lock (two layers of high-frequency fibre noise along V);
//   * depth: roots and inner layers darker, outer locks and tips lighter (root gradient + a per-lock tone);
//   * the sheen: light catches ACROSS the strands as a moving band (Kajiya-Kay anisotropic highlight from the strand
//     direction, two lobes: a bright narrow one and a wider one tinted by the hair colour, shifted per fibre);
//   * soft ends: the tips thin out into wisps (alpha-scissored fibres in the last part of each lock);
//   * a soft, anime-friendly light falloff (wrapped diffuse with a gentle shade tone) so it sits with the toon faces.
// UV: U across a lock, V along it (0 = root, 1 = tip) - the Celestial models' strand textures.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_disabled;
// v2 (2026-10-15): with the envelope normals from tools/models/refine_hair.py the hairdo shades as one soft mass;
// texture detail is kept subtle so the locks read clean, not noisy.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 shade_tint : source_color = vec4(0.68, 0.64, 0.8, 1.0);   // the colour light falls off into
uniform float fibre_density = 260.0;      // fine strands per UV unit across a lock
uniform float fibre_strength = 0.22;
uniform float root_dark = 0.32;           // how much darker the roots are
uniform float tip_feather = 0.14;         // the last fraction of a lock that thins into wisps (0 = hard ends)
uniform float sheen = 0.55;               // primary highlight strength
uniform float sheen2 = 0.35;              // secondary (tinted) highlight strength
uniform float sheen_shift = 0.12;         // where along the lock the band sits
uniform vec4 sheen_color : source_color = vec4(1.0, 0.97, 0.94, 1.0);
uniform float wrap = 0.45;                // soft wrap-around diffuse
uniform float rim = 0.18;
uniform float alpha_cut = 0.5;
uniform float flow = 0.9;                 // 1 = the highlight follows one smooth flow over the whole hairdo (gravity on
                                          // the smooth surface: a continuous "angel ring"); 0 = each clump's own direction
                                          // (clumps in curls then catch light differently: jagged, messy stripes)
uniform float detail = 0.35;              // how much of the strand texture's own tone shows (0 = one clean mass colour)
uniform vec4 mass_color : source_color = vec4(0.0);   // the hairdo's base colour (alpha 0 = take the texture's average)
uniform float sun_scale = 0.5;
uniform float gain = 1.0;                 // per-character brightness (a light hair colour keeps its luminance)            // the character light balance (WorldCharacter.apply_light_balance)

varying vec3 v_strand;     // strand direction (view space, set in fragment from BINORMAL)
varying float v_fibre;     // the fibre value, so the sheen breaks up per strand

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

float fibre(float u, float v, float dens, float seed) {
	float x = u * dens + sin(v * 9.0 + seed) * 0.35;
	float i = floor(x);
	float f = fract(x);
	float a = hash11(i + seed);
	float b = hash11(i + 1.0 + seed);
	return mix(a, b, smoothstep(0.0, 1.0, f));
}

void fragment() {
	vec4 t = texture(albedo_tex, UV) * tint;
	// one clean mass colour (the texture's own average - a deep mip - or the profile's colour), with only a little
	// of each clump's painted tone: overlapping clumps of different tones read as torn, messy patches
	vec3 avg = mass_color.a > 0.0 ? mass_color.rgb : textureLod(albedo_tex, vec2(0.5, UV.y), 11.0).rgb * tint.rgb;
	t.rgb = mix(avg, t.rgb, detail);
	float v = clamp(UV.y, 0.0, 1.0);
	// fine fibres (two scales) and a per-lock tone (darker / lighter locks side by side)
	float f1 = fibre(UV.x, v, fibre_density, 3.1);
	float f2 = fibre(UV.x, v, fibre_density * 2.7, 11.7);
	// a very gentle per-lock tone (strong bands read as patchy, "messy" hair)
	float lock_tone = mix(0.97, 1.03, hash11(floor(UV.x * 7.0) + 5.0));
	float fib = mix(1.0, 0.82 + 0.36 * (f1 * 0.65 + f2 * 0.35), fibre_strength / 0.22 * 0.6);
	// roots darker, inner layers darker (the lab's per-layer textures already darken the under-layer)
	float root = mix(1.0 - root_dark, 1.0, smoothstep(0.0, 0.35, v));
	ALBEDO = t.rgb * fib * root * lock_tone * gain;
	// the ends: the geometry already tapers each lock to a point - cutting fibres out of the tips with alpha left
	// torn, jagged edges (the developer: "their hair looks so messy"), so the tips are only lightened a touch
	ALBEDO *= 1.0 + 0.06 * smoothstep(1.0 - max(tip_feather, 0.001), 1.0, v);
	// the highlight's strand direction: gravity projected onto the (smooth, Blender-refined) surface, a touch of the
	// clump's own direction for life
	vec3 down_v = (VIEW_MATRIX * vec4(0.0, -1.0, 0.0, 0.0)).xyz;
	vec3 flow_t = down_v - NORMAL * dot(down_v, NORMAL);
	flow_t = length(flow_t) > 1e-3 ? normalize(flow_t) : normalize(BINORMAL);
	v_strand = normalize(mix(normalize(BINORMAL) * sign(dot(BINORMAL, flow_t) + 1e-4), flow_t, flow));
	// the fibre value shifts the highlight band up and down the lock (it breaks up like real sheen)
	SPECULAR = 0.0;
	ROUGHNESS = 0.6;
	BACKLIGHT = t.rgb * 0.12;
	v_fibre = f1;
	RIM = rim;
	RIM_TINT = 0.6;
}

uniform float self_shadow = 0.35;          // how much shadow-map darkness the hair takes (clumps shadowing clumps
                                          // break into jagged dark shards; anime hair keeps soft, broad shading)

void light() {
	float att = mix(1.0, ATTENUATION, self_shadow);
	float ndl = dot(NORMAL, LIGHT);
	// cull_disabled: a back face's normal points away - light both sides of a ribbon
	ndl = abs(ndl) * 0.85 + ndl * 0.15;
	float d = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	d = smoothstep(0.0, 1.0, d);
	vec3 lit = mix(shade_tint.rgb, vec3(1.0), d);
	DIFFUSE_LIGHT += ALBEDO * lit * LIGHT_COLOR * att * sun_scale / 3.14159;
	// Kajiya-Kay anisotropic sheen along the strand direction, two lobes
	vec3 T = normalize(v_strand);
	vec3 H = normalize(LIGHT + VIEW);
	float f1 = v_fibre;
	vec3 t1 = normalize(T + NORMAL * (sheen_shift + (f1 - 0.5) * 0.25));
	vec3 t2 = normalize(T + NORMAL * (sheen_shift - 0.18 + (f1 - 0.5) * 0.3));
	float th1 = dot(t1, H);
	float th2 = dot(t2, H);
	float s1 = pow(sqrt(max(1.0 - th1 * th1, 0.0)), 200.0);
	float s2 = pow(sqrt(max(1.0 - th2 * th2, 0.0)), 36.0);
	// only where the light really falls on the lock (no glare on its shaded side or silhouette), and broken up by
	// the fibres so it reads as a soft band of many strands, never a wet plastic patch
	float vis = smoothstep(0.05, 0.5, ndl) * att * (0.8 + 0.2 * v_fibre);
	SPECULAR_LIGHT += LIGHT_COLOR * sun_scale * vis * (sheen_color.rgb * s1 * sheen + ALBEDO * s2 * sheen2) * 0.35;
}
