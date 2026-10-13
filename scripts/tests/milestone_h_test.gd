class_name MilestoneHTest
extends Node
## --mhtest=<mode>: Milestone H checks (two mages, progression, combat, fusion, transformations).
##   vrm          every form VRM imports, instantiates as a 54-bone humanoid with expressions; Mika's avatar
##                swaps to her Level 10 form and back with a working animation tree
##   progression  firsts pay once, repeats decay, the Level 10 Orbit Gate blocks until its milestones are met,
##                then the form unlocks; no reward is ever paid twice
##   isolation    Mika's and Luna's minds never share knowledge, items, skills, trials or XP
##   combat       a mage hunts a real creature through her planner option: spells, hits, defeat, physical loot
##                collected into HER inventory, defeat + XP + journal line in HER mind only
##   fusion       both mages strike one creature in the window: Eclipse Convergence fires, both remember it
##   transform    preview (full + short) for both mages: form swaps at the flash, camera never inside geometry,
##                nothing about progression changes, base avatar restored; screenshots at the key beats
##   levelup      on a COPY of the real save (Mika at the Level 10 Orbit Gate): she beats a Thornback through her
##                planner; the gate opens, Level 10, Bloom form unlocks, the full first-time sequence plays on its own
##                when safe, she stays transformed, then the form times out and she reverts
##   persist1/2   Luna's mind (knowledge, inventory, XP, level) survives a restart beside Mika's
## Disposable saves only (user://test_regress_*.json). Prints "[mhtest] PASS|FAIL <mode>"; exit 0 / 1.

var main: Node
var mode := ""
var checks: Array = []
var failed := false
var report := {}
var dir := ""


func _ready() -> void:
	mode = String(RenderProfile.options.get("mhtest", ""))
	dir = RenderProfile.shots_dir + "/mhtest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _check(ok: bool, what: String, detail = "") -> void:
	checks.append({"ok": ok, "check": what, "detail": str(detail).left(400)})
	print("[mhtest]   %s %s %s" % ["ok  " if ok else "FAIL", what, ("(" + str(detail).left(220) + ")") if str(detail) != "" else ""])
	if not ok:
		failed = true


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s_%s.png" % [dir, mode, tag])


func _run() -> void:
	print("[mhtest] mode=%s save=%s persistent=%s mages=%s" % [mode, WorldState.save_path, WorldState.persistent, main.mages])
	if WorldState.persistent and not WorldState.save_path.begins_with("user://test_regress_"):
		_check(false, "refusing to run persistently against a non-test save", WorldState.save_path)
		_finish()
		return
	await _wait(2.0)
	match mode:
		"vrm": await _vrm()
		"progression": _progression()
		"isolation": _isolation()
		"combat": await _combat()
		"fusion": await _fusion()
		"transform": await _transform()
		"levelup": await _levelup()
		"persist1": _persist(1)
		"persist2": _persist(2)
		_: _check(false, "unknown mode " + mode)
	_finish()


func _finish() -> void:
	var f := FileAccess.open("%s/%s.json" % [dir, mode], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"mode": mode, "passed": not failed, "checks": checks, "report": report}, "  "))
		f.close()
	print("[mhtest] %s %s" % ["FAIL" if failed else "PASS", mode])
	get_tree().quit(1 if failed else 0)


