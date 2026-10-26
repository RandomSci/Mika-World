extends RefCounted
## --mktest=lunawedge (27 Oct live: Luna wedged at (22.9, -0.2, 116.7) in the sanctuary, 24 failed catch-ups while Mika
## went on alone): from that corner, out of the camera's view, she is placed near Mika where the camera does not see her.
## Marks "[lunawedge] ...".


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	if main.streaming.current_id != "sanctuary":
		await main.streaming.travel("sanctuary", main.characters["mika"])
	await t._wait(2.0)
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var b = main.mage_brains["luna"]
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	luna.visible = true
	luna.set_physics_process(true)
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	# (the live corner is not in this layout: a walkable spot 25 to 35 m off, out of the camera's view)
	var far := Vector3.INF
	for deg in range(0, 360, 20):
		for r in [30.0, 25.0, 35.0]:
			var p: Vector3 = await main.snap_to_nav(mika.global_position + Vector3(r, 0, 0).rotated(Vector3.UP, deg_to_rad(deg)))
			if p.distance_to(mika.global_position) > 20.0 and not cam.is_position_in_frustum(p + Vector3(0, 1, 0)):
				far = p
				break
		if far != Vector3.INF:
			break
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	luna.global_position = far + Vector3(0, 0.05, 0)
	await t._wait(1.5)
	print("[lunawedge] mika at %s, luna at %s (%.0f m), luna in view %s" % [str(mika.global_position.snapped(Vector3.ONE * 0.1)), str(luna.global_position.snapped(Vector3.ONE * 0.1)),
		luna.global_position.distance_to(mika.global_position), str(cam.is_position_in_frustum(luna.global_position + Vector3(0, 1, 0)))])
	var moved: bool = await b._rejoin_out_of_view(mika)
	await t._wait(1.0)
	var d := luna.global_position.distance_to(mika.global_position)
	var seen := cam.is_position_in_frustum(luna.global_position + Vector3(0, 1, 0))
	print("[lunawedge] placed %s: luna at %s, %.1f m from Mika, in view %s, floor %s" % [str(moved), str(luna.global_position.snapped(Vector3.ONE * 0.1)), d, str(seen), str(luna.is_on_floor())])
	t._check(moved and d < 9.0 and not seen, "wedged out of view, Luna comes back near Mika unseen")
