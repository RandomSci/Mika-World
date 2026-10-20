// The petals in front of the lens (Selwyn's look notes 2026-10-20: "a few large petals near the camera for depth"): a
// handful of big petals drifting slowly across the space between the camera and the technique, 1.6 to 3.4 m from the
// lens (the petal material fades them out closer than that), falling and swirling. Same COLOR contract as the storm.
shader_type particles;
render_mode disable_velocity, keep_data;

uniform vec3 cam_pos = vec3(0.0);
uniform vec3 focus = vec3(0.0, 0.0, -4.0);
uniform float tclock = 0.0;
uniform float shown = 0.0;                 // 0 to 1, the layer fading in and out with the technique
uniform float size = 3.5;

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

mat3 rot_axis(vec3 ax, float ang) {
	ax = normalize(ax);
	float s = sin(ang);
	float co = cos(ang);
	float oc = 1.0 - co;
	return mat3(vec3(oc * ax.x * ax.x + co, oc * ax.x * ax.y + ax.z * s, oc * ax.z * ax.x - ax.y * s),
		vec3(oc * ax.x * ax.y - ax.z * s, oc * ax.y * ax.y + co, oc * ax.y * ax.z + ax.x * s),
		vec3(oc * ax.z * ax.x + ax.y * s, oc * ax.y * ax.z - ax.x * s, oc * ax.z * ax.z + co));
}

void start() {
	CUSTOM = vec4(h1(float(INDEX) * 0.731 + 0.5), h1(float(INDEX) * 1.37), h1(float(INDEX) * 2.11), h1(float(INDEX) * 3.07));
}

void process() {
	vec3 fw = normalize(focus - cam_pos + vec3(1e-4));
	vec3 sd = normalize(cross(fw, vec3(0.0, 1.0, 0.0)) + vec3(1e-4, 0.0, 0.0));
	vec3 up = cross(sd, fw);
	// each petal drifts across the view and falls, then comes round again from the other side
	float ph = fract(CUSTOM.x + tclock * (0.08 + 0.06 * CUSTOM.y));
	float d = mix(1.6, 3.4, CUSTOM.z);
	float x = (ph * 2.0 - 1.0) * (1.0 + 0.5 * d) * (CUSTOM.w < 0.5 ? 1.0 : -1.0);
	float y = (0.6 - ph * 1.4) * (0.6 + 0.3 * d) + sin(tclock * 1.3 + CUSTOM.w * 6.28) * 0.12;
	vec3 p = cam_pos + fw * d + sd * x + up * y;
	vec3 ax = normalize(vec3(CUSTOM.y - 0.5, CUSTOM.z - 0.5 + 0.3, CUSTOM.w - 0.5));
	mat3 rot = rot_axis(ax, tclock * (1.2 + CUSTOM.y * 1.5) + sin(tclock * 2.0 + CUSTOM.x * 6.28) * 0.9);
	float sc = size * (0.7 + 0.6 * CUSTOM.w);
	float edge = smoothstep(0.0, 0.12, ph) * (1.0 - smoothstep(0.85, 1.0, ph));
	TRANSFORM = mat4(vec4(rot[0] * sc, 0.0), vec4(rot[1] * sc, 0.0), vec4(rot[2] * sc, 0.0), vec4(p, 1.0));
	COLOR = vec4(0.5, CUSTOM.y, edge * shown * 0.85, shown > 0.01 ? 1.0 : 0.0);
	if (shown <= 0.01) {
		TRANSFORM[0].xyz = vec3(0.0);
		TRANSFORM[1].xyz = vec3(0.0);
		TRANSFORM[2].xyz = vec3(0.0);
	}
}
