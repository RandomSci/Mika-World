// A real leaf torn loose by a gust (WindFX): one of six scanned beech/hazel leaves (ambientCG LeafSet009, CC0),
// picked per particle, tumbling about its own random axis (true 3D tumble, not a billboard), lit through from
// behind; the particle colour tints it (fresh green to autumn brown) and its alpha dissolves it out.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float spin = 5.0;

varying vec4 v_col;

float h1(float n) {
	return fract(sin(n * 12.9898 + 4.1) * 43758.5453);
}

vec3 rot(vec3 v, vec3 ax, float a) {
	float c = cos(a);
	float s = sin(a);
	return v * c + cross(ax, v) * s + ax * dot(ax, v) * (1.0 - c);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 ax = normalize(vec3(h1(id) - 0.5, h1(id + 3.1) - 0.5, h1(id + 7.7) - 0.5) + vec3(0.0001));
	float a = TIME * spin * (0.45 + h1(id + 1.3)) + h1(id + 9.1) * 6.2831853;
	VERTEX = rot(VERTEX, ax, a);
	NORMAL = rot(NORMAL, ax, a);
	float cell = floor(h1(id + 5.5) * 5.999);
	UV = (UV + vec2(mod(cell, 3.0), floor(cell / 3.0))) / vec2(3.0, 2.0);
	v_col = COLOR;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	float dither = fract(dot(FRAGCOORD.xy, vec2(0.0671, 0.00583)) * 52.9829);
	if (t.a < 0.5 || v_col.a < dither) {
		discard;
	}
	vec3 c = t.rgb * v_col.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.72;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.55;
}
