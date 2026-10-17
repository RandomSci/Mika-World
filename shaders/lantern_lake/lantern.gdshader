shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, world_vertex_coords;
// A paper sky lantern lit from inside by its small flame (LanternLake._lantern_mesh(): UV.x round, UV.y up,
// UV2.x part: 0 paper, 1 flame, 2 wire hoop). Brightest low inside where the flame is, cream-white where the light
// comes straight through the paper, deep orange at the edges and the top, thin darker bamboo ribs, gentle flicker.
// anim 1: a sky lantern rising over the lake (MultiMesh; INSTANCE_CUSTOM r seed, g rise speed m/s, b brightness),
// anim 2: one floating on the water (bobbing, turning, drifting a little round its spot), anim 0: placed by script.
// Viewer lanterns carry a name (name_tex) glowing on two sides.

uniform int anim = 0;
uniform float energy = 1.3;
uniform float lit = 1.0;                       // 0 = unlit paper (before the flame catches), 1 = burning
uniform float rise_range = 170.0;
uniform vec3 wind = vec3(0.05, 0.0, -0.03);    // drift per second aloft
uniform vec3 tint : source_color = vec3(1.0, 0.42, 0.11);
uniform vec3 hot : source_color = vec3(1.0, 0.83, 0.52);
uniform sampler2D name_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float name_on = 0.0;
uniform float name_energy = 1.7;

varying float v_bright;
varying float v_seed;

float h11(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - origin;
	float seed = INSTANCE_CUSTOM.r;
	float bright = anim == 0 ? 1.0 : INSTANCE_CUSTOM.b;
	vec3 off = vec3(0.0);
	float s = 1.0;
	if (anim == 1) {
		float spd = INSTANCE_CUSTOM.g;
		float hgt = mod(TIME * spd + seed * rise_range, rise_range);
		float aloft = hgt / max(spd, 0.01);
		s = smoothstep(0.0, 4.0, hgt) * (1.0 - smoothstep(rise_range * 0.86, rise_range, hgt));
		bright *= mix(1.0, 0.55, hgt / rise_range) * (0.4 + 0.6 * s);
		off = vec3(0.0, hgt, 0.0) + wind * aloft + vec3(sin(TIME * 0.21 + seed * 40.0), 0.0, cos(TIME * 0.17 + seed * 23.0)) * 0.6;
		// a slow lean and turn in the air
		float a = sin(TIME * 0.35 + seed * 9.0) * 0.06;
		local = vec3(local.x, local.y * cos(a) - local.z * sin(a), local.y * sin(a) + local.z * cos(a));
	} else if (anim == 2) {
		float r = INSTANCE_CUSTOM.g;
		float ph = TIME * 0.025 * (0.6 + seed) + seed * 6.283;
		off = vec3(cos(ph) * r, 0.012 * sin(TIME * 0.9 + seed * 20.0), sin(ph * 0.8) * r);
		float a = sin(TIME * 0.6 + seed * 13.0) * 0.035;
		float b = cos(TIME * 0.5 + seed * 7.0) * 0.035;
		local = vec3(local.x, local.y * cos(a) - local.z * sin(a), local.y * sin(a) + local.z * cos(a));
		local = vec3(local.x * cos(b) - local.y * sin(b), local.x * sin(b) + local.y * cos(b), local.z);
	}
	VERTEX = origin + local * s + off;
	v_bright = bright;
	v_seed = seed;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	int part = int(UV2.x + 0.5);
	float fl = 0.9 + 0.06 * sin(TIME * 9.0 + v_seed * 50.0) + 0.04 * sin(TIME * 23.0 + v_seed * 17.0);
	vec3 col;
	if (part == 1) {
		col = vec3(1.0, 0.72, 0.32) * 7.0 * fl * lit;
	} else if (part == 2) {
		col = vec3(0.05, 0.03, 0.02) + tint * 0.15 * lit;
	} else {
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		// light through the paper: strongest a little above the flame, falling off toward the top
		float q = (v - 0.28) / 0.33;
		float I = 0.42 + 0.9 * exp(-q * q);
		I *= mix(0.55, 1.0, pow(facing, 0.7));
		I *= mix(1.0, 0.5, smoothstep(0.78, 1.0, v));
		float rib = abs(fract(u * 8.0 + 0.5) - 0.5) * 2.0;
		I *= mix(0.7, 1.0, smoothstep(0.0, 0.07, rib));
		I *= mix(0.65, 1.0, smoothstep(0.0, 0.035, v));
		// paper grain: soft, uneven brightness (smooth, so it never reads as pixels up close)
		float mott = sin(u * 37.0 + v * 11.0 + v_seed * 20.0) * sin(v * 23.0 - u * 9.0 + v_seed * 7.0);
		I *= 0.96 + 0.04 * mott;
		if (!FRONT_FACING) {
			I *= 1.2;         // looking up into it: the lit inside
		}
		I *= v_bright * fl;
		// deep orange paper, cream-white only where the light comes straight through
		col = mix(tint, hot, smoothstep(0.85, 1.4, I)) * I * energy;
		// unlit paper: the warm paper itself, faintly lit by the night
		col = mix(vec3(0.05, 0.036, 0.024) * (0.6 + 0.4 * facing), col, lit);
		if (name_on > 0.0) {
			for (int side = 0; side < 2; side++) {
				float c = side == 0 ? 0.25 : 0.75;
				vec2 tuv = vec2(0.5 - (u - c) / 0.33, 1.0 - (v - 0.3) / 0.36);    // read from outside, not mirrored
				if (tuv.x > 0.0 && tuv.x < 1.0 && tuv.y > 0.0 && tuv.y < 1.0 && FRONT_FACING) {
					vec4 t = texture(name_tex, tuv);
					col = mix(col, t.rgb * name_energy * max(lit, 0.25), t.a * name_on);
				}
			}
		}
	}
	ALBEDO = col;
}
