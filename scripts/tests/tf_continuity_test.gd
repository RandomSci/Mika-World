extends Node
## --tfcontinuity=<dir> [--tfcontinuity-places=a,b,c] - the continuity rule for transformations: in each place (a
## registry location reached by dev fast travel before the test begins) the living world runs until both mages are
## busy with something; a BEFORE screenshot; a transformation (Mika L10, Luna L10, Mika L20 in turn, permanent, on the
## test save); an AFTER screenshot from the restored camera the moment it ends, and another a few seconds later
## (resumed activity). Logs both characters' area, position, rotation and activity before / after; fails when anyone
## moved, the area changed or the camera did not come back. Needs --dev-fast-travel.

var main: Node
var out := ""
var results: Array = []


func _ready() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _state() -> Dictionary:
	var d := {"area": String(main.streaming.current_id)}
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		var b = main.mage_brains.get(who)
		d[who] = {"pos": [snappedf(c.global_position.x, 0.001), snappedf(c.global_position.y, 0.001), snappedf(c.global_position.z, 0.001)],
			"yaw": snappedf(rad_to_deg(c.global_rotation.y), 0.01), "seated": c.seated, "avatar": c.avatar_path.get_file(),
			"activity": String((b.current as Dictionary).get("label", "")) if b else "", "action": c.current_action}
	var cam := get_viewport().get_camera_3d()
	if cam:
		d["camera"] = [snappedf(cam.global_position.x, 0.01), snappedf(cam.global_position.y, 0.01), snappedf(cam.global_position.z, 0.01), snappedf(cam.fov, 0.1)]
	return d


## Mid-cutscene: replies to viewers must be paused (TransformationDirector.playing) and nothing may call the LLM / TTS.
func _mid_check(i: int) -> void:
	var d = main.transformer
	print("[tfcont] MID %d director.playing=%s sequence.playing=%s" % [i, String(d.playing), String(d.sequence.playing)])
	await _shot("%02d_mid_cutscene" % i)


var _back_state := {}
var _front_state := {}


