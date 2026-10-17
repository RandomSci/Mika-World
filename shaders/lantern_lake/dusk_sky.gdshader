shader_type sky;
render_mode use_debanding;
// LANTERN LAKE's painted backdrop, drawn per pixel so it is sharp at any size and mirrors exactly in the lake:
// a late-dusk sky (deep navy overhead, a violet-rose afterglow low in the north between the mountains), thin
// painted cloud wisps, twinkling stars, and three layers of mountains - dark near slopes framing the valley left and
// right, lighter hazier ranges behind, small far peaks in the gap - with painted rock streaks and lit ridges.
// Azimuth is measured from north (-Z) toward east (+X), in degrees.

uniform vec3 zenith : source_color = vec3(0.075, 0.105, 0.27);
uniform vec3 upper : source_color = vec3(0.13, 0.17, 0.42);
uniform vec3 low : source_color = vec3(0.27, 0.26, 0.56);
uniform vec3 glow_col : source_color = vec3(0.62, 0.47, 0.76);
uniform vec3 mtn_near : source_color = vec3(0.075, 0.09, 0.19);
uniform vec3 mtn_mid : source_color = vec3(0.13, 0.14, 0.28);
uniform vec3 mtn_far : source_color = vec3(0.24, 0.23, 0.44);
uniform vec3 haze : source_color = vec3(0.36, 0.32, 0.56);
uniform float star_energy = 1.0;
uniform float glow_az = 12.0;         // degrees: where the afterglow sits (the valley gap)

// hashes without sine (Dave Hoskins): stable at large inputs, no blocky steps along the ridges
float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec3 h33(vec3 p) {
	vec3 p3 = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return s;
}

// sharp-peaked ridge line along the azimuth (periodic: sampled on a circle)
float ridged(float az, float freq, float seed) {
	float r = 0.0;
	float a = 0.55;
	float f = freq;
	for (int i = 0; i < 5; i++) {
		vec2 c = vec2(cos(radians(az)), sin(radians(az))) * f + seed;
		float n = 1.0 - abs(vnoise(c) * 2.0 - 1.0);
		r += n * n * a;
		f *= 2.1;
		a *= 0.45;
	}
	return r;
}

float wrap_az(float a) { return mod(a + 180.0, 360.0) - 180.0; }

// layer ridge elevations (degrees above the horizon)
float ridge_near(float az) {
	float g = wrap_az(az - glow_az);
	float frame = smoothstep(8.0, 40.0, abs(g));                  // the valley gap in the middle
	return 1.2 + frame * (13.0 + 11.0 * ridged(az, 2.6, 3.0)) + (1.0 - frame) * 1.6 * ridged(az, 6.0, 11.0);
}
float ridge_mid(float az) {
	float g = wrap_az(az - glow_az);
	float frame = smoothstep(4.0, 28.0, abs(g));
	return 1.8 + frame * (7.5 + 7.0 * ridged(az, 4.0, 21.0)) + (1.0 - frame) * 3.0 * ridged(az, 7.0, 5.0);
}
float ridge_far(float az) {
	return 2.6 + 5.0 * ridged(az, 5.5, 41.0) + 1.4 * ridged(az, 11.0, 7.0);
}

