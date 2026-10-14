// Oriel's solid parts (body under the plumage, beak, legs, wing leading edge): vertex colour, a soft sheen,
// the same ember heat and the same dissolve as her feathers, so during the transformation no smooth body is
// left standing when the plumage burns away.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform float metallic = 0.0;
uniform float roughness = 0.7;
uniform float heat = 0.0;
uniform float hurt = 0.0;
uniform float dissolve = 0.0;
uniform vec3 dissolve_origin = vec3(0.0, 1.6, 0.0);
uniform float dissolve_radius = 4.2;

varying vec3 world_pos;

float hash3(vec3 p) {
	return fract(sin(dot(floor(p), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = 0.0;
	if (dissolve > 0.0) {
		float d = clamp(distance(world_pos, dissolve_origin) / dissolve_radius, 0.0, 1.0);
		float n = hash3(world_pos * 28.0 + vec3(0.37));
		// the body goes a little later than the feathers (it is nearer the heart)
		float v = d * 0.6 + n * 0.25 + 0.15;
		float gone = 1.0 - dissolve * 1.08;
		if (v > gone) {
			discard;
		}
		edge = 1.0 - smoothstep(0.0, 0.09, gone - v);
	}
	ALBEDO = COLOR.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = 0.45;
	RIM = 0.25;
	RIM_TINT = 0.6;
	EMISSION = vec3(1.0, 0.5, 0.12) * heat * 0.6 * COLOR.r + vec3(1.0, 0.92, 0.7) * edge * 3.0 + vec3(1.0, 0.85, 0.6) * hurt;
}
