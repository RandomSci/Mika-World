class_name MilestoneKTest
extends Node
## --mktest=<mode>: Milestone K checks. Disposable saves only (user://test_regress_*.json); screenshots in
## screenshots/mktest/. Uses GAME time (works identically under Godot's Movie Maker recording).
##   face        expressive faces in real gameplay: both mages, close-ups, event-driven emotions (no timers),
##               blinks (count, interval), speech visemes, listening, personality difference Mika vs Luna

var main: Node
var mode := ""
var checks: Array = []
var failed := false
var report := {}
var dir := ""
var _frame_ms: Array = []
var _game_t := 0.0


func _ready() -> void:
	mode = String(RenderProfile.options.get("mktest", ""))
	dir = RenderProfile.shots_dir + "/mktest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	_game_t += delta


func _gms() -> int:
	return int(_game_t * 1000.0)


func _check(ok: bool, what: String, detail = "") -> void:
	checks.append({"ok": ok, "check": what, "detail": str(detail).left(400)})
	print("[mktest]   %s %s %s" % ["ok  " if ok else "FAIL", what, ("(" + str(detail).left(220) + ")") if str(detail) != "" else ""])
	if not ok:
		failed = true


func _wait(s: float) -> void:
	var t0 := _game_t
	while _game_t - t0 < s:
		await get_tree().process_frame


func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless" or RenderProfile.options.has("noshots"):
		return
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s_%s.png" % [dir, mode, tag])


func _run() -> void:
	main.player.enabled = false
	main.player.set_process_unhandled_input(false)
	main.set_process_unhandled_input(false)
	if main.hud:
		main.hud.visible = false
	if main.get("overlay_ui"):
		main.overlay_ui.visible = false
	print("[mktest] mode=%s save=%s persistent=%s mages=%s" % [mode, WorldState.save_path, WorldState.persistent, main.mages])
	if not WorldState.save_path.begins_with("user://test_regress_"):
		_check(false, "refusing to run: tests need a disposable user://test_regress_*.json save", WorldState.save_path)
		_finish()
		return
	await _wait(2.5)
	_frame_ms.clear()
	match mode:
		"face": await _face()
		"companions": await _companions()
		"duel": await _duel()
		"env": await _env()
		"walk": await _walk()
		_: _check(false, "unknown mode " + mode)
	_finish()


func _fps_stats() -> Dictionary:
	if _frame_ms.is_empty():
		return {}
	var s: Array = _frame_ms.duplicate()
	s.sort()
	var total := 0.0
	for x in s:
		total += float(x)
	return {"frames": s.size(), "avg_fps": snappedf(1000.0 * s.size() / maxf(total, 1.0), 0.1), "p50_ms": snappedf(float(s[s.size() / 2]), 0.1),
		"p95_ms": snappedf(float(s[int(s.size() * 0.95)]), 0.1), "worst_ms": snappedf(float(s[s.size() - 1]), 0.1),
		"hitches_over_50ms": s.filter(func(x): return float(x) > 50.0).size()}


func _finish() -> void:
	report["fps"] = _fps_stats()
	var f := FileAccess.open("%s/%s.json" % [dir, mode], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"mode": mode, "passed": not failed, "checks": checks, "report": report}, "  "))
		f.close()
	print("[mktest] fps ", JSON.stringify(report.fps))
	print("[mktest] %s %s" % ["FAIL" if failed else "PASS", mode])
	get_tree().quit(1 if failed else 0)


func _hold_all() -> void:
	for w in main.mage_brains:
		var b: SanctuaryBrain = main.mage_brains[w]
		b.hold = true
		var t0 := _gms()
		while not b.current.is_empty() and _gms() - t0 < 40000:
			await get_tree().process_frame


## Stand the two mages facing each other near the garden, 1.6 m apart (a conversation spacing).
func _stage_pair() -> Array:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = mika.get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, Vector3(4.5, 0, 3.0))
	var b := NavigationServer3D.map_get_closest_point(map, a + Vector3(1.6, 0, 0.0))
	mika.global_position = a + Vector3(0, 0.05, 0)
	luna.global_position = b + Vector3(0, 0.05, 0)
	mika.visible = true
	luna.visible = true
	mika.set_physics_process(true)
	luna.set_physics_process(true)
	mika.look_at_point(luna.global_position)
	luna.look_at_point(mika.global_position)
	await _wait(1.2)
	return [mika, luna]


