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
var _gpu_ms: Array = []
var _cpu_ms: Array = []
var _vp_rid: RID
var _game_t := 0.0


func _ready() -> void:
	mode = String(RenderProfile.options.get("mktest", ""))
	dir = RenderProfile.shots_dir + "/mktest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_run.call_deferred()


func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
	_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu())
	_game_t += delta


func _reset_frames() -> void:
	_frame_ms.clear()
	_gpu_ms.clear()
	_cpu_ms.clear()


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
	_reset_frames()
	match mode:
		"face": await _face()
		"companions": await _companions()
		"duel": await _duel()
		"env": await _env()
		"walk": await _walk()
		"territory": await _territory()
		"rest": await _rest()
		"stargaze": await _stargaze()
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
	var gsum := 0.0
	for g in _gpu_ms:
		gsum += float(g)
	var csum := 0.0
	for c in _cpu_ms:
		csum += float(c)
	return {"frames": s.size(), "avg_fps": snappedf(1000.0 * s.size() / maxf(total, 1.0), 0.1), "p50_ms": snappedf(float(s[s.size() / 2]), 0.1),
		"p95_ms": snappedf(float(s[int(s.size() * 0.95)]), 0.1), "worst_ms": snappedf(float(s[s.size() - 1]), 0.1),
		"hitches_over_50ms": s.filter(func(x): return float(x) > 50.0).size(),
		"gpu_ms": snappedf(gsum / maxf(_gpu_ms.size(), 1), 0.01), "render_cpu_ms": snappedf(csum / maxf(_cpu_ms.size(), 1), 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)}


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
## V3 quiet scene: the REAL joint activity (Mika's planner invites Luna to watch the stars; the companionship
## scene walks them to the glade, lies them down, talks, gets them up) under the game's stargaze camera. Checked:
## both lay for long enough, lines were spoken, the heads looked up, the camera never looked up a skirt, both
## stood again, each remembers it. Stills every 6 s.
func _stargaze() -> void:
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
	WorldState.night = true
	w.set_night(true)
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(-2, w.height(-2, 104), 104))
	mika.global_position = start + Vector3(0, 0.05, 0)
	luna.world = w
	luna.global_position = NavigationServer3D.map_get_closest_point(map, start + Vector3(2.5, 0, 1.0)) + Vector3(0, 0.05, 0)
	luna.visible = true
	luna.set_physics_process(true)
	main.director.enabled = true
	main.director.set_subject(mika)
	main.companionship.force_accept = true
	var lines := []
	main.voice.line_started.connect(func(spk, text): lines.append([spk, text]))
	var brain = main.mage_brains["mika"]
	var area_info: Dictionary = WorldState.areas["whispering_woods"]
	var sp: Array = area_info.stargaze_spot
	var target := {"pos": Vector3(sp[0], w.height(sp[0], sp[1]), sp[1]), "fill": {"place": String(area_info.stargaze_place)}}
	var lying_s := {"mika": 0.0, "luna": 0.0}
	var heads_up := {"mika": 0, "luna": 0}
	var cam_bad := []
	var modes := {}
	var shots := 0
	var box := {"done": false, "result": {}}   # a Dictionary: lambdas capture locals by value
	var runner := func() -> void:
		box.result = await main.companionship.invite(brain, "luna", "stargaze_together", target)
		box.done = true
	runner.call()
	var t0 := _gms()
	var next_shot := 6000
	while not box.done and _gms() - t0 < 240000:
		await _wait(0.5)
		var el := _gms() - t0
		modes[main.director.mode] = int(modes.get(main.director.mode, 0)) + 1
		for c in [mika, luna]:
			if c.ground_pose == "lie":
				lying_s[c.character_id] += 0.5
				var head := _bone_world(c, "Head")
				if head.basis.y.dot(Vector3.UP) < 0.35:    # the head's up axis lies flat: she is on her back
					heads_up[c.character_id] += 1
		# the camera rule while they lie: never from the feet side below shoulder height, never below 0.6 m
		if mika.ground_pose == "lie":
			var cam: Camera3D = get_viewport().get_camera_3d()
			var hd := _bone_world(mika, "Head").origin
			var hp := _bone_world(mika, "Hips").origin
			var axis := Vector3(hd.x - hp.x, 0, hd.z - hp.z).normalized()
			var rel := cam.global_position - hp
			var along := rel.dot(axis)
			if (along < -0.8 and rel.y < 1.2) or rel.y < 0.6:
				cam_bad.append([snappedf(el / 1000.0, 0.5), snappedf(along, 0.1), snappedf(rel.y, 0.1)])
		if el >= next_shot:
			next_shot += 6000
			_shot("%03d_%s" % [int(el / 1000), main.director.mode])
			shots += 1
	await _wait(1.0)
	var done: bool = box.done
	var result: Dictionary = box.result
	report["stargaze"] = {"result": result, "lying_s": lying_s, "heads_up_samples": heads_up, "lines": lines, "camera_modes": modes, "camera_violations": cam_bad, "shots": shots,
		"memory_mika": WorldState.mind("mika").knowledge.keys().filter(func(k): return String(k).begins_with("together:luna")).map(func(k): return WorldState.mind("mika").knowledge[k]),
		"memory_luna": WorldState.mind("luna").knowledge.keys().filter(func(k): return String(k).begins_with("together:mika")).map(func(k): return WorldState.mind("luna").knowledge[k])}
	print("[mktest] stargaze ", JSON.stringify(report.stargaze))
	_check(done and result.get("ok", false), "the stargazing activity ran to the end", result.get("detail", result))
	_check(lying_s.mika >= 25.0 and lying_s.luna >= 25.0, "both lay in the grass for a good while (Mika %.0f s, Luna %.0f s)" % [lying_s.mika, lying_s.luna], lying_s)
	_check(heads_up.mika >= 20 and heads_up.luna >= 20, "both were on their backs looking up (samples %d / %d)" % [heads_up.mika, heads_up.luna], heads_up)
	_check(lines.size() >= 4, "they spoke a few lines (%d)" % lines.size(), lines)
	_check(int(modes.get("stargaze", 0)) >= 30, "the camera used the stargaze framing for most of the scene", modes)
	_check(cam_bad.is_empty(), "the camera never looked up a skirt or sat in the grass", cam_bad.slice(0, 6))
	_check(mika.ground_pose == "" and luna.ground_pose == "", "both stood up again", [mika.ground_pose, luna.ground_pose])
	var mem_ok := (report.stargaze.memory_mika as Array).any(func(m): return String(m.get("memory", "")).contains("stars")) and (report.stargaze.memory_luna as Array).any(func(m): return String(m.get("memory", "")).contains("stars"))
	_check(mem_ok, "each of them remembers the night in her own mind", [report.stargaze.memory_mika, report.stargaze.memory_luna])


