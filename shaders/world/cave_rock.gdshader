// CAVE ROCK (Crystal Caverns): walls and ceilings from photoscanned rock, triplanar (no stretching on any face),
// two scales mixed against tiling, darker and wet-glossy where water seeps (noise bands running down), mineral
// tint near crystals, and vertex alpha = depth under the rock (the sky's ambient light does not reach in).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float tile = 0.22;
uniform vec4 tone : source_color = vec4(0.62, 0.62, 0.64, 1.0);
uniform vec4 mineral : source_color = vec4(0.3, 0.6, 0.75, 1.0);
uniform float wet = 0.45;

varying vec3 v_wp;
varying vec3 v_wn;
varying float v_occ;
varying float v_min;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_occ = COLOR.a;
	v_min = COLOR.b;
}

vec3 tri_a(vec3 p, vec3 w) {
	return texture(rock_alb, p.zy).rgb * w.x + texture(rock_alb, p.xz).rgb * w.y + texture(rock_alb, p.xy).rgb * w.z;
}

vec3 tri_n(vec3 p, vec3 w) {
	return texture(rock_nrm, p.zy).rgb * w.x + texture(rock_nrm, p.xz).rgb * w.y + texture(rock_nrm, p.xy).rgb * w.z;
}

void fragment() {
	vec3 w = pow(abs(v_wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_wp * tile;
	vec3 a = mix(tri_a(p, w), tri_a(p * 0.37 + 0.3, w), 0.4);
	vec3 n = tri_n(p, w);
	float seep = smoothstep(0.55, 0.75, texture(noise_tex, vec2(v_wp.x * 0.05 + v_wp.z * 0.03, v_wp.y * 0.012)).r);
	float var_ = texture(noise_tex, v_wp.xz * 0.02 + v_wp.y * 0.01).r;
	vec3 col = a * tone.rgb * (0.8 + 0.4 * var_);
	col = mix(col, col * 0.55, seep * wet);
	col = mix(col, col * mineral.rgb * 1.6, v_min * 0.5);
	ALBEDO = col;
	NORMAL_MAP = n;
	ROUGHNESS = mix(0.85, 0.25, seep * wet);
	SPECULAR = 0.5;
	AO = 1.0 - v_occ * 0.97;
	AO_LIGHT_AFFECT = 0.0;
}
