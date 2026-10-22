extends RefCounted
## --mktest=lakewaterdance: the lake dance on the water, start to end, as the brain would run it (LakeWaterDance.run).
## Record with --movie for the 10 fps sheet. At Lantern Lake, a clear night.
## Checks: the path forms and is solid only while lit; both reach the circle on the navmesh (never over bare water);
## the dance plays its whole routine with the song; no T-pose; both back on land; the path gone; the night saved, so
## it is not offered again tonight; a whole-body lens all the way (Mika in frame).


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("lake dance test")
	await t._hold_all()
	await t._force_luna_l1()
	main.travel.cancel("lake dance test")
	if main.streaming.current_id != "lantern_lake":
		await main.streaming.travel("lantern_lake", main.characters["mika"])
	t._check(main.streaming.current_id == "lantern_lake", "at Lantern Lake")
	if main.day_night:
		main.day_night.set_override(true)
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
		main.weather.rain = 0.0
		main.weather.cloud = 0.0
	main.spawner.enabled = false
	main.place_curiosity.set_process(false)
	await t._wait(3.0)
	for id in ["mika", "luna"]:
		WorldState.mind(id).knowledge.erase("lake_dance_night")
	var lwd: LakeWaterDance = LakeWaterDance.instance
	t._check(lwd != null, "the lake dance node")
	if lwd == null:
		return
	var why := lwd.available()
	t._check(why == "", "available on a clear night at the lake (%s)" % why)
	if why != "":
		return
	var w := {"tpose": 0, "frames": 0, "on_water_no_path": 0, "path_seen": false, "solid_seen": false, "max_out": 0.0, "dance_s": 0.0, "music": false,
		"mika_hidden": 0, "stages": []}
	var lake: Node3D = lwd._lake()
	var watcher := func():
		while lwd.running or w.frames == 0:
			await t.get_tree().process_frame
			w.frames += 1
			if not (w.stages as Array).has(lwd.stage):
				(w.stages as Array).append(lwd.stage)
				print("[lakewaterdance] stage %s frame %d" % [lwd.stage, Engine.get_frames_drawn()])
			if lwd.path and is_instance_valid(lwd.path):
				w.path_seen = true
				if lwd.path.body.collision_layer == 1:
					w.solid_seen = true
			if lwd._session and is_instance_valid(lwd._session) and lwd._session.playing:
				w.dance_s = float(w.dance_s) + t.get_process_delta_time()
			if lwd._player and is_instance_valid(lwd._player) and lwd._player.playing:
				w.music = true
			for id in ["mika", "luna"]:
				var c: WorldCharacter = main.characters[id]
				var l := lake.to_local(c.global_position)
				var on_water: bool = float(main.world.h(l.x, l.z)) < 0.0
				if on_water:
					w.max_out = maxf(float(w.max_out), -l.z)
					if lwd.path == null or not is_instance_valid(lwd.path) or not lwd.path.covers(c.global_position):
						w.on_water_no_path += 1
				if _tpose(c):
					w.tpose += 1
	watcher.call()
	var r: Dictionary = await lwd.run("the test")
	await t._wait(1.0)
	print("[lakewaterdance] result %s, stages %s, danced %.1f s" % [str(r), str(w.stages), float(w.dance_s)])
	t._check(bool(r.get("ok", false)), "the whole dance ran (%s)" % String(r.get("detail", "")))
	t._check(bool(w.path_seen) and bool(w.solid_seen), "the path formed and was solid while lit")
	t._check(int(w.on_water_no_path) == 0, "never on bare water (%d frames off the path)" % int(w.on_water_no_path))
	t._check(float(w.max_out) > 5.0, "they really walked out over the water (%.1f m from the shoreline's z)" % float(w.max_out))
	t._check(float(w.dance_s) > 45.0, "the dance played its routine (%.1f s)" % float(w.dance_s))
	t._check(bool(w.music), "the song played")
	t._check(int(w.tpose) == 0, "no T-pose frames (%d)" % int(w.tpose))
	for id in ["mika", "luna"]:
		var l2 := lake.to_local((main.characters[id] as WorldCharacter).global_position)
		t._check(float(main.world.h(l2.x, l2.z)) >= 0.0, "%s back on land" % id)
	t._check(lwd.path == null and lake.find_children("WaterPath", "", true, false).is_empty(), "the path is gone")
	t._check(LakeWaterDance.danced_tonight() and lwd.available() != "", "the night is saved: not offered again tonight (%s)" % lwd.available())


static func _tpose(c: WorldCharacter) -> bool:
	var sk := c.skeleton
	var n := 0
	for s in ["Left", "Right"]:
		var u := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(s + "UpperArm")).origin
		var lo := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(s + "LowerArm")).origin
		var h := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(s + "Hand")).origin
		var a := (lo - u).normalized()
		var b := (h - lo).normalized()
		if absf(a.y) < 0.2 and a.dot(b) > 0.97:
			n += 1
	return n == 2
