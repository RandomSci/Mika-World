shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
// Reeds and cattails at the waterline (LanternLake._reed_mesh(): UV.y up the plant, UV2.x 0 leaf, 1 stem, 2 cattail
// head). They sway in the light night air; the part under the water is clipped for the reflection camera.

uniform vec3 leaf_base : source_color = vec3(0.03, 0.04, 0.03);
uniform vec3 leaf_tip : source_color = vec3(0.12, 0.13, 0.08);
uniform vec3 head_col : source_color = vec3(0.16, 0.09, 0.05);
uniform float wind = 0.06;
uniform float water_y = 0.0;
uniform float brightness = 1.0;

varying vec3 v_world;
varying float v_t;
varying float v_part;

void vertex() {
	float t = UV.y;
	float seed = INSTANCE_CUSTOM.r;
	vec3 w0 = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = TIME * (0.7 + seed * 0.4) + w0.x * 0.3 + w0.z * 0.2;
	float sway = (sin(ph) * 0.6 + sin(ph * 2.3 + 1.7) * 0.25) * wind * t * t;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.4;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_t = t;
	v_part = UV2.x;
}

void fragment() {
	if (CAMERA_POSITION_WORLD.y < water_y && v_world.y < water_y) {
		discard;
	}
	vec3 c = mix(leaf_base, leaf_tip, smoothstep(0.0, 1.0, v_t));
	if (v_part > 1.5) {
		c = head_col;
	} else if (v_part > 0.5) {
		c = mix(leaf_base, leaf_tip * 0.8, v_t);
	}
	// wet and dark right at the waterline
	c *= mix(0.45, 1.0, smoothstep(water_y, water_y + 0.25, v_world.y));
	ALBEDO = c * brightness;
	ROUGHNESS = 0.8;
	BACKLIGHT = vec3(0.25) * (1.0 - step(1.5, v_part));
}
