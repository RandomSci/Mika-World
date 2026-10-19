// Combat v3: one thin tapered ray of an impact glint (a cone stretched to a needle): hot at the base, gone at the tip.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 col : source_color = vec3(0.92, 0.97, 1.0);
uniform float energy = 3.0;
uniform float fade = 1.0;

void fragment() {
	float a = smoothstep(1.0, 0.0, UV.y) * fade;          // UV.y: 0 base .. 1 tip
	ALBEDO = col * energy * a;
	ALPHA = a;
}
