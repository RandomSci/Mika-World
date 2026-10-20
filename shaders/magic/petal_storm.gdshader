// The petal storm (2026-10-20, Selwyn: "research how the Bleach character that uses Bankai that has the effect of cherry
// blossom ... and apply it"; then his look notes: never fill a volume, streams spirals and rings dense at the edges and
// empty in the middle, petals always entering and leaving, flutter and spin, curl noise so the streams swirl). Our own
// take on the technique, not its assets: every position is computed here from the technique's shape, then moved by a
// curl noise field and a flutter, so thousands of petals move as one living mass.
//   mode 0 GATHER   five spiral arms flowing in to the point (her hand), a ring at their outer edge
//   mode 1 RIVER    three ribbons twisting round a curve from a through b to c (head at `prog`), the tail at the hand
//   mode 2 ENGULF   bands of petals orbiting on the shell of a sphere round `center` (shrinking crushes it)
//   mode 3 SHIELD   slanted rings orbiting round `center` (her body)
//   mode 4 SCATTER  bursting out from `center` and drifting down and away as `amount` goes 0 to 1
//   mode 5 COMETS   up to 12 comets, each from `a` to pts[g].xyz launched at pts[g].w (on tclock) flying `rise` s,
//                   a knot at the head and a spiral tail
//   mode 6 COLUMNS  up to 12 helices standing on pts[g].xyz, each erupting at pts[g].w over `rise` s up to `height`,
//                   petals climbing them all the time; `taper` < 1 a spire, > 1 a tornado opening at the top
//   mode 7 TIDE     a curling crest `width` across and `height` high rolling from a to c (front at `prog`)
//   mode 8 CASCADE  a funnel pouring down from `height` over `center`, the front reaching the ground with `amount`
//   mode 9 RIPPLE   a ring running out over the ground from `center` to `radius`
//   mode 10 STREAM  a held torrent from a through b to c (front at `prog`), ribbons flowing along it
// Two modes are blended (mode_a, mode_b, k) so every change of shape flows instead of jumping.
// The same shader drives three draw layers (`layer`): 0 the petals, 1 the sparkles, 2 the soft glow.
// COLOR out: petals (spark, colour variant, life fade, on); sparkles and glow (rgb brightness, on).
shader_type particles;
render_mode disable_velocity, keep_data;

uniform int layer = 0;
uniform int mode_a = 0;
uniform int mode_b = 0;
uniform float k : hint_range(0.0, 1.0) = 0.0;
uniform vec3 a = vec3(0.0);
uniform vec3 b = vec3(0.0, 2.0, 0.0);
uniform vec3 c = vec3(0.0, 0.0, 4.0);
uniform vec3 center = vec3(0.0);
uniform float prog = 0.0;
uniform float trail = 0.55;
uniform float width = 0.35;
uniform float radius = 1.0;
uniform float amount = 0.0;
uniform float size = 1.0;
uniform float visible_frac = 1.0;          // the share of petals shown (the storm grows from a few to all)
uniform float tclock = 0.0;                // the technique's own clock (s)
uniform vec4 pts[12];                      // COMETS targets / COLUMNS bases (xyz) and their start times (w, on tclock)
uniform int n_groups = 1;
uniform float rise = 0.3;
uniform float height = 3.0;
uniform float taper = 0.55;
uniform float spread = 1.0;
uniform float arc_h = 0.8;
uniform float flow = 1.2;                  // STREAM: how fast the petals run along it (path lengths per second)
uniform float ground_y = -10000.0;         // no petal goes under the ground
uniform float curl_amp = 0.12;             // how far the curl noise swirls a petal off its shape (m)
uniform float curl_freq = 0.9;


float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

vec3 rnd_dir(float s) {
	float z = h1(s) * 2.0 - 1.0;
	float ph = h1(s + 1.7) * TAU;
	float r = sqrt(max(1.0 - z * z, 0.0));
	return vec3(r * cos(ph), z, r * sin(ph));
}

