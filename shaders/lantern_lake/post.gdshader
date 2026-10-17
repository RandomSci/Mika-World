shader_type canvas_item;
// Lantern Lake's finishing pass: a soft vignette and a whisper of film grain. Colours are left as they are.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float vignette = 0.32;
uniform float grain = 0.008;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec2 q = SCREEN_UV - 0.5;
	q.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float vg = 1.0 - vignette * smoothstep(0.35, 1.05, length(q) * 1.25);
	float n = fract(sin(dot(SCREEN_UV * 1000.0 + fract(TIME * 7.13) * 91.7, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	COLOR = vec4(c * vg + n * grain, 1.0);
}
