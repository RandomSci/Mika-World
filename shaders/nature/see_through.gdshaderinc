// SEE-THROUGH (Selwyn, 24 Oct: "make sure the camera isn't blocked by some leaves"): leaves, plants and grass between
// the lens and Mika, or right at the lens, dissolve in a fine screen dither, the way games keep the hero visible in a
// forest. Trunks, rocks and walls are kept out by the camera's own collision; only soft vegetation goes see-through.
// lens_subject is set every frame by CameraDirector (her chest); the shadow pass is left alone (its camera is the sun,
// far away: the test below needs the lens within 14 m of her).
global uniform vec3 lens_subject;
global uniform vec3 lens_subject_b;   // Luna when she shares the shot (24 Oct live: a pine hid her in the market)

float _bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int idx = i.x + i.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

// how much a fragment hides this subject: 1 inside the cone from the lens to her, 0 outside
float _hides(vec3 world_pos, vec3 cam, vec3 subject) {
	vec3 seg = subject - cam;
	float len2 = dot(seg, seg);
	if (len2 > 196.0 || len2 < 0.01)
		return 0.0;
	float t = clamp(dot(world_pos - cam, seg) / len2, 0.0, 1.0);
	if (t > 0.94)
		return 0.0;                               // at her or behind her: never
	float d = distance(world_pos, cam + seg * t);
	float r = mix(0.55, 1.05, t);                 // a cone widening toward her (head to feet)
	return 1.0 - smoothstep(r * 0.65, r, d);
}

// call from fragment() with the fragment's world position: discards it when it hides either girl
void see_through(vec3 world_pos, vec3 cam, vec2 frag) {
	if (distance(lens_subject, cam) > 14.0)
		return;
	float fade = max(_hides(world_pos, cam, lens_subject), _hides(world_pos, cam, lens_subject_b));
	// branches round the lens itself (the lens inside a pine's skirt filled the picture, 24 Oct live)
	// (not the grass at her feet: only what is at most a metre below the lens)
	if (world_pos.y > cam.y - 1.0)
		fade = max(fade, 1.0 - smoothstep(1.6, 2.6, distance(world_pos, cam)));
	if (fade > _bayer4(frag))
		discard;
}
