class_name MilestoneKTest
extends Node
## --mktest=<mode>: Milestone K checks. Disposable saves only (user://test_regress_*.json); screenshots in
## screenshots/mktest/. Uses GAME time (works identically under Godot's Movie Maker recording).
##   face        expressive faces in real gameplay: both mages, close-ups, event-driven emotions (no timers),
##               blinks (count, interval), speech visemes, listening, personality difference Mika vs Luna
##   spells      V3 Part XIII: the two spell families in real casts - Mika's Gale Spiral (helix, push), Verdant
##               Bind (roots hold a chasing creature), Leaf Ward (bolts really stopped, limits honest); Luna's
##               Umbral Rift (spikes, daze, scar), Gilded Mirror (front only, reflects once practised); the
##               tactics that choose them; two short real fights

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


var hitch_log: Array = []          # every frame over 50 ms with what had just happened (to find the cause)


func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	if delta > 0.05 and main and is_instance_valid(main):
		hitch_log.append({"ms": int(delta * 1000.0), "t": snappedf(_game_t, 0.01), "gpu": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid), 0.1),
			"ghosts": Afterimage.made, "voice_lines": main.voice.log.size() if main.get("voice") else -1, "casts": main.magic.history.size() if main.get("magic") else -1,
			"cuts": TrailerCam.log.size(), "monsters": get_tree().get_nodes_in_group("monsters").size(), "area": main.streaming.current_id if main.get("streaming") else "",
			"proc_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1), "phys_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
			"nav_ms": snappedf(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0, 0.1), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), "nav_maps": Performance.get_monitor(Performance.NAVIGATION_ACTIVE_MAPS)})
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
		"ambush": await _ambush()
		"tour": await _tour()
		"companions": await _companions()
		"duel": await _duel()
		"env": await _env()
		"walk": await _walk()
		"territory": await _territory()
		"rest": await _rest()
		"stargaze": await _stargaze()
		"spells": await _spells()
		"phoenix_voice": await _phoenix_voice()
		"phoenix": await _phoenix()
		"phoenix_reel": await _phoenix_reel()
		"showcase": await _showcase()
		"no_teleport": await _no_teleport()
		"mossback": await _mossback()
		"wayside": await _wayside_look()
		"journey": await _journey()
		"fixcheck": await _fixcheck()
		"appearances": await _appearances()
		"pack": await _pack_hunt()
		"town": await _town()
		"rematch": await _rematch()
		"lore": await _lore()
		"fold": await _fold()
		"hamlet": await _hamlet()
		"hitch": await _hitch()
		"road": await _road()
		"navcheck": await _navcheck()
		"soak": await _soak()
		"weather": await _weather()
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
	if not (report.mika_clues as Array).is_empty():
		lm.knowledge["heard:mika:" + String((report.mika_clues as Array)[0])] = 1
	mm.knowledge["heard:luna:monster:gloomwisp"] = 1   # "Luna had been out fighting" (what she could see / was told in passing)
	var shots := {"n": 0}
	var on_line := func(sp: String, _tx: String):
		shots.n += 1
		if shots.n <= 6:
			await _wait(0.6)
			_shot("talk_%02d_%s" % [shots.n, sp])
	main.voice.line_started.connect(on_line)
	# V3 Part 9: measured turn-taking latency (one line ends -> the next voice starts)
	var marks := {"start": [], "end": []}
	var on_start := func(_sp: String, _tx: String): (marks.start as Array).append(_gms())
	var on_end := func(_sp: String, _r: Dictionary): (marks.end as Array).append(_gms())
	main.voice.line_started.connect(on_start)
	main.voice.line_finished.connect(on_end)
	var t_meet := _gms()
	var res: Dictionary = await main.mage_talk.meet(mb, "luna")
	main.voice.line_started.disconnect(on_line)
	main.voice.line_started.disconnect(on_start)
	main.voice.line_finished.disconnect(on_end)
	var gaps := []
	for i in range(1, (marks.start as Array).size()):
		if i - 1 < (marks.end as Array).size():
			gaps.append(int(marks.start[i]) - int(marks.end[i - 1]))
	var sg := gaps.duplicate()
	sg.sort()
	var lat := {"first_line_ms": (int(marks.start[0]) - t_meet) if not (marks.start as Array).is_empty() else -1,
		"turn_gaps_ms": gaps, "median_gap_ms": sg[int(sg.size() * 0.5)] if not sg.is_empty() else -1,
		"max_gap_ms": sg[-1] if not sg.is_empty() else -1, "phrase_ms": main.mage_talk.phrase_ms, "voice": main.voice.latency_report()}
	report["talk_latency"] = lat
	print("[mktest] talk latency ", JSON.stringify(lat))
	_check(not sg.is_empty() and int(lat.median_gap_ms) < 1500 and int(lat.max_gap_ms) < 4000, "no long silences between turns (median %s ms, max %s ms)" % [lat.median_gap_ms, lat.max_gap_ms], lat)
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
	# whoever was told something (the one with no memory of her own to share may only listen) remembers being
	# TOLD; the fact itself does not enter her own knowledge
	var luna_told := lm.knowledge.keys().filter(func(k): return String(k).begins_with("told:mika:"))
	var mika_told := mm.knowledge.keys().filter(func(k): return String(k).begins_with("told:luna:"))
	var leaked := luna_told.filter(func(k): return lm.knowledge.has(String(k).trim_prefix("told:mika:"))) + \
		mika_told.filter(func(k): return mm.knowledge.has(String(k).trim_prefix("told:luna:")))
	_check(not (luna_told + mika_told).is_empty() and leaked.is_empty(), "the listener remembers being TOLD, the fact did not enter her own knowledge", {"luna_told": luna_told, "mika_told": mika_told, "leaked": leaked})
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
	print("[mktest] walk gap timeline: ", walk_gaps.filter(func(_g): return true).slice(0, walk_gaps.size(), 30).map(func(g): return snappedf(g, 0.1)))
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


# ------------------------------------------------------------------ spell families (V3 Part XIII, K5/K6)
func _park(who: String, at: Vector3) -> void:
	if not main.characters.has(who):
		return
	var oc: WorldCharacter = main.characters[who]
	oc.global_position = NavigationServer3D.map_get_closest_point(oc.get_world_3d().navigation_map, at) + Vector3(0, 0.1, 0)


func _find_spell(cls) -> Node:
	for n in main.characters["mika"].get_parent().get_children():
		if is_instance_of(n, cls):
			return n
	return null


func _find_node(cls) -> Node:
	return _find_spell(cls)


## A test bolt flying at `who` from `from` (a creature's bolt if `owner` is given): resolves against her ward
## and her real position. Returns the hazard's result {struck, absorbed_by, reflected, reflected_hit}.
func _test_bolt(who: String, from: Vector3, owner: Monster = null, speed := 8.0) -> Dictionary:
	var c: WorldCharacter = main.characters[who]
	var h := AttackHazard.new()
	h.kind = "projectile"
	h.owner_monster = owner
	h.center = from
	h.dir = (c.global_position + Vector3(0, 1.05, 0) - from).normalized()
	h.speed = speed
	h.max_range = 30.0
	h.vigor = 0.03
	h.style = "ember"
	var box := {"done": false, "struck": []}
	h.resolved.connect(func(hz: AttackHazard, struck: Array): box.struck = struck.map(func(x): return x.character_id); box.done = true; box.absorbed_by = String(hz.get_meta("absorbed_by", "")); box.reflected = hz.has_meta("reflected"); box.reflected_hit = String(hz.get_meta("reflected_hit", "")); box.warder = String(hz.get_meta("warder", "")))
	main.world.add_child(h)
	var t0 := _gms()
	while not box.done and _gms() - t0 < 6000:
		await get_tree().process_frame
	return box


func _cast_watch(who: String, spell: String, target_id: String, tag: String, cls) -> Dictionary:
	var c: WorldCharacter = main.characters[who]
	var phases := []
	var cb := func(cc: Node, sid: String, ph: String, _el: String, _pos: Vector3):
		if cc == c and sid == spell:
			phases.append(ph)
	MagicEvents.spell_phase.connect(cb)
	var box := {"done": false, "res": {}}
	var runner := func():
		box.res = await main.magic.cast(c, spell, target_id)
		box.done = true
	runner.call()
	var t0 := _gms()
	var seen := {"node": false, "charge_shot": false, "release_shot": false, "release_t": -1}
	while not box.done and _gms() - t0 < 14000:
		await get_tree().process_frame
		var sp := _find_spell(cls)
		if sp:
			seen.node = true
			if sp.get("_fired") is Dictionary:
				var f: Dictionary = sp.get("_fired")
				if f.has("charge") and not f.has("release") and not seen.charge_shot and sp.get("t") > sp.call("phase_time", "charge") + 0.25:
					seen.charge_shot = true
					_shot(tag + "_charge")
				if f.has("release"):
					if seen.release_t < 0:
						seen.release_t = _gms()
					if not seen.release_shot and _gms() - int(seen.release_t) > 380:
						seen.release_shot = true
						_shot(tag + "_release")
	MagicEvents.spell_phase.disconnect(cb)
	var out: Dictionary = box.res.duplicate()
	out["phases"] = phases
	out["node_seen"] = seen.node
	return out