## A close-up on one face (from in front of her, slightly to the side).
func _closeup(c: WorldCharacter, side := 1.0, dist := 0.85) -> void:
	var head := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Head"))
	var face := head.origin + Vector3(0, 0.07, 0)
	var fwd := -c.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	main.director.enabled = false
	main.camera_rig.set_shot(face + fwd * dist + right * side * 0.28 + Vector3(0, 0.02, 0), face, 32.0)


## Sum of |blend shape| over the face's brow/eye/mouth components (to prove the face really moves).
func _face_energy(c: WorldCharacter) -> Dictionary:
	var out := {}
	for k in c.face.idx:
		var v := c.face.face.get_blend_shape_value(int(c.face.idx[k]))
		var rg := FaceController._region(k)
		out[rg] = float(out.get(rg, 0.0)) + v
	return out


# ------------------------------------------------------------------ face
func _face() -> void:
	await _hold_all()
	var pair := await _stage_pair()
	var mika: WorldCharacter = pair[0]
	var luna: WorldCharacter = pair[1]
	_check(mika.face != null and luna.face != null, "both mages have a component face controller", [mika.face != null, luna.face != null])
	if mika.face == null or luna.face == null:
		return
	_check(mika.face.idx.size() >= 30 and luna.face.idx.size() >= 30, "brow/eye/mouth/viseme morphs found on both models", [mika.face.idx.size(), luna.face.idx.size()])
	# blinks: count over 12 s of quiet (no events)
	_closeup(mika)
	var blinks := 0
	var was := false
	var t0 := _game_t
	while _game_t - t0 < 12.0:
		await get_tree().process_frame
		var bv := mika.face.face.get_blend_shape_value(int(mika.face.idx["blink"]))
		if bv > 0.6 and not was:
			blinks += 1
		was = bv > 0.6
	report["blinks_12s"] = blinks
	_check(blinks >= 2 and blinks <= 7, "natural blink rate (2-7 in 12 s)", blinks)
	_check(mika.face.dominant() == "neutral" or mika.face.dominant() == "", "at rest her face is not stuck smiling", mika.face.dominant())
	# event-driven emotions (the Affect model's real handlers)
	var shots := [["mika", "clue", "curious"], ["mika", "struck", "surprised"], ["mika", "victory", "excited"], ["mika", "spell_miss", "frustrated"],
		["luna", "clue", "thoughtful"], ["luna", "victory", "playful"], ["luna", "struck", "frustrated"]]
	var energies := {}
	for s in shots:
		var c: WorldCharacter = main.characters[s[0]]
		_closeup(c, -1.0 if s[0] == "luna" else 1.0)
		await _wait(0.6)
		var e0 := _face_energy(c)
		var used: String = main.affect.react(String(s[0]), String(s[1]))
		await _wait(0.55)
		var e1 := _face_energy(c)
		_shot("%s_%s" % [s[0], s[1]])
		energies["%s_%s" % [s[0], s[1]]] = {"emotion": used, "before": e0, "after": e1}
		_check(used == String(s[2]) and c.face.dominant() == String(s[2]), "%s reacts to '%s' with %s" % [s[0], s[1], s[2]], [used, c.face.dominant()])
		if c.face.brow_overlay:
			report["cams_%s" % s[0]] = [str(get_viewport().get_camera_3d().global_position), str(main.camera_rig.camera.global_position), main.camera_rig.camera == get_viewport().get_camera_3d(), str(c.face.face.get_viewport() == get_viewport())]
			report["brow_overlay_%s" % s[0]] = [snappedf(c.face._brow_mat.albedo_color.a, 0.01), str(c.face.debug_brow), str(c.global_transform.basis.z)]
		await _wait(2.8)
	report["energies"] = energies
	# personality: the same event reads stronger on Mika than on Luna
	var mk: Dictionary = energies["mika_victory"].after
	var ln: Dictionary = energies["luna_victory"].after
	var m_sum := float(mk.get("brow", 0.0)) + float(mk.get("eye", 0.0)) + float(mk.get("mouth", 0.0))
	var l_sum := float(ln.get("brow", 0.0)) + float(ln.get("eye", 0.0)) + float(ln.get("mouth", 0.0))
	_check(m_sum > l_sum, "Mika is more openly expressive than Luna for the same event", [snappedf(m_sum, 0.01), snappedf(l_sum, 0.01)])
	# it fades back
	await _wait(2.0)
	_check(mika.face.dominant() in ["neutral", "listening"], "emotion fades back to her baseline", mika.face.dominant())
	# conversation: speaker's face follows her words, the other listens and looks at her
	main.director.enabled = false
	var mid := (mika.global_position + luna.global_position) * 0.5
	var axis := (luna.global_position - mika.global_position).normalized()
	var perp := Vector3(-axis.z, 0, axis.x)
	main.camera_rig.set_shot(mid + perp * 2.2 + Vector3(0, 1.45, 0), mid + Vector3(0, 1.35, 0), 34.0)
	var lines := [["mika", "Luna, what do you think that light in the ruins was?"], ["luna", "Hmm. I think it was a ward, not a lamp. Careful with it."]]
	var listened := false
	var looked := false
	var vis_max := 0.0
	for ln2 in lines:
		var sp: WorldCharacter = main.characters[ln2[0]]
		var other: WorldCharacter = luna if sp == mika else mika
		var box := {"done": false}
		var runner := func():
			await main.voice.say(String(ln2[0]), String(ln2[1]), {})
			box.done = true
		runner.call()
		var k := 0
		while not box.done:
			await get_tree().process_frame
			k += 1
			for vk in ["v_a", "v_o", "v_e", "v_i", "v_u"]:
				vis_max = maxf(vis_max, sp.face.face.get_blend_shape_value(int(sp.face.idx[vk])))
			if other.face.hold.has("listening"):
				listened = true
			if other.head_look and other.head_look.influence > 0.3:
				looked = true
			if k == 20:
				_shot("conv_%s_speaks" % ln2[0])
		await _wait(0.6)
	report["viseme_max"] = vis_max
	_check(vis_max > 0.2 or not main.voice.available, "her mouth forms visemes while speaking", snappedf(vis_max, 0.01))
	_check(listened, "the other mage listens (listening face) while she speaks")
	_check(looked, "the listener turns to look at the speaker")
	report["face_log_mika"] = mika.face.log.slice(maxi(0, mika.face.log.size() - 20))
	report["face_log_luna"] = luna.face.log.slice(maxi(0, luna.face.log.size() - 20))