mat3 rot_axis(vec3 ax, float ang) {
	ax = normalize(ax);
	float s = sin(ang);
	float co = cos(ang);
	float oc = 1.0 - co;
	return mat3(vec3(oc * ax.x * ax.x + co, oc * ax.x * ax.y + ax.z * s, oc * ax.z * ax.x - ax.y * s),
		vec3(oc * ax.x * ax.y - ax.z * s, oc * ax.y * ax.y + co, oc * ax.y * ax.z + ax.x * s),
		vec3(oc * ax.z * ax.x + ax.y * s, oc * ax.y * ax.z - ax.x * s, oc * ax.z * ax.z + co));
}

// --- curl noise (the curl of three smooth value noise fields: divergence free, so petals swirl and never bunch)
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 pot(vec3 p) {
	return vec3(vnoise(p), vnoise(p + vec3(31.4, 7.7, 2.9)), vnoise(p + vec3(-5.3, 19.1, 43.7)));
}

vec3 curl(vec3 p) {
	const float e = 0.15;
	vec3 dx = pot(p + vec3(e, 0, 0)) - pot(p - vec3(e, 0, 0));
	vec3 dy = pot(p + vec3(0, e, 0)) - pot(p - vec3(0, e, 0));
	vec3 dz = pot(p + vec3(0, 0, e)) - pot(p - vec3(0, 0, e));
	return vec3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x) / (2.0 * e);
}

vec3 bez(float s) {
	return mix(mix(a, b, s), mix(b, c, s), s);
}

vec3 bez_d(float s) {
	return normalize(2.0 * (1.0 - s) * (b - a) + 2.0 * s * (c - b) + vec3(1e-4));
}

vec3 qbez(vec3 p0, vec3 p1, vec3 p2, float s) {
	return mix(mix(p0, p1, s), mix(p1, p2, s), s);
}

vec3 frame_side(vec3 tg) {
	vec3 sd = cross(tg, vec3(0.0, 1.0, 0.0));
	return length(sd) > 1e-3 ? normalize(sd) : vec3(1.0, 0.0, 0.0);
}

// life fade of a petal cycling through a shape: in over the first tenth, out over the last
float life(float ph) {
	return smoothstep(0.0, 0.1, ph) * (1.0 - smoothstep(0.85, 1.0, ph));
}