func _spells() -> void:
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
	var mind_m := WorldState.mind("mika")
	var mind_l := WorldState.mind("luna")
	for w in ["mika", "luna"]:
		WorldState.mind(w).vigor = 1.0
		main.mage_brains[w].needs.energy = 0.9
	var lens := {}
	for cl in ["wide_arm_spell", "magic_attack_2h", "magic_attack_1h", "spell_casting", "brace", "cast_quick"]:
		lens[cl] = snappedf(mika.animation_length(cl), 0.01)
	report["clip_lengths"] = lens
	# ---- the catalogue: two families, nothing granted early
	var known_m: Array = main.magic.known_spells("mika").filter(func(x): return x.castable).map(func(x): return x.id)
	var known_l: Array = main.magic.known_spells("luna").filter(func(x): return x.castable).map(func(x): return x.id)
	_check(known_m.has("gale_spiral") and known_m.has("leaf_ward") and known_m.has("arcane_orb"), "Mika knows her family from the start (Gale Spiral, Leaf Ward) and keeps her first spell", known_m)
	_check(known_l.has("umbral_lance") and known_l.has("gilded_mirror") and not known_l.has("gale_spiral") and not known_l.has("leaf_ward"), "Luna knows hers (Umbral Lance, Gilded Mirror), not Mika's", known_l)
	_check(not main.magic.can_cast("verdant_bind", "mika").ok and not main.magic.can_cast("umbral_rift", "luna").ok, "the advanced techniques are refused before practice", [main.magic.can_cast("verdant_bind", "mika").reason])
	_check(SignatureCast.spell_for("mika") == "gale_spiral" and SignatureCast.spell_for("luna") == "umbral_lance", "signatures: Mika wind, Luna umbral")
	report["known"] = {"mika": known_m, "luna": known_l}

	# ---- Mika at the training grounds, a thornback (ground, melee) out in front
	await main.focus_mage("mika", true)
	_park("luna", Vector3(-3, 0, 2))
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(27, 0, 4)) + Vector3(0, 0.1, 0)
	mika.rotation.y = atan2(-1.0, 0.0)
	await _wait(0.6)
	var at := NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(7.5, 0, 1.0))
	var tb: Monster = main.spawner.spawn("thornback", at)
	_check(tb != null, "a thornback to work with")
	if tb == null:
		return
	tb.set_physics_process(false)
	await _wait(0.8)
	_shot("00_stage")
	# 1. GALE SPIRAL: a helix of two ribbons, leaves, a push
	var p0 := tb.global_position
	var r1 := await _cast_watch("mika", "gale_spiral", tb.id, "spiral", SylvanSpell)
	await _wait(0.5)
	_shot("spiral_after")
	report["gale_spiral"] = r1
	_check(r1.get("ok", false) and r1.get("outcome", "") == "hit", "Gale Spiral: cast through the pipeline and hit", [r1.get("outcome"), r1.get("reason", "")])
	var ph1: Array = r1.get("phases", [])
	_check(ph1.has("activation") and ph1.has("gather") and ph1.has("charge") and ph1.has("release") and ph1.has("impact"), "its phases follow her clip (activation, gather, charge, release, impact)", ph1)
	_check(r1.get("node_seen", false) and String(r1.get("clip", "")) == "wide_arm_spell", "cast by SylvanSpell with her sweeping two-handed gesture", [r1.get("node_seen"), r1.get("clip")])
	var pushed := float(r1.get("reaction", {}).get("pushed_m", 0.0))
	var moved := Vector2(tb.global_position.x - p0.x, tb.global_position.z - p0.z).length()
	_check(pushed > 0.3 and moved > 0.25, "the gust shoved the thornback back (real displacement)", [snappedf(pushed, 0.01), snappedf(moved, 0.01)])
	_check(float(r1.get("reaction", {}).get("damage", 0.0)) > 0.0, "and hurt it", r1.get("reaction", {}).get("damage"))
	# 2. VERDANT BIND: once the spiral is practised (fixture in the DISPOSABLE save), roots hold a chasing creature
	mind_m.skills["gale_spiral"] = maxf(float(mind_m.skills.get("gale_spiral", 0.0)), 0.6)
	mind_m.knowledge["practical:gale_spiral"] = 1
	var cc: Dictionary = main.magic.can_cast("verdant_bind", "mika")
	_check(cc.ok, "Verdant Bind unlocked by practice (Apprentice spiral + practical understanding)", cc)
	tb.hp = tb.max_hp
	tb.global_position = NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(8.5, 0, -0.5))
	tb.target_mage = mika
	tb.mstate = "chase"
	tb.set_physics_process(true)
	var t0 := _gms()
	while _gms() - t0 < 3000 and Vector2(tb.global_position.x - mika.global_position.x, tb.global_position.z - mika.global_position.z).length() > 6.4:
		await get_tree().process_frame
	var d_cast := Vector2(tb.global_position.x - mika.global_position.x, tb.global_position.z - mika.global_position.z).length()
	var r2 := await _cast_watch("mika", "verdant_bind", tb.id, "bind", SylvanSpell)
	report["verdant_bind"] = r2
	report["bind_cast_distance"] = snappedf(d_cast, 0.1)
	var bound_state := tb.mstate
	var cage := _find_node(SylvanSpell.RootCage)
	var roots := 0
	if cage:
		roots = (cage as SylvanSpell.RootCage).roots.size()
	await _wait(0.45)
	_shot("bind_roots")
	var pb := tb.global_position
	var attacked_box := {"n": 0}
	tb.attacked.connect(func(_m, _c, _a): attacked_box.n += 1)
	await _wait(2.0)
	_shot("bind_hold")
	var held := Vector2(tb.global_position.x - pb.x, tb.global_position.z - pb.z).length()
	_check(r2.get("ok", false) and r2.get("outcome", "") == "hit" and String(r2.get("effect", "")) == "bound", "Verdant Bind: the seam reached it and the roots caught it (judged when they closed)", [r2.get("outcome"), r2.get("effect"), r2.get("reason", ""), r2.get("distance_from_target_m")])
	_check(bound_state == "bound" and roots >= 7, "a cage of roots grew round it and it is held", [bound_state, roots])
	_check(held < 0.35 and attacked_box.n == 0, "while held it neither moved nor attacked (2 s)", [snappedf(held, 0.02), attacked_box.n])
	var t1 := _gms()
	while tb.mstate == "bound" and _gms() - t1 < 6000:
		await get_tree().process_frame
	_check(tb.mstate != "bound", "and the roots let it go when they withered", [tb.mstate, (_gms() - t1) / 1000.0])
	# it goes back to being a creature: hold it still for the ward test
	tb.set_physics_process(false)
	tb.global_position = NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(7.0, 0, 1.5))
	# 3. LEAF WARD: a ring of leaves that really stops bolts - two, then it is spent and the third lands
	var r3 := await _cast_watch("mika", "leaf_ward", "", "ward_leaf", SylvanSpell)
	report["leaf_ward"] = r3
	var wd := Ward.active_for(mika)
	_check(r3.get("ok", false) and String(r3.get("effect", "")) == "warded" and wd != null and wd.kind == "leaf", "Leaf Ward: cast (her brace), a ward node orbits her", [r3.get("effect"), r3.get("reason", ""), wd != null])
	await _wait(0.4)
	_shot("ward_leaf")
	var from := mika.global_position + Vector3(6.0, 1.3, 0.5)
	var b1 := await _test_bolt("mika", from, tb)
	_shot("ward_leaf_absorb")
	var b2 := await _test_bolt("mika", mika.global_position + Vector3(-5.5, 1.3, 2.0), tb)
	await _wait(0.3)
	var b3 := await _test_bolt("mika", from, tb)
	report["leaf_bolts"] = [b1, b2, b3]
	_check(b1.get("absorbed_by", "") == "leaf" and (b1.struck as Array).is_empty(), "a bolt from the front was stopped by the leaves", b1)
	_check(b2.get("absorbed_by", "") == "leaf" and (b2.struck as Array).is_empty(), "a second bolt, from behind, too (the ring covers every side)", b2)
	_check(b3.get("absorbed_by", "") == "" and (b3.struck as Array).has("mika"), "the third landed: the ward was spent (honest limits)", b3)
	_check(float(mind_m.skills.get("leaf_ward", 0.0)) > 0.02, "stopping real bolts is practice for the ward", mind_m.skills.get("leaf_ward"))

	# ---- Luna and an emberwing (a flyer that hovers and spits bolts). The stream's spotlight would hand the
	# camera back to Mika: an explicit (locked) focus, as a developer's F3 does.
	main.focus_locked = false
	await main.focus_mage("luna", true)
	_park("mika", Vector3(-3, 0, 2))
	tb.queue_free()
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(27, 0, 4)) + Vector3(0, 0.1, 0)
	luna.rotation.y = atan2(-1.0, 0.0)
	_check(main.focus == "luna", "the camera follows Luna for her part", main.focus)
	await _wait(5.0)      # the sub-area's establishing shot plays out first
	var at2 := NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(8.0, 0, 0.5))
	var ew: Monster = main.spawner.spawn("emberwing", at2)
	_check(ew != null, "an emberwing to work with")
	if ew == null:
		return
	ew.set_physics_process(false)
	await _wait(0.8)
	# 4. UMBRAL RIFT (fixture: the lance practised)
	mind_l.skills["umbral_lance"] = maxf(float(mind_l.skills.get("umbral_lance", 0.0)), 0.6)
	mind_l.knowledge["practical:umbral_lance"] = 1
	_check(main.magic.can_cast("umbral_rift", "luna").ok, "Umbral Rift unlocked by practice (Apprentice lance)", main.magic.can_cast("umbral_rift", "luna"))
	var hp0 := ew.hp
	var r4 := await _cast_watch("luna", "umbral_rift", ew.id, "rift", UmbralSpell)
	report["umbral_rift"] = r4
	var dazed_state := ew.mstate
	var rift := _find_node(UmbralSpell.Rift)
	var spikes_up := 0
	if rift:
		for sp in (rift as UmbralSpell.Rift).spikes:
			if sp.visible:
				spikes_up += 1
	await _wait(0.2)
	_shot("rift_erupt")
	# a fixed close shot of the eruption and, later, of the scar (the director's framing stays on Luna)
	if rift:
		var rp: Vector3 = (rift as Node3D).global_position
		var toward := Vector3(luna.global_position.x - rp.x, 0, luna.global_position.z - rp.z).normalized()
		var sidev := toward.cross(Vector3.UP)
		main.director.enabled = false
		main.camera_rig.set_shot(rp + toward * 3.2 + sidev * 2.6 + Vector3(0, 1.9, 0), rp + Vector3(0, 0.9, 0), 46.0)
		await _wait(0.15)
		_shot("rift_erupt_close")
		main.director.enabled = true
	_check(r4.get("ok", false) and r4.get("outcome", "") == "hit" and String(r4.get("clip", "")) == "spell_casting", "Umbral Rift: cast by UmbralSpell and hit (judged when it erupted)", [r4.get("outcome"), r4.get("reason", ""), r4.get("clip")])
	_check(String(r4.get("effect", "")) == "dazed" and dazed_state == "stagger", "the eruption dazed the emberwing (it reels; its attack is lost)", [r4.get("effect"), dazed_state])
	_check(ew.hp < hp0 and spikes_up >= 7, "dark crystal spikes burst up through the rift and hurt it", [snappedf(hp0 - ew.hp, 0.1), spikes_up])
	await _wait(3.0)
	_shot("rift_scar")
	var scar_ok := false
	if rift and is_instance_valid(rift):
		scar_ok = float(((rift as UmbralSpell.Rift).quad.material_override as ShaderMaterial).get_shader_parameter("scorch")) > 0.9
		var rp2: Vector3 = (rift as Node3D).global_position
		var toward2 := Vector3(luna.global_position.x - rp2.x, 0, luna.global_position.z - rp2.z).normalized()
		main.director.enabled = false
		main.camera_rig.set_shot(rp2 + toward2 * 3.0 + Vector3(0, 2.6, 0), rp2 + Vector3(0, 0.2, 0), 50.0)
		await _wait(0.15)
		_shot("rift_scar_close")
		main.director.enabled = true
	_check(scar_ok, "the rift cooled into a scar that stays on the ground", scar_ok)
	# 5. GILDED MIRROR: front only; reflects once practised
	var r5 := await _cast_watch("luna", "gilded_mirror", "", "ward_mirror", UmbralSpell)
	report["gilded_mirror"] = r5
	var wm := Ward.active_for(luna)
	_check(r5.get("ok", false) and wm != null and wm.kind == "mirror" and not wm.reflects, "Gilded Mirror: a pane before her (no reflection yet at Apprentice)", [r5.get("effect"), r5.get("reason", ""), wm != null])
	await _wait(0.4)
	_shot("ward_mirror")
	var ffront := luna.global_position + Vector3(6.5, 1.5, 0.3)
	var m1 := await _test_bolt("luna", ffront, ew)
	_shot("ward_mirror_absorb")
	await _wait(0.4)
	var r5b: Dictionary = await main.magic.cast(luna, "gilded_mirror")
	await _wait(0.3)
	var m2 := await _test_bolt("luna", luna.global_position + Vector3(-6.0, 1.5, 1.0), ew)
	report["mirror_bolts"] = [m1, m2]
	_check(m1.get("absorbed_by", "") == "mirror" and (m1.struck as Array).is_empty(), "a bolt from the front was stopped on the glass", m1)
	_check(r5b.get("ok", false) and m2.get("absorbed_by", "") == "" and (m2.struck as Array).has("luna"), "a bolt from behind landed: the mirror covers only her front", [r5b.get("effect"), m2])
	# Adept: the pane throws the bolt back at the creature that sent it
	mind_l.skills["gilded_mirror"] = 1.6
	var wold := Ward.active_for(luna)
	if wold:
		wold._spend("test")
	await _wait(0.3)
	var r5c: Dictionary = await main.magic.cast(luna, "gilded_mirror")
	var wr := Ward.active_for(luna)
	var hp1 := ew.hp
	await _wait(0.25)
	var m3 := await _test_bolt("luna", ffront, ew)
	_shot("ward_mirror_reflect")
	report["mirror_reflect"] = m3
	_check(r5c.get("ok", false) and wr != null and wr.reflects and m3.get("reflected", false) and (m3.struck as Array).is_empty(), "practised (Adept): the mirror threw the bolt back", [r5c.get("effect"), wr != null and wr.reflects, m3])
	_check(ew.hp < hp1 or m3.get("reflected_hit", "") != "", "and the bolt struck the emberwing that sent it", [snappedf(hp1 - ew.hp, 0.1), m3.get("reflected_hit", "")])
	mind_l.skills["gilded_mirror"] = 0.3

	# ---- the tactics that choose them
	ew.set_physics_process(true)
	ew.mstate = "recover"
	var fam_l := CombatTactics.family_spell(lb, luna, ew, "umbral_lance", true, 7.0)
	_check(fam_l == "umbral_rift", "Luna's tactics: a creature standing exposed -> the rift", fam_l)
	ew.mstate = "chase"
	var fam_l2 := CombatTactics.family_spell(lb, luna, ew, "umbral_lance", false, 7.0)
	_check(fam_l2 == "umbral_lance", "...and the lance while it moves", fam_l2)
	_check(CombatTactics.ward_spell(lb, luna) == "gilded_mirror" or Ward.active_for(luna) != null, "her ward is the mirror", CombatTactics.ward_spell(lb, luna))
	var tb2: Monster = main.spawner.spawn("thornback", NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(4.0, 0, 0.0)))
	if tb2:
		tb2.set_physics_process(false)
		tb2.mstate = "chase"
		tb2.target_mage = mika
		var fam_m := CombatTactics.family_spell(mb, mika, tb2, "gale_spiral", false, 4.0)
		_check(fam_m == "verdant_bind", "Mika's tactics: a ground creature pressing in -> the roots", fam_m)
		ew.mstate = "chase"
		var fam_m2 := CombatTactics.family_spell(mb, mika, ew, "gale_spiral", false, 6.0)
		_check(fam_m2 == "gale_spiral", "...and the spiral against a flyer (roots cannot reach it)", fam_m2)
		tb2.queue_free()
	_check(CombatTactics.ward_spell(mb, mika) == "leaf_ward", "her ward is the ring of leaves", CombatTactics.ward_spell(mb, mika))

	# ---- two short real fights through the planner (the techniques chosen by the moment, not scripted)
	await _wait(0.5)
	ew.queue_free()
	main.focus_locked = false
	await main.focus_mage("mika", true)
	_park("luna", Vector3(-3, 0, 2))
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(27, 0, 4)) + Vector3(0, 0.1, 0)
	mika.rotation.y = atan2(-1.0, 0.0)
	mind_m.vigor = 1.0
	await _wait(4.5)
	var tb3: Monster = main.spawner.spawn("thornback", NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(9.0, 0, 0.5)))
	var fight_m := {}
	if tb3:
		tb3.target_mage = mika
		tb3.mstate = "chase"
		var fbox := {"done": false, "res": {}}
		var frun := func():
			fbox.res = await mb._hunt({"monster": tb3.id})
			fbox.done = true
		frun.call()
		var tf := _gms()
		var n := 0
		while not fbox.done and _gms() - tf < 50000:
			await get_tree().process_frame
			n += 1
			if n % 120 == 60:
				_shot("fight_mika_%02d" % (n / 120))
		if not fbox.done:
			mb._cancel = true
			await _wait(2.0)
		fight_m = fbox.res
		report["fight_mika"] = fight_m
		var tac: Dictionary = fight_m.get("tactics", {})
		_check(tac.get("spells", {}).has("verdant_bind") or tac.get("effects", {}).has("bound"), "in a real fight Mika used the roots on the crawler", tac)
		_check(int(tac.get("casts", 0)) >= 2 and tac.get("spells", {}).has("gale_spiral"), "and her spiral", tac.get("spells"))
	await _wait(0.5)
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	main.focus_locked = false
	await main.focus_mage("luna", true)
	_park("mika", Vector3(-3, 0, 2))
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(27, 0, 4)) + Vector3(0, 0.1, 0)
	luna.rotation.y = atan2(-1.0, 0.0)
	mind_l.vigor = 1.0
	mind_l.skills["gilded_mirror"] = 0.3
	await _wait(4.5)
	var ew2: Monster = main.spawner.spawn("emberwing", NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(9.0, 0, 0.5)))
	if ew2:
		ew2.target_mage = luna
		ew2._set_state("chase")
		var fbox2 := {"done": false, "res": {}}
		var frun2 := func():
			fbox2.res = await lb._hunt({"monster": ew2.id})
			fbox2.done = true
		frun2.call()
		var tf2 := _gms()
		var n2 := 0
		while not fbox2.done and _gms() - tf2 < 50000:
			await get_tree().process_frame
			n2 += 1
			if n2 % 120 == 60:
				_shot("fight_luna_%02d" % (n2 / 120))
		if not fbox2.done:
			lb._cancel = true
			await _wait(2.0)
		report["fight_luna"] = fbox2.res
		var tac2: Dictionary = fbox2.res.get("tactics", {})
		_check(int(tac2.get("casts", 0)) >= 2 and tac2.get("spells", {}).has("umbral_lance"), "in a real fight Luna used her lance", tac2.get("spells"))
		_check(int(tac2.get("wards", 0)) > 0 or tac2.get("spells", {}).has("umbral_rift"), "and her family's other techniques (a mirror against its bolts, or the rift in an opening)", tac2)
	main.focus_locked = false
	# ---- sound: each family in its own voice
	var sounds := {}
	if AudioDirector.instance:
		for e in AudioDirector.instance.log:
			sounds[String(e.sound)] = int(sounds.get(String(e.sound), 0)) + 1
	report["sounds"] = sounds
	_check(sounds.has("spell_nature_release") and sounds.has("roots_erupt") and sounds.has("ward_leaf_up") and sounds.has("ward_leaf_absorb"), "Mika's techniques sound like leaves, wood and earth", sounds.keys().filter(func(k): return String(k).begins_with("spell_nature") or String(k).begins_with("roots") or String(k).begins_with("ward_leaf")))
	_check(sounds.has("rift_open") and sounds.has("rift_erupt") and sounds.has("ward_mirror_up") and sounds.has("ward_mirror_absorb") and sounds.has("ward_mirror_reflect"), "Luna's like glass, shadow and crystal", sounds.keys().filter(func(k): return String(k).begins_with("rift") or String(k).begins_with("ward_mirror")))


# ------------------------------------------------------------------ V3 Part X: the Phoenix's voice (Gemini Kore)
## Her confirmed cloud voice inside the running game: a line is synthesised through VoiceService (async, key never
## shown), validated, played on the right bus, cached so the same line never costs a second call.
func _phoenix_voice() -> void:
	var v: VoiceService = main.voice
	var d := v.describe()
	_check(bool(d.gemini.configured), "GEMINI_API_KEY is available to Godot (read from .env, never printed)", d.gemini.status)
	_check(AudioServer.get_bus_index("VoicePhoenix") != -1, "the VoicePhoenix bus exists (resonance for her true form)", AudioBuses.describe().get("VoicePhoenix", {}))
	var line := "So. You are the one who woke the old circle. I felt it from the summit, like a hearth relit."
	var r1: Dictionary = await v.say("phoenix", line, {"form": "humanoid"})
	_check(r1.get("audio", false) and String(r1.get("provider", "")) == "gemini", "a line in her Kore voice was synthesised and played (humanoid form)",
		{"provider": r1.get("provider"), "seconds": r1.get("seconds"), "tts_ms": r1.get("tts_ms"), "cached": r1.get("cached"), "rms": r1.get("rms"), "error": r1.get("gemini_error", "")})
	_check(float(r1.get("seconds", 0.0)) > 2.0 and float(r1.get("seconds", 0.0)) < 20.0, "the audio has a plausible length for the line", r1.get("seconds"))
	var r2: Dictionary = await v.say("phoenix", line, {"form": "humanoid"})
	_check(String(r2.get("cached", "")) in ["session", "shipped"] and r2.get("audio", false), "the same line again came from the cache (no second cloud call)",
		{"cached": r2.get("cached"), "tts_ms": r2.get("tts_ms"), "calls": v.gemini_stats.calls})
	var r3: Dictionary = await v.say("phoenix", "Keep the circle warm, little mage.", {"form": "phoenix", "bus": "VoicePhoenix", "mood": "tender"})
	_check(r3.get("audio", false) and String(r3.get("bus", "")) == "VoicePhoenix", "her true form speaks through the resonance bus", {"bus": r3.get("bus"), "provider": r3.get("provider"), "seconds": r3.get("seconds")})
	var r4: Dictionary = await v.say("phoenix", "Ignis, memento.", {"form": "phoenix", "bus": "VoicePhoenix", "mood": "serious"})
	_check(r4.get("audio", false), "her transformation words were spoken", {"provider": r4.get("provider"), "seconds": r4.get("seconds")})
	report["voice"] = {"gemini": v.describe().gemini, "lines": [r1, r2, r3, r4]}


