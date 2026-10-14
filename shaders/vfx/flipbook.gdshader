// SIMULATED FIRE & SMOKE (the cinematic pass, 2026-10-14): a flipbook from tools/vfx/fire_flipbooks.py - a real gas
// simulation (fuel, heat, buoyancy, turbulence) rendered volumetrically - on a camera-facing card. Two layers: the
// fire's own light (HDR, so the bloom carries it) and the smoke as the sun and the fire lit it, premultiplied by its
// coverage (soot darkens what is behind it, fire adds light). Frames cross-blend for smooth motion; the card fades
// softly where it meets geometry (no hard intersection lines) and close to the camera.
//   particles: INSTANCE_CUSTOM.y (age 0..1) picks the frame, .x spins it, COLOR tints the fire and fades it;
//   a MeshInstance3D: the instance uniforms frame_t / fade / spin drive it (FireFX animates them), or `loop_fps`
//   plays a looping flipbook on its own.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D fire_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D smoke_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 grid = vec2(8.0, 8.0);
uniform float frames = 64.0;
uniform float fire_scale = 4.0;
uniform float fire_gain = 1.6;
uniform vec3 fire_tint : source_color = vec3(1.0);
uniform float smoke_gain = 1.0;
uniform vec3 smoke_tint : source_color = vec3(1.0);
uniform float smoke_alpha = 1.0;
uniform float soft = 0.8;
uniform bool billboard = true;
uniform bool upright = false;          // billboard about the vertical only (flames stay upright when seen from above)
uniform bool particles = true;
uniform float loop_fps = 0.0;          // > 0: a looping flipbook that plays itself
instance uniform float frame_t = 0.0;
instance uniform float fade = 1.0;
instance uniform float spin = 0.0;
instance uniform float phase = 0.0;

varying float v_t;
varying vec4 v_col;

void vertex() {
	float ang = spin;
	float t = frame_t;
	v_col = COLOR;
	if (particles) {
		ang += INSTANCE_CUSTOM.x;
		t = INSTANCE_CUSTOM.y;
	}
	if (loop_fps > 0.0) {
		t = fract(TIME * loop_fps / frames + phase + (particles ? INSTANCE_CUSTOM.z : 0.0));
	}
	v_t = t;
	if (billboard) {
		mat4 w;
		if (upright) {
			vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
			to_cam.y = 0.0;
			vec3 fwd = normalize(to_cam + vec3(0.0, 0.0, 0.0001));
			vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
			w = mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
		} else {
			w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		}
		w = w * mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
				vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

vec2 cell_uv(vec2 uv, float f) {
	float c = mod(f, grid.x);
	float r = floor(f / grid.x);
	return (vec2(c, r) + uv) / grid;
}

void fragment() {
	bool looping = loop_fps > 0.0;
	float f = (looping ? fract(v_t) * frames : clamp(v_t, 0.0, 1.0) * (frames - 1.0));
	float f0 = floor(f);
	float k = f - f0;
	float f1 = looping ? mod(f0 + 1.0, frames) : min(f0 + 1.0, frames - 1.0);
	vec2 uv0 = cell_uv(UV, f0);
	vec2 uv1 = cell_uv(UV, f1);
	vec4 s = mix(texture(smoke_tex, uv0), texture(smoke_tex, uv1), k);
	vec3 e = mix(texture(fire_tex, uv0).rgb, texture(fire_tex, uv1).rgb, k) * fire_scale;
	// soft where it meets geometry, and close to the camera
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -vp.z / vp.w;
	float my_z = -VERTEX.z;
	float sf = clamp((scene_z - my_z) / max(soft, 0.01), 0.0, 1.0) * clamp((my_z - 0.3) / 1.5, 0.0, 1.0);
	float vis = sf * fade * v_col.a;
	ALBEDO = (s.rgb * smoke_gain * smoke_tint * smoke_alpha + e * fire_gain * fire_tint * v_col.rgb) * vis;
	ALPHA = clamp(s.a * smoke_alpha * vis, 0.0, 1.0);
}
