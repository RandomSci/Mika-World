// The duel's realm sky (2026-10-20, Selwyn: "I want a worldly effect during fights, not simple things"; his references
// change the whole sky in a domain). The area's own day and night panoramas as DayNightCycle blends them, and over them
// the realm of the girl who is winning the sky, spreading out across the dome from her side:
//   realm 0  Mika, a frozen starfield. The Milky Way band (ESO eso0932a, CC BY 4.0, CREDITS.md) lifted and tinted ice
//            blue, dense crisp stars, aurora curtains sweeping overhead
//   realm 1  Luna, an eclipse. A violet nebula churning, scattered stars, a huge moon above the other girl going dark
//            with a burning violet corona and long rays
// realm_k 0..1 is how far the realm has taken the sky; flash adds the light of a release (a white bloom on the dome).
shader_type sky;

uniform sampler2D day_pano : filter_linear, repeat_enable;
uniform sampler2D night_pano : filter_linear, repeat_enable;
uniform float mixk : hint_range(0.0, 1.0) = 0.0;
uniform float day_energy = 1.0;
uniform float night_energy = 1.0;

uniform sampler2D galaxy : source_color, filter_linear, repeat_enable;
uniform mat3 galaxy_rot = mat3(1.0);
uniform float realm_k : hint_range(0.0, 1.0) = 0.0;
uniform int realm = 0;
uniform vec3 origin_dir = vec3(1.0, 0.2, 0.0);       // where the realm spreads from (the caster's side, world)
uniform vec3 moon_dir = vec3(-0.6, 0.55, 0.3);       // Luna's moon (above the other girl)
uniform float eclipse : hint_range(0.0, 1.0) = 0.0;  // how far the moon has gone dark
uniform float flash = 0.0;
uniform vec3 ice : source_color = vec3(0.45, 0.8, 1.0);
uniform vec3 violet : source_color = vec3(0.62, 0.32, 1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

float stars(vec3 d, float scale, float density, float t) {
	vec3 p = d * scale;
	vec3 c = floor(p);
	float h = hash13(c);
	if (h <= 1.0 - density) {
		return 0.0;
	}
	vec3 sp = c + 0.25 + 0.5 * hash33(c);
	float r = length(p - sp);
	float tw = 0.7 + 0.3 * sin(t * (1.5 + h * 3.0) + h * 40.0);
	return smoothstep(0.09, 0.0, r) * tw * (0.4 + 0.6 * fract(h * 17.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 base = mix(texture(day_pano, SKY_COORDS).rgb * day_energy, texture(night_pano, SKY_COORDS).rgb * night_energy, smoothstep(0.0, 1.0, mixk));
	float t = TIME;
	// the realm spreads from the caster's side of the dome: a soft front sweeping across as realm_k rises
	float ang = acos(clamp(dot(d, normalize(origin_dir)), -1.0, 1.0)) / 3.14159;
	float front = smoothstep(realm_k * 1.25 - 0.18, realm_k * 1.25, ang);
	float m = (1.0 - front) * smoothstep(0.0, 0.08, realm_k);
	vec3 r = vec3(0.0);
	float up = clamp(d.y, -0.2, 1.0);
	if (realm == 0) {
		// Mika: deep ice night, the galaxy band, aurora
		vec3 g = texture(galaxy, vec2(atan((galaxy_rot * d).x, (galaxy_rot * d).z) / 6.2831853 + 0.5, acos(clamp((galaxy_rot * d).y, -1.0, 1.0)) / 3.14159)).rgb;
		float gl = dot(g, vec3(0.3, 0.5, 0.2));
		r = vec3(0.004, 0.012, 0.035) + ice * gl * 5.5 + vec3(0.9, 0.95, 1.0) * pow(gl, 2.0) * 9.0;
		r += vec3(0.85, 0.93, 1.0) * (stars(d, 220.0, 0.05, t) * 2.5 + stars(d, 520.0, 0.08, t) * 1.2);
		// aurora curtains: vertical bands that wave, brightest low over the horizon
		float az = atan(d.x, d.z);
		float band = fbm(vec3(az * 3.0, t * 0.08, 0.0));
		float curtain = smoothstep(0.45, 0.75, band) * smoothstep(0.02, 0.18, up) * smoothstep(0.75, 0.25, up);
		float rays = 0.6 + 0.4 * sin(az * 90.0 + band * 20.0 + t * 0.6);
		vec3 au = mix(vec3(0.15, 1.0, 0.75), vec3(0.55, 0.45, 1.0), smoothstep(0.1, 0.5, up));
		r += au * curtain * rays * 1.6;
	} else {
		// Luna: violet nebula, stars, the eclipse
		float n = fbm(d * 2.2 + vec3(0.0, t * 0.015, t * 0.01));
		float n2 = fbm(d * 5.5 - vec3(t * 0.02, 0.0, 0.0));
		r = vec3(0.012, 0.004, 0.03) + violet * pow(n, 2.2) * 2.2 + vec3(0.95, 0.35, 0.75) * pow(n2 * n, 3.0) * 3.5;
		r += vec3(1.0, 0.92, 1.0) * stars(d, 260.0, 0.04, t) * 2.0;
		vec3 md = normalize(moon_dir);
		float ca = dot(d, md);
		float rad = 0.14;                                   // the moon's angular size (radians)
		float dm = acos(clamp(ca, -1.0, 1.0));
		float disc = smoothstep(rad, rad - 0.004, dm);
		float lit = mix(1.0, 0.03, eclipse);
		vec3 moon_c = mix(vec3(0.95, 0.92, 1.0), vec3(0.12, 0.02, 0.18), eclipse) * (0.8 + 0.2 * fbm(d * 40.0));
		float corona = exp(-max(dm - rad, 0.0) * 24.0) * (0.35 + eclipse * 2.6);
		float rays_l = pow(max(0.0, sin(atan(dot(d - md * ca, cross(md, vec3(0, 1, 0))), dot(d - md * ca, vec3(0, 1, 0))) * 14.0 + t * 0.3)), 6.0);
		corona += exp(-max(dm - rad, 0.0) * 6.0) * rays_l * eclipse * 0.9;
		r = mix(r, moon_c * lit * 6.0, disc);
		r += (violet * 1.4 + vec3(1.0, 0.85, 1.0) * 0.6) * corona * (1.0 - disc);
	}
	r += vec3(1.0, 0.97, 1.0) * flash * (0.6 + 0.4 * smoothstep(-0.1, 0.6, up));
	COLOR = mix(base, r, m);
}