## V3 quiet scenes, first slice: sitting on the ground and lying down with real clips, measured on the skeleton
## (hips and feet against the ground, the head's facing when lying) and photographed from the side.
func _bone_world(c: WorldCharacter, bone: String) -> Transform3D:
	return c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone(bone))


func _pose_metrics(c: WorldCharacter) -> Dictionary:
	var g: float = c.global_position.y    # the floor she stands on (paving or grass), not the terrain underneath
	var hips := _bone_world(c, "Hips").origin.y - g
	var lf := _bone_world(c, "LeftFoot").origin.y - g
	var rf := _bone_world(c, "RightFoot").origin.y - g
	if c.pose_adjust and c.pose_adjust.mode == "sit" and c.pose_adjust.debug.has("LeftLowerLeg"):
		# get_bone_global_pose() reports the animation pose; the ground-sit legs are solved by the modifier
		lf = float(c.pose_adjust.debug.LeftLowerLeg.foot_y) - float(c.pose_adjust.floor_y) - c.pose_adjust.sole
		rf = float(c.pose_adjust.debug.RightLowerLeg.foot_y) - float(c.pose_adjust.floor_y) - c.pose_adjust.sole
	var head := _bone_world(c, "Head")
	var face_dir := -head.basis.z    # VRM faces +Z in model space; after the retarget the head's forward is -z of the bone basis
	var up_face := head.basis.y.dot(Vector3.UP)
	return {"hips_m": snappedf(hips, 0.01), "left_foot_m": snappedf(lf, 0.01), "right_foot_m": snappedf(rf, 0.01),
		"head_y_axis_up": snappedf(up_face, 0.02), "head_m": snappedf(head.origin.y - g, 0.01)}


