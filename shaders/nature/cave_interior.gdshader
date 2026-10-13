shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, shadows_disabled;
// Cave interior for the Whispering Woods den (Milestone K environment pass). The outdoor distance fog and the sky
// ambient would wash a hollow into flat grey, so the interior shades itself: a rock tone that darkens with depth
// (vertex COLOR from the dome builder), a faint cool bounce from the mouth, soft noise so it is not a flat fill,
// and a dim mineral glint. Readable darkness, never black.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 rock : source_color = vec4(0.30, 0.27, 0.26, 1.0);
uniform vec4 bounce : source_color = vec4(0.36, 0.46, 0.58, 1.0);
uniform float floor_y = 0.0;      // world y of the cave floor (the ground lightens near it)

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(noise_tex, v_wp.xz * 0.18 + v_wp.y * 0.07).r;
	float n2 = texture(noise_tex, v_wp.xy * 0.45 + 3.0).r;
	float depth = COLOR.r;                       // 0 deep .. ~0.16 at the mouth (from the builder)
	float k = clamp(depth * 5.5, 0.0, 1.0);      // 0 at the back, 1 at the mouth
	vec3 col = rock.rgb * (0.35 + 0.65 * k) * (0.8 + n * 0.4);
	col = mix(col, bounce.rgb * (0.5 + 0.5 * n2), k * 0.35);
	// low surfaces catch a little more of the light from the opening
	float low = 1.0 - smoothstep(floor_y + 0.2, floor_y + 3.0, v_wp.y);
	col *= 0.85 + 0.35 * low * k;
	ALBEDO = col * 0.55;
}