# ------------------------------------------------------------------ companions
func _speakers_lines(entry: Dictionary) -> Array:
	return (entry.get("lines", []) as Array).map(func(l): return "%s: %s" % [l.who, l.text])


func _companions() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	await _hold_all()
	main.director.enabled = true
	var mm := WorldState.mind("mika")
	var lm := WorldState.mind("luna")
	report["mika_clues"] = mm.knowledge.keys().filter(func(k): return String(k).begins_with("clue:"))
	# 1) Luna lives through something of her own first: a real fight (her memory, not a fixture)
	var map: RID = luna.get_world_3d().navigation_map
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(26, 0, 6)) + Vector3(0, 0.1, 0)
	lm.vigor = 1.0
	await main.focus_mage("luna", true)
	var mon: Monster = main.spawner.spawn("gloomwisp", NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(8, 0, 1)))
	if mon:
		mon.hp = mon.max_hp * 0.4
	await _wait(1.5)
	var opts := lb.options().filter(func(o): return o.kind == "hunt")
	if not opts.is_empty():
		var fr: Dictionary = await lb.run_activity(opts[0].merged(lb.score(opts[0])))
		report["luna_fight"] = fr.get("detail", "")
	_check(int(lm.knowledge.get("defeated:gloomwisp", 0)) > 0, "Luna has a real memory of her own (she fought a gloomwisp)", report.get("luna_fight", ""))
	main.focus_locked = false
	await main.focus_mage("mika", true)
	main.focus_locked = false
	# bring them near each other (each walks there herself)
	var meet_spot := NavigationServer3D.map_get_closest_point(map, Vector3(6, 0, 4))
	luna.navigate_to(meet_spot + Vector3(2.5, 0, 0.5), false)
	mika.navigate_to(meet_spot, false)
	var t0 := _gms()
	while (luna.current_action == "navigate_to" or mika.current_action == "navigate_to") and _gms() - t0 < 30000:
		await get_tree().process_frame
	# 2) a meeting started by Mika: both bring topics from their own memory; real turn-taking
	mm.knowledge["met:luna"] = 1                       # they already know each other (Milestone H introductions)
	lm.knowledge["met:mika"] = 1
	lm.knowledge["heard:mika:" + String((report.mika_clues as Array)[0]) ] = 1 if not (report.mika_clues as Array).is_empty() else 0
	mm.knowledge["heard:luna:monster:gloomwisp"] = 1   # "Luna had been out fighting" (what she could see / was told in passing)
	var shots := {"n": 0}
	var on_line := func(sp: String, _tx: String):
		shots.n += 1
		if shots.n <= 6:
			await _wait(0.6)
			_shot("talk_%02d_%s" % [shots.n, sp])
	main.voice.line_started.connect(on_line)
	var res: Dictionary = await main.mage_talk.meet(mb, "luna")
	main.voice.line_started.disconnect(on_line)
	report["meeting"] = res
	var lines: Array = res.get("lines", [])
	var speakers := {}
	for l in lines:
		speakers[l.who] = int(speakers.get(l.who, 0)) + 1
	_check(lines.size() >= 4 and speakers.size() == 2, "a real two-sided conversation (%d lines)" % lines.size(), speakers)
	var alternations := 0
	for i in range(1, lines.size()):
		if lines[i].who != lines[i - 1].who:
			alternations += 1
	_check(alternations >= lines.size() - 2, "turn-taking: they alternate, nobody monologues", alternations)
	var told := lines.filter(func(l): return String(l.get("told", "")) != "")
	_check(not told.is_empty(), "something from one mage's own memory was shared", told.map(func(l): return l.told))
	var luna_told := lm.knowledge.keys().filter(func(k): return String(k).begins_with("told:mika:"))
	var luna_knows_fact := luna_told.any(func(k): return lm.knowledge.has(String(k).trim_prefix("told:mika:")))
	_check(not luna_told.is_empty() and not luna_knows_fact, "Luna remembers being TOLD, the fact did not enter her own knowledge", luna_told)
	var mika_told := mm.knowledge.keys().filter(func(k): return String(k).begins_with("told:luna:"))
	report["mika_told"] = mika_told
	report["luna_told"] = luna_told
	# 3) an invitation: Mika proposes exploring together; Luna decides from her own state
	mm.knowledge.erase("together_last:luna")
	var cands: Array = mb.explore_map.candidates(3)
	_check(not cands.is_empty(), "Mika sees somewhere unexplored to propose")
	if cands.is_empty():
		return
	var tgt := {"pos": cands[0].pos, "fill": {"place": String(cands[0].describe)}}
	var walk_gaps := []
	var min_gap := {"v": 99.0}
	var tracker := func():
		while main.companionship.busy():
			await get_tree().physics_frame
			var g := Vector2(mika.global_position.x - luna.global_position.x, mika.global_position.z - luna.global_position.z).length()
			if String(main.companionship.active.get("stage", "")) == "walking together":
				walk_gaps.append(g)
				min_gap.v = minf(min_gap.v, g)
				if walk_gaps.size() == 60:
					_shot("walk_together_a")
				if walk_gaps.size() == 240:
					_shot("walk_together_b")
	var box := {"done": false, "res": {}}
	var runner := func():
		box.res = await main.companionship.invite(mb, "luna", "explore_together", tgt)
		box.done = true
	runner.call()
	await get_tree().process_frame
	tracker.call()
	while not box.done:
		await get_tree().process_frame
	var ent: Dictionary = box.res.get("entry", {})
	report["invite"] = ent
	report["walk_gap"] = {"samples": walk_gaps.size(), "min": snappedf(min_gap.v, 0.01), "max": snappedf(walk_gaps.max() if not walk_gaps.is_empty() else 0.0, 0.01),
		"avg": snappedf((walk_gaps.reduce(func(a, b): return a + b, 0.0) / maxf(1, walk_gaps.size())), 0.01)}
	_check(ent.has("accepted"), "Luna answered the invitation from her own state", ent)
	if ent.get("accepted", false):
		_check(walk_gaps.size() > 30 and min_gap.v > 0.55, "they walked together without colliding (closest %.2f m)" % min_gap.v, report.walk_gap)
		_check(float(report.walk_gap.avg) < 4.0, "the follower kept up beside her (avg gap %.2f m)" % float(report.walk_gap.avg))
		var mt: Array = mm.knowledge.keys().filter(func(k): return String(k).begins_with("together:luna:"))
		var lt: Array = lm.knowledge.keys().filter(func(k): return String(k).begins_with("together:mika:"))
		_check(not mt.is_empty() and not lt.is_empty(), "each keeps her own memory of doing it together", [mt, lt])
	report["rel_mika"] = MageTalk.rel("mika", "luna")
	report["rel_luna"] = MageTalk.rel("luna", "mika")
	_check(float(report.rel_mika.camaraderie) > 0.0, "their bond grew from real shared time", report.rel_mika)
	# 4) persistence of the relationship memories
	_check(WorldState.save_game(), "saved (disposable)")


