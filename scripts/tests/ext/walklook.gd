extends RefCounted
## --mktest=walklook (23 Oct, Selwyn: "the way she walks, her feet is causing conflict"): Mika (and Luna) walk a
## straight line on the sanctuary's flat ground, filmed from the side and from the front, so the feet can be judged
## frame by frame at 10 fps. Marks "[walklook] <who> <view> start at frame N" / "... end at frame N".


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("walk look")
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = true
	await t._wait(2.0)
	var map: RID = main.characters["mika"].get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, Vector3(-6, 0, 18))
	var b := NavigationServer3D.map_get_closest_point(map, Vector3(14, 0, 18))
	for who in ["mika", "luna"]:
		var c: WorldCharacter = main.characters.get(who)
		if c == null:
			continue
		var other: WorldCharacter = main.characters.get("luna" if who == "mika" else "mika")
		for view in ["side", "front"]:
			if main.teleport_guard:
				main.teleport_guard.allow(c)
				if other:
					main.teleport_guard.allow(other)
			if other:
				other.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 40))
			c.global_position = a if view == "side" else b
			await t._wait(1.0)
			var target := b if view == "side" else a
			var live := [c]
			main.director.begin_scene(func(_d):
				var p: Vector3 = (live[0] as Node3D).global_position
				if view == "side":
					return {"pos": p + Vector3(0, 0.9, 3.6), "look": p + Vector3(0, 0.75, 0), "fov": 40.0, "rate": 30.0}
				var dir := (target - p)
				dir.y = 0
				dir = dir.normalized() if dir.length() > 0.2 else Vector3.LEFT
				return {"pos": p + dir * 3.4 + Vector3(0, 0.9, 0), "look": p + Vector3(0, 0.7, 0), "fov": 40.0, "rate": 30.0})
			c.navigate_to(target, false)
			await t._wait(2.0)
			print("[walklook] %s %s start at frame %d" % [who, view, Engine.get_frames_drawn()])
			await t._wait(3.0)
			print("[walklook] %s %s end at frame %d" % [who, view, Engine.get_frames_drawn()])
			c.stop_action()
			main.director.end_scene()
	t._check(true, "walks filmed")
