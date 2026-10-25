extends RefCounted
## --mktest=stuckblock (25 Oct live): someone standing on a narrow way (the waterfall bridge, the lake hill track, the
## village square by the bench) while she walks through it. Mika stands still on Luna's path 1.6 m ahead; Luna must
## get past and arrive. Marks "[stuckblock] ...".

const CASES := [
	["river_valley", Vector3(113.2, 3.3, 17.7), Vector3(100.0, 2.3, 17.9)],
	["lantern_lake", Vector3(5.1, 3.3, 37.2), Vector3(4.068, 1.064, 15.379)],
	["lantern_lake", Vector3(-18.9, 1.6, 30.2), Vector3(-15.121, 3.682, 39.2)],
	["village", Vector3(-10.6, 0.0, 4.5), Vector3(-14.0, 0.0, 8.0)],
]


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	var ok := 0
	for cs in CASES:
		var area: String = cs[0]
		var p: Vector3 = cs[1]
		var map: RID
		if main.streaming.current_id != area:
			await main.streaming.travel(area, mika)
		await t._wait(2.0)
		map = luna.get_world_3d().navigation_map
		var goal := NavigationServer3D.map_get_closest_point(map, cs[2])
		var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, p), goal, true)
		# Mika 1.6 m along Luna's path, standing still
		var block := p
		var left := 1.6
		for i in range(1, path.size()):
			var seg: float = path[i - 1].distance_to(path[i])
			if seg >= left:
				block = path[i - 1].lerp(path[i], left / seg)
				break
			left -= seg
		for c in [luna, mika]:
			if main.teleport_guard:
				main.teleport_guard.allow(c)
			c.stop_action()
			c.visible = true
			c.set_physics_process(true)
			c.velocity = Vector3.ZERO
		luna.global_position = p
		mika.global_position = block
		await t._wait(0.8)
		var res := [null]
		var cb := func(a, okk, detail): if a == "navigate_to": res[0] = [okk, detail]
		luna.action_finished.connect(cb)
		luna.navigate_to(goal, false)
		var t0 := Time.get_ticks_msec()
		while res[0] == null and Time.get_ticks_msec() - t0 < int(luna.global_position.distance_to(goal) / 1.0 * 1000.0) + 15000:
			await t._wait(0.25)
		luna.action_finished.disconnect(cb)
		if res[0] == null:
			luna.stop_action()
			res[0] = [false, "still walking at the time limit"]
		var good: bool = luna.global_position.distance_to(goal) < 1.6   # (there: arrived, or standing at it when the time ran out)
		print("[stuckblock] %s from %s, Mika standing at %s: %s (%s), %.1f m from the goal" % [area, str(p), str(block.snapped(Vector3.ONE * 0.1)),
			"OK" if good else "STUCK", res[0][1], luna.global_position.distance_to(goal)])
		if good:
			ok += 1
	t._check(ok == CASES.size(), "she gets past someone standing in her way (%d of %d)" % [ok, CASES.size()])