# ------------------------------------------------------------------ VRMs
func _vrm() -> void:
	var paths := ["res://assets/characters/mika/Mika.vrm", "res://assets/characters/mika/forms/Mika_Level10.vrm",
		"res://assets/characters/luna/forms/Luna_Level01.vrm", "res://assets/characters/luna/forms/Luna_Level10.vrm"]
	for p in paths:
		var t0 := Time.get_ticks_msec()
		var ps: PackedScene = load(p)
		var n: Node = ps.instantiate() if ps else null
		var sk: Skeleton3D = n.find_child("GeneralSkeleton", true, false) if n else null
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", false, false) if n else null
		_check(sk != null and sk.get_bone_count() >= 50 and sk.find_bone("Head") >= 0 and sk.find_bone("RightHand") >= 0,
			"%s loads as a humanoid" % p.get_file(), "bones %d, %d ms" % [sk.get_bone_count() if sk else 0, Time.get_ticks_msec() - t0])
		_check(ap != null and ap.has_animation("blink") and ap.has_animation("happy"), "%s has VRM expressions" % p.get_file())
		if n:
			n.free()
	var mika: WorldCharacter = main.characters["mika"]
	var base := mika.avatar_path
	_check(mika.swap_avatar("res://assets/characters/mika/forms/Mika_Level10.vrm"), "Mika swaps to her Level 10 form")
	await _wait(1.0)
	_check(mika.body_player.has_animation("mx/idle") and mika.anim_tree.active and mika.skeleton.is_inside_tree(), "animation tree rebuilt on the new skeleton")
	_check(mika.handler.ik != null and mika.handler.ik.is_inside_tree(), "arm IK rebound")
	mika.navigate_to(mika.global_position + Vector3(2, 0, 0))
	await _wait(2.5)
	_shot("mika_level10_walk")
	_check(mika.swap_avatar(base), "and back to her base form")
	if main.characters.has("luna"):
		var luna: WorldCharacter = main.characters["luna"]
		_check(luna.visible and luna.is_physics_processing(), "Luna is present and simulated in the Sanctuary", luna.global_position)
		main.mage_brains["luna"].set_enabled(false)      # her own planner may be mid-cast (a swap is refused then)
		var tw := Time.get_ticks_msec()
		while luna.casting and Time.get_ticks_msec() - tw < 10000:
			await get_tree().process_frame
		_check(luna.swap_avatar("res://assets/characters/luna/forms/Luna_Level10.vrm") and luna.swap_avatar("res://assets/characters/luna/forms/Luna_Level01.vrm"), "Luna swaps forms both ways")


# ------------------------------------------------------------------ progression (pure, on throwaway minds)
func _progression() -> void:
	var p: Progression = main.progression
	var m := WorldState.register_mind("t_prog")
	Progression.mages["t_prog"] = Progression.mages.mika.duplicate(true)
	var e1 := {"activity": {"id": "spell:arcane_orb"}, "changes": {"knowledge.reaction:arcane_orb:dummy:jolted": [0, 1], "knowledge.practical:arcane_orb": [0, 1]}}
	var a1 := Progression.xp_for_entry(m, e1)
	var a2 := Progression.xp_for_entry(m, e1.duplicate(true))
	var s1: float = a1.reduce(func(acc, x): return acc + float(x[0]), 0.0)
	var s2: float = a2.reduce(func(acc, x): return acc + float(x[0]), 0.0)
	_check(s1 == 55.0, "a first reaction + first practical success pay 30 + 25", a1)
	_check(s2 < 5.0, "the same discovery again pays only a small practice amount", a2)
	var kills := []
	for i in 5:
		var r := Progression.xp_for_entry(m, {"activity": {"id": "defeat:gloomwisp"}, "changes": {}})
		kills.append(r.reduce(func(acc, x): return acc + float(x[0]), 0.0))
	_check(kills[0] == 50.0 and kills[1] < kills[0] and kills[4] < kills[2], "first victory is a milestone; later ones decay", kills)
	# drive to the gate with XP only
	m.progress.xp = Progression.xp_for(10) + 50.0
	m.progress.level = 1
	var got := p.check_level("t_prog")
	_check(m.level() == 9, "XP alone stops at Level 9 (Orbit Gate)", "level %d after +%d" % [m.level(), got])
	var g := Progression.gate_status("t_prog", 10)
	_check(g.defined and not g.met, "gate lists what is missing", g.requirements)
	# satisfy the gate for real: rank, a medium victory, two spells
	for t in ["read_first_circle", "read_gate", "warding_glyph"]:
		m.trials_done[t] = true
	m.knowledge["defeated:thornback"] = 1
	m.skills["arcane_orb"] = 0.5
	m.skills["wind_gust"] = 0.2
	var unlocked := []
	p.form_unlocked.connect(func(w, l, f): if w == "t_prog": unlocked.append([l, f.id]))
	p.check_level("t_prog")
	_check(m.level() == 10 and unlocked.size() == 1 and unlocked[0][1] == "bloom", "gate met -> Level 10, Bloom form unlocked once", [m.level(), unlocked])
	p.check_level("t_prog")
	_check(unlocked.size() == 1, "no repeated unlock / reward", unlocked)
	WorldState.minds.erase("t_prog")
	Progression.mages.erase("t_prog")
	report["curve"] = range(1, 12).map(func(l): return [l, snappedf(Progression.xp_for(l), 1.0)])


