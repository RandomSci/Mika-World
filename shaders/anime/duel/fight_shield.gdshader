shader_type spatial;
// A spell shield (a curved disc of light in front of the defender): fresnel rim, a hexagon lattice, a flash where it
// is struck and cracks (Voronoi edges) that spread from the strike point as `crack` rises 0..1. HDR + additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.7, 0.5, 1.0, 1.0);
uniform float energy = 1.6;
uniform float crack = 0.0;
uniform vec3 hit_local = vec3(0.0, 0.0, 1.0);
uniform float hit_flash = 0.0;
uniform float fade = 1.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg, mr;
	float md = 8.0;
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j));
		vec2 o = hash2(n + g);
		vec2 r = g + o - f;
		float d = dot(r, r);
		if (d < md) { md = d; mr = r; mg = g; }
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
		vec2 g = mg + vec2(float(i), float(j));
		vec2 o = hash2(n + g);
		vec2 r = g + o - f;
		if (dot(mr - r, mr - r) > 0.00001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
	}
	return md;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	vec2 h = lp.xy * 9.0;
	vec2 hx = vec2(h.x * 1.1547, h.y + h.x * 0.57735);
	vec2 fh = fract(hx) - 0.5;
	float hexl = smoothstep(0.42, 0.5, max(abs(fh.x), abs(fh.y)));
	float dist = length(lp - hit_local);
	float spread = crack * 1.4;
	float e = voronoi_edge(lp.xy * 5.0 + 3.0);
	float cr = (1.0 - smoothstep(0.0, 0.035, e)) * smoothstep(spread, spread - 0.25, dist) * step(0.01, crack);
	float flash = hit_flash * exp(-dist * dist * 10.0);
	vec3 col = color.rgb * (0.18 + fres * 1.3 + hexl * 0.35) + vec3(1.0) * cr * 2.6 + mix(color.rgb, vec3(1.0), 0.6) * flash * 3.0;
	ALBEDO = clamp(col * energy * fade, vec3(0.0), vec3(64.0));   // (never a NaN into the glow pass)
}
