shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;
// The lake: real planar reflection (a mirrored camera renders the scene above the water into `reflection` every
// frame; LanternLake._reflect()), so the mountains, the sky, the pier, the two of them and every lantern - on the
// water and in the air - are mirrored in it. Calm water: slow fine ripples break the mirror a little, more along the
// view (lantern reflections stretch into soft vertical streaks), less far away; Fresnel for water (F0 = 0.02) makes
// it a near-mirror at grazing angles and lets the dark depth show right under the lens.

uniform sampler2D reflection : filter_linear, repeat_disable;
uniform bool reflection_srgb = false;
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.012, 0.018, 0.04);
uniform float ripple_strength = 1.0;
uniform float reflect_gain = 1.0;
uniform float water_y = 0.0;
uniform vec4 calm_zone = vec4(0.0, 0.0, 0.0, 0.0);   // xy centre, z radius: a little more chop round the pier posts

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 na = texture(ripple_a, p * 0.045 + TIME * vec2(0.006, 0.0035)).xyz * 2.0 - 1.0;
	vec3 nb = texture(ripple_b, p * 0.11 + TIME * vec2(-0.004, 0.007)).xyz * 2.0 - 1.0;
	vec3 nc = texture(ripple_a, p * 0.33 + TIME * vec2(0.012, -0.01)).xyz * 2.0 - 1.0;
	vec2 rip = na.xy * 0.55 + nb.xy * 0.35 + nc.xy * 0.2;
	vec3 to_cam = CAMERA_POSITION_WORLD - v_world;
	float dist = length(to_cam);
	vec3 V = to_cam / dist;
	// screen-space break-up: much more along the view than across it, fading with distance
	float k = ripple_strength / (1.0 + dist * 0.045);
	vec3 rip_v = (VIEW_MATRIX * vec4(rip.x, 0.0, rip.y, 0.0)).xyz;
	vec2 off = vec2(rip_v.x * 0.006, rip_v.z * 0.03 + rip_v.y * 0.03) * k;
	vec2 suv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + vec2(-off.x, off.y);
	suv = clamp(suv, vec2(0.002), vec2(0.998));
	vec3 refl = textureLod(reflection, suv, 0.0).rgb;
	if (reflection_srgb) {
		refl = mix(refl / 12.92, pow((refl + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), refl));
	}
	// Fresnel with the rippled normal
	vec3 n = normalize(vec3(rip.x * 0.08 * k, 1.0, rip.y * 0.08 * k));
	float cosv = clamp(dot(n, V), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - cosv, 5.0);
	fres = clamp(fres * 1.1 + 0.05, 0.0, 1.0);
	vec3 c = mix(deep_color, refl * reflect_gain, fres);
	ALBEDO = c;
}