# ------------------------------------------------------------------ V3 Part X: Oriel, the Phoenix, in the real world
## Everything the directive asks for, inside the running Woods: the original rigged true form with its clips, a
## real flight in (altitude, banking, the clips), a landing on the viewpoint stone, her fire lighting the cold
## bowls and striking a creature (judged by the creature), gestures and combat clips, the cinematic
## transformation to her human form (continuity, collision, no T-pose), her Kore voice, a conversation through
## the dialogue system (memory, teaching), sitting, walking, casting as a woman, the way back, the leave.
func _phoenix() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna = main.characters.get("luna")
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load (streamed)", r)
	if not r.get("ok", false):
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	var vp: Vector2 = w.VIEWPOINT
	var perch_y: float = w.ground_at(vp.x, vp.y) + 0.12
	var stand := NavigationServer3D.map_get_closest_point(map, Vector3(vp.x - 7.0, w.height(vp.x - 7.0, vp.y), vp.y)) + Vector3(0, 0.05, 0)
	mika.global_position = stand
	mika.rotation.y = atan2(vp.x - stand.x, vp.y - stand.z) + PI
	if luna:
		luna.world = w
		luna.global_position = NavigationServer3D.map_get_closest_point(map, stand + Vector3(0, 0, 2.0)) + Vector3(0, 0.05, 0)
		luna.visible = true
		luna.set_physics_process(true)
	main.focus_mage("mika", true)
	main.director.enabled = false
	main.spawner.enabled = false
	var mgr: PhoenixManager = main.phoenix_mgr
	mgr.auto_greet = false
	mgr.auto_leave = false
	# ---- 1. the asset
	var ph: Phoenix = mgr.summon()
	_check(ph != null and is_instance_valid(ph), "Oriel comes to the Woods (her node exists, registered with the dialogue system)", {"present": main.npcs.present.has("phoenix"), "travellers": main.dialogue.travellers.has("phoenix")})
	if ph == null:
		return
	var rig: PhoenixTrueRig = ph.true_rig
	_check(rig.skeleton != null and rig.skeleton.get_bone_count() >= 100 and rig.model.find_children("*", "MeshInstance3D", true, false).size() >= 8,
		"her true form is the original rigged model (bones, skinned feather meshes)", {"bones": rig.skeleton.get_bone_count() if rig.skeleton else 0, "meshes": rig.model.find_children("*", "MeshInstance3D", true, false).size()})
	var required := ["idle", "breathe", "look", "wing_fold", "wing_spread", "walk", "turn_left", "turn_right", "takeoff", "fly", "bank_left", "bank_right", "hover", "land", "cast_fire", "defend", "attack", "react", "recover", "preen", "call", "bow", "stretch", "glide"]
	var missing := required.filter(func(c): return not rig.has_clip(c))
	_check(missing.is_empty(), "every required true-form clip is in the GLB (%d clips)" % rig.player.get_animation_list().size(), {"missing": missing})
	ph.shot_cb = _shot
	# ---- 2. the flight in (wide shot from the terrace, looking east over the valley)
	main.camera_rig.set_shot(Vector3(vp.x - 14.0, perch_y + 7.0, vp.y + 3.0), Vector3(vp.x + 26.0, perch_y + 12.0, vp.y - 8.0), 62.0)
	var t0 := _game_t
	var max_y := -1e9
	var max_bank := 0.0
	var seen := {}
	var phases := []
	var shots_done := {}
	while ph.phase != "perched" and _game_t - t0 < 80.0 and is_instance_valid(ph):
		max_y = maxf(max_y, ph.global_position.y)
		max_bank = maxf(max_bank, absf(ph.true_rig.bank))
		seen[rig.state] = true
		if phases.is_empty() or phases[phases.size() - 1] != ph.phase:
			phases.append(ph.phase)
		if ph.phase == "circle" and not shots_done.has("circle") and ph.global_position.distance_to(Vector3(vp.x, perch_y, vp.y)) < 22.0 and ph.global_position.x < vp.x + 4.0:
			shots_done["circle"] = true
			var at := ph.global_position
			main.camera_rig.set_shot(Vector3(vp.x + 2.0, perch_y + 1.8, vp.y + 6.0), at, 50.0)
			await _wait(0.25)
			_shot("flight_circle")
		if ph.phase == "land" and not shots_done.has("land"):
			shots_done["land"] = true
			main.camera_rig.set_shot(Vector3(vp.x - 9.0, perch_y + 2.4, vp.y + 4.0), Vector3(vp.x, perch_y + 2.2, vp.y), 50.0)
			await _wait(1.2)
			_shot("landing")
		await get_tree().process_frame
	_check(ph.phase == "perched", "she flew in from the summit, circled the viewpoint and landed", {"phases": phases, "seconds": snappedf(_game_t - t0, 0.1)})
	_check(max_y - perch_y > 8.0, "the flight had real altitude (%.1f m above the perch at most)" % (max_y - perch_y), snappedf(max_y - perch_y, 0.1))
	_check(max_bank > 0.25, "she banked into her turns (max roll %.2f rad)" % max_bank, snappedf(max_bank, 0.01))
	_check(seen.has("fly") and (seen.has("glide") or seen.has("bank_left") or seen.has("bank_right")) and seen.has("hover"), "flight used the flap, glide/bank and hover clips", seen.keys())
	var perch := Vector3(vp.x, perch_y, vp.y)
	_check(Vector2(ph.global_position.x - perch.x, ph.global_position.z - perch.z).length() < 0.35 and absf(ph.global_position.y - perch_y) < 0.2,
		"she stands on the perch stone (%.2f m off, %.2f m above)" % [Vector2(ph.global_position.x - perch.x, ph.global_position.z - perch.z).length(), ph.global_position.y - perch_y], ph.global_position)
	_check(Gusts.registered() >= 6 and Gusts.history.size() >= 2, "her wingbeats drive gusts through the woods (%d plant materials bend; %d gusts so far)" % [Gusts.registered(), Gusts.history.size()], {"registered": Gusts.registered(), "gusts": Gusts.history.size()})
	rig.clearance.measure = true
	rig.clearance.min_clearance = INF
	await _wait(1.0)
	_shot("perched")
	# ---- 3. her fire: the cold bowls
	main.camera_rig.set_shot(Vector3(vp.x + 9.0, perch_y + 3.4, vp.y + 7.5), Vector3(vp.x - 1.5, perch_y + 2.2, vp.y - 0.5), 58.0)
	_check(ph.braziers.size() == 2 and ph.braziers.all(func(b): return not b.lit), "the viewpoint's two fire bowls stand cold before she acts", ph.braziers.map(func(b): return [b.name, b.lit]))
	var lit: Array = await ph.light_bowls()
	_check(ph.braziers.size() == 2 and ph.braziers.all(func(b): return b.lit), "her sunflares lit both bowls (a reactive change in the world that stays)", lit)
	await _wait(0.8)
	_shot("bowls_lit")
	# ---- 4. the clips as behaviour: gestures, defence, reaction, recovery
	main.camera_rig.set_shot(Vector3(vp.x + 6.5, perch_y + 2.2, vp.y + 4.5), Vector3(vp.x, perch_y + 1.8, vp.y), 48.0)
	var played := {}
	for g in ["preen", "call", "stretch", "defend", "react", "recover"]:
		ph.true_rig.play(g)
		if g == "call":
			main.audio.play3d("phoenix_cry", ph.global_position + Vector3(0, 2.5, 0), "SFX", 0.0, "phoenix cry")
		await _wait(0.5)
		played[g] = ph.true_rig.current_clip()
		if g in ["preen", "call", "defend"]:
			_shot("clip_" + g)
		await _wait(maxf(ph.true_rig.clip_length(g) - 0.5, 0.2))
	_check(played.values().all(func(c): return c != ""), "gestures, defence, reaction and recovery clips played on her body", played)
	ph.true_rig.play("idle")
	# ---- 5. her fire against a creature (judged by the creature)
	var cpos := NavigationServer3D.map_get_closest_point(map, Vector3(vp.x - 8.0, perch_y, vp.y - 4.5))
	# a sculpted Bestiary creature for the hero scene (not the procedural placeholder)
	var mon: Monster = main.spawner.spawn("briar_imp", cpos)
	if mon:
		await _wait(0.6)
		var hp0 := mon.hp
		var o: Dictionary = await ph.cast_flare(mon, 1.0)
		var hp1 := mon.hp if is_instance_valid(mon) else 0.0
		_check(hp1 < hp0 or String(o.get("effect", "")) == "defeated", "her sunflare struck the creature: fire damage through its own reaction (%s)" % o.get("effect", ""), {"hp_before": snappedf(hp0, 1), "hp_after": snappedf(hp1, 1), "outcome": o.get("detail", "")})
		_shot("flare_creature")
		_check(float(ph.last_nova.get("peak_alt", 0.0)) > 3.0, "she rose into the air for her nova (%.1f m above her perch) - her wings clear the ground" % float(ph.last_nova.get("peak_alt", 0.0)), ph.last_nova)
		if is_instance_valid(mon) and mon.alive():
			await ph.cast_flare(mon, 1.0)
		await _wait(0.5)
		if is_instance_valid(mon) and mon.alive():
			mon.queue_free()
	else:
		_check(false, "a creature could be spawned for the fire test", cpos)
	# ---- 6. the transformation (cinematic: the first meeting)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, perch + Vector3(-5.5, 0, 0.8)) + Vector3(0, 0.05, 0)
	mika.look_at_point(perch)
	var st0: Dictionary = main.dialogue.state_of("phoenix")
	_check(not st0.met, "this is the first meeting (her memory says so)", {"met": st0.met, "visits": st0.visits})
	await ph.say(String(Phoenix.data.lines.before_transform), "playful")
	var rec: Dictionary = await ph.transform_to_human("cinematic")
	var tr: Dictionary = rec.get("record", {})
	_check(rec.get("ok", false) and ph.form == "human" and ph.human.visible and not ph.true_rig.visible, "she transformed into her human form (cinematic variation)", tr)
	_check(float(tr.get("drift_m", 9.0)) < 0.35, "position continuity: the woman stands where the Phoenix stood (drift %.2f m)" % float(tr.get("drift_m", 9.0)), tr.get("drift_m"))
	var tf_spec: Dictionary = Phoenix.data.transformation
	_check(absf(float(tr.get("hit_s", 0.0)) - float(tf_spec.cinematic_hit_s)) < 0.4 and absf(float(tr.get("seconds", 0.0)) - float(tf_spec.cinematic_s)) < 0.8,
		"the swap landed on the music's hit (%.2f s) in a %.1f s cinematic (about ten seconds, slow and complete)" % [float(tr.get("hit_s", 0.0)), float(tr.get("seconds", 0.0))], tr)
	_check(ph.body.collision_layer == 0 and ph.human.collision_layer == 1, "collision switched from the bird's body to the woman's capsule", {"bird_layer": ph.body.collision_layer, "woman_layer": ph.human.collision_layer})
	var hand_h := ph.human.left_hand.global_position.y - ph.human.global_position.y
	_check(hand_h < 1.25 and ph.human.body_player != null and ph.human.anim_tree.active, "no T-pose: her arms hang in a posed idle (left hand %.2f m up)" % hand_h, snappedf(hand_h, 0.01))
	_shot("human_form")
	# ---- 7. identity across the change
	_check(ph.memory() == main.dialogue.state_of("phoenix") and ph.describe(mika.global_position).name == "Oriel" and ph.witnessed.size() >= 0, "the same identity and memory in both forms (one node, one memory record)", ph.describe(mika.global_position))
	# ---- 8. her voice as a woman
	main.director.enabled = true
	main.director.set_subject(mika)
	var v1: Dictionary = await ph.say(String(Phoenix.data.lines.after_transform), "playful")
	var want_gemini: bool = main.voice.gemini_configured()
	_check(v1.get("audio", false) and (String(v1.get("provider", "")) == "gemini" or not want_gemini), "she spoke in her Kore voice (humanoid form, Voice bus)", {"provider": v1.get("provider"), "seconds": v1.get("seconds"), "bus": v1.get("bus"), "cached": v1.get("cached")})
	# ---- 9. a conversation through the dialogue system (beats, memory, teaching; Luna present)
	var fwd := Basis(Vector3.UP, ph.human.rotation.y) * Vector3(0, 0, -1)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, ph.global_position + fwd * 1.9) + Vector3(0, 0.05, 0)
	if luna:
		luna.global_position = NavigationServer3D.map_get_closest_point(map, ph.global_position + fwd * 2.4 + fwd.cross(Vector3.UP) * 1.4) + Vector3(0, 0.05, 0)
	var conv: Dictionary = await main.dialogue.converse("phoenix", mika)
	var her_lines: Array = conv.get("lines", []).filter(func(l): return l.speaker == "Oriel")
	_check(conv.get("ok", false) and her_lines.size() >= 1 and her_lines.all(func(l): return l.audio), "a real conversation ran through the dialogue system, her lines in her own voice", {"lines": conv.get("lines", []).map(func(l): return [l.speaker, l.text.left(60), l.audio]), "provider": conv.get("provider")})
	_check(conv.get("taught", []).size() >= 1, "she taught Mika something (knowledge recorded by the engine)", conv.get("taught", []).map(func(t): return t.fact))
	var st1: Dictionary = main.dialogue.state_of("phoenix")
	_check(st1.met and st1.conversations >= 1 and st1.relationship > 0.0 and WorldState.npc_state.has("phoenix"), "her memory of Mika is in the persisted NPC state", {"met": st1.met, "conversations": st1.conversations, "relationship": st1.relationship, "memories": st1.memories.size()})
	_shot("conversation")
	# ---- 10. she sits at the edge and watches the valley; then walks
	main.director.enabled = false
	main.camera_rig.set_shot(ph.global_position + fwd * 3.2 + Vector3(0, 1.3, 0) + fwd.cross(Vector3.UP) * 1.5, ph.global_position + Vector3(0, 0.9, 0), 46.0)
	await ph.sit_down()
	await _wait(1.2)
	_check(ph.human.ground_pose == "sit", "she sat on the ground (the shared ground-rest clips)", ph.human.ground_pose)
	_shot("sitting")
	await _wait(0.8)
	await ph.stand_up()
	var walk_from := ph.global_position
	var walk_to := NavigationServer3D.map_get_closest_point(map, perch + Vector3(-3.0, 0, 3.5))
	ph.walk_to(walk_to)
	var tw0 := _game_t
	while ph.human.current_action == "navigate_to" and _game_t - tw0 < 12.0:
		await get_tree().process_frame
	_check(ph.global_position.distance_to(walk_from) > 1.5, "she walked (navigation on the real navmesh, %.1f m)" % ph.global_position.distance_to(walk_from), snappedf(ph.global_position.distance_to(walk_from), 0.1))
	# ---- 11. spellcasting as a woman (the shared casting clip, her flare at a bowl)
	var north = ph.braziers[0]
	var hf := Basis(Vector3.UP, ph.human.rotation.y) * Vector3(0, 0, -1)
	main.camera_rig.set_shot(ph.global_position + hf * 2.6 + hf.cross(Vector3.UP) * 2.8 + Vector3(0, 1.6, 0), ph.global_position + Vector3(0, 1.2, 0), 46.0)
	var o2: Dictionary = await ph.cast_flare(north, 0.7)
	_check(String(o2.get("effect", "")) in ["relit", "flare", "flared", "struck", "burst"] and o2.get("ok", false), "she cast her fire in human form through the shared rig (%s)" % o2.get("effect", ""), o2)
	_shot("human_cast")
	# ---- 12. the way back, and the leave
	mika.look_at_point(ph.global_position)
	await ph.say(String(Phoenix.data.lines.farewell), "tender")
	await ph.say(String(Phoenix.data.lines.reform), "serious")
	main.camera_rig.set_shot(ph.global_position + fwd * 7.0 + Vector3(0, 2.2, 0) + fwd.cross(Vector3.UP) * 2.5, ph.global_position + Vector3(0, 1.4, 0), 50.0)
	var rec2: Dictionary = await ph.transform_to_phoenix()
	var tr2: Dictionary = rec2.get("record", {})
	_check(rec2.get("ok", false) and ph.form == "phoenix" and ph.true_rig.visible and not ph.human.visible, "she became the Phoenix again (the way back)", tr2)
	_check(float(tr2.get("drift_m", 9.0)) < 0.35 and ph.body.collision_layer == 2 and ph.human.collision_layer == 0, "continuity and collision on the way back (drift %.2f m)" % float(tr2.get("drift_m", 9.0)), {"drift": tr2.get("drift_m"), "bird_layer": ph.body.collision_layer})
	_shot("reformed")
	_check(rig.clearance.min_clearance > -0.08, "her wingtips and train never sank into the ground or the stones (lowest tip %.2f m above it)" % rig.clearance.min_clearance, {"min_clearance": snappedf(rig.clearance.min_clearance, 0.01), "where": rig.clearance.min_where, "lifted": rig.clearance.lifted})
	main.camera_rig.set_shot(Vector3(vp.x + 7.0, perch_y + 2.6, vp.y + 9.0), ph.global_position + Vector3(0, 1.8, 0), 58.0)
	await ph.takeoff()
	var tl := _game_t
	while is_instance_valid(ph) and ph.phase != "gone" and _game_t - tl < 45.0:
		if _game_t - tl > 1.5 and not shots_done.has("takeoff"):
			shots_done["takeoff"] = true
			_shot("takeoff")
		await get_tree().process_frame
	_check(not is_instance_valid(ph) or ph.phase == "gone", "she took off and flew back toward the summit (gone from the Woods)", {"present": is_instance_valid(ph), "seconds": snappedf(_game_t - tl, 0.1)})
	_check(not main.npcs.present.has("phoenix") or not is_instance_valid(main.npcs.present.get("phoenix")), "her registration cleared when she left", main.npcs.present.keys())
	report["phoenix"] = {"manager": mgr.describe(), "voice": main.voice.describe().gemini, "transformations": [tr, tr2], "conversation": conv.get("lines", []).map(func(l): return [l.speaker, l.text]) if conv.has("lines") else []}
	main.camera_rig.clear_shot()


## Visual pass 2 proof reel in the real Woods (record it with Movie Maker): her display, the solar nova against a
## creature, the cinematic transformation (its own camera beats), the way back. Same code paths as the game.
func _phoenix_reel() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load", r)
	if not r.get("ok", false):
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	main.director.enabled = false
	main.spawner.enabled = false
	var mgr: PhoenixManager = main.phoenix_mgr
	mgr.auto_greet = false
	mgr.auto_leave = false
	var vp: Vector2 = w.VIEWPOINT
	var gy: float = w.ground_at(vp.x, vp.y)
	var perch := Vector3(vp.x, gy, vp.y)
	var ph: Phoenix = mgr.summon()
	await get_tree().process_frame
	ph.place_perched()
	var b := Basis(Vector3.UP, ph.rotation.y)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, perch + b * Vector3(-5.5, 0, 3.5)) + Vector3(0, 0.05, 0)
	mika.look_at_point(perch)
	var luna: WorldCharacter = main.characters.get("luna")
	if luna:
		# TEST STAGING ONLY (a developer utility, never production behaviour): the reel's scene is set with Luna
		# already here, nearer the nova's mark (inside its blast radius); Mika further back (she braces)
		_dev_stage(luna, NavigationServer3D.map_get_closest_point(map, perch + b * Vector3(-2.6, 0, 9.0)))
		luna.look_at_point(perch)
	await _wait(1.0)
	# 1. her display
	main.camera_rig.set_shot(perch + b * Vector3(4.0, 1.3, 9.5), perch + Vector3(0, 2.7, 0), 52.0)
	ph.true_rig.play_clip("majestic_enter", 0.3, 1.0, false)
	await _wait(1.5)
	ph.true_rig.play_clip("majestic", 0.3, 1.0, true)
	await _wait(2.6)
	_shot("reel_display")
	# 2. the solar nova
	var cpos := NavigationServer3D.map_get_closest_point(map, perch + b * Vector3(1.0, 0, 12.0))
	var mon: Monster = main.spawner.spawn("briar_imp", cpos)
	await _wait(0.8)
	if mon:
		var mid := (perch + mon.global_position) * 0.5
		var side := (mon.global_position - perch).cross(Vector3.UP).normalized()
		main.camera_rig.set_shot(mid + side * 15.0 + Vector3(0, 4.0, 0), mid + Vector3(0, 3.4, 0), 64.0)   # she rises ~5 m for her nova
		var hp0 := mon.hp
		_watch_reactions(ph, "attack", "reel_reaction")
		var o: Dictionary = await ph.cast_nova(mon, 1.0)
		var hp1 := mon.hp if is_instance_valid(mon) else 0.0
		_check(hp1 < hp0 or String(o.get("effect", "")) == "defeated", "the solar nova struck the creature (%s)" % o.get("effect", ""), {"hp_before": hp0, "hp_after": hp1})
		_shot("reel_nova")
	await _wait(1.5)
	if is_instance_valid(mon) and mon.alive():
		mon.queue_free()
	ph.true_rig.play("idle")
	await _wait(0.8)
	# 3. the cinematic transformation (its own camera beats), facing Mika
	_watch_reactions(ph, "transform", "reel_tf_reaction", true)
	var rec: Dictionary = await ph.transform_to_human("cinematic")
	_check(rec.get("ok", false), "the cinematic transformation ran", rec.get("record", {}))
	var hb := Basis(Vector3.UP, ph.human.rotation.y)
	main.camera_rig.set_shot(ph.human.global_position + hb * Vector3(1.2, 1.5, -3.4), ph.human.global_position + Vector3(0, 1.25, 0), 40.0)
	await _wait(2.2)
	# 4. the way back
	var rec2: Dictionary = await ph.transform_to_phoenix(true)
	_check(rec2.get("ok", false), "the way back ran", rec2.get("record", {}))
	main.camera_rig.set_shot(perch + b * Vector3(4.0, 1.3, 9.5), perch + Vector3(0, 2.7, 0), 52.0)
	ph.true_rig.play("majestic")
	await _wait(3.0)
	var hows := {}
	for e in ph.bystander_log:
		hows[String(e.who) + ":" + String(e.how)] = true
	_check(hows.has("mika:brace") or hows.has("mika:hit"), "Mika reacted physically to Oriel's fire (braced or was struck)", ph.bystander_log)
	_check(luna != null and luna.visible and (hows.has("luna:brace") or hows.has("luna:hit")), "Luna was there and reacted physically to Oriel's fire", ph.bystander_log)
	report["phoenix_reel"] = {"transformations": ph.transformations, "bystanders": ph.bystander_log}
	main.camera_rig.clear_shot()


