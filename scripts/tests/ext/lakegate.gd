extends RefCounted
## --mktest=lakegate (25 Oct live, 03:19: Mika twice "could not reach the gate: stuck near (16.9, 0.8, 18.7)" leaving
## Lantern Lake, Luna stuck 8 times near (5.1, 3.3, 37.2) on the same road): from each spot where they stuck, the
## real journey to the sanctuary; what is solid around the spot (layer, kind) and whether the navmesh runs through it.
## Marks "[lakegate] ...".

const SPOTS := [Vector3(16.9, 0.8, 18.7), Vector3(5.1, 3.3, 37.2), Vector3(17.1, 0.8, 18.6)]


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	if main.streaming.current_id != "lantern_lake":
		await main.streaming.travel("lantern_lake", main.characters["mika"])
	await t._wait(2.0)
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = mika.get_world_3d().navigation_map
	var space := mika.get_world_3d().direct_space_state
	var ok := 0
	for p in SPOTS:
		var on_nav := NavigationServer3D.map_get_closest_point(map, p)
		print("[lakegate] spot %s: navmesh closest %s (%.2f m)" % [str(p), str(on_nav), on_nav.distance_to(p)])
		var q := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new()
		s.radius = 1.2
		q.shape = s
		q.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
		q.collision_mask = 0xFFFFFFFF
		for hit in space.intersect_shape(q, 16):
			var c = hit.collider
			var layer: int = c.collision_layer if "collision_layer" in c else -1
			print("[lakegate]   solid near: %s (%s) layer %d at %s" % [c.name, c.get_class(), layer, str((c as Node3D).global_position) if c is Node3D else "-"])
		mika.global_position = on_nav + Vector3(0, 0.1, 0)
		mika.velocity = Vector3.ZERO
		await t._wait(1.0)
		var started: Dictionary = main.travel.travel_to("ritual_sanctuary", "walk")
		if not started.get("ok", false):
			print("[lakegate]   could not start: %s" % started)
			continue
		var done := [null]
		var cb := func(ev): if ev.event == "journey_finished" or ev.event == "journey_progress": done[0] = ev
		main.travel.journey_event.connect(cb)
		var t0 := Time.get_ticks_msec()
		while done[0] == null and Time.get_ticks_msec() - t0 < 90000:
			await t._wait(0.5)
		main.travel.journey_event.disconnect(cb)
		var d = done[0]
		var good: bool = d != null and (d.event == "journey_progress" or not String(d.get("detail", "")).contains("could not reach"))
		print("[lakegate]   journey from %s: %s %s" % [str(p), "OK" if good else "FAIL", str(d.get("detail", d.get("event", "")) if d else "timeout")])
		if good:
			ok += 1
		main.travel.cancel("lakegate next spot")
		if main.streaming.current_id != "lantern_lake":
			await main.streaming.travel("lantern_lake", mika)
		await t._wait(1.0)
	t._check(ok == SPOTS.size(), "every stuck spot reaches the lake gate (%d of %d)" % [ok, SPOTS.size()])
