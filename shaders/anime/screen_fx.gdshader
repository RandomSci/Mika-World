shader_type canvas_item;
// The anime screen-effect stack (2026-10-18), one full-screen pass, driven by scripts/fx/screen_fx.gd.
// Every effect is built from a reference frame (~/Downloads/Anime_Reference_Breakdown.md):
//  * flash frames: white / black-with-burst / inverted (v4 22.2-23.3 s, v5 22.3-22.5 s, v3 4.3 s)
//  * speed lines: radial streaks toward a vanishing point, posterized (v4 19.5 s, v6 14.4 s; technique after
//    ProfesorShader's CC0 "Anime Style Speedlines", shaders/anime/ref)
//  * zoom blur: radial blur from a centre (v4 14.5 s, v3 12.5 s)
//  * chromatic aberration: radial RGB split, strongest at the edges (v4 23.2 s)
//  * colour wash: a full-frame colour grade toward one hue (v3 15-25 s red, v5 violet sky); wash_hi takes the
//    highlights to a second colour (2026-10-20, the ultimates' colour takeover: Mika pink and white, Luna violet and gold)
//  * inverted black and white impact frame (flash_mode 5): the image's light inverted and cut to two tones
//  * lens flare (2026-10-20, an ultimate's release): a long anamorphic streak through a hot core at flare_pos, a soft
//    halo and a row of ghosts mirrored through the frame's centre
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform vec2 center = vec2(0.5, 0.5);          // vanishing point / blur centre (UV)
uniform float speed_lines = 0.0;               // 0..1
uniform vec3 speed_line_color : source_color = vec3(1.0);
uniform float speed_line_density = 90.0;       // streaks around the circle
uniform float zoom_blur = 0.0;                 // 0..1 (length of the radial smear)
uniform float chroma = 0.0;                    // 0..1 (RGB split at the edges, up to ~1.6% of the screen)
uniform vec4 wash : source_color = vec4(1.0, 0.1, 0.2, 0.0);   // rgb = colour, a = strength
uniform float wash_keep_luma = 0.75;           // a wash keeps the image's light and dark (a grade, not a fill)
uniform int flash_mode = 0;                    // 0 none, 1 white, 2 black + white burst, 3 inverted, 4 white + dark burst
uniform float flash = 0.0;                     // 0..1
uniform float burst_seed = 0.0;
uniform float burst_angle = 0.6;               // the burst's main smear direction (radians)
uniform float vignette = 0.0;
uniform vec3 wash_hi : source_color = vec3(1.0, 0.92, 0.95);
uniform float wash_split = 0.0;                // 1: the two-tone grade multiplies the image (keeps its contrast and colours)
uniform float flare = 0.0;                     // 0..1
uniform vec2 flare_pos = vec2(0.5, 0.5);       // UV
uniform vec3 flare_col : source_color = vec3(1.0, 0.8, 0.9);

float hash11(float p) { return fract(sin(p * 127.1) * 43758.5453); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// angular noise: many thin streaks, each with its own length and brightness
float streaks(vec2 uv, float density, float t, float seed, float aspect) {
	vec2 d = uv - center;
	d.x *= aspect;     // round, not stretched to the screen's aspect
	float ang = atan(d.y, d.x) / 6.28318 + 0.5;
	float r = length(d);
	float cell = floor(ang * density);
	float f = fract(ang * density);
	float h = hash11(cell + seed * 13.0);
	float width = mix(0.08, 0.35, hash11(cell + 7.3 + seed));
	float line = smoothstep(width, 0.0, abs(f - 0.5) * 2.0);
	float start = mix(0.12, 0.42, h);                     // a clear centre, streaks from the edges inward
	float flicker = step(0.35, hash11(cell + floor(t * 24.0) * 3.1 + seed));   // 24 fps redraw, anime-style
	return line * smoothstep(start, start + 0.12, r) * flicker * mix(0.5, 1.0, hash11(cell + 2.7));
}

// value noise along one axis (for jagged spike edges)
float vnoise(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash11(i), hash11(i + 1.0), f); }