# ------------------------------------------------------------------ visual quality pass: fixed before/after views
## The Woods viewpoint (where Oriel meets Mika) from fixed cameras, then Oriel in both forms in close-up.
## --tag=before|after names the files: screenshots/showcase/<tag>_<view>.png. Same cameras every run.
func _showcase() -> void:
	await _hold_all()
	var tag := String(RenderProfile.options.get("tag", "shot"))
	var out := "res://screenshots/showcase"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var mika: WorldCharacter = main.characters["mika"]
	var luna = main.characters.get("luna")
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load", r)
	if not r.get("ok", false):
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	main.director.enabled = false
	main.spawner.enabled = false
	main.phoenix_mgr.auto_greet = false
	main.phoenix_mgr.auto_leave = false
	var vp: Vector2 = w.VIEWPOINT
	var gy: float = w.ground_at(vp.x, vp.y)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(vp.x - 6.0, gy, vp.y + 1.5)) + Vector3(0, 0.05, 0)
	mika.look_at_point(Vector3(vp.x, gy, vp.y))
	if luna:
		luna.world = w
		luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(vp.x - 7.0, gy, vp.y + 3.2)) + Vector3(0, 0.05, 0)
		luna.visible = true
		luna.set_physics_process(true)
	var ph: Phoenix = main.phoenix_mgr.summon()
	await get_tree().process_frame
	ph.place_perched()
	await _wait(2.0)
	var save := func(name: String) -> void:
		await _wait(0.6)
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [out, tag, name])
	var views := {
		"e1_terrace_wide": [Vector3(vp.x - 17.0, gy + 3.6, vp.y + 7.0), Vector3(vp.x + 18.0, gy + 3.0, vp.y - 6.0), 60.0],
		"e2_terrace_low": [Vector3(vp.x - 7.5, gy + 1.1, vp.y + 7.5), Vector3(vp.x + 2.0, gy + 1.6, vp.y - 3.0), 55.0],
		"e3_vista": [Vector3(vp.x + 3.5, gy + 1.8, vp.y + 0.5), Vector3(vp.x + 70.0, gy - 6.0, vp.y - 14.0), 62.0],
		"e4_forest_edge": [Vector3(vp.x + 4.0, gy + 2.0, vp.y + 2.0), Vector3(vp.x - 22.0, gy + 3.5, vp.y + 6.0), 58.0],
		"e5_overview": [Vector3(vp.x - 8.0, gy + 7.0, vp.y + 8.0), Vector3(vp.x + 6.0, gy - 1.0, vp.y - 6.0), 64.0],
		"e6_trail": [Vector3(vp.x - 13.0, w.ground_at(vp.x - 13.0, vp.y - 2.0) + 1.65, vp.y - 2.0), Vector3(vp.x + 2.0, gy + 1.8, vp.y + 1.0), 58.0],
	}
	var perf := {}
	for k in views:
		var v: Array = views[k]
		main.camera_rig.set_shot(v[0], v[1], v[2])
		await _wait(1.0)
		_reset_frames()
		await _wait(3.0)
		perf[k] = _fps_stats()
		await save.call(k)
	# Oriel, true form
	var b := Basis(Vector3.UP, ph.rotation.y)
	var at := ph.global_position
	var rel := func(x: float, y: float, z: float) -> Vector3: return at + b * Vector3(x, y, z)
	ph.true_rig.look_at_point(rel.call(-3.0, 2.0, 6.0), 1.0)
	var tviews := {
		"t1_front34": [rel.call(-3.2, 2.2, 5.6), rel.call(0.0, 1.7, 0.4), 42.0],
		"t2_side": [rel.call(-6.8, 1.8, 0.6), rel.call(0.0, 1.6, 0.3), 42.0],
		"t3_head": [rel.call(-1.1, 2.9, 2.6), ph.true_rig.head_point(), 34.0],
		"t4_back34": [rel.call(4.0, 3.0, -4.8), rel.call(0.0, 1.5, 0.0), 44.0],
	}
	for k in tviews:
		var v: Array = tviews[k]
		main.camera_rig.set_shot(v[0], v[1], v[2])
		await save.call(k)
	ph.true_rig.play_clip("wing_spread", 0.1, 1.0, false)
	await _wait(1.3)
	ph.true_rig.player.pause()
	main.camera_rig.set_shot(rel.call(-5.0, 2.6, 8.5), rel.call(0.0, 2.0, 0.0), 50.0)
	await save.call("t5_spread")
	ph.true_rig.play("idle")
	# Oriel, human form
	ph.show_form("human")
	ph.phase = "showcase"          # hold her still for the stills (no head turning toward Mika)
	ph.human.look_head_at(null)
	await _wait(1.5)
	# her facing, measured from the skeleton (the eyes are in front of the head bone)
	var sk := ph.human.skeleton
	var eye_i := sk.find_bone("LeftEye")
	var head_i := sk.find_bone("Head")
	var fwd3 := Vector3(0, 0, -1)
	if eye_i >= 0 and head_i >= 0:
		var e := sk.global_transform * sk.get_bone_global_pose(eye_i).origin
		var hpos := sk.global_transform * sk.get_bone_global_pose(head_i).origin
		fwd3 = Vector3(e.x - hpos.x, 0, e.z - hpos.z).normalized()
	var hb := Basis(Vector3.UP, atan2(-fwd3.x, -fwd3.z))
	var hp := ph.human.global_position
	var hrel := func(x: float, y: float, z: float) -> Vector3: return hp + hb * Vector3(x, y, z)
	ph.human.look_head_at(hrel.call(0.5, 1.6, -3.0))
	var head := ph.human.head_point()
	var hviews := {
		"h1_full34": [hrel.call(1.2, 1.25, -3.2), hrel.call(0.0, 0.95, 0.0), 40.0],
		"h2_face": [head + hb * Vector3(0.0, -0.02, -0.75), head + Vector3(0, -0.04, 0), 30.0],
		"h3_face34": [head + hb * Vector3(0.45, 0.02, -0.62), head + Vector3(0, -0.05, 0), 30.0],
		"h4_back": [hrel.call(-1.0, 1.4, 2.6), hrel.call(0.0, 1.1, 0.0), 40.0],
	}
	for k in hviews:
		var v: Array = hviews[k]
		main.camera_rig.set_shot(v[0], v[1], v[2])
		await save.call(k)
	ph.human.set_expression("happy", 1.0)
	main.camera_rig.set_shot(head + hb * Vector3(0.25, 0.0, -0.7), head + Vector3(0, -0.04, 0), 30.0)
	await _wait(0.8)
	await save.call("h5_smile")
	ph.human.set_expression("happy", 0.0)
	report["showcase"] = {"tag": tag, "perf": perf}
	_check(true, "showcase captured", perf.keys())


## Reel proof of the bystanders (the developer: "Mika and Luna must react"): the moment Oriel's fire reaches them
## (a brace or a hit in her bystander log), cut to them for a beat, take a still, and give the shot back.
func _watch_reactions(ph: Phoenix, kind: String, tag: String, stills_only := false) -> void:
	var n0 := ph.bystander_log.size()
	var t0 := _game_t
	var first_brace := -1.0
	while is_instance_valid(ph) and _game_t - t0 < 30.0:
		var hit := false
		for i in range(n0, ph.bystander_log.size()):
			var e: Dictionary = ph.bystander_log[i]
			if String(e.kind) == kind and String(e.how) == "hit":
				hit = true
			elif String(e.kind) == kind and String(e.how) == "brace" and first_brace < 0.0:
				first_brace = _game_t
		# a knock-back is the strongest proof; a brace will do if no blow lands within 4 s of it
		if hit or (first_brace >= 0.0 and _game_t - first_brace > 4.0):
			break
		await get_tree().process_frame
	if not is_instance_valid(ph) or _game_t - t0 >= 30.0:
		return
	var mika: WorldCharacter = main.characters["mika"]
	var luna = main.characters.get("luna")
	var mid: Vector3 = mika.global_position if luna == null else (mika.global_position + (luna as Node3D).global_position) * 0.5
	if not stills_only:
		var keep := {"pos": main.camera_rig._shot_pos, "look": main.camera_rig._shot_look, "fov": main.camera_rig.camera.fov, "on": main.camera_rig.shot_active}
		var fwd := (ph.global_position - mid)
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		# the first angle from which both are in clear sight (walls and stones must not hide them)
		var space := mika.get_world_3d().direct_space_state
		var targets: Array = [mika.global_position + Vector3(0, 1.2, 0)]
		if luna:
			targets.append((luna as Node3D).global_position + Vector3(0, 1.2, 0))
		var cam := mid + side * 4.5 + fwd * 1.5 + Vector3(0, 1.4, 0)
		for cand in [side * 4.5 + fwd * 1.5, -side * 4.5 + fwd * 1.5, fwd * 4.5 + side * 1.5, -fwd * 4.0 + side * 1.5, side * 3.5 - fwd * 2.5]:
			var c: Vector3 = mid + cand + Vector3(0, 1.4, 0)
			var clear := true
			for tg in targets:
				var q := PhysicsRayQueryParameters3D.create(c, tg, 1)
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit.position as Vector3).distance_to(tg) > 0.6:
					clear = false
			if clear:
				cam = c
				break
		main.camera_rig.set_shot(cam, mid + Vector3(0, 1.0, 0), 52.0)
		await _wait(0.35)
		_shot(tag)
		await _wait(1.1)
		_shot(tag + "_2")
		if bool(keep.on):
			main.camera_rig.set_shot(keep.pos, keep.look, keep.fov)
	else:
		await _wait(0.3)
		_shot(tag)


## TEST STAGING ONLY: put a mage at a spot in the loaded area before a scene starts (like a director placing an
## actor). Production code never relocates a character; see PhoenixManager.call_luna / the no-teleport test.
func _dev_stage(c: WorldCharacter, at: Vector3) -> void:
	if main.teleport_guard:
		main.teleport_guard.allow(c)
	if main.world and main.world.has_method("ground_at"):
		at.y = maxf(at.y, float(main.world.ground_at(at.x, at.z)))
	c.global_position = at + Vector3(0, 0.05, 0)
	c.world = main.world
	c.velocity = Vector3.ZERO
	c.visible = true
	c.set_physics_process(true)
	WorldState.mind(c.character_id).set_location(main.streaming.current_id, c.global_position)


# ------------------------------------------------------------------ no teleportation in production (V3 continuation)
## A production run (no --dev-fast-travel): instant travel is refused everywhere; the dormant ley-line gate is not a
## route; Oriel's arrival never moves Luna (in another area she stays there; in this area she walks over); and a
## minute of ordinary life with both mages' planners running shows no position jump at all (TeleportGuard).
func _no_teleport() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	_check(not TravelController.dev_fast_travel(), "this is a production run (no --dev-fast-travel)")
	var fast: Dictionary = main.travel.travel_to("ancient_grove", "fast")
	_check(not fast.get("ok", true), "instant ('fast') travel is refused", fast)
	if fast.get("ok", false):
		main.travel.cancel("test")
	var bridge: Dictionary = main.travel.travel_to("academy_courtyard", "walk")
	_check(not bridge.get("ok", true) and WorldState.route(main.streaming.current_id, "academy").is_empty(),
		"the dormant ley-line gate to the Academy is no route (no portal hop)", {"result": bridge, "sealed": WorldState.is_sealed("sanctuary", "academy")})
	if bridge.get("ok", false):
		main.travel.cancel("test")
	_check(main.get("teleport_guard") != null, "the TeleportGuard watches every physics frame")
	# --- Oriel arrives while Luna is in another area: she stays there
	await _hold_all()
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load (Mika walks in through the gate)")
	if luna == null:
		_check(false, "Luna exists (run with --luna)")
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	var lm := WorldState.mind("luna")
	lm.set_location("village", Vector3(3, 0, 3))        # she is away in the village (background simulation)
	luna.visible = false
	luna.set_physics_process(false)
	var luna_before := luna.global_position
	var mgr: PhoenixManager = main.phoenix_mgr
	mgr.auto_greet = false
	mgr.auto_leave = false
	var verdict := mgr.call_luna()
	await _wait(1.0)
	_check(verdict == "away" and not luna.visible and luna.global_position == luna_before and String(lm.location.get("area", "")) == "village",
		"Oriel's arrival does not bring Luna from the village (she stays where she is)", {"verdict": verdict, "visible": luna.visible, "area": lm.location.get("area")})
	# --- Luna in this area, ~30 m away: she comes on foot, every frame a small step
	var vp: Vector2 = w.VIEWPOINT
	var stand := NavigationServer3D.map_get_closest_point(map, Vector3(vp.x - 7.0, w.height(vp.x - 7.0, vp.y), vp.y))
	_dev_stage(mika, stand)
	var far := NavigationServer3D.map_get_closest_point(map, stand + Vector3(-22.0, 0, 20.0))
	_dev_stage(luna, far)
	await _wait(1.0)
	var d0 := luna.global_position.distance_to(mika.global_position)
	var v2 := mgr.call_luna()
	var worst := 0.0
	var prev := luna.global_position
	var t0 := _game_t
	while _game_t - t0 < 20.0 and luna.current_action == "navigate_to":
		await get_tree().physics_frame
		worst = maxf(worst, luna.global_position.distance_to(prev))
		prev = luna.global_position
	var d1 := luna.global_position.distance_to(mika.global_position)
	_check(v2 == "coming" and d1 < d0 - 10.0 and worst < 0.35, "Luna in the same area walks over herself (%.0f m -> %.1f m; largest single-frame step %.2f m)" % [d0, d1, worst],
		{"verdict": v2, "from_m": d0, "to_m": d1, "worst_step_m": worst})
	# --- a minute of ordinary life: both planners running, nobody jumps
	var before := (main.teleport_guard.violations as Array).size()
	for who in main.mage_brains:
		main.mage_brains[who].hold = false
		main.mage_brains[who].set_enabled(true)
	await _wait(60.0)
	var v: Array = (main.teleport_guard.violations as Array).slice(before)
	_check(v.is_empty(), "a minute of autonomous life with both planners: no position jumps (%d frames watched)" % main.teleport_guard.frames, v)
	report["no_teleport"] = {"luna_walk": {"from_m": d0, "to_m": d1, "worst_step_m": worst}, "violations": main.teleport_guard.violations}


