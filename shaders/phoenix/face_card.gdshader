// Oriel's painted face (humanoid form): an eye or mouth card conforming to the head shows one frame of its
// atlas; Godot switches `frame` for blinking, emotion and speech (PhoenixHuman). Lit like skin, cut by alpha.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform int cols = 3;
uniform int rows = 2;
uniform int frame = 0;
uniform float glow = 0.0;            // her eyes catch fire when she casts / transforms

void fragment() {
	int c = frame % max(cols, 1);
	int r = frame / max(cols, 1);
	vec2 uv = vec2((UV.x + float(c)) / float(cols), (UV.y + float(r)) / float(rows));
	vec4 t = texture(atlas, uv);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ALBEDO = t.rgb;
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
	// the gold of the iris glows a little (and more with heat); whites and lashes do not
	float goldness = clamp((t.r - t.b) * 1.6, 0.0, 1.0) * step(0.35, t.r);
	EMISSION = t.rgb * goldness * (0.25 + 1.6 * glow);
}
