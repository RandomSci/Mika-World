shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_lambert, specular_schlick_ggx, shadows_disabled;
// Stylized water for the Whispering Woods (Milestone K, original): clear turquoise shallows that deepen to a dark
// teal by real water depth (scene depth behind the surface), a soft foam line where water meets banks and rocks,
// a gentle sky-coloured fresnel sheen and sun glints from two drifting ripple layers. `flow` moves the ripples
// (river) or leaves them almost still (pond). Night: the glow tint lifts it a little (bioluminescence).

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 shallow : source_color = vec4(0.36, 0.78, 0.72, 1.0);
uniform vec4 deep : source_color = vec4(0.03, 0.20, 0.24, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.70, 0.86, 0.95, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.98, 0.96, 1.0);
uniform float depth_scale = 1.6;      // metres to reach the deep colour
uniform float foam_width = 0.35;
uniform vec2 flow = vec2(0.0, 0.05);
uniform float ripple = 0.35;
uniform vec4 glow_color : source_color = vec4(0.3, 0.8, 0.75, 1.0);
uniform float glow = 0.0;
uniform float spec = 0.6;
uniform float shore_soft = 0.07;
uniform float sheen_base = 0.12;       // how much sky colour sits on the water head-on
uniform float sheen_fres = 0.45;       // and at grazing angles
uniform float foam_amount = 0.85;       // metres of water depth over which the edge fades in

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_wp.xz;
	float t = TIME;
	// ripples: two noise layers drifting differently -> a normal
	vec2 u1 = uv * 0.09 + flow * t + vec2(t * 0.007, 0.0);
	vec2 u2 = uv * 0.21 - flow.yx * t * 0.6 + vec2(0.0, t * 0.011);
	float e = 0.02;
	float h0 = texture(noise_tex, u1).r + texture(noise_tex, u2).r * 0.5;
	float hx = texture(noise_tex, u1 + vec2(e, 0.0)).r + texture(noise_tex, u2 + vec2(e, 0.0)).r * 0.5;
	float hz = texture(noise_tex, u1 + vec2(0.0, e)).r + texture(noise_tex, u2 + vec2(0.0, e)).r * 0.5;
	vec3 nw = normalize(vec3((h0 - hx) * ripple * 6.0, 1.0, (h0 - hz) * ripple * 6.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// water depth behind this pixel
	float zd = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, zd, 1.0);
	vp.xyz /= vp.w;
	float wdepth = max(-vp.z - (-VERTEX.z), 0.0);
	float k = 1.0 - exp(-wdepth / depth_scale);
	// refraction: the bed seen through the water (distorted a little), tinted by depth
	vec2 ruv = SCREEN_UV + nw.xz * 0.02 * k;
	vec3 bed = textureLod(screen_tex, ruv, 1.0).rgb;
	vec3 body = mix(bed * shallow.rgb * 1.25, deep.rgb, smoothstep(0.0, 1.0, k));
	// fresnel sky sheen
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(body, sky_tint.rgb, sheen_base + fres * sheen_fres);
	// foam at the shore / around stones, broken by noise
	float fn = texture(noise_tex, uv * 0.5 + flow * t * 2.0).r;
	float foam = (1.0 - smoothstep(0.0, foam_width, wdepth - (fn - 0.5) * foam_width * 0.8)) * foam_amount;
	col = mix(col, foam_color.rgb, foam);
	ALBEDO = col * 0.85;
	EMISSION = glow_color.rgb * glow * (0.4 + h0 * 0.6) + col * 0.12;
	ROUGHNESS = mix(0.06, 0.4, foam);
	METALLIC = 0.0;
	SPECULAR = spec;
	// a soft shoreline: where the water thins to nothing over the bank it fades out instead of ending in a line
	ALPHA = smoothstep(0.0, shore_soft, wdepth);
}
