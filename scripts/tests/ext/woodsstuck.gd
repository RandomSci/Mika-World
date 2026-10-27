extends RefCounted
## --mktest=woodsstuck (27 Oct live, Whispering Woods): every walk to the wayshrine, the Lamplighter chapter's first clue,
## ended "stuck" near (0.4, 0.6, 77.5), 14 m short ("nearest walkable point is 4.2 m from target"), and after the ban
## the shrine was no longer offered, so the story stood still all day. Shows the woods' spots (where each stands, how
## far its approach is off the navmesh), what is solid around the stuck point, and walks to the shrine from where the
## girls arrive. Marks "[woodsstuck] ...".

const STUCK := [Vector3(0.4, 0.6, 77.5), Vector3(-12.1, 0.0, 80.1)]
const STARTS := [Vector3(-4.0, 0.84, 80.0), Vector3(-12.1, 0.0, 80.1)]


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	# the Lamplighter chapter running, as on the live save (its spots stand only then)
	var st = main.story
	if st.chapter == 0:
		for c in st.data.clues:
			for k in st.data.clues[c].any_knowledge:
				WorldState.knowledge[k] = 1
		st.evaluate(true)
		WorldState.knowledge["chapter_done:heartstone"] = Time.get_unix_time_from_system() - 700.0
		st.evaluate()
	if main.streaming.current_id == "whispering_woods":
		await main.streaming.travel("sanctuary", mika, false)
	await main.streaming.travel("whispering_woods", mika, false)
	await t._wait(3.0)
	var area = main.world
	var map: RID = luna.get_world_3d().navigation_map
	var space := luna.get_world_3d().direct_space_state
	for key in area.interactables:
		if not String(key).begins_with("spot:"):
			continue
		var it: Interactable = area.interactables[key]
		var ap: Vector3 = it.approach_point()
		var np := NavigationServer3D.map_get_closest_point(map, ap)
		print("[woodsstuck] %s at %s, approach %s, %.2f m off the navmesh" % [key, str(it.global_position.snapped(Vector3.ONE * 0.01)),
			str(ap.snapped(Vector3.ONE * 0.01)), np.distance_to(ap)])
	for p in STUCK:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 1.6
		q.shape = sh
		q.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
		q.exclude = [luna.get_rid(), mika.get_rid()]
		var hits := space.intersect_shape(q, 16)
		var names := []
		for h in hits:
			var c: Node = h.collider
			if String(c.name) == "Terrain":
				continue
			var par: Node = c.get_parent()
			var what := ""
			if par is MeshInstance3D and (par as MeshInstance3D).mesh:
				var m: Mesh = (par as MeshInstance3D).mesh
				what = "mesh %s size %s, under %s, meta %s" % [m.resource_path if m.resource_path != "" else m.resource_name, str(m.get_aabb().size.snapped(Vector3.ONE * 0.1)),
					str(par.get_path()).right(90), str(par.get_meta_list())]
			for ch in c.get_children():
				if ch is CollisionShape3D and (ch as CollisionShape3D).shape:
					what += " shape %s" % (ch as CollisionShape3D).shape.get_class()
			names.append("%s (%s) at %s %s" % [c.name, par.name if par else "-", str((c as Node3D).global_position.snapped(Vector3.ONE * 0.1)) if c is Node3D else "-", what])
		var np := NavigationServer3D.map_get_closest_point(map, p)
		print("[woodsstuck] solid within 1.6 m of %s (navmesh %.2f m away): %s" % [str(p), np.distance_to(p), "; ".join(names)])
	var shrine: Interactable = area.interactables.get("spot:woods_shrine")
	if shrine == null:
		t._check(false, "the wayshrine stands in the woods")
		return
	var goal: Vector3 = shrine.approach_point()
	var ok := 0
	for p in STARTS:
		var from_nav := NavigationServer3D.map_get_closest_point(map, p)
		var path := NavigationServer3D.map_get_path(map, from_nav, goal, true)
		var corners := []
		for i in range(path.size()):
			corners.append(str(path[i].snapped(Vector3.ONE * 0.1)))
		print("[woodsstuck] path %s -> %s: %d points %s" % [str(p), str(goal.snapped(Vector3.ONE * 0.01)), path.size(), ", ".join(corners)])
		mika.global_position = p + Vector3(30, 0, 30)
		if main.teleport_guard:
			main.teleport_guard.allow(luna)
		luna.stop_action()
		luna.visible = true
		luna.set_physics_process(true)
		luna.global_position = from_nav
		luna.velocity = Vector3.ZERO
		await t._wait(0.6)
		var res := [null]
		var cb := func(a, okk, detail): if a == "navigate_to": res[0] = [okk, detail]
		luna.action_finished.connect(cb)
		luna.navigate_to(goal, false)
		var t0 := Time.get_ticks_msec()
		var far := luna.global_position.distance_to(goal)
		while res[0] == null and Time.get_ticks_msec() - t0 < int(far / 0.7 * 1000.0) + 20000:
			await t._wait(0.25)
		luna.action_finished.disconnect(cb)
		if res[0] == null:
			luna.stop_action()
			res[0] = [false, "still walking at the time limit"]
		var good: bool = res[0][0]
		print("[woodsstuck]   walk %s: %s, ends at %s (%.1f m from the goal)" % ["OK" if good else "FAIL", res[0][1],
			str(luna.global_position.snapped(Vector3.ONE * 0.1)), luna.global_position.distance_to(goal)])
		if good:
			ok += 1
	t._check(ok == STARTS.size(), "the wayshrine can be walked to from where the girls come into the woods (%d of %d)" % [ok, STARTS.size()])
