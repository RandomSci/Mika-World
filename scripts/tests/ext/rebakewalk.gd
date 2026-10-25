extends RefCounted
## --mktest=rebakewalk (25 Oct live stuck loops at Lantern Lake): the walking map rebuilt while she walks (the lake
## dance re-bakes it twice a night, an arrival with no path re-bakes it): does the walk carry on, old way and with the
## recovery. Marks "[rebakewalk] ...".


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	if main.streaming.current_id != "lantern_lake":
		await main.streaming.travel("lantern_lake", mika)
	await t._wait(2.0)
	var area = main.streaming.current
	var map: RID = luna.get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(5.1, 3.3, 37.2))
	var goal := NavigationServer3D.map_get_closest_point(map, Vector3(4.068, 1.064, 15.379))
	mika.global_position = goal + Vector3(20, 0, 0)
	var results := {}
	for mode in ["old (no recovery)", "with recovery"]:
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
		await t._wait(1.5)
		area.bake_navigation()                 # (not awaited: she walks on while it bakes)
		var t0 := Time.get_ticks_msec()
		while res[0] == null and Time.get_ticks_msec() - t0 < 45000:
			await t._wait(0.25)
		luna.action_finished.disconnect(cb)
		if res[0] == null:
			luna.stop_action()
			res[0] = [false, "still walking at the time limit"]
		var arrived: bool = res[0][0] and luna.global_position.distance_to(goal) < 1.6
		results[mode] = arrived
		print("[rebakewalk] re-bake mid walk, %s: %s (%s), %.1f m from the goal" % [mode, "ARRIVED" if arrived else "STUCK", res[0][1], luna.global_position.distance_to(goal)])
		await t._wait(3.0)
	luna.nav_recoveries = 2
	t._check(results["with recovery"], "with the recovery the walk survives a re-bake")
