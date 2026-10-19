// A caster's domain over the arena (CombatSim): a dome seen from inside that replaces the sky while her ultimate
// holds. Mika: an icy starfield (deep blue, dense white-blue stars, a pale aurora band). Luna: a violet night with a
// huge moon low over the horizon and drifting violet haze. `amount` fades it in and out over the real sky.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, fog_disabled;

uniform vec3 top_col : source_color = vec3(0.02, 0.05, 0.16);
uniform vec3 horizon_col : source_color = vec3(0.25, 0.45, 0.85);
uniform vec3 star_col : source_color = vec3(0.85, 0.95, 1.0);
uniform float star_density = 0.35;
uniform vec3 moon_dir = vec3(0.0, 0.25, -1.0);
uniform float moon_size = 0.0;
uniform vec3 moon_col : source_color = vec3(0.95, 0.9, 1.0);
uniform float amount = 0.0;

varying vec3 dir;

void vertex() {
	dir = normalize(VERTEX);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 d = normalize(dir);
	float h = clamp(d.y, -0.1, 1.0);
	vec3 col = mix(horizon_col, top_col, smoothstep(0.0, 0.7, h));
	// stars: a cell grid on the sphere, one star per lit cell, twinkling
	vec3 cell = floor(d * 180.0);
	float r = hash(cell);
	if (r > 1.0 - star_density * 0.08 && h > 0.02) {
		float tw = 0.6 + 0.4 * sin(TIME * (2.0 + r * 5.0) + r * 40.0);
		col += star_col * tw * smoothstep(0.0, 0.2, h) * 1.4;
	}
	// a soft aurora / haze band
	float band = exp(-pow((h - 0.28 - 0.06 * sin(d.x * 3.0 + TIME * 0.2)) * 6.0, 2.0));
	col += horizon_col * band * 0.35;
	// the moon
	if (moon_size > 0.0) {
		float md = acos(clamp(dot(d, normalize(moon_dir)), -1.0, 1.0));
		col = mix(col, moon_col, smoothstep(moon_size, moon_size * 0.92, md));
		col += moon_col * exp(-md / (moon_size * 2.5)) * 0.35;
	}
	ALBEDO = col;
	ALPHA = amount * smoothstep(-0.1, 0.05, d.y);
}
