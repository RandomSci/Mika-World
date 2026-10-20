// Character look prototype (test only): the light comes from the character light rig (look_rig in the look lab), not
// from the world's lights, so she reads the same in day, dusk, night and the dark forest. Every material is unshaded
// and lights itself from these uniforms, which the rig sets every frame.
uniform vec3 key_dir = vec3(0.3, 0.7, 0.6);              // world, toward the key light
uniform vec3 key_color : source_color = vec3(1.0);
uniform float key_energy = 0.9;
uniform vec3 ambient_color : source_color = vec3(0.3);
uniform vec3 rim_color : source_color = vec3(1.0);
uniform float rim_strength = 0.3;
uniform float night = 0.0;                                // 1 = the night rows of the ramp
uniform sampler2D ramp_tex : source_color, filter_linear, repeat_disable;

vec3 look_ramp(float lit, float row) {
	float r = floor(row + 0.5) + (night > 0.5 ? 8.0 : 0.0);
	return texture(ramp_tex, vec2(clamp(lit, 0.01, 0.99), (r + 0.5) / 16.0)).rgb;
}

// a thin fresnel rim, strongest on the side facing the key light and from behind
vec3 look_rim(vec3 N, vec3 V, vec3 base) {
	float fres = 1.0 - max(dot(N, V), 0.0);
	float edge = smoothstep(0.62, 0.72, fres);
	float side = 0.45 + 0.55 * clamp(dot(N, key_dir) * 0.5 + 0.5, 0.0, 1.0);
	return edge * side * rim_strength * rim_color * mix(vec3(1.0), base, 0.35);
}
