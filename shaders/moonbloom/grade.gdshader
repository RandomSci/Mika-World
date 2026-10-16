shader_type canvas_item;
// Moonbloom cinematic grade (after tonemap + glow, full screen): everything pulled onto one deep saturated blue ramp
// with crushed rich blacks, only the brightest things (petals, moon, fireflies, rims) left cyan / white; some of the
// original hue kept in the mids so faces and gold still read. Vignette, subtle edge chromatic aberration, fine grain.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec3 shadow_col : source_color = vec3(0.0, 0.004, 0.022);
uniform vec3 mid_col : source_color = vec3(0.02, 0.15, 0.62);
uniform vec3 high_col : source_color = vec3(0.42, 0.78, 1.0);
uniform float black_point = 0.04;
uniform float white_point = 1.0;
uniform float keep_hue = 0.34;
uniform float saturation = 1.45;
uniform float vignette = 0.62;
uniform float aberration = 0.0035;
uniform float grain = 0.018;
uniform float lift_gamma = 1.0;
// a photographic backdrop plate composited BEHIND the 3D scene (the scene renders over a transparent background):
// shown raw - unlit, sharp, no DoF / bloom / grade / vignette - cover-fitted to the screen
uniform bool use_backdrop = false;
uniform bool use_scene_tex = false;           // the 3D scene comes from a SubViewport (transparent background)
uniform sampler2D scene_tex : filter_linear, repeat_disable;
uniform sampler2D backdrop : source_color, filter_linear_mipmap, repeat_disable;
uniform float backdrop_aspect = 1.7917;
uniform float screen_aspect = 1.7778;
uniform float meteor_energy = 0.0;            // > 0: an occasional shooting star across the backdrop's sky
uniform float char_real = 0.0;
// world-anchored plate: its painted horizon sits on the true horizon (elevation 0) whatever the camera does; it spans
// plate_span_h x plate_span_v degrees centred on plate_az and wraps mirrored beyond its edges
uniform bool plate_world = false;
uniform mat3 cam_basis = mat3(1.0);
uniform float tan_half_v = 0.45;
uniform float plate_az = 0.0;                 // radians, from north (-Z) toward east (+X)
uniform float plate_span_h = 2.5;             // radians
uniform float plate_span_v = 1.4;             // radians
uniform float plate_horizon_v = 0.715;        // the plate row that is the horizon                // 1: the characters keep their real (lit) colours, no grade at all            // < 1 opens the shadows (dark scenes read deep blue, not black)
// the characters alone, unlit (rgb = albedo, a = coverage), half resolution - their skin keeps its real tone
uniform sampler2D char_mask : filter_linear, repeat_disable, hint_default_transparent;
uniform float skin_keep = 1.0;
uniform float char_keep = 0.45;
uniform bool debug_skin = false;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 off = c * aberration * smoothstep(0.02, 0.35, r2) * 2.0;
	vec4 scr = use_scene_tex ? texture(scene_tex, uv) : texture(screen_tex, uv);
	vec3 col = use_scene_tex ? vec3(texture(scene_tex, uv + off).r, scr.g, texture(scene_tex, uv - off).b)
		: vec3(texture(screen_tex, uv + off).r, scr.g, texture(screen_tex, uv - off).b);
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float t = pow(clamp((l - black_point) / (white_point - black_point), 0.0, 1.0), lift_gamma);
	t = mix(t, t * t * (3.0 - 2.0 * t), 0.65);                         // S-curve: rich contrast
	vec3 ramp = t < 0.55 ? mix(shadow_col, mid_col, t / 0.55) : mix(mid_col, high_col, (t - 0.55) / 0.45);
	vec3 sat = max(mix(vec3(l), col, saturation), vec3(0.0));
	vec3 keep = sat * (t / max(l, 1e-4)) * 0.85;
	vec3 g = mix(ramp, keep, keep_hue);
	// the brightest things stay bright cyan / white
	g = mix(g, max(g, mix(col, high_col, 0.35)), smoothstep(0.82, 1.0, l));
	// characters: skin (warm albedo, light and moderately saturated) stays close to its real tone, bright and clean,
	// with only a soft cool tint in its shadows; the rest of them (hair, clothes) takes a lighter grade than the world
	vec4 cm = texture(char_mask, uv);
	float cover = cm.a;
	if (cover > 0.002) {
		vec3 a = cm.rgb;
		float mx = max(a.r, max(a.g, a.b));
		float mn = min(a.r, min(a.g, a.b));
		float s_ = (mx - mn) / max(mx, 1e-3);
		// skin and lips: red is the strongest channel and clearly above blue (peach, tan, pink)
		// (pale skin too: a faint warm cast is enough; lavender-tinted whites have blue >= red and stay out)
		float warm = smoothstep(0.0, 0.025, a.r - max(a.g, a.b) + 0.01) * smoothstep(0.012, 0.045, a.r - a.b);
		float skin = cover * warm * smoothstep(0.32, 0.5, mx) * smoothstep(0.015, 0.05, s_) * (1.0 - smoothstep(0.75, 0.9, s_));
		vec3 orig = scr.rgb;
		float lo = dot(orig, vec3(0.2126, 0.7152, 0.0722));
		vec3 cool = orig * mix(vec3(0.86, 0.92, 1.1), vec3(1.0), smoothstep(0.18, 0.55, lo));
		vec3 skin_col = cool * 1.04;
		vec3 char_col = mix(g, max(keep, vec3(0.0)) * 1.05, char_keep);
		g = mix(g, char_col, cover * (1.0 - skin));
		g = mix(g, skin_col, skin * skin_keep);
		g = mix(g, orig, cover * char_real);
		if (debug_skin) {
			g = mix(g, vec3(1.0, 0.0, 0.0), skin * 0.6);
			g = mix(g, vec3(0.0, 1.0, 0.0), cover * (1.0 - skin) * 0.25);
		}
	}
	g *= mix(1.0, 1.0 - vignette, smoothstep(0.08, 0.5, r2));
	float n = fract(sin(dot(uv * 1000.0 + fract(TIME * 7.13), vec2(12.9898, 78.233))) * 43758.5453);
	g += (n - 0.5) * grain * (0.4 + 0.6 * (1.0 - t));
	if (use_backdrop) {
		// premultiplied: opaque scene where it was drawn, the raw plate where it was not; additive fireflies and the
		// scene's own soft bloom stay on top of the plate
		vec2 buv = (uv - 0.5) * vec2(screen_aspect / backdrop_aspect, 1.0) + 0.5;
		if (plate_world) {
			vec3 ray = normalize(cam_basis * vec3((uv.x * 2.0 - 1.0) * tan_half_v * screen_aspect, (1.0 - uv.y * 2.0) * tan_half_v, -1.0));
			float az = atan(ray.x, -ray.z) - plate_az;
			az = mod(az + 3.14159265, 6.2831853) - 3.14159265;
			float el = asin(clamp(ray.y, -1.0, 1.0));
			float u = 0.5 + az / plate_span_h;
			float v = plate_horizon_v - el / plate_span_v;
			u = 1.0 - abs(fract(u * 0.5) * 2.0 - 1.0);           // mirrored wrap round the horizon
			v = v < 0.0 ? -v : (v > 1.0 ? 2.0 - v : v);            // mirrored above the plate's top
			buv = vec2(u, v);
		}
		vec3 plate;
		if (plate_world) {
			// full resolution (the plate is sharper than the screen): no mip jump at the mirrored folds
			plate = textureLod(backdrop, buv, 0.0).rgb;
		} else {
			plate = texture(backdrop, buv).rgb;
		}
		if (meteor_energy > 0.0) {
			float k = floor(TIME / 7.0);
			float ft = TIME - k * 7.0;
			if (ft < 0.8) {
				vec2 hs = fract(sin(vec2(k * 12.9898, k * 78.233)) * 43758.5453);
				vec2 a = vec2(mix(0.15, 0.85, hs.x), mix(0.08, 0.35, hs.y));
				vec2 dir = normalize(vec2(hs.x < 0.5 ? 1.0 : -1.0, 0.55));
				float pr = ft / 0.8;
				vec2 head = a + dir * 0.22 * pr;
				vec2 tl = head - dir * 0.07;
				vec2 q = uv * vec2(screen_aspect, 1.0);
				vec2 h2 = head * vec2(screen_aspect, 1.0);
				vec2 ab = (tl - head) * vec2(screen_aspect, 1.0);
				float tt = clamp(dot(q - h2, ab) / dot(ab, ab), 0.0, 1.0);
				float dd = length(q - (h2 + ab * tt));
				float fade = smoothstep(0.0, 0.15, pr) * (1.0 - smoothstep(0.6, 1.0, pr));
				plate += vec3(0.9, 0.93, 1.0) * fade * pow(1.0 - tt, 1.5) * exp(-dd * dd / 0.0000045) * meteor_energy;
			}
		}
		float a2 = clamp(scr.a, 0.0, 1.0);
		g = plate * (1.0 - a2) + g * a2 + max(g - vec3(0.006), vec3(0.0)) * (1.0 - a2);
	}
	COLOR = vec4(g, 1.0);
}
