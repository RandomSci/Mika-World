shader_type spatial;
// Ground light on a flat quad: mode 0 = an impact ring racing outward (t 0..1: thin white core, coloured glow, fading);
// mode 1 = a magic circle (two rings, rune ticks and a star polygon - `points` 5 for Mika's star, 0 for Luna's moon
// circle of crescents) that turns slowly. HDR + additive, lying on the ground.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;
// (pulled 0.35 m toward the camera: small rises of the terrain no longer cut dark holes in the glow)
void vertex() {
	VERTEX += normalize(CAMERA_POSITION_WORLD - VERTEX) * 0.35;
}
uniform vec4 color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform float energy = 2.0;
uniform int mode = 0;
uniform float t = 0.0;
uniform float width = 0.05;
uniform float points = 5.0;
uniform float turn = 0.0;
uniform float fade = 1.0;

float ring(float r, float at, float w) {
	float d = abs(r - at);
	return exp(-d * d / (w * w));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x) + turn;
	vec3 col = vec3(0.0);
	if (mode == 0) {
		float at = mix(0.05, 0.95, 1.0 - pow(1.0 - t, 2.4));
		float w = width * (1.0 + t * 1.5);
		float k = ring(r, at, w * 0.35);
		float g = ring(r, at, w * 1.6);
		float inner = smoothstep(at, 0.0, r) * 0.06 * (1.0 - t);
		col = vec3(1.0) * k * 1.5 + color.rgb * (g + inner);
		col *= (1.0 - t) * (1.0 - smoothstep(0.92, 1.0, r));
	} else {
		float o = ring(r, 0.92, 0.012) + ring(r, 0.78, 0.008) + ring(r, 0.36, 0.008);
		float ticks = ring(r, 0.85, 0.035) * smoothstep(0.75, 0.95, abs(sin(a * 24.0)));
		float star = 0.0;
		if (points > 2.5) {
			// star polygon: lines between every second vertex of an n-gon of radius 0.78
			for (int i = 0; i < 8; i++) {
				if (float(i) >= points) break;
				float a0 = 6.2831853 * float(i) / points - turn * 2.0;
				float a1 = 6.2831853 * float(i + 2) / points - turn * 2.0;
				vec2 v0 = 0.78 * vec2(cos(a0), sin(a0));
				vec2 v1 = 0.78 * vec2(cos(a1), sin(a1));
				vec2 pa = p - v0, ba = v1 - v0;
				float hh = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
				float d = length(pa - ba * hh);
				star += exp(-d * d / 0.00012);
			}
		} else {
			// crescents round the ring (Luna)
			for (int i = 0; i < 6; i++) {
				float a0 = 6.2831853 * float(i) / 6.0 - turn * 2.0;
				vec2 cc = 0.57 * vec2(cos(a0), sin(a0));
				float d1 = length(p - cc) - 0.11;
				float d2 = length(p - cc - 0.045 * vec2(cos(a0 + 0.9), sin(a0 + 0.9))) - 0.095;
				float cres = max(d1, -d2);
				star += exp(-cres * cres / 0.0002) * 0.8;
			}
		}
		float glow = exp(-r * r * 2.5) * 0.12;
		col = vec3(1.0) * (o + star) * 0.7 + color.rgb * (o * 1.4 + ticks + star * 1.2 + glow);
		col *= (1.0 - smoothstep(0.96, 1.0, r));
	}
	ALBEDO = clamp(col * energy * fade, vec3(0.0), vec3(64.0));   // (never a NaN into the glow pass)
}
