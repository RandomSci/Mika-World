extends RefCounted
## --mktest=towerstuck (26 Oct live, Mentor's Tower): the exact walks that ended "stuck" again and again, from the spot where she
## stood to the target the log shows, with the path the navmesh gives (its first corners) and where she ends.
## Marks "[towerstuck] ...".

const CASES := [
	["mentor_tower", Vector3(-33.5, 1.2, 19.6), Vector3(-34.951, 2.965, 39.956)],
	["mentor_tower", Vector3(-34.3, 1.4, 21.8), Vector3(-34.951, 2.965, 39.956)],
	["mentor_tower", Vector3(-89.9, -0.1, 22.5), Vector3(-41.68, -0.258, 11.05)],
	["mentor_tower", Vector3(-44.1, -0.6, 9.4), Vector3(-34.951, 2.965, 39.956)],
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
		var goal: Vector3 = cs[2]
		if main.streaming.current_id != area:
			await main.streaming.travel(area, mika)
		await t._wait(2.0)
		mika.global_position = p + Vector3(30, 0, 30)   # out of the way
		var map: RID = luna.get_world_3d().navigation_map
		var from_nav := NavigationServer3D.map_get_closest_point(map, p)
		var path := NavigationServer3D.map_get_path(map, from_nav, goal, true)
		var corners := []
		for i in range(mini(path.size(), 5)):
			corners.append(str(path[i].snapped(Vector3.ONE * 0.1)))
		print("[towerstuck] %s %s -> %s: her spot is %.2f m off the navmesh (%s); path %d points, first %s" % [area, str(p), str(goal),
			from_nav.distance_to(p), str(from_nav.snapped(Vector3.ONE * 0.01)), path.size(), ", ".join(corners)])
		if main.teleport_guard:
			main.teleport_guard.allow(luna)
		luna.stop_action()
		luna.visible = true
		luna.set_physics_process(true)
		luna.global_position = p
		luna.velocity = Vector3.ZERO
		await t._wait(0.6)
		var space := luna.get_world_3d().direct_space_state
		var down := PhysicsRayQueryParameters3D.create(luna.global_position + Vector3(0, 1.0, 0), luna.global_position + Vector3(0, -2, 0), 0xFFFFFFFF, [luna.get_rid()])
		var fh := space.intersect_ray(down)
		print("[towerstuck]   she settles at %s (floor %s), ground under her: %s at %s" % [str(luna.global_position.snapped(Vector3.ONE * 0.01)), str(luna.is_on_floor()),
			str((fh.collider as Node).name) if fh else "none", str((fh.position as Vector3).snapped(Vector3.ONE * 0.01)) if fh else "-"])
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
		print("[towerstuck]   walk %s: %s, ends at %s (%.1f m from the goal)" % ["OK" if good else "FAIL", res[0][1],
			str(luna.global_position.snapped(Vector3.ONE * 0.1)), luna.global_position.distance_to(goal)])
		if good:
			ok += 1
	t._check(ok == CASES.size(), "every live stuck walk gets through (%d of %d)" % [ok, CASES.size()])
