shader_type sky;
render_mode use_half_res_pass;
// Painted sky for the Whispering Woods (Milestone K, original). Replaces the photographic panorama, which clashed
// with the stylized forest: a saturated zenith fading to a luminous horizon, soft cel-edged cumulus with warm
// sunlit tops and cool blue undersides drifting slowly, a sun halo. Night (night = 1): deep teal-indigo, a band
// of faint violet nebula, twinkling stars and a soft moon. Everything is procedural (no textures).

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec4 zenith_day : source_color = vec4(0.20, 0.45, 0.86, 1.0);
uniform vec4 horizon_day : source_color = vec4(0.72, 0.87, 0.95, 1.0);
uniform vec4 ground_day : source_color = vec4(0.42, 0.52, 0.48, 1.0);
uniform vec4 cloud_lit : source_color = vec4(1.0, 0.98, 0.94, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.62, 0.72, 0.88, 1.0);
uniform vec4 zenith_night : source_color = vec4(0.01, 0.025, 0.06, 1.0);
uniform vec4 horizon_night : source_color = vec4(0.05, 0.12, 0.17, 1.0);
uniform vec4 nebula_color : source_color = vec4(0.42, 0.22, 0.62, 1.0);
uniform vec3 moon_dir = vec3(-0.35, 0.55, -0.76);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.46;
uniform float cloud_speed = 0.004;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	// ---- day gradient
	float hz = pow(1.0 - clamp(up, 0.0, 1.0), 3.2);
	vec3 day = mix(zenith_day.rgb, horizon_day.rgb, hz);
	day = mix(day, ground_day.rgb, smoothstep(0.0, -0.12, up));
	// sun halo + disk
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = max(dot(d, sd), 0.0);
	day += LIGHT0_COLOR * (pow(sdot, 8.0) * 0.18 + pow(sdot, 64.0) * 0.35) * (LIGHT0_ENABLED ? 1.0 : 0.0);
	day += LIGHT0_COLOR * smoothstep(0.9993, 0.9997, sdot) * 6.0 * (LIGHT0_ENABLED ? 1.0 : 0.0);
	// ---- clouds on a virtual dome plane
	vec3 col = day;
	if (up > 0.0) {
		vec2 uv = d.xz / (up + 0.18) * 1.6 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float n = fbm(uv);
		float cov = 1.0 - cloud_cover;
		float dens = smoothstep(cov, cov + 0.16, n);                 // soft-ish cel edge
		float body = smoothstep(cov + 0.02, cov + 0.32, n);
		// lit from the sun side: sample toward the sun to fake self-shadow
		vec2 toward = normalize(sd.xz + vec2(0.0001)) * 0.06;
		float n2 = fbm(uv + toward);
		float lit = clamp(0.5 + (n - n2) * 5.0, 0.0, 1.0);
		vec3 cc = mix(cloud_shade.rgb, cloud_lit.rgb, smoothstep(0.25, 0.75, lit + body * 0.25));
		cc += LIGHT0_COLOR * pow(sdot, 6.0) * 0.25 * (1.0 - body);  // silver lining
		float fade = smoothstep(0.0, 0.18, up);                     // dissolve into the horizon haze
		if (!AT_CUBEMAP_PASS) {
			col = mix(col, cc, dens * fade * (1.0 - night));
		} else {
			col = mix(col, cc, dens * fade * 0.5 * (1.0 - night));
		}
	}
	// ---- night
	vec3 nc = mix(zenith_night.rgb, horizon_night.rgb, pow(1.0 - clamp(up, 0.0, 1.0), 2.5));
	if (night > 0.0 && up > -0.05) {
		// nebula band across the sky
		vec3 bandn = normalize(vec3(0.35, 0.25, 0.9));
		float band = exp(-pow(dot(d, bandn) * 3.2, 2.0));
		float nn = fbm(d.xz * 3.0 / (up + 0.4) + 4.0);
		nc += nebula_color.rgb * band * smoothstep(0.35, 0.8, nn) * 0.22;
		nc += vec3(0.2, 0.45, 0.55) * band * smoothstep(0.55, 0.9, fbm(d.xz * 6.0 + 9.0)) * 0.08;
		if (!AT_CUBEMAP_PASS) {
			// stars: cells on the direction cube
			vec3 sp = d * 260.0;
			vec3 cell = floor(sp);
			float h = hash3(cell);
			float star = step(0.9965 - band * 0.004, h);
			vec3 fp = fract(sp) - 0.5;
			float tw = 0.6 + 0.4 * sin(TIME * (1.5 + h * 4.0) + h * 40.0);
			nc += vec3(0.85, 0.9, 1.0) * star * smoothstep(0.42, 0.0, length(fp)) * tw * 1.6 * smoothstep(0.0, 0.15, up);
		}
		// moon
		vec3 md = normalize(moon_dir);
		float mdot = dot(d, md);
		nc += vec3(0.75, 0.85, 1.0) * (smoothstep(0.99935, 0.9995, mdot) * 2.4 + pow(max(mdot, 0.0), 40.0) * 0.12);
	}
	col = mix(col, nc, night);
	COLOR = col;
}