func _rest() -> void:
	await _hold_all()
	main.director.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load (streamed)", r)
	if not r.get("ok", false):
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	var vp: Vector2 = w.VIEWPOINT + Vector2(-3.0, -2.0)
	var spot := NavigationServer3D.map_get_closest_point(map, Vector3(vp.x, w.height(vp.x, vp.y), vp.y))
	mika.global_position = spot + Vector3(0, 0.05, 0)
	mika.look_at_point(spot + Vector3(1, 0, 0))
	await _wait(1.0)
	var side_cam := func(c: WorldCharacter, dist := 3.2, h := 1.2, fov := 40.0):
		var fwd := -c.global_transform.basis.z
		var right := Vector3(-fwd.z, 0, fwd.x)
		main.camera_rig.set_shot(c.global_position + right * dist + fwd * 1.2 + Vector3(0, h, 0), c.global_position + Vector3(0, 0.55, 0), fov)
	var front_cam := func(c: WorldCharacter, dist := 3.4, h := 1.0, fov := 40.0):
		var fwd := -c.global_transform.basis.z
		main.camera_rig.set_shot(c.global_position + fwd * dist + Vector3(0.8, h, 0), c.global_position + Vector3(0, 0.6, 0), fov)
	report["rest"] = {}
	# 1) sitting on the ground
	side_cam.call(mika)
	_shot("sit_00_standing")
	var stand_m := _pose_metrics(mika)
	mika.play_gesture("sit_ground_enter", 0.25, 0.3)
	mika.set_ground_pose("sit", mika.animation_length("sit_ground_enter") * 0.9)
	await _wait(mika.animation_length("sit_ground_enter") * 0.85)
	mika.play_gesture("sit_ground_loop", 0.3, 0.6)
	await _wait(2.0)
	_shot("sit_01_side")
	front_cam.call(mika)
	await _wait(0.8)
	_shot("sit_02_front")
	var sit_m := _pose_metrics(mika)
	report.rest["standing"] = stand_m
	report.rest["sit_ground"] = sit_m
	print("[mktest] pose_adjust mode=%s influence=%.2f active=%s debug=%s" % [mika.pose_adjust.mode, mika.pose_adjust.influence, mika.pose_adjust.active, mika.pose_adjust.debug])
	print("[mktest] avatar y=%.2f ground_pose=%s hips skel-space y=%.2f" % [mika.avatar.position.y, mika.ground_pose, mika.skeleton.get_bone_global_pose(mika.skeleton.find_bone("Hips")).origin.y])
	print("[mktest] standing ", stand_m, " sit_ground ", sit_m)
	_check(sit_m.hips_m > 0.08 and sit_m.hips_m < 0.4, "sitting on the ground: hips low over the grass (%.2f m)" % sit_m.hips_m, sit_m)
	_check(sit_m.left_foot_m > -0.08 and sit_m.right_foot_m > -0.08, "sitting on the ground: the feet are not underground", sit_m)
	mika.end_gesture()
	mika.play_gesture("sit_ground_exit", 0.2, 0.4)
	mika.set_ground_pose("", mika.animation_length("sit_ground_exit") * 0.9)
	await _wait(mika.animation_length("sit_ground_exit") + 0.6)
	var up_m := _pose_metrics(mika)
	_check(absf(up_m.hips_m - stand_m.hips_m) < 0.08, "she stood back up to her normal height", [stand_m.hips_m, up_m.hips_m])
	# 2) lying down: the UAL get-up played backwards, then the held lying pose with breathing
	side_cam.call(mika, 3.6, 1.5)
	await _wait(0.5)
	mika.play_gesture("lie_down", 0.25, 0.4)
	mika.set_gesture_speed(0.6)
	await _wait(0.9)
	_shot("lie_01_motion")
	await _wait(mika.animation_length("lie_down") / 0.6 - 0.9 + 0.1)
	mika.set_gesture_speed(1.0)
	mika.play_gesture("lie_loop", 0.3, 0.6)
	mika.set_ground_pose("lie", 0.6)
	await _wait(2.0)
	_shot("lie_02_side")
	var lie_m := _pose_metrics(mika)
	# from beyond the HEAD, low and wide (never from the feet in a skirt): the face and the sky
	var hd := _bone_world(mika, "Head").origin
	var hp := _bone_world(mika, "Hips").origin
	var axis := Vector3(hd.x - hp.x, 0, hd.z - hp.z).normalized()   # hips -> head along the ground
	# a high three-quarter angle from the head's side: the face, the body, the ground around her
	var sidev := axis.cross(Vector3.UP)
	main.camera_rig.set_shot(hd + axis * 0.9 + sidev * 2.0 + Vector3(0, 2.1, 0), hp + axis * 0.35 + Vector3(0, 0.2, 0), 42.0)
	await _wait(0.8)
	_shot("lie_03_high_quarter")
	main.camera_rig.set_shot(hp + Vector3(0.0, 3.2, 0.0) - axis * 0.3, hp + Vector3(0, 0.2, 0), 50.0)
	await _wait(0.8)
	_shot("lie_04_above")
	report.rest["lie"] = lie_m
	print("[mktest] lie ", lie_m)
	_check(lie_m.hips_m < 0.3, "lying: hips on the ground (%.2f m)" % lie_m.hips_m, lie_m)
	_check(lie_m.head_m < 0.45, "lying: the head is down on the grass (%.2f m)" % lie_m.head_m, lie_m)
	mika.end_gesture()
	mika.set_ground_pose("", 0.8)
	mika.play_gesture("lie_get_up", 0.2, 0.5)
	await _wait(0.6)
	_shot("lie_05_getting_up")
	await _wait(mika.animation_length("lie_get_up") + 0.6)
	var up2 := _pose_metrics(mika)
	_check(absf(up2.hips_m - stand_m.hips_m) < 0.08, "she got up to her normal height", [stand_m.hips_m, up2.hips_m])
	# 3) the Mixamo "lying down" clip, for comparison only
	side_cam.call(mika, 3.6, 1.5)
	mika.play_gesture("lie_down_mx", 0.25, 0.4)
	await _wait(mika.animation_length("lie_down_mx") - 0.3)
	_shot("lie_06_mixamo_end")
	report.rest["lie_mixamo_end"] = _pose_metrics(mika)
	print("[mktest] mixamo lying_down end ", report.rest.lie_mixamo_end)
	mika.end_gesture()
	await _wait(1.2)
	# 4) night, both of them lying side by side on the ruin court, the camera low from the feet
	WorldState.night = true
	w.set_night(true)
	var court: Vector2 = Vector2(-8.0, 116.0)   # the entry glade: open sky, soft grass
	var cs := NavigationServer3D.map_get_closest_point(map, Vector3(court.x, w.height(court.x, court.y), court.y))
	mika.global_position = cs + Vector3(0, 0.05, 0)
	luna.world = w
	luna.global_position = cs + Vector3(1.4, 0.05, 0)
	luna.visible = true
	luna.set_physics_process(true)
	for c in [mika, luna]:
		c.look_at_point(c.global_position + Vector3(0, 0, -3))
	await _wait(0.8)
	for c in [mika, luna]:
		c.play_gesture("lie_down", 0.25, 0.4)
		c.set_gesture_speed(0.6)
	await _wait(mika.animation_length("lie_down") / 0.6 + 0.2)
	for c in [mika, luna]:
		c.set_gesture_speed(1.0)
		c.play_gesture("lie_loop", 0.3, 0.6)
		c.set_ground_pose("lie", 0.6)
	await _wait(1.0)
	mika.look_head_at(mika.global_position + Vector3(0, 12, -4))
	luna.look_head_at(luna.global_position + Vector3(0, 12, -4))
	await _wait(1.5)
	var f2 := -mika.global_transform.basis.z
	var mid := (mika.global_position + luna.global_position) * 0.5
	# from beyond their heads, low and wide: both faces and the sky above them (never from the feet in a skirt)
	var hd2 := _bone_world(mika, "Head").origin
	var hp2 := _bone_world(mika, "Hips").origin
	var ax2 := Vector3(hd2.x - hp2.x, 0, hd2.z - hp2.z).normalized()
	var sd2 := ax2.cross(Vector3.UP)
	main.camera_rig.set_shot(mid + ax2 * 1.2 + sd2 * 2.6 + Vector3(0, 2.0, 0), mid + ax2 * 0.3 + Vector3(0, 0.25, 0), 46.0)
	await _wait(1.0)
	_shot("stargaze_01_night_high_quarter")
	main.camera_rig.set_shot(mid + Vector3(0, 3.4, 0) + ax2 * 0.4 + ax2.cross(Vector3.UP) * 1.2, mid + Vector3(0, 0.25, 0), 50.0)
	await _wait(1.0)
	_shot("stargaze_02_night_high")
	mika.look_head_at(luna.global_position + Vector3(0, 0.3, 0))
	await _wait(1.2)
	_shot("stargaze_03_turn_to_luna")
	for c in [mika, luna]:
		c.look_head_at(null)
		c.end_gesture()
		c.set_ground_pose("", 0.8)
		c.play_gesture("lie_get_up", 0.2, 0.5)
	await _wait(mika.animation_length("lie_get_up") + 0.8)
	_shot("stargaze_04_up")