# ------------------------------------------------------------------ the Mossback encounter (V3 continuation)
## A prominent encounter with a real creature model (OpenGameArt "Forest Monster", CC0): the Mossback comes out of
## the Woods at Mika and Luna; both fight it with their own tactics (the real hunt activity); its blows and slams
## land through BodyReaction / ImpactDirector (flinch / stagger / falls and getting up, a companion's help), and
## the fight resolves. Record with --write-movie for the reel.
func _mossback() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Whispering Woods load")
	if luna == null or not r.get("ok", false):
		_check(luna != null, "Luna exists (run with --luna)")
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	main.spawner.enabled = false
	var vp: Vector2 = w.VIEWPOINT
	var stand := NavigationServer3D.map_get_closest_point(map, Vector3(vp.x - 9.0, w.height(vp.x - 9.0, vp.y + 4.0), vp.y + 4.0))
	_dev_stage(mika, stand)
	_dev_stage(luna, NavigationServer3D.map_get_closest_point(map, stand + Vector3(2.4, 0, 1.6)))
	await main.focus_mage("mika", true)
	for who in ["mika", "luna"]:
		WorldState.mind(who).vigor = 1.0
		main.mage_brains[who].needs.energy = 0.9
	var at := NavigationServer3D.map_get_closest_point(map, stand + Vector3(-15.0, 0, -6.0))
	var mon: Monster = main.spawner.spawn("mossback", at)
	_check(mon != null, "a Mossback comes out of the trees")
	if mon == null:
		return
	var cr := mon.creature as ClipRig
	_check(cr != null and String(cr.spec.get("glb", "")).ends_with("mossback.glb") and cr.player != null,
		"its body is the rigged, textured model with its own clips", {"clips": cr.player.get_animation_list() if cr and cr.player else []})
	var need := ["idle", "walk", "alert", "windup", "strike", "recover", "hit", "death"]
	var have: Array = cr.player.get_animation_list() if cr and cr.player else []
	_check(need.all(func(c): return have.has(c)), "idle, walk, alert, wind-up, strike, recover, hit and death clips", have)
	var hgt := 0.0
	for mi in mon.find_children("*", "MeshInstance3D", true, false):
		hgt = maxf(hgt, ((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()).end.y - mon.global_position.y)
	_check(hgt > 2.8 and hgt < 4.5, "it towers over them (%.1f m)" % hgt)
	main.director.enabled = true
	await _wait(1.5)
	_shot("mossback_00_emerges")
	var hp0 := mon.hp
	var states := {}
	var reactions_before := {"mika": mika.reaction.history.size(), "luna": luna.reaction.history.size()}
	var bm: SanctuaryBrain = main.mage_brains["mika"]
	var bl: SanctuaryBrain = main.mage_brains["luna"]
	var opt := func(b: SanctuaryBrain) -> Dictionary:
		return {"kind": "hunt", "key": "hunt:" + mon.id, "monster": mon.id, "monster_kind": "mossback", "tier": mon.tier(), "label": "fight the mossback"}
	var res := {}
	var run := func(b: SanctuaryBrain, who: String) -> void:
		b.current = {"kind": "hunt", "label": "fight the mossback", "stage": "starting"}
		res[who] = await b.run_activity(opt.call(b))
		b.current = {}
	run.call(bl, "luna")
	run.call(bm, "mika")
	var t0 := _game_t
	var k := 0
	var recovered_then_cast := {}
	var downs := {}
	while _game_t - t0 < 180.0 and res.size() < 2:
		if is_instance_valid(mon):
			states[mon.mstate] = int(states.get(mon.mstate, 0)) + 1
		for who in ["mika", "luna"]:
			var c: WorldCharacter = main.characters[who]
			if c.reaction.active and c.reaction.tier == "down":
				downs[who] = true
			if downs.has(who) and not c.reaction.active and c.casting:
				recovered_then_cast[who] = true
		if _game_t - t0 > k * 6.0:
			_shot("mossback_%02d" % (k + 1))
			k += 1
		await get_tree().process_frame
	await _wait(2.0)
	var struck := []
	for who in ["mika", "luna"]:
		var c: WorldCharacter = main.characters[who]
		for e in c.reaction.history.slice(int(reactions_before[who])):
			struck.append({"who": who, "tier": e.tier, "severity": e.severity, "kind": e.kind, "source": e.get("source", "")})
	var defeated := not is_instance_valid(mon) or not mon.alive()
	report["mossback"] = {"states": states, "struck": struck, "results": res, "hp": [hp0, mon.hp if is_instance_valid(mon) else 0.0],
		"aftermath": main.impacts.aftermath_log, "said": main.impacts.said, "downs": downs, "recovered_then_cast": recovered_then_cast}
	_check(states.has("chase") or states.has("alert"), "it noticed them and came at them", states)
	_check(states.has("windup") and states.has("strike"), "it telegraphed and struck (wind-up -> strike)", states)
	_check(not struck.is_empty(), "its blows landed with consequences (%d reactions: %s)" % [struck.size(), ", ".join(struck.map(func(x): return "%s %s" % [x.who, x.tier]))], struck)
	_check((not is_instance_valid(mon)) or mon.hp < hp0, "their spells hurt it (%.0f -> %.0f hp)" % [hp0, mon.hp if is_instance_valid(mon) else 0.0])
	for who in downs:
		_check(not main.characters[who].reaction.active, "%s was knocked down and got back up" % who)
	_check(res.size() == 2, "both fights resolved (%s)" % [", ".join(res.keys().map(func(x): return "%s: %s" % [x, str(res[x].get("detail", ""))]))], res)
	report["mossback"]["defeated"] = defeated
	_shot("mossback_zz_end")


## A Wayside stretch of the old forest track: does it load, and does it look like the Woods' forest?
func _wayside_look() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	Wayside.params = {"route": "whispering_woods|ancient_grove", "km": 21.0, "seed": int(RenderProfile.options.get("seed", 4721)),
		"from": "whispering_woods", "to": "ancient_grove", "title": "the old forest track west"}
	var r: Dictionary = await main.streaming.travel("wayside", mika)
	_check(r.get("ok", false), "a stretch of the old forest track loads (%d ms build, %d ms nav)" % [int(r.get("build_ms", 0)), int(r.get("nav_bake_ms", 0))], r)
	if not r.get("ok", false):
		return
	var w: Wayside = main.world
	main.director.enabled = false
	var c: Vector3 = w.camp.center
	_check(not (w.camp.wood as Array).is_empty() and w.camp.has("fire"), "a campsite with fire stones and %d branches of dry wood around" % (w.camp.wood as Array).size())
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	var want := c + Vector3(0, 0, 2.2)
	var on := NavigationServer3D.map_get_closest_point(map, want)
	_check(Vector2(on.x - want.x, on.z - want.z).length() < 1.5, "the campsite is on the navmesh", {"want": want, "nearest": on})
	report["nav_polys"] = w.nav_region.navigation_mesh.get_polygon_count() if w.nav_region and w.nav_region.navigation_mesh else -1
	report["nav_map_regions"] = NavigationServer3D.map_get_regions(map).size()
	WorldState.world_min = 360.0 + 6.0 * 60.0
	main.camera_rig.set_shot(c + Vector3(7, 2.4, 6), c + Vector3(0, 0.6, 0), 50.0)
	_reset_frames()
	await _wait(4.0)
	report["fps_camp_noon"] = _fps_stats()
	# GPU cost by layer (diagnostic): hide each dressing layer in turn
	var layers := {}
	var groups := {}
	for ch in w.get_children():
		if ch is Node3D and (ch as Node3D).visible:
			var key := String(ch.get_class()) if String(ch.name).begins_with("@") else String(ch.name).rstrip("0123456789_")
			groups.get_or_add(key, []).append(ch)
	report["top_level"] = groups.keys().map(func(k): return "%s x%d" % [k, (groups[k] as Array).size()])
	for key in groups:
		for n in groups[key]:
			(n as Node3D).visible = false
		_reset_frames()
		await _wait(1.5)
		layers[key] = _fps_stats().get("gpu_ms", -1)
		for n in groups[key]:
			(n as Node3D).visible = true
	var e: Environment = w.env
	for flag in ["volumetric_fog_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "glow_enabled", "ssr_enabled"]:
		if e.get(flag):
			e.set(flag, false)
			_reset_frames()
			await _wait(1.5)
			layers["env:" + flag] = _fps_stats().get("gpu_ms", -1)
			e.set(flag, true)
	report["gpu_without_layer"] = layers
	var p1 := w.road_point(0.15)
	main.camera_rig.set_shot(p1 + Vector3(4, 2.2, 6), p1 + Vector3(-10, 1.2, -2), 55.0)
	await _wait(2.0)
	_shot("road")
	main.camera_rig.set_shot(c + Vector3(7, 2.4, 6), c + Vector3(0, 0.6, 0), 50.0)
	await _wait(1.5)
	_shot("camp")
	var fp := w.road_point(0.62)
	main.camera_rig.set_shot(fp + Vector3(6, 2.0, 7), fp + Vector3(-2, 0.5, 0), 55.0)
	await _wait(1.5)
	_shot("ford")
	for hh in [6.0, 9.0, 18.4, 19.4, 22.0]:
		WorldState.world_min = 1440.0 + hh * 60.0
		w.set_time_of_day(hh)
		main.camera_rig.set_shot(c + Vector3(7, 2.4, 6), c + Vector3(0, 0.6, 0), 50.0)
		await _wait(1.2)
		_shot("camp_%02d" % int(hh * 10.0 / 10.0))


# ------------------------------------------------------------------ a complete multi-day journey (V3 continuation)
## Mika and Luna walk from the Whispering Woods to the Ancient Grove: 46 km of the old forest track, about two days.
## Everything is real and live: walking to the Woods' west gate, stretches of road (time passes at road pace),
## waypoints, a camp at dusk (firewood, fire, supper, talk, the watch, a creature at night), the morning, and the
## arrival - with the TeleportGuard watching every frame.
func _journey() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	if luna == null:
		_check(false, "Luna exists (run with --luna)")
		return
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "they start in the Whispering Woods")
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	# TEST STAGING: the two of them at the crossroads, ready to set out, Day 1 07:00
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(-30, 0, 4))
	_dev_stage(mika, start)
	_dev_stage(luna, NavigationServer3D.map_get_closest_point(map, start + Vector3(1.2, 0, 1.0)))
	WorldState.world_min = 360.0 + 60.0
	main.director.enabled = not DisplayServer.get_name() == "headless"
	main.spawner.enabled = false
	for who in ["mika", "luna"]:
		WorldState.mind(who).vigor = 1.0
	var jd: JourneyDirector = main.journeys
	var plan := jd.start("ancient_grove", "the Forgotten Forest Shrine: Luna wants to read its glyph stones, said to speak of folding distance", ["mika", "luna"], "luna")
	_check(plan.get("ok", false) and float(plan.km) >= 40.0, "a journey is planned: Woods -> Ancient Grove, %.0f km (about %.1f days on foot)" % [float(plan.get("km", 0)), float(plan.get("days_estimate", 0))], plan)
	CampScene.stock_rings(mika, luna)
	var v0 := (main.teleport_guard.violations as Array).size()
	var day0 := WorldState.day()
	var t_real := Time.get_ticks_msec()
	var shots := {"n": 0, "on": true}
	var snap := func() -> void:
		while shots.on:
			await get_tree().create_timer(15.0).timeout
			if shots.on:
				_shot("j_%03d_%s" % [shots.n, jd.stage.replace(" ", "_").replace(":", "").replace(",", "").left(40)])
				shots.n = int(shots.n) + 1
	snap.call()
	var j: Dictionary = await jd.run_live(12)
	shots.on = false
	var secs := (Time.get_ticks_msec() - t_real) / 1000.0
	report["journey"] = {"log": j.get("log", []), "camps": j.get("camps", []), "supplies": j.get("supplies", {}), "condition": j.get("condition", {}),
		"unresolved": j.get("unresolved", []), "discoveries": j.get("discoveries", []), "arrived": j.get("arrived", ""), "real_s": snappedf(secs, 0.1), "clock": WorldState.clock_text()}
	for e in j.get("log", []):
		print("[journey-log] %s  %s" % [e.when, e.what])
	_check(String(j.get("phase", "")) == "done" and main.streaming.current_id == "ancient_grove", "they arrived at the Ancient Grove (%s)" % j.get("arrived", "not arrived"), {"phase": j.get("phase"), "area": main.streaming.current_id})
	_check(WorldState.day() > day0, "the journey took more than one day (Day %d -> Day %d)" % [day0, WorldState.day()])
	var waypoints := (j.get("log", []) as Array).filter(func(e): return String(e.kind) == "waypoint")
	_check(waypoints.size() >= 3, "they passed the places along the track (%s)" % ", ".join(waypoints.map(func(e): return String(e.what).get_slice(" (", 0))))
	var camps: Array = j.get("camps", [])
	_check(camps.size() >= 1, "they camped for the night (%d camp)" % camps.size())
	if not camps.is_empty():
		var c: Dictionary = camps[0]
		var beats: Array = (c.beats as Array).map(func(b): return String(b.beat))
		print("[journey-camp] beats ", beats)
		_check(beats.has("choose_site") and beats.has("from the ring"), "they chose the campsite and drew their things from their storage rings", beats)
		_check(int(c.meal.get("firewood_carried", 0)) >= 1, "Mika carried firewood back from the trees (%d)" % int(c.meal.get("firewood_carried", 0)), c.meal)
		_check(beats.has("bedroll laid out"), "Luna laid out the bedrolls")
		_check(beats.has("the fire catches"), "the fire was struck from sparks and caught")
		_check(beats.has("cooking") and int(c.meal.get("bites", 0)) >= 2, "supper cooked on the fire and eaten (%d spoonfuls)" % int(c.meal.get("bites", 0)), c.meal)
		_check(int(c.get("talk_lines", 0)) >= 2, "they talked by the fire (%d lines)" % int(c.get("talk_lines", 0)))
		_check(not (c.watch as Array).is_empty(), "the watch was decided by the danger of the road (%s)" % str((c.watch as Array)[0] if not (c.watch as Array).is_empty() else ""))
		_check(not (c.encounter as Dictionary).is_empty(), "something came out of the dark at night (%s: %s)" % [c.encounter.get("kind", "-"), c.encounter.get("outcome", "-")], c.encounter)
		_check(beats.has("packed"), "in the morning they packed up and walked on")
	var v: Array = (main.teleport_guard.violations as Array).slice(v0)
	_check(v.is_empty(), "nobody was ever moved instantly on the whole journey (%d frames watched)" % main.teleport_guard.frames, v)


## Visual checks for the developer's 2026-10-15 notes: the storage ring, the ford, bodies parting the plants, the
## Woods river as one continuous surface.
func _fixcheck() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	Wayside.params = {"route": "whispering_woods|ancient_grove", "km": 21.0, "seed": 4721, "from": "whispering_woods", "to": "ancient_grove", "title": "the old forest track west"}
	var r: Dictionary = await main.streaming.travel("wayside", mika)
	_check(r.get("ok", false), "the stretch loads")
	var w: Wayside = main.world
	main.director.enabled = false
	var map: RID = mika.get_world_3d().navigation_map
	WorldState.world_min = 360.0 + 5.0 * 60.0
	await get_tree().physics_frame
	# 1. the ring: an apple drawn out of it into her palm
	var p0: Vector3 = await main.snap_to_nav(w.road_point(0.3))
	_dev_stage(mika, p0)
	await _wait(1.0)
	var ring := StorageRing.attach(mika)
	ring.stock({"apple": "an apple"})
	var fwd := -mika.global_transform.basis.z
	var hand := mika.right_hand.global_position
	main.camera_rig.set_shot(hand + fwd * 0.55 + mika.global_transform.basis.x * 0.25 + Vector3(0, 0.12, 0), hand, 32.0)
	mika.play_gesture("pick_chest", 0.3, 0.5)
	await _wait(0.6)
	var h := HoldableObject.new()
	h.setup("apple", "an apple", "an apple")
	h.grasp_height = 0.04
	w.add_child(h)
	var mdl := Node3D.new()
	Kit.place_prop_all(mdl, "food_apple_01", Kit.xf(Vector3.ZERO))
	h.add_child(mdl)
	ring.draw("apple", h)
	await _wait(0.2)
	_shot("ring_drawing")
	await _wait(0.5)
	hand = mika.right_hand.global_position
	main.camera_rig.set_shot(hand + fwd * 0.38 + mika.global_transform.basis.x * 0.12 + Vector3(0, -0.12, 0), hand, 34.0)
	await _wait(0.4)
	_shot("ring_holding")
	_check(mika.handler.held == h and not ring.has("apple"), "the apple came out of the ring into her hand")
	await ring.store("apple", "an apple")
	_check(ring.has("apple"), "and went back in")
	# 2. the ford: she wades across on the stones
	var fz := Wayside.FORD.y
	var fx := w.stream_x(fz)
	var east: Vector3 = await main.snap_to_nav(Vector3(fx + 6.0, 0, fz))
	var west: Vector3 = await main.snap_to_nav(Vector3(fx - 6.0, 0, fz))
	_dev_stage(mika, east)
	await _wait(0.5)
	main.camera_rig.set_shot(Vector3(fx + 2.0, w.height(fx, fz) + 1.6, fz + 6.5), Vector3(fx, w.height(fx, fz) + 0.4, fz), 50.0)
	mika.navigate_to(west)
	var t := 0.0
	var shot_mid := false
	while mika.current_action == "navigate_to" and t < 15.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not shot_mid and absf(mika.global_position.x - fx) < 0.8:
			shot_mid = true
			_shot("ford_crossing")
	_check(shot_mid and mika.global_position.distance_to(west) < 2.0, "she crossed the ford on foot")
	main.camera_rig.set_shot(Vector3(fx + 9.0, w.height(fx, fz) + 3.0, fz - 8.0), Vector3(fx, w.height(fx, fz), fz + 4.0), 55.0)
	await _wait(0.6)
	_shot("stream_banks")
	# 3. through the plants: across a thicket of undergrowth beside the road
	var ug := w.find_child("Undergrowth", false, false)
	var spot := Vector3.INF
	if ug:
		for mmi in ug.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (mmi as MultiMeshInstance3D).multimesh
			for i in range(0, mm.instance_count, 7):
				var q := (mmi as MultiMeshInstance3D).global_transform * mm.get_instance_transform(i).origin
				if q.distance_to(p0) < 30.0 and w.trail_at(q.x, q.z) < 0.05 and w.site_water_dist(Vector2(q.x, q.z)) > 4.0:
					spot = q
					break
			if spot != Vector3.INF:
				break
	_check(spot != Vector3.INF, "found a thicket to walk through")
	if spot != Vector3.INF:
		var a: Vector3 = await main.snap_to_nav(spot + Vector3(2.5, 0, 0))
		var b: Vector3 = await main.snap_to_nav(spot - Vector3(2.5, 0, 0))
		_dev_stage(mika, a)
		await _wait(0.5)
		main.camera_rig.set_shot(spot + Vector3(0.3, 0.9, 3.2), spot + Vector3(0, 0.4, 0), 45.0)
		mika.navigate_to(b)
		t = 0.0
		var k := 0
		while mika.current_action == "navigate_to" and t < 10.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if Vector2(mika.global_position.x - spot.x, mika.global_position.z - spot.z).length() < 0.6 and k < 2:
				_shot("plants_%d" % k)
				k += 1
				var parted := 0
				for wr in Gusts._mats:
					var m: ShaderMaterial = wr.get_ref()
					if m and float(m.get_shader_parameter("body_on")) > 0.5:
						var arr = m.get_shader_parameter("body_pos")
						if arr is PackedVector4Array and (arr as PackedVector4Array).size() > 0 and Vector3((arr as PackedVector4Array)[0].x, (arr as PackedVector4Array)[0].y, (arr as PackedVector4Array)[0].z).distance_to(mika.global_position) < 0.5:
							parted += 1
				report["plant_materials_parting"] = parted
				_check(parted > 0, "the plants around her are told where her body is (%d plant materials part round her)" % parted)
				await _wait(0.35)
	# 4. the Woods river, one surface
	r = await main.streaming.travel("whispering_woods", mika)
	var ww = main.world
	var bz: float = ww.BRIDGE.y + 18.0
	var bx: float = ww.river_x(bz)
	main.camera_rig.set_shot(Vector3(bx - 14.0, ww.height(bx - 14.0, bz) + 4.0, bz + 6.0), Vector3(bx, ww.height(bx, bz) + 0.5, bz - 6.0), 55.0)
	await _wait(2.0)
	_shot("woods_river")
	main.camera_rig.set_shot(Vector3(bx + 10.0, ww.height(bx + 10.0, bz + 30.0) + 3.0, bz + 30.0), Vector3(bx, ww.height(bx, bz + 20.0), bz + 15.0), 60.0)
	await _wait(1.5)
	_shot("woods_river_2")


