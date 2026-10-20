shader_type spatial;
// A magic beam (the clash): a strip facing the camera, UV.x along the beam (0 at the caster), UV.y across. A thin
// white-hot core, a coloured glow that ripples (scrolling bands), soft ends. HDR + additive.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform vec4 core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float energy = 4.0;
uniform float scroll = 0.0;
uniform float fade = 1.0;
uniform float length_m = 3.0;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float x = UV.x * length_m;
	float band = 0.75 + 0.25 * sin(x * 9.0 - scroll * 22.0) * sin(x * 3.1 - scroll * 9.0 + 1.3);
	float c = exp(-across * across * 60.0);
	float g = exp(-across * across * 5.0) * (1.0 - across) * band;
	float ends = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.97, UV.x);
	ALBEDO = clamp((core.rgb * c * 2.2 + color.rgb * g * 1.2) * energy * fade * ends, vec3(0.0), vec3(64.0));   // (never a NaN into the glow pass)
}
