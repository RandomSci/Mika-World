shader_type spatial;
render_mode diffuse_lambert_wrap;
// Stylized terrain for the Whispering Woods (Milestone K, original). Painted palette first, texture second:
// the Poly Haven textures only contribute their LUMINANCE as fine detail, so colours stay art-directed and match
// the stylized trees. Vertex COLOR: r = trail (dirt), g = forest floor (moss / leaf litter), b = riverbank /
// wet ground, a = sanctuary lawn (manicured). Cliffs come from the slope (triplanar rock). Large soft colour
// patches keep meadows from looking like a flat carpet.

uniform sampler2D grass_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

uniform vec4 grass_a : source_color = vec4(0.42, 0.62, 0.23, 1.0);
uniform vec4 grass_b : source_color = vec4(0.56, 0.72, 0.30, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.70, 0.70, 0.36, 1.0);
uniform vec4 forest_a : source_color = vec4(0.22, 0.33, 0.16, 1.0);
uniform vec4 forest_b : source_color = vec4(0.36, 0.30, 0.18, 1.0);
uniform vec4 dirt_a : source_color = vec4(0.58, 0.46, 0.32, 1.0);
uniform vec4 dirt_b : source_color = vec4(0.70, 0.60, 0.44, 1.0);
uniform vec4 bank_col : source_color = vec4(0.36, 0.34, 0.26, 1.0);
uniform vec4 rock_a : source_color = vec4(0.40, 0.39, 0.35, 1.0);
uniform vec4 rock_b : source_color = vec4(0.56, 0.53, 0.46, 1.0);
uniform vec4 lawn_col : source_color = vec4(0.48, 0.70, 0.30, 1.0);
uniform vec4 moss_col : source_color = vec4(0.32, 0.46, 0.20, 1.0);
uniform float detail_scale = 0.35;
uniform float detail_strength = 0.35;
uniform float cliff_start = 0.72;     // normal.y below this begins to show rock
uniform float cliff_end = 0.55;

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

vec3 triplanar_lum(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float a = lum(texture(t, p.zy * s).rgb);
	float b = lum(texture(t, p.xz * s).rgb);
	float c = lum(texture(t, p.xy * s).rgb);
	return vec3(a * w.x + b * w.y + c * w.z);
}

void fragment() {
	vec2 uv = v_wp.xz;
	float n1 = texture(noise_tex, uv * 0.012).r;       // big soft patches
	float n2 = texture(noise_tex, uv * 0.06 + 3.1).r;  // medium breakup
	float n3 = texture(noise_tex, uv * 0.23 + 7.7).r;  // small
	// meadow: two greens + dry patches
	vec3 grass = mix(grass_a.rgb, grass_b.rgb, smoothstep(0.35, 0.7, n1));
	grass = mix(grass, grass_dry.rgb, smoothstep(0.62, 0.82, n2) * 0.45);
	float gd = lum(texture(grass_detail, uv * detail_scale).rgb);
	grass *= 1.0 + (gd - 0.45) * detail_strength * 1.6;
	// forest floor: moss and leaf litter
	vec3 forest = mix(forest_a.rgb, forest_b.rgb, smoothstep(0.4, 0.75, n2));
	forest *= 1.0 + (gd - 0.45) * detail_strength;
	// trail
	float dd = lum(texture(dirt_detail, uv * detail_scale * 1.3).rgb);
	vec3 dirt = mix(dirt_a.rgb, dirt_b.rgb, smoothstep(0.3, 0.8, n3)) * (1.0 + (dd - 0.45) * detail_strength * 1.8);
	vec3 col = grass;
	col = mix(col, lawn_col.rgb * (1.0 + (gd - 0.45) * 0.2), COLOR.a);
	col = mix(col, forest, smoothstep(0.0, 1.0, COLOR.g));
	col = mix(col, bank_col.rgb * (0.9 + dd * 0.2), smoothstep(0.0, 1.0, COLOR.b));
	// trail with a soft, broken edge
	float tr = smoothstep(0.25 + (n3 - 0.5) * 0.35, 0.75, COLOR.r);
	col = mix(col, dirt, tr);
	// cliffs from slope (triplanar rock), moss on rock ledges
	float steep = 1.0 - smoothstep(cliff_end, cliff_start, v_wn.y);
	vec3 rd = triplanar_lum(rock_detail, v_wp, v_wn, 0.18);
	vec3 rock = mix(rock_a.rgb, rock_b.rgb, smoothstep(0.3, 0.7, n2)) * (0.75 + rd * 0.55);
	// vertical streaks (water staining) and moss on ledges
	float streak = texture(noise_tex, vec2(v_wp.x * 0.12 + v_wp.z * 0.12, v_wp.y * 0.015)).r;
	rock *= 0.92 + smoothstep(0.3, 0.7, streak) * 0.12;
	rock = mix(rock, moss_col.rgb * 0.9, smoothstep(0.5, 0.68, v_wn.y + (n3 - 0.5) * 0.35) * 0.75);
	col = mix(col, rock, steep);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.85, tr);
}
