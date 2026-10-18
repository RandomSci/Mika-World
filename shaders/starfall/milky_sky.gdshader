shader_type sky;
// Starfall Hill sky: the ESO Milky Way all-sky panorama (eso0932a, ESO/S. Brunier, CC BY 4.0 - see CREDITS.md),
// rotated so the galactic band arches across the sky, lifted so the band is the brightest thing in the frame; crisp
// procedural stars on top (the panorama's own stars are soft at screen scale), a faint violet airglow at the horizon,
// and occasional shooting stars.
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform mat3 sky_rot = mat3(1.0);              // world -> galactic (the panorama's own frame)
uniform float pano_energy = 1.4;
uniform float band_boost = 6.0;                // extra light on the bright band (bloom picks it up)
uniform vec3 night_tint : source_color = vec3(0.8, 0.82, 1.1);
uniform vec3 airglow : source_color = vec3(0.045, 0.03, 0.11);
uniform vec3 ground_col : source_color = vec3(0.004, 0.004, 0.012);
uniform float star_energy = 1.3;
uniform float meteor_energy = 9.0;
uniform vec2 meteor_az = vec2(-1.2, 1.2);      // azimuth range (radians) where shooting stars start
uniform float meteor_heading = 0.0;            // the azimuth the ranges are measured from
// dusk and dawn (DayNightCycle, 2026-10-19): the area's day panorama crossfaded in by the clock (mixk 1 = full night)
uniform sampler2D day_pano : filter_linear, repeat_enable;
uniform float day_energy = 1.0;
uniform float mixk = 1.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float stars(vec3 d, float scale, float density, float t) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash13(c);
	if (h <= 1.0 - density) {
		return 0.0;
	}
	vec3 sp = c + 0.25 + 0.5 * hash33(c);
	float b = pow(fract(h * 91.7), 5.0) * 2.2 + 0.2;
	float tw = 0.7 + 0.3 * sin(t * (0.8 + 2.5 * fract(h * 13.1)) + h * 40.0);
	return b * tw * smoothstep(0.42, 0.0, length(p - sp));
}

// one shooting star per `period` seconds (offset by `seed`), visible for ~0.8 s, sliding down a short arc
float meteor(vec3 d, float t, float period, float seed) {
	float k = floor((t + seed) / period);
	float ft = (t + seed) - k * period;
	float dur = 0.85;
	if (ft > dur) {
		return 0.0;
	}
	vec3 h = hash33(vec3(k, seed, k * 1.37 + 3.0));
	float az = meteor_heading + mix(meteor_az.x, meteor_az.y, h.x);
	float el = mix(0.45, 1.05, h.y);
	vec3 s = vec3(cos(el) * sin(az), sin(el), -cos(el) * cos(az));
	vec3 side = normalize(cross(s, vec3(0.0, 1.0, 0.0)));
	vec3 tdir = normalize(mix(side * (h.z < 0.5 ? 1.0 : -1.0), vec3(0.0, -1.0, 0.0), 0.45));
	float prog = ft / dur;
	vec3 head = normalize(s + tdir * 0.32 * prog);
	vec3 tail = normalize(head - tdir * 0.11);
	vec3 ab = tail - head;
	float tt = clamp(dot(d - head, ab) / dot(ab, ab), 0.0, 1.0);
	float dist = length(d - (head + ab * tt));
	float fade = smoothstep(0.0, 0.12, prog) * (1.0 - smoothstep(0.65, 1.0, prog));
	return fade * pow(1.0 - tt, 1.6) * exp(-dist * dist / 0.0000025);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 g = sky_rot * d;
	vec2 uv = vec2(atan(g.x, -g.z) / 6.2831853 + 0.5, acos(clamp(g.y, -1.0, 1.0)) / 3.14159265);
	vec3 p = textureLod(pano, uv, 0.0).rgb;
	float l = dot(p, vec3(0.3, 0.55, 0.15));
	vec3 col = p * pano_energy * night_tint + p * pow(l, 1.35) * band_boost;
	col += airglow * exp(-max(d.y, 0.0) * 7.0);
	if (!AT_CUBEMAP_PASS) {
		float up = smoothstep(-0.02, 0.12, d.y);
		col += vec3(0.85, 0.9, 1.0) * (stars(d, 300.0, 0.012, TIME) + stars(d, 620.0, 0.01, TIME * 1.3) * 0.5) * star_energy * up;
		float m = meteor(d, TIME, 7.0, 0.0) + meteor(d, TIME, 11.3, 4.1);
		col += vec3(0.85, 0.92, 1.0) * m * meteor_energy * up;
	}
	col = mix(col, ground_col, smoothstep(0.0, -0.08, d.y));
	COLOR = mix(texture(day_pano, SKY_COORDS).rgb * day_energy, col, smoothstep(0.0, 1.0, mixk));
}
