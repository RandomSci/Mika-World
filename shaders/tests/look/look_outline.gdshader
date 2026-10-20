// Inverted hull outline (test only): pushed out along the smoothed normal the look lab bakes into TANGENT (so the hull
// doesn't split where Tripo's normals are hard), about the same pixel width at any distance, the surface's own colour
// darkened (like the face's rose outline).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform sampler2D base_tex : source_color, filter_linear_mipmap;
uniform float width = 0.0011;                             // view-space metres per metre of distance
uniform float darken = 0.32;
uniform vec3 outline_tint : source_color = vec3(0.55, 0.5, 0.75);
uniform bool smooth_normals = true;

void vertex() {
	vec3 n = smooth_normals ? normalize(TANGENT) : NORMAL;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 vn = normalize(mat3(MODELVIEW_MATRIX) * n);
	float d = clamp(-vp.z, 0.4, 8.0);
	vp.xyz += normalize(vec3(vn.xy, 0.0) + vec3(0.0, 0.0, 1e-4)) * width * d;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = texture(base_tex, UV).rgb * darken * outline_tint;
}