// a jagged impact burst (the black / white impact frames, v4 22.2 / 22.8 s, v5 22.3 s): hard-edged, asymmetric.
// One dominant wedge along burst_angle (the hit's direction) reaching past the frame, ragged spikes of very
// different lengths around it, a hot core and scattered spark fragments. No soft gradients: anime impact frames
// are two-tone.
float burst(vec2 uv, float seed, float aspect) {
	vec2 d = uv - center;
	d.x *= aspect;
	float ang = atan(d.y, d.x);
	float r = length(d);
	// the wedge: within ~25 deg of the hit direction (and a weaker one opposite), reaching 1.5 frames
	float da = abs(mod(ang - burst_angle + 3.14159, 6.28318) - 3.14159);
	float db = abs(mod(ang - burst_angle, 6.28318) - 3.14159);
	float edge_jag = (vnoise(r * 38.0 + seed * 7.0) - 0.5) * 0.09 + (vnoise(r * 140.0 + seed) - 0.5) * 0.03;
	float wedge = step(da + edge_jag, 0.30 * (1.0 - r * 0.35)) * step(r, 1.6);
	float wedge2 = step(db + edge_jag, 0.16 * (1.0 - r * 0.6)) * step(r, 0.75);
	// ragged spikes: angular cells, each with its own length; the edge jitters along the radius
	float a = ang / 6.28318 + 0.5;
	float spikes = 0.0;
	for (int k = 0; k < 2; k++) {
		float n = 26.0 + float(k) * 41.0;
		float c = floor(a * n);
		float f = fract(a * n);
		float h = hash11(c + seed * 5.0 + float(k) * 17.0);
		float len = h * h * 0.75 + 0.05;
		float width = mix(0.08, 0.42, hash11(c + 3.3 + seed)) * (1.0 - r / max(len, 0.01));
		spikes = max(spikes, step(abs(f - 0.5) * 2.0, width) * step(r, len));
	}
	float core = step(r + (vnoise(ang * 9.0 + seed) - 0.5) * 0.05, 0.07);
	// spark fragments: small cells far out, a few lit
	vec2 cell = floor(d * 34.0);
	float spark = step(0.985, hash21(cell + seed)) * step(0.25, r) * step(r, 0.9) * step(length(fract(d * 34.0) - 0.5), 0.22);
	return clamp(max(max(wedge, wedge2), max(max(spikes, core), spark)), 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 dir = uv - center;
	// zoom blur (radial smear toward the centre) with the chromatic split folded in
	vec3 col = vec3(0.0);
	float taps = zoom_blur > 0.001 ? 12.0 : 1.0;
	float ca = chroma * 0.016 * length(dir) * 2.0;
	for (float i = 0.0; i < 12.0; i += 1.0) {
		if (i >= taps) break;
		float s = 1.0 - zoom_blur * 0.22 * (i / 11.0);
		vec2 p = center + dir * s;
		col.r += texture(screen_tex, center + (p - center) * (1.0 + ca)).r;
		col.g += texture(screen_tex, p).g;
		col.b += texture(screen_tex, center + (p - center) * (1.0 - ca)).b;
	}
	col /= taps;
	// colour wash: tint toward the colour keeping some of the luminance structure
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 hot = mix(wash.rgb, wash_hi, 0.55);
	vec3 washed = mix(wash.rgb * 0.18, hot * 1.15, smoothstep(0.05, 0.75, luma));
	washed = mix(washed, wash.rgb * luma * 2.0 + col * 0.15, 1.0 - wash_keep_luma);
	// (the ultimates' grade: split toning, shadows toward wash, highlights toward wash_hi, multiplied so the image keeps
	// its own contrast; the plain wash replaced the image's colours and turned the frame milky)
	vec3 split = col * mix(wash.rgb * 1.25 + 0.25, wash_hi * 1.15, smoothstep(0.08, 0.7, luma));
	washed = mix(washed, split, wash_split);
	col = mix(col, washed, wash.a);
	// speed lines (additive, posterized: hard anime streaks, no soft gradient)
	float sl = streaks(uv, speed_line_density, TIME, burst_seed, aspect);
	col = mix(col, speed_line_color, step(0.5, sl) * speed_lines);
	// lens flare (added light)
	if (flare > 0.001) {
		vec2 fd = uv - flare_pos;
		fd.x *= aspect;
		float core = exp(-length(fd) * 22.0);
		float halo = exp(-length(fd) * 9.0) * 0.18;
		float streak = exp(-abs(fd.y) * 160.0) * exp(-abs(fd.x) * 2.2);
		float streak2 = exp(-abs(fd.y) * 40.0) * exp(-abs(fd.x) * 6.0) * 0.4;
		vec3 fl = flare_col * (core * 2.5 + halo + streak * 1.4 + streak2) + vec3(1.0) * core * 1.5;
		// ghosts along the line from the flare through the centre
		vec2 axis = vec2(0.5) - flare_pos;
		for (int g = 0; g < 4; g++) {
			float k = (g == 0) ? 0.55 : ((g == 1) ? 0.9 : ((g == 2) ? 1.35 : 1.7));
			vec2 gp = flare_pos + axis * k * 2.0;
			vec2 gd = uv - gp;
			gd.x *= aspect;
			float rad = 0.02 + 0.025 * float(g);
			float ring = smoothstep(rad, rad * 0.7, length(gd)) * 0.12 + smoothstep(rad * 1.05, rad, length(gd)) * smoothstep(rad * 0.8, rad, length(gd)) * 0.18;
			fl += mix(flare_col, vec3(0.6, 0.8, 1.0), float(g) / 3.0) * ring;
		}
		col += fl * flare;
	}
	// vignette
	col *= 1.0 - vignette * smoothstep(0.3, 0.85, length(dir * vec2(1.0, 0.8)));
	// flash frames
	if (flash_mode == 1) {
		col = mix(col, vec3(1.0), flash);
	} else if (flash_mode == 2) {
		vec3 f = mix(vec3(0.02, 0.02, 0.03), vec3(1.0), burst(uv, burst_seed, aspect));
		col = mix(col, f, flash);
	} else if (flash_mode == 3) {
		col = mix(col, vec3(1.0) - col, flash);
	} else if (flash_mode == 5) {
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(1.0 - smoothstep(0.32, 0.4, lum)), flash);
	} else if (flash_mode == 4) {
		vec3 f = mix(vec3(0.97), vec3(0.04, 0.05, 0.08), burst(uv, burst_seed, aspect));
		col = mix(col, f, flash);
	}
	COLOR = vec4(col, 1.0);
}