## The moment the flash has cleared: the state (and the screenshot) right as she is back.
func _on_beat(name: String, _t: float, i: int) -> void:
	if name == "00_before_flash":
		_front_state = _state()
		var loc0 := String(String(RenderProfile.options.get("tfcontinuity-places", "ritual_sanctuary,village_square,academy_courtyard")).split(",")[i])
		await _shot("%02d_%s_before" % [i, loc0])
	if name == "06_back_in_the_world":
		_back_state = _state()
		var loc := String(String(RenderProfile.options.get("tfcontinuity-places", "ritual_sanctuary,village_square,academy_courtyard")).split(",")[i])
		await _shot("%02d_%s_after" % [i, loc])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	out = String(RenderProfile.options.get("tfcontinuity", "user://tfcontinuity"))
	DirAccess.make_dir_recursive_absolute(out)
	var places := String(RenderProfile.options.get("tfcontinuity-places", "ritual_sanctuary,village_square,academy_courtyard")).split(",")
	var plan := [["luna", 10], ["mika", 10], ["mika", 20]]          # Luna where she is (the sanctuary), then Mika as she travels
	await _wait(6.0)
	for i in places.size():
		var loc := String(places[i])
		for l in WorldState.locations:
			WorldState.visited_locations[l] = maxi(1, int(WorldState.visited_locations.get(l, 0)))
		if WorldState.area_of(loc) != String(main.streaming.current_id):
			for w in main.mage_brains:                  # (a planner's own journey must not race the test's fast travel)
				main.mage_brains[w].hold = true
			while main.travel.active() or main.characters.mika.casting:
				await _wait(0.5)
			var r: Dictionary = main.travel.travel_to(loc, "fast")
			print("[tfcont] travel %s -> %s" % [loc, JSON.stringify(r)])
			var t0 := Time.get_ticks_msec()
			while (main.travel.active() or main.streaming.state != "idle") and Time.get_ticks_msec() - t0 < 60000:
				await _wait(0.5)
			for w in main.mage_brains:
				main.mage_brains[w].hold = false
		# let the living world carry on until both are doing something
		var t1 := Time.get_ticks_msec()
		await _wait(12.0)
		while Time.get_ticks_msec() - t1 < 40000:
			var busy := 0
			for who in main.mage_brains:
				if not (main.mage_brains[who].current as Dictionary).is_empty():
					busy += 1
			if busy >= 2:
				break
			await _wait(1.0)
		var who := String(plan[i % plan.size()][0])
		var lvl := int(plan[i % plan.size()][1])
		var before := _state()
		print("[tfcont] BEFORE %s %s" % [loc, JSON.stringify(before)])
		get_tree().create_timer(4.0).timeout.connect(_mid_check.bind(i))
		var t_play := Time.get_ticks_msec()
		main.transformer.sequence.beat.connect(_on_beat.bind(i), CONNECT_REFERENCE_COUNTED)
		if RenderProfile.options.has("tfcontinuity-swap"):
			var cc: WorldCharacter = main.characters[who]
			var path := cc.avatar_path if String(RenderProfile.options.get("tfcontinuity-swap")) == "same" else String(TransformationSequence.target_avatar(who, lvl).avatar)
			print("[tfcont] bare swap %s -> %s" % [who, path.get_file()])
			cc.swap_avatar(path)
			await _wait(20.0)
			print("[tfcont] swap place %d survived" % i)
			continue
		var res: Dictionary = {} if RenderProfile.options.has("tfcontinuity-dry") else (await main.transformer.sequence.play(who, lvl, "full", {"preview": false}) if RenderProfile.options.has("tfcontinuity-direct") else await main.transformer.play(who, "full", RenderProfile.options.has("tfcontinuity-preview"), lvl))
		if RenderProfile.options.has("tfcontinuity-dry"):
			await _wait(20.0)
			print("[tfcont] dry place %d survived" % i)
			continue
		main.transformer.sequence.beat.disconnect(_on_beat)
		print("[tfcont] play %s L%d took %.2f s" % [who, lvl, (Time.get_ticks_msec() - t_play) / 1000.0])
		var after: Dictionary = _back_state if not _back_state.is_empty() else _state()
		if not _front_state.is_empty():
			before = _front_state                 # the exact moment the flash began
		_back_state = {}
		_front_state = {}
		# the first activity each one takes up once she is back
		var first := {}
		var tw := Time.get_ticks_msec()
		while Time.get_ticks_msec() - tw < 8000 and first.size() < main.characters.size():
			for w in main.characters:
				var bb = main.mage_brains.get(w)
				var lab := String((bb.current as Dictionary).get("label", "")) if bb else ""
				if lab != "" and not first.has(w):
					first[w] = lab
			await _wait(0.2)
		await _wait(1.0)
		var later := _state()
		await _shot("%02d_%s_after_5s" % [i, loc])
		var ok: bool = after.area == before.area
		var moved := {}
		for w in main.characters:
			var a: Array = before[w].pos
			var b: Array = after[w].pos
			var d := Vector3(a[0], a[1], a[2]).distance_to(Vector3(b[0], b[1], b[2]))
			moved[w] = snappedf(d, 0.001)
			ok = ok and d < 0.05 and absf(wrapf(float(after[w].yaw) - float(before[w].yaw), -180.0, 180.0)) < 1.0
		var resumed := {}
		for w in main.characters:
			var act := String(before[w].activity)
			resumed[w] = {"before": act, "first_after": String(first.get(w, "")), "same": act == "" or act.ends_with("(out of view)") or act == String(first.get(w, ""))}
		var cont: Dictionary = res.get("continuity", {})
		var cam_ok: bool = float(cont.get("camera_error", 1.0)) >= 0.0 and float(cont.get("camera_error", 1.0)) < 0.01 and before.has("camera") and after.has("camera") and Vector3(before.camera[0], before.camera[1], before.camera[2]).distance_to(Vector3(after.camera[0], after.camera[1], after.camera[2])) < 0.05
		for w in (cont.get("chars", {}) as Dictionary):
			ok = ok and float(cont.chars[w].pos_error) < 0.01
		for w in resumed:
			ok = ok and bool(resumed[w].same)
		ok = ok and String(after[who].avatar) != String(before[who].avatar) or String(res.get("avatar", "")) == String(before[who].avatar)
		var r := {"place": loc, "who": who, "level": lvl, "ok": ok and cam_ok, "moved_m": moved, "camera_back": cam_ok, "resumed": resumed,
			"result": {"ok": res.get("ok"), "avatar": res.get("avatar"), "continuity": res.get("continuity", {})}, "before": before, "after": after, "after_5s": later}
		results.append(r)
		print("[tfcont] RESULT %s" % JSON.stringify(r))
	# skip after the first viewing: Mika L10 again (already seen) - a viewer types skip 2.5 s in
	get_tree().create_timer(2.5).timeout.connect(func(): print("[tfcont] skip request -> ", main.transformer.sequence.request_skip("test viewer")))
	var t_skip := Time.get_ticks_msec()
	main.transformer.sequence.beat.connect(func(n, tt): print("[tfcont] skip-run beat %s at %.2f s" % [n, (Time.get_ticks_msec() - t_skip) / 1000.0]))
	var rs: Dictionary = await main.transformer.play("mika", "full", false, 10)
	var skip_r := {"place": "skip", "ok": bool(rs.get("skipped", false)) and (Time.get_ticks_msec() - t_skip) < 6000, "seconds": (Time.get_ticks_msec() - t_skip) / 1000.0, "result": rs}
	results.append(skip_r)
	print("[tfcont] SKIP %s" % JSON.stringify(skip_r))
	await _shot("99_after_skip")
	var f := FileAccess.open(out + "/report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	print("[tfcont] done %d/%d ok" % [results.filter(func(x): return x.ok).size(), results.size()])
	get_tree().quit()
