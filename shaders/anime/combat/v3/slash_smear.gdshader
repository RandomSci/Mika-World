// Combat v3 magic: the swept crescent slash of the reference fights (Download(5) 26-37 s): a ring sector swept around
// its centre. UV.x runs along the arc (0 = where the sweep began, 1 = where it ends), UV.y across it (0 = inner edge,
// 1 = outer edge). `head` (0..1.3) is where the sweep has reached: ahead of it nothing, at it a white-hot leading edge,
// behind it a glassy translucent smear streaked along the arc, fading over `tail` of the arc; the outer rim stays
// bright (a thin hot line), the inner edge dissolves into soft wisps. Additive, unshaded: it only adds light.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 edge : source_color = vec3(0.35, 0.62, 1.0);
uniform float energy = 3.0;
uniform float head = 0.0;
uniform float tail = 0.55;
uniform float fade = 1.0;
uniform float rim = 0.18;               // how thick the bright outer rim is (fraction of the width)
uniform float rim_gain = 1.0;           // 0 = a soft wisp (no hard edge, no hot leading line): the swirling vapour ribbons
uniform float softness = 0.0;           // 1 = the whole band is soft vapour (fades at both edges)
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float behind = head - x;                                   // >0 behind the leading edge
	float lead = smoothstep(0.035, 0.0, abs(behind)) * step(-0.02, behind);
	float body = smoothstep(tail, 0.0, behind) * step(0.0, behind);
	// streaks running along the arc, stretched by the sweep
	float s1 = texture(noise, vec2(x * 1.2 - head * 0.6, y * 7.0)).r;
	float s2 = texture(noise, vec2(x * 3.5 + 0.21, y * 15.0 - head)).r;
	float streak = smoothstep(0.35, 0.8, s1 * 0.65 + s2 * 0.35);
	float outer = smoothstep(1.0 - rim, 1.0, y) * smoothstep(1.0, 0.985, y);
	float inner = smoothstep(0.0, 0.55, y);
	float wisp = smoothstep(0.25, 0.75, s2 + y * 0.4);
	float band_soft = mix(1.0, smoothstep(0.0, 0.5, y) * smoothstep(1.0, 0.5, y), softness);
	float glass = body * inner * wisp * (0.22 + 0.55 * streak) * band_soft;
	float hot = (body * outer * (0.6 + 0.4 * streak) + lead * (0.4 + 0.6 * y)) * rim_gain;
	float a = clamp((glass + hot * 1.6) * fade, 0.0, 1.0);
	vec3 c = mix(edge, core, clamp(hot * 1.4 + y * 0.25, 0.0, 1.0));
	ALBEDO = c * energy * a;
	ALPHA = a;
}