# ------------------------------------------------------------------ duel
func _duel() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	var map: RID = mika.get_world_3d().navigation_map
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(18, 0, 2)) + Vector3(0, 0.1, 0)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(19.5, 0, 3.5)) + Vector3(0, 0.1, 0)
	for w in ["mika", "luna"]:
		WorldState.mind(w).vigor = 1.0
		main.mage_brains[w].needs.energy = 0.9
	# consent: a tired mage declines
	WorldState.mind("luna").vigor = 0.3
	var tired: Dictionary = main.companionship.consider("luna", "mika", "train_together")
	_check(not tired.accept and tired.reason == "tired", "a tired Luna declines to spar", tired)
	WorldState.mind("luna").vigor = 1.0
	var tr := {"frames": 0, "both_in": 0, "modes": {}}
	var vp := get_viewport()
	var tracker := func():
		var n := 0
		while not main.duel.busy():
			await get_tree().process_frame
		while main.duel.busy():
			await get_tree().process_frame
			tr.frames += 1
			n += 1
			tr.modes[main.director.mode] = int(tr.modes.get(main.director.mode, 0)) + 1
			var cam := vp.get_camera_3d()
			if cam and not cam.is_position_behind(mika.global_position + Vector3(0, 1, 0)) and not cam.is_position_behind(luna.global_position + Vector3(0, 1, 0)):
				var r := vp.get_visible_rect()
				var pa := cam.unproject_position(mika.global_position + Vector3(0, 1, 0))
				var pb := cam.unproject_position(luna.global_position + Vector3(0, 1, 0))
				if r.has_point(pa) and r.has_point(pb):
					tr.both_in += 1
			if n % 90 == 45 and n < 1300:
				_shot("duel_%02d" % (n / 90))
	tracker.call()
	var res: Dictionary = await main.companionship.invite(mb, "luna", "train_together", {"pos": SanctuaryTerrain.TRAINING_CENTER_3D, "fill": {}})
	await _wait(1.0)
	var d: Dictionary = main.duel.log.back() if not main.duel.log.is_empty() else {}
	report["invite"] = res.get("entry", {})
	report["duel"] = d
	report["camera_modes"] = tr.modes
	report["both_in_frame"] = [tr.both_in, tr.frames]
	var frames: int = tr.frames
	var both_in: int = tr.both_in
	_check(res.get("entry", {}).get("accepted", false), "Luna (rested) accepts the invitation to spar", res.get("entry", {}))
	_check(not d.is_empty(), "a duel took place", d.get("detail", ""))
	if d.is_empty():
		return
	var casts := int(d.casts.mika) + int(d.casts.luna)
	var dodges := int(d.dodges.mika) + int(d.dodges.luna)
	_check(casts >= 4, "both cast spar bolts (%d)" % casts, d.casts)
	_check(dodges >= 1, "real dodges happened (%d)" % dodges, d.dodges)
	_check(int(d.dodged.mika) + int(d.dodged.luna) >= 1, "at least one dodge really avoided a bolt", d.dodged)
	_check(String(d.stop) != "", "it stopped safely (%s)" % d.stop)
	_check(float(d.seconds) <= TrainingDuel.MAX_S + 2.0, "bounded length (%.0f s)" % float(d.seconds))
	_check(WorldState.mind("mika").vigor > 0.5 and WorldState.mind("luna").vigor > 0.5, "nonlethal: both still well", [WorldState.mind("mika").vigor, WorldState.mind("luna").vigor])
	_check(WorldState.mind("mika").knowledge.has("sparred:luna") and WorldState.mind("luna").knowledge.has("sparred:mika"), "each remembers the bout")
	_check(both_in >= frames * 0.8, "the camera kept both duelists in frame (%d/%d)" % [both_in, frames])
	_check(main.focus == "mika", "Mika stayed the camera's subject")


