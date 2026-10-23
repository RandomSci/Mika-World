// Scanned understory plants (Poly Haven shrub_02, fern_02, nettle_plant; CC0) as the realism pass shows them - the
// scan's own maps (albedo with alpha, normal, ORM), alpha-scissored, light through the leaves - plus a gentle sway
// and the gusts of wingbeats and blasts (gust.gdshaderinc), growing with the height above the plant's root.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/nature/see_through.gdshaderinc"

#include "res://shaders/nature/gust.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cut = 0.5;
uniform float use_normal = 1.0;
uniform float use_orm = 1.0;
uniform float plant_height = 1.0;
uniform float wind_strength = 0.035;
uniform float translucency = 0.3;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = MODEL_MATRIX[3].xyz;
	float hm = max(wp.y - root.y, 0.0);
	float h = clamp(hm / max(plant_height, 0.05), 0.0, 1.0);
	vec3 off = vec3(sin(TIME * 1.3 + wp.x * 0.7 + wp.z * 0.5), 0.0, cos(TIME * 1.1 + wp.z * 0.6 + wp.x * 0.2)) * wind_strength * h * h;
	if (gust_on > 0.5) {
		off += gust_offset(gust_push(root) * 0.45, hm, max(plant_height, 0.3));
	}
	if (body_on > 0.5) {
		off += body_offset(wp, hm);
	}
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	see_through((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD, FRAGCOORD.xy);
	vec4 t = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	vec3 orm = texture(orm_tex, UV).rgb;
	AO = mix(1.0, orm.r, use_orm);
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = mix(0.8, orm.g, use_orm);
	SPECULAR = 0.35;
	BACKLIGHT = t.rgb * translucency;
}
