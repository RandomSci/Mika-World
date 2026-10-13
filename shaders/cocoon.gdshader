shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always, shadows_disabled, blend_mix;
// Transformation cocoon (original): ribbons of light spiral around the mage from the feet up (cover), seal
// for the moment the outfit changes, then unravel from the head down (reveal) with a soft, flowing edge.
// Heights: 0 = cocoon bottom (uniform `offset` maps the mesh's centred Y), `height` = top.

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.95, 1.0);
uniform vec4 accent : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float height = 1.95;
uniform float offset = 0.0;
uniform float cover = 0.0;        // 0..1: how far up the ribbons have wrapped
uniform float reveal_line = 2.2;  // above this the ribbons have unravelled
uniform float seal = 0.0;         // 0..1: the ribbons close into a nearly opaque shell (the outfit change)
uniform float energy = 1.15;

varying float ly;
varying vec3 lpos;

void vertex() {
	ly = VERTEX.y + offset;
	lpos = VERTEX;
}

void fragment() {
	float ang = atan(lpos.x, lpos.z);
	float a = sin(ang * 3.0 + ly * 6.5 - TIME * 2.6);
	float b = sin(-ang * 2.0 + ly * 5.0 + TIME * 1.9);
	float ribbon = smoothstep(0.35, 0.8, max(a, b));
	// a soft, flowing unravelling edge (no blocky noise)
	float edge_y = reveal_line + 0.07 * sin(ang * 7.0 + ly * 3.0 + TIME * 4.0) + 0.04 * sin(ang * 13.0 - TIME * 3.0);
	float wrapped = smoothstep(cover * height + 0.03, cover * height - 0.05, ly);
	float kept = smoothstep(edge_y + 0.02, edge_y - 0.03, ly);
	float edge = smoothstep(0.1, 0.0, abs(ly - edge_y)) * step(reveal_line, height);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	// the shell itself is only the brief luminous veil while the outfit changes (the ribbons do the rest)
	float fill = seal * (0.9 + 0.08 * ribbon);
	float alpha = clamp(fill * wrapped + rim * 0.4 * seal, 0.0, 1.0);
	if (alpha < 0.02) {
		discard;
	}
	// a soft veil of light: near-white, tinted at the rim, with a gentle rising shimmer (no stripes)
	float shimmer = 0.9 + 0.1 * sin(ly * 14.0 - TIME * 6.0 + ang * 2.0);
	vec3 col = mix(vec3(1.0), color.rgb, 0.35 + rim * 0.4);
	col = mix(col, accent.rgb, rim * 0.35);
	ALBEDO = col * energy * shimmer;
	ALPHA = alpha;
}
