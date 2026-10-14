// The fire core of Oriel's transformation: a sphere of living flame (scrolling noise through a fresnel shell),
// additive, brighter toward the centre and the top. `power` scales it from a glow to a blaze.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 inner : source_color = vec3(1.0, 0.92, 0.7);
uniform vec3 outer : source_color = vec3(1.0, 0.4, 0.08);
uniform float power = 1.0;
uniform float speed = 1.4;

varying vec3 nrm;
varying vec3 vpos;

void vertex() {
	nrm = NORMAL;
	vpos = VERTEX;
	float n = texture(noise_tex, vec2(atan(VERTEX.x, VERTEX.z) * 0.16 + TIME * 0.05, VERTEX.y * 0.35 - TIME * speed * 0.3)).r;
	VERTEX += NORMAL * (n - 0.5) * 0.18 * power;
}

void fragment() {
	vec3 v = normalize(VIEW);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), v), 0.0, 1.0), 1.6);
	vec2 uv = vec2(atan(vpos.x, vpos.z) * 0.16, vpos.y * 0.5 - TIME * speed);
	float n1 = texture(noise_tex, uv).r;
	float n2 = texture(noise_tex, uv * 2.3 + vec2(0.3, TIME * speed * 0.7)).r;
	float flame = clamp(n1 * 0.7 + n2 * 0.5 - 0.25 + vpos.y * 0.25, 0.0, 1.0);
	float core = (1.0 - fres) * 0.9 + 0.35;
	vec3 col = mix(outer, inner, core * flame) * (0.6 + 1.6 * flame) * power;
	ALBEDO = col * (0.35 + fres * 1.2 + flame * 0.8);   // unshaded: ALBEDO is the output (HDR)
	ALPHA = clamp((flame * 0.9 + fres * 0.6) * power, 0.0, 1.0);
}
