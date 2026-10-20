// Burn dissolve, adapted from GDQuest's dissolve.gdshader (godot-shaders, MIT code; https://github.com/gdquest-demos/
// godot-shaders). The old outfit, already pure light, burns away: a noise threshold eats it with a white-hot edge in
// the element's colours. Unshaded light (it replaces the old outfit's materials as material_override on its frozen
// last pose while the new outfit stands under it in the same light).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0);
uniform vec3 body_color : source_color = vec3(0.72, 0.77, 1.0);
uniform vec3 burn_color : source_color = vec3(0.55, 0.62, 1.0);
uniform float glow = 2.2;
uniform sampler2D dissolve_texture : repeat_enable;
uniform float burn_size : hint_range(0.0, 0.5) = 0.12;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// sampled in world space (the avatar's UV atlas would burn in patches)
	float s = texture(dissolve_texture, vec2(wpos.x * 0.7 + wpos.z * 0.5, wpos.y * 0.9)).r;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float edge = 1.0 - smoothstep(dissolve_amount, dissolve_amount + burn_size, s);
	vec3 col = mix(mix(core_color, body_color, 0.3 + 0.4 * fres), burn_color * 2.0, edge);
	ALBEDO = col * glow * (1.0 + edge * 1.8);
	ALPHA = smoothstep(dissolve_amount - burn_size * 0.5, dissolve_amount, s);
}
