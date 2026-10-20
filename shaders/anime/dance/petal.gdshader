shader_type spatial;
// A drifting blossom petal that glows softly (T2): a camera-facing petal with a little notch at its tip, blush pink at
// the base fading to white at the edge, turned by the particle's angle and tumbling (it narrows as it flips).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.72, 0.86, 1.0);
uniform float glow = 1.4;
varying float v_flip;

void vertex() {
	float ang = INSTANCE_CUSTOM.x;
	float flip = cos(TIME * 1.7 + INSTANCE_CUSTOM.w * 37.0 + float(INSTANCE_ID) * 1.3);
	v_flip = abs(flip);
	vec2 v = VERTEX.xy * vec2(0.5 + 0.5 * abs(flip), 1.0);
	v = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * v;
	float sc = length(MODEL_MATRIX[0].xyz);
	vec3 wp = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * sc;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	// a teardrop petal: narrow at the base, round and wide toward the tip, a small notch in the tip
	float y = 1.0 - UV.y;                                   // 0 base .. 1 tip
	float x = UV.x * 2.0 - 1.0;
	float w = 0.92 * pow(sin(3.14159 * clamp(y, 0.0, 1.0)), 0.7) * (0.45 + 0.55 * y);
	float d = abs(x) / max(w, 0.001);
	float notch = smoothstep(0.0, 0.1, abs(x) * 1.4 + (1.0 - y) * 1.1);
	float a = smoothstep(1.0, 0.78, d) * notch;
	if (a < 0.02) discard;
	vec3 col = mix(color.rgb, vec3(1.0, 0.9, 0.94), smoothstep(0.35, 1.0, max(d, y * 0.9)));
	ALBEDO = col * (0.75 + 0.25 * v_flip) * glow * COLOR.rgb;
	ALPHA = a * COLOR.a * 0.92;
}
