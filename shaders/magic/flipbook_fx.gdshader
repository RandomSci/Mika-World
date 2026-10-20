// A video flipbook effect on a camera facing card (Selwyn's FX_Video_Test_v1, 2026-10-20: 8x8 sheets of 512 px frames
// cut from video on black). Black is nothing (added). From his flipbook_fx.gdshader, with:
//   upright      0 faces the camera fully, 1 turns only round the vertical (a pillar stays standing when the camera
//                looks down on it; the card's bottom edge stays on the ground), 2 none: the card keeps its node's own
//                turn (a sigil lying flat on the ground)
//   roll         turns the picture in the card's plane (radians), so a baked slash can follow the real slash
//   uv inset and a capped mip level, so the lower mipmaps never pull a neighbouring cell's edge in (a square edge)
//   edge_mask    a round fade of our own at the card's edge, on top of the sheet's own, so no corner ever shows
//   black_cut    the brightness under which a pixel is dropped (the dim haze), with a soft knee above it
//   fade         the whole card in and out (0..1) from the script
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform float columns = 8.0;
uniform float rows = 8.0;
uniform float frame = 0.0;          // 0 to 63, fractional blends frames
uniform float intensity = 2.2;      // HDR, so the bloom picks it up
uniform float black_cut = 0.14;
uniform float knee = 0.1;
uniform vec4 tint : source_color = vec4(1.0);
uniform float soft_depth = 0.6;     // fades where the card meets the ground or a body
uniform float upright = 0.0;
uniform float roll = 0.0;
uniform float edge_mask = 0.47;     // radius (in card UV) where our round fade ends
uniform float edge_soft = 0.08;     // how wide that fade is (a burst: wide, no visible rim)
uniform float fade = 1.0;
uniform float top_fade = 0.0;
uniform float near_fade = 0.0;      // m: the card fades out closer to the lens than this (a burst never fills a close-up)       // the top share of the card fades out (a pillar thins upward, no dome edge)
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void vertex() {
	vec3 sx = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	if (upright > 1.5) {
		// (as placed: MODELVIEW_MATRIX is already VIEW_MATRIX * MODEL_MATRIX)
	} else if (upright > 0.5) {
		// turn round the world vertical only: x across the view, y straight up, z toward the camera
		vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
		to_cam.y = 0.0;
		vec3 z = length(to_cam) > 1e-4 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
		vec3 y = vec3(0.0, 1.0, 0.0);
		vec3 x = normalize(cross(y, z));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(x * sx.x, 0.0), vec4(y * sx.y, 0.0), vec4(z * sx.z, 0.0), MODEL_MATRIX[3]);
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(sx.x, 0, 0, 0), vec4(0, sx.y, 0, 0), vec4(0, 0, sx.z, 0), vec4(0, 0, 0, 1));
	}
}

vec3 cell(float f, vec2 uv) {
	float i = clamp(floor(f), 0.0, columns * rows - 1.0);
	vec2 c = vec2(mod(i, columns), floor(i / columns));
	// (inset half a texel of the 4th mip so filtering stays inside the cell; mip capped at 3)
	vec2 cs = vec2(textureSize(sheet, 0)) / vec2(columns, rows);
	vec2 inset = vec2(8.0) / cs;
	vec2 u = clamp(uv, inset, vec2(1.0) - inset);
	vec2 dx = dFdx(uv) / vec2(columns, rows);
	vec2 dy = dFdy(uv) / vec2(columns, rows);
	float lod = clamp(0.5 * log2(max(dot(dx * vec2(textureSize(sheet, 0)), dx * vec2(textureSize(sheet, 0))),
		dot(dy * vec2(textureSize(sheet, 0)), dy * vec2(textureSize(sheet, 0))))), 0.0, 3.0);
	return textureLod(sheet, (c + u) / vec2(columns, rows), lod).rgb;
}

void fragment() {
	vec2 q = UV - 0.5;
	float cr = cos(roll);
	float sr = sin(roll);
	vec2 uv = vec2(cr * q.x - sr * q.y, sr * q.x + cr * q.y) + 0.5;
	vec3 a = cell(frame, uv);
	vec3 b = cell(min(frame + 1.0, columns * rows - 1.0), uv);
	vec3 col = mix(a, b, fract(frame));
	float l = max(col.r, max(col.g, col.b));
	col *= smoothstep(black_cut, black_cut + knee, l);
	col *= 1.0 - smoothstep(edge_mask - edge_soft, edge_mask, length(uv - 0.5));
	col *= smoothstep(0.0, max(top_fade, 1e-3), uv.y) * step(1e-4, top_fade) + (1.0 - step(1e-4, top_fade));
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float soft = clamp((scene_z - (-VERTEX.z)) / soft_depth, 0.0, 1.0);
	float near_k = near_fade > 0.0 ? smoothstep(near_fade * 0.55, near_fade, length(VERTEX)) : 1.0;
	ALBEDO = col * tint.rgb * intensity * soft * fade * near_k;
}
