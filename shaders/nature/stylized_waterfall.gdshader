shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;
// Stylized falling water (Milestone K, original), the painted-anime look of the references: a translucent teal
// body behind bright, crisp white streaks that race downward at different speeds, a glassy lip at the top where
// the water bends over the edge, frothing white toward the foot, and soft ragged side edges.
// UV.x across the sheet (0..1), UV.y from the lip (0) to the foot (1). `glow` lifts it at night.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 body : source_color = vec4(0.42, 0.74, 0.76, 1.0);
uniform vec4 deep : source_color = vec4(0.12, 0.36, 0.42, 1.0);
uniform vec4 streak_col : source_color = vec4(0.96, 1.0, 1.0, 1.0);
uniform float speed = 0.9;
uniform float width_m = 8.0;
uniform float glow = 0.0;

void fragment() {
	float x = UV.x * width_m * 0.35;
	float y = UV.y;
	// three streak layers at different speeds (parallax inside the sheet)
	float s1 = texture(noise_tex, vec2(x * 0.9, y * 0.35 - TIME * speed * 0.55)).r;
	float s2 = texture(noise_tex, vec2(x * 2.1 + 3.7, y * 0.6 - TIME * speed * 0.9)).r;
	float s3 = texture(noise_tex, vec2(x * 4.3 + 9.1, y * 1.1 - TIME * speed * 1.4)).r;
	float streak = smoothstep(0.56, 0.62, s1) * 0.55 + smoothstep(0.58, 0.63, s2) * 0.75 + smoothstep(0.6, 0.66, s3) * 0.5;
	streak = clamp(streak, 0.0, 1.0);
	// lip: glassy and smooth for the first stretch, then breaking up
	float lip = 1.0 - smoothstep(0.0, 0.12, y);
	streak *= smoothstep(0.02, 0.16, y);
	// froth toward the foot
	float froth = smoothstep(0.62, 1.0, y) * (0.55 + 0.45 * texture(noise_tex, vec2(x * 3.0, y * 2.0 - TIME * 1.6)).r);
	vec3 col = mix(deep.rgb, body.rgb, 0.5 + 0.5 * s1);
	col = mix(col, streak_col.rgb, clamp(streak + froth, 0.0, 1.0));
	col += vec3(0.25, 0.35, 0.35) * lip;
	// ragged sides
	float side = min(UV.x, 1.0 - UV.x);
	float rag = texture(noise_tex, vec2(y * 2.0 - TIME * speed * 0.8, UV.x * 0.5)).r;
	float edge = smoothstep(0.0, 0.08 + rag * 0.06, side);
	ALBEDO = col;
	EMISSION = col * (0.18 + glow) + streak_col.rgb * streak * 0.15;
	ALPHA = clamp((0.62 + streak * 0.35 + froth * 0.3) * edge, 0.0, 0.96);
	ROUGHNESS = 0.3;
}