// (xyz place, w life fade)
vec4 shape(int m, float id) {
	float r1 = h1(id + 0.13);
	float r2 = h1(id + 7.31);
	float r3 = h1(id + 3.77);
	float t = tclock;
	if (m == 0) {
		// GATHER: five spiral arms; each petal flows in along its arm, enters at the rim, leaves into the hand
		float arm = floor(r2 * 5.0);
		float ph = fract(r1 + t * (0.55 + 0.35 * r3));
		float R = mix(1.5, 0.35, amount);
		float rr = R * (1.0 - ph) + 0.05;
		float ang = arm * TAU / 5.0 + (1.0 - ph) * 4.2 + t * 2.4;
		vec3 ax = normalize(vec3(0.25, 1.0, 0.15));
		vec3 u = normalize(cross(ax, vec3(1.0, 0.0, 0.0)));
		vec3 v = cross(ax, u);
		vec3 p = center + (u * cos(ang) + v * sin(ang)) * rr + ax * (r3 - 0.5) * 0.18 * rr;
		return vec4(p, life(ph) * (1.0 - smoothstep(0.88, 1.0, ph)));
	} else if (m == 1) {
		// RIVER: three ribbons twisting round the curve; petals on the ribbons' surface, none down the middle
		float u = r1;
		float s = clamp(prog - u * trail, 0.0, 1.0);
		vec3 p = bez(s);
		vec3 tg = bez_d(s);
		vec3 sd = frame_side(tg);
		vec3 up = normalize(cross(sd, tg));
		float rib = floor(r2 * 3.0);
		float w = width * (0.85 + 0.15 * r3) * (0.35 + 0.65 * sin(3.14159 * clamp(s * 1.2, 0.0, 1.0)));
		float ang = rib * 2.0944 + s * 14.0 - t * 4.0 + (r3 - 0.5) * 0.5;
		p += (sd * cos(ang) + up * sin(ang)) * w;
		if (prog - u * trail <= 0.0) {
			float a2 = r2 * TAU + t * 6.0;
			p = a + vec3(cos(a2), (r3 - 0.5) * 0.4, sin(a2)) * 0.16;
		}
		return vec4(p, 1.0);
	} else if (m == 2) {
		// ENGULF: six bands of petals orbiting on the shell, each on its own tilted axis
		float band = floor(r3 * 6.0);
		vec3 ax = normalize(rnd_dir(band * 3.3 + 11.0));
		vec3 ref = normalize(cross(ax, abs(ax.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		float ang = r1 * TAU + t * (1.6 + band * 0.25) * (band < 3.0 ? 1.0 : -1.0);
		vec3 dir = rot_axis(ax, ang) * ref;
		dir = normalize(dir + ax * (r2 - 0.5) * 0.35);
		return vec4(center + dir * radius * (0.92 + 0.08 * r2), 1.0);
	} else if (m == 3) {
		// SHIELD: rings of petals orbiting her body at several slants
		float ring = floor(r2 * 4.0);
		vec3 ax = normalize(vec3(sin(ring * 1.9) * 0.6, 1.0, cos(ring * 2.3) * 0.6));
		vec3 ref = normalize(cross(ax, vec3(1.0, 0.0, 0.0)));
		float ang = r1 * TAU + t * (2.4 + ring * 0.5);
		vec3 off = rot_axis(ax, ang) * ref * radius * (0.92 + 0.12 * r3);
		return vec4(center + off + ax * (r3 - 0.5) * 0.12, 1.0);
	} else if (m == 5) {
		// COMETS: group g flies its own arc; r1 places the petal along the tail behind the head
		int g = min(int(floor(r2 * float(n_groups))), n_groups - 1);
		float gf = n_groups > 1 ? float(g) / float(n_groups - 1) - 0.5 : 0.0;
		vec4 tp = pts[g];
		vec3 p0 = a + (rnd_dir(float(g) * 3.1 + 2.0) * vec3(1.0, 0.4, 1.0)) * spread * 0.18;
		vec3 dl = tp.xyz - p0;
		vec3 sd = frame_side(normalize(dl + vec3(1e-4)));
		vec3 p1 = mix(p0, tp.xyz, 0.5) + vec3(0.0, arc_h, 0.0) + sd * gf * spread;
		float pg = (t - tp.w) / max(rise, 0.02);
		float s = clamp(pg - r1 * 0.22, 0.0, 1.0);
		vec3 p = qbez(p0, p1, tp.xyz, s);
		vec3 tg = normalize(2.0 * (1.0 - s) * (p1 - p0) + 2.0 * s * (tp.xyz - p1) + vec3(1e-4));
		vec3 s2 = frame_side(tg);
		vec3 u2 = normalize(cross(s2, tg));
		// a spiral tail: the knot at the head, opening into two twisting strands behind it
		float w = width * (0.15 + 0.85 * r1) * (0.85 + 0.15 * r3);
		float ang = floor(r3 * 2.0) * 3.14159 + t * 9.0 + r1 * 10.0;
		p += (s2 * cos(ang) + u2 * sin(ang)) * w;
		if (pg - r1 * 0.22 <= 0.0) {
			float a2 = r3 * TAU + t * 7.0;
			p = p0 + vec3(cos(a2), (r1 - 0.5) * 0.4, sin(a2)) * 0.16;
		}
		return vec4(p, 1.0);
	} else if (m == 6) {
		// COLUMNS: a double helix on each base, rising from the ground when its time comes; petals climb it and
		// leave from its top
		int g = min(int(floor(r2 * float(n_groups))), n_groups - 1);
		vec4 tp = pts[g];
		float lu = clamp((t - tp.w) / max(rise, 0.02), 0.0, 1.0);
		float e = 1.0 - pow(1.0 - lu, 3.0);
		float ph = fract(r1 + t * 0.45 * (0.8 + 0.4 * r3));
		float hh = ph * height * e;
		float rr = width * (0.88 + 0.12 * r3) * mix(1.0, taper, ph) * (0.6 + 0.4 * e);
		float strand = floor(h1(id + 5.1) * 2.0);
		float ang = strand * 3.14159 + ph * 9.0 + t * (4.0 + 2.0 * r3);
		vec3 p = tp.xyz + vec3(cos(ang) * rr, hh + 0.02, sin(ang) * rr);
		float f = life(ph);
		if (lu <= 0.0) {
			// before it erupts: a ring of petals whirling flat on the ground where it will stand
			p = tp.xyz + vec3(cos(ang + r1 * TAU) * width * 0.95, 0.03 + r1 * 0.04, sin(ang + r1 * TAU) * width * 0.95);
			f = 1.0;
		}
		return vec4(p, f);
	} else if (m == 7) {
		// TIDE: a curling crest; petals on the curl's surface, r1 how far behind the front, r3 across
		float s = clamp(prog - r1 * trail, 0.0, 1.0);
		vec3 base = bez(s);
		vec3 tg = bez_d(s);
		vec3 sd = frame_side(tg);
		float x = (r3 * 2.0 - 1.0);
		float hh = height * (1.0 - 0.85 * r1) * (1.0 - 0.55 * x * x);
		float R = hh * 0.5;
		float phi = mod(h1(id + 9.3) * 3.14159 * 1.35 + t * 3.0 * (0.5 + r2), 3.14159 * 1.35);
		vec3 p = base + sd * x * width + vec3(0.0, R - R * cos(phi), 0.0) + tg * (R * sin(phi) * 0.8);
		if (prog - r1 * trail <= 0.0) {
			float a2 = r2 * TAU + t * 6.0;
			p = a + vec3(cos(a2), (r3 - 0.5) * 0.4, sin(a2)) * 0.18;
		}
		return vec4(p, 1.0);
	} else if (m == 8) {
		// CASCADE: a funnel's surface; each petal pours down it again and again, the front coming down with `amount`
		float ph = fract(r1 + t * (0.7 + 0.6 * r3));
		float front = clamp(amount, 0.0, 1.0);
		float d = ph * front;
		float rr = width * (0.25 + 1.3 * d * d) * (0.9 + 0.1 * r3);
		float ang = floor(r2 * 4.0) * 1.5708 + d * 7.0 + t * 3.0;
		return vec4(center + vec3(cos(ang) * rr, height * (1.0 - d), sin(ang) * rr), life(ph));
	} else if (m == 9) {
		// RIPPLE: a ring over the ground, petals thrown up off its edge and falling behind it
		float e = 1.0 - pow(1.0 - clamp(amount, 0.0, 1.0), 2.0);
		float rr = radius * e * (0.9 + 0.12 * r1);
		float ang = r2 * TAU + t * 0.6;
		float lift = (0.04 + r3 * 0.6) * sin(3.14159 * clamp(e * 1.4 - r1 * 0.4, 0.0, 1.0));
		return vec4(center + vec3(cos(ang) * rr, lift, sin(ang) * rr), 1.0);
	} else if (m == 10) {
		// STREAM: petals run along the path's surface for as long as it holds, entering at her hand and leaving at
		// the target; five ribbons twisting round it
		float ph = fract(r1 + t * flow * (0.8 + 0.4 * r3));
		float s = ph * clamp(prog, 0.0, 1.0);
		vec3 p = bez(s);
		vec3 tg = bez_d(s);
		vec3 sd = frame_side(tg);
		vec3 up = normalize(cross(sd, tg));
		float rib = floor(r2 * 5.0);
		float w = width * (0.85 + 0.15 * r3) * (0.6 + 0.4 * sin(3.14159 * s));
		float ang = rib * 1.2566 + s * 18.0 - t * 7.0;
		return vec4(p + (sd * cos(ang) + up * sin(ang)) * w, life(ph));
	}
	// SCATTER: out from the centre, slowing, drifting down and with the air
	vec3 dir = normalize(rnd_dir(id) + vec3(0.0, 0.35, 0.0));
	float sp = (0.8 + 2.4 * r1) * radius;
	float e = 1.0 - pow(1.0 - clamp(amount, 0.0, 1.0), 3.0);
	vec3 p = center + dir * sp * e + vec3(sin(t * 1.3 + r2 * 6.28) * 0.3, -amount * amount * (0.6 + r3) * 2.0, cos(t * 1.1 + r3 * 6.28) * 0.3);
	return vec4(p, 1.0);
}

void start() {
	CUSTOM = vec4(h1(float(INDEX) * 0.731 + 0.5), h1(float(INDEX) * 1.37), h1(float(INDEX) * 2.11), h1(float(INDEX) * 3.07));
}

void process() {
	float id = float(INDEX) * 1.618 + 0.5;
	vec4 sa = shape(mode_a, id);
	vec4 sb = shape(mode_b, id);
	float kk = smoothstep(0.0, 1.0, k);
	vec3 p = mix(sa.xyz, sb.xyz, kk);
	float fade = mix(sa.w, sb.w, kk);
	// the air: a curl noise field drifting through the storm swirls each petal off its line, and it flutters
	vec3 cn = curl(p * curl_freq + vec3(0.0, tclock * 0.35, tclock * 0.2));
	p += cn * curl_amp;
	float fl_ph = CUSTOM.w * TAU;
	p += vec3(sin(tclock * (4.0 + 3.0 * CUSTOM.x) + fl_ph), 0.5 * sin(tclock * (6.0 + 2.0 * CUSTOM.y) + fl_ph * 1.3), cos(tclock * (3.5 + 3.0 * CUSTOM.z) + fl_ph)) * 0.035;
	p.y = max(p.y, ground_y + 0.015 + 0.03 * CUSTOM.z);
	// the petal tumbles on its own axis, rocking as it goes (a falling petal swings, it does not spin like a coin)
	vec3 ax = normalize(vec3(CUSTOM.x - 0.5, CUSTOM.y - 0.5, CUSTOM.z - 0.5) + vec3(0.0, 0.3, 0.0));
	float spin = tclock * (2.0 + CUSTOM.y * 4.0) + CUSTOM.z * TAU + sin(tclock * (3.0 + 2.0 * CUSTOM.w) + fl_ph) * 1.1;
	mat3 rot = rot_axis(ax, spin);
	// sizes 0.5x to 2x, most of them small
	float sc = size * mix(0.5, 2.0, pow(CUSTOM.x, 2.2));
	bool on = CUSTOM.y < visible_frac && fade > 0.01;
	float spark = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(tclock * (5.0 + CUSTOM.z * 9.0) + CUSTOM.x * 40.0), 6.0);
	if (layer == 0) {
		TRANSFORM = mat4(vec4(rot[0] * sc, 0.0), vec4(rot[1] * sc, 0.0), vec4(rot[2] * sc, 0.0), vec4(p, 1.0));
		COLOR = vec4(spark, CUSTOM.w, fade, on ? 1.0 : 0.0);
	} else if (layer == 1) {
		// sparkles: tiny points riding the petals, twinkling hard
		float tw = pow(0.5 + 0.5 * sin(tclock * (9.0 + CUSTOM.z * 14.0) + CUSTOM.x * 60.0), 10.0);
		float s1 = size * (0.6 + 0.8 * CUSTOM.z) * (0.4 + 0.6 * tw);
		TRANSFORM = mat4(vec4(s1, 0, 0, 0), vec4(0, s1, 0, 0), vec4(0, 0, s1, 0), vec4(p + cn * 0.05, 1.0));
		COLOR = vec4(vec3(tw * fade), on ? 1.0 : 0.0);
	} else {
		// glow: soft light riding the petals (each sprite faint, so the glow builds where the swarm is densest)
		float s2 = size * (0.8 + 0.6 * CUSTOM.z);
		TRANSFORM = mat4(vec4(s2, 0, 0, 0), vec4(0, s2, 0, 0), vec4(0, 0, s2, 0), vec4(p, 1.0));
		COLOR = vec4(vec3(fade), on ? 1.0 : 0.0);
	}
	if (!on) {
		TRANSFORM[0].xyz = vec3(0.0);
		TRANSFORM[1].xyz = vec3(0.0);
		TRANSFORM[2].xyz = vec3(0.0);
	}
}
