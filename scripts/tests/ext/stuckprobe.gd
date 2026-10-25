extends RefCounted
## --mktest=stuckprobe (25 Oct live: Luna stuck 37 times at one lake spot, 32 at the waterfall bridge, Mika 43 times in the
## village square, each at the very same coordinates): what is solid around each spot, how far the navmesh runs from it,
## and whether a walk from it to a point 8 m along the navmesh gets through. Marks "[stuckprobe] ...".

const CASES := [
	["lantern_lake", Vector3(-18.9, 1.6, 30.2)],
	["lantern_lake", Vector3(5.1, 3.3, 37.2)],
	["river_valley", Vector3(113.2, 3.3, 17.8)],
	["village", Vector3(-10.6, 0.0, 4.4)],
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
		if main.streaming.current_id != area:
			await main.streaming.travel(area, mika)
		await t._wait(2.0)
		var map: RID = luna.get_world_3d().navigation_map
		var space := luna.get_world_3d().direct_space_state
		var on_nav := NavigationServer3D.map_get_closest_point(map, p)
		print("[stuckprobe] %s %s: navmesh closest %s (%.2f m)" % [area, str(p), str(on_nav), on_nav.distance_to(p)])
		var q := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new()
		s.radius = 1.0
		q.shape = s
		q.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
		q.collision_mask = 0xFFFFFFFF
		q.exclude = [luna.get_rid(), mika.get_rid()]
		for hit in space.intersect_shape(q, 16):
			var c = hit.collider
			var layer: int = c.collision_layer if "collision_layer" in c else -1
			var path := ""
			if c is Node:
				path = str((c as Node).get_path()).replace(str(main.get_path()), "")
			print("[stuckprobe]   solid: %s (%s) layer %d at %s" % [path, c.get_class(), layer, str((c as Node3D).global_position.snapped(Vector3.ONE * 0.1)) if c is Node3D else "-"])
		# the walk: Luna from the spot, Mika standing 8 m away in four directions
		var through := 0
		for k in 8:
			var from_live := k >= 4
			var dir: Vector3 = [Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, -8)][k % 4]
			var goal := NavigationServer3D.map_get_closest_point(map, on_nav + dir)
			if goal.distance_to(on_nav) < 3.0:
				continue
			if main.teleport_guard:
				main.teleport_guard.allow(luna)
			luna.stop_action()
			luna.visible = true
			luna.set_physics_process(true)
			luna.velocity = Vector3.ZERO
			luna.global_position = (p if from_live else on_nav) + Vector3(0, 0.1, 0)
			await t._wait(0.8)
			var down := PhysicsRayQueryParameters3D.create(luna.global_position + Vector3(0, 0.3, 0), luna.global_position + Vector3(0, -2, 0), 0xFFFFFFFF, [luna.get_rid()])
			var floor_hit := space.intersect_ray(down)
			var start := luna.global_position
			print("[stuckprobe]   start %s (%s), settled at %s, floor %s %s" % [str(start.snapped(Vector3.ONE * 0.01)), "live spot" if from_live else "navmesh", str(luna.global_position.snapped(Vector3.ONE * 0.01)), str(floor_hit.get("collider", null).name if floor_hit else "none"), str((floor_hit.position as Vector3).snapped(Vector3.ONE * 0.01)) if floor_hit else ""])
			var res := [null]
			var cb := func(_a, okk, detail): res[0] = "%s %s" % ["ok" if okk else "fail", detail]
			luna.action_finished.connect(cb, CONNECT_ONE_SHOT)
			luna.navigate_to(goal)
			var t0 := Time.get_ticks_msec()
			while res[0] == null and Time.get_ticks_msec() - t0 < 20000:
				await t._wait(0.25)
			var d := luna.global_position.distance_to(goal)
			var good := d < 1.5
			print("[stuckprobe]   walk %s -> %s: %s, %.1f m left, %s" % [str(on_nav.snapped(Vector3.ONE * 0.1)), str(goal.snapped(Vector3.ONE * 0.1)), "OK" if good else "STUCK", d, str(res[0])])
			if good:
				through += 1
			else:
				print("[stuckprobe]   stopped at %s" % str(luna.global_position.snapped(Vector3.ONE * 0.1)))
		if through > 0:
			ok += 1
	t._check(true, "probe ran over %d spots (%d with at least one clear walk)" % [CASES.size(), ok])
