shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Sun shafts through the canopy (Milestone K, original) — the "light pouring into the forest" of the references,
// done as soft additive cards instead of volumetric fog (too costly on the stream machine's iGPU). Each card fades
// at its edges and ends, dissolves when seen edge-on or from very close, shimmers slowly as leaves move, and is
// faded out by `strength` (0 at night / overcast).

uniform vec4 color : source_color = vec4(1.0, 0.93, 0.72, 1.0);
uniform float strength = 0.22;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x);
	float ends = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.55, UV.y);
	float facing = abs(dot(NORMAL, VIEW));
	float n = texture(noise_tex, vec2(UV.x * 0.6 + TIME * 0.01, v_wp.y * 0.02 + TIME * 0.006) + v_wp.xz * 0.01).r;
	float near = smoothstep(2.0, 7.0, -VERTEX.z);
	// shafts are seen from beneath the canopy: looking DOWN on one (from a cliff top) it would read as a bar
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	near *= 1.0 - 0.9 * smoothstep(1.0, 5.0, cam.y - v_wp.y);
	float a = edge * ends * smoothstep(0.1, 0.5, facing) * near * (0.55 + n * 0.9);
	ALBEDO = color.rgb * a * strength;
}
