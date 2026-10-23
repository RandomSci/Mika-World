extends RefCounted
## --mktest=spotlook (23 Oct): every small place (PlaceSpots) seen once on the GPU, Mika standing beside it, a whole
## body three-quarter shot from 6 m, by day (--spotlook-night for night). One mark per spot ("[spotlook] <spot> at
## frame N"), so gpu_marked-style stills can be cut from the movie and judged by eye. --spots-areas=a,b limits it.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("spot look")
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	if main.day_night:
		main.day_night.set_override(RenderProfile.options.has("spotlook-night"))
	var mc: WorldCharacter = main.characters["mika"]
	var lc: WorldCharacter = main.characters.get("luna")
	var only := String(RenderProfile.options.get("spots-areas", ""))
	var areas: Array = load("res://scripts/tests/ext/spots.gd").ORDER if only == "" else Array(only.split(","))
	var shots := 0
	for a in areas:
		if main.streaming.current_id != a:
			await main.streaming.travel(a, mc, false)
		await t._wait(2.0)
		var area = main.streaming.current
		for k in area.interactables.keys():
			if not String(k).begins_with("spot:"):
				continue
			var it: Interactable = area.interactables[k]
			var p := it.global_position
			var stand := it.approach_point()
			for c in [mc, lc]:
				if c and main.teleport_guard:
					main.teleport_guard.allow(c)
			mc.global_position = stand
			mc.look_at_point(p)
			if lc:
				lc.global_position = NavigationServer3D.map_get_closest_point(mc.get_world_3d().navigation_map, stand + (stand - p).normalized().rotated(Vector3.UP, 1.2) * 1.4)
				lc.look_at_point(p)
			var mid := (p + stand) * 0.5
			var side := (stand - p)
			side.y = 0
			side = side.normalized() if side.length() > 0.1 else Vector3.BACK
			# a clear line from the lens to them (the first stills had the lens inside a trunk or the prop itself)
			var space := mc.get_world_3d().direct_space_state
			var cam := mid + side.rotated(Vector3.UP, 0.7) * 6.0 + Vector3(0, 1.7, 0)
			for turn in [0.7, -0.7, 1.4, -1.4, 0.0, 2.2, -2.2, 3.0]:
				var c2: Vector3 = mid + side.rotated(Vector3.UP, turn) * 6.0 + Vector3(0, 1.7, 0)
				var q := PhysicsRayQueryParameters3D.create(mid + Vector3(0, 1.0, 0), c2)
				q.exclude = [mc.get_rid()] + ([lc.get_rid()] if lc else [])
				if space.intersect_ray(q).is_empty():
					cam = c2
					break
			main.director.begin_scene(func(_d): return {"pos": cam, "look": mid + Vector3(0, 0.9, 0), "fov": 55.0, "rate": 30.0})
			await t._wait(1.6)
			print("[spotlook] %s %s at frame %d" % [a, String(k).trim_prefix("spot:"), Engine.get_frames_drawn()])
			shots += 1
			await t._wait(0.4)
			main.director.end_scene()
	t._check(shots > 0, "%d places seen" % shots)