# ------------------------------------------------------------------ environment (Whispering Woods)
## The continuous route, walked for real (navmesh + the game's own Mika-first camera): Mika leads, Luna walks
## with her (FollowCompanion). Pauses where a viewer would want to look. Records time, distance and stalls.
func _walk() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load (streamed)", r)
	if not r.get("ok", false):
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	luna.world = w
	luna.global_position = NavigationServer3D.map_get_closest_point(map, mika.global_position + mika.global_transform.basis.x * 1.6) + Vector3(0, 0.05, 0)
	luna.visible = true
	luna.set_physics_process(true)
	var f := FollowCompanion.new()
	f.leader = mika
	f.follower = luna
	f.side = 1.0
	add_child(f)
	main.director.enabled = true
	await _wait(2.0)
	var route := [[Vector2(-5, 110), ""], [Vector2(2, 90), ""], [Vector2(-7, 68), ""], [w.CROSS + Vector2(0, 2), "crossroads"],
		[Vector2(1, 22), ""], [w.STAIR_BASE + Vector2(0, 5), "stair"], [Vector2(0, -8), ""], [Vector2(0, -27), ""], [w.RUIN_GATE + Vector2(0, -3), ""],
		[w.INSCRIPTION + Vector2(1.5, 4.0), "inscription"], [Vector2(16, -42.5), ""], [w.VIEWPOINT + Vector2(-1.5, 0), "viewpoint"]]
	var legs := []
	var t_start := _gms()
	var dist := 0.0
	var last := mika.global_position
	var reached_all := true
	for leg in route:
		var p: Vector2 = leg[0]
		var t0 := _gms()
		var ok: bool = await main.companionship.walk_together(mika, f, Vector3(p.x, w.height(p.x, p.y), p.y), 90.0)
		dist += last.distance_to(mika.global_position)
		last = mika.global_position
		legs.append({"to": [p.x, p.y], "ok": ok, "s": snappedf((_gms() - t0) / 1000.0, 0.1), "gap_end": snappedf(f.gap(), 0.1)})
		print("[mktest] leg ", legs[-1])
		if not ok:
			reached_all = false
		match String(leg[1]):
			"crossroads":
				mika.look_head_at(Vector3(w.CROSS.x + 4.2, w.height(w.CROSS.x, w.CROSS.y) + 1.4, w.CROSS.y + 3.0))
				await _wait(2.5)
				mika.look_head_at(null)
			"stair":
				mika.look_head_at(Vector3(0, w.height(0, -14) + 4.0, -14))
				await _wait(3.0)
				mika.look_head_at(null)
			"inscription":
				mika.look_head_at(Vector3(w.INSCRIPTION.x, w.height(w.INSCRIPTION.x, w.INSCRIPTION.y) + 1.5, w.INSCRIPTION.y))
				await _wait(4.0)
				mika.look_head_at(null)
			"viewpoint":
				mika.look_at_point(Vector3(w.FALLS.x, mika.global_position.y, w.FALLS.y + 4.0))
				mika.look_head_at(Vector3(w.FALLS.x, w.upper_water_y(), w.FALLS.y + 2.0))
				await _wait(6.0)
	var end_gap := f.gap()
	f.queue_free()
	report["walk"] = {"legs": legs, "total_s": snappedf((_gms() - t_start) / 1000.0, 0.1), "distance_m": snappedf(dist, 0.1)}
	_check(reached_all, "walked the whole route entry -> forest -> crossroads -> stairway -> ruins -> viewpoint", legs.filter(func(l): return not l.ok))
	_check(end_gap < 6.0, "Luna was still beside Mika at the end (gap %.1f m)" % end_gap)


