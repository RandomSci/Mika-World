shader_type spatial;
// Ritual floor: photogrammetry stone with an engraved, original arcane circle.
// The engraving is real shading (darkened groove + bevelled normal), and fills with light
// as `charge` rises. `reveal` sweeps the glow outward from the centre during a cast.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D floor_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D breakup_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float floor_tiling = 0.32;
uniform float radius_m = 4.3;
uniform vec3 rune_color : source_color = vec3(0.35, 0.62, 1.0);
uniform vec3 rune_color_inner : source_color = vec3(0.72, 0.5, 1.0);
uniform float idle_glow = 0.22;
uniform float charge = 0.0;
uniform float reveal = 1.0;
uniform float spin_speed = 0.02;
uniform float glyph_seed = 3.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Distance (in metres) to the nearest engraved line.
float rune_dist(vec2 p, float t) {
	float r = length(p);
	float a = atan(p.y, p.x);
	float d = 1e3;
	// concentric bands
	d = min(d, abs(r - 4.05));
	d = min(d, abs(r - 3.78));
	d = min(d, abs(r - 3.0));
	d = min(d, abs(r - 2.82));
	d = min(d, abs(r - 1.25));
	d = min(d, abs(r - 0.55));
	// glyph band between 3.78 and 4.05: 40 cells, each with hash-chosen strokes
	{
		float cells = 40.0;
		float aa = (a + t) / 6.2831853 * cells;
		float ci = floor(aa);
		float u = fract(aa);
		float v = (r - 3.8) / 0.23;
		if (v > 0.0 && v < 1.0) {
			float h = hash12(vec2(ci, glyph_seed));
			float h2 = hash12(vec2(ci, glyph_seed + 7.0));
			float arc = 6.2831853 * 3.92 / cells; // metres per cell
			vec2 q = vec2((u - 0.5) * arc, (v - 0.5) * 0.23);
			float g = 1e3;
			g = min(g, seg_dist(q, vec2(0.0, -0.08), vec2(0.0, 0.08)));
			if (h > 0.3) g = min(g, seg_dist(q, vec2(-0.09, 0.06), vec2(0.09, 0.06)));
			if (h > 0.6) g = min(g, seg_dist(q, vec2(-0.09, -0.07), vec2(0.06, 0.04)));
			if (h2 > 0.5) g = min(g, abs(length(q - vec2(0.0, -0.02)) - 0.045));
			if (h2 < 0.35) g = min(g, seg_dist(q, vec2(-0.09, -0.06), vec2(-0.09, 0.06)));
			if (fract(h * 7.0) > 0.55) g = min(g, seg_dist(q, vec2(0.05, -0.08), vec2(0.1, -0.02)));
			d = min(d, g);
		}
	}
	// small dots between the 2.82/3.0 bands
	{
		float cells = 24.0;
		float aa = (a - t * 1.5) / 6.2831853 * cells;
		float u = fract(aa) - 0.5;
		float arc = 6.2831853 * 2.91 / cells;
		vec2 q = vec2(u * arc, r - 2.91);
		d = min(d, abs(length(q) - 0.035));
	}
	// hexagram (two interlocked triangles) inscribed in r=2.82
	for (int k = 0; k < 6; k++) {
		float a0 = float(k) * 1.0471976 + t * 0.5;
		vec2 v0 = 2.82 * vec2(cos(a0), sin(a0));
		vec2 v1 = 2.82 * vec2(cos(a0 + 2.0943951), sin(a0 + 2.0943951));
		d = min(d, seg_dist(p, v0, v1));
	}
	// radial spokes from 1.25 to 2.0 (8)
	{
		float sa = mod(a - t * 0.5 + 0.3927, 0.7854) - 0.3927;
		if (r > 1.25 && r < 2.1) d = min(d, abs(sa * r));
	}
	// inner square rotated
	{
		float ia = a + t * 2.0;
		vec2 ip = r * vec2(cos(ia), sin(ia));
		vec2 q = abs(ip);
		d = min(d, abs(max(q.x, q.y) - 0.9));
	}
	return d;
}

void fragment() {
	vec2 p = wpos.xz - (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	float t = TIME * spin_speed;
	vec2 fuv = wpos.xz * floor_tiling;
	vec3 alb = texture(floor_albedo, fuv).rgb;
	float rough = texture(floor_rough, fuv).r;
	float ao = texture(floor_ao, fuv).r;
	vec3 nt = texture(floor_normal, fuv).xyz * 2.0 - 1.0;

	float px = max(fwidth(length(p)), 0.002);
	float width = 0.026;
	float d = rune_dist(p, t);  // single evaluation per pixel
	float groove = 1.0 - smoothstep(width - px, width + px, d);
	// cut-wall shading from screen-space derivatives of the distance (no extra SDF evaluations)
	vec2 dp_dx = dFdx(p), dp_dy = dFdy(p);
	float dd_dx = dFdx(d), dd_dy = dFdy(d);
	float det = dp_dx.x * dp_dy.y - dp_dx.y * dp_dy.x;
	vec2 grad = abs(det) > 1e-9 ? vec2(dd_dx * dp_dy.y - dd_dy * dp_dx.y, dd_dy * dp_dx.x - dd_dx * dp_dy.x) / det : vec2(0.0);
	float wall = smoothstep(width + 0.02, width, d) * smoothstep(0.0, width * 0.6, d);
	nt.xy += -clamp(grad, vec2(-1.0), vec2(1.0)) * wall * 0.8;

	// moss creeping into the outer floor and weathering the carving
	float nz = texture(breakup_noise, wpos.xz * 0.06).r;
	float moss = smoothstep(0.62, 0.8, nz + length(p) / radius_m * 0.25) * 0.75;
	alb = mix(alb, texture(moss_albedo, wpos.xz * 0.7).rgb * vec3(0.85, 0.95, 0.7), moss * (1.0 - groove));

	// grooves: darker, rougher, slightly occluded
	alb *= mix(1.0, 0.38, groove);
	rough = mix(rough, 0.95, groove);
	ao *= mix(1.0, 0.55, groove);

	float r = length(p);
	float reveal_mask = 1.0 - smoothstep(reveal * radius_m - 0.4, reveal * radius_m + 0.05, r);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2 - r * 1.6);
	vec3 col = mix(rune_color_inner, rune_color, smoothstep(1.0, 3.5, r));
	float energy = idle_glow + charge * 5.5 * reveal_mask * pulse;
	float soft = exp(-d * d / (0.0045 + charge * 0.003)) * 0.35; // halo bleeding out of the groove
	ALBEDO = alb;
	ROUGHNESS = rough;
	AO = ao;
	NORMAL_MAP = normalize(nt) * 0.5 + 0.5;
	EMISSION = col * (groove + soft) * energy;
}
