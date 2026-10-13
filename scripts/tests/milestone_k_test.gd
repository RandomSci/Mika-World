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
