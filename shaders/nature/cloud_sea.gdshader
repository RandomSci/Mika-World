// SEA OF CLOUDS seen from a mountain (Celestial Highlands): a stack of horizontal layers, each a slowly drifting
// fbm of the noise texture, lit from the sun side (bright, creamy tops; soft blue-grey hollows), soft where it
// touches rock (depth fade) and dissolving into the horizon haze. Several layers a few metres apart give the
// billows real depth when seen at a low angle.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec4 top_color : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform vec4 shade_color : source_color = vec4(0.82, 0.86, 0.93, 1.0);
uniform vec4 haze_color : source_color = vec4(0.78, 0.84, 0.92, 1.0);
uniform vec3 sun_dir = vec3(0.4, 0.5, 0.6);
uniform float layer = 0.0;          // 0 = bottom .. 1 = top layer (thinner, brighter)
uniform float scale = 0.0018;
uniform float coverage = 0.52;
uniform float drift = 0.004;
uniform float soft = 6.0;           // metres of fade where clouds meet terrain
uniform float far = 2600.0;

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 5; i++) {
		v += a * texture(noise_tex, p).r;
		p = p * 2.03 + vec2(0.17, 0.31);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = v_wp.xz * scale + vec2(TIME * drift, TIME * drift * 0.4);
	// large billows (low-frequency shape) carved by finer detail; contrast stretched so there are real gaps and
	// heaped crests, not an even grey sheet
	float shape_n = fbm(p * 0.33 + 3.1);
	float detail = fbm(p);
	float n = (shape_n - 0.53) * 2.6 + (detail - 0.53) * 0.3 + 0.5;
	float cov = coverage + layer * 0.06;
	float dens = smoothstep(cov - 0.12, cov + 0.22, n);
	// light: billows facing the sun are bright, their far sides cool
	float nx = fbm(p * 0.33 + 3.1 + vec2(0.006, 0.0)) - shape_n;
	float nz = fbm(p * 0.33 + 3.1 + vec2(0.0, 0.006)) - shape_n;
	vec3 grad = normalize(vec3(-nx * 40.0, 1.0, -nz * 40.0));
	// crests catch the sun; the deep parts between billows are shadowed
	float lit = clamp(dot(grad, normalize(sun_dir)) * 0.7 + 0.35 + smoothstep(0.5, 1.0, n) * 0.45 + layer * 0.1, 0.0, 1.0);
	vec3 col = mix(shade_color.rgb, top_color.rgb, lit);
	// depth fade against rock and the distance haze
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_d = -view.z;
	float my_d = -VERTEX.z;
	float touch = clamp((scene_d - my_d) / soft, 0.0, 1.0);
	float dist = length(v_wp.xz - CAMERA_POSITION_WORLD.xz);
	float hz = smoothstep(far * 0.35, far, dist);
	col = mix(col, haze_color.rgb, hz * 0.55);
	ALBEDO = col;
	// beyond the near billows the layers merge into one bright floor reaching the horizon
	float floor_a = mix(dens, 1.0, smoothstep(far * 0.2, far * 0.8, dist) * (1.0 - layer));
	ALPHA = clamp(floor_a * touch * mix(0.82, 0.95, layer), 0.0, 1.0);
}
