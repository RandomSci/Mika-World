shader_type spatial;
// Wing flapping for MultiMesh birds and butterflies. Wings are the vertices with |x| > body_half;
// they rotate about the body's long axis (z). INSTANCE_CUSTOM.x = phase, .y = flap speed scale.
render_mode cull_disabled, shadows_disabled;

uniform float flap_speed = 9.0;
uniform float flap_amount = 0.9;
uniform float body_half = 0.02;
uniform vec3 base_color : source_color = vec3(0.08, 0.08, 0.09);
uniform bool use_instance_color = false;
uniform float emission = 0.0;

void vertex() {
	if (abs(VERTEX.x) > body_half) {
		float ang = sin(TIME * flap_speed * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.x * 6.2831) * flap_amount * sign(VERTEX.x);
		float r = abs(VERTEX.x);
		VERTEX.y += sin(ang) * r;
		VERTEX.x = sign(VERTEX.x) * cos(ang) * r;
	}
}

void fragment() {
	vec3 c = use_instance_color ? COLOR.rgb : base_color;
	ALBEDO = c;
	ROUGHNESS = 0.8;
	EMISSION = c * emission;
}