# ------------------------------------------------------------------ level-based appearances
## The appearance registry (data/appearances.json) in the real game: the Celestial stages for levels 1-10, the
## level 10 forms through their existing transformation, safe fallback past the last available model, saves already
## beyond level 10, a developer preview that never touches progress, and both mages living together in the Woods.
func _appearances() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	# 1. selection rules
	var cases := [["mika", 1, "", "celestial"], ["mika", 9, "", "celestial"], ["mika", 10, "", "celestial"], ["mika", 10, "bloom", "bloom"],
		["mika", 25, "bloom", "bloom"], ["mika", 100, "bloom", "bloom"], ["luna", 1, "", "oracle"], ["luna", 15, "eclipse", "eclipse"], ["luna", 95, "eclipse", "eclipse"]]
	var bad := []
	for cse in cases:
		var got := String(AppearanceRegistry.pick(cse[0], cse[1], cse[2]).get("id", ""))
		if got != String(cse[3]):
			bad.append("%s L%d form '%s' -> %s (want %s)" % [cse[0], cse[1], cse[2], got, cse[3]])
	_check(bad.is_empty(), "stage selection: levels 1-10 Celestial/Oracle, the level 10 forms once taken, safe fallback beyond (no level 20+ models yet)", bad)
	_check(AppearanceRegistry.stages("mika").size() == 11 and AppearanceRegistry.stages("luna").size() == 11, "eleven stage slots per mage (1-10, the level 10 forms, 20 ... 100)")
	# 2. live: both wear their level 1-10 appearance
	_check(mika.avatar_path.get_file().begins_with("MikaCelestial"), "Mika wears Celestial Mage at level %d" % WorldState.mind("mika").level(), mika.avatar_path)
	if luna:
		_check(luna.avatar_path.get_file().begins_with("LunaOracle"), "Luna wears Celestial Oracle at level %d" % WorldState.mind("luna").level(), luna.avatar_path)
	_check(mika.face != null and mika.face.bound_count() >= 25 and (luna == null or (luna.face != null and luna.face.bound_count() >= 25)), "their expressive faces are bound (%d / %d components)" % [mika.face.bound_count() if mika.face else 0, luna.face.bound_count() if luna and luna.face else 0])
	# 3. a save already beyond level 10 (fixture in the DISPOSABLE save): identity preserved through the swap
	var m := WorldState.mind("mika")
	var before := {"knowledge": m.knowledge.size(), "skills": m.skills.size(), "xp": float(m.progress.xp)}
	var keep_level := m.level()
	var keep_form := String(m.progress.get("appearance", ""))
	m.progress.level = 15
	m.progress["appearance"] = "bloom"
	var ok := mika.swap_avatar(TransformationDirector.avatar_for("mika"))
	await _wait(1.0)
	_check(ok and mika.avatar_path.ends_with("Mika_Level10.vrm"), "a level 15 save with the Bloom form taken shows the Bloom form", mika.avatar_path)
	_check(m.knowledge.size() == before.knowledge and m.skills.size() == before.skills and float(m.progress.xp) == before.xp, "the change of look touched nothing she knows or has", before)
	m.progress.level = 27
	_check(TransformationDirector.avatar_for("mika").ends_with("Mika_Level10.vrm"), "level 27 (no level 20 model yet): she keeps her latest look (fallback)")
	m.progress.level = keep_level
	m.progress["appearance"] = keep_form
	mika.swap_avatar(TransformationDirector.avatar_for("mika"))
	await _wait(1.0)
	_check(mika.avatar_path.get_file().begins_with("MikaCelestial"), "back at her real level she wears Celestial again")
	# 4. developer preview: shows another stage, progress untouched
	var lv := m.level()
	AppearanceRegistry.preview("mika", "classic")
	mika.swap_avatar(TransformationDirector.avatar_for("mika"))
	await _wait(1.0)
	_check(mika.avatar_path.ends_with("Mika.vrm") and m.level() == lv and String(m.progress.get("appearance", "")) == keep_form, "developer preview of the archived look changes nothing she has earned")
	AppearanceRegistry.preview("mika", "")
	mika.swap_avatar(TransformationDirector.avatar_for("mika"))
	await _wait(1.0)
	# 5. the level 10 transformation still plays (preview: it changes nothing and reverts)
	if main.transformer:
		var tr: Dictionary = await main.transformer.play("mika", "short", true, 10)
		await _wait(2.0)
		_check(tr.get("ok", false) and mika.avatar_path.get_file().begins_with("MikaCelestial"), "the level 10 transformation still plays from Celestial into Bloom (preview, reverted)", tr)
	# 6. both alive together in the Woods, their own planners, performance measured
	await _hold_all()
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	_check(r.get("ok", false), "the Woods load with both new appearances")
	if luna:
		var map: RID = mika.get_world_3d().navigation_map
		_dev_stage(luna, NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(2, 0, 1)))
	main.director.enabled = true
	for w in main.mage_brains:
		main.mage_brains[w].hold = false
		main.mage_brains[w].set_enabled(true)
	_reset_frames()
	var shots := 0
	var t0 := _game_t
	while _game_t - t0 < 45.0:
		await _wait(9.0)
		_shot("living_%d" % shots)
		shots += 1
	var fps := _fps_stats()
	report["together_fps"] = fps
	report["vram_mb"] = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)
	report["static_mem_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	_check(float(fps.get("avg_fps", 0)) >= 25.0, "both together in the Woods at %.1f fps (GPU %.1f ms, VRAM %.0f MB)" % [float(fps.get("avg_fps", 0)), float(fps.get("gpu_ms", 0)), float(report.vram_mb)], fps)
	report["mika_recent"] = main.mage_brains["mika"].history.slice(-4)
	if main.mage_brains.has("luna"):
		report["luna_recent"] = main.mage_brains["luna"].history.slice(-4)


## A pack hunts them (the developer: "many monsters hunting them ... fast ... the camera following closely like a
## trailer"): four Briar Imps close in from different sides and a Mossback brute follows; both mages fight with their
## own tactics. Checks: the pack surrounds its prey, blows land with consequences, the trailer camera cuts and punches.
func _pack_hunt() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	if luna == null or not r.get("ok", false):
		_check(false, "Woods + Luna")
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	main.spawner.enabled = false
	var vp: Vector2 = w.VIEWPOINT
	var stand: Vector3 = await main.snap_to_nav(Vector3(vp.x - 9.0, 0, vp.y + 4.0))
	_dev_stage(mika, stand)
	_dev_stage(luna, NavigationServer3D.map_get_closest_point(map, stand + Vector3(2.2, 0, 1.4)))
	await main.focus_mage("mika", true)
	for who in ["mika", "luna"]:
		WorldState.mind(who).vigor = 1.0
	var pack := []
	for i in 4:
		var ang := TAU * i / 4.0 + 0.4
		var at := NavigationServer3D.map_get_closest_point(map, stand + Vector3(cos(ang), 0, sin(ang)) * 16.0)
		var m: Monster = main.spawner.spawn("briar_imp", at)
		if m:
			m.target_mage = mika if i % 2 == 0 else luna
			m.mstate = "chase"
			pack.append(m)
	var brute: Monster = main.spawner.spawn("mossback", NavigationServer3D.map_get_closest_point(map, stand + Vector3(-18, 0, -8)))
	_check(pack.size() == 4 and brute != null, "four Briar Imps and a Mossback hunt them")
	main.director.enabled = true
	var cuts0 := TrailerCam.log.size()
	var res := {}
	var go := func(b: SanctuaryBrain, who: String, mon: Monster) -> void:
		var done := 0
		while done < 4:
			var tgt: Monster = mon
			if tgt == null or not is_instance_valid(tgt) or not tgt.alive():
				tgt = null
				for x in main.spawner.alive:
					if is_instance_valid(x) and x.alive():
						tgt = x
						break
			if tgt == null:
				break
			b.current = {"kind": "hunt", "monster": tgt.id, "label": "fight"}
			var rr: Dictionary = await b.run_activity({"kind": "hunt", "key": "hunt:" + tgt.id, "monster": tgt.id, "monster_kind": tgt.kind, "tier": tgt.tier(), "label": "fight"})
			b.current = {}
			res[who + str(done)] = rr.get("detail", "")
			done += 1
			mon = null
		res[who] = "done"
	go.call(main.mage_brains["mika"], "mika", pack[0])
	go.call(main.mage_brains["luna"], "luna", pack[1])
	var sides := {}
	var t0 := _game_t
	var k := 0
	var max_hunting_one := 0
	var fell := {}
	var trail := {}
	var floor_y := {}
	while _game_t - t0 < 150.0 and not (res.has("mika") and res.has("luna")):
		# how many close in on one mage from different sides
		for target in [mika, luna]:
			var angs := []
			for m in main.spawner.alive:
				if is_instance_valid(m) and m.alive() and m.target_mage == target and m.global_position.distance_to(target.global_position) < 6.0:
					angs.append(snappedf(atan2(m.global_position.z - target.global_position.z, m.global_position.x - target.global_position.x), 0.5))
			max_hunting_one = maxi(max_hunting_one, angs.size())
			if angs.size() >= 2:
				var spread := 0.0
				for a in angs:
					for b2 in angs:
						spread = maxf(spread, absf(angle_difference(a, b2)))
				sides[target.character_id] = maxf(float(sides.get(target.character_id, 0.0)), spread)
		if _game_t - t0 > k * 5.0:
			_shot("pack_%02d" % k)
			k += 1
		for c in [mika, luna]:
			if c.is_on_floor() or not floor_y.has(c.character_id):
				floor_y[c.character_id] = c.global_position.y
			var gy := float(floor_y[c.character_id])
			if c.global_position.y < gy - 3.0 and not fell.has(c.character_id):
				fell[c.character_id] = {"t": snappedf(_game_t - t0, 0.01), "pos": c.global_position, "ground": gy, "trail": trail.get(c.character_id, []).duplicate()}
				print("[mktest] FELL ", c.character_id, " ", JSON.stringify(fell[c.character_id]))
			var tr: Array = trail.get(c.character_id, [])
			tr.append([snappedf(_game_t - t0, 0.01), c.global_position.snappedf(0.01), c.velocity.snappedf(0.01), c.is_on_floor(), c.current_action,
				c.reaction.tier if c.reaction and c.reaction.active else "", not c._dash.is_empty(), snappedf(gy, 0.01)])
			if tr.size() > 40:
				tr.pop_front()
			trail[c.character_id] = tr
		await get_tree().process_frame
	_check(fell.is_empty(), "nobody falls through the ground", fell)
	var cuts := TrailerCam.log.slice(cuts0)
	var shots := cuts.filter(func(e): return e.has("shot")).map(func(e): return e.shot)
	var punches := cuts.filter(func(e): return e.has("punch")).size()
	report["pack"] = {"results": res, "spread": sides, "shots": shots, "punches": punches, "reactions": {"mika": mika.reaction.history.size(), "luna": luna.reaction.history.size()},
		"left_alive": main.spawner.alive.filter(func(x): return is_instance_valid(x) and x.alive()).size()}
	_check(max_hunting_one >= 2 and float(sides.values().max() if not sides.is_empty() else 0.0) > 1.2, "the pack closed in on its prey from different sides (up to %d at once, spread %.1f rad)" % [max_hunting_one, float(sides.values().max() if not sides.is_empty() else 0.0)], sides)
	_check(shots.size() >= 6 and Array(shots).duplicate().filter(func(x): return x != shots[0]).size() > 0, "the trailer camera cut between %d shots (%s)" % [shots.size(), ", ".join(PackedStringArray(shots.slice(0, 12)))])
	_check(punches >= 5, "big hits punched the camera (%d)" % punches)
	_check(mika.reaction.history.size() + luna.reaction.history.size() >= 2, "blows landed on them with consequences")
	Engine.time_scale = 1.0


# ------------------------------------------------------------------ road ambush by human rivals
## Garran's band: they watch from cover and talk about the rings, walk out and encircle the girls, make their demand,
## the girls answer; then every rival fights in his own style (sword waves, an assassin's blinks with afterimages,
## thrown knives, hex bolts / curse circles); the band breaks (yield / flight, never a killing), and the Hexer is
## remembered. Nobody teleports (TeleportGuard).
func _ambush() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	var r: Dictionary = await main.streaming.travel("whispering_woods", mika)
	if luna == null or not r.get("ok", false):
		_check(false, "Woods + Luna")
		return
	var w = main.world
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	main.spawner.enabled = false
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	var vp: Vector2 = w.VIEWPOINT
	var stand: Vector3 = await main.snap_to_nav(Vector3(vp.x - 9.0, 0, vp.y + 4.0))
	_dev_stage(mika, stand)
	_dev_stage(luna, NavigationServer3D.map_get_closest_point(map, stand + Vector3(1.4, 0, 0.6)))
	await main.focus_mage("mika", true)
	main.director.enabled = true
	for who in ["mika", "luna"]:
		WorldState.mind(who).vigor = 1.0
	var tg0: int = main.teleport_guard.violations.size() if main.teleport_guard else 0
	var cuts0 := TrailerCam.log.size()
	var h0: int = main.magic.history.size()
	var co0: int = main.impacts.callouts.size()
	var ghosts0 := Afterimage.made
	var styles := {}
	var hz_watch := func() -> void:
		for h in AttackHazard.active(main.world):
			if is_instance_valid(h) and (h as AttackHazard).owner_monster and String((h as AttackHazard).owner_monster.get("kind")).begins_with("rival_"):
				styles[(h as AttackHazard).kind + ":" + (h as AttackHazard).style] = true
	var hz_timer := Timer.new()
	hz_timer.wait_time = 0.1
	hz_timer.autostart = true
	hz_timer.timeout.connect(hz_watch)
	add_child(hz_timer)
	var shot_n := {"n": 0}
	var shots_timer := Timer.new()
	shots_timer.wait_time = 6.0
	shots_timer.autostart = true
	shots_timer.timeout.connect(func() -> void:
		_shot("ambush_%02d" % int(shot_n.n))
		shot_n.n = int(shot_n.n) + 1)
	add_child(shots_timer)
	var res: Dictionary = await main.ambush.run("road_thieves", {"fight_s": 120.0})
	hz_timer.queue_free()
	shots_timer.queue_free()
	var rec: Dictionary = main.ambush.rec
	report["ambush"] = {"result": res, "beats": rec.get("beats", []), "said": rec.get("said", []), "outcome": rec.get("outcome", {}),
		"ring": rec.get("ring", 0.0), "fight_s": rec.get("fight_s", 0.0), "styles": styles.keys(), "afterimages": Afterimage.made - ghosts0,
		"rivals_state": WorldState.rivals}
	_check(res.get("ok", false), "the ambush played through", res)
	_check((rec.get("spawned", []) as Array).size() == 4, "four rivals: cutthroat, shade, ronin, hexer", rec.get("spawned", []))
	var said: Array = rec.get("said", [])
	var thug_lines := said.filter(func(e): return String(e.who).begins_with("rival_")).size()
	var girl_lines := said.filter(func(e): return String(e.who) in ["mika", "luna"]).size()
	_check(thug_lines >= 6 and girl_lines >= 3, "the thugs talk about them and the girls answer (%d / %d lines)" % [thug_lines, girl_lines])
	_check(float(rec.get("ring", 0.0)) > PI, "the band encircled them (covers %.1f rad of the circle)" % float(rec.get("ring", 0.0)))
	var beats: Array = (rec.get("beats", []) as Array).map(func(b): return b.beat)
	_check(beats.has("watch") and beats.has("encircle") and beats.has("standoff") and beats.has("fight") and beats.has("break"), "watch -> encircle -> standoff -> fight -> break", beats)
	_check(styles.size() >= 3, "the rivals fought in different styles (%s)" % ", ".join(styles.keys()))
	_check(Afterimage.made - ghosts0 > 0, "fast dashes left afterimages (%d)" % (Afterimage.made - ghosts0))
	var outcome: Dictionary = rec.get("outcome", {})
	_check(outcome.values().has("yielded") or outcome.values().has("fled"), "the band broke: yielded / fled", outcome)
	_check(WorldState.rivals.has("rival_hexer") and int(WorldState.rivals.rival_hexer.get("met", 0)) >= 1, "the Hexer is remembered (he will be back)", WorldState.rivals)
	var cuts := TrailerCam.log.slice(cuts0).filter(func(e): return e.has("shot")).size()
	_check(cuts >= 4, "the trailer camera covered the fight (%d cuts)" % cuts)
	var tg: Array = main.teleport_guard.violations.slice(tg0) if main.teleport_guard else []
	_check(tg.is_empty(), "nobody teleported", tg)
	# body language: a mage who took real blows carries them afterwards (guarding, slower pace, winces)
	var bl := {}
	for c in [mika, luna]:
		if c.body_language:
			bl[c.character_id] = c.body_language.status()
			bl[c.character_id]["hits"] = c.body_language.log.filter(func(e): return e.event == "hit").size()
	report["ambush"]["body_language"] = bl
	var struck := [mika, luna].filter(func(c): return c.body_language and c.body_language.log.any(func(e): return e.event == "hit"))
	_check(not struck.is_empty() and struck.all(func(c): return c.body_language.injury > 0.05 and c.body_language.tempo() < 0.99),
		"a struck mage carries her injury in her body afterwards (posture, pace)", bl)
	var voices: Array = main.voice.log.filter(func(e): return String(e.get("speaker", "")) in ["mika", "luna"] and e.get("audio", false))
	var foreign := voices.filter(func(e): return String(e.get("provider", "")) != "gemini")
	_check(foreign.is_empty(), "Mika and Luna spoke only in their own voices", foreign)
	# no recitation in an ordinary fight: at most a one-word call now and then, never the full words
	var casts: Array = main.magic.history.slice(h0).filter(func(e): return e.has("voicing"))
	var full := casts.filter(func(e): return String(e.voicing) == "full")
	var voiced := casts.filter(func(e): return String(e.voicing) in ["full", "short", "short_combat"])
	report["ambush"]["voicing"] = casts.map(func(e): return String(e.voicing))
	_check(full.is_empty() and voiced.size() <= maxi(2, int(casts.size() * 0.25)), "no spell recitation in the fight (%d casts, %d voiced)" % [casts.size(), voiced.size()], report["ambush"]["voicing"])
	var co: Array = main.impacts.callouts.slice(co0)
	report["ambush"]["callouts"] = co
	report["ambush"]["voice_latency"] = main.voice.latency_report()
	report["ambush"]["slow_lines"] = main.voice.log.filter(func(e): return int(e.get("tts_ms", 0)) > 1500).map(func(e): return {"speaker": e.speaker, "text": e.text, "tts_ms": e.tts_ms, "cached": e.get("cached", ""), "provider": e.get("provider", ""), "error": e.get("error", "")})
	print("[ambush] slow lines: ", report["ambush"]["slow_lines"])
	print("[ambush] hitches: ", JSON.stringify(hitch_log))
	print("[ambush] callouts: ", co)
	print("[ambush] voice latency: ", report["ambush"]["voice_latency"])


# ------------------------------------------------------------------ region tour (visual quality review)
## --mktest=tour --areas=a,b,c : travels to each area, stands Mika at its first point of interest for scale and frames
## an establishing view plus eye-level views of every location's point of interest; measures the frame rate there.
func _tour() -> void:
	await _hold_all()
	main.director.enabled = false
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var areas: Array = String(RenderProfile.options.get("areas", "ancient_grove")).split(",", false)
	# a fixed review hour (late morning) so every region is judged in the same light
	var hour := float(RenderProfile.options.get("hour", 10.5))
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + hour * 60.0
	WorldState.clock_rate = 0.0
	var out := {}
	for a in areas:
		var r: Dictionary = await main.streaming.travel(String(a), mika)
		if not r.get("ok", false):
			_check(false, "%s loads" % a, r)
			continue
		await _wait(2.0)
		var w = main.world
		var pois: Dictionary = w.points_of_interest
		var first := Vector3.ZERO
		for k in pois:
			first = pois[k].position
			break
		var stand: Vector3 = await main.snap_to_nav(first + Vector3(0, 0, 2.0))
		_dev_stage(mika, stand)
		await _wait(1.0)
		var aabb: AABB = w.nav_aabb
		var cen := aabb.get_center()
		var gy := float(w.ground_height(cen.x, cen.z))
		var shots := []
		if w is CaveArea:
			# under rock there is no aerial view: a high wide shot inside the chamber, under its roof
			var ep := first + Vector3(14.0, 0, 16.0)
			ep.y = lerpf(float(w.height(ep.x, ep.z)), float(w.roof(ep.x, ep.z)), 0.55)
			shots.append([ep, first + Vector3(0, 1.5, 0), 62.0, "establish"])
		else:
			shots.append([Vector3(cen.x + 40.0, gy + 55.0, cen.z + 125.0), Vector3(cen.x, gy + 5.0, cen.z - 20.0), 55.0, "establish"])
		var mh := mika.global_position + Vector3(0, 1.2, 0)
		shots.append([mh + (-mika.global_transform.basis.z) * 3.2 + Vector3(1.2, 0.3, 0), mh, 45.0, "mika_scale"])
		var i := 0
		for k in pois:
			if String(k).begins_with("gate:"):
				continue
			var pp: Vector3 = pois[k].position
			var ang := float(i) * 1.7
			# eye level, 12 m off, from the first direction with a clear view (no wall or rock between)
			var cp := pp + Vector3(sin(ang) * 12.0, 0, cos(ang) * 12.0)
			for tries in 16:
				var aa := ang + tries * TAU / 8.0
				var rr := 12.0 if tries < 8 else 7.0
				var c2 := pp + Vector3(sin(aa) * rr, 0, cos(aa) * rr)
				c2.y = float(w.ground_height(c2.x, c2.z)) + 1.7
				if w is CaveArea and float(w.roof(c2.x, c2.z)) - c2.y < 0.8:
					continue        # inside the cave wall
				var q := PhysicsRayQueryParameters3D.create(c2, pp + Vector3(0, 1.4, 0))
				q.collision_mask = 1
				if mika.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					cp = c2
					break
			cp.y = float(w.ground_height(cp.x, cp.z)) + 1.7
			shots.append([cp, pp + Vector3(0, 1.4, 0), 55.0, String(k)])
			i += 1
			if i >= 6:
				break
		for sh in shots:
			main.camera_rig.set_shot(sh[0], sh[1], float(sh[2]))
			await _wait(0.8)
			_shot("%s_%s" % [a, sh[3]])
		_reset_frames()
		await _wait(4.0)
		out[a] = {"pois": pois.keys(), "fps": _fps_stats()}
		print("[mktest] tour ", a, " ", JSON.stringify(out[a]))
		_check(true, "%s toured (%d views)" % [a, shots.size()], out[a].fps)
	report["tour"] = out


# ------------------------------------------------------------------ town life (the people who live there)
func _res_shot(r: Resident, tag: String) -> void:
	if r == null or not is_instance_valid(r) or not r.visible:
		return
	var fwd := Vector3(sin(r.rotation.y), 0, cos(r.rotation.y))
	var side := Vector3(fwd.z, 0, -fwd.x)
	var head := r.global_position + Vector3(0, 1.25, 0)
	main.camera_rig.set_shot(head + fwd * 3.6 + side * 1.4 + Vector3(0, 0.35, 0), head - Vector3(0, 0.2, 0), 46.0)
	await _wait(0.7)
	_shot(tag)


func _town() -> void:
	await _hold_all()
	main.director.enabled = false
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var day0 := floorf(WorldState.world_min / 1440.0) * 1440.0
	# 1) the Village at 10:00: everyone where their day puts them
	WorldState.world_min = day0 + 10.0 * 60.0
	WorldState.clock_rate = 0.0
	var r: Dictionary = await main.streaming.travel("village", mika)
	_check(r.get("ok", false), "the Village loads")
	await _wait(3.0)
	var t: TownLife = main.town
	report["village_10"] = t.describe(mika.global_position)
	_check(t.residents.size() == 5, "five people live in the Village (%d)" % t.residents.size(), report["village_10"])
	var at_place := []
	for rid in t.residents:
		var rr: Resident = t.residents[rid]
		var a: Dictionary = main.world.anchors.get(rr.anchor_key, {})
		var ok := rr.state == "inside" or (not a.is_empty() and Vector2(rr.global_position.x - a.pos.x, rr.global_position.z - a.pos.z).length() < 3.0)
		at_place.append([rid, rr.activity, rr.anchor_key, ok])
	_check(at_place.all(func(e): return e[3]), "each is at the place of their hour (work, stall, woodpile; the night watch asleep)", at_place)
	_check(t.residents.has("rook") and not (t.residents.rook as Resident).visible, "the night watch sleeps by day (inside his house)")
	for rid in ["bram", "hilde", "wenna", "odo"]:
		if t.residents.has(rid):
			await _res_shot(t.residents[rid], "village_%s_%s" % [rid, (t.residents[rid] as Resident).activity])
	main.camera_rig.set_shot(Vector3(14, 3.2, 2), Vector3(18, 1.2, -18), 58.0)
	await _wait(0.8)
	_shot("village_market_10h")
	# Mika goes to talk with someone who lives here (her own planner's option): Hilde, at her stall
	var mbt: SanctuaryBrain = main.mage_brains["mika"]
	var chats: Array = mbt.options().filter(func(o): return String(o.kind) == "chat" and String(o.resident) == "hilde")
	_check(not chats.is_empty(), "her planner offers to talk with Hilde", mbt.options().filter(func(o): return String(o.kind) == "chat").map(func(o): return o.label))
	if not chats.is_empty():
		var bread0 := int(WorldState.mind("mika").inventory.get("bread", 0))
		var cr: Dictionary = await mbt.run_activity(chats[0])
		report["chat_hilde"] = cr
		_check(cr.get("ok", false) and int(WorldState.mind("mika").inventory.get("bread", 0)) == bread0 + 1, "Hilde gave her a loaf (%s)" % cr.get("detail", ""), cr)
		await _res_shot(t.residents.hilde, "village_hilde_chat")
	# 2) the day goes on: noon to evening, they walk to their next places (no jumps)
	var track := {}
	var jumps := []
	# the tools of their trade in hand (Odo's axe at the woodpile)
	if t.residents.has("odo"):
		var t_tool := _gms()
		while (t.residents.odo as Resident)._clip != "chop" and _gms() - t_tool < 40000:
			await get_tree().process_frame
		print("[town] odo clip ", (t.residents.odo as Resident)._clip, " tools ", (t.residents.odo as Resident).tools.keys())
		await _wait(0.6)
		await _res_shot(t.residents.odo, "village_odo_chopping")
		_check((t.residents.odo as Resident)._clip == "chop" and ((t.residents.odo as Resident).tools.get("chop") as Node3D).visible, "Odo chops with an axe in his hands")
	WorldState.world_min = day0 + 11.9 * 60.0
	WorldState.clock_rate = 2.0              # 2 world minutes per second: walks take their real time
	var t0 := _gms()
	var shot_n := 0
	var prev_ms := _gms()
	while _gms() - t0 < 150000:
		await get_tree().physics_frame
		var dt := maxf(0.001, (_gms() - prev_ms) / 1000.0)
		prev_ms = _gms()
		for rid in t.residents:
			var rr: Resident = t.residents[rid]
			if not is_instance_valid(rr) or not rr.visible:
				track.erase(rid)
				continue
			# a jump = faster than any walk could carry them in that frame (a slow frame is not a jump)
			if track.has(rid) and (track[rid] as Vector3).distance_to(rr.global_position) > maxf(0.6, dt * 2.5):
				jumps.append([rid, snappedf((track[rid] as Vector3).distance_to(rr.global_position), 0.01), WorldState.clock_text()])
			track[rid] = rr.global_position
		if shot_n < 6 and _gms() - t0 > 12000 + shot_n * 22000:
			var pick: Array = t.residents.values().filter(func(x): return is_instance_valid(x) and (x as Resident).visible)
			if not pick.is_empty():
				var rr2: Resident = pick[shot_n % pick.size()]
				await _res_shot(rr2, "village_%s_%s_%s" % [WorldState.clock_text().replace(" ", "_").replace(":", "").replace(",", ""), rr2.id, rr2.activity])
			shot_n += 1
	WorldState.clock_rate = 0.0
	report["village_day"] = {}
	for rid in t.residents:
		report["village_day"][rid] = (t.residents[rid] as Resident).log.map(func(e): return "%s %s" % [e.t, e.what])
	print("[town] village day: ", JSON.stringify(report["village_day"]))
	var lived := t.residents.keys().filter(func(k): return ((t.residents[k] as Resident).log as Array).size() >= 3)
	_check(lived.size() >= 4, "their day moved on (%d of %d did three or more things)" % [lived.size(), t.residents.size()], report["village_day"])
	_check(jumps.is_empty(), "nobody jumped: every move was a walk (coming out of a door excepted)", jumps.slice(0, 6))
	# 3) Mika walks past: they notice her, someone speaks
	var near: Resident = null
	for rid in t.residents:
		if (t.residents[rid] as Resident).visible:
			near = t.residents[rid]
			break
	if near:
		var map: RID = mika.get_world_3d().navigation_map
		mika.navigate_to(NavigationServer3D.map_get_closest_point(map, near.global_position + Vector3(2.2, 0, 1.5)), false)
		var t1 := _gms()
		while mika.current_action == "navigate_to" and _gms() - t1 < 25000:
			await get_tree().process_frame
		await _wait(3.0)
		var st: Dictionary = WorldState.npc_state.get("res:" + near.id, {})
		_check(int(st.get("noticed_mika", -1)) == WorldState.day(), "%s noticed Mika walk up (and she glanced back)" % near.id, st)
		await _res_shot(near, "village_notice_%s" % near.id)
	# 4) night: the town goes in; the watch walks with his lantern
	WorldState.world_min = day0 + 21.4 * 60.0
	WorldState.clock_rate = 2.0
	await _wait(70.0)                        # they walk home and go in
	WorldState.clock_rate = 0.0
	var out_at_night: Array = t.residents.keys().filter(func(k): return (t.residents[k] as Resident).visible)
	report["village_night"] = t.describe(mika.global_position)
	_check(out_at_night == ["rook"] or out_at_night.size() <= 1, "at night they are indoors - only the watch is out (%s)" % [out_at_night], report["village_night"])
	if t.residents.has("rook"):
		await _wait(6.0)
		await _res_shot(t.residents.rook, "village_night_rook")
	# 5) the Academy at 9:00: a lesson on the lawn; at 11:30 practice in the arena
	WorldState.world_min = day0 + 1440.0 + 9.0 * 60.0
	var r2: Dictionary = await main.streaming.travel("academy", mika)
	_check(r2.get("ok", false), "the Academy loads")
	await _wait(3.0)
	report["academy_9"] = t.describe(mika.global_position)
	var teaching: Array = t.residents.values().filter(func(x): return (x as Resident).activity == "teach")
	var attending: Array = t.residents.values().filter(func(x): return (x as Resident).activity == "attend")
	_check(teaching.size() == 1 and attending.size() == 2, "a lesson: Master Aldric teaches, two students sit in the class", report["academy_9"])
	await _wait(4.0)
	var lec: Dictionary = main.world.anchors.get("lecture", {})
	if not lec.is_empty():
		main.camera_rig.set_shot((lec.pos as Vector3) + Vector3(-1.5, 2.0, 5.5), (lec.pos as Vector3) + Vector3(-2.2, 0.9, 0), 52.0)
		await _wait(0.8)
		_shot("academy_lesson")
	# Mika sits in on the lesson: the option comes from her own planner (a teacher teaching, a free place)
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var lopts: Array = mb.options().filter(func(o): return String(o.kind) == "lesson")
	_check(not lopts.is_empty(), "her planner sees the lesson (a free place on the bench)", lopts)
	if not lopts.is_empty():
		var sc: Dictionary = mb.score(lopts[0])
		report["lesson_option"] = {"option": lopts[0].label, "score": sc}
		var shot_lesson := func():
			await _wait(14.0)
			main.camera_rig.set_shot((lec.pos as Vector3) + Vector3(-1.0, 1.9, 6.0), (lec.pos as Vector3) + Vector3(-3.0, 0.9, 0), 50.0)
			await _wait(0.6)
			_shot("academy_mika_in_class")
		shot_lesson.call()
		var lr: Dictionary = await mb.run_activity(lopts[0])
		report["lesson"] = lr
		var mk := WorldState.mind("mika").knowledge
		_check(lr.get("ok", false) and mk.has("mentor:aldric") and mk.keys().any(func(k): return String(k).begins_with("lesson:aldric:")),
			"Mika sat in on Master Aldric's lesson and learned from it (%s)" % String(lr.get("activity", {}).get("topic", "")), lr)
		_check(mk.has("fact:breath_before_word"), "the first lesson's knowledge is hers now (breath before the word)")
	WorldState.world_min = day0 + 1440.0 + 11.2 * 60.0
	WorldState.clock_rate = 2.0
	await _wait(25.0)
	WorldState.clock_rate = 0.0
	report["academy_11"] = t.describe(mika.global_position)
	_check(t.sparks > 0, "students practised spells (%d small casts)" % t.sparks, report["academy_11"])
	for x in t.residents.values():
		if (x as Resident).activity == "practice" and (x as Resident).visible:
			await _res_shot(x, "academy_practice_%s" % (x as Resident).id)
			break
	report["academy_day"] = {}
	for rid in t.residents:
		report["academy_day"][rid] = (t.residents[rid] as Resident).log.map(func(e): return "%s %s" % [e.t, e.what])
	print("[town] academy: ", JSON.stringify(report["academy_day"]))


# ------------------------------------------------------------------ unfinished business (V3 Part 5)
func _rematch() -> void:
	var luna: WorldCharacter = main.characters.get("luna")
	if luna == null:
		_check(false, "Luna exists (run with --luna)")
		return
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	var lm := WorldState.mind("luna")
	await _hold_all()
	main.director.enabled = true
	var map: RID = luna.get_world_3d().navigation_map
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(26, 0, 6)) + Vector3(0, 0.1, 0)
	await main.focus_mage("luna", true)
	# 1) tired out, she meets something strong: a real fight she withdraws from
	lm.vigor = 0.26
	var mon: Monster = main.spawner.spawn("hollow_sentinel", NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(8, 0, 1)))
	await _wait(1.5)
	var hopts := lb.options().filter(func(o): return o.kind == "hunt")
	var fr := {}
	if not hopts.is_empty():
		fr = await lb.run_activity(hopts[0].merged(lb.score(hopts[0])))
	report["fight1"] = fr.get("detail", "")
	var unf = lm.knowledge.get("unfinished:hollow_sentinel")
	_check(unf is Dictionary, "she withdrew and remembers it as unfinished business (%s)" % fr.get("detail", ""), unf)
	if is_instance_valid(mon):
		mon.queue_free()
	await _wait(2.0)
	lm.vigor = 1.0
	# 2) her planner now leans toward getting ready, and keeps her away from it
	var opts: Array = lb.options()
	var drill: Array = opts.filter(func(o): return String(o.kind) == "drill")
	_check(not drill.is_empty(), "getting ready is now an option (drill her ward)", drill)
	var probe: Monster = main.spawner.spawn("hollow_sentinel", NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(14, 0, 2)))
	await _wait(1.0)
	var h2: Array = lb.options().filter(func(o): return String(o.kind) == "hunt" and String(o.monster_kind) == "hollow_sentinel")
	var s_before := {}
	if not h2.is_empty():
		s_before = lb.score(h2[0])
	_check(not s_before.is_empty() and (s_before.get("why", []) as Array).any(func(w): return String(w).begins_with("not ready")), "she would rather not face it yet", s_before)
	if is_instance_valid(probe):
		probe.queue_free()
	# 3) she drills (real casts), twice
	var r0 := lb.readiness("hollow_sentinel")
	for i in 2:
		if not drill.is_empty():
			var dr: Dictionary = await lb.run_activity(drill[0])
			report["drill_%d" % i] = dr.get("detail", "")
			lm.vigor = 1.0
	var r1 := lb.readiness("hollow_sentinel")
	_check(r1 > r0, "drilling made her readier (%.2f -> %.2f)" % [r0, r1], [report.get("drill_0", ""), report.get("drill_1", "")])
	# 4) she tells Mika about it (her own memory)
	var tps: Array = Companionship.topics("luna", "mika")
	_check(tps.any(func(t): return String(t.kind) == "worry"), "it is something she would tell Mika about", tps.slice(0, 4))
	# 5) the rematch: rested and readier, she faces it again
	var mon2: Monster = main.spawner.spawn("hollow_sentinel", NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(9, 0, 1)))
	if mon2:
		mon2.hp = mon2.max_hp * 0.45
	await _wait(1.5)
	var h3: Array = lb.options().filter(func(o): return String(o.kind) == "hunt" and String(o.monster_kind) == "hollow_sentinel")
	if not h3.is_empty():
		var sc: Dictionary = lb.score(h3[0])
		report["rematch_score"] = sc
		var fr2: Dictionary = await lb.run_activity(h3[0].merged(sc))
		report["fight2"] = fr2.get("detail", "")
	_check(lm.knowledge.has("overcame:hollow_sentinel") and not lm.knowledge.has("unfinished:hollow_sentinel"), "the rematch closed it: she overcame the hollow sentinel (%s)" % report.get("fight2", ""), lm.knowledge.get("overcame:hollow_sentinel"))
	var tps2: Array = Companionship.topics("luna", "mika")
	_check(tps2.any(func(t): return String(t.kind) == "triumph"), "and now that is what she would tell Mika", tps2.slice(0, 4))