## Main-route proof views. Heights are RELATIVE to the ground under the camera / the look point.
const ENV_VIEWS := {
	"01_outward_from_sanctuary": {"area": "sanctuary", "cam": [0, 3.2, -24], "look": [0, 2.5, -60]},
	"02_entering_forest": {"cam": [1.5, 1.7, 131], "look": [-2, 2.6, 104]},
	"03_walking_forest": {"cam": [-5.5, 1.7, 103], "look": [3, 2.4, 86]},
	"03b_canopy_trail": {"cam": [2.5, 1.6, 84], "look": [-8, 3.2, 64]},
	"04_crossroads": {"cam": [-1, 1.8, 52], "look": [3, 1.6, 36]},
	"12_stairway": {"cam": [0.6, 1.7, 13], "look": [0, 5.5, -16]},
	"12b_stair_landing": {"cam": [1.2, 1.7, -6], "look": [-1, 4.0, -26]},
	"07_ancient_ruins": {"cam": [1.5, 1.7, -26.5], "look": [0, 2.6, -40]},
	"13_inscription": {"cam": [3.5, 1.6, -42], "look": [-2, 1.4, -50]},
	"10_scenic_viewpoint": {"cam": [41.8, 2.7, -33.8], "cam_h_from": [40, -34], "look": [60, 2.0, -20]},
	"05_lotus_pond": {"cam": [-57, 1.7, 52], "look": [-76, -0.5, 42]},
	"04b_river_bridge": {"cam": [49, 1.7, -2], "look": [58, 2.0, -26]},
	"11_waterfall": {"cam_abs": [59.0, 6.1, -21.0], "look": [55.5, 2.5, -40]},
	"14_den_mouth": {"cam": [108.0, 1.8, -23.0], "look": [116, 1.6, -31]},
	"15_den_close": {"cam": [111.3, 1.7, -26.2], "look": [117.2, 1.2, -31.5]},
	"16_den_top": {"cam": [104.0, 14.0, -20.0], "look": [118.7, 0.0, -32.8]},
	"06_monster_habitat": {"cam": [98, 2.6, -15], "look": [118, 3.0, -33]},
	"08_elevated_trail": {"cam": [-30, 2.0, -64], "look": [-70, 3.0, -100]},
}


