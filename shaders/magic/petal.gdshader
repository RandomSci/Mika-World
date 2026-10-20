// One petal of the petal storm (Selwyn's look notes 2026-10-20): a sakura petal (a rounded teardrop, the notch at its
// tip) with soft edges, unshaded and alpha blended. Its colour runs from a pale pink core to a white edge; one petal in
// five is a deeper pink, a few are white. It glows (brighter than white at the heart, so the bloom picks it up), a thin
// rim in the girl's own colour (ice blue Mika, violet Luna) catching the light as it turns. Seen from both sides.
// COLOR in from the storm: r sparkle, g colour variant, b life fade, a shown.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, unshaded, shadows_disabled;

uniform vec3 petal : source_color = vec3(1.0, 0.72, 0.84);       // the pale pink core
uniform vec3 deep : source_color = vec3(0.98, 0.42, 0.66);       // the deeper pink petals
uniform vec3 edge_col : source_color = vec3(1.0, 0.96, 0.98);    // the white edge
uniform vec3 rim : source_color = vec3(0.6, 0.85, 1.0);
uniform float glow = 1.6;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;                     // -1..1, the petal's base at y = 1, its tip at y = -1
	float y = q.y;
	// the petal's half width along its length: round at the base, narrowing to the tip
	float w = 0.62 * sqrt(clamp(1.0 - pow((y - 0.15) / 1.15, 2.0), 0.0, 1.0)) * (0.55 + 0.45 * smoothstep(-1.0, 0.4, -y));
	float d = abs(q.x) - w;
	float notch = smoothstep(0.2, 0.06, length(vec2(q.x, y + 0.98)));
	// soft edges (the alpha falls off over the last part of the width, no cut-out stair steps)
	float body = (1.0 - smoothstep(-0.16, 0.02, d)) * smoothstep(-1.0, -0.9, y) * (1.0 - smoothstep(0.92, 1.0, y)) * (1.0 - notch);
	// a petal right in front of the lens fades out (a close shot never fills with petals)
	float near_k = smoothstep(0.7, 1.8, length(VERTEX));
	float a = body * near_k * COLOR.b * COLOR.a;
	if (a < 0.01) {
		discard;
	}
	float edge = smoothstep(-0.3, 0.0, d);
	float core = 1.0 - smoothstep(0.0, 0.85, length(vec2(q.x * 1.3, y - 0.3)));
	float v = COLOR.g;
	vec3 base = v < 0.2 ? deep : (v > 0.88 ? edge_col : petal);
	vec3 col = mix(base, edge_col, edge * 0.75);
	col = mix(col, rim, smoothstep(-0.06, 0.0, d) * 0.35);
	// the glow: the heart above white for the bloom, more as the petal catches the light (sparkle)
	float spark = COLOR.r;
	ALBEDO = col * (0.9 + core * glow * (0.5 + spark));
	ALPHA = a * (0.85 + 0.15 * core);
}
