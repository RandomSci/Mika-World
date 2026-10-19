// Combat v3 magic: the surface of a shaped spell body (an ice shard, a moon crescent, a conjured blade, a barrier) -
// a bright core where the surface faces the eye, soft glowing edges at grazing angles (no hard silhouette), energy
// flowing through it as scrolling noise, and a burn-dissolve (godotshaders.com "3D burn dissolve": a noise threshold
// with an emissive rim) that conjures it in (dissolve 1 -> 0, from `from_y` along the shape) and away (0 -> 1).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core : source_color = vec3(0.93, 0.98, 1.0);
uniform vec3 edge : source_color = vec3(0.32, 0.62, 1.0);
uniform float energy = 2.6;
uniform float dissolve = 0.0;              // 0 = whole, 1 = gone
uniform float along_bias = 0.6;            // how much the dissolve follows the shape's length (UV.y) vs pure noise
uniform float flow = 1.2;                  // speed of the energy running through it
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float n = texture(noise, vec2(UV.x * 2.0, UV.y * 1.5 - TIME * flow)).r;
	float n2 = texture(noise, vec2(UV.x * 5.0 + 0.31, UV.y * 4.0 + TIME * flow * 0.6)).r;
	// the conjure / vanish front runs along the shape, broken by noise
	float d = mix(n * 0.8 + n2 * 0.2, 1.0 - UV.y, along_bias);
	float keep = smoothstep(dissolve - 0.04, dissolve + 0.04, d);
	float burn = smoothstep(dissolve + 0.12, dissolve, d) * keep * step(0.001, dissolve) * step(dissolve, 0.999);
	float body = mix(0.25, 1.0, pow(facing, 1.4)) * (0.7 + 0.5 * n2);
	float a = clamp((body + burn * 2.5) * keep, 0.0, 1.0);
	vec3 c = mix(edge, core, pow(facing, 2.2));
	ALBEDO = (c * body + core * burn * 3.0) * energy * keep;
	ALPHA = a;
}