// a painted mountain face: rock streaks running down the slope, a lit edge under the ridge on the side facing the glow
vec3 mountain(vec3 base, float az, float el, float ridge, float dr, float layer) {
	float below = max(ridge - el, 0.0);
	float streak = fbm(vec2(az * 0.9 + layer * 13.0 + el * 0.25, el * 0.22 - az * 0.05) * vec2(1.0, 2.6));
	float face = fbm(vec2(az * 0.18 + layer * 7.0, el * 0.35));
	vec3 c = base * (0.82 + 0.34 * streak + 0.18 * (face - 0.5));
	float g = wrap_az(az - glow_az);
	float facing = clamp(dr * sign(g) * 0.9, 0.0, 1.0);          // slopes that fall toward the bright gap
	float rim = exp(-below / (0.35 + layer * 0.15)) * (0.25 + 0.75 * facing);
	c += glow_col * rim * (0.16 + 0.08 * layer);
	// aerial haze toward each layer's foot
	c = mix(c, haze, smoothstep(ridge * 0.2, -0.5, el) * (0.25 + 0.25 * layer));
	return c;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float el = degrees(asin(clamp(d.y, -1.0, 1.0)));
	// (straight up atan(0, 0) is undefined: a NaN there spreads through the glow as a huge black disc)
	float az = length(d.xz) > 1e-5 ? degrees(atan(d.x, -d.z)) : 0.0;
	float g = wrap_az(az - glow_az);
	// the sky: navy overhead, blue, then violet near the horizon; the afterglow over the gap
	float t = clamp(el / 90.0, 0.0, 1.0);
	vec3 c = mix(low, upper, smoothstep(0.0, 0.24, t));
	c = mix(c, zenith, smoothstep(0.18, 0.75, t));
	float ag = exp(-max(el, 0.0) / 7.5) * exp(-g * g / (2.0 * 38.0 * 38.0));
	c = mix(c, glow_col, ag * 0.85);
	// painted cloud wisps, long and thin, low in the sky
	float cb = smoothstep(3.0, 9.0, el) * (1.0 - smoothstep(18.0, 34.0, el));
	float cn = fbm(vec2(az * 0.05 + TIME * 0.0006, el * 0.42) * vec2(1.0, 1.0)) ;
	cn += 0.35 * fbm(vec2(az * 0.16 - TIME * 0.0009, el * 1.3));
	float cloud = smoothstep(0.78, 1.02, cn) * cb;
	vec3 ccol = mix(upper * 1.25 + vec3(0.03, 0.02, 0.06), glow_col * 0.9, ag * 1.4 + 0.1);
	c = mix(c, ccol, cloud * 0.55);
	// stars (not in the radiance cubemap)
	if (!AT_CUBEMAP_PASS && el > 1.0) {
		float s = 0.0;
		vec3 sc = vec3(0.0);
		for (int k = 0; k < 2; k++) {
			float scale = k == 0 ? 220.0 : 90.0;
			vec3 p = d * scale;
			vec3 cell = floor(p);
			vec3 hsh = h33(cell + float(k) * 31.0);
			vec3 sp = cell + 0.2 + 0.6 * hsh;
			float dist = length(p - sp);
			float keep = step(k == 0 ? 0.955 : 0.972, hsh.z);
			float mag = pow(h21(cell.xy + cell.z * 7.1), 4.0) * (k == 0 ? 1.1 : 3.0) + (k == 0 ? 0.12 : 0.35);
			float tw = 0.78 + 0.22 * sin(TIME * (1.3 + hsh.x * 2.4) + hsh.y * 40.0);
			float pt = exp(-dist * dist * (k == 0 ? 38.0 : 120.0)) * mag * tw * keep;
			vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.78), hsh.x);
			sc += tint * pt;
		}
		float fade = smoothstep(1.0, 14.0, el) * (1.0 - cloud * 0.85);
		c += sc * fade * star_energy * 0.9;
	}
	// mountains, far to near (each covers what is behind it)
	float e = 0.03;
	float rf = ridge_far(az);
	float aa = 0.035;
	float mf = smoothstep(rf + aa, rf - aa, el);
	float drf = (ridge_far(az + e * 20.0) - ridge_far(az - e * 20.0)) / (e * 40.0);
	if (mf > 0.0) {
		c = mix(c, mountain(mix(mtn_far, haze, 0.25), az, el, rf, drf, 2.0), mf);
	}
	float rm = ridge_mid(az);
	float mm = smoothstep(rm + aa, rm - aa, el);
	float drm = (ridge_mid(az + e * 20.0) - ridge_mid(az - e * 20.0)) / (e * 40.0);
	if (mm > 0.0) {
		c = mix(c, mountain(mtn_mid, az, el, rm, drm, 1.0), mm);
	}
	float rn = ridge_near(az);
	float mn = smoothstep(rn + aa, rn - aa, el);
	float drn = (ridge_near(az + e * 20.0) - ridge_near(az - e * 20.0)) / (e * 40.0);
	if (mn > 0.0) {
		c = mix(c, mountain(mtn_near, az, el, rn, drn, 0.0), mn);
	}
	// below the horizon (only seen through gaps): the far mist over the water
	c = mix(c, haze * 0.8, smoothstep(0.6, -0.6, el));
	COLOR = c;
}
