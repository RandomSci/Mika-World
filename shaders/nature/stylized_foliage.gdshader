shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_disabled;
// Stylized canopy / leaf cards (Milestone K, original). The look of painted anime forests comes from three things:
//   1. SPHERISED NORMALS: each leaf card's normal is blended toward "out from the canopy centre", so a crown shades
//      as one soft volume (lit side / shade side) instead of hundreds of noisy cards;
//   2. a GRADIENT: cooler and darker in the inner, lower crown, warm and bright on top, plus per-instance variation;
//   3. LIGHT THROUGH THE LEAVES: back-light (translucency) where the sun shines through the crown's edge.
// Wind: a gentle sway that grows with height, plus a faster leaf flutter; world-position phase so trees never
// move in lockstep. INSTANCE_CUSTOM.r = colour variation (-1..1), .g = wind phase offset.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.42;
uniform vec4 tint_top : source_color = vec4(0.62, 0.86, 0.36, 1.0);
uniform vec4 tint_bottom : source_color = vec4(0.16, 0.34, 0.20, 1.0);
uniform vec4 tint_texture_mix = vec4(0.55, 0.0, 0.0, 0.0);   // x: how much of the texture's own colour is kept
uniform vec3 canopy_center = vec3(0.0, 4.0, 0.0);            // model space
uniform float canopy_radius = 3.0;
uniform float canopy_bottom = 1.5;                            // model-space y where the crown starts
uniform float canopy_top = 7.0;
uniform float spherize : hint_range(0.0, 1.0) = 0.78;
uniform float translucency : hint_range(0.0, 2.0) = 0.6;
uniform vec4 translucency_color : source_color = vec4(0.85, 1.0, 0.45, 1.0);
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.1;
uniform float flutter = 0.025;
uniform float variation_strength = 0.12;

varying float v_height;
varying float v_var;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp((VERTEX.y - canopy_bottom) / max(canopy_top - canopy_bottom, 0.01), 0.0, 1.0);
	v_height = h;
	v_var = INSTANCE_CUSTOM.r;
	float ph = wp.x * 0.21 + wp.z * 0.17 + INSTANCE_CUSTOM.g * 6.2831;
	float sway = sin(TIME * wind_speed + ph) * 0.6 + sin(TIME * wind_speed * 2.3 + ph * 1.7) * 0.25;
	float k = h * h;
	VERTEX.x += sway * wind_strength * k;
	VERTEX.z += sway * wind_strength * 0.6 * k;
	VERTEX += NORMAL * sin(TIME * 6.0 + dot(VERTEX, vec3(3.1, 2.7, 4.3))) * flutter * h;
	// spherised normal: out from the crown centre
	vec3 out_dir = normalize(VERTEX - canopy_center + vec3(0.0001));
	NORMAL = normalize(mix(NORMAL, out_dir, spherize));
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// leaves right in front of the camera dissolve (dithered) instead of filling the frame
	float near_keep = smoothstep(0.7, 2.0, length(VERTEX));
	float dither = fract(dot(FRAGCOORD.xy, vec2(0.0671, 0.00583)) * 52.9829);
	if (t.a < alpha_cut || near_keep < dither) {
		discard;
	}
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	vec3 grad = mix(tint_bottom.rgb, tint_top.rgb, smoothstep(0.0, 1.0, v_height));
	vec3 col = mix(grad * (0.75 + 0.5 * lum), t.rgb * grad * 1.6, tint_texture_mix.x);
	col *= 1.0 + v_var * variation_strength;
	col = mix(col, col * vec3(1.04, 1.0, 0.92), max(v_var, 0.0) * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	BACKLIGHT = translucency_color.rgb * translucency * (0.4 + 0.6 * v_height);
	AO = mix(0.55, 1.0, v_height);
	AO_LIGHT_AFFECT = 0.25;
}