## Milestone K8: creatures live in their habitats. Observed for real over game time: where they appear (inside
## their habitat, outside safe zones, never near a mage, never where the camera could watch them pop in), what
## they do (patrol, guard, rest, investigate a noise, withdraw to the lair when hurt), that the main route stays
## peaceful, that night changes the population, and that a defeat is remembered by the habitat (and saved).
func _territory() -> void:
	await _hold_all()
	main.director.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load (streamed)", r)
	if not r.get("ok", false):
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	# both mages at the crossroads (a safe zone), the camera behind Mika looking north up the stairs
	var cross: Vector2 = w.CROSS
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(cross.x, w.height(cross.x, cross.y), cross.y)) + Vector3(0, 0.05, 0)
	luna.world = w
	luna.global_position = NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(1.6, 0, 0)) + Vector3(0, 0.05, 0)
	luna.visible = true
	luna.set_physics_process(true)
	main.camera_rig.set_shot(Vector3(cross.x, w.height(cross.x, cross.y + 8) + 1.8, cross.y + 8), Vector3(cross.x, w.height(cross.x, cross.y - 10) + 1.5, cross.y - 10), 55.0)
	main.spawner.enabled = true
	var terr: Array = main.spawner.territories
	_check(terr.size() == 3, "three habitats live in the woods", terr.map(func(t): return t.id))
	var route := [Vector2(0, 126), Vector2(-5, 100), Vector2(-7, 68), cross, Vector2(0, 7), Vector2(0, -8), Vector2(0, -27), w.INSCRIPTION, w.VIEWPOINT]
	var cam: Camera3D = get_viewport().get_camera_3d()
	var routines := {}
	var states := {}
	var peace_violations := []
	var outside := []
	var seen_spawns := {}
	var visible_spawns := []
	var pop_day := 0
	var t0 := _gms()
	var phase := "day"
	var noise_sent := false
	var noise_t := 0
	var investigated := false
	var withdraw_target: Monster = null
	var withdrew := false
	var rested_after := false
	var defeat_done := false
	var pop_night := 0
	var shot_marks := [25000, 60000, 95000, 140000, 200000, 250000]
	var shots_taken := 0
	while _gms() - t0 < 300000:
		await _wait(1.0)
		var el := _gms() - t0
		# visual proof: frame the nearest living creature from a few metres away, then return to the crossroads shot
		if not shot_marks.is_empty() and el >= int(shot_marks[0]):
			shot_marks.pop_front()
			var best: Monster = null
			var bd := 1e9
			for t in terr:
				for m in t.alive:
					if is_instance_valid(m) and m.alive() and mika.global_position.distance_to(m.global_position) < bd:
						bd = mika.global_position.distance_to(m.global_position)
						best = m
			if best:
				var fwd := -best.global_transform.basis.z
				var side := Vector3(-fwd.z, 0, fwd.x)
				var cp := best.global_position + fwd * 4.5 + side * 2.5 + Vector3(0, 1.9, 0)
				cp.y = maxf(cp.y, w.height(cp.x, cp.z) + 1.4)
				main.camera_rig.set_shot(cp, best.aim_point(), 42.0)
				await _wait(1.2)
				_shot("creature_%03d_%s_%s_%s" % [int(el / 1000), best.kind, best.routine, "night" if WorldState.night else "day"])
				shots_taken += 1
				main.camera_rig.set_shot(Vector3(cross.x, w.height(cross.x, cross.y + 8) + 1.8, cross.y + 8), Vector3(cross.x, w.height(cross.x, cross.y - 10) + 1.5, cross.y - 10), 55.0)
		for t in terr:
			for m in t.alive:
				if not is_instance_valid(m):
					continue
				routines[m.kind + ":" + m.routine] = int(routines.get(m.kind + ":" + m.routine, 0)) + 1
				states[m.mstate] = int(states.get(m.mstate, 0)) + 1
				if not t.contains(m.global_position) and m.routine != "investigate" and m.mstate in ["wander"]:
					outside.append([m.kind, snappedf(m.global_position.x, 0.1), snappedf(m.global_position.z, 0.1)])
				for rp in route:
					if Vector2(m.global_position.x - rp.x, m.global_position.z - rp.y).length() < 22.0:
						peace_violations.append([m.kind, rp, snappedf(el / 1000.0, 1.0)])
				if m.routine == "investigate":
					investigated = true
			for e in t.log:
				if e.event == "spawned" and not seen_spawns.has(str(e)):
					seen_spawns[str(e)] = true
					var sp := Vector3(e.at[0], w.height(e.at[0], e.at[1]) + 0.8, e.at[1])
					var q := PhysicsRayQueryParameters3D.create(cam.global_position, sp)
					q.collision_mask = 1 | 4
					var hit: Dictionary = mika.get_world_3d().direct_space_state.intersect_ray(q)
					var clear := hit.is_empty() or (hit.position as Vector3).distance_to(sp) < 1.0
					if cam.is_position_in_frustum(sp) and clear and cam.global_position.distance_to(sp) < 60.0:
						visible_spawns.append(e)
		# day phase: after 70 s a noise near the dead wood (a spell's loudness) must draw a creature to look
		if phase == "day" and el > 70000 and not noise_sent:
			noise_sent = true
			noise_t = el
			var np := Vector3(96, w.height(96, -16), -16)
			main.spawner.hear(np, 20.0, "spell")
		# after 130 s wound a den creature badly: it should break off to its lair and rest
		if phase == "day" and el > 130000 and withdraw_target == null:
			for t in terr:
				if t.id == "den":
					for m in t.alive:
						if m.kind == "thornback" and m.alive():
							withdraw_target = m
							m.last_attacker = mika
							m.apply_damage(m.max_hp * 0.78, "arcane")
							break
		if withdraw_target and is_instance_valid(withdraw_target) and withdraw_target.alive():
			if withdraw_target.routine == "withdraw":
				withdrew = true
			if withdrew and withdraw_target.routine == "rest":
				rested_after = true
		if phase == "day" and el > 170000:
			pop_day = terr.reduce(func(acc, t): return acc + t.alive.size(), 0)
			phase = "night"
			WorldState.night = true
			w.set_night(true)
			main.camera_rig.set_shot(Vector3(cross.x, w.height(cross.x, cross.y + 8) + 1.8, cross.y + 8), Vector3(cross.x, w.height(cross.x, cross.y - 10) + 1.5, cross.y - 10), 55.0)
		if phase == "night" and el > 285000 and not defeat_done:
			defeat_done = true
			pop_night = terr.reduce(func(acc, t): return acc + t.alive.size(), 0)
			for t in terr:
				if t.id == "den" and not t.alive.is_empty():
					var m2: Monster = t.alive[0]
					m2.last_attacker = mika
					m2.apply_damage(99999.0, "arcane")
	await _wait(1.5)
	var den_state: Dictionary = {}
	for t in terr:
		if t.id == "den":
			den_state = t.state()
	report["territory"] = {"routines": routines, "states": states, "spawns": seen_spawns.size(), "visible_spawns": visible_spawns,
		"outside_habitat": outside.slice(0, 8), "peace_violations": peace_violations.slice(0, 8), "pop_day": pop_day, "pop_night": pop_night,
		"den_state": den_state, "territories": terr.map(func(t): return t.describe()), "logs": terr.map(func(t): return t.log.slice(0, 12))}
	print("[mktest] territory ", JSON.stringify(report.territory))
	_check(seen_spawns.size() >= 3, "creatures appeared in their habitats over five minutes (%d spawns)" % seen_spawns.size(), seen_spawns.size())
	_check(visible_spawns.is_empty(), "no creature appeared where the camera could watch it pop in", visible_spawns)
	_check(outside.is_empty(), "creatures stayed inside their habitats while at home", outside.slice(0, 5))
	_check(peace_violations.is_empty(), "the main route (entry -> ruins -> viewpoint) stayed peaceful", peace_violations.slice(0, 5))
	var seen_kinds := routines.keys().map(func(k): return String(k).split(":")[1])
	_check("patrol" in seen_kinds and ("guard" in seen_kinds or "rest" in seen_kinds), "territory routines happened (patrol + guard/rest)", routines)
	_check(investigated, "a creature came to investigate the noise", routines)
	_check(withdrew, "a badly hurt den creature withdrew to its lair", withdraw_target.routine_history if withdraw_target and is_instance_valid(withdraw_target) else "no target")
	_check(rested_after or withdrew, "it rested in the lair afterwards", rested_after)
	_check(pop_night >= pop_day, "night brought at least as many creatures out as day (%d -> %d)" % [pop_day, pop_night], [pop_day, pop_night])
	_check(int(den_state.get("defeats", 0)) >= 1 and float(den_state.get("depleted_until", 0.0)) > WorldState.game_time(), "the den remembers the defeat and is depleted for a while", den_state)
	var saved := WorldState.save_game()
	var raw := FileAccess.get_file_as_string(WorldState.save_path)
	var sd = JSON.parse_string(raw) if raw != "" else null
	_check(saved and sd is Dictionary and (sd as Dictionary).has("habitats") and (sd.habitats as Dictionary).get("whispering_woods", {}).has("den"), "the habitat state is in the (test) save", str(sd.get("habitats", "")).left(200) if sd is Dictionary else "no save")


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
	"17_mushroom_grove": {"cam": [-17, 1.7, 47], "look": [-30, 1.2, 40]},
	"18_crystal_vale_from_viewpoint": {"cam": [38.5, 1.9, -36], "cam_h_from": [40, -34], "look": [120, 6.0, -60]},
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
	if RenderProfile.options.has("ev_hardshadow"):
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	if RenderProfile.options.has("ev_scale"):
		get_viewport().scaling_3d_scale = float(RenderProfile.options.ev_scale)
	if RenderProfile.options.has("ev_nossao"):
		w.env.ssao_enabled = false
	if RenderProfile.options.has("ev_noglow"):
		w.env.glow_enabled = false
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
		var pth := NavQuery.path(mp, a3, b3, true)
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
		var path := NavQuery.path(map, start, to, true)
		var reach := path.size() > 0 and path[path.size() - 1].distance_to(to) < 1.5 and to.distance_to(Vector3(m2.x, to.y, m2.y)) < 4.0
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i].distance_to(path[i - 1])
		conn[k] = {"reachable": reach, "path_m": snappedf(length, 0.1), "snap_err": snappedf(to.distance_to(Vector3(m2.x, to.y, m2.y)), 0.1)}
	report["connectivity"] = conn
	if RenderProfile.options.has("navprobe"):
		# the frontier trail: the first point that cannot be reached from the entry
		var start0 := NavigationServer3D.map_get_closest_point(map, Vector3(0, w.height(0, 126), 126))
		var ft: Array = w.trails[8][0]
		for i in ft.size() - 1:
			var f0: Vector2 = ft[i]
			var f1: Vector2 = ft[i + 1]
			var k2 := 0.0
			while k2 <= f0.distance_to(f1):
				var q2 := f0.lerp(f1, k2 / maxf(f0.distance_to(f1), 0.01))
				k2 += 3.0
				var tq := NavigationServer3D.map_get_closest_point(map, Vector3(q2.x, w.height(q2.x, q2.y), q2.y))
				var pth2 := NavQuery.path(map, start0, tq, true)
				var okq := pth2.size() > 0 and pth2[pth2.size() - 1].distance_to(tq) < 1.5
				if not okq:
					print("[mktest] frontier trail unreachable from ", q2.snapped(Vector2.ONE * 0.1), " (nav ", tq.snapped(Vector3.ONE * 0.1), ")")
					# the terrain along the broken stretch: slope (deg) and the navmesh polygons under it
					var pq := f0.lerp(f1, maxf(k2 - 6.0, 0.0) / maxf(f0.distance_to(f1), 0.01))
					var worst_deg := 0.0
					for si in 13:
						var sp := pq.lerp(q2, si / 12.0)
						var hx: float = w.height(sp.x + 0.5, sp.y) - w.height(sp.x - 0.5, sp.y)
						var hz: float = w.height(sp.x, sp.y + 0.5) - w.height(sp.x, sp.y - 0.5)
						worst_deg = maxf(worst_deg, rad_to_deg(atan(Vector2(hx, hz).length())))
					print("[mktest]   terrain slope along the stretch: worst %.1f deg; trail_at mid %.2f" % [worst_deg, w.trail_at(pq.lerp(q2, 0.5).x, pq.lerp(q2, 0.5).y)])
					var nverts := nmesh.get_vertices()
					var npoly := 0
					for pi in nmesh.get_polygon_count():
						var poly := nmesh.get_polygon(pi)
						var cen := Vector3.ZERO
						for vi in poly:
							cen += nverts[vi]
						cen /= poly.size()
						if w._seg_dist(Vector2(cen.x, cen.z), pq, q2) < 2.5:
							npoly += 1
							var vs2 := []
							for vi in poly:
								vs2.append(nverts[vi].snapped(Vector3.ONE * 0.01))
							print("[mktest]   navpoly ", vs2)
					print("[mktest]   navmesh polygons within 2.5 m of the stretch: ", npoly)
					# what solid geometry sits along the broken stretch (the last reachable point was 3 m back)?
					var prevq := f0.lerp(f1, maxf(k2 - 6.0, 0.0) / maxf(f0.distance_to(f1), 0.01))
					for sh in w.find_children("*", "CollisionShape3D", true, false):
						var cs3 := sh as CollisionShape3D
						var gp := cs3.global_position
						if w._seg_dist(Vector2(gp.x, gp.z), prevq, q2) < 15.0:
							var shp := cs3.shape
							var desc := shp.get_class()
							if shp is SphereShape3D: desc += " r=%.2f" % (shp as SphereShape3D).radius
							elif shp is CylinderShape3D: desc += " r=%.2f h=%.2f" % [(shp as CylinderShape3D).radius, (shp as CylinderShape3D).height]
							elif shp is BoxShape3D: desc += " size=%s" % (shp as BoxShape3D).size
							print("[mktest]   near: ", cs3.get_parent().name, "/", cs3.name, " at ", gp.snapped(Vector3.ONE * 0.1), " ", desc,
								" trail_d=%.1f ground=%.1f" % [w.dress.trail_dist(gp.x, gp.z), w.height(gp.x, gp.z)])
					break
		# every trail polyline, 4 m steps: report where the navmesh is not under the path
		for t in w.trails:
			var pts: Array = t[0]
			for i in pts.size() - 1:
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				var L := p0.distance_to(p1)
				var k := 0.0
				while k <= L:
					var q := p0.lerp(p1, k / maxf(L, 0.01))
					k += 4.0
					var gq := Vector3(q.x, w.height(q.x, q.y), q.y)
					var cq := NavigationServer3D.map_get_closest_point(map, gq)
					if cq.distance_to(gq) > 1.0:
						print("[mktest] trail gap at ", q.snapped(Vector2.ONE * 0.1), " nav ", cq.snapped(Vector3.ONE * 0.1), " d=", snappedf(cq.distance_to(gq), 0.1))
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
		_reset_frames()
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
		main.camera_rig.set_shot(Vector3(-5.5, w.height(-5.5, 103) + 1.7, 103), Vector3(3, w.height(3, 86) + 2.4, 86), 55.0)
		await _wait(2.0)
		_shot("09_after_sunset")
		main.camera_rig.set_shot(Vector3(-17, w.height(-17, 47) + 1.7, 47), Vector3(-30, w.height(-30, 40) + 1.2, 40), 55.0)
		await _wait(1.5)
		_shot("09c_grove_night")
		main.camera_rig.set_shot(Vector3(-56, w.height(-56, 56) + 2.6, 56), Vector3(-76, w.height(-76, 42) + 0.5, 42), 55.0)
		await _wait(1.5)
		_shot("09b_pond_night")