func _isolation() -> void:
	var a := WorldState.mind("mika")
	var b := WorldState.mind("luna")
	_check(b != a and not b.legacy, "Luna has her own mind")
	WorldState.record_activity({"id": "test:x"}, {"knowledge": {"lore:only_mika": 1}, "items": {"wisp_ember": 2}, "skills": {"arcane_orb": 0.1}}, "mika")
	WorldState.record_activity({"id": "test:y"}, {"knowledge": {"lore:only_luna": 1}, "items": {"thorn_carapace": 1}}, "luna")
	_check(a.knowledge.has("lore:only_mika") and not b.knowledge.has("lore:only_mika"), "Mika's knowledge stays Mika's")
	_check(b.knowledge.has("lore:only_luna") and not a.knowledge.has("lore:only_luna"), "Luna's knowledge stays Luna's")
	_check(int(a.inventory.get("thorn_carapace", 0)) == 0 and int(b.inventory.get("wisp_ember", 0)) == 0, "inventories are separate")
	_check(not b.skills.has("arcane_orb") and main.magic.can_cast("umbral_lance", "luna").ok and not main.magic.can_cast("umbral_lance", "mika").ok, "spells and mastery are separate")
	_check(a.activity_log[-1].who == "mika" and b.activity_log[-1].who == "luna" and a.activity_seq != 0 and b.activity_seq != 0, "each has her own activity log")
	var j := Journal.compose(b)
	_check(not String(j.get("text", "")).contains("only_mika"), "Luna's journal draws only on her log")


# ------------------------------------------------------------------ combat through the planner
func _spawn_near(c: WorldCharacter, kind: String, dist := 9.0) -> Monster:
	var fwd := Vector3(sin(c.rotation.y), 0, cos(c.rotation.y)) * -1.0
	var map: RID = c.get_world_3d().navigation_map
	for ang in [0.0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0, PI]:
		var p := c.global_position + fwd.rotated(Vector3.UP, ang) * dist
		p = NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(p.x, p.z).length() > 13.5:
			return main.spawner.spawn(kind, p)
	return null


