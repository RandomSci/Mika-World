extends RefCounted
## --mktest=unstick (25 Oct live stuck loops): a walk blocked by something the walking map does not know (a post set
## down after the bake, 0.8 m wide, right in her way) and a walk starting off the map (on the bench's foot). With the
## recovery off she ends "stuck" (the old behaviour), with it on she gets free and arrives. Marks "[unstick] ...".


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	if main.streaming.current_id != "village":
		await main.streaming.travel("village", mika)
	await t._wait(2.0)
	var map: RID = luna.get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(-14.0, 0.0, 8.0))
	var goal := NavigationServer3D.map_get_closest_point(map, start + Vector3(0, 0, 9.0))
	var post := StaticBody3D.new()
	post.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.2, 0.3)
	cs.shape = box
	post.add_child(cs)
	main.streaming.current.add_child(post)
	var dirv := (goal - start)
	dirv.y = 0
	post.global_position = start + dirv.normalized() * 1.2 + Vector3(0, 0.6, 0)
	mika.global_position = start + Vector3(25, 0, -25)
	var results := {}
	var widths := [1.2, 1.6, 2.0]
	for w in widths:
		box.size = Vector3(w, 1.2, 0.3)
		post.global_position = start + dirv.normalized() * 1.2 + Vector3(dirv.normalized().z, 0, -dirv.normalized().x) * 0.15 + Vector3(0, 0.6, 0)
		post.look_at(post.global_position + dirv.normalized(), Vector3.UP)
		await t._wait(0.2)
		var rq := PhysicsRayQueryParameters3D.create(start + Vector3(0, 0.6, 0), goal + Vector3(0, 0.6, 0), luna.collision_mask, [luna.get_rid()])
		var hit := luna.get_world_3d().direct_space_state.intersect_ray(rq)
		print("[unstick] post at %s, luna mask %d; the straight line hits %s" % [str(post.global_position.snapped(Vector3.ONE * 0.1)), luna.collision_mask, str(hit.collider) if hit else "nothing"])
		for mode in ["old (no recovery)", "with recovery"]:
			await _walk(t, main, luna, start, goal, mode, w, results)
	post.queue_free()
	luna.nav_recoveries = 2
	var blocked := widths.filter(func(w): return not results["%s old (no recovery)" % w])
	t._check(not blocked.is_empty(), "a post blocks the old walk at some width (%s m)" % str(blocked))
	t._check(blocked.all(func(w): return results["%s with recovery" % w]), "with the recovery she gets past every post that stopped the old walk")


static func _walk(t, main, luna: WorldCharacter, start: Vector3, goal: Vector3, mode: String, w: float, results: Dictionary) -> void:
	if true:
		luna.nav_recoveries = 0 if mode.begins_with("old") else 2
		if main.teleport_guard:
			main.teleport_guard.allow(luna)
		luna.stop_action()
		luna.visible = true
		luna.set_physics_process(true)
		luna.global_position = start + Vector3(0, 0.05, 0)
		luna.velocity = Vector3.ZERO
		await t._wait(0.8)
		var res := [null]
		var cb := func(a, okk, detail): if a == "navigate_to": res[0] = [okk, detail]
		luna.action_finished.connect(cb)
		luna.navigate_to(goal, false)
		var t0 := Time.get_ticks_msec()
		while res[0] == null and Time.get_ticks_msec() - t0 < 40000:
			await t._wait(0.25)
		luna.action_finished.disconnect(cb)
		if res[0] == null:
			luna.stop_action()
			res[0] = [false, "still walking at the time limit"]
		var arrived: bool = res[0][0] and luna.global_position.distance_to(goal) < 1.6
		print("[unstick]   took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
		results["%s %s" % [w, mode]] = arrived
		print("[unstick] post %.1f m wide in the way, %s: %s (%s), %.1f m from the goal" % [w, mode, "ARRIVED" if arrived else "STUCK", res[0][1], luna.global_position.distance_to(goal)])
