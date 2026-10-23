shader_type spatial;
// Geometry grass clumps (no alpha cards → no overdraw cost, crisp under TAA).
// UV.y = 0 at root, 1 at tip. Instance colour (multimesh) carries per-clump tint.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/nature/see_through.gdshaderinc"

uniform vec3 root_color : source_color = vec3(0.05, 0.08, 0.03);
uniform vec3 tip_color : source_color = vec3(0.26, 0.38, 0.12);
uniform vec3 dry_color : source_color = vec3(0.42, 0.42, 0.2);
uniform sampler2D breakup_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wind_strength = 0.12;
uniform vec2 wind_dir = vec2(0.8, 0.35);
uniform float fade_start = 20.0;
uniform float fade_end = 28.0;

#include "res://shaders/nature/gust.gdshaderinc"

varying float tipness;
varying vec3 wpos;

void vertex() {
	tipness = UV.y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = texture(breakup_noise, world.xz * 0.05 + TIME * 0.03 * wind_dir).r;
	float sway = (sin(TIME * 1.7 + world.x * 0.35 + world.z * 0.22) * 0.5 + n) * wind_strength;
	float bend = UV.y * UV.y;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * vec3(wind_dir.x, 0.0, wind_dir.y)) * sway * bend;
	if (body_on > 0.5) {
		VERTEX += inverse(mat3(MODEL_MATRIX)) * body_offset(world, max(world.y - MODEL_MATRIX[3].y, 0.0));
	}
	if (gust_on > 0.5) {
		vec3 root = MODEL_MATRIX[3].xyz;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * gust_offset(gust_push(root) * 0.3, max(world.y - root.y, 0.0), 0.45);
	}
	// shrink grass far away (avoid aliasing shimmer), it fades into the terrain texture
	float cam_d = length(world - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float shrink = 1.0 - smoothstep(fade_start, fade_end, cam_d);
	VERTEX.y *= shrink;
	wpos = world;
}

void fragment() {
	see_through((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD, FRAGCOORD.xy);
	float n = texture(breakup_noise, wpos.xz * 0.03).r;
	vec3 tip = mix(tip_color, dry_color, smoothstep(0.55, 0.85, n) * 0.6) * COLOR.rgb;
	ALBEDO = mix(root_color, tip, smoothstep(0.0, 0.85, tipness));
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.35, 0.42, 0.18) * tipness;
	AO = mix(0.35, 1.0, tipness);
	AO_LIGHT_AFFECT = 0.6;
}