func _combat() -> void:
	var who := String(RenderProfile.options.get("who", "luna"))
	var c: WorldCharacter = main.characters[who]
	var b: SanctuaryBrain = main.mage_brains[who]
	var m := WorldState.mind(who)
	var other := "mika" if who == "luna" else "luna"
	var other_inv: Dictionary = WorldState.mind(other).inventory.duplicate() if main.characters.has(other) else {}
	# her own planner must not drive her at the same time as the test (one controller per character)
	b.hold = true
	var tw0 := Time.get_ticks_msec()
	while not b.current.is_empty() and Time.get_ticks_msec() - tw0 < 30000:
		await get_tree().process_frame
	# stand her outside the ward first (east, by the training grounds)
	var map: RID = c.get_world_3d().navigation_map
	c.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(26, 0, 6)) + Vector3(0, 0.1, 0)
	await _wait(1.0)
	var kind := String(RenderProfile.options.get("kind", "gloomwisp"))
	var mon := _spawn_near(c, kind, 9.0)
	_check(mon != null, "a %s appeared near %s" % [kind, who])
	if mon == null:
		return
	await _wait(1.0)
	var opts := b.options().filter(func(o): return o.kind == "hunt" and o.monster == mon.id)
	_check(not opts.is_empty(), "%s's planner offers to fight it (she can see it)" % who, b.options().map(func(o): return o.key))
	if opts.is_empty():
		return
	var scored: Dictionary = opts[0].merged(b.score(opts[0]))
	var xp0 := float(m.progress.xp)
	var t0 := Time.get_ticks_msec()
	_shot("before")
	var res: Dictionary = await b.run_activity(scored)
	_shot("after")
	report["result"] = res
	report["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	report["spawner"] = main.spawner.describe()
	report["vigor"] = m.vigor
	_check(res.get("ok", false), "%s won the fight" % who, res)
	_check(int(m.knowledge.get("defeated:" + kind, 0)) >= 1, "the victory is in her memory")
	var items := m.inventory.keys().filter(func(k): return Spawner.data.items.has(k))
	_check(not items.is_empty(), "she picked up loot (physical pickups) into her inventory", m.inventory)
	_check(WorldState.mind(other).inventory == other_inv, "nothing went into %s's inventory" % other)
	_check(float(m.progress.xp) > xp0 + 49.0, "XP for a first victory (+ firsts on the way)", [xp0, m.progress.xp])
	_check(String(Journal.compose(m).get("text", "")).contains("fought off"), "her journal can tell it", Journal.compose(m))


func _fusion() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = mika.get_world_3d().navigation_map
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(22, 0, 2)) + Vector3(0, 0.1, 0)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(23, 0, 9)) + Vector3(0, 0.1, 0)
	main.mage_brains["luna"].hold = true          # idle her planner without cancelling her movement
	await _wait(1.0)
	var done := false
	for attempt in 4:
		for old in main.spawner.alive:
			old.queue_free()
		await get_tree().process_frame
		var mon: Monster = main.spawner.spawn("thornback")     # a real wild-edge anchor, as in play
		if mon == null:
			continue
		mon.set_physics_process(false)           # it holds still for the test (no wandering, no attacks)
		for pair in [[mika, 1.0], [luna, -1.0]]:
			var side := Vector3(pair[1] * 4.0, 0, 6.0).rotated(Vector3.UP, randf() * 0.5)
			var spot := NavigationServer3D.map_get_closest_point(map, mon.global_position + side)
			(pair[0] as WorldCharacter).global_position = spot + Vector3(0, 0.1, 0)
		await _wait(0.8)
		mon.def = mon.def.duplicate(true)
		mon.def.aggro_radius = 0.0            # it stands still for the test
		await _wait(0.5)
		# take casting positions the way the planner does in play (range, line of sight, space)
		var pos_ok := [await main.mage_brains["mika"]._stand_for_cast("arcane_orb", mon.id), await main.mage_brains["luna"]._stand_for_cast("umbral_lance", mon.id)]
		report["positions_%d" % attempt] = pos_ok
		var results := {}
		_cast_into(results, "mika", mika, "arcane_orb", mon.id)
		# the orb is slower: release Luna's lance later so both land inside the window
		await _wait([4.6, 4.2, 5.0, 3.8][attempt])
		_cast_into(results, "luna", luna, "umbral_lance", mon.id)
		var tw := Time.get_ticks_msec()
		while results.size() < 2 and Time.get_ticks_msec() - tw < 15000:
			await get_tree().process_frame
		var r1: Dictionary = results.get("mika", {})
		var r2: Dictionary = results.get("luna", {})
		report["attempt_%d" % attempt] = {"mika": [r1.get("outcome"), r1.get("effect")], "luna": [r2.get("outcome"), r2.get("effect")], "fusion": main.magic.fusion.log.slice(-1), "pairing": main.magic.fusion.last_check}
		if not main.magic.fusion.log.is_empty():
			done = true
			break
		await _wait(1.0)
	_check(done, "Eclipse Convergence fired from two real hits in the window", report)
	_check(WorldState.mind("mika").knowledge.has("fusion:eclipse_convergence") and WorldState.mind("luna").knowledge.has("fusion:eclipse_convergence"), "both mages remember the fusion (separately)")
	_shot("fusion")


func _cast_into(out: Dictionary, key: String, c: WorldCharacter, spell: String, target: String) -> void:
	out[key] = await main.magic.cast(c, spell, target)


