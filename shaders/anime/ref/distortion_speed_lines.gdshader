// "Distortion Speed Lines" by xxidbr9 - https://godotshaders.com/shader/distortion-speed-lines/
// License: MIT (godotshaders.com: "under MIT license and can be used freely"). Reference copy, unchanged.
shader_type canvas_item;

uniform sampler2D noise: repeat_enable;
uniform float line_count: hint_range(0.0, 2.0, 0.05) = 2.0;
uniform float distortion_power: hint_range(0.0, 0.1) = 0.034;
uniform float line_falloff: hint_range(0.0, 1.0) = 1.0;
uniform float mask_size: hint_range(0.0, 1.0) = 0.175;
uniform float mask_edge: hint_range(0.0, 1.0) = 0.195;
uniform float animation_speed: hint_range(1.0, 20.0) = 20.0;
uniform float blur_strength: hint_range(0.0, 0.01) = 0.01;
uniform float effect_power: hint_range(0.0, 1.0) = 0.5;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

float inv_lerp(float from, float to, float value){
  return (value - from) / (to - from);
}

vec2 polar_coordinates(vec2 uv, vec2 center, float zoom, float repeat)
{
	vec2 dir = uv - center;
	float radius = length(dir) * 2.0;
	float angle = atan(dir.y, dir.x) * 1.0/(PI * 2.0);
	return mod(vec2(radius * zoom, angle * repeat), 1.0);
}

vec2 rotate_uv(vec2 uv, vec2 pivot, float rotation) {
    float cosa = cos(rotation);
    float sina = sin(rotation);
    uv -= pivot;
    return vec2(cosa * uv.x - sina * uv.y, cosa * uv.y + sina * uv.x) + pivot;
}

void fragment(){
	vec2 polar_uv = polar_coordinates(rotate_uv(UV, vec2(0.5), floor(fract(TIME) * animation_speed)), vec2(0.5), 0.01, line_count);
	vec3 lines = texture(noise, polar_uv).rgb;
	float mask_value = length(UV - vec2(0.5));
	float mask = inv_lerp(mask_size, mask_edge, mask_value);
	float effect_strength = mask * distortion_power * effect_power;
	float line_intensity = smoothstep(1.0 - effect_strength, 1.0 - effect_strength + line_falloff, lines.r);
	vec2 center = vec2(0.5);
	vec2 direction = normalize(UV - center);
	vec2 distorted_uv = UV + direction * line_intensity * effect_strength;
	vec4 base_color = texture(SCREEN_TEXTURE, distorted_uv);
	vec4 blur_color = vec4(0.0);
	float blur_samples = 8.0;
	for(float i = 0.0; i < blur_samples; i++){
		float angle = (i / blur_samples) * PI * 2.0;
		vec2 offset = vec2(cos(angle), sin(angle)) * blur_strength * line_intensity;
		blur_color += texture(SCREEN_TEXTURE, distorted_uv + offset);
	}
	blur_color /= blur_samples;
	COLOR = mix(base_color, blur_color, line_intensity * 0.5);
}