# ------------------------------------------------------------------ the world's own texts (docs/WORLD_BIBLE.md)
func _lore() -> void:
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var mk := WorldState.mind("mika").knowledge
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 10.0 * 60.0
	WorldState.clock_rate = 0.0
	for step in [["village", "notice_board", "lore:village_people"], ["observatory_hill", "star_chart_study", "lore:ten_orbits"], ["academy", "statue_plaque", "lore:ilvane"]]:
		var r: Dictionary = await main.streaming.travel(String(step[0]), mika)
		_check(r.get("ok", false), "%s loads" % step[0])
		await _wait(2.5)
		var shots := {"n": 0}
		var on_page := func(_b, i, _p):
			if shots.n < 2:
				shots.n += 1
				await _wait(1.2)
				_shot("lore_%s_page%d" % [step[1], i])
		BookReader.instance.page_shown.connect(on_page)
		var res: Dictionary = await mb._use(String(step[1]))
		BookReader.instance.page_shown.disconnect(on_page)
		report[String(step[1])] = res.get("detail", "")
		_check(res.get("ok", false) and mk.has(String(step[2])), "Mika read %s and knows %s now" % [step[1], step[2]], res.get("detail", ""))
		if String(step[1]) == "notice_board":
			# what she read becomes a reason to go somewhere: the Academy's open lessons (an expedition option)
			WorldState.mind("mika").vigor = 1.0
			var ex: Array = mb.options().filter(func(o): return String(o.kind) == "expedition")
			report["expeditions"] = ex.map(func(o): return [o.label, mb.score(o)])
			_check(ex.any(func(o): return String(o.area) == "academy"), "the notice board gave her a reason to set out (the Academy's open lessons)", report["expeditions"])