func _env() -> void:
	await _hold_all()
	main.director.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var only := String(RenderProfile.options.get("view", ""))
	# 1) the woods themselves
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load (streamed)", r)
	if not r.get("ok", false):
		return
	await _wait(1.5)
	report["build"] = main.streaming.last_report
	var w = main.world
	var nmesh: NavigationMesh = w.nav_region.navigation_mesh
	var vs := nmesh.get_vertices()
	var vb := AABB(vs[0], Vector3.ZERO) if vs.size() > 0 else AABB()
	for v in vs:
		vb = vb.expand(v)
	report["navmesh"] = {"polygons": nmesh.get_polygon_count(), "vertices": vs.size(), "aabb": str(vb)}
	print("[mktest] navmesh ", report.navmesh)
	await get_tree().physics_frame
	var mp: RID = mika.get_world_3d().navigation_map
	for pair in [[Vector2(2, 38), Vector2(-20, 46)], [Vector2(2, 38), Vector2(2, 60)], [Vector2(0, 100), Vector2(0, 90)], [Vector2(0, 126), Vector2(0, 120)], [Vector2(36, 18), Vector2(48, 9)]]:
		var a3 := NavigationServer3D.map_get_closest_point(mp, Vector3(pair[0].x, w.height(pair[0].x, pair[0].y), pair[0].y))
		var b3 := NavigationServer3D.map_get_closest_point(mp, Vector3(pair[1].x, w.height(pair[1].x, pair[1].y), pair[1].y))
		var pth := NavigationServer3D.map_get_path(mp, a3, b3, true)
		print("[mktest] navpair ", pair, " a=", a3, " b=", b3, " n=", pth.size(), " end=", pth[pth.size() - 1] if pth.size() > 0 else Vector3.INF)
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	# 2) connectivity: real navmesh paths between every landmark and the entry
	var marks := {"entry": Vector2(0, 126), "crossroads": w.CROSS, "pond": w.POND + Vector2(18, 5), "bridge_west": Vector2(w.BRIDGE_W - 5.0, w.BRIDGE.y), "bridge_east": Vector2(w.BRIDGE_E + 5.0, w.BRIDGE.y),
		"under_bridge": Vector2(52.6, w.BRIDGE.y), "bridge_deck": w.BRIDGE, "den": w.DEN_MOUTH + w.DEN_FACE * 2.0, "den_inside": w.DEN_MOUTH - w.DEN_FACE * 4.0, "stair_base": w.STAIR_BASE + Vector2(0, 4), "alcove": w.ALCOVE, "ruins": w.INSCRIPTION + Vector2(0, 5),
		"viewpoint": w.VIEWPOINT, "frontier": w.FRONTIER_END + Vector2(6, 6), "falls_pool": w.FALLS + Vector2(-6, 14)}
	var conn := {}
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(0, w.height(0, 126), 126))
	for k in marks:
		var m2: Vector2 = marks[k]
		var qy: float = w.height(m2.x, m2.y)
		if k == "bridge_deck":
			qy = w.marks._deck_y(m2.x, maxf(w.height(w.BRIDGE_W - 6.0, m2.y), w.height(w.BRIDGE_E + 6.0, m2.y))) + 0.2   # on the deck, not the riverbed
		var to := NavigationServer3D.map_get_closest_point(map, Vector3(m2.x, qy, m2.y))
		var path := NavigationServer3D.map_get_path(map, start, to, true)
		var reach := path.size() > 0 and path[path.size() - 1].distance_to(to) < 1.5 and to.distance_to(Vector3(m2.x, to.y, m2.y)) < 4.0
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i].distance_to(path[i - 1])
		conn[k] = {"reachable": reach, "path_m": snappedf(length, 0.1), "snap_err": snappedf(to.distance_to(Vector3(m2.x, to.y, m2.y)), 0.1)}
	report["connectivity"] = conn
	if RenderProfile.options.has("navprobe"):
		for i in 13:
			var q2: Vector2 = Vector2(104, -19).lerp(w.DEN_MOUTH - w.DEN_FACE * 4.0, i / 12.0)
			var gq := Vector3(q2.x, w.height(q2.x, q2.y), q2.y)
			var cp2 := NavigationServer3D.map_get_closest_point(map, gq)
			print("[mktest] probe ", q2, " ground=", snappedf(gq.y, 0.01), " nav=", cp2.snapped(Vector3.ONE * 0.01), " d=", snappedf(cp2.distance_to(gq), 0.01))
	var bad := conn.keys().filter(func(k): return not conn[k].reachable)
	_check(bad.is_empty(), "every landmark is reachable on foot from the entry (%d/%d)" % [conn.size() - bad.size(), conn.size()], bad)
	# 3) the views
	var views := {}
	for k in ENV_VIEWS:
		if only != "" and not k.begins_with(only):
			continue
		var v: Dictionary = ENV_VIEWS[k]
		if v.has("area"):
			continue
		var c: Array = v.get("cam", v.get("cam_abs", []))
		var l: Array = v.look
		var cp := Vector3(c[0], w.height(c[0], c[2]) + c[1], c[2]) if v.has("cam") else Vector3(c[0], c[1], c[2])
		if v.has("cam_h_from"):   # height relative to another ground point (e.g. a terrace level)
			var hf: Array = v.cam_h_from
			cp.y = w.height(hf[0], hf[1]) + c[1]
		var lp := Vector3(l[0], w.height(l[0], l[2]) + l[1], l[2])
		main.camera_rig.set_shot(cp, lp, 55.0)
		_frame_ms.clear()
		await _wait(2.0)
		var st := _fps_stats()
		views[k] = st
		_shot(k)
	report["views"] = views
	for nm in ["day"]:
		pass
	# night view of the forest
	if only == "" or only == "09":
		WorldState.night = true
		w.set_night(true)
		await _wait(1.0)
		main.camera_rig.set_shot(Vector3(-2, w.height(-2, 96) + 2.0, 96), Vector3(-8, w.height(-8, 70) + 2.2, 70), 55.0)
		await _wait(2.0)
		_shot("09_after_sunset")
		main.camera_rig.set_shot(Vector3(-56, w.height(-56, 56) + 2.6, 56), Vector3(-76, w.height(-76, 42) + 0.5, 42), 55.0)
		await _wait(1.5)
		_shot("09b_pond_night")