# ------------------------------------------------------------------ transformations (preview)
func _transform() -> void:
	for who in main.mages:
		var c: WorldCharacter = main.characters[who]
		var m := WorldState.mind(who)
		var before := {"xp": m.progress.xp, "level": m.level(), "forms": (m.progress.forms_unlocked as Array).duplicate(), "know": m.knowledge.size()}
		var base := c.avatar_path
		for version in ["full", "short"]:
			var blocked := 0
			var frames := 0
			var min_d := 99.0
			var worst := 0.0
			var phases := {}
			var shots := {}
			var v: Dictionary = TransformationDirector.data.versions[version]
			var n_log: int = main.transformer.log.size()
			main.transformer.play(who, version, true)        # runs on its own; result lands in transform.log
			var t0 := Time.get_ticks_msec()
			while main.transformer.playing == who:
				await get_tree().process_frame
				var cam: Camera3D = main.transformer.cam
				var t := (Time.get_ticks_msec() - t0) / 1000.0
				frames += 1
				var look: Vector3 = main.transformer._look_point(c, "chest")
				var q := PhysicsRayQueryParameters3D.create(look, cam.global_position)
				q.collision_mask = 1
				q.exclude = main.characters.values().map(func(x): return (x as CollisionObject3D).get_rid())
				if not c.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					blocked += 1
				min_d = minf(min_d, cam.global_position.distance_to(c.global_position + Vector3(0, 1.0, 0)))
				var ft := get_process_delta_time() * 1000.0
				worst = maxf(worst, ft)
				var st: float = main.transformer.seq_t
				var ph := "staging" if st < 0.0 else ("buildup" if st < float(v.swap) - 0.3 else ("swap" if st < float(v.swap) + 0.6 else "after"))
				var b: Array = phases.get_or_add(ph, [0, 0.0, 0.0])
				b[0] += 1
				b[1] += ft
				b[2] = maxf(b[2], ft)
				for beat in [["buildup", float(v.swap) * 0.5], ["hands", float(v.gesture_at) + 1.0], ["reveal", float(v.swap) + 0.9], ["pose", float(v.pose_at) + 1.0], ["end", float(v.length) - 0.6]]:
					if t >= beat[1] and not shots.has(beat[0]):
						shots[beat[0]] = true
						_shot("%s_%s_%s" % [who, version, beat[0]])
			while main.transformer.log.size() == n_log and Time.get_ticks_msec() - t0 < 30000:
				await get_tree().process_frame
			var res: Dictionary = main.transformer.log[-1] if main.transformer.log.size() > n_log else {}
			report["%s_%s" % [who, version]] = {"result": res, "frames": frames, "camera_blocked_frames": blocked, "camera_min_distance_m": snappedf(min_d, 0.01), "worst_frame_ms": snappedf(worst, 0.1), "avg_fps": snappedf(frames / maxf(float(res.get("seconds", 1.0)), 0.1), 0.1),
				"phases": phases.keys().map(func(k): return [k, phases[k][0], snappedf(1000.0 * phases[k][0] / maxf(phases[k][1], 1.0), 0.1), snappedf(phases[k][2], 0.1)])}
			_check(res.get("ok", false), "%s %s preview: form swapped at the flash" % [who, version], res)
			_check(blocked <= int(frames * 0.03), "%s %s: camera line of sight clear (%d/%d frames blocked)" % [who, version, blocked, frames])
			_check(min_d > 0.55, "%s %s: camera never inside her (closest %.2f m)" % [who, version, min_d])
			await _wait(2.0)
			_check(c.avatar_path == base, "%s back in her base form after a preview" % who, c.avatar_path)
		var after := {"xp": m.progress.xp, "level": m.level(), "forms": m.progress.forms_unlocked, "know": m.knowledge.size()}
		_check(JSON.stringify(after) == JSON.stringify(before), "%s: previews changed no progress" % who, [before, after])
		_check(not main.transformer.is_transformed(who), "%s: not left in a transformed state" % who)


# ------------------------------------------------------------------ persistence of a second mind
func _persist(phase: int) -> void:
	_check(WorldState.persistent and WorldState.save_path.begins_with("user://test_regress_"), "persistent run on a test save", WorldState.save_path)
	var l := WorldState.mind("luna")
	var mk := WorldState.mind("mika")
	if phase == 1:
		WorldState.record_activity({"id": "defeat:gloomwisp", "verb": "defeat", "label": "Defeated Gloomwisp"}, {"knowledge": {"defeated:gloomwisp": 1}}, "luna")
		WorldState.record_activity({"id": "collect:wisp_ember"}, {"items": {"wisp_ember": 2}, "knowledge": {"material:wisp_ember": 1}}, "luna")
		WorldState.record_activity({"id": "spell:umbral_lance"}, {"skills": {"umbral_lance": 0.3}, "knowledge": {"reaction:umbral_lance:gloomwisp:struck": 1}}, "luna")
		_check(float(l.progress.xp) > 0.0 and not mk.knowledge.has("defeated:gloomwisp"), "Luna earned XP; Mika learned nothing from it", l.progress)
		_check(WorldState.save_game(), "saved")
		report["luna"] = {"xp": l.progress.xp, "level": l.level(), "know": l.knowledge.size(), "inv": l.inventory}
	else:
		_check(WorldState.load_report.get("result", "") == "loaded", "restart loaded the save", WorldState.load_report)
		_check(int(l.knowledge.get("defeated:gloomwisp", 0)) == 1 and int(l.inventory.get("wisp_ember", 0)) == 2 and float(l.skills.get("umbral_lance", 0.0)) > 0.29,
			"Luna's memories, materials and mastery survived", [l.knowledge.keys(), l.inventory, l.skills])
		_check(float(l.progress.xp) > 0.0 and (l.progress.awarded as Dictionary).has("k:reaction:umbral_lance:gloomwisp:struck"), "her XP and awarded firsts survived (no double pay)", l.progress.xp)
		_check(not mk.knowledge.has("defeated:gloomwisp") and int(mk.inventory.get("wisp_ember", 0)) == 0, "Mika's mind still separate after reload")
		var before := float(l.progress.xp)
		Progression.xp_for_entry(l, {"activity": {"id": "spell:umbral_lance"}, "changes": {"knowledge.reaction:umbral_lance:gloomwisp:struck": [0, 1]}})
		_check(float(l.progress.xp) == before, "a reloaded first is not paid again")


