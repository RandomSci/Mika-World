shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;
// Spiral ribbons of light for the Level 10 awakening (original). UV.x runs along the ribbon, UV.y across it.
// Heights (ly, 0 = feet) gate them: they appear up to `cover` (wrapping up) and vanish above `reveal_line`
// (unravelling down) with a bright fraying edge.

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.95, 1.0);
uniform vec4 accent : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float height = 1.95;
uniform float cover = 0.0;
uniform float reveal_line = 2.2;
uniform float energy = 1.6;

varying float ly;

void vertex() {
	ly = VERTEX.y;
}

void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);              // soft edges across the ribbon
	float body = smoothstep(0.0, 0.55, across);
	float flow = 0.65 + 0.35 * sin(UV.x * 40.0 - TIME * 6.0);  // light running along it
	float wrapped = smoothstep(cover * height + 0.04, cover * height - 0.06, ly);
	float edge_y = reveal_line + 0.06 * sin(UV.x * 30.0 + TIME * 5.0);
	float kept = smoothstep(edge_y + 0.02, edge_y - 0.04, ly);
	float edge = smoothstep(0.09, 0.0, abs(ly - edge_y)) * step(reveal_line, height);
	float a = body * flow * wrapped * kept + edge * body * 1.5;
	vec3 col = mix(color.rgb, accent.rgb, 0.5 + 0.5 * sin(UV.x * 6.0 + TIME));
	ALBEDO = col * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