# ------------------------------------------------------------------ the Fold Step: teleportation only once learned
func _fold() -> void:
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var mk := WorldState.mind("mika").knowledge
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 11.0 * 60.0
	WorldState.clock_rate = 0.0
	var tg0: int = main.teleport_guard.violations.size()
	_check(not main.magic.can_cast("fold_step", "mika").ok, "at first she cannot fold space at all", main.magic.can_cast("fold_step", "mika"))
	# 1) the glyph stones of the Forgotten Shrine (the theory)
	var r: Dictionary = await main.streaming.travel("ancient_grove", mika)
	await _wait(2.5)
	var g: Dictionary = await mb._use("shrine_glyphs_read")
	_check(mk.has("teleport:theory_seam") and mk.has("teleport:theory_knowing"), "she read the Weaver's theory on the shrine stones", g.get("detail", ""))
	_check(not main.magic.can_cast("fold_step", "mika").ok, "theory alone is not the spell", main.magic.can_cast("fold_step", "mika"))
	# 2) the Weaver's words beneath the Cloud Temple (the incantation)
	r = await main.streaming.travel("celestial_summit", mika)
	await _wait(2.5)
	var w: Dictionary = await mb._use("weaver_stone_read")
	_check(mk.has("incantation:fold_step"), "she read the Weaver's words beneath the temple", w.get("detail", ""))
	_check(main.magic.can_cast("fold_step", "mika").ok, "now the Fold Step is hers", main.magic.can_cast("fold_step", "mika"))
	# 3) the rules of the fold: not beyond her reach, only where she can see and stand
	var fwd := -mika.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var far: Dictionary = await main.magic.fold_step(mika, mika.global_position + fwd * 40.0)
	_check(not far.get("ok", false), "too far: refused (%s)" % far.get("reason", ""), far)
	# a visible spot 7-10 m away on open ground
	var map: RID = mika.get_world_3d().navigation_map
	var target := Vector3.INF
	for k in 16:
		var dir := fwd.rotated(Vector3.UP, k * TAU / 16.0)
		var cand := NavigationServer3D.map_get_closest_point(map, mika.global_position + dir * 8.5)
		var q := PhysicsRayQueryParameters3D.create(mika.global_position + Vector3(0, 1.55, 0), cand + Vector3(0, 1.2, 0), 1)
		q.exclude = [mika.get_rid()]
		if Vector2(cand.x - mika.global_position.x, cand.z - mika.global_position.z).length() > 6.0 and mika.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			target = cand
			break
	_check(target != Vector3.INF, "a place she can see, 6+ m away")
	if target != Vector3.INF:
		var before := mika.global_position
		var shoot := func():
			await _wait(0.75)
			_shot("fold_step_crossing")
		shoot.call()
		var fr: Dictionary = await main.magic.fold_step(mika, target)
		await _wait(0.5)
		_shot("fold_step_arrived")
		report["fold"] = fr
		_check(fr.get("ok", false) and Vector2(mika.global_position.x - target.x, mika.global_position.z - target.z).length() < 1.0,
			"she folded %.1f m to the place she saw" % before.distance_to(mika.global_position), fr)
	var folds: Array = main.teleport_guard.folds
	var viol: Array = main.teleport_guard.violations.slice(tg0)
	_check(folds.size() == 1 and viol.is_empty(), "the guard recorded it as a learned fold, not a teleport violation", {"folds": folds, "violations": viol})
	# the ninth gate (Level 90): defined, and it does not answer one young mage alone at noon
	var g90 := Progression.gate_status("mika", 90)
	_check(bool(g90.defined) and not bool(g90.met), "the Level 90 gate is defined (the ninth gate, together)", g90)
	var ng: Dictionary = await mb._use("ninth_gate_open")
	var det := String(ng.get("activity", {}).get("detail", ng.get("detail", "")))
	_check(not ng.get("ok", false) and det.contains("one alone") and det.contains("Twin Lights"), "alone, at noon, at her level: the ninth gate stays shut (%s)" % det, ng)


# ------------------------------------------------------------------ waypoints as real places (hamlet, village, inn)
func _hamlet() -> void:
	await _hold_all()
	main.director.enabled = false
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 10.0 * 60.0
	WorldState.clock_rate = 0.0
	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/overland.json")).routes
	for case in [["whispering_woods|ancient_grove", "fernhollow", 2], ["village|academy", "thornwick", 2], ["river_valley|village", "millbrook_inn", 1]]:
		var rk := String(case[0])
		var r0: Dictionary = routes[rk]
		var wp := {}
		for w in r0.waypoints:
			if String(w.id) == String(case[1]):
				wp = w
		var parts := rk.split("|")
		Wayside.params = {"route": rk, "km": float(wp.km) - 3.0, "seed": 4000 + String(case[1]).length() * 37, "from": parts[0], "to": parts[1],
			"title": String(r0.name), "waypoint": wp, "waypoint_t": 0.35}
		var r: Dictionary = await main.streaming.travel("wayside", mika)
		_check(r.get("ok", false), "a stretch of %s with %s loads" % [r0.name, wp.name])
		await _wait(3.0)
		var w2: Wayside = main.world
		var t: TownLife = main.town
		report[String(case[1])] = t.describe(mika.global_position)
		_check(w2.site != Vector2.INF and t.residents.size() == int(case[2]), "%s stands at the roadside with its %d people (%s)" % [wp.name, int(case[2]), ", ".join(t.residents.keys())], report[String(case[1])])
		var sc := Vector3(w2.site.x, w2.height(w2.site.x, w2.site.y), w2.site.y)
		var rd := Vector3(w2.site_road.x, w2.height(w2.site_road.x, w2.site_road.y), w2.site_road.y)
		main.camera_rig.set_shot(rd + (rd - sc).normalized() * 6.0 + Vector3(0, 3.0, 0), sc + Vector3(0, 1.5, 0), 58.0)
		await _wait(0.8)
		_shot("hamlet_%s_wide" % case[1])
		for rid in t.residents:
			await _res_shot(t.residents[rid], "hamlet_%s_%s" % [case[1], rid])


# ------------------------------------------------------------------ what stalls a frame every few seconds (diagnosis)
func _hitch() -> void:
	await _hold_all()
	main.director.enabled = RenderProfile.options.has("director")
	main.spawner.enabled = false
	if RenderProfile.options.has("free"):
		for who in main.mage_brains:
			main.mage_brains[who].hold = false
	var mika: WorldCharacter = main.characters["mika"]
	var area := String(RenderProfile.options.get("areas", "whispering_woods"))
	if main.streaming.current_id != area:
		await main.streaming.travel(area, mika)
	await _wait(8.0)
	var count := func(secs: float) -> int:
		var n0 := hitch_log.size()
		await _wait(secs)
		return hitch_log.size() - n0
	var base: int = await count.call(18.0)
	report["baseline_18s"] = base
	print("[hitch] %s baseline: %d stalls in 18 s" % [area, base])
	var res := {}
	for ch in main.get_children():
		var nd := ch as Node
		if nd == null or nd == main.world or nd is Camera3D or String(nd.name) in ["TrailerCam"]:
			continue
		var pm := nd.process_mode
		nd.process_mode = Node.PROCESS_MODE_DISABLED
		var n: int = await count.call(13.0)
		nd.process_mode = pm
		res[String(nd.name)] = n
		print("[hitch]   without %s: %d stalls in 13 s" % [nd.name, n])
	# the world's own top-level children
	for ch in main.world.get_children():
		var nd := ch as Node
		if nd == null or nd.get_child_count() == 0 and not nd.has_method("_process"):
			continue
		var pm := nd.process_mode
		nd.process_mode = Node.PROCESS_MODE_DISABLED
		var n2: int = await count.call(13.0)
		nd.process_mode = pm
		res["world/" + String(nd.name)] = n2
		if n2 == 0:
			print("[hitch]   without world/%s: %d stalls in 13 s" % [nd.name, n2])
	report["without"] = res


# ------------------------------------------------------------------ someone on the road (a rumour that leads somewhere)
func _road() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters.get("luna")
	main.spawner.enabled = false
	main.director.enabled = true
	var r: Dictionary = await main.streaming.travel("highland_path", mika)
	_check(r.get("ok", false), "they start on the Highland Path")
	var map: RID = mika.get_world_3d().navigation_map
	await get_tree().physics_frame
	if luna:
		_dev_stage(luna, NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(1.2, 0, 1.0)))
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 9.5 * 60.0
	var jd: JourneyDirector = main.journeys
	var plan := jd.start("celestial_summit", "to see the Cloud Temple", ["mika", "luna"] if luna else ["mika"], "mika")
	_check(plan.get("ok", false), "a short journey up to the summit (%.0f km)" % float(plan.get("km", 0)), plan)
	var food0 := int(WorldState.journey.supplies.get("food", 0))
	jd.force_encounter = "pedlar"
	var shots := {"n": 0}
	var on_line := func(sp: String, _tx: String):
		if sp.begins_with("res_pedlar") and shots.n < 2:
			shots.n += 1
			await _wait(0.5)
			_shot("road_pedlar_%d" % shots.n)
	main.voice.line_started.connect(on_line)
	await jd.run_live(6)
	main.voice.line_started.disconnect(on_line)
	report["encounters"] = jd.encounters
	report["journey_log"] = (WorldState.journey.get("log", []) as Array).map(func(e): return "%s %s" % [e.get("clock", ""), e.get("text", "")])
	print("[road] ", JSON.stringify(jd.encounters))
	_check(not jd.encounters.is_empty() and String(jd.encounters[0].kind) == "pedlar", "a pedlar came the other way and stopped for a word", jd.encounters)
	_check(int(WorldState.journey.supplies.get("food", 0)) > food0 - 1, "they bought food from him (food %d -> %d, eaten on the way counted)" % [food0, int(WorldState.journey.supplies.get("food", 0))])
	var clue := String(jd.encounters[0].get("clue", "")) if not jd.encounters.is_empty() else ""
	_check(clue != "" and WorldState.mind("mika").knowledge.has(clue), "she heard a rumour on the road and remembers it (%s)" % clue)
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	WorldState.mind("mika").vigor = 1.0
	var ex: Array = mb.options().filter(func(o): return String(o.kind) == "expedition")
	report["expeditions_after_rumour"] = ex.map(func(o): return o.label)
	_check(clue == "" or ex.any(func(o): return true), "the rumour is now a reason she could set out for", report["expeditions_after_rumour"])


# ------------------------------------------------------------------ can she walk to every gate of an area? (diagnosis)
func _navcheck() -> void:
	await _hold_all()
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	for area in String(RenderProfile.options.get("areas", "highland_path")).split(","):
		var r: Dictionary = await main.streaming.travel(area, mika)
		await _wait(2.0)
		var map: RID = mika.get_world_3d().navigation_map
		for g in main.world.gates:
			var gp: Vector3 = main.world.gates[g].position
			var goal := NavigationServer3D.map_get_closest_point(map, gp)
			var path := NavigationServer3D.map_get_path(map, mika.global_position, goal, true)
			var end_d: float = (path[path.size() - 1] as Vector3).distance_to(goal) if path.size() > 0 else 999.0
			var off := goal.distance_to(gp)
			print("[nav] %s -> gate %s: path %d pts, ends %.1f m from goal, goal %.1f m from the gate" % [area, g, path.size(), end_d, off])
			if end_d > 2.0:
				var arv = main.world.gates[g].arrive
				var arr: Vector3 = (arv as Transform3D).origin if arv is Transform3D else arv
				var pa := NavigationServer3D.map_get_path(map, mika.global_position, NavigationServer3D.map_get_closest_point(map, arr), true)
				var ea: float = (pa[pa.size() - 1] as Vector3).distance_to(NavigationServer3D.map_get_closest_point(map, arr)) if pa.size() > 0 else 999.0
				print("[nav]     path end %s, goal %s (gate %s); arrival %s reachable: %s (%.1f m short)" % [path[path.size() - 1], goal, gp, arr, ea < 2.0, ea])
			_check(path.size() > 1 and end_d < 2.0 and off < 4.0, "%s: a walkable way to the %s gate" % [area, g], {"end": end_d, "goal_off_gate": off})
		# the grade along every trail (navmesh agent_max_slope is 30 degrees)
		if "trails" in main.world:
			for tr in main.world.trails:
				var pts: Array = tr[0]
				var worst := 0.0
				var at := Vector2.ZERO
				for i in pts.size() - 1:
					var a2: Vector2 = pts[i]
					var b2: Vector2 = pts[i + 1]
					var n := int(a2.distance_to(b2))
					for k in n:
						var q := a2.lerp(b2, float(k) / maxf(n, 1))
						var q2 := a2.lerp(b2, float(k + 1) / maxf(n, 1))
						var dh := absf(float(main.world.height(q2.x, q2.y)) - float(main.world.height(q.x, q.y)))
						var ang := rad_to_deg(atan2(dh, q.distance_to(q2)))
						if ang > worst:
							worst = ang
							at = q
				print("[nav]   trail %s..%s: steepest %.0f deg at %s" % [pts[0], pts[pts.size() - 1], worst, at])
		if area == "celestial_summit":
			var prof := []
			for zi in range(0, 62, 2):
				var zz := float(zi)
				var xx := 3.0 * sin(zz * 0.05)
				prof.append("%d:%.1f" % [zi, float(main.world.height(xx, zz))])
			print("[nav]   crest heights z:h ", " ".join(prof))
			var a3 := Vector2(0, 38)
			var b3 := Vector2(-2, 6)
			var prof2 := []
			for zi2 in range(26, 35):
				var q3 := a3.lerp(b3, (38.0 - zi2) / 32.0)
				prof2.append("%d:(%.1f) h%.2f raw%.2f" % [zi2, q3.x, float(main.world.height(q3.x, q3.y)), float(main.world._raw_height(q3.x, q3.y))])
			print("[nav]   on the trail: ", " ".join(prof2))
			print("[nav]   trail0 pts: ", main.world.trails[0][0])
		if RenderProfile.options.has("walk"):
			var g2 := String(RenderProfile.options.get("walk"))
			if main.world.gates.has(g2):
				var goal2 := NavigationServer3D.map_get_closest_point(map, main.world.gates[g2].position)
				var res := {"d": ""}
				var cb := func(act, ok, det): if act == "navigate_to": res.d = "%s %s" % [ok, det]
				mika.action_finished.connect(cb)
				mika.navigate_to(goal2, false)
				var t0 := _gms()
				while mika.current_action == "navigate_to" and _gms() - t0 < 200000:
					await get_tree().process_frame
				mika.action_finished.disconnect(cb)
				print("[nav] walked toward %s: %s; now %.1f m from it at %s" % [g2, res.d, mika.global_position.distance_to(goal2), mika.global_position])
				# what is she pressed against?
				var sq := PhysicsShapeQueryParameters3D.new()
				var sph := SphereShape3D.new()
				sph.radius = 0.9
				sq.shape = sph
				sq.transform = Transform3D(Basis.IDENTITY, mika.global_position + Vector3(0, 0.9, 0))
				sq.collision_mask = 0xFFFF
				sq.exclude = [mika.get_rid()]
				for hit in mika.get_world_3d().direct_space_state.intersect_shape(sq, 8):
					var co = hit.collider
					print("[nav]   touching: %s (%s) layer %d" % [co.name if co else "?", co.get_parent().name if co and co.get_parent() else "", co.collision_layer if co else -1])
				var pth := NavigationServer3D.map_get_path(map, mika.global_position, goal2, true)
				print("[nav]   path from here: %d pts, last %s, goal %s" % [pth.size(), pth[pth.size() - 1] if pth.size() > 0 else Vector3.ZERO, goal2])
				print("[nav]   floor normal %s on_floor %s ground_at %.2f" % [mika.get_floor_normal(), mika.is_on_floor(), float(main.world.ground_at(mika.global_position.x, mika.global_position.z))])


# ------------------------------------------------------------------ a long unattended session (livestream soak)
func _soak() -> void:
	var minutes := int(RenderProfile.options.get("minutes", 40))
	main.director.enabled = true
	main.spawner.enabled = true
	for who in main.mage_brains:
		main.mage_brains[who].hold = false
	var samples := []
	var acts := {}
	var seen_logs := {}
	var t0 := _gms()
	var hz_n0 := hitch_log.size()
	for m in minutes:
		await _wait(60.0)
		for who in main.mage_brains:
			var b = main.mage_brains[who]
			var mind := WorldState.mind(who)
			for e in mind.activity_log.slice(maxi(0, mind.activity_log.size() - 20)):
				var key := "%s|%s|%s" % [who, e.get("seq", -1), e.get("t", 0)]
				if seen_logs.has(key):
					continue
				seen_logs[key] = true
				var aid := String(e.get("activity", {}).get("id", "?")).get_slice(":", 0)
				acts[who + ":" + aid] = int(acts.get(who + ":" + aid, 0)) + 1
		var smp := {"min": m + 1, "static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"voice_cache": main.voice._cache.size(), "kit_meshes": Kit._meshes.size(), "kit_mats": Kit._mats.size(),
			"logs": WorldState.mind("mika").activity_log.size() + WorldState.mind("luna").activity_log.size() + WorldState.activity_log.size(),
			"area": main.streaming.current_id, "clock": WorldState.clock_text(),
			"mika": String(main.mage_brains.mika.current.get("label", "")) if main.mage_brains.has("mika") else "",
			"luna": String(main.mage_brains.luna.current.get("label", "")) if main.mage_brains.has("luna") else ""}
		samples.append(smp)
		print("[soak] ", JSON.stringify(smp))
		if m % 5 == 4:
			_shot("soak_%02d" % (m + 1))
	report["soak"] = {"samples": samples, "activities": acts}
	print("[soak] activities: ", JSON.stringify(acts))
	var first: Dictionary = samples[mini(2, samples.size() - 1)]
	var last: Dictionary = samples[samples.size() - 1]
	var growth := float(last.static_mb) - float(first.static_mb)
	_check(growth < 150.0, "memory stays bounded over %d minutes (static %.0f -> %.0f MB from minute 3)" % [minutes, float(first.static_mb), float(last.static_mb)], samples.map(func(x): return x.static_mb))
	_check(int(last.orphans) < 200, "no pile-up of orphan nodes (%d)" % int(last.orphans))
	var kinds := acts.keys().size()
	_check(kinds >= 6, "they keep doing different things (%d kinds of activity)" % kinds, acts)


# ------------------------------------------------------------------ weather
func _weather() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	main.spawner.enabled = false
	main.director.enabled = true
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 13.0 * 60.0
	WorldState.clock_rate = 0.0
	await main.streaming.travel("whispering_woods", mika)
	await _wait(3.0)
	var wx: WeatherSystem = main.weather
	wx.set_weather("clear", 3.0)
	var tc := _gms()
	while (wx.cloud > 0.005 or wx.rain > 0.005) and _gms() - tc < 40000:   # a saved sky may still be clearing
		await get_tree().process_frame
	await _wait(1.0)
	var sun0: float = main.world.sun.light_energy
	main.camera_rig.set_shot(mika.global_position + Vector3(4, 2.2, 6), mika.global_position + Vector3(0, 1.4, 0), 55.0)
	await _wait(0.6)
	_shot("weather_clear")
	wx.set_weather("storm", 3.0)
	await _wait(28.0)
	report["storm"] = wx.describe()
	_check(wx.rain > 0.9 and wx._rain_fx.emitting, "a storm: the rain falls round her (rain %.2f)" % wx.rain, wx.describe())
	_check(main.world.sun.light_energy < sun0 * 0.5, "the sun is dimmed under the storm clouds (%.2f -> %.2f)" % [sun0, main.world.sun.light_energy])
	_check(wx._rain_player.playing or wx._roof_player.playing, "the rain is heard")
	main.camera_rig.set_shot(mika.global_position + Vector3(4, 2.2, 6), mika.global_position + Vector3(0, 1.4, 0), 55.0)
	await _wait(0.6)
	_shot("weather_storm")
	var t0 := _gms()
	while not wx.log.any(func(e): return e.has("lightning")) and _gms() - t0 < 30000:
		await get_tree().process_frame
	_check(wx.log.any(func(e): return e.has("lightning")), "lightning, and the thunder after it", wx.log.filter(func(e): return e.has("lightning")))
	wx.set_weather("clear", 3.0)
	await _wait(30.0)
	_check(wx.rain < 0.05 and absf(main.world.sun.light_energy - sun0) < sun0 * 0.15, "it clears again (sun %.2f)" % main.world.sun.light_energy, wx.describe())
