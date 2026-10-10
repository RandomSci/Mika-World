shader_type spatial;
// Cheap fake god-ray card: additive, soft-edged, slowly drifting dust; fades when seen edge-on or up close.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.88, 0.66);
uniform float intensity = 0.22;
uniform float day = 1.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = smoothstep(0.0, 0.38, UV.x) * smoothstep(1.0, 0.62, UV.x);
	float along = smoothstep(0.0, 0.3, UV.y) * smoothstep(1.0, 0.55, UV.y);
	float dust = 0.72 + 0.28 * sin(UV.y * 17.0 + TIME * 0.5 + UV.x * 6.0) * sin(UV.y * 5.0 - TIME * 0.3);
	float facing = smoothstep(0.08, 0.55, abs(dot(NORMAL, VIEW)));
	float near = smoothstep(1.2, 5.0, length(wpos - CAMERA_POSITION_WORLD));
	ALBEDO = color * intensity * edge * along * dust * facing * near * day;
}
