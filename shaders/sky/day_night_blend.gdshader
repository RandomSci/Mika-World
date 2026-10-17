// Dusk and dawn (DayNightCycle): the area's day panorama and its night panorama (the starry sky), crossfaded by the
// game clock. Panoramas are linear HDR: no colour hint.
shader_type sky;

uniform sampler2D day_pano : filter_linear, repeat_enable;
uniform sampler2D night_pano : filter_linear, repeat_enable;
uniform float mixk : hint_range(0.0, 1.0) = 0.0;
uniform float day_energy = 1.0;
uniform float night_energy = 1.0;

void sky() {
	vec3 d = texture(day_pano, SKY_COORDS).rgb * day_energy;
	vec3 n = texture(night_pano, SKY_COORDS).rgb * night_energy;
	COLOR = mix(d, n, smoothstep(0.0, 1.0, mixk));
}