# ------------------------------------------------------------------ the real path to Level 10
func _levelup() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var m := WorldState.mind("mika")
	var b: SanctuaryBrain = main.mage_brains["mika"]
	report["start"] = {"level": m.level(), "xp": m.progress.xp, "gate": Progression.gate_status("mika", 10)}
	_check(m.level() == 9 and not Progression.gate_status("mika", 10).met, "Mika starts at Level 9 at the Orbit Gate (from her real save)", report.start)
	var base := mika.avatar_path
	var map: RID = mika.get_world_3d().navigation_map
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(26, 0, 6)) + Vector3(0, 0.1, 0)
	await _wait(1.0)
	var won := false
	for attempt in 3:
		var mon := _spawn_near(mika, "thornback", 9.0)
		if mon == null:
			continue
		await _wait(0.8)
		var opts := b.options().filter(func(o): return o.kind == "hunt" and o.monster == mon.id)
		if opts.is_empty():
			continue
		var res: Dictionary = await b.run_activity(opts[0].merged(b.score(opts[0])))
		report["fight_%d" % attempt] = res
		if int(m.knowledge.get("defeated:thornback", 0)) > 0:
			won = true
			break
		m.vigor = 1.0        # she rests between attempts (as the planner would make her)
	_check(won, "she won against a Thornback through her own planner", report)
	_check(m.level() == 10 and (m.progress.forms_unlocked as Array).has("bloom"), "gate met -> Level 10, Bloom form unlocked", [m.level(), m.progress.forms_unlocked])
	# the first-time sequence starts by itself once it is safe (between activities)
	var t0 := Time.get_ticks_msec()
	while main.transformer.playing == "" and not main.transformer.is_transformed("mika") and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	_check(main.transformer.playing == "mika" or main.transformer.is_transformed("mika"), "the full transformation started on its own", main.transformer.describe())
	var shot_t := Time.get_ticks_msec()
	while main.transformer.playing == "mika" and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		if Time.get_ticks_msec() - shot_t > 2500:
			shot_t = Time.get_ticks_msec()
			_shot("levelup_%d" % int((shot_t - t0) / 1000))
	var last: Dictionary = main.transformer.log[-1] if not main.transformer.log.is_empty() else {}
	_check(last.get("version", "") == "full" and not last.get("preview", true) and last.get("ok", false), "it was the full first-time version", last)
	_check(main.transformer.is_transformed("mika") and mika.avatar_path.ends_with("Mika_Level10.vrm") and String(m.progress.get("appearance", "")) == "bloom", "Bloom Form is now her permanent appearance", mika.avatar_path)
	_check(m.knowledge.has("form:bloom"), "the form is in her memory")
	await _wait(2.0)
	_shot("bloom_after")
	# a later strong fight: the short sequence is an Orbit Surge (temporary power) - her outfit never changes
	await main.transformer.surge("mika")
	_check(main.transformer.has_surge("mika") and mika.has_meta("form_power") and mika.has_node("AetherOrbit"), "Orbit Surge: extra power + orbit ring")
	main.transformer.surges["mika"].until = 0.0
	await _wait(1.5)
	_check(not main.transformer.has_surge("mika") and not mika.has_meta("form_power") and mika.avatar_path.ends_with("Mika_Level10.vrm"), "the surge expires; she keeps her Bloom Form", mika.avatar_path)
	_check(base != mika.avatar_path, "(base model preserved on disk for future forms)", base)
	_check(m.level() == 10 and (m.progress.forms_unlocked as Array).has("bloom"), "Level 10 and the unlocked form remain")
	report["end"] = {"level": m.level(), "xp": m.progress.xp, "transform_log": main.transformer.log}
