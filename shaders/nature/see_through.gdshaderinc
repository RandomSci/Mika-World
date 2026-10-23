// SEE-THROUGH (Selwyn, 24 Oct: "make sure the camera isn't blocked by some leaves"): leaves, plants and grass between
// the lens and Mika, or right at the lens, dissolve in a fine screen dither, the way games keep the hero visible in a
// forest. Trunks, rocks and walls are kept out by the camera's own collision; only soft vegetation goes see-through.
// lens_subject is set every frame by CameraDirector (her chest); the shadow pass is left alone (its camera is the sun,
// far away: the test below needs the lens within 14 m of her).
global uniform vec3 lens_subject;

float _bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

// call from fragment() with the fragment's world position: discards it when it hides her
void see_through(vec3 world_pos, vec3 cam, vec2 frag) {
	vec3 seg = lens_subject - cam;
	float len2 = dot(seg, seg);
	if (len2 > 196.0 || len2 < 0.01)
		return;
	float t = clamp(dot(world_pos - cam, seg) / len2, 0.0, 1.0);
	if (t > 0.94)
		return;                                   // at her or behind her: never
	float d = distance(world_pos, cam + seg * t);
	float r = mix(0.55, 1.05, t);                 // a cone widening toward her (head to feet)
	float fade = 1.0 - smoothstep(r * 0.65, r, d);
	fade = max(fade, 1.0 - smoothstep(0.8, 1.4, distance(world_pos, cam)));   // a leaf brushing the lens itself
	if (fade > _bayer4(frag))
		discard;
}
