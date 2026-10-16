shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Fireflies (GPUParticles3D): camera-facing soft dots that blink on their own rhythm.
uniform vec3 color : source_color = vec3(0.85, 1.0, 0.45);
uniform float energy = 6.0;

varying float v_blink;

void vertex() {
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	float ph = float(INSTANCE_ID) * 2.399;
	float rate = 0.6 + fract(float(INSTANCE_ID) * 0.618) * 0.9;
	v_blink = pow(max(sin(TIME * rate + ph), 0.0), 4.0) * 0.9 + 0.1;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = dot(p, p);
	float core = exp(-r * 18.0);
	float halo = exp(-r * 3.5) * 0.25;
	// additive: rgb * ALPHA is added; ALPHA covers only the glowing dot, so over a transparent background (a backdrop
	// plate behind the scene) a firefly never leaves a dark square
	float glow = (core + halo) * v_blink * COLOR.a;
	ALBEDO = color * energy;
	ALPHA = clamp(glow, 0.0, 1.0);
}
