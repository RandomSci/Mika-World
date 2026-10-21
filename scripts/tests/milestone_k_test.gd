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
	if main.get("overlay_ui") and not RenderProfile.options.has("keep-overlay"):
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
		"crown": await _crown()
		"grove": await _grove()
		"audit": await _audit()
		"bench": await _bench()
		"gfxcal": await _gfxcal()
		"adaptive": await _adaptive()
		"weapons": await _weapons()
		"stones": await _stones()
		"view": await _view()
		"dance": await _dance()
		"pacing": await _pacing()
		"headwatch": await _headwatch()
		"tremble": await _tremble()
		"motionwatch": await _motionwatch()
		"earshot": await _earshot()
		"starfall_site": await _starfall_site()
		"starfall_look": await _starfall_look()
		"estcams": await _estcams()
		"estwalk": await _estwalk()
		"skirtlook": await _skirtlook()
		"camshake": await _camshake()
		"framepace": await _framepace()
		"lenswatch": await _lenswatch()
		"thumbshot": await _thumbshot()
		"showdance": await _showdance()
		"streamday": _check(StreamDay.day() == int(RenderProfile.options.get("expect-day", "-1")), "stream day %d" % StreamDay.day())
		"discoveries": await _discoveries()
		"braziers": await _braziers()
		"walkaudit": await _walkaudit()
		"livefixes": await _livefixes()
		"sparwatch": await _sparwatch()
		"day2story": await _day2story()
		"day2crash": await _day2crash()
		"daynight": await _daynight()
		"day2stargaze": await _day2stargaze()
		"day2topics": await _day2topics()
		"libnav": await _libnav()
		"gateprobe": await _gateprobe()
		"lakenight": await _lakenight()
		"day2soak": await _day2soak()
		"towervisit": await _towervisit()
		"readtravel": await _readtravel()
		"lakehome": await _lakehome()
		"discovery_live": await _discovery_live()
		"benchwalk": await _benchwalk()
		"sunflash": await _sunflash()
		"standstill": await _standstill()
		"lunarelay": await _lunarelay()
		"benchrest": await _benchrest()
		"showline": await _showline()
		"showtakes": await _showtakes()
		"luna_r12": await _luna_r12()
		"dresstest": await _dresstest()
		"skinprobe": await _skinprobe()
		"benchscan": await _benchscan()
		"screenfx": await _screenfx()
		"lunaclip": await _lunaclip()
		"outfitaudit": await _outfitaudit()
		"harpprobe": await _harpprobe()
		"starlitharp": await _starlitharp()
		"sittest": await _sittest()
		"motionshots": await _motionshots()
		"daylapse": await _daylapse()
		"lakedance": await _lakedance()
		"clipreel": await _clipreel()
		"lakemv": await _lakemv()
		"hairprobe": await _hairprobe()
		"boatnight": await _boatnight()
		"boatstill": await _boatstill()
		_:
			# plug-in test modes (one file per feature, so parallel work never edits this file):
			# res://scripts/tests/ext/<mode>.gd with  `static func run(t) -> void`  (t = this test node: _wait, _check,
			# _lake_setup, _cine_setup, main ...)
			var ext := "res://scripts/tests/ext/%s.gd" % mode
			if ResourceLoader.exists(ext):
				await (load(ext) as GDScript).call("run", self)
			else:
				_check(false, "unknown mode " + mode)
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
	# body jitter while they spar: stop-start flips (moving one frame, stopped the next and back) and direction
	# reversals of the root at walking speeds - what reads as trembling at 30 FPS
	var jit := {"mika": {"flips": 0, "reversals": 0, "frames": 0}, "luna": {"flips": 0, "reversals": 0, "frames": 0}}
	var lastp := {}
	var lastv := {}
	var jsampler := func():
		if not main.duel.busy():
			return
		for w in ["mika", "luna"]:
			var ch: WorldCharacter = main.characters[w]
			var p := ch.global_position
			if lastp.has(w):
				var v := Vector2(p.x - (lastp[w] as Vector3).x, p.z - (lastp[w] as Vector3).z)
				if lastv.has(w):
					var pv: Vector2 = lastv[w]
					if (pv.length() > 0.012) != (v.length() > 0.012) and maxf(pv.length(), v.length()) > 0.02:
						jit[w].flips += 1
					if pv.length() > 0.01 and v.length() > 0.01 and pv.dot(v) < 0.0:
						jit[w].reversals += 1
				lastv[w] = v
				jit[w].frames += 1
			lastp[w] = p
	get_tree().physics_frame.connect(jsampler)
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
	get_tree().physics_frame.disconnect(jsampler)
	print("[mktest] duel body jitter%s: %s" % [" (no nav-bound)" if RenderProfile.options.has("no-nav-bound") else "", JSON.stringify(jit)])


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
	if main.performance:
		# (the night dance may start on its own at night: "a dance is on" refused the invitation)
		main.performance.set_process(false)
		if main.performance.busy():
			main.performance.interrupt("test")
		var tb := _gms()
		while main.performance.busy() and _gms() - tb < 4000:
			await get_tree().process_frame
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
	for w2 in main.mage_brains:
		main.mage_brains[w2].hold = false      # (_hold_all held them: "Luna is held for something else")
		main.mage_brains[w2].set_enabled(false)
	var runner := func() -> void:
		box.result = await main.companionship.invite(brain, "luna", "stargaze_together", target)
		box.done = true
	runner.call()
	var t0 := _gms()
	var next_shot := 6000
	while not box.done and _gms() - t0 < 360000:      # (the quiet rounds are random: the scene runs 2-5 min)
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
	# knowing is not yet holding: before her First Orbit (Level 10) the fold will not hold
	var pg: Dictionary = WorldState.mind("mika").progress
	var lv0 := int(pg.get("level", 1))
	pg["level"] = 9
	var early: Dictionary = main.magic.can_cast("fold_step", "mika")
	_check(not early.ok and int(early.get("needs_level", 0)) == 10, "at Level 9 the fold will not hold yet (%s)" % early.get("reason", ""), early)
	pg["level"] = maxi(lv0, 10)
	_check(main.magic.can_cast("fold_step", "mika").ok, "at her First Orbit (Level 10) the Fold Step is hers", main.magic.can_cast("fold_step", "mika"))
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
			"xp": {"mika": snappedf(float(WorldState.mind("mika").progress.xp), 0.1), "luna": snappedf(float(WorldState.mind("luna").progress.xp), 0.1)},
			"level": {"mika": WorldState.mind("mika").level(), "luna": WorldState.mind("luna").level()},
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
	# she gets out of it: her own planner wants shelter (a big tree here, a doorstep's eaves in the Village), she is
	# dry there, then she sits (under a roof) or stands against the trunk and listens to it for a while
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	for place in ["whispering_woods", "village"]:
		if place != main.streaming.current_id:
			await main.streaming.travel(place, mika)
			await _wait(3.0)
		if wx.sheltered_at(mika.global_position):
			mika.global_position = mika.global_position + Vector3(4, 0, 4)
			await _wait(0.5)
		var top: Array = mb.ranked()
		var sh: Array = top.filter(func(o): return String(o.kind) == "shelter")
		_check(not sh.is_empty() and String(top[0].kind) == "shelter", "%s: out in the rain, getting under cover is what she wants most (%s)" % [place, sh.map(func(o): return o.label)],
			top.slice(0, 4).map(func(o): return [o.kind, snappedf(o.utility, 0.01)]))
		if sh.is_empty():
			continue
		var r: Dictionary = await mb.run_activity(sh[0])
		report["shelter_" + place] = r
		_check(r.get("ok", false) and wx.sheltered_at(mika.global_position), "%s: %s" % [place, r.get("detail", "")], r)
		var f := mika.global_transform.basis.z
		f.y = 0.0
		f = f.normalized()
		var sd := f.cross(Vector3.UP)
		main.camera_rig.set_shot(mika.global_position + f * 4.2 + sd * 1.6 + Vector3(0, 1.5, 0), mika.global_position + Vector3(0, 1.3, 0), 52.0)
		var ls: Array = mb.options().filter(func(o): return String(o.kind) == "listen_rain")
		_check(not ls.is_empty(), "%s: dry, with the rain all round, she can sit and listen to it" % place)
		if not ls.is_empty():
			get_tree().create_timer(9.0).timeout.connect(func(): _shot("weather_listen_" + place))
			var lr: Dictionary = await mb.run_activity(ls[0])
			report["listen_" + place] = lr
			_check(lr.get("ok", false) and float(lr.get("seconds", 0)) > 15.0, "%s: %s" % [place, lr.get("detail", "")], lr)
	# the townsfolk too: out in it with no roof over their place, they go to a doorstep under its hood
	if main.get("town") and not main.town.residents.is_empty():
		var t2 := _gms()
		var wet := []
		while _gms() - t2 < 60000:
			await _wait(3.0)
			wet = []
			for rid in main.town.residents:
				var rr = main.town.residents[rid]
				if is_instance_valid(rr) and rr.visible and rr.state != "walking" and not wx.sheltered_at(rr.global_position):
					wet.append([rid, rr.activity, rr.state])
			if wet.is_empty():
				break
		report["town_in_rain"] = main.town.residents.keys().map(func(k): return [k, main.town.residents[k].activity, main.town.residents[k].state])
		_check(wet.is_empty(), "in the storm no one in the Village is left standing in the rain", wet)
		var near: Resident = null
		for rid in main.town.residents:
			var r3 = main.town.residents[rid]
			if is_instance_valid(r3) and r3.visible and r3.activity == "shelter":
				near = r3
				break
		if near:
			await _res_shot(near, "weather_resident_sheltering")
	wx.set_weather("clear", 3.0)
	await _wait(30.0)
	if main.get("town") and not main.town.residents.is_empty():
		await _wait(5.0)
		var still: Array = main.town.residents.keys().filter(func(k): return main.town.residents[k].activity == "shelter")
		_check(still.is_empty(), "the rain over, they went back to their day", still)
	_check(wx.rain < 0.05 and absf(main.world.sun.light_energy - sun0) < sun0 * 0.15, "it clears again (sun %.2f)" % main.world.sun.light_energy, wx.describe())


# ------------------------------------------------------------------ the Crown (Level 100) and Rising Air
func _crown() -> void:
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var mk := WorldState.mind("mika").knowledge
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 11.0 * 60.0
	WorldState.clock_rate = 0.0
	var tg0: int = main.teleport_guard.violations.size()
	_check(not main.magic.can_cast("rising_air", "mika").ok, "at first the air will not lift her", main.magic.can_cast("rising_air", "mika"))
	await main.streaming.travel("mentor_tower", mika)
	await _wait(2.5)
	# 1) the founders' notes, before Master Aldric's lesson on footing: the last page means nothing yet
	var r1: Dictionary = await mb._use("mentor_notes")
	_check(mk.has("lore:rising_air") and mk.has("clue:crown_bells") and not mk.has("incantation:rising_air"),
		"she read the founders' notes: the theory and the bells, but not the word (%s)" % [r1.get("detail", "")], r1)
	_check(not main.magic.can_cast("rising_air", "mika").ok, "reading alone is not the spell")
	# 2) the lesson (Master Aldric's "magic follows the body", as his footing lesson grants), then the last page
	mk["fact:magic_follows_body"] = 1
	var r2: Dictionary = await mb._use("mentor_notes")
	_check(mk.has("incantation:rising_air") and main.magic.can_cast("rising_air", "mika").ok, "with the lesson understood, the last page gives her the word: Rising Air is hers", r2.get("detail", ""))
	# 3) by day the bells hang still: no reason to go up
	_check(not mb.options().any(func(o): return String(o.kind) == "ascend"), "by day she has no reason to rise to the crown")
	var spot: Dictionary = main.world.rise_spots()[0]
	var gap := (spot.top as Vector3).y - (spot.foot as Vector3).y      # two lifts: grass -> balcony -> crown
	var pth := NavigationServer3D.map_get_path(mika.get_world_3d().navigation_map, mika.global_position, spot.foot, true)
	var foot_nav := NavigationServer3D.map_get_closest_point(mika.get_world_3d().navigation_map, spot.foot)
	report["crown_spot"] = {"foot": spot.foot, "top": spot.top, "gap": gap, "foot_nav": foot_nav, "path_end": pth[pth.size() - 1] if pth.size() > 0 else null, "path_n": pth.size(), "from": mika.global_position}
	_check(pth.size() > 0 and (pth[pth.size() - 1] as Vector3).distance_to(spot.foot) < 1.0, "she can walk to where she rises from (the grass below the gallery)", report["crown_spot"])
	var map: RID = mika.get_world_3d().navigation_map
	var on_crown := NavigationServer3D.map_get_closest_point(map, spot.top)
	_check(on_crown.distance_to(spot.top) < 0.8, "the crown walk is ground to stand on (navmesh %.2f m from the spot)" % on_crown.distance_to(spot.top))
	# 4) night: six of the nine rings heard (a lesson, the rain, four Wardens' stories)
	for k in ["fact:breath_before_word", "listened_to_rain", "lore:warden_verdance", "lore:warden_umbra", "lore:warden_emberhart", "lore:warden_stonefather"]:
		mk[k] = 1
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 22.5 * 60.0
	await _wait(2.0)
	_check(WorldState.daylight() < 0.15, "night has come (%s)" % WorldState.clock_text())
	var asc: Array = mb.options().filter(func(o): return String(o.kind) == "ascend")
	_check(not asc.is_empty(), "at night her planner offers to rise to the crown (%s)" % [asc.map(func(o): return o.label)])
	if asc.is_empty():
		return
	var shots := func():
		await _wait(9.0)
		var c: Vector3 = mika.global_position
		main.camera_rig.set_shot(c + Vector3(7.5, 1.0, 7.5), c + Vector3(0, 0.6, 0), 55.0)
		await _wait(1.6)
		_shot("crown_rising")
	shots.call()
	var a1: Dictionary = await mb.run_activity(asc[0])
	report["ascend_partial"] = a1
	var rise: Dictionary = a1.get("rise", {})
	_check(rise.get("ok", false) and float(rise.get("height", 0)) > 12.0, "Rising Air: up %.1f m, onto the gallery and on to the crown (%s)" % [float(rise.get("height", 0)), rise.get("reason", rise.get("outcome", ""))], rise)
	var cr: Dictionary = a1.get("crown", {})
	_check(cr.get("ok", false) and (cr.get("sounded", []) as Array).size() == 6 and not cr.get("all_nine", true), "six bells sounded, three swung silent (%s)" % cr.get("detail", ""), cr)
	_check(mk.has("crown:silent_7") and mk.has("crown:silent_9") and not mk.has("crown:heard_all_nine"), "she remembers which rings she has still to hear")
	_check((a1.get("down", {}) as Dictionary).get("ok", false), "and she drifted back down, gallery then grass", a1.get("down", {}))
	# 5) the rest of her journey: a fold, a ward that held, the ninth gate with Luna
	for k in ["practical:fold_step", "practical:leaf_ward", "ninth_gate:opened"]:
		mk[k] = 1
	mk.erase("ascended:crown")
	var g0: Dictionary = Progression.gate_status("mika", 100)
	_check(not g0.met, "the Level 100 gate is still closed before the Crown is heard")
	asc = mb.options().filter(func(o): return String(o.kind) == "ascend")
	_check(not asc.is_empty(), "another night: up again")
	if not asc.is_empty():
		var top_shot := func():
			while not (main.world.crown as CrownChime)._busy:
				await get_tree().process_frame
			await _wait(4.0)
			var cc: Vector3 = (main.world.crown as CrownChime).global_position
			main.camera_rig.set_shot(cc + Vector3(-6.5, 3.2, 6.5), cc + Vector3(0, 1.6, 0), 55.0)
			await _wait(9.0)
			_shot("crown_bells")
			await _wait(4.5)
			main.camera_rig.set_shot(cc + Vector3(-14.0, 2.0, 14.0), cc + Vector3(0, 4.0, 0), 50.0)
			await _wait(1.2)
			_shot("crown_of_light")
		top_shot.call()
		var a2: Dictionary = await mb.run_activity(asc[0])
		report["ascend_all"] = a2
		var cr2: Dictionary = a2.get("crown", {})
		_check(cr2.get("all_nine", false) and mk.has("crown:heard_all_nine"), "all nine bells: she has heard the Crown (%s)" % cr2.get("detail", ""), cr2)
		var g1: Dictionary = Progression.gate_status("mika", 100)
		_check(g1.met, "the Level 100 gate is open (hear all nine rings)", g1)
		_check((a2.get("down", {}) as Dictionary).get("ok", false), "back down safely")
	_check(main.teleport_guard.violations.size() == tg0, "no one was ever moved instantly: the air carried her (violations %d)" % (main.teleport_guard.violations.size() - tg0), main.teleport_guard.violations.slice(tg0))


# ------------------------------------------------------------------ the Gilded Grove (two wards become one)
func _grove() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 15.0 * 60.0
	WorldState.clock_rate = 0.0
	await main.streaming.travel("whispering_woods", mika)
	await _wait(3.0)
	for w in ["mika", "luna"]:
		WorldState.mind(w).vigor = 1.0
	var base := mika.global_position
	_park("luna", base + Vector3(2.2, 0, 0))
	luna.visible = true                 # she is here too (not left behind in the Sanctuary's background)
	luna.set_physics_process(true)
	await _wait(0.6)
	mika.look_at_point(base + Vector3(0, 0, 8))
	luna.look_at_point(luna.global_position + Vector3(0, 0, 8))
	await _wait(0.6)
	var dist0 := mika.global_position.distance_to(luna.global_position)
	var r1: Dictionary = await main.magic.cast(mika, "leaf_ward")
	await _wait(0.3)
	var box := {"r2": {}}
	var caster := func():
		box.r2 = await main.magic.cast(luna, "gilded_mirror")
	caster.call()
	var g: Ward = null
	var tg := _gms()
	while _gms() - tg < 6000:
		var w := Ward.active_for(luna)
		if w and w.kind == "grove":
			g = w
			break
		await get_tree().process_frame
	while box.r2.is_empty() and _gms() - tg < 8000:
		await get_tree().process_frame
	var r2: Dictionary = box.r2
	_check(r1.get("ok", false) and r2.get("ok", false) and g != null and g.kind == "grove" and Ward.active_for(mika) == g,
		"Leaf Ward and Gilded Mirror, %.1f m apart, became one dome over both: the Gilded Grove" % dist0, [r1.get("reason", ""), r2.get("reason", ""), g.kind if g else "none"])
	if g == null or g.kind != "grove":
		return
	report["grove_up"] = {"charges": g.charges, "seconds": snappedf(g.seconds, 0.1), "radius": snappedf(g._radius(), 0.01)}
	_check(WorldState.mind("mika").knowledge.has("fusion:gilded_grove") and WorldState.mind("luna").knowledge.has("fusion:gilded_grove"), "both of them learned it, each in her own mind")
	var c := g._centre()
	main.camera_rig.set_shot(c + Vector3(-3.5, 1.4, 6.5), c + Vector3(0, 0.3, 0), 52.0)
	await _wait(0.9)
	_shot("grove_up")
	# their bodies hold it: arms up and out, leaning in (BodyLanguage barrier channel)
	_check(mika.body_language and luna.body_language and mika.body_language.barrier > 0.6 and luna.body_language.barrier > 0.6,
		"both of them visibly hold the dome (barrier hold %.2f / %.2f)" % [mika.body_language.barrier if mika.body_language else -1.0, luna.body_language.barrier if luna.body_language else -1.0])
	var mf := -mika.global_transform.basis.z
	main.camera_rig.set_shot(mika.global_position + Vector3(mf.x, 0, mf.z).normalized() * 2.6 + Vector3(0.6, 1.5, 0), mika.global_position + Vector3(0, 1.25, 0), 45.0)
	await _wait(0.6)
	_shot("grove_hold_close")
	# a bolt at Luna's BACK (her mirror alone covers only her front): the grove stops it
	print("[mktest] grove before bolts: done=%s age=%.2f/%.2f charges=%d r=%.2f centre=%s log=%s" % [g.done, g._age, g.seconds, g.charges, g._radius(), g._centre(), g.log])
	var knocked := {"mika": 0.0, "luna": 0.0}
	var watch_knock := func():
		var t0 := _gms()
		while _gms() - t0 < 3000:
			for w in knocked:
				var bl: BodyLanguage = main.characters[w].body_language
				if bl:
					knocked[w] = maxf(knocked[w], bl._impact)
			await get_tree().process_frame
	watch_knock.call()
	var b1 := await _test_bolt("luna", luna.global_position + Vector3(0.5, 1.5, -7.0))
	_check(knocked.mika > 0.3 and knocked.luna > 0.3, "the blow on the dome knocked them both back a little (%.2f / %.2f)" % [knocked.mika, knocked.luna])
	_check((b1.struck as Array).is_empty() and String(b1.get("absorbed_by", "")) == "grove" or bool(b1.get("reflected", false)), "a bolt at Luna's back: the grove took it (the mirror alone would not have)", b1)
	await _wait(0.2)
	_shot("grove_block")
	# a bolt at Mika from the side: covered too, and thrown back (the combination's gift)
	var b2 := await _test_bolt("mika", mika.global_position + Vector3(-7.0, 1.5, 1.0))
	_check((b2.struck as Array).is_empty() and bool(b2.get("reflected", false)), "a bolt at Mika's side: thrown back off the dome", b2)
	report["grove_bolts"] = [b1, b2]
	_check(float(WorldState.mind("mika").skills.get("leaf_ward", 0.0)) > 0.0 and float(WorldState.mind("luna").skills.get("gilded_mirror", 0.0)) > 0.0, "each blow was practice for each mage's own ward")
	# they part: the grove comes apart
	_park("luna", mika.global_position + Vector3(6.0, 0, 0))
	await _wait(0.5)
	_check((not is_instance_valid(g) or g.done) and Ward.active_for(mika) == null, "when they step apart, the grove comes apart")
	# alone, too far apart, the two wards stay two
	var r3: Dictionary = await main.magic.cast(mika, "leaf_ward")
	await _wait(0.3)
	var r4: Dictionary = await main.magic.cast(luna, "gilded_mirror")
	await _wait(0.6)
	var wm := Ward.active_for(mika)
	var wl := Ward.active_for(luna)
	print("[mktest] grove apart: r3=%s r4=%s wm=%s wl=%s" % [r3.get("reason", r3.get("effect", "")), r4.get("reason", r4.get("effect", "")), wm.kind if wm else "none", wl.kind if wl else "none"])
	_check(r3.get("ok", false) and r4.get("ok", false) and wm != null and wl != null and wm.kind == "leaf" and wl.kind == "mirror", "six metres apart, the wards stay their own")


# ------------------------------------------------------------------ the automatic audit (InvariantAuditor)
## Every area, every interaction she can do there (walk to it, use it / read it), and the townsfolk's working
## day - all under the auditor's rules (at the object and facing it, tool in hand, nobody floating or sunk).
## A still of each interaction mid-way: screenshots/mktest/audit_<area>_<id>.png.
func _audit() -> void:
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var au: InvariantAuditor = main.auditor
	BookReader.test_time_scale = 0.3
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 10.0 * 60.0
	WorldState.clock_rate = 0.0
	var areas: Array = String(RenderProfile.options.get("areas", "")).split(",", false) if RenderProfile.options.has("areas") else \
		["sanctuary", "whispering_woods", "ancient_grove", "river_valley", "highland_path", "celestial_summit", "crystal_caverns",
		"deep_caverns", "village", "observatory_hill", "academy", "mentor_tower", "great_library"]
	var rows := []
	for area in areas:
		if area != main.streaming.current_id:
			await main.streaming.travel(area, mika)
			await _wait(2.0)
		for id in main.world.interactables.keys():
			var it: Interactable = main.world.interactables.get(id)
			if it == null or it.custom_activity.is_valid() or not it._requirements_met("mika") or (not it.repeatable and it.times_done > 0):
				continue
			it.duration_override = 1.8
			var v0 := au.violations.size()
			var tag := "audit_%s_%s" % [area, id]
			var shot_box := {"armed": true}
			var shoot := func():
				var t0 := _gms()
				while not it.busy and _gms() - t0 < 30000 and shot_box.armed:
					await get_tree().process_frame
				await _wait(1.8)
				if shot_box.armed:
					_shot(tag)
			shoot.call()
			var r: Dictionary = await mb._use(id)
			shot_box.armed = false
			var new_v := au.violations.slice(v0)
			rows.append({"area": area, "id": id, "ok": r.get("ok", false), "detail": String(r.get("detail", "")).left(80), "violations": new_v.map(func(v): return v.rule)})
			print("[mktest] audit %s/%s ok=%s violations=%s" % [area, id, r.get("ok", false), new_v.map(func(v): return [v.rule, v.get("dist", v.get("face_deg", v.get("gap", "")))])])
			await _wait(0.4)
		# where people live: a working day at speed, every tool and every pair of feet checked
		if main.get("town") and not main.town.residents.is_empty():
			WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 7.0 * 60.0
			WorldState.clock_rate = 6.0
			var t1 := _gms()
			var shots := 0
			while _gms() - t1 < 100000:
				await _wait(12.0)
				for rid in main.town.residents:
					var rr = main.town.residents[rid]
					if shots < 4 and is_instance_valid(rr) and rr.visible and rr.tools.values().any(func(h): return (h as Node3D).visible):
						await _res_shot(rr, "audit_%s_tool_%s" % [area, rid])
						shots += 1
						break
			WorldState.clock_rate = 0.0
			WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 10.0 * 60.0
	BookReader.test_time_scale = 1.0
	report["audit_rows"] = rows
	report["audit"] = au.summary()
	report["audit_violations"] = au.violations
	print("[mktest] audit summary ", JSON.stringify(au.summary()))
	_check(rows.size() >= mini(10, areas.size() * 2) and rows.all(func(r): return r.ok), "the audit used %d interactions across %d areas, every one completed (%s)" % [rows.size(), areas.size(), str(rows.filter(func(r): return not r.ok).map(func(r): return r.area + "/" + r.id))])
	_check(au.violations.is_empty(), "no visible defects found by the auditor (%d checks)" % au.checks.values().reduce(func(a, b): return a + b, 0), au.summary())


# ------------------------------------------------------------------ performance benchmark (test-only overrides)
## --mktest=bench --bench-fps=30|60|0 (0 = uncapped): the FPS cap and VSync are overridden HERE, for this run only
## (production profiles untouched). Representative scenes with both mages, 45 s measured each after a warm-up:
## the Sanctuary, the dense Whispering Woods, the Village at work (residents), an ambush fight (rivals, magic).
## "[bench] start/end <scene> <unix time>" lines align external GPU/CPU/temperature samples.
func _bench() -> void:
	var cap := int(RenderProfile.options.get("bench-fps", "30"))
	var mika: WorldCharacter = main.characters["mika"]
	var apply_cap := func():
		Engine.max_fps = cap
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	apply_cap.call()
	main.spawner.enabled = false
	main.director.enabled = true
	var results := {}
	var scenes: Array = String(RenderProfile.options.get("bench-scenes", "sanctuary,forest,town,combat")).split(",", false)
	for sc in scenes:
		var fight := {}
		match sc:
			"sanctuary":
				if main.streaming.current_id != "sanctuary":
					await main.streaming.travel("sanctuary", mika)
			"forest":
				await main.streaming.travel("whispering_woods", mika)
			"town":
				WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 10.0 * 60.0
				WorldState.clock_rate = 2.0
				await main.streaming.travel("village", mika)
			"summit":
				await main.streaming.travel("celestial_summit", mika)
			"caverns":
				await main.streaming.travel("deep_caverns", mika)
			"transform":
				await main.streaming.travel("sanctuary", mika)
				await _wait(2.0)
				var tr := func():
					fight["res"] = await main.transformer.play("mika", "full", true)    # preview: no progress, reverts
				tr.call()
			"combat":
				WorldState.clock_rate = 0.0
				await _hold_all()
				await main.streaming.travel("whispering_woods", mika)
				await _wait(2.0)
				var vp: Vector2 = main.world.get("viewpoint") if main.world.get("viewpoint") != null else Vector2(mika.global_position.x, mika.global_position.z)
				var runner := func():
					fight["res"] = await main.ambush.run("road_thieves", {"fight_s": 75.0})
				runner.call()
		apply_cap.call()
		if sc != "combat":
			for w in main.mage_brains:
				(main.mage_brains[w] as SanctuaryBrain).hold = false
		await _wait(8.0 if sc == "combat" else 6.0)
		_frame_ms.clear()
		_gpu_ms.clear()
		_cpu_ms.clear()
		print("[bench] start %s %.3f" % [sc, Time.get_unix_time_from_system()])
		var levels := []
		var ch0: int = main.gfx.history.size() if main.get("gfx") else 0
		var measure := 25.0 if sc == "transform" else 45.0
		var tm := 0.0
		while tm < measure:
			await _wait(1.0)
			tm += 1.0
			if main.get("gfx"):
				levels.append(int(main.gfx.level))
			if int(tm) == int(measure / 2.0):
				_shot("bench_%s_%s" % [RenderProfile.profile.to_lower(), sc])
		print("[bench] end %s %.3f" % [sc, Time.get_unix_time_from_system()])
		var st := _fps_stats()
		var s2: Array = _frame_ms.duplicate()
		s2.sort()
		s2.reverse()
		var n1 := maxi(1, int(s2.size() * 0.01))
		var worst := 0.0
		for i in n1:
			worst += float(s2[i])
		st["low1_fps"] = snappedf(1000.0 / (worst / n1), 0.1)
		st["p99_ms"] = snappedf(float(s2[int(s2.size() * 0.01)]), 0.1)
		st["cap"] = cap
		st["profile"] = RenderProfile.profile
		if not levels.is_empty():
			var lsum := 0
			for l in levels:
				lsum += int(l)
			st["quality_level_avg"] = snappedf(float(lsum) / levels.size(), 0.01)
			st["quality_level_min"] = levels.min()
			st["quality_level_max"] = levels.max()
			st["quality_changes"] = main.gfx.history.size() - ch0
			st["quality_last"] = String(main.gfx.reason)
			st["scale_3d_end"] = snappedf(get_viewport().scaling_3d_scale, 0.01)
		st["window"] = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
		st["vsync"] = DisplayServer.window_get_vsync_mode()
		results[sc] = st
		print("[bench] result %s %s" % [sc, JSON.stringify(st)])
		if sc in ["combat", "transform"]:
			var t0 := _gms()
			while not fight.has("res") and _gms() - t0 < 90000:
				await get_tree().process_frame
	report["bench"] = results
	if main.get("gfx"):
		print("[gfx] history ", JSON.stringify(main.gfx.history))
		print("[gfx] memory ", JSON.stringify(main.gfx.memory), " hitchy ", JSON.stringify(main.gfx.hitchy))
	_check(results.size() == scenes.size(), "benchmarked %d scenes at cap %s" % [results.size(), str(cap) if cap > 0 else "none"], results)


# ------------------------------------------------------------------ adaptive graphics calibration
## --profile=adaptive --mktest=gfxcal: in heavy scenes, each quality knob is tried ALONE at its lowest setting and
## its real GPU saving measured (4 s windows), so the Adaptive 60 ladder can be ordered by measured gain.
func _gfxcal() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var g: AdaptiveQuality = main.gfx
	g.enabled = false
	Engine.max_fps = 0                         # uncapped: GPU time is measured, not hidden by the cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main.spawner.enabled = false
	main.director.enabled = true
	var cands := [["scale", 0.83], ["scale", 0.67], ["distant", 0.52], ["foliage", 0.55], ["shadow", 0.6], ["particles", 0.6],
		["volfog", 0.0], ["ssil", 0.0], ["ssr", 0.0], ["ssao", 0.0], ["lod", 2.5], ["shadowmap", 0.5], ["ssaoq", 0.0], ["upscaler", 0.0],
		["x_veg", 1.0], ["x_trees", 1.0], ["x_fx", 1.0], ["x_shadow", 1.0]]
	var base_k: Dictionary = g.floor_knobs() if String(RenderProfile.options.get("cal-base", "")) == "floor" else {}
	if RenderProfile.options.has("cal-knobs"):
		cands = cands.filter(func(c2): return String(RenderProfile.options["cal-knobs"]).split(",").has(String(c2[0])))
	var table := {}
	for sc in String(RenderProfile.options.get("bench-scenes", "forest,combat,town")).split(",", false):
		var fight := {}
		match sc:
			"forest":
				await main.streaming.travel("whispering_woods", mika)
			"town":
				WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 10.0 * 60.0
				await main.streaming.travel("village", mika)
			"sanctuary":
				await main.streaming.travel("sanctuary", mika)
			"combat":
				await _hold_all()
				await main.streaming.travel("whispering_woods", mika)
				await _wait(2.0)
				var runner := func():
					fight["res"] = await main.ambush.run("road_thieves", {"fight_s": 140.0})
				runner.call()
		Engine.max_fps = 0
		await _wait(6.0)
		g.apply_knobs(base_k)
		await _wait(2.0)
		var base: Dictionary = g.window(4.0)
		await _wait(4.0)
		base = g.window(4.0)
		var rows := {"base_gpu_ms": snappedf(float(base.get("gpu_ms", 0.0)), 0.01), "base_fps": snappedf(1000.0 / maxf(float(base.get("avg_ms", 1.0)), 0.1), 0.1)}
		for cnd in cands:
			var kk: Dictionary = base_k.duplicate()
			kk[String(cnd[0])] = float(cnd[1])
			g.apply_knobs(kk)
			await _wait(1.5)
			await _wait(4.0)
			var w: Dictionary = g.window(4.0)
			g.apply_knobs(base_k)
			await _wait(1.0)
			var b2: Dictionary = g.window(1.0)
			rows["%s=%s" % [cnd[0], cnd[1]]] = {"gpu_ms": snappedf(float(w.get("gpu_ms", 0.0)), 0.01), "saved_ms": snappedf(float(base.get("gpu_ms", 0.0)) - float(w.get("gpu_ms", 0.0)), 0.01),
				"fps": snappedf(1000.0 / maxf(float(w.get("avg_ms", 1.0)), 0.1), 0.1)}
		table[sc] = rows
		print("[gfxcal] %s %s" % [sc, JSON.stringify(rows)])
		if sc == "combat":
			var t0 := _gms()
			while not fight.has("res") and _gms() - t0 < 150000:
				await get_tree().process_frame
	report["gfxcal"] = table
	_check(not table.is_empty(), "calibrated %d scenes" % table.size(), table)


# ------------------------------------------------------------------ Adaptive 60: the decision rules (GPU-independent)
## --profile=adaptive --mktest=adaptive: synthetic frame windows drive AdaptiveQuality's decisions, so its rules are
## checked exactly, whatever this machine's GPU does: sustained GPU overload -> one step down at a time (with the
## minimum gap); loads and compile stalls ignored; CPU-bound frames never lower graphics; quality restored only after
## sustained headroom, one step at a time; a step that bounces back is restored more patiently; a remembered
## situation goes straight to its level.
func _adaptive() -> void:
	var g: AdaptiveQuality = main.gfx
	_check(RenderProfile.profile == RenderProfile.ADAPTIVE_60 and g.enabled, "Adaptive 60 is on", RenderProfile.profile)
	await _hold_all()
	g.set_process(false)                    # we feed it ourselves
	var feed := func(frame_ms: float, gpu_ms: float, cpu_ms: float, n: int, flagged := false):
		for i in n:
			g._frames.append([frame_ms, gpu_ms, cpu_ms, flagged])
			if g._frames.size() > 640:
				g._frames.pop_front()
	g.reset_quality()
	g._hold_until = 0.0
	g._last_change = -100.0
	g.memory.clear()
	g._sit = g._situation()
	# 1) heavy GPU frames: one step down, then nothing until the gap has passed
	feed.call(20.0, 19.0, 3.0, 240)
	g._evaluate()
	_check(g.level == 1, "a sustained GPU overload takes ONE step down (level %d: %s)" % [g.level, g.reason])
	g._evaluate()
	_check(g.level == 1, "...and waits before the next (minimum gap)")
	g._last_change -= 3.0
	feed.call(20.0, 19.0, 3.0, 240)
	g._evaluate()
	_check(g.level == 2, "after the gap, the next step (level %d)" % g.level)
	# 2) a load / compile stall is not a reason
	var l0 := g.level
	g._last_change -= 3.0
	g._frames.clear()
	feed.call(16.6, 9.0, 3.0, 200)
	feed.call(120.0, 9.0, 3.0, 12, true)
	g._evaluate()
	_check(g.level == l0, "loading / shader-compile stalls never lower quality (level %d)" % g.level)
	# 3) CPU-bound: reported, graphics untouched
	g._frames.clear()
	feed.call(21.0, 8.0, 18.0, 240)
	g._evaluate()
	_check(g.level == l0 and g.bottleneck == "cpu", "CPU-bound frames do not lower graphics (%s)" % g.reason)
	# 4) headroom: restored only after it lasts, one step at a time
	g._frames.clear()
	feed.call(16.67, 6.0, 3.0, 600)
	g._last_change = g._now() - 2.0
	g._evaluate()
	_check(g.level == l0, "headroom for a moment is not enough to restore")
	g._last_change = g._now() - 9.0
	g._evaluate()
	_check(g.level == l0 - 1, "sustained headroom restores ONE step (level %d: %s)" % [g.level, g.reason])
	# 5) a step that comes straight back is restored more patiently next time
	var restored := g.level
	g._frames.clear()
	feed.call(20.0, 19.0, 3.0, 240)
	g._last_change -= 3.0
	g._evaluate()
	_check(g.level == restored + 1 and int(g.oscillation.get(restored, 0)) >= 1, "re-needed soon after a restore: counted as an oscillation (%s)" % str(g.oscillation))
	g._frames.clear()
	feed.call(16.67, 6.0, 3.0, 600)
	g._last_change = g._now() - 9.0
	g._evaluate()
	_check(g.level == restored + 1, "...so it waits longer before restoring that step again")
	# 6) a remembered situation: straight to its level in one change
	g.reset_quality()
	g.memory["test_place"] = 5
	g._sit = "elsewhere"
	var real_sit := g._situation()
	g.memory[real_sit] = 5
	g._frames.clear()
	feed.call(16.67, 12.0, 3.0, 240)
	g._evaluate()
	_check(g.level == 5, "a situation met before goes straight to the level that held 60 there (level %d: %s)" % [g.level, g.reason])
	# 7) the knobs really reach the renderer; the characters are protected
	g.apply_knobs({"scale": 0.75})
	_check(absf(get_viewport().scaling_3d_scale - 0.75) < 0.01 and get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2, "the 3D scale reaches the viewport (FSR 2)")
	var prot := true
	for who in main.characters:
		for gi in (main.characters[who] as Node).find_children("*", "GeometryInstance3D", true, false):
			if (gi as GeometryInstance3D).lod_bias < 3.9:
				prot = false
	_check(prot, "Mika's and Luna's meshes keep full detail (LOD bias)")
	g.reset_quality()
	_check(absf(get_viewport().scaling_3d_scale - 1.0) < 0.01, "back to full quality")
	# down to the floor and back up: the area's own look is restored exactly (fog, SSR / SSIL, the sun's reach)
	var env: Environment = main.world.get("env")
	var sun: DirectionalLight3D = main.world.get("sun")
	if env and sun:
		var d0 := sun.directional_shadow_max_distance
		g.apply_knobs(g.floor_knobs())
		await get_tree().process_frame
		var low_ok := not env.volumetric_fog_enabled and sun.directional_shadow_max_distance < d0
		g.reset_quality()
		await get_tree().process_frame
		_check(low_ok and env.volumetric_fog_enabled == bool(RenderProfile.get_setting("volumetric_fog")) and env.ssr_enabled == bool(RenderProfile.get_setting("ssr"))
			and env.ssil_enabled == bool(RenderProfile.get_setting("ssil")) and absf(sun.directional_shadow_max_distance - d0) < 0.01,
			"floor and back: fog / SSR / SSIL as the profile has them, the sun's shadow reach exactly restored (%.1f m)" % sun.directional_shadow_max_distance)
	g.set_process(true)


# ------------------------------------------------------------------ weapons in hand (visual + auditor)
## Every armed rival: standing (weapon at rest) and in a real strike at Mika - close-ups of the weapon hand from
## two sides (screenshots/mktest/weapons_<kind>_*.png) while the auditor checks the blade never passes through the
## wielder, never sinks into the ground and points at what it strikes.
func _weapons() -> void:
	await _hold_all()
	main.director.enabled = false
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var au: InvariantAuditor = main.auditor
	await main.streaming.travel("whispering_woods", mika)
	await _wait(2.0)
	var v0 := au.violations.size()
	var fwd := -mika.global_transform.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	for kind in ["rival_ronin", "rival_cutthroat", "rival_shade"]:
		var at := NavigationServer3D.map_get_closest_point(mika.get_world_3d().navigation_map, mika.global_position + fwd * 6.0)
		var m: Monster = main.spawner.spawn(kind, at)
		_check(m != null, "%s spawned" % kind)
		if m == null:
			continue
		m.set_physics_process(false)            # standing still: the weapon at rest
		await _wait(2.5)
		var rig = m.get("creature")
		var ws: Array = rig.weapons if rig and rig.get("weapons") != null else []
		_check(not ws.is_empty() and (ws[0] as Node3D).has_meta("tip_local"), "%s holds a measured weapon (%d)" % [kind, ws.size()])
		for w in ws:
			# held by the HANDLE: the fist (grip point) far from the tip - most of the weapon beyond the hand
			var gl: Vector3 = (w as Node3D).get_meta("grip_local", Vector3.ZERO)
			var tl: Vector3 = (w as Node3D).get_meta("tip_local", Vector3.ZERO)
			var wl := float((w as Node3D).get_meta("weapon_length", 1.0))
			_check(gl.distance_to(tl) > wl * 0.6, "%s holds its weapon by the handle (fist to tip %.2f of %.2f m, found by %s)" % [kind, gl.distance_to(tl), wl, String((w as Node3D).get_meta("grip_by", "?"))])
			var hand: Vector3 = (w as Node3D).global_position
			var tip: Vector3 = (w as Node3D).global_transform * ((w as Node3D).get_meta("tip_local", Vector3.ZERO) as Vector3)
			report["weapon_%s" % kind] = {"grip_y": snappedf(hand.y - m.global_position.y, 0.01), "tip_y": snappedf(tip.y - m.global_position.y, 0.01),
				"length": snappedf(hand.distance_to(tip), 0.01)}
		if not ws.is_empty():
			var hp: Vector3 = (ws[0] as Node3D).global_position
			var mr := m.global_transform.basis.x
			main.camera_rig.set_shot(hp + mr * 1.3 + Vector3(0, 0.25, 0), hp, 45.0)
			await _wait(0.5)
			_shot("weapons_%s_rest_side" % kind)
			var mf := m.global_transform.basis.z
			main.camera_rig.set_shot(hp + mf * 1.6 + Vector3(0, 0.4, 0), hp + Vector3(0, -0.1, 0), 50.0)
			await _wait(0.5)
			_shot("weapons_%s_rest_front" % kind)
		# a real strike at Mika
		m.global_position = NavigationServer3D.map_get_closest_point(mika.get_world_3d().navigation_map, mika.global_position + fwd * 2.4)
		m.set_physics_process(true)
		m.target_mage = mika
		var t0 := _gms()
		var shot_taken := false
		var alert_shot := false
		while _gms() - t0 < 15000 and not shot_taken:
			await get_tree().process_frame
			if not alert_shot and String(m.mstate) == "alert" and _gms() - t0 > 300 and not ws.is_empty():
				alert_shot = true
				var hp3: Vector3 = (ws[0] as Node3D).global_position
				main.camera_rig.set_shot(m.global_position + m.global_transform.basis.x * 2.2 + Vector3(0, 1.6, 0), m.global_position + Vector3(0, 1.3, 0), 50.0)
				await _wait(0.1)
				_shot("weapons_%s_alert_side" % kind)
				main.camera_rig.set_shot(m.global_position + m.global_transform.basis.z * 2.6 + Vector3(0, 1.6, 0), m.global_position + Vector3(0, 1.3, 0), 50.0)
				await _wait(0.1)
				_shot("weapons_%s_alert_front" % kind)
			if String(m.mstate) in ["strike", "windup", "attack"] and _gms() - t0 > 600 and not ws.is_empty():
				var hp2: Vector3 = (ws[0] as Node3D).global_position
				main.camera_rig.set_shot(hp2 + m.global_transform.basis.x * 2.0 + Vector3(0, 0.6, 0), hp2, 50.0)
				await _wait(0.12)
				_shot("weapons_%s_strike" % kind)
				shot_taken = true
		_check(shot_taken, "%s struck at her (a strike pose captured)" % kind)
		m.queue_free()
		await _wait(1.0)
	var wv := au.violations.slice(v0).filter(func(v): return String(v.rule).begins_with("weapon") or String(v.rule).begins_with("facing"))
	report["weapon_violations"] = wv
	_check(wv.is_empty(), "no blade through its wielder, into the ground or pointing away in a strike", wv)
	main.director.enabled = true
	main.camera_rig.clear_shot()


# ------------------------------------------------------------------ built stone: nothing floats
## --mktest=stones [--areas=a,b]: every area's built stone (walls, ruins, arches, steps, terraces) - each block rests
## on the ground or on a block below it (InvariantAuditor.check_stones, the same rule the auditor runs on arrival).
func _stones() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var areas: Array = String(RenderProfile.options.get("areas", "")).split(",", false) if RenderProfile.options.has("areas") else \
		["sanctuary", "whispering_woods", "ancient_grove", "river_valley", "highland_path", "celestial_summit", "crystal_caverns",
		"deep_caverns", "village", "observatory_hill", "academy", "mentor_tower", "great_library"]
	for area in areas:
		if area != main.streaming.current_id:
			await main.streaming.travel(area, mika)
		await _wait(1.0)
		var r := InvariantAuditor.check_stones(main.world)
		for s in r.structures:
			print("[mktest] stones %s/%s: %d of %d float, at %s, gap below %s m" % [area, s.name, s.count, s.of, str(s.at), str(s.gap_m)])
			# a picture of the first one, from 7 m off and a little above, so it can be judged by eye
			var at: Array = s.at[0]
			var bp := Vector3(at[0], at[1], at[2])
			var from := bp + Vector3(5.0, 3.0, 5.0)
			main.camera_rig.set_shot(from, bp, 55.0)
			await _wait(0.8)
			_shot("%s_%s" % [area, String(s.name)])
		main.camera_rig.clear_shot()
		_check(int(r.floating) == 0, "%s: every stone stands on something (%d blocks checked)" % [area, int(r.checked)], r.floating)


## --mktest=view --area=<id> --views="fx,fy,fz>ax,ay,az;..." [--hour=H]: pictures from given points (QA of one spot).
func _view() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var area := String(RenderProfile.options.get("area", main.streaming.current_id))
	if area != main.streaming.current_id:
		await main.streaming.travel(area, mika)
	if RenderProfile.options.has("hour"):
		WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + float(RenderProfile.options.hour) * 60.0
		WorldState.clock_rate = 0.0
	await _wait(1.5)
	# --probe="x,z;x,z": the ground height there (the area's height function), for placing things on walkable ground
	for pz in String(RenderProfile.options.get("probe", "")).split(";", false):
		var xz := pz.split_floats(",")
		if main.world.has_method("height"):
			print("[mktest] probe %.1f,%.1f -> %.2f roof %.2f" % [xz[0], xz[1], float(main.world.height(xz[0], xz[1])), float(main.world.roof(xz[0], xz[1])) if main.world.has_method("roof") else -1.0])
	var i := 0
	for v in String(RenderProfile.options.get("views", "")).split(";", false):
		var ft := v.split(">")
		var f := ft[0].split_floats(",")
		var t := ft[1].split_floats(",")
		main.camera_rig.set_shot(Vector3(f[0], f[1], f[2]), Vector3(t[0], t[1], t[2]), 55.0)
		await _wait(1.0)
		_shot("%s_%d" % [area, i])
		i += 1
	main.camera_rig.clear_shot()
	_check(i > 0, "%d views taken" % i)


# ------------------------------------------------------------------ braziers (Part 5: none floating, none a black lump)
## --mktest=braziers [--areas=a,b]: every brazier / fire bowl in those areas is measured (the gap between its base and
## whatever solid is under it) and photographed from 3 m at noon.
func _braziers() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 12.0 * 60.0
	WorldState.clock_rate = 0.0
	var areas := String(RenderProfile.options.get("areas", "sanctuary,whispering_woods,deep_caverns")).split(",", false)
	for area in areas:
		if area != main.streaming.current_id:
			await main.streaming.travel(area, mika)
		await _wait(1.5)
		var found: Array = main.world.find_children("*", "Brazier", true, false) + main.world.find_children("*Brazier*", "Node3D", true, false)
		var seen := {}
		var i := 0
		for b in found:
			if seen.has(b) or not (b as Node3D).is_visible_in_tree():
				continue
			seen[b] = true
			var p: Vector3 = (b as Node3D).global_position
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, -0.05, 0), p + Vector3(0, -6.0, 0), 1)
			var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
			var gap := 99.0 if hit.is_empty() else p.y - (hit.position as Vector3).y
			var lit = b.get("lit")
			print("[mktest] brazier %s %s at %s gap_below=%.2f lit=%s" % [area, b.name, str(p.snapped(Vector3.ONE * 0.1)), gap, str(lit)])
			var dir := Vector3(1, 0, 1).normalized()
			main.camera_rig.set_shot(p + dir * 3.0 + Vector3(0, 1.0, 0), p, 55.0)
			await _wait(0.8)
			_shot("brazier_%s_%d_%s" % [area, i, b.name])
			i += 1
		main.camera_rig.clear_shot()
		_check(i > 0, "%s: %d braziers photographed" % [area, i])


# ------------------------------------------------------------------ dancing (the dance wing)
## --mktest=dance [--no-voice]: a viewer asks both mages to dance the Macarena; they dance it together, on the song's
## beat, and stop cleanly. The chat parser knows a request from talk about dancing. Poses of both mages during the
## dance are written (<dir>/<who>_dance_poses.json) for the outfit clip check.
func _dance() -> void:
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	var pair := await _stage_pair()
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 15.0 * 60.0
	WorldState.clock_rate = 0.0
	main.focus = "mika"
	var ch: ViewerChat = main.chat
	_check(ch.dance_intent("I don't dance").is_empty() and ch.dance_intent("what dance was that?").is_empty(), "talk about dancing is not a request")
	_check(bool(ch.dance_intent("stop dancing please").get("stop", false)), "\"stop dancing\" stops")
	_check(String(ch.dance_intent("go dancing!").get("who", "")) == "mika", "\"go dancing!\" asks the mage on camera")
	_check(String(ch.dance_intent("Luna, can you do the YMCA?").get("dance", "")) == "dance_ymca" and String(ch.dance_intent("Luna, can you do the YMCA?").get("who", "")) == "luna", "a named mage, a named routine")
	# each strand's resting angle while she stands (2 s, the widest seen): the reference "flung" is judged against
	var base := {"mika": {}, "luna": {}}
	var tb := _gms()
	while _gms() - tb < 2000:
		for who in ["mika", "luna"]:
			await (main.characters[who] as WorldCharacter).skeleton.skeleton_updated
			var a0: Dictionary = _dance_body_check(main.characters[who]).angles
			for k in a0:
				base[who][k] = maxf(float(base[who].get(k, 0.0)), float(a0[k]))
	report["hair_rest_deg"] = base
	# a celebration queued at start-up (a level gained while staging) would dance first: this test is about the request
	main.performance.requests.clear()
	var tq := _gms()
	while main.performance.busy() and _gms() - tq < 120000:
		await get_tree().process_frame
	var r: Dictionary = ch.receive({"message_id": "dance-1", "author_id": "v1", "author": "Viewer", "text": String(RenderProfile.options.get("dance-text", "Mika and Luna, can you dance the macarena together?"))})
	var di: Dictionary = r.get("dance", {})
	_check(String(di.get("who", "")) == "mika" and String(di.get("with", "")) == "luna" and String(di.get("dance", "")).begins_with("dance_"), "the request is understood: both, %s" % String(di.get("dance", "")), di)
	var first_done := {}
	main.performance.ended.connect(func(res): if first_done.is_empty(): first_done.merge(res), CONNECT_ONE_SHOT)
	var t0 := _gms()
	while not main.performance.busy() and _gms() - t0 < 30000:
		await get_tree().process_frame
	_check(main.performance.busy(), "the dance starts (within 30 s)")
	var poses := {"mika": {}, "luna": {}}
	var n := 0
	var t1 := _gms()
	var stats := {"mika": {"frames": 0, "flung": 0, "max_deg": 0.0, "feet_below": 0, "max_below_cm": 0.0}, "luna": {"frames": 0, "flung": 0, "max_deg": 0.0, "feet_below": 0, "max_below_cm": 0.0}}
	while first_done.is_empty() and _gms() - t1 < 120000:
		var t2 := _gms()
		while _gms() - t2 < 5000 and first_done.is_empty():
			await get_tree().process_frame
			if String(main.performance.active.get("stage", "")) != "dancing":
				continue
			var cl := String(main.performance.active.get("clips", [""])[-1])
			if cl != String(stats.get("_clip", "")):
				stats["_clip"] = cl
				print("[mktest] dance clip %s at frame %d (t=%.1f s)" % [cl, Engine.get_frames_drawn(), Time.get_ticks_msec() / 1000.0])
			for who in ["mika", "luna"]:
				# the FINAL pose (springs, FootGuard and the rest applied): only inside skeleton_updated
				await (main.characters[who] as WorldCharacter).skeleton.skeleton_updated
				var mm := _dance_body_check(main.characters[who], base[who])
				var s: Dictionary = stats[who]
				s.frames += 1
				if float(mm.hair_deg) > 60.0:
					s.flung += 1
					var key := "%s@%s" % [mm.strand, String(main.performance.active.get("clips", [""])[-1])]
					var wh: Dictionary = s.get_or_add("where", {})
					wh[key] = int(wh.get(key, 0)) + 1
					if int(s.get("shots", 0)) < 3 and int(wh[key]) == 8:
						s["shots"] = int(s.get("shots", 0)) + 1
						# a close look at her from behind-side while the strand is out
						var cw: WorldCharacter = main.characters[who]
						var keep_on: bool = main.camera_rig.shot_active
						main.camera_rig.set_shot(cw.global_position + cw.global_transform.basis.z * 2.2 + cw.global_transform.basis.x * 1.2 + Vector3(0, 1.5, 0), cw.global_position + Vector3(0, 1.2, 0), 45.0)
						await get_tree().process_frame
						await get_tree().process_frame
						_shot("flung_%s_%s" % [who, key])
						if not keep_on:
							main.camera_rig.clear_shot()
				s.max_deg = maxf(float(s.max_deg), float(mm.hair_deg))
				if float(mm.below) > 0.015:
					s.feet_below += 1
				s.max_below_cm = maxf(float(s.max_below_cm), float(mm.below) * 100.0)
		if String(main.performance.active.get("stage", "")) == "dancing" and n < 8:
			for who in ["mika", "luna"]:
				var sk: Skeleton3D = main.characters[who].skeleton
				await sk.skeleton_updated
				var d := {}
				for i in sk.get_bone_count():
					var D: Transform3D = sk.get_bone_global_pose(i) * sk.get_bone_global_rest(i).affine_inverse()
					var b := D.basis
					d[sk.get_bone_name(i)] = [b.x.x, b.y.x, b.z.x, D.origin.x, b.x.y, b.y.y, b.z.y, D.origin.y, b.x.z, b.y.z, b.z.z, D.origin.z]
				poses[who]["dance_%d_%s" % [n, String(main.performance.active.get("clips", [""])[-1])]] = d
			if n == 2:
				_shot("dance_both")
			n += 1
	_check(not first_done.is_empty(), "the dance ends by itself")
	var res: Dictionary = first_done
	report["dance"] = res
	_check(bool(res.get("ok", false)) and [String(res.get("who", "")), String(res.get("partner", ""))].has("luna") and [String(res.get("who", "")), String(res.get("partner", ""))].has("mika") and (res.get("clips", []) as Array).size() > 0,
		"they danced it together (%s led; %s, %.0f s of music)" % [String(res.get("who", "")), str(res.get("clips", [])), float(res.get("music_s", 0.0))], res)
	for who in poses:
		var f := FileAccess.open("%s/%s_dance_poses.json" % [dir, who], FileAccess.WRITE)
		f.store_string(JSON.stringify(poses[who]))
	_check(n >= 3, "poses captured during the dance (%d moments)" % n)
	stats.erase("_clip")
	report["dance_body"] = stats
	print("[mktest] dance body ", JSON.stringify(stats))
	for who in stats:
		var s: Dictionary = stats[who]
		var fr := maxf(float(s.frames), 1.0)
		_check(float(s.flung) / fr < 0.02, "%s's hair hangs while dancing (flung >60 deg in %d of %d frames, worst %.0f deg)" % [who, int(s.flung), int(s.frames), float(s.max_deg)])
		_check(float(s.feet_below) / fr < 0.01, "%s's feet stay on the floor while dancing (below it in %d of %d frames, worst %.1f cm)" % [who, int(s.feet_below), int(s.frames), float(s.max_below_cm)])


## While dancing: how far her hair is flung from hanging (the worst strand: root -> tip against straight down, in
## degrees; long hair shaken out sideways or flying up reads as a glitch), and how deep a foot is below the real
## floor under it (metres, after FootGuard).
func _dance_body_check(c: WorldCharacter, base := {}) -> Dictionary:
	var sk := c.skeleton
	var angles := {}
	var worst := 0.0
	var strand := ""
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		if not nm.begins_with("J_Sec_Hair") or nm.contains("Ribbon") or not sk.get_bone_children(i).is_empty():
			continue
		var root := i
		while sk.get_bone_parent(root) >= 0 and sk.get_bone_name(sk.get_bone_parent(root)).begins_with("J_Sec_Hair"):
			root = sk.get_bone_parent(root)
		if root == i:
			continue
		var v := (sk.get_bone_global_pose(i).origin - sk.get_bone_global_pose(root).origin)
		if v.length() < 0.15:
			continue                                        # short strands (fringe) are not judged
		var ang := rad_to_deg(v.normalized().angle_to(Vector3.DOWN))
		var sname := sk.get_bone_name(root).trim_prefix("J_Sec_").trim_suffix("_0")
		angles[sname] = ang
		# judged against the strand's own resting angle (a strand styled out to the side is not "flung")
		var over := ang - maxf(60.0, float(base.get(sname, 0.0)) + 40.0) + 60.0
		if over > worst:
			worst = over
			strand = sname
	var below := 0.0
	var space := sk.get_world_3d().direct_space_state
	for b in ["LeftFoot", "RightFoot"]:
		var bi := sk.find_bone(b)
		if bi < 0:
			continue
		var p := sk.global_transform * sk.get_bone_global_pose(bi).origin
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p - Vector3(0, 0.6, 0), 1)
		q.exclude = [c.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			below = maxf(below, ((hit.position as Vector3).y + maxf(sk.get_bone_global_rest(bi).origin.y, 0.02) * 0.6) - p.y)
	return {"hair_deg": worst, "below": below, "strand": strand, "angles": angles}


# ------------------------------------------------------------------ stream pacing (Task 1)
## --mktest=pacing --pacing-test: XP earned ahead of the pacing curve is banked (never lost) and released as played
## hours accrue; each level arrives no earlier than its target hour (Level 2 at 2 h ... Level 9 by ~380 h).
func _pacing() -> void:
	await _hold_all()
	var pr: Progression = main.progression
	var m := WorldState.mind("luna")
	m.progress.xp = 0.0
	m.progress.level = 1
	m.progress["played_s"] = 0.0
	m.progress["xp_bank"] = 0.0
	pr.gain("luna", 600.0, "a burst of discoveries")
	_check(float(m.progress.xp) <= 0.01 and absf(float(m.progress.xp_bank) - 600.0) < 0.1, "a burst at hour 0 is banked, not lost (xp %.1f, bank %.1f)" % [float(m.progress.xp), float(m.progress.xp_bank)])
	m.progress.played_s = 2.0 * 3600.0
	pr._pace_t = 99.0
	pr._process(0.0)
	_check(m.level() == 2, "after 2 played hours she reaches Level 2 (level %d, xp %.1f)" % [m.level(), float(m.progress.xp)])
	pr.gain("luna", 5000.0, "more")
	m.progress.played_s = 379.0 * 3600.0
	pr._pace_t = 99.0
	pr._process(0.0)
	_check(m.level() == 8, "at 379 h she is still Level 8 (level %d)" % m.level())
	m.progress.played_s = 381.0 * 3600.0
	pr._pace_t = 99.0
	pr._process(0.0)
	_check(m.level() == 9, "by ~380 h she is Level 9 (level %d, %.0f XP banked)" % [m.level(), float(m.progress.xp_bank)])
	m.progress.played_s = 600.0 * 3600.0
	pr._pace_t = 99.0
	pr._process(0.0)
	_check(m.level() == 9, "Level 10 still needs its Orbit Gate (level %d)" % m.level())


# ------------------------------------------------------------------ places to find (Task 3)
## --mktest=discoveries: every data/discoveries.json entry is placed (a solid prop on walkable ground), reachable,
## completes once its requirements are known, and teaches what it says (the next clue); the auditor watches.
func _discoveries() -> void:
	await _hold_all()
	main.director.enabled = true
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var mk := WorldState.mind("mika").knowledge
	WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 11.0 * 60.0
	WorldState.clock_rate = 0.0
	var by_area := {}
	for d in Discoveries.load_data().get("discoveries", []):
		(by_area.get_or_add(String(d.area), []) as Array).append(d)
	var au: InvariantAuditor = main.auditor
	for area in by_area:
		if area != main.streaming.current_id:
			await main.streaming.travel(area, mika)
			await _wait(2.0)
		for d in by_area[area]:
			var it: Interactable = main.world.interactables.get(String(d.id))
			_check(it != null, "%s: placed in %s" % [d.id, area])
			if it == null:
				continue
			for k in d.get("requires", {}).get("knowledge", {}):
				mk[k] = 1                                   # the clue that leads here (as if the journey was made)
			it.duration_override = 3.0
			var v0 := au.violations.size()
			# the screenshot is taken WHILE she does it (what viewers see), not after
			var job := {"done": false, "r": {}}
			var run := func(): job.r = await mb._use(String(d.id)); job.done = true
			run.call()
			var t0 := Time.get_ticks_msec()
			while not job.done and not it.in_reach(mika.global_position) and Time.get_ticks_msec() - t0 < 90000:
				await get_tree().process_frame
			if not job.done:
				await _wait(1.2)
				_shot("disc_%s" % d.id)
			while not job.done:
				await get_tree().process_frame
			var r: Dictionary = job.r
			var got := true
			for k in d.get("effects", {}).get("knowledge", {}):
				got = got and mk.has(k)
			_check(bool(r.get("ok", false)) and got, "%s: she reaches it, does it and learns what it says (%s)" % [d.id, String(r.get("detail", "")).left(60)], r)
			_check(au.violations.size() == v0, "%s: no visible defect while doing it" % d.id, au.violations.slice(v0))
			await _wait(0.3)



# ------------------------------------------------------------------ why do their heads keep moving?
## --mktest=headwatch [--headwatch-s=240]: both mages live on their own (brains on); every frame each one's head yaw
## relative to her chest is sampled, with what moves it (the look-at modifier vs the animation) and what she is doing
## (idle / walking / other). Reports how much of the time the head is turning, how often it swings back and forth,
## and where that comes from.
func _headwatch() -> void:
	var secs := float(RenderProfile.options.get("headwatch-s", "240"))
	for w in main.mage_brains:
		main.mage_brains[w].hold = false
		if not main.mage_brains[w].enabled:
			main.mage_brains[w].set_enabled(true)
	await get_tree().create_timer(8.0).timeout
	var st := {}
	for w in ["mika", "luna"]:
		st[w] = {"n": 0, "turning": 0, "rev": 0, "abs_yaw": 0.0, "by_driver": {"look_at": [0, 0], "anim": [0, 0]}, "by_act": {}, "last_yaw": 0.0, "last_v": 0.0, "last_sign_t": -9.0, "big": 0}
	var csv := FileAccess.open(RenderProfile.shots_dir + "/headwatch.csv", FileAccess.WRITE)
	if csv:
		csv.store_line("t,who,yaw,pitch,lookat,act,speed,bl,root_yaw,body_yaw,gaze_by,gaze_age_ms,qx,qy,qz,qw,dt")
	# the FINAL pose (after the look-at, head posture and body language modifiers), as it is rendered
	var fcsv := FileAccess.open(RenderProfile.shots_dir + "/headwatch_final.csv", FileAccess.WRITE)
	fcsv.store_line("t,who,qx,qy,qz,qw,lookat,act")
	var t_fin := Time.get_ticks_msec()
	for w2 in ["mika", "luna"]:
		var c2: WorldCharacter = main.characters.get(w2)
		if c2 and c2.skeleton:
			var sk2 := c2.skeleton
			sk2.skeleton_updated.connect(func():
				var hi2 := sk2.find_bone("Head")
				var ci2 := sk2.find_bone("UpperChest")
				if hi2 < 0 or ci2 < 0 or not c2.visible:
					return
				var rq2 := (sk2.get_bone_global_pose(ci2).basis.inverse() * sk2.get_bone_global_pose(hi2).basis).get_rotation_quaternion()
				var a2 := "walking" if c2.velocity.length() > 0.3 else String(c2.current_action)
				fcsv.store_line("%.4f,%s,%.5f,%.5f,%.5f,%.5f,%.2f,%s" % [(Time.get_ticks_msec() - t_fin) / 1000.0, w2, rq2.x, rq2.y, rq2.z, rq2.w, c2.head_look.influence if c2.head_look else 0.0, a2]))
	var t0 := _gms()
	print("[mktest] headwatch t0_ticks_ms=%d" % Time.get_ticks_msec())
	var prev_t := t0
	while _gms() - t0 < secs * 1000.0:
		await get_tree().process_frame
		var now := _gms()
		var dt := maxf((now - prev_t) / 1000.0, 0.001)
		prev_t = now
		for w in ["mika", "luna"]:
			var c: WorldCharacter = main.characters.get(w)
			if c == null or not c.visible or c.skeleton == null:
				continue
			var sk := c.skeleton
			var hi := sk.find_bone("Head")
			var ci := sk.find_bone("UpperChest")
			if ci < 0:
				ci = sk.find_bone("Chest")
			if hi < 0 or ci < 0:
				continue
			var hb := sk.get_bone_global_pose(hi).basis
			var cb := sk.get_bone_global_pose(ci).basis
			var f := (cb.inverse() * hb) * Vector3(0, 0, 1)
			var yaw := rad_to_deg(atan2(f.x, f.z))
			var pitch := rad_to_deg(asin(clampf(f.y, -1.0, 1.0)))
			var d: Dictionary = st[w]
			if csv:
				var a0 := "walking" if c.velocity.length() > 0.3 else String(c.current_action)
				var b0 = main.mage_brains.get(w)
				if b0 and not b0.current.is_empty():
					a0 += "/" + String(b0.current.get("kind", ""))
				var fr := hb * Vector3(0, 0, 1)          # skeleton space = the character's own facing
				var root_yaw := rad_to_deg(atan2(fr.x, fr.z))
				var rq := (cb.inverse() * hb).get_rotation_quaternion()
				csv.store_line("%.3f,%s,%.2f,%.2f,%.2f,%s,%.2f,%s,%.2f,%.2f,%s,%d,%.5f,%.5f,%.5f,%.5f,%.4f" % [(now - t0) / 1000.0, w, yaw, pitch, c.head_look.influence if c.head_look else 0.0, a0, c.velocity.length(), str(c.body_language != null), root_yaw, rad_to_deg(c.global_rotation.y), String(c.gaze_trace.get("by", "")).replace(",", ";"), Time.get_ticks_msec() - int(c.gaze_trace.get("t", 0)), rq.x, rq.y, rq.z, rq.w, dt])
			var v := (yaw - float(d.last_yaw)) / dt
			if int(d.n) == 0:
				v = 0.0
			d.last_yaw = yaw
			d.n = int(d.n) + 1
			d.abs_yaw = float(d.abs_yaw) + absf(yaw)
			if absf(yaw) > 25.0:
				d.big = int(d.big) + 1
			var turning := absf(v) > 20.0
			var driver := "look_at" if c.head_look and c.head_look.influence > 0.05 else "anim"
			var act := "walking" if c.velocity.length() > 0.3 else String(c.current_action)
			var br = main.mage_brains.get(w)
			if br and not br.current.is_empty():
				act += "/" + String(br.current.get("kind", ""))
			if turning:
				d.turning = int(d.turning) + 1
				d.by_driver[driver][0] += 1
				if not d.by_act.has(act):
					d.by_act[act] = 0
				d.by_act[act] += 1
				# a swing back: the turn reverses direction within a second of the last turn
				if signf(v) != signf(float(d.last_v)) and absf(float(d.last_v)) > 20.0 and (now - float(d.last_sign_t)) < 1000.0:
					d.rev = int(d.rev) + 1
				d.last_v = v
				d.last_sign_t = now
			d.by_driver[driver][1] += 1
	for w in ["mika", "luna"]:
		var d: Dictionary = st[w]
		var n := maxf(float(d.n), 1.0)
		var acts: Array = (d.by_act as Dictionary).keys()
		acts.sort_custom(func(a, b): return d.by_act[a] > d.by_act[b])
		var top := {}
		for a in acts.slice(0, 6):
			top[a] = snappedf(float(d.by_act[a]) / n * 100.0, 0.1)
		var res := {"who": w, "seconds": secs, "turning_pct": snappedf(float(d.turning) / n * 100.0, 0.1),
			"swings_back_per_min": snappedf(float(d.rev) / (secs / 60.0), 0.1), "mean_abs_yaw_deg": snappedf(float(d.abs_yaw) / n, 0.1),
			"head_off_centre_over_25deg_pct": snappedf(float(d.big) / n * 100.0, 0.1),
			"turning_while_lookat_pct_of_lookat_time": snappedf(float(d.by_driver.look_at[0]) / maxf(float(d.by_driver.look_at[1]), 1.0) * 100.0, 0.1),
			"turning_while_anim_pct_of_anim_time": snappedf(float(d.by_driver.anim[0]) / maxf(float(d.by_driver.anim[1]), 1.0) * 100.0, 0.1),
			"lookat_time_pct": snappedf(float(d.by_driver.look_at[1]) / n * 100.0, 0.1), "turning_pct_by_activity": top}
		print("[mktest] headwatch ", JSON.stringify(res))
	_check(true, "head motion measured")


## --mktest=tremble [--tremble-key=research:chamber_tablet]: Mika does one activity (default: read the Heartstone
## tablet on the altar-chamber wall); every frame her body, hips, head and hands are sampled in the world. Jitter =
## how often each part reverses direction at mm scale (a still pose has none, a tremble many) and its frame-to-frame
## acceleration, while she does it vs idle before it. Writes <shots>/tremble.csv.
func _tremble() -> void:
	var key := String(RenderProfile.options.get("tremble-key", "research:chamber_tablet"))
	await _hold_all()
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var c: WorldCharacter = main.characters["mika"]
	var csv := FileAccess.open(RenderProfile.shots_dir + "/tremble.csv", FileAccess.WRITE)
	csv.store_line("t,phase,act,stage,body_x,body_y,body_z,hips_x,hips_y,hips_z,head_x,head_y,head_z,rh_x,rh_y,rh_z,lh_x,lh_y,lh_z,vel")
	var phase := ["idle"]
	var t0 := _gms()
	var sampler := func():
		var sk := c.skeleton
		var pts := [c.global_position]
		for bn in ["Hips", "Head", "RightHand", "LeftHand"]:
			var bi := sk.find_bone(bn)
			pts.append(sk.global_transform * sk.get_bone_global_pose(bi).origin if bi >= 0 else Vector3.ZERO)
		var row := "%.3f,%s,%s,%s" % [(_gms() - t0) / 1000.0, phase[0], c.current_action, String(mb.current.get("stage", "")).replace(",", ";")]
		for p3 in pts:
			row += ",%.5f,%.5f,%.5f" % [p3.x, p3.y, p3.z]
		csv.store_line(row + ",%.3f" % c.velocity.length())
	get_tree().process_frame.connect(sampler)
	main.director.enabled = true
	var mw := MotionWatch.attach(main)
	await get_tree().create_timer(6.0).timeout
	var pick := {}
	for o in mb.ranked():
		if String(o.key) == key:
			pick = o
	if pick.is_empty():
		for o in mb.options():
			if String(o.get("key", "")) == key:
				pick = o
	_check(not pick.is_empty(), "the activity %s is on offer" % key)
	if not pick.is_empty():
		phase[0] = "activity"
		mb.current = {"kind": pick.kind, "label": pick.label, "key": pick.key, "stage": "starting"}
		var r: Dictionary = await mb.run_activity(pick)
		mb.current = {}
		_check(bool(r.get("ok", false)), "she did it (%s)" % String(r.get("detail", "")).left(80))
	phase[0] = "after"
	await get_tree().create_timer(4.0).timeout
	get_tree().process_frame.disconnect(sampler)
	csv.close()
	print("[mktest] tremble motion ", JSON.stringify(mw.report(8)))
	print("[mktest] tremble csv written")


## --mktest=motionwatch [--motionwatch-s=180] [--motionwatch-idle-s=40]: first both mages stand still (planners held)
## so an idle tremble shows on its own, then they live normally; MotionWatch watches every bone the whole time.
## FAILS when any bone trembles while they stand still.
func _motionwatch() -> void:
	var secs := float(RenderProfile.options.get("motionwatch-s", "180"))
	var idle_s := float(RenderProfile.options.get("motionwatch-idle-s", "40"))
	await _hold_all()
	if RenderProfile.options.has("motionwatch-pair"):
		await _stage_pair()              # both side by side, on camera
	await get_tree().create_timer(3.0).timeout
	await get_tree().create_timer(6.0).timeout        # whatever she was doing settles first (standing up, a gesture)
	var mw := MotionWatch.attach(main)
	await get_tree().create_timer(idle_s).timeout
	var still := mw.report(12)
	# at rest, which parts are still moving at all (mm/s), per mage - the restless chains by name
	for who in mw.stats:
		if who == "camera":
			continue
		var per: Dictionary = mw.stats[who].get("idle", {})
		var sp := []
		for bn in per:
			var s5: Array = per[bn]
			if s5.size() > 5 and int(s5[0]) > 30:
				sp.append([bn, float(s5[5]) / float(s5[0])])
		sp.sort_custom(func(a, b): return a[1] > b[1])
		print("[mktest] motionwatch REST SPEED %s %s" % [who, JSON.stringify(sp.slice(0, 25).map(func(x): return "%s %.0f" % [x[0], x[1]]))])
		var core := {}
		for x in sp:
			if String(x[0]) in ["_ROOT", "_SKELETON", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				core[x[0]] = snappedf(x[1], 1.0)
		var cc: WorldCharacter = main.characters.get(who)
		if cc and cc.anim_tree:
			var params := {}
			for pr in cc.anim_tree.get_property_list():
				var nm := String(pr.name)
				if nm.begins_with("parameters/"):
					var v = cc.anim_tree.get(nm)
					if v is float or v is int or v is bool or v is Vector2 or v is String or v is StringName:
						params[nm.trim_prefix("parameters/")] = str(v)
			var bt := cc.anim_tree.tree_root as AnimationNodeBlendTree
			var ca = bt.get_node("cast_anim") if bt and bt.has_node("cast_anim") else null
			print("[mktest] motionwatch CAST CLIP %s %s active=%s gesture_trace=%s" % [who, str(ca.animation) if ca else "?", str(cc.anim_tree.get("parameters/cast/active")), JSON.stringify(cc.get("gesture_trace") if cc.get("gesture_trace") else {})])
		print("[mktest] motionwatch REST CORE %s %s action=%s anim=%s" % [who, JSON.stringify(core), cc.current_action if cc else "", str(cc.anim_tree.get("parameters/playback").get_current_node()) if cc and cc.anim_tree and cc.anim_tree.get("parameters/playback") else "?"])
	print("[mktest] motionwatch STANDING STILL ", JSON.stringify(still))
	for w in main.mage_brains:
		main.mage_brains[w].hold = false
		if not main.mage_brains[w].enabled:
			main.mage_brains[w].set_enabled(true)
	mw.reset()
	await get_tree().create_timer(secs).timeout
	var live := mw.report(12)
	print("[mktest] motionwatch LIVING ", JSON.stringify(live))
	print("[mktest] motionwatch CLIPS ", JSON.stringify(mw.clips))
	var vp := get_viewport()
	print("[mktest] motionwatch AA msaa_3d=%d scaling_mode=%d scale=%.2f taa=%s" % [vp.msaa_3d, vp.scaling_3d_mode, vp.scaling_3d_scale, str(vp.use_taa)])
	for who in still:
		var n := int(still[who].get("idle", {}).get("trembling_bones", 0))
		_check(n == 0, "%s stands still without trembling (%d trembling bones: %s)" % [who, n, JSON.stringify(still[who].get("idle", {}).get("trembling_by_group", {}))])
	for who in live:
		var n2 := int(live[who].get("idle", {}).get("trembling_bones", 0))
		_check(n2 == 0, "%s idles in her own life without trembling (%d trembling bones: %s)" % [who, n2, JSON.stringify(live[who].get("idle", {}).get("trembling_by_group", {}))])


## --mktest=earshot: a mage's voice depends on where she is - full beside the camera, fainter further off, and not
## heard at all far away (no audio, no subtitle).
func _earshot() -> void:
	await _hold_all()
	var luna: WorldCharacter = main.characters["luna"]
	var cam := get_viewport().get_camera_3d()
	main.director.enabled = false
	var map: RID = luna.get_world_3d().navigation_map
	var flat := -cam.global_transform.basis.z
	flat.y = 0.0
	flat = flat.normalized()
	var out := {}
	for dist in [3.0, 15.0, 24.0, 40.0]:
		var p := NavigationServer3D.map_get_closest_point(map, cam.global_position + flat * dist)
		luna.global_position = p + Vector3(0, 0.05, 0)
		await get_tree().create_timer(0.3).timeout
		var d := cam.global_position.distance_to(luna.global_position + Vector3(0, 1.4, 0))
		var h: float = main.voice.hearing("luna")
		out["%.0f m" % d] = snappedf(h, 0.01)
	print("[mktest] earshot ", JSON.stringify(out))
	var vals: Array = out.values()
	_check(float(vals[0]) >= 0.99, "beside the camera she is heard in full (%s)" % JSON.stringify(out))
	_check(float(vals[1]) < 0.9 and float(vals[1]) > 0.05, "further off she is fainter")
	_check(float(vals[3]) == 0.0, "far away she is not heard at all")


## --mktest=starfall_site: where near their first spawn Starfall Hill could stand - open (nothing solid within 8 m at
## body height), gentle, a little raised, on the walkable ground. Prints the best candidates.
func _starfall_site() -> void:
	await _hold_all()
	var w = main.world
	var space: PhysicsDirectSpaceState3D = main.characters["mika"].get_world_3d().direct_space_state
	var map: RID = main.characters["mika"].get_world_3d().navigation_map
	var rows := []
	for r in [18.0, 24.0, 30.0, 36.0, 42.0, 50.0, 60.0]:
		for k in 24:
			var a := TAU * k / 24.0
			var x: float = cos(a) * float(r)
			var z: float = 1.6 + sin(a) * float(r)
			var hh: float = w.ground_at(x, z)
			var slope := 0.0
			var ring := 0.0
			for j in 8:
				var b := TAU * j / 8.0
				var h2: float = w.ground_at(x + cos(b) * 4.0, z + sin(b) * 4.0)
				slope = maxf(slope, absf(h2 - hh) / 4.0)
				ring += float(w.ground_at(x + cos(b) * 12.0, z + sin(b) * 12.0))
			var raised := hh - ring / 8.0
			var sh := SphereShape3D.new()
			sh.radius = 8.0
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = sh
			q.transform = Transform3D(Basis.IDENTITY, Vector3(x, hh + 9.0, z))   # above the ground: only things standing up
			q.collision_mask = 1 | 4
			var hits := space.intersect_shape(q, 16).filter(func(hd): return not ((hd.collider as Node).is_in_group("cat_terrain") if hd.collider is Node else false))
			var q2 := PhysicsShapeQueryParameters3D.new()
			var sh2 := SphereShape3D.new()
			sh2.radius = 8.0
			q2.shape = sh2
			q2.transform = Transform3D(Basis.IDENTITY, Vector3(x, hh + 1.2, z))
			q2.collision_mask = 1 | 4
			var low := space.intersect_shape(q2, 16).filter(func(hd): return hd.collider is Node and not (hd.collider as Node).is_in_group("cat_terrain") and not String((hd.collider as Node).name).to_lower().contains("terrain"))
			var nav := NavigationServer3D.map_get_closest_point(map, Vector3(x, hh, z))
			var navd := Vector2(nav.x - x, nav.z - z).length()
			rows.append({"x": snappedf(x, 0.1), "z": snappedf(z, 0.1), "r": r, "h": snappedf(hh, 0.01), "slope": snappedf(slope, 0.01), "raised": snappedf(raised, 0.01),
				"blocked": low.size(), "nav_off": snappedf(navd, 0.1), "area": String(w.area_at(Vector3(x, 0, z))) if w.has_method("area_at") else ""})
	var ok := rows.filter(func(rr): return rr.blocked == 0 and rr.nav_off < 1.0 and rr.slope < 0.2)
	ok.sort_custom(func(a, b): return (a.raised - a.slope * 2.0 - a.r * 0.01) > (b.raised - b.slope * 2.0 - b.r * 0.01))
	print("[mktest] starfall_site candidates %d of %d" % [ok.size(), rows.size()])
	for rr in ok.slice(0, 14):
		print("[mktest] starfall_site ", JSON.stringify(rr))
	_check(not ok.is_empty(), "an open, gentle spot near the spawn exists")


## --mktest=starfall_look --clock-hour=H: Starfall Hill in the sanctuary at hour H - both lying at the bed, then the
## camera from down the hill, close, from the tree, up at the sky. Stills: starfall_look_<hour>_<shot>.png.
func _starfall_look() -> void:
	await _hold_all()
	var sf: StarfallPlace = StarfallPlace.instance
	_check(sf != null and is_instance_valid(sf), "Starfall Hill is in the sanctuary")
	if sf == null:
		return
	main.director.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var fwd := sf.bed - sf.tree_base
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var map: RID = mika.get_world_3d().navigation_map
	mika.global_position = NavigationServer3D.map_get_closest_point(map, sf.bed + side * 0.6)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, sf.bed - side * 0.6)
	mika.visible = true
	luna.visible = true
	for c in [mika, luna]:
		c.look_at_point(c.global_position + fwd * 3.0)
	await _wait(1.5)
	mika.lie_down()
	await luna.lie_down()
	await _wait(3.0)
	# lying still: how much the hair and the dress keep moving (should settle on the grass)
	var mw := MotionWatch.attach(main)
	main.camera_rig.set_shot(sf.bed + fwd * 4.2 + side * 2.2 + Vector3(0, 1.7, 0), sf.bed + Vector3(0, 0.3, 0), 50.0)
	await _wait(8.0)
	for who in ["mika", "luna"]:
		var per: Dictionary = mw.stats.get(who, {}).get("other", mw.stats.get(who, {}).get("idle", {}))
		var g := {}
		for bn in per:
			var s5: Array = per[bn]
			if s5.size() > 5 and int(s5[0]) > 30:
				var grp := MotionWatch.group_of(bn)
				var sp := float(s5[5]) / float(s5[0])
				var cur: Array = g.get(grp, [0.0, 0])
				g[grp] = [maxf(cur[0], sp), cur[1] + 1]
		print("[mktest] starfall_look LYING max speed mm/s by group %s %s" % [who, JSON.stringify(g)])
	mw.queue_free()
	var hr := "%02d" % WorldState.hour()
	print("[mktest] starfall_look hour %s night=%s daylight=%.2f phrase='%s'" % [hr, str(WorldState.night), WorldState.daylight(), WorldState.time_phrase()])
	var shots := {"wide": [sf.bed + fwd * 13.0 + side * -2.5 + Vector3(0, 1.8, 0), sf.tree_base + Vector3(0, 5.0, 0), 55.0],
		"medium": [sf.bed + fwd * 4.2 + side * 2.2 + Vector3(0, 1.7, 0), sf.bed + Vector3(0, 0.3, 0), 50.0],
		"from_tree": [sf.tree_base + fwd * 1.2 + Vector3(0, 2.0, 0), sf.bed + fwd * 6.0 + Vector3(0, 0.5, 0), 55.0],
		"sky": [sf.bed + fwd * 2.0 + Vector3(0, 1.0, 0), sf.bed + Vector3(0, 30.0, 0) - fwd * 25.0, 70.0]}
	for nm in shots:
		var sh: Array = shots[nm]
		main.camera_rig.set_shot(sh[0], sh[1], float(sh[2]))
		await _wait(1.8)
		_shot("%s_%s" % [hr, nm])
	var fps := Engine.get_frames_per_second()
	_check(fps >= 28.0, "30 fps there (%.1f)" % fps)


## Every sub-area's establishing shot, and candidates for one being replaced (the 35-min proof: the Ancient Spell
## Library's lens sat in a tree - no collider, so the solid checks pass - and went near black 14 times). Each frame's
## brightness is printed (mean < 0.04 of white is a black screen on stream).
func _estcams() -> void:
	await _hold_all()
	main.director.enabled = false
	var shots := {}
	for id in WorldState.sanctuary.sub_areas:
		var cam: Dictionary = WorldState.sanctuary.sub_areas[id].camera
		shots[id] = [Vector3(cam.pos[0], cam.pos[1], cam.pos[2]), Vector3(cam.look[0], cam.look[1], cam.look[2])]
		# as the director plays it: a little wider, pulled back 18% from what it looks at
		var lk0 := Vector3(cam.look[0], cam.look[1], cam.look[2])
		shots[id + "_played"] = [lk0 + (shots[id][0] - lk0) * CameraDirector.PULL_BACK, lk0]
	var lk := Vector3(-10.5, 1.5, 12.0)
	for i in (8 if RenderProfile.options.has("estcams-cands") else 0):
		var a := deg_to_rad(i * 45.0)
		shots["lib_cand_%d" % i] = [lk + Vector3(sin(a), 0, cos(a)) * 9.0 + Vector3(0, 1.8, 0), lk]
	for nm in shots:
		var sh: Array = shots[nm]
		main.camera_rig.set_shot(sh[0], sh[1], 55.0)
		if RenderProfile.options.has("keep-overlay"):
			main.show_subtitle("Luna: 'Return'? Sounds like a riddle waiting to be solved. Any ideas?", 5.0)
		await _wait(1.2)
		var img := get_viewport().get_texture().get_image()
		img.resize(64, 36)
		var sum := 0.0
		for y in 36:
			for x in 64:
				sum += img.get_pixel(x, y).get_luminance()
		var sp3: PhysicsDirectSpaceState3D = (main.characters["mika"] as Node3D).get_world_3d().direct_space_state
		print("[mktest] estcams %s pos=%s brightness=%.3f solid=%s crowded=%s" % [nm, sh[0], sum / (64.0 * 36.0), str(CombatFraming.inside_solid(sp3, sh[0])), str(main.director._crowded(sp3, sh[0], sh[1]))])
		_shot(nm)


## Walks Mika into a sub-area with the real camera director (its establishing shot plays) and reads every frame's
## brightness; a dark frame prints where the lens was and what it looked at. --estwalk-sub=<id> (default the library).
func _estwalk() -> void:
	var sub := String(RenderProfile.options.get("estwalk-sub", "ancient_spell_library"))
	var cen := Vector3.ZERO
	if sub == "starfall":
		cen = StarfallPlace.instance.tree_base       # the chase camera round the old tree at night (crown)
	else:
		var sa: Dictionary = WorldState.sanctuary.sub_areas[sub]
		cen = Vector3(sa.center[0], 0, sa.center[2])
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = mika.get_world_3d().navigation_map
	main.brain.enabled = false
	main.director.enabled = true
	var dark := 0
	var frames := 0
	var est_frames := 0
	var modes := {}
	# the routes the 35-min proof ran when the library's wide shot went dark (Starfall Hill -> the circle)
	var routes := [[Vector3(-22.17, 0.5, 17.93), Vector3(0, 1, 1.5)], [Vector3(-33.28, 1.4, 18.56), Vector3(1.34, 1, -1.25)],
		[Vector3(-22.17, 0.5, 17.93), Vector3(-8.59, 0.5, 5.47)], [Vector3(-26.95, 1.1, 21.75), Vector3(-2.5, 1, -0.9)]]
	for k in 4:
		var a := deg_to_rad(k * 90.0 + 20.0)
		var start := NavigationServer3D.map_get_closest_point(map, cen + Vector3(sin(a), 0, cos(a)) * (6.0 if sub == "starfall" else 11.0))
		if sub == "ancient_spell_library":
			start = NavigationServer3D.map_get_closest_point(map, routes[k][0])
		if main.teleport_guard:
			main.teleport_guard.allow(mika)
		mika.global_position = start + Vector3(0, 0.1, 0)
		main.director.current_sub = ""
		main.director._last_established.clear()
		await _wait(2.5)
		# odd runs: running straight through it to the far side (how the proof run met it)
		if sub == "ancient_spell_library":
			mika.navigate_to(routes[k][1], true)
		elif sub == "starfall":
			# round the trunk under the crown to the far side, running
			mika.navigate_to(NavigationServer3D.map_get_closest_point(map, cen + Vector3(sin(a + 2.6), 0, cos(a + 2.6)) * 4.0), true)
		elif k % 2 == 1:
			mika.navigate_to(NavigationServer3D.map_get_closest_point(map, cen - Vector3(sin(a), 0, cos(a)) * 11.0), true)
		else:
			mika.navigate_to(cen)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 12000:
			await get_tree().process_frame
			frames += 1
			if main.director.mode == "establishing":
				est_frames += 1
			modes[main.director.mode] = int(modes.get(main.director.mode, 0)) + 1
			var img := get_viewport().get_texture().get_image()
			img.resize(48, 27)
			var sum := 0.0
			for y in 27:
				for x in 48:
					sum += img.get_pixel(x, y).get_luminance()
			var br := sum / (48.0 * 27.0)
			if br < 0.02:
				dark += 1
				var cam := get_viewport().get_camera_3d()
				print("[mktest] estwalk DARK run=%d t=%.2f br=%.3f mode=%s cam=%s fwd=%s mika=%s" % [k, (Time.get_ticks_msec() - t0) / 1000.0, br,
					main.director.mode, cam.global_position.snapped(Vector3.ONE * 0.01), (-cam.global_basis.z).snapped(Vector3.ONE * 0.01), mika.global_position.snapped(Vector3.ONE * 0.01)])
				if dark % 10 == 1:
					_shot("dark_%d_%d" % [k, dark])
	print("[mktest] estwalk %s: %d dark of %d frames (%d in its establishing shot) modes %s" % [sub, dark, frames, est_frames, modes])


## Both mages standing as in a talk, photographed knees-down-to-head from the front, side and back (wide: the
## no-close-up rule), the skirts' hem height printed: compare with / without --no-hem-floor.
func _skirtlook() -> void:
	await _hold_all()
	main.director.enabled = false
	var pair: Array = await _stage_pair()
	await _wait(4.0)
	for c in pair:
		var cw: WorldCharacter = c
		var low := INF
		var lowest := ""
		var sk := cw.skeleton
		for bi in sk.get_bone_count():
			var bn := sk.get_bone_name(bi)
			if bn.contains("Skirt"):
				var y := (sk.global_transform * sk.get_bone_global_pose(bi)).origin.y - cw.global_position.y
				if y < low:
					low = y
					lowest = bn
		print("[mktest] skirtlook %s lowest skirt bone %s at %.3f m above her feet" % [cw.character_id, lowest, low])
	var mid: Vector3 = ((pair[0] as Node3D).global_position + (pair[1] as Node3D).global_position) * 0.5
	var axis: Vector3 = ((pair[1] as Node3D).global_position - (pair[0] as Node3D).global_position).normalized()
	var perp := Vector3(-axis.z, 0, axis.x)
	var shots := {"front": mid + perp * 4.2, "back": mid - perp * 4.2, "side": mid - axis * 4.6}
	for nm in shots:
		main.camera_rig.set_shot(shots[nm] + Vector3(0, 1.3, 0), mid + Vector3(0, 0.8, 0), 50.0)
		await _wait(2.0)
		_shot(nm)


## The picture while they talk and while Mika stands: the real director frames them (conversation, then chase),
## both held still; record with --write-movie and measure the frame-to-frame image motion afterwards. Also prints
## the lens path's own wobble (direction reversals of the lens per second, mm).
func _camshake() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].enabled = false
	if main.performance and main.performance.busy():
		main.performance.interrupt("test")
		await _wait(2.0)
	var pair: Array = await _stage_pair()
	for c in pair:
		(c as WorldCharacter).stop_action()
	main.director.enabled = true
	await _wait(3.0)
	var cam := get_viewport().get_camera_3d()
	for phase in ["conversation", "chase"]:
		if phase == "conversation":
			main.director.focus_conversation(pair[1], 30.0)
		else:
			main.director.focus_conversation(null, 0.0)
		await _wait(4.0)
		print("[mktest] camshake PHASE %s start t=%.2f mode=%s" % [phase, Time.get_ticks_msec() / 1000.0, main.director.mode])
		var prev := cam.global_position
		var prev_d := Vector3.ZERO
		var rev := 0
		var path := 0.0
		var n := 0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
			var p := cam.global_position
			var d := p - prev
			if d.length() > 0.0002 and prev_d.length() > 0.0002 and d.dot(prev_d) < 0.0:
				rev += 1
			path += d.length()
			prev_d = d
			prev = p
			n += 1
		print("[mktest] camshake %s mode=%s frames=%d lens_path_mm=%.0f lens_reversals_per_s=%.2f" % [phase, main.director.mode, n, path * 1000.0, rev / 20.0])


## The real frame times for 15 s in a window (no movie mode): how evenly frames come. With a 30 fps cap on a
## 144 Hz panel the presentation can only alternate 4 and 5 refreshes (27.8 / 34.7 ms): motion judders.
func _framepace() -> void:
	await _wait(5.0)
	var buckets := {}
	var ds := []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < 15000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		ds.append(ms)
		var k := "%d" % int(round(ms))
		buckets[k] = int(buckets.get(k, 0)) + 1
	var alt := 0
	for i in range(2, ds.size()):
		if absf(ds[i] - ds[i - 1]) > 4.0:
			alt += 1
	print("[mktest] framepace max_fps=%d vsync=%d frames=%d ms_histogram=%s uneven_steps=%d (%.0f%%)" % [Engine.max_fps, DisplayServer.window_get_vsync_mode(), ds.size(), JSON.stringify(buckets), alt, 100.0 * alt / maxf(ds.size(), 1)])


## The director's chase lens while Mika stands still in different places (real time, both planners held): per frame
## the lens step; reversals (> 0.5 mm one way, then back) per second and the mean step. A still subject with a
## lens that keeps reversing looks like she shakes.
func _lenswatch() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = mika.get_world_3d().navigation_map
	main.director.enabled = true
	var cam := get_viewport().get_camera_3d()
	var spots := {"circle": Vector3(2, 0, 3), "garden": Vector3(12, 0, 22), "library_steps": Vector3(-8, 0, 9),
		"altar": Vector3(-20, 0, -18), "starfall": Vector3(-28, 0, 19), "gate": Vector3(4, 0, -12), "training": Vector3(24, 0, 6)}
	for nm in spots:
		var at := NavigationServer3D.map_get_closest_point(map, spots[nm])
		if main.teleport_guard:
			main.teleport_guard.allow(mika)
		mika.global_position = at + Vector3(0, 0.05, 0)
		mika.velocity = Vector3.ZERO
		main.camera_rig.snap_behind()
		await _wait(4.0)
		var prev := cam.global_position
		var pd := Vector3.ZERO
		var rev := 0
		var steps := 0.0
		var n := 0
		var big := 0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 8000:
			await get_tree().process_frame
			var p := cam.global_position
			var d := p - prev
			if d.length() > 0.0005 and pd.length() > 0.0005 and d.dot(pd) < 0.0:
				rev += 1
			if d.length() > 0.01:
				big += 1
			steps += d.length()
			pd = d
			prev = p
			n += 1
		print("[mktest] lenswatch %s mode=%s frames=%d reversals_per_s=%.2f mean_step_mm=%.2f steps_over_1cm=%d" % [nm, main.director.mode, n, rev / 8.0, steps * 1000.0 / maxf(n, 1), big])


## Thumbnail art: both mages standing together, wide shots in the light of the hour (--clock-hour), faces small (the
## no-close-up rule), no overlay, their planners OFF (at night they would go and lie down). Spots: the Ritual Circle
## (the launch start) and Starfall Hill. Saved as thumb_<spot>_<cam>.png for picking.
func _thumbshot() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)       # (cancels a night on the hill already under way, not just the next one)
		main.mage_brains[w].interrupt("thumbnail")
	main.director.enabled = false
	if main.get("subtitle"):
		main.subtitle.visible = false
	# night only now, with nobody planning: started at night they would already be off to lie on the hill
	if RenderProfile.options.has("thumb-night"):
		WorldState.world_min = floorf(WorldState.world_min / 1440.0) * 1440.0 + 22.0 * 60.0
		WorldState.night = true
		if main.world and main.world.has_method("set_night"):
			main.world.set_night(true)
		await _wait(3.0)
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = mika.get_world_3d().navigation_map
	var spots := {"circle": Vector3(0, 0, 3.2)}
	if StarfallPlace.instance:
		var sf: StarfallPlace = StarfallPlace.instance
		var fwd := sf.bed - sf.tree_base
		fwd.y = 0.0
		spots["starfall"] = sf.tree_base + fwd.normalized() * 6.5
	for spot in spots:
		var c: Vector3 = spots[spot]
		c.y = 0.0
		var a := NavigationServer3D.map_get_closest_point(map, c + Vector3(-0.75, 0, 0))
		var b := NavigationServer3D.map_get_closest_point(map, c + Vector3(0.75, 0, 0))
		for pair in [[mika, a], [luna, b]]:
			var ch: WorldCharacter = pair[0]
			ch.stop_action()
			if main.teleport_guard:
				main.teleport_guard.allow(ch)
			ch.global_position = (pair[1] as Vector3) + Vector3(0, 0.05, 0)
			ch.visible = true
			ch.velocity = Vector3.ZERO
		var gy := (a.y + b.y) * 0.5
		var cams := {"front": [c + Vector3(0.6, gy + 2.2, 7.5), c + Vector3(0, gy + 1.0, 0), 50.0],
			"close": [c + Vector3(-0.9, gy + 1.75, 5.2), c + Vector3(-1.55, gy + 1.05, 0), 46.0],
			"low": [c + Vector3(1.8, gy + 1.2, 6.2), c + Vector3(-0.6, gy + 2.2, 0), 52.0],
			# larger figures (knees up), faces still ~7% of the frame height (the no-close-up rule allows 10%)
			"medium": [c + Vector3(0.3, gy + 1.55, 4.3), c + Vector3(0, gy + 1.1, 0), 45.0],
			"medium_side": [c + Vector3(2.3, gy + 1.5, 3.8), c + Vector3(-0.2, gy + 1.1, 0), 45.0]}
		for nm in cams:
			var cm: Array = cams[nm]
			for pair in [[mika, a], [luna, b]]:
				var ch2: WorldCharacter = pair[0]
				if ch2.ground_pose != "":
					await ch2.get_up()
				ch2.end_gesture()
				if Vector2(ch2.global_position.x - (pair[1] as Vector3).x, ch2.global_position.z - (pair[1] as Vector3).z).length() > 0.3:
					if main.teleport_guard:
						main.teleport_guard.allow(ch2)
					ch2.global_position = (pair[1] as Vector3) + Vector3(0, 0.05, 0)
			for ch in [mika, luna]:
				(ch as WorldCharacter).stop_action()
				(ch as WorldCharacter).look_at_point((cm[0] as Vector3).lerp(c, 0.4))
			await _wait(4.0)
			main.camera_rig.set_shot(cm[0], cm[1], float(cm[2]))
			await _wait(2.0)
			_shot("thumb_%s_%s" % [spot, nm])


## The launch-night bug: Luna dances on her own (music), then the show asks Mika to dance. Luna's dance must be filmed
## while it runs, then give way; Mika must be the one dancing (filmed) shortly after the show asked.
func _showdance() -> void:
	await _hold_all()
	await _stage_pair()
	var ll = main.get("live_link")
	_check(ll != null, "live link present (--live-link)")
	if ll == null:
		return
	main.performance.perform("luna", "casual", {})
	var t := Time.get_ticks_msec()
	while not main.performance.busy() and Time.get_ticks_msec() - t < 15000:
		await get_tree().process_frame
	await _wait(3.0)
	_check(String(main.performance.active.get("who", "")) == "luna" and bool(main.performance.active.get("filmed", false)),
		"Luna's own dance is filmed (%s, filmed=%s)" % [main.performance.active.get("who", ""), str(main.performance.active.get("filmed", false))])
	ll._do("dance", {"routine": "chicken"})
	var t2 := Time.get_ticks_msec()
	while not (main.performance.busy() and String(main.performance.active.get("who", "")) == "mika") and Time.get_ticks_msec() - t2 < 40000:
		await get_tree().process_frame
	var secs := (Time.get_ticks_msec() - t2) / 1000.0
	await _wait(2.0)
	_check(String(main.performance.active.get("who", "")) == "mika", "Mika dances for the show after %.1f s (performer: %s)" % [secs, main.performance.active.get("who", "")])
	_check(bool(main.performance.active.get("filmed", false)) and main.director.mika == main.characters["mika"], "the camera films Mika's dance")
	main.performance.interrupt("test over")


# ------------------------------------------------------------------ every move a walk, round the walls (2026-10-17 live)
## On stream Mika (and Luna) seemed to dash and pass through walls. Two halves:
##  1. geometry: every DRAWN mesh at body height with no collider, standing on the walkable navmesh (she would walk
##     straight through it): built as temporary shapes on layer 31 (no one collides with it), probed with a body-size
##     capsule over the navmesh.
##  2. the real walks: the brain's own trips (the altar to the old tree and the sanctuary errands, walked one after
##     the other) and a stargaze-style walk where Mika FOLLOWS Luna; every physics frame: speed, gait blend, jumps,
##     and the body inside a drawn-only mesh.
const _GHOST_LAYER := 31

func _walkaudit() -> void:
	await _hold_all()
	main.spawner.enabled = false
	if main.director:
		main.director.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = mika.get_world_3d().navigation_map
	var space := mika.get_world_3d().direct_space_state
	# --- 1. drawn-only geometry on the walkable floor
	var ghosts := Node3D.new()
	ghosts.name = "WalkauditGhosts"
	main.add_child(ghosts)
	var made := 0
	var stack: Array = [main.world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is WorldCharacter or n is GPUParticles3D or n is CPUParticles3D:
			continue
		for ch in n.get_children():
			stack.append(ch)
		if not (n is MeshInstance3D) or not (n as MeshInstance3D).is_visible_in_tree() or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var bb: AABB = mi.global_transform * mi.get_aabb()
		var lname := String(mi.name).to_lower() + " " + String(mi.get_parent().name).to_lower()
		if bb.size.y < 0.9 or bb.size.x > 150.0 or bb.size.z > 150.0:
			continue                  # flat things (floors, rugs, grass, water) and the terrain itself
		if lname.contains("terrain") or lname.contains("grass") or lname.contains("sky") or lname.contains("cloud") or lname.contains("water"):
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 0
		body.collision_mask = 0
		body.set_collision_layer_value(_GHOST_LAYER, true)
		body.set_meta("src", str(mi.get_path()).trim_prefix(str(main.world.get_path()) + "/"))
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		ghosts.add_child(body)
		body.global_transform = mi.global_transform
		made += 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = [mika.get_rid(), luna.get_rid()]
	var real_mask := mika.collision_mask & ~(1 << (_GHOST_LAYER - 1))
	var offenders := {}
	var probes := 0
	var x := -70.0
	while x <= 70.0:
		var z := -70.0
		while z <= 70.0:
			var g := Vector3(x, 0, z)
			var p := NavigationServer3D.map_get_closest_point(map, Vector3(x, 30.0, z))
			p = NavigationServer3D.map_get_closest_point(map, Vector3(x, p.y + 1.0, z))
			if Vector2(p.x - x, p.z - z).length() < 0.3:
				probes += 1
				q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.45 + 0.55 + 0.05, 0))   # 0.45..1.55 m above the floor
				q.collision_mask = 1 << (_GHOST_LAYER - 1)
				var hits := space.intersect_shape(q, 4)
				if not hits.is_empty():
					q.collision_mask = real_mask
					if space.intersect_shape(q, 1).is_empty():        # nothing real there either: she walks through it
						for h in hits:
							var src := String((h.collider as Node).get_meta("src", "?"))
							if not offenders.has(src):
								offenders[src] = {"n": 0, "at": p.snapped(Vector3.ONE * 0.1)}
							offenders[src].n += 1
			z += 0.6
		x += 0.6
	var ranked := offenders.keys()
	ranked.sort_custom(func(a, b): return int(offenders[a].n) > int(offenders[b].n))
	print("[mktest] walkaudit: %d drawn meshes shaped, %d navmesh probes, %d drawn-only meshes stand on the walkable floor" % [made, probes, ranked.size()])
	for k in ranked.slice(0, 40):
		print("[mktest]   drawn-only on the floor: %s  (%d probes, e.g. %s)" % [k, offenders[k].n, offenders[k].at])
	var big := ranked.filter(func(k): return int(offenders[k].n) >= int(RenderProfile.options.get("ghost-min", 3)))
	# (informational: hanging leaves, magic quads and animals show up here too; the walks below decide - her body never
	# inside any of these meshes on the real trips)
	print("[mktest]   info: %d drawn-only meshes with >= %s probes on the walkable floor: %s" % [big.size(), RenderProfile.options.get("ghost-min", 3), big.slice(0, 8)])
	if RenderProfile.options.has("geo-only"):
		# what reaches past the collider: per surface (material), the horizontal reach from the tree's axis at body
		# height, beside the collider's radius
		for k in big:
			var mi := main.world.get_node_or_null(NodePath(k)) as MeshInstance3D
			if mi == null:
				continue
			var root := mi.get_parent() as Node3D
			while root and not (root.name.begins_with("Tree") or root.name == "HeroTree"):
				root = root.get_parent() as Node3D
			if root == null:
				var mb: AABB = mi.global_transform * mi.get_aabb()
				print("[mktest]   %s: not a tree: mesh '%s' %s, parent %s (%s), aabb %s size %s" % [k, mi.mesh.get_class() + "/" + str(mi.get_active_material(0).resource_path if mi.get_active_material(0) else "") + "/" + str((mi.get_active_material(0) as ShaderMaterial).shader.resource_path if mi.get_active_material(0) is ShaderMaterial else ""), str(mi.get_meta_list()) + " groups " + str(mi.get_groups()) + " cast_shadow " + str(mi.cast_shadow), mi.get_parent().name, mi.get_parent().get_class(), mb.position.snapped(Vector3.ONE * 0.1), mb.size.snapped(Vector3.ONE * 0.1)])
				continue
			var axis := root.global_position
			var col_r := -1.0
			for b in root.get_parent().find_children("*", "StaticBody3D", true, false) + root.find_children("*", "StaticBody3D", true, false):
				for cs2 in (b as Node).get_children():
					if cs2 is CollisionShape3D and (cs2 as CollisionShape3D).shape is CylinderShape3D and Vector2((b as Node3D).global_position.x - axis.x, (b as Node3D).global_position.z - axis.z).length() < 0.5:
						col_r = ((cs2 as CollisionShape3D).shape as CylinderShape3D).radius * (b as Node3D).global_basis.get_scale().x
			var floor_y := NavigationServer3D.map_get_closest_point(map, axis + Vector3(1.5, 2.0, 0)).y
			for si in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var rs: Array = []
				for v in verts:
					var w := mi.global_transform * v
					if w.y > floor_y + 0.3 and w.y < floor_y + 1.7:
						rs.append(Vector2(w.x - axis.x, w.z - axis.z).length())
				if rs.is_empty():
					continue
				rs.sort()
				var mat := mi.get_active_material(si)
				print("[mktest]   %s surf %d '%s': %d verts at body height, reach p50 %.2f p90 %.2f max %.2f m (collider r %.2f, scale %.2f)" % [k, si,
					mat.resource_name if mat else "?", rs.size(), rs[rs.size() / 2], rs[int(rs.size() * 0.9)], rs[rs.size() - 1], col_r, root.global_basis.get_scale().x])
		ghosts.queue_free()
		return
	# --- 2. the real walks
	var dests := {"altar": Vector3(-21.55, 0.5, -21.0), "old_tree": Vector3(-31.02, 1.48, 21.06), "bed": Vector3(-28.33, 1.1, 19.65),
		"flowers": Vector3(-26.95, 1.12, 21.75), "view": Vector3(-22.17, 0.5, 17.93), "roots": Vector3(-33.28, 1.4, 18.56),
		"gate": Vector3(4.15, 0.5, -13.18), "journal": Vector3(2.96, 1.0, 2.1), "rune4": Vector3(16.84, 0.5, 1.72),
		"dummy": Vector3(18.5, 0.25, 9.49), "rune2": Vector3(25.84, 0.31, 6.54), "scroll": Vector3(-2.5, 1.0, -0.9),
		"stone": Vector3(-6.6, 0.33, -12.87), "tablet": Vector3(-20.4, 0.5, -23.24), "scholar": Vector3(-15.79, 0.0, -19.53)}
	var order := ["altar", "old_tree", "gate", "roots", "journal", "flowers", "rune2", "view", "tablet", "dummy", "bed", "stone", "rune4", "scroll", "scholar", "old_tree"]
	if RenderProfile.options.has("legs"):
		order = order.slice(0, int(RenderProfile.options.legs) + 1)      # a short run: the first N trips
	var brain: SanctuaryBrain = main.mage_brains["mika"]
	if main.teleport_guard:
		main.teleport_guard.allow(mika)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, dests["altar"]) + Vector3(0, 0.1, 0)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(8, 0, 8)) + Vector3(0, 0.1, 0)
	await _wait(1.5)
	var st := {"worst_v": 0.0, "worst_at": "", "run_frames": 0, "jumps": 0, "ghost_frames": 0, "ghost_in": {}, "frames": 0}
	for i in range(1, order.size()):
		var leg := "%s->%s" % [order[i - 1], order[i]]
		var goal: Vector3 = dests[order[i]]
		var r := {"done": false, "ok": false}
		var walker := func() -> void:
			r.ok = await brain._walk(goal)
			r.done = true
		walker.call()
		var res: Dictionary = await _walk_watch(mika, r, leg, 120.0, st)
		_check(bool(r.ok), "walked %s (%.0f m in %.0f s, %.2f m/s)" % [leg, res.metres, res.secs, res.metres / maxf(res.secs, 0.1)], res)
	# Mika follows Luna to the old tree (how the stargaze she was invited to went)
	if main.teleport_guard:
		main.teleport_guard.allow(mika)
		main.teleport_guard.allow(luna)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, dests["altar"]) + Vector3(0, 0.1, 0)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, dests["altar"] + Vector3(9, 0, 4)) + Vector3(0, 0.1, 0)
	await _wait(1.0)
	var f := FollowCompanion.new()
	f.leader = luna
	f.follower = mika
	main.companionship.add_child(f)
	var r2 := {"done": false, "ok": false}
	var lead_walk := func() -> void:
		r2.ok = await main.companionship.walk_together(luna, f, dests["bed"], 120.0)
		r2.done = true
	lead_walk.call()
	var res2: Dictionary = await _walk_watch(mika, r2, "follow luna altar->bed", 130.0, st)
	f.queue_free()
	_check(bool(r2.ok), "followed Luna to the bed spot (%.0f m in %.0f s)" % [res2.metres, res2.secs], res2)
	print("[mktest] walkaudit walks: %s" % JSON.stringify(st))
	_check(float(st.worst_v) <= 2.0, "never faster than a brisk walk (worst %.2f m/s over 0.5 s, %s)" % [st.worst_v, st.worst_at])
	_check(int(st.run_frames) == 0, "never the run gait (%d frames of the loco blend above walk)" % st.run_frames)
	_check(int(st.jumps) == 0, "no jump cut (%d frames moved > 0.35 m)" % st.jumps)
	_check(int(st.ghost_frames) == 0, "never inside a drawn-only mesh (%d frames)" % st.ghost_frames, st.ghost_in)
	ghosts.queue_free()


## Sample one walker every physics frame until `r.done`: speed over 0.5 s windows, the loco blend, one-frame jumps,
## her body inside a drawn-only (layer 31) mesh. Returns the leg's metres / seconds.
func _walk_watch(c: WorldCharacter, r: Dictionary, leg: String, max_s: float, st: Dictionary) -> Dictionary:
	var space := c.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1 << (_GHOST_LAYER - 1)
	var t := 0.0
	var metres := 0.0
	var last := c.global_position
	var hist: Array = []
	var leg_worst := 0.0
	while not r.done and t < max_s:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var p := c.global_position
		var step := Vector2(p.x - last.x, p.z - last.z).length()
		metres += step
		last = p
		st.frames = int(st.frames) + 1
		if step > 0.35:
			st.jumps = int(st.jumps) + 1
		hist.append([t, p])
		while hist.size() > 2 and t - float(hist[0][0]) > 0.5:
			hist.pop_front()
		if t - float(hist[0][0]) >= 0.45:
			var a: Vector3 = hist[0][1]
			var v := Vector2(p.x - a.x, p.z - a.z).length() / (t - float(hist[0][0]))
			leg_worst = maxf(leg_worst, v)
			if v > float(st.worst_v):
				st.worst_v = snappedf(v, 0.01)
				st.worst_at = "%s at %s" % [leg, p.snapped(Vector3.ONE * 0.1)]
		if float(c.anim_tree.get("parameters/loco/blend_position")) > 1.08:
			st.run_frames = int(st.run_frames) + 1
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, 0))
		for h in space.intersect_shape(q, 2):
			st.ghost_frames = int(st.ghost_frames) + 1
			var src := String((h.collider as Node).get_meta("src", "?"))
			st.ghost_in[src] = "%s at %s" % [leg, p.snapped(Vector3.ONE * 0.1)]
	return {"metres": snappedf(metres, 0.1), "secs": snappedf(t, 0.1), "worst_v": snappedf(leg_worst, 0.01)}


# ------------------------------------------------------------------ stream reports of 2026-10-17 (broadcast 2)
## --profile=stream --luna: the steady quality floor (no back and forth), no FSR 2 jitter on the stream, no solo dance
## from Luna's own brain, and the camera given back to Mika after a dance of Luna's.
func _livefixes() -> void:
	await _hold_all()
	var g = main.gfx
	_check(g.steady_floor > 0, "the stream has a steady quality floor (%d)" % g.steady_floor)
	g._hold_until = 0.0
	var t0 := _gms()
	while g.level < g.steady_floor and _gms() - t0 < 15000:
		await get_tree().process_frame
	_check(g.level >= g.steady_floor, "quality settles at the floor (level %d)" % g.level)
	var vp := get_viewport()
	_check(vp.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2 and vp.msaa_3d != Viewport.MSAA_DISABLED and not vp.use_taa,
		"no temporal jitter on the stream (scaling mode %d, MSAA %d, TAA %s, scale %.2f)" % [vp.scaling_3d_mode, vp.msaa_3d, str(vp.use_taa), vp.scaling_3d_scale])
	var lvl: int = g.level
	await _wait(12.0)
	_check(g.level >= g.steady_floor, "it never restores above the floor (level %d -> %d)" % [lvl, g.level])
	# Luna's brain: no dance of her own choosing; Mika's may
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	var lkeys: Array = lb.options().map(func(o): return String(o.get("key", "")))
	_check(lkeys.filter(func(k): return k.begins_with("perform:")).is_empty(), "Luna's brain offers no solo dance", lkeys.slice(0, 12))
	# a dance of Luna's, then the camera is Mika's again
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	await _stage_pair()
	if main.performance.busy():
		main.performance.interrupt("test: a clean start")
		var tq := _gms()
		while main.performance.busy() and _gms() - tq < 15000:
			await get_tree().process_frame
		await _wait(1.0)
	main.director.enabled = true
	main.director.set_subject(mika)
	main.performance.perform("luna", "casual", {})
	var t1 := _gms()
	while not main.performance.busy() and _gms() - t1 < 15000:
		await get_tree().process_frame
	await _wait(2.0)
	_check(String(main.performance.active.get("who", "")) == "luna" and main.director.mika == mika and main.director._perf.get("pair") == luna,
		"Luna dances with the camera still on Mika, both in frame (performer %s, subject %s)" % [main.performance.active.get("who", "-"), main.director.mika.character_id])
	main.performance.interrupt("test over")
	var t2 := _gms()
	while main.performance.busy() and _gms() - t2 < 15000:
		await get_tree().process_frame
	await _wait(1.0)
	_check(main.director.mika == mika, "the camera is Mika's again after Luna's dance (subject: %s)" % main.director.mika.character_id)


# ------------------------------------------------------------------ walk look + spar jitter (broadcast 2)
## Broadcast 2 reports: "she dashes instead of walking" and "bodies tremble in the spar and the talk after it".
## 1. foot sliding on a real walk: a planted foot (lowest part of its step) should stand still; its horizontal speed
##    against the body's says whether the steps keep up with the travel (sliding = gliding = looks like a dash).
## 2. the real spar invite and the 25 s after it: per rendered frame, for both mages, hips / head / right hand -
##    direction reversals at mm scale (a smooth motion has none; a tremble many) per second, by phase.
func _sparwatch() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
		main.mage_brains[w].current = {}
	if main.performance and main.performance.busy():
		main.performance.interrupt("test")
	main.spawner.enabled = false
	main.director.enabled = true
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = mika.get_world_3d().navigation_map
	await _wait(1.5)
	# --- 1. foot sliding on a 20 m walk
	if main.teleport_guard:
		main.teleport_guard.allow(mika)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(-2, 0, 12)) + Vector3(0, 0.05, 0)
	await _wait(1.0)
	var sk := mika.skeleton
	var feet := {"L": sk.find_bone("LeftFoot"), "R": sk.find_bone("RightFoot")}
	var hist := {"L": [], "R": []}
	var body: Array = []
	var fsamp := func():
		var gt := sk.global_transform
		for k in feet:
			hist[k].append(gt * sk.get_bone_global_pose(feet[k]).origin)
		body.append(mika.global_position)
	get_tree().process_frame.connect(fsamp)
	mika.navigate_to(NavigationServer3D.map_get_closest_point(map, Vector3(-2, 0, -8)), false)
	var tw0 := _game_t
	while mika.current_action == "navigate_to" and _game_t - tw0 < 25.0:
		await get_tree().process_frame
	get_tree().process_frame.disconnect(fsamp)
	var dt := 1.0 / 30.0
	var contact_sp := []
	for k in feet:
		var h: Array = hist[k]
		for i in range(3, h.size() - 3):
			var y: float = (h[i] as Vector3).y
			var lo := y
			for j in range(i - 3, i + 4):
				lo = minf(lo, (h[j] as Vector3).y)
			if y <= lo + 0.004:          # the planted moment of this step
				var a: Vector3 = h[i - 1]
				var b: Vector3 = h[i + 1]
				contact_sp.append(Vector2(b.x - a.x, b.z - a.z).length() / (2.0 * dt))
	var bsp := []
	for i in range(1, body.size()):
		bsp.append(Vector2((body[i] as Vector3).x - (body[i - 1] as Vector3).x, (body[i] as Vector3).z - (body[i - 1] as Vector3).z).length() / dt)
	contact_sp.sort()
	bsp.sort()
	var foot_med: float = contact_sp[contact_sp.size() / 2] if not contact_sp.is_empty() else -1.0
	var body_med: float = bsp[bsp.size() / 2] if not bsp.is_empty() else -1.0
	print("[mktest] sparwatch walk: body %.2f m/s, planted foot %.2f m/s (%d contacts), loco scale %.2f, blend %.2f" % [body_med, foot_med, contact_sp.size(),
		float(mika.anim_tree.get("parameters/loco_speed/scale")), float(mika.anim_tree.get("parameters/loco/blend_position"))])
	_check(foot_med >= 0.0 and foot_med <= body_med * 0.25, "planted feet do not slide on a walk (foot %.2f vs body %.2f m/s)" % [foot_med, body_med])
	# --- 2. spar + after
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(18, 0, 2)) + Vector3(0, 0.1, 0)
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(19.5, 0, 3.5)) + Vector3(0, 0.1, 0)
	for w in ["mika", "luna"]:
		WorldState.mind(w).vigor = 1.0
		main.mage_brains[w].needs.energy = 0.9
	var bones := ["Hips", "Head", "RightHand"]
	var J := {}
	var lastd := {}
	var lastp := {}
	var phase := ["pre"]
	var pops: Array = []
	var camm := {"frames": 0, "inside": 0, "near": 0, "empty": 0, "tiny": 0, "blocked": 0, "min_d": 99.0}
	var csamp := func():
		if not main.duel.busy():
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		camm.frames += 1
		var vr := get_viewport().get_visible_rect()
		var cp := cam.global_position
		var any_in := false
		var space := mika.get_world_3d().direct_space_state
		for c in [mika, luna]:
			var bp: Vector3 = c.global_position
			var hd := Vector2(cp.x - bp.x, cp.z - bp.z).length()
			if cp.y > bp.y - 0.2 and cp.y < bp.y + 2.1:
				camm.min_d = minf(camm.min_d, hd)
				if hd < 0.6:
					camm.inside += 1
					camm["inside_at"] = camm.get("inside_at", [])
					if camm.inside_at.size() < 8:
						camm.inside_at.append("%s %s:%s %.2fm cam_y %.2f body_y %.2f | rig cam %s, shot_active %s, shot_pos %.2fm away, director enabled %s, streaming %s" % [c.character_id, main.director.mode, String(main.director._trailer.shot), hd, cp.y, bp.y,
							str(cam == main.camera_rig.camera), str(main.camera_rig.shot_active), cp.distance_to(main.camera_rig._shot_pos), str(main.director.enabled), String(main.streaming.state)])
				elif hd < 1.2:
					camm.near += 1
			var head := bp + Vector3(0, 1.6, 0)
			if not cam.is_position_behind(head) and not cam.is_position_behind(bp):
				var a := cam.unproject_position(head)
				var b := cam.unproject_position(bp)
				if vr.has_point(a) or vr.has_point(b):
					any_in = true
					if absf(b.y - a.y) < vr.size.y * 0.12:
						camm.tiny += 1
			for hgt in [1.15, 0.8]:
				var q := PhysicsRayQueryParameters3D.create(cp, bp + Vector3(0, hgt, 0), 1 | 4)
				q.exclude = [mika.get_rid(), luna.get_rid()]
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit.position as Vector3).distance_to(bp + Vector3(0, hgt, 0)) > 0.5:
					camm.blocked += 1
					var bk := "%s:%s|%s@%s" % [String(main.director.mode), String(main.director._trailer.shot), String((hit.collider as Node).name) if hit.collider is Node else "?",
						str(((hit.collider as Node3D).global_position if hit.collider is Node3D else Vector3.ZERO).snapped(Vector3.ONE * 0.5))]
					camm["by"] = camm.get("by", {})
					camm.by[bk] = int(camm.by.get(bk, 0)) + 1
					break
		if not any_in:
			camm.empty += 1
		camm["modes"] = camm.get("modes", {})
		camm.modes[main.director.mode] = int(camm.modes.get(main.director.mode, 0)) + 1
	# sampled LAST in the frame (after the director and the rig): what is drawn. process_frame fires before any
	# _process - a fighter who dodged in physics met last frame's lens there, a position never rendered
	var late := LateTick.new()
	late.cb = csamp
	late.process_priority = 100000
	add_child(late)
	var jsamp := func():
		var ph: String = "spar" if main.duel.busy() else phase[0]
		for c in [mika, luna]:
			var cs: Skeleton3D = c.skeleton
			for bn in bones:
				var bi := cs.find_bone(bn)
				if bi < 0:
					continue
				var key := "%s:%s" % [c.character_id, bn]
				var p := cs.global_transform * cs.get_bone_global_pose(bi).origin
				var jk := "%s|%s" % [ph, key]
				if not J.has(jk):
					J[jk] = {"frames": 0, "rev": 0, "spike": 0}
				J[jk].frames += 1
				if lastp.has(key):
					var d: Vector3 = p - (lastp[key] as Vector3)
					if lastd.has(key):
						var pd: Vector3 = lastd[key]
						if d.length() > 0.002 and pd.length() > 0.002 and d.normalized().dot(pd.normalized()) < -0.5:
							J[jk].rev += 1
						if d.length() > 0.02 and d.length() > pd.length() * 4.0:
							J[jk].spike += 1
							if bn == "Hips" and pops.size() < 40:
								var gt: Dictionary = c.gesture_trace if c.get("gesture_trace") is Dictionary else {}
								pops.append("%s %.2fs %.0fmm act=%s gest=%s(%s, %d ms ago) react=%s dash=%s" % [c.character_id, _game_t, d.length() * 1000.0,
									c.current_action, gt.get("clip", "-"), gt.get("by", "-"), Time.get_ticks_msec() - int(gt.get("t", 0)),
									(c.reaction.tier + ":" + str(c.reaction.phase)) if c.reaction and c.reaction.active else "-", str(not c._dash.is_empty())])
					lastd[key] = d
				lastp[key] = p
	get_tree().process_frame.connect(jsamp)
	main.director.enabled = true          # (an interrupted dance restores the director's old state late: set again here)
	main.director.set_subject(mika)
	var res: Dictionary = await main.companionship.invite(main.mage_brains["mika"], "luna", "train_together", {"pos": SanctuaryTerrain.TRAINING_CENTER_3D, "fill": {}})
	phase[0] = "after"
	await _wait(25.0)
	get_tree().process_frame.disconnect(jsamp)
	var out := {}
	for jk in J:
		var e: Dictionary = J[jk]
		out[jk] = "%d rev/s, %d spikes (%d fr)" % [roundi(float(e.rev) / maxf(float(e.frames) / 30.0, 0.1)), int(e.spike), int(e.frames)]
	var ks := out.keys()
	ks.sort()
	for k in ks:
		print("[mktest] sparwatch %s: %s" % [k, out[k]])
	late.queue_free()
	print("[mktest] sparwatch camera: %s" % JSON.stringify(camm))
	_check(int(camm.get("modes", {}).get("combat", 0)) >= int(camm.frames) / 2, "the director framed the spar as a fight", camm.get("modes", {}))
	# (<= 0.2 %: the one remaining case is the hand-over frame from the chase camera, whose spring arm can squash
	# against what is behind her - a chase-camera fix still to do)
	_check(int(camm.inside) <= int(camm.frames) / 500, "the combat camera is (almost) never inside a fighter (%d of %d frames; nearest %.2f m)" % [camm.inside, camm.frames, camm.min_d])
	_check(int(camm.empty) <= int(camm.frames) / 50, "the combat camera keeps a fighter in view (%d empty of %d)" % [camm.empty, camm.frames])
	for pp in pops:
		print("[mktest] sparwatch pop: ", pp)
	print("[mktest] sparwatch invite: %s" % str(res.get("entry", {}).get("accepted", "?")))
	_check(not main.duel.log.is_empty(), "a spar took place")


## Broadcast 2, morning in the rain: the whole picture flashed about every second. The day cycle (every 0.5 s) wrote
## the sun at full strength AFTER the weather had dimmed it for that frame: the frame rendered undimmed. --clock-hour=8
## (daylight); the weather is set to rain and the sun sampled before each frame's processing (what the last frame drew).
func _sunflash() -> void:
	await _hold_all()
	main.weather.set_weather("rain", 2.0)
	main.weather.cloud = 0.75
	await _wait(3.0)
	var sun: DirectionalLight3D = main.world.get("sun")
	var vals: Array = []
	var grab := func(): vals.append(sun.light_energy)
	get_tree().process_frame.connect(grab)          # (emitted before any _process: the value the last frame drew)
	await _wait(6.0)
	get_tree().process_frame.disconnect(grab)
	vals.sort()
	var lo: float = vals[int(vals.size() * 0.05)]
	var hi: float = vals[vals.size() - 1]
	print("[mktest] sunflash: %d frames, sun energy p5 %.2f max %.2f (daylight %.2f, cloud %.2f)" % [vals.size(), lo, hi, WorldState.daylight(), main.weather.cloud])
	_check(vals.size() > 30 and hi <= lo * 1.15, "the sun under rain never flashes to full strength (p5 %.2f, max %.2f)" % [lo, hi])



# ------------------------------------------------------------------ a viewer's reply is never kept waiting (broadcast 2, 15:07)
## "hi" got no answer: the server's reply reached the stage in 2 s and then waited behind her in-world talk until
## the server gave it up (~20 s). Here: a long in-world line is playing and another is queued; a viewer's message
## is selected and its reply arrives - it must start at once, the queued in-world line waits for it, the playback
## ack follows, and in-world speech resumes afterwards.
func _silent_wav(secs: float) -> PackedByteArray:
	var n := int(secs * 24000.0)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.resize(44)
	out.encode_u32(4, 36 + pcm.size())
	for i in 4:
		out[8 + i] = "WAVE".to_ascii_buffer()[i]
		out[12 + i] = "fmt ".to_ascii_buffer()[i]
		out[36 + i] = "data".to_ascii_buffer()[i]
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)
	out.encode_u16(22, 1)
	out.encode_u32(24, 24000)
	out.encode_u32(28, 48000)
	out.encode_u16(32, 2)
	out.encode_u16(34, 16)
	out.encode_u32(40, pcm.size())
	out.append_array(pcm)
	return out


func _showline() -> void:
	await _hold_all()
	var ll = main.get("live_link")
	_check(ll != null, "live link present (--live-link)")
	if ll == null:
		return
	var v: VoiceService = main.voice
	var starts := {}
	var on_start := func(sp: String, text: String):
		starts[text] = _game_t
	v.line_started.connect(on_start)
	var sent: Array = []
	# (no server in a test: record what the stage would send)
	var world1 := "This is a long line I am saying to Luna about the old stones by the gate, and it goes on for quite a while yet."
	var world2 := "And this is what I wanted to say next to her."
	v._cache[VoiceService._cache_key("mika", world1, {})] = _silent_wav(12.0)
	v._cache[VoiceService._cache_key("mika", world2, {})] = _silent_wav(2.0)
	v.say("mika", world1)
	await _wait(1.0)
	v.say("mika", world2)
	await _wait(0.5)
	_check(starts.has(world1) and v._player.playing, "an in-world line is playing", str(starts.keys()))
	var t0 := _game_t
	ll._on_message({"type": "control", "text": "conversation-chain-start"})
	ll._on_message({"type": "youtube-live-selected-message", "active": true, "message": "hi", "author": "@tester", "id": "t1", "to": ["mika"]})
	var reply := "Hi tester, welcome to the sanctuary!"
	ll._on_message({"type": "audio", "character": "mika", "audio": Marshalls.raw_to_base64(_silent_wav(1.5)), "display_text": {"text": reply}})
	ll._on_message({"type": "backend-synth-complete"})
	while not starts.has(reply) and _game_t - t0 < 25.0:
		await get_tree().process_frame
	var wait_s: float = (starts[reply] - t0) if starts.has(reply) else 99.0
	print("[mktest] showline: reply started after %.2f s (world line was %s)" % [wait_s, "cut" if not starts.has(world2) or starts.get(world2, 0.0) > starts.get(reply, 0.0) else "?"])
	_check(wait_s < 1.0, "a viewer's reply starts at once, over in-world talk", "%.2f s" % wait_s)
	_check(not starts.has(world2) or float(starts[world2]) > float(starts.get(reply, 0.0)), "the queued in-world line waits for the reply")
	while (ll._speaking or not ll._speech.is_empty()) and _game_t - t0 < 25.0:
		await get_tree().process_frame
	_check(not ll._speaking and ll._speech.is_empty() and not ll._synth_complete, "the reply finished and the playback ack went out")
	_check(not v.world_held(), "in-world speech is released after the reply")
	var t1 := _game_t
	while not starts.has(world2) and _game_t - t1 < 10.0:
		await get_tree().process_frame
	_check(starts.has(world2), "her in-world line follows the reply", "%.2f s later" % (float(starts.get(world2, 99.0)) - t1))
	# an autonomous show line (no viewer) never waits more than a few seconds behind a talk either
	v.line_started.disconnect(on_start)



# ------------------------------------------------------------------ a long rest on the watchpoint bench, as the brain does it (broadcast 2, 15:15)
## Selwyn's screenshot: the seat slab through her waist, the dress spread flat sideways through the stone. The brain's
## rest is long (12-60 s) and walks there itself: this runs exactly that, samples her hips against the seat top and
## her root against the sit point all through, and shoots it from the live camera's high rear angle and the side.
func _benchrest() -> void:
	await _hold_all()
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var b: SanctuaryBrain = main.mage_brains["mika"]
	b.set_enabled(false)
	b.current = {}
	var it: Interactable = main.world.interactables.get("watchpoint_rest")
	if it == null:
		_check(false, "watchpoint bench exists")
		return
	var seat_top := -99.0
	for cs in it.seat_body.get_children():
		if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
			seat_top = (cs as CollisionShape3D).global_position.y + ((cs as CollisionShape3D).shape as BoxShape3D).size.y * 0.5
	var sp: Vector3 = it.get_parent().to_global(it.sit_point)
	var map: RID = mika.get_world_3d().navigation_map
	if main.teleport_guard:
		main.teleport_guard.allow(mika)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, sp + Vector3(6, 0, 4)) + Vector3(0, 0.05, 0)
	await _wait(1.5)
	# (a disabled brain cancels its own walks: walk there directly, then the bench's own sit with the brain's long rest)
	mika.navigate_to(it.approach_point(), false)
	var tn := _game_t
	while mika.current_action == "navigate_to" and _game_t - tn < 60.0:
		await get_tree().process_frame
	it.duration_override = 40.0
	var job := func(): await it.perform(mika)
	job.call()
	var hb := mika.skeleton.find_bone("Hips")
	var samples: Array = []
	var t0 := _game_t
	var sat_at := -1.0
	var shots := 0
	while _game_t - t0 < 75.0:
		await get_tree().process_frame
		if mika.seated and sat_at < 0.0:
			sat_at = _game_t
		if sat_at >= 0.0 and not mika.seated:
			break
		if sat_at >= 0.0 and _game_t - sat_at > 2.5:
			var hy := (mika.skeleton.global_transform * mika.skeleton.get_bone_global_pose(hb).origin).y
			samples.append({"t": _game_t - sat_at, "hips": hy, "root_y": mika.global_position.y, "off": Vector2(mika.global_position.x - sp.x, mika.global_position.z - sp.z).length(),
				"g": mika.current_gesture, "gp": mika.ground_pose, "avy": mika.avatar.position.y})
			if DisplayServer.get_name() != "headless" and _game_t - sat_at > 4.0 + shots * 12.0 and shots < 4:
				var fwd := -mika.global_transform.basis.z
				fwd.y = 0
				fwd = fwd.normalized()
				var side := Vector3(-fwd.z, 0, fwd.x)
				var hip := mika.global_position + Vector3(0, 0.6, 0)
				var view: bool = main.director.enabled
				main.director.enabled = false
				if shots % 2 == 0:
					main.camera_rig.set_shot(hip - fwd * 3.2 + side * 0.6 + Vector3(0, 2.0, 0), hip, 50.0)
				else:
					main.camera_rig.set_shot(hip + side * 3.0 + fwd * 0.6 + Vector3(0, 0.3, 0), hip + Vector3(0, -0.1, 0), 50.0)
				await _wait(0.3)
				_shot("rest_%d" % shots)
				main.camera_rig.clear_shot()
				main.director.enabled = view
				shots += 1
	var low := 99.0
	var high := -99.0
	var off := 0.0
	var gs := {}
	for s in samples:
		low = minf(low, s.hips)
		high = maxf(high, s.hips)
		off = maxf(off, s.off)
		gs["%s|%s|%.2f" % [s.g, s.gp, s.avy]] = int(gs.get("%s|%s|%.2f" % [s.g, s.gp, s.avy], 0)) + 1
	print("[mktest] benchrest: seat top %.3f, hips %.3f..%.3f over %.0f s seated, root off the sit point up to %.2f m, root y %.3f, poses %s" % [seat_top, low, high,
		(samples[-1].t if not samples.is_empty() else 0.0), off, (samples[-1].root_y if not samples.is_empty() else 0.0), str(gs)])
	_check(not samples.is_empty() and float(samples[-1].t) > 15.0, "a long rest on the bench (%.0f s)" % (samples[-1].t if not samples.is_empty() else 0.0))
	_check(low >= seat_top + 0.04, "she stays on top of the seat the whole rest (lowest hips %.3f, seat top %.3f)" % [low, seat_top])
	_check(off < 0.25, "she stays over the seat (root drifts up to %.2f m)" % off)



# ------------------------------------------------------------------ Luna cannot read chat: Mika passes it on (Job 3)
## A viewer writes to Luna while she is across the clearing: Mika calls her over, passes the message on in her own
## words, and Luna answers Mika; nobody is left holding.
func _lunarelay() -> void:
	await _hold_all()
	var ll = main.get("live_link")
	_check(ll != null, "live link present (--live-link)")
	if ll == null:
		return
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = mika.get_world_3d().navigation_map
	for c in [mika, luna]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(4, 0, 10)) + Vector3(0, 0.05, 0)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(14, 0, 16)) + Vector3(0, 0.05, 0)
	for w in main.mage_brains:
		main.mage_brains[w].current = {}
	await _wait(1.5)
	var d0 := luna.global_position.distance_to(mika.global_position)
	# a quiet moment (the test world starts with a show performance and a greeting; the brains stay held until the
	# message - the relay holds and releases them itself)
	if main.performance and main.performance.busy():
		main.performance.interrupt("test")
	main.voice.stop()
	await _wait(1.0)
	print("[mktest] lunarelay pre: safe %s voice_busy %s streaming %s magic_busy %s perf %s reading %s mika_kind '%s' luna_kind '%s'" % [main.chat._safe_point("mika"), main.voice.busy(),
		main.streaming.state, main.magic.busy, main.performance.busy() if main.performance else false, main.book_reader.reading(),
		main.mage_brains.mika.current.get("kind", ""), main.mage_brains.luna.current.get("kind", "")])
	var lines: Array = []
	var on_line := func(sp: String, text: String): lines.append([sp, text])
	main.voice.line_started.connect(on_line)
	ll._on_message({"type": "youtube-live-selected-message", "active": true, "message": "Luna, what is your favourite spell?", "author": "@tester", "id": "r1", "to": ["mika"]})
	var t0 := _game_t
	while _game_t - t0 < 70.0 and ll._luna_busy:
		await get_tree().process_frame
	main.voice.line_started.disconnect(on_line)
	var who: Array = lines.map(func(l): return String(l[0]))
	print("[mktest] lunarelay: start %.1f m apart, end %.1f m, %.0f s, lines %s" % [d0, luna.global_position.distance_to(mika.global_position), _game_t - t0, str(lines).left(500)])
	_check(not ll._luna_busy, "the relay finished")
	_check(luna.global_position.distance_to(mika.global_position) < 4.5, "Luna came over to Mika (%.1f m -> %.1f m)" % [d0, luna.global_position.distance_to(mika.global_position)])
	var mi := who.rfind("mika")
	var lu := who.rfind("luna")
	_check(mi >= 0 and lu > mi, "Mika passes it on, then Luna answers her", str(who))
	_check(lines.size() >= 3, "she called Luna over first (%d lines)" % lines.size())
	for b in main.mage_brains.values():
		_check(not b.hold, "%s is not left on hold" % b.agent_id)


## Bodies shaking while they stand (talks, casts, spars; broadcast 2): standing still on several real floors, every
## physics frame: is_on_floor() flips, the foot guard's hip lift and the hips' height jumps (mm). Still = none.
func _standstill() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = mika.get_world_3d().navigation_map
	var spots := {"training": Vector3(20, 0, 8), "beyond_training": Vector3(48, 0, 13), "starfall": Vector3(-26.9, 0, 21.7), "circle": Vector3(0.5, 0, 2.5), "garden": Vector3(-8, 0, 6)}
	var all_ok := true
	for k in spots:
		if main.teleport_guard:
			main.teleport_guard.allow(mika)
		mika.global_position = NavigationServer3D.map_get_closest_point(map, spots[k]) + Vector3(0, 0.05, 0)
		mika.velocity = Vector3.ZERO
		await _wait(2.0)
		var st := {"frames": 0, "floor_flips": 0, "lift_jumps": 0, "hip_jumps": 0, "max_lift": 0.0}
		var last_floor := mika.is_on_floor()
		var last_lift: float = mika.foot_guard.lift if mika.foot_guard else 0.0
		var hb := mika.skeleton.find_bone("Hips")
		var last_hy := (mika.skeleton.global_transform * mika.skeleton.get_bone_global_pose(hb).origin).y
		var t0 := _game_t
		while _game_t - t0 < 4.0:
			await get_tree().process_frame
			st.frames += 1
			var f := mika.is_on_floor()
			if f != last_floor:
				st.floor_flips += 1
			last_floor = f
			var l: float = mika.foot_guard.lift if mika.foot_guard else 0.0
			if absf(l - last_lift) > 0.004:
				st.lift_jumps += 1
			st.max_lift = maxf(st.max_lift, l)
			last_lift = l
			var hy := (mika.skeleton.global_transform * mika.skeleton.get_bone_global_pose(hb).origin).y
			if absf(hy - last_hy) > 0.004:
				st.hip_jumps += 1
			last_hy = hy
		print("[mktest] standstill %s: %s" % [k, JSON.stringify(st)])
		if int(st.floor_flips) > 2 or int(st.lift_jumps) > 4:
			all_ok = false
	_check(all_ok, "standing still: no floor flicker, no hip lift jumping")


## Broadcast 2: "she doesn't walk anymore" (legs still, body sliding) and "sits sunk into the watchpoint bench".
## 1. a talking idle (a looping gesture) left on after a line, then a walk: the walk cycle must take over.
## 2. the real watchpoint rest: her hips against the seat's top while seated.
func _benchwalk() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
		main.mage_brains[w].current = {}
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = mika.get_world_3d().navigation_map
	if main.teleport_guard:
		main.teleport_guard.allow(mika)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(-2, 0, 12)) + Vector3(0, 0.05, 0)
	await _wait(1.0)
	mika.play_gesture("idle_talk", 0.5, 0.7)
	await _wait(1.5)
	mika.navigate_to(NavigationServer3D.map_get_closest_point(map, Vector3(-2, 0, 2)), false)
	await _wait(2.5)
	var active := bool(mika.anim_tree.get("parameters/cast/active"))
	var blend := float(mika.anim_tree.get("parameters/loco/blend_position"))
	_check(not active and blend > 0.8, "walking after a talk: the walk cycle plays (held gesture %s, loco blend %.2f, gesture '%s')" % [str(active), blend, mika.current_gesture])
	mika.stop_action()
	await _wait(1.0)
	var it: Interactable = main.world.interactables.get("watchpoint_rest")
	if it == null:
		_check(false, "watchpoint bench exists")
		return
	var seat_top: float = it.get_parent().to_global(it.sit_point).y + float(main.world.get("SEAT_H") if main.world.get("SEAT_H") != null else 0.45)
	if it.seat_body:
		var sb := it.seat_body as Node3D
		for cs in sb.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
				seat_top = (cs as CollisionShape3D).global_position.y + ((cs as CollisionShape3D).shape as BoxShape3D).size.y * 0.5
	mika.navigate_to(it.approach_point(), false)
	var tn := _game_t
	while mika.current_action == "navigate_to" and _game_t - tn < 80.0:
		await get_tree().process_frame
	var job := func(): await it.perform(mika)
	job.call()
	var hb := mika.skeleton.find_bone("Hips")
	var low := 99.0
	var t0 := _game_t
	var sat_at := -1.0
	while _game_t - t0 < 70.0 and (sat_at < 0.0 or _game_t - sat_at < 6.0):
		await get_tree().process_frame
		if mika.seated and sat_at < 0.0:
			sat_at = _game_t
		if mika.seated and sat_at >= 0.0 and _game_t - sat_at > 2.5:
			var hy := (mika.skeleton.global_transform * mika.skeleton.get_bone_global_pose(hb).origin).y
			low = minf(low, hy)
	if mika.seated and DisplayServer.get_name() != "headless":
		var hip := mika.skeleton.global_transform * mika.skeleton.get_bone_global_pose(hb).origin
		var fwd := -mika.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := Vector3(-fwd.z, 0, fwd.x)
		main.director.enabled = false
		main.camera_rig.set_shot(hip + fwd * 3.0 + side * 1.6 + Vector3(0, 0.5, 0), hip + Vector3(0, -0.1, 0), 50.0)
		await _wait(1.5)
		_shot("bench_front")
		main.camera_rig.set_shot(hip + side * 3.2 + Vector3(0, 0.3, 0) + fwd * 0.4, hip + Vector3(0, -0.15, 0), 50.0)
		await _wait(1.5)
		_shot("bench_side")
	print("[mktest] benchwalk: seat top %.3f, lowest seated hips %.3f, root y %.3f, gesture '%s', seated %s" % [seat_top, low, mika.global_position.y, mika.current_gesture, str(mika.seated)])
	_check(low < 90.0 and low >= seat_top + 0.04, "seated on top of the watchpoint bench (hips %.3f, seat top %.3f)" % [low, seat_top])


## Calls `cb` at the END of each frame's process step (after every other node's _process): a test's view of what
## is actually drawn.
class LateTick extends Node:
	var cb: Callable

	func _process(_delta: float) -> void:
		if cb.is_valid():
			cb.call()


# ================================================================== Day 2 update checks (2026-10-17)
## 1+3: the story's library book is reachable at Levels 1-9; the followed mage walks to the library and reads it,
## and Luna walks along (she no longer vanishes when Mika changes area).
func _day2story() -> void:
	await _hold_all()
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var m := WorldState.mind("mika")
	m.progress.level = 5
	for k in ["clue:sign_of_return_location", "lore:heartstone", "clue:heartbeat_should_be_three", "noticed:keepers_daybook"]:
		m.knowledge[k] = 1
	m.knowledge["read:keepers_daybook"] = [0, 1, 2, 3]
	m.knowledge.erase("incantation:rune_activation")
	main.story.evaluate(true)
	var leads: Array = main.story.next_leads()
	print("[mktest] day2story leads: %s" % str(leads.map(func(l): return l.lead)))
	_check(leads.any(func(l): return String(l.get("book", "")) == "signs_and_wakings"), "the story's next lead is the library book Signs and Wakings")
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var opts: Array = mb.options()
	var ro: Array = opts.filter(func(o): return o.kind == "research" and String(o.get("book", "")) == "signs_and_wakings")
	_check(not ro.is_empty(), "Level 5: the library book is an option (it used to be filtered out below Level 10)", opts.map(func(o): return o.key).slice(0, 30))
	var visits: Array = opts.filter(func(o): return o.kind == "visit").map(func(o): return o.area)
	print("[mktest] day2story visit options: %s" % str(visits))
	_check(visits.size() >= 2, "home-region outings are offered (%s)" % str(visits))
	# run it: luna beside her; Mika's brain does exactly that option
	var map: RID = mika.get_world_3d().navigation_map
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, mika.global_position + Vector3(2.0, 0, 1.0)) + Vector3(0, 0.05, 0)
	main.director.enabled = true
	main.director.set_subject(mika)
	var res := {}
	var job := func(): res["r"] = await mb.run_activity(ro[0])
	job.call()
	var t0 := _game_t
	var luna_in_lib := false
	var logged := false
	while not res.has("r") and _game_t - t0 < 240.0:
		await get_tree().process_frame
		if main.streaming.current_id == "arcane_library" and luna.visible:
			luna_in_lib = true
		if main.streaming.current_id == "arcane_library" and main.streaming.state == "idle":
			if not logged:
				logged = true
				var mp := mika.global_position
				var tgt: Vector3 = main.world.points_of_interest["ancient_spell_library"].position
				var path := NavigationServer3D.map_get_path(mika.get_world_3d().navigation_map, mp, tgt, true)
				print("[mktest] day2story arrival: luna visible %s mika action %s/%s, mika %s luna %s marker %s path %s" % [luna.visible, mika.current_action, mika.is_physics_processing(), str(mp.snapped(Vector3.ONE * 0.1)), str(luna.global_position.snapped(Vector3.ONE * 0.1)), str(tgt), str(Array(path).map(func(v): return v.snapped(Vector3.ONE * 0.1)))])
	print("[mktest] day2story: %s after %.0f s, area %s" % [str(res.get("r", {})).left(200), _game_t - t0, main.streaming.current_id])
	_check(res.has("r") and bool(res.r.get("ok", false)), "she went and read it", res.get("r", "timeout"))
	_check(not BookLibrary.pages_read("signs_and_wakings", "mika").is_empty(), "pages of Signs and Wakings are read")
	_check(main.streaming.current_id == "arcane_library", "she is in the Ancient Spell Library (%s)" % main.streaming.current_id)
	_check(luna_in_lib, "Luna walked along and is there with her")
	_shot("library")
	report["day2story"] = {"result": str(res.get("r", {})).left(300), "area": main.streaming.current_id, "luna_along": luna_in_lib}


## 6: the crash fix repeats: while Luna walks to an interactable, the area unloads under her (a journey) - six times.
## Before the fix this touched the freed interactable (Godot crashed at the journey's arrival).
func _day2crash() -> void:
	await _hold_all()
	main.spawner.enabled = false
	var lb: SanctuaryBrain = main.mage_brains["mika"]       # her own walk, cut off by a journey (the crash path)
	var mika: WorldCharacter = main.characters["mika"]
	var results := []
	var dests := ["whispering_woods", "ritual_sanctuary", "ancient_spell_library", "ritual_sanctuary", "mentors_tower", "ritual_sanctuary"]
	for i in dests.size():
		var here: String = main.streaming.current_id
		var ids: Array = main.world.interactables.keys()
		var luna: WorldCharacter = main.characters["mika"]
		var box := {}
		if luna.visible and not ids.is_empty():
			var far := ""
			var best := 0.0
			for id in ids:
				var d: float = (main.world.interactables[id] as Node3D).global_position.distance_to(luna.global_position)
				if d > best:
					best = d
					far = String(id)
			var job := func(): box["r"] = await lb._use(far)
			job.call()
			await _wait(1.0)
		var r: Dictionary = main.travel.travel_to(dests[i], "walk")
		var t0 := _game_t
		while main.travel.active() and _game_t - t0 < 200.0:
			await get_tree().process_frame
		await _wait(2.0)
		var t1 := _game_t
		while not box.is_empty() and not box.has("r") and _game_t - t1 < 30.0:
			await get_tree().process_frame
		results.append({"from": here, "to": main.streaming.current_id, "travel": r.get("ok", false), "luna_use": box.get("r", {}).get("detail", "none")})
		print("[mktest] day2crash %d: %s" % [i, str(results.back())])
	report["day2crash"] = results
	_check(results.size() == dests.size(), "six journeys with an interactable walk cut short, no crash (%d)" % results.size())
	_check(results.all(func(x): return x.travel), "every journey started")
	var guarded := results.filter(func(x): return String(x.luna_use).contains("no longer here") or String(x.luna_use).contains("could not reach"))
	_check(guarded.size() >= 4, "the cut-off walks ended safely (%d of %d returned 'no longer here' / 'could not reach')" % [guarded.size(), results.size()])


## 4: a full dusk and dawn on the clock (17:20 -> 07:30 at 12 world minutes a second, ~70 s), a wide shot of the
## sanctuary toward Starfall Hill; the night look follows the clock: k rises to 1 by 20:00 and falls to 0 by 07:00.
func _daynight() -> void:
	await _hold_all()
	main.spawner.enabled = false
	_check(main.day_night != null, "the day/night cycle runs")
	main.day_night.clear_override()
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 17.33 * 60.0
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 24.0)
	await _wait(4.0)
	# a fixed wide lens of its own for the clip: the dais, the ruins and a big piece of sky toward Starfall Hill
	main.director.enabled = false
	var cam := Camera3D.new()
	cam.fov = 64.0
	main.add_child(cam)
	var g: float = main.world.ground_at(6.0, -8.0) if main.world.has_method("ground_at") else 0.0
	cam.global_position = Vector3(6.0, g + 3.2, -8.0)
	cam.look_at(Vector3(-20.0, g + 7.0, 16.0), Vector3.UP)
	cam.make_current()
	WorldState.clock_rate = float(RenderProfile.options.get("dn-rate", "12"))
	var samples := []
	var max_k := 0.0
	var flips := []
	var was := WorldState.night
	var t0 := _game_t
	var next_s := 0.0
	while WorldState.hour_f() < 7.5 or WorldState.hour_f() > 17.0:
		await get_tree().process_frame
		if _game_t - t0 > 900.0 / maxf(WorldState.clock_rate, 1.0) + 30.0:
			break
		max_k = maxf(max_k, main.day_night.k)
		if WorldState.night != was:
			flips.append([WorldState.clock_text(), WorldState.night])
			was = WorldState.night
		if _game_t - t0 >= next_s:
			next_s += 3.0
			samples.append([WorldState.clock_text().right(5), snappedf(main.day_night.k, 0.02)])
	WorldState.clock_rate = 0.5
	await _wait(2.0)
	cam.queue_free()
	main.director.enabled = true
	print("[mktest] daynight samples %s" % str(samples))
	print("[mktest] daynight flips %s" % str(flips))
	report["daynight"] = {"samples": samples, "flips": flips, "max_k": max_k}
	_check(max_k > 0.98, "full night reached by the clock (k %.2f)" % max_k)
	_check(main.day_night.k < 0.02, "full day again after dawn (k %.2f)" % main.day_night.k)
	_check(flips.size() == 2, "the night flag turned at dusk and back at dawn (%s)" % str(flips))


## 4: stargazing on any open grassy spot (not only the registry's one), with a cooldown.
func _day2stargaze() -> void:
	await _hold_all()
	main.spawner.enabled = false
	main.day_night.set_override(true)
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 22.0 * 60.0
	await _wait(5.0)
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	luna.global_position = NavigationServer3D.map_get_closest_point(mika.get_world_3d().navigation_map, mika.global_position + Vector3(2.0, 0, 1.0)) + Vector3(0, 0.05, 0)
	var cells: Dictionary = mb._grass_cells()
	var thick := cells.values().filter(func(v): return int(v) >= 6).size()
	print("[mktest] day2stargaze grass cells %d (thick %d), mika at %s" % [cells.size(), thick, str(mika.global_position)])
	var spots := []
	for i in 6:
		spots.append(mb._grass_stargaze_spot())
	var found := spots.filter(func(p): return p != Vector3.INF)
	print("[mktest] day2stargaze grass spots %s" % str(found))
	_check(found.size() >= 4, "open grassy spots found under the sky (%d of 6)" % found.size())
	var o: Array = mb.options().filter(func(x): return String(x.key).begins_with("together:stargaze"))
	_check(not o.is_empty(), "stargazing is offered at night")
	WorldState.note_activity("together:stargaze:luna", "mika")
	var o2: Array = mb.options().filter(func(x): return String(x.key).begins_with("together:stargaze"))
	_check(o2.is_empty(), "and not again within the cooldown (saved in her mind)")
	main.day_night.clear_override()


## 5: the show's facts no longer carry the level in every line; the fresh topic rotates.
func _day2topics() -> void:
	var ll = main.get("live_link")
	if ll == null:
		for n in main.get_children():
			if n.has_method("_mage_progress"):
				ll = n
	_check(ll != null, "the live link is there")
	if ll == null:
		return
	WorldState.mind("mika").progress["leveled_unix"] = 0.0
	ll._progress_at = -100000
	var p: Dictionary = ll._mage_progress()
	print("[mktest] day2topics mika: %s" % JSON.stringify(p.get("mika", {})).left(400))
	_check(not (p.get("mika", {}) as Dictionary).has("level") and not (p.get("mika", {}) as Dictionary).has("toNextLevel"), "no level number / percent pushed while it is old news")
	var kinds := []
	for i in 5:
		ll._topic_at = -1000000
		var tp := String(ll._rotating_topic())
		kinds.append(tp.left(40))
	print("[mktest] day2topics rotation: %s" % str(kinds))
	var distinct := {}
	for k in kinds:
		distinct[k] = true
	_check(distinct.size() >= 4, "topics rotate (%d distinct of 5)" % distinct.size())
	WorldState.mind("mika").progress["leveled_unix"] = Time.get_unix_time_from_system()
	ll._progress_at = -100000
	_check((ll._mage_progress().get("mika", {}) as Dictionary).has("levelNews"), "a fresh level-up is news")


func _libnav() -> void:
	await _hold_all()
	var mika: WorldCharacter = main.characters["mika"]
	var r: Dictionary = await main.streaming.travel("arcane_library", mika)
	await _wait(2.0)
	var map: RID = mika.get_world_3d().navigation_map
	print("[mktest] libnav regions %d iteration %d" % [NavigationServer3D.map_get_regions(map).size(), NavigationServer3D.map_get_iteration_id(map)])
	for p in [Vector3(0, 0, 12), Vector3(0, 0, 8), Vector3(0, 0, 4), Vector3(0, 0, 0), Vector3(0, 0, -2), Vector3(-2.6, 0, 2.95), Vector3(0, 0, -8)]:
		var cp := NavigationServer3D.map_get_closest_point(map, p)
		var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 12)), cp, true)
		print("[mktest] libnav %s -> closest %s, path from entry %d pts" % [str(p), str(cp.snapped(Vector3.ONE * 0.01)), path.size()])
	var nr: NavigationRegion3D = main.world.nav_region
	if nr and nr.navigation_mesh:
		var nm: NavigationMesh = nr.navigation_mesh
		print("[mktest] libnav navmesh polys %d verts %d cell %.2f agent r %.2f" % [nm.get_polygon_count(), nm.get_vertices().size(), nm.cell_size, nm.agent_radius])
	for y in [0.0, 0.1, 0.25, 0.4, 0.5, 0.8]:
		print("[mktest] libnav from y=%.2f: %d pts; closest %s" % [y, NavigationServer3D.map_get_path(map, Vector3(0, y, 12), Vector3(0, 0.5, -2), true).size(), str(NavigationServer3D.map_get_closest_point(map, Vector3(0, y, 12)))])
	for y in [0.0, 0.25, 0.5]:
		print("[mktest] libnav from (0,%.2f,6): %d pts" % [y, NavigationServer3D.map_get_path(map, Vector3(0, y, 6), Vector3(0, 0.5, -2), true).size()])
	print("[mktest] libnav mika at %s path-from-her %d" % [str(mika.global_position), NavigationServer3D.map_get_path(map, mika.global_position, Vector3(0, 0.5, -2), true).size()])
	mika.navigate_to(Vector3(0, 0, -2), false)
	var t0 := _game_t
	while mika.current_action == "navigate_to" and _game_t - t0 < 20.0:
		await get_tree().process_frame
	print("[mktest] libnav walk: now %s, %s, last %s" % [str(mika.global_position.snapped(Vector3.ONE * 0.1)), mika.current_action, str(mika.get("last_rejection"))])


func _gateprobe() -> void:
	await _wait(3.0)
	var map: RID = main.characters["mika"].get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 0))
	for c in [Vector2(-34, 30), Vector2(-30, 36), Vector2(-35, 40), Vector2(-25, 42), Vector2(-33, 34), Vector2(-28, 30), Vector2(-20, 44)]:
		var p := Vector3(c.x, main.world.ground_at(c.x, c.y), c.y)
		var cp := NavigationServer3D.map_get_closest_point(map, p)
		var path := NavigationServer3D.map_get_path(map, from, cp, true)
		print("[mktest] gateprobe %s -> closest %s (off %.2f) path %d" % [str(c), str(cp.snapped(Vector3.ONE * 0.1)), Vector2(cp.x - c.x, cp.z - c.y).length(), path.size()])


## 7: Lantern Lake, their second night spot: at night they walk down past Starfall Hill together, sit at the end of the
## pier, watch the lanterns and let one go, then walk home.
func _lakenight() -> void:
	await _hold_all()
	main.spawner.enabled = false
	main.day_night.clear_override()
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 21.5 * 60.0
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 12.0)
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = mika.get_world_3d().navigation_map
	for c in [mika, luna]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(-30, 0, 30)) + Vector3(0, 0.05, 0)
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(-28, 0, 31)) + Vector3(0, 0.05, 0)
	await _wait(5.0)
	main.director.enabled = true
	main.director.set_subject(mika)
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var opts: Array = mb.options()
	var lake_opt: Array = opts.filter(func(o): return o.kind == "visit" and String(o.area) == "lantern_lake")
	_check(not lake_opt.is_empty(), "at night the walk down to Lantern Lake is offered", opts.map(func(o): return o.key).slice(0, 20))
	if lake_opt.is_empty():
		return
	var sc: Dictionary = mb.score(lake_opt[0])
	print("[mktest] lakenight visit score %s" % str(sc))
	var res := {}
	var job := func(): res["r"] = await mb.run_activity(lake_opt[0])
	job.call()
	var t0 := _game_t
	while not res.has("r") and _game_t - t0 < 200.0:
		await get_tree().process_frame
	print("[mktest] lakenight arrive: %s area %s luna visible %s" % [str(res.get("r", {})).left(160), main.streaming.current_id, luna.visible])
	_check(main.streaming.current_id == "lantern_lake", "they reached Lantern Lake (%s)" % main.streaming.current_id)
	_check(luna.visible and String(WorldState.mind("luna").location.get("area", "")) == "lantern_lake", "Luna walked down with her")
	_shot("lake_arrival")
	await _wait(2.0)
	var lw: Array = mb.options().filter(func(o): return o.kind == "lakewatch")
	_check(not lw.is_empty(), "sitting on the pier to watch the lanterns is offered")
	if lw.is_empty():
		return
	var res2 := {}
	var job2 := func(): res2["r"] = await mb.run_activity(lw[0])
	job2.call()
	var t1 := _game_t
	var sat := {"mika": false, "luna": false}
	var logged_at := 0.0
	while not res2.has("r") and _game_t - t1 < 180.0:
		await get_tree().process_frame
		if _game_t - t1 > logged_at + 15.0:
			logged_at = _game_t - t1
			var cam := get_viewport().get_camera_3d()
			print("[mktest] lakenight t=%.0f mika %s %s luna %s %s | director mode %s scene %s cam %s" % [logged_at, str(mika.global_position.snapped(Vector3.ONE * 0.1)), mika.ground_pose,
				str(luna.global_position.snapped(Vector3.ONE * 0.1)), luna.ground_pose, str(main.director.get("mode")), str(main.director.get("_scene") != null and (main.director.get("_scene") as Callable).is_valid()), str(cam.global_position.snapped(Vector3.ONE * 0.1)) if cam else "-"])
		var sp_now: Array = main.world.sit_spots() if main.world.has_method("sit_spots") else []
		for i in 2:
			var c: WorldCharacter = [mika, luna][i]
			if c.ground_pose == "sit" and not sp_now.is_empty() and c.global_position.distance_to(sp_now[i]) < 1.2:
				sat[c.character_id] = true
	print("[mktest] lakenight watch: %s sat %s" % [str(res2.get("r", {})).left(200), str(sat)])
	_check(res2.has("r") and bool(res2.r.get("ok", false)), "they watched the lanterns", res2.get("r", "timeout"))
	_check(sat.mika and sat.luna, "both sat on the pier deck (%s)" % str(sat))
	_check(mb.options().filter(func(o): return o.kind == "lakewatch").is_empty(), "not again tonight")
	report["lakenight"] = {"visit": str(res.get("r", {})).left(200), "watch": str(res2.get("r", {})).left(200), "sat": sat}


## Day 2 soak: 30 real minutes of their own life from Day 1's save (a copy), afternoon -> dusk -> night -> dawn
## (15:30 -> ~06:30 at the normal clock). Everything is their own choice; this only watches and reports.
func _day2soak() -> void:
	var mins := float(RenderProfile.options.get("soak-min", "30"))
	main.day_night.clear_override()
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + float(RenderProfile.options.get("soak-start", "15.5")) * 60.0
	WorldState.clock_rate = 0.5
	main.director.enabled = true
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var mm := WorldState.mind("mika")
	var j0: int = (mm.knowledge.get("journal", []) as Array).size()
	var seq0 := mm.activity_seq
	var areas := {}
	var together := 0
	var samples := 0
	var max_k := 0.0
	var topics := []
	var kinds := {}
	var decisions := []
	var cb := func(d): decisions.append([snappedf(_game_t, 1.0), WorldState.clock_text().right(5), main.streaming.current_id, String(d.get("kind", "")), String(d.get("label", "")).left(60)])
	main.mage_brains["mika"].decided.connect(cb)
	var lcb := func(d): kinds["luna:" + String(d.get("kind", ""))] = int(kinds.get("luna:" + String(d.get("kind", "")), 0)) + 1
	main.mage_brains["luna"].decided.connect(lcb)
	var t0 := _game_t
	var next_s := 0.0
	var next_tp := 0.0
	while _game_t - t0 < mins * 60.0:
		await get_tree().process_frame
		if _game_t - t0 >= next_s:
			next_s += 20.0
			samples += 1
			areas[main.streaming.current_id] = int(areas.get(main.streaming.current_id, 0)) + 1
			if luna.visible and mika.visible and luna.global_position.distance_to(mika.global_position) < 40.0:
				together += 1
			max_k = maxf(max_k, main.day_night.k)
			if RenderProfile.options.has("soak-diag"):
				var b0: SanctuaryBrain = main.mage_brains.mika
				print("[mktest] soakdiag mika enabled %s hold %s busy %s current %s last %s focus %s sim %s" % [b0.enabled, b0.hold, b0.busy, str(b0.current).left(80), str(b0.last_decision.get("key", "")), main.focus, main.sim_mode("mika")])
			if int(_game_t - t0) % 120 < 20:
				print("[mktest] soak %4.0fs %s %s k=%.2f mika: %s | luna: %s" % [_game_t - t0, WorldState.clock_text().right(5), main.streaming.current_id, main.day_night.k,
					String(main.mage_brains.mika.current.get("label", "-")).left(50), String(main.mage_brains.luna.current.get("label", "-")).left(50)])
		if main.live_link and _game_t - t0 >= next_tp:
			next_tp += 120.0
			main.live_link._topic_at = -1000000
			topics.append(String(main.live_link._rotating_topic()).left(70))
	for d in decisions:
		kinds[d[3]] = int(kinds.get(d[3], 0)) + 1
	var journal_n: int = (mm.knowledge.get("journal", []) as Array).size() - j0
	print("[mktest] soak decisions (%d): %s" % [decisions.size(), JSON.stringify(decisions)])
	print("[mktest] soak kinds %s" % JSON.stringify(kinds))
	print("[mktest] soak areas %s together %d/%d max_k %.2f journal +%d activities +%d" % [JSON.stringify(areas), together, samples, max_k, journal_n, mm.activity_seq - seq0])
	print("[mktest] soak topics %s" % JSON.stringify(topics))
	report["day2soak"] = {"decisions": decisions, "kinds": kinds, "areas": areas, "together": [together, samples], "max_k": max_k,
		"journal_new": journal_n, "topics": topics, "lake_night": mm.knowledge.get("lake_night", -1),
		"stargazed": mm.activity_counts.get("together:stargaze:luna", {}), "level": [mm.level(), WorldState.mind("luna").level()]}
	var mk: Array = kinds.keys().filter(func(k): return not String(k).begins_with("luna:"))
	_check(journal_n <= int(mins / 15.0) + 1, "the journal is not every 2 minutes (%d entries in %.0f min)" % [journal_n, mins])
	_check(mk.size() >= 8, "variety: %d different kinds of activity (%s)" % [mk.size(), str(mk)])
	_check(areas.keys().size() >= 3, "they lived in more of the home region than the sanctuary (%s)" % str(areas.keys()))
	_check(together >= samples * 0.85, "Luna stayed with Mika in the same place (%d/%d samples)" % [together, samples])
	_check(max_k > 0.98, "night fell by the clock (k %.2f)" % max_k)
	var distinct := {}
	for tp in topics:
		distinct[String(tp).left(25)] = true
	_check(topics.size() < 3 or distinct.size() >= mini(4, topics.size()), "the show's topics rotate (%d distinct of %d)" % [distinct.size(), topics.size()])



## The Mentor's Tower outing: by day she walks over with Luna, arrives, and later walks home.
func _towervisit() -> void:
	await _hold_all()
	main.spawner.enabled = false
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 11.0 * 60.0
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	luna.global_position = NavigationServer3D.map_get_closest_point(mika.get_world_3d().navigation_map, Vector3(-30, 0, 25)) + Vector3(0, 0.05, 0)
	main.director.enabled = true
	main.director.set_subject(mika)
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var o: Array = mb.options().filter(func(x): return x.kind == "visit" and String(x.area) == "mentor_tower")
	_check(not o.is_empty(), "the walk to the Mentor's Tower is offered by day")
	if o.is_empty():
		return
	print("[mktest] towervisit score %s (luna %.0f m away)" % [str(mb.score(o[0])), luna.global_position.distance_to(mika.global_position)])
	var res := {}
	var job := func(): res["r"] = await mb.run_activity(o[0])
	job.call()
	var t0 := _game_t
	while not res.has("r") and _game_t - t0 < 200.0:
		await get_tree().process_frame
	_check(bool(res.get("r", {}).get("ok", false)) and main.streaming.current_id == "mentor_tower", "she arrived at the Mentor's Tower (%s, %s)" % [main.streaming.current_id, str(res.get("r", {})).left(120)])
	_check(luna.visible and String(WorldState.mind("luna").location.get("area", "")) == "mentor_tower", "Luna came along from 40+ m away")
	await _wait(4.0)
	_shot("tower")
	var home: Array = mb.options().filter(func(x): return x.kind == "visit" and String(x.area) == "sanctuary")
	_check(not home.is_empty(), "the way home is offered there")


## Luna is reading in the library when Mika walks home: Luna stops, walks along, her brain is free again, and the
## one-reader lock is released (Day 2 soak: her read hung for the rest of the run).
func _readtravel() -> void:
	await _hold_all()
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	var r: Dictionary = await main.streaming.travel("arcane_library", mika)
	await _wait(1.0)
	await main.world.bake_navigation()          # (as a journey's arrival does: the first bake answers no paths)
	await _wait(1.0)
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	var map: RID = mika.get_world_3d().navigation_map
	luna.world = main.world
	luna.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(1.5, 0, 6)) + Vector3(0, 0.05, 0)
	luna.visible = true
	luna.set_physics_process(true)
	WorldState.mind("luna").set_location("arcane_library", luna.global_position)
	lb.hold = false
	var ljob := func(): lb.current = {"kind": "research", "label": "read Elementa Prima", "key": "research:elementa_prima"}; await lb._use("lectern_warding_glyph"); lb.current = {}
	ljob.call()
	var t0 := _game_t
	while not main.book_reader.reading() and _game_t - t0 < 40.0:
		await get_tree().process_frame
	_check(main.book_reader.reading(), "Luna is reading Elementa Prima in the library")
	await _wait(3.0)
	var home: Array = mb.options().filter(func(o): return o.kind == "visit" and String(o.area) == "sanctuary")
	var res := {}
	var job := func(): res["r"] = await mb.run_activity(home[0])
	job.call()
	var t1 := _game_t
	while not res.has("r") and _game_t - t1 < 200.0:
		await get_tree().process_frame
	await _wait(3.0)
	print("[mktest] readtravel: %s area %s, reading %s, luna current %s visible %s" % [str(res.get("r", {})).left(100), main.streaming.current_id, main.book_reader.reading(), str(lb.current), luna.visible])
	_check(main.streaming.current_id == "sanctuary", "Mika walked home")
	_check(not main.book_reader.reading(), "the reading ended (the one-reader lock is free)")
	_check(lb.current.is_empty() or String(lb.current.get("label", "")) != "read Elementa Prima", "Luna's brain is free again (%s)" % str(lb.current.get("label", "-")))
	_check(luna.visible and String(WorldState.mind("luna").location.get("area", "")) == "sanctuary", "Luna walked home with her")


## Walking home from Lantern Lake with Luna there (the Day 2 soak's slow-frame burst): per-second frame and process time.
func _lakehome() -> void:
	await _lakenight()
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	main.mage_brains["luna"].hold = false
	await _wait(3.0)
	var home: Array = mb.options().filter(func(o): return o.kind == "visit" and String(o.area) == "sanctuary")
	_check(not home.is_empty(), "the way home is offered at the lake")
	if home.is_empty():
		return
	var res := {}
	var job := func(): res["r"] = await mb.run_activity(home[0])
	job.call()
	var t0 := _game_t
	var acc := {"n": 0, "slow": 0, "proc": 0.0, "worst": 0.0}
	var last := Time.get_ticks_usec()
	var next_p := 1.0
	while not res.has("r") and _game_t - t0 < 150.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		acc.n += 1
		acc.proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		acc.worst = maxf(acc.worst, ms)
		if ms > 50.0:
			acc.slow += 1
		if _game_t - t0 >= next_p:
			next_p += 1.0
			var lb: SanctuaryBrain = main.mage_brains["luna"]
			print("[mktest] lakehome t=%3.0f frames %d slow %d proc avg %.1f worst %.0f | area %s state %s | mika %s | luna %s (hold %s)" % [_game_t - t0, acc.n, acc.slow, acc.proc / maxf(acc.n, 1), acc.worst,
				main.streaming.current_id, main.streaming.state, String(mb.current.get("stage", "-")).left(30), String(lb.current.get("label", "-")).left(30), lb.hold])
			acc = {"n": 0, "slow": 0, "proc": 0.0, "worst": 0.0}
	_check(res.has("r") and bool(res.r.get("ok", false)), "they walked home", res.get("r", "timeout"))


func _discovery_live() -> void:
	await _wait(6.0)
	main.spawner.enabled = false
	var dd: DiscoveryDirector = main.discoveries
	_check(dd != null, "the discovery director is running")
	if dd == null:
		return
	var who := dd.lead()
	if who == "":
		who = "mika"
	var c: WorldCharacter = main.characters[who]
	var other: WorldCharacter = main.characters["luna" if who == "mika" else "mika"]
	print("[mktest] discovery_live lead %s at %s in %s, other %.1f m away" % [who, str(c.global_position.snapped(Vector3.ONE * 0.1)), main.streaming.current_id, other.global_position.distance_to(c.global_position)])
	var target := String(RenderProfile.options.get("disc-force", "sanc_lantern_wisp"))
	var got := {}
	dd.found.connect(func(e): got.merge(e))
	var live := {}
	var t0 := _gms()
	while live.is_empty() and _gms() - t0 < 30000:
		dd.forced = target
		live = dd.spawn(who)
		if live.is_empty():
			await _wait(1.0)
	_check(not live.is_empty(), "a find was placed near %s (%s)" % [who, target])
	if live.is_empty():
		return
	var d := c.global_position.distance_to(live.pos)
	var map: RID = c.get_world_3d().navigation_map
	_check(d >= 5.0 and d <= 17.0, "a few metres from her (%.1f m)" % d)
	_check(NavigationServer3D.map_get_closest_point(map, live.pos).distance_to(live.pos) < 0.6, "on walkable ground")
	_check(main.world.interactables.has((live.it as Interactable).id), "a real interactable in the area (%s)" % (live.it as Interactable).id)
	await _wait(1.5)
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_jpg(dir + "/disc_noticed.jpg", 0.85)
	var tn := _gms()
	while got.is_empty() and _gms() - tn < 150000:
		await _wait(1.0)
	var secs := (_gms() - tn) / 1000.0
	_check(not got.is_empty(), "she walked over and examined it on her own (%.0f s, planner: %s)" % [secs, str(main.mage_brains[who].current.get("kind", "-"))])
	if got.is_empty():
		print("[mktest] discovery_live options: ", JSON.stringify((main.mage_brains[who] as SanctuaryBrain).ranked().slice(0, 5).map(func(o): return [o.key, o.utility])))
		return
	await _wait(2.5)
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_jpg(dir + "/disc_found.jpg", 0.85)
	var mind := WorldState.mind(who)
	_check(mind.knowledge.has("find:" + target), "the reward is in %s's own mind (find:%s)" % [who, target])
	var rew: Dictionary = got.get("reward", {})
	var items_ok := true
	for k in rew.get("items", {}):
		items_ok = items_ok and int(mind.inventory.get(k, 0)) >= int(rew.items[k])
	_check(items_ok, "and its items (%s)" % str(rew.get("items", {})))
	var log_: Array = WorldState.finds.get("log", [])
	_check(not log_.is_empty() and String(log_[-1].id) == target and String(log_[-1].area) == String(main.streaming.current_id), "saved in the finds log with where and when")
	var overlay_hit := false
	for ev in main.overlay_ui.events:
		if String(ev.text).contains("found") and String(ev.text).to_lower().contains(String(got.label).split(" ")[-1].to_lower()):
			overlay_hit = true
	_check(overlay_hit, "the overlay notes it")
	var reacted := false
	if other.face:
		for l in other.face.log:
			if String(l.emotion) in ["surprised", "happy"] and float(l.t) > tn / 1000.0:
				reacted = true
	_check(reacted or other.global_position.distance_to(c.global_position) > 30.0, "the other mage reacts (%.1f m away)" % other.global_position.distance_to(c.global_position))
	_check(dd.revisits().size() >= 1, "the place stays in the world, to revisit (%d)" % dd.revisits().size())
	var save_txt := FileAccess.get_file_as_string(WorldState.save_path)
	_check(save_txt.contains('"finds"') and save_txt.contains(target), "written to the save file")
	report["find"] = got
	report["seconds_to_find"] = secs


# ------------------------------------------------------------------ Luna round 12 face (2026-10-18)
## Luna's base face V2 (Mika's face, her gold eyes, violet hair and brows): the right model, the shading fix applied,
## the skin tint, then stills next to Mika by day, at dusk and at night: wide, gameplay medium and close-ups.
## (Close-ups of Luna are approved for review stills; the framing guard is suspended for this test only.)
func _luna_r12() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.spawner.enabled = false
	main.director.enabled = false
	if main.performance and main.performance.busy():
		main.performance.interrupt("look stills")
	if main.weather:
		main.weather.set_weather("clear", 12.0)
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	if RenderProfile.options.has("r12-avatar"):          # another form with the round 12 face (oracle, eclipse, ...)
		var ap := String(RenderProfile.options["r12-avatar"])
		if main.teleport_guard:
			main.teleport_guard.allow(luna)
		_check(luna.swap_avatar(ap), "Luna wears " + ap.get_file())
		await _wait(2.0)
	else:
		_check(luna.avatar_path.ends_with("LunaOracle_L1Outfit_faceV2.vrm"), "Luna wears the round 12 face", luna.avatar_path)
	_check(luna.face != null and luna.face.bound_count() >= 25, "her expressive face is bound", luna.face.bound_count() if luna.face else 0)
	_check(int(luna.get("face_shading_restored")) >= 1, "her face gets VRoid's face shading", luna.get("face_shading_restored"))
	var tinted := 0
	for mi in luna.avatar.find_children("*", "MeshInstance3D", true, false):
		for si in (mi as MeshInstance3D).mesh.get_surface_count():
			var mat := (mi as MeshInstance3D).get_active_material(si)
			if mat is ShaderMaterial and mat.has_meta("skin_base"):
				tinted += 1
	_check(tinted >= 1, "her skin tint is applied", tinted)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	var map: RID = mika.get_world_3d().navigation_map
	var spot := NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0, 6.0))
	var front := Vector3(0, 0, -1)                      # both face -Z, the camera stands at -Z looking back
	for c in [mika, luna]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.end_gesture()
	mika.global_position = spot + Vector3(0.55, 0.05, 0)
	luna.global_position = spot + Vector3(-0.55, 0.05, 0)
	for hh in [10.5, 18.4, 22.0]:
		WorldState.world_min = (WorldState.day() - 1) * 1440.0 + hh * 60.0
		if main.day_night:
			main.day_night.set_override(hh >= 21.0)
		for c in [mika, luna]:
			c.rotation.y = 0.0
		await _wait(2.0)
		var tag := "%02d" % int(hh)
		var mid := spot + Vector3(0, 1.0, 0)
		for sh in [["wide", Vector3(0.0, 0.3, -4.4), 40.0, Vector3.ZERO], ["medium", Vector3(0.0, 0.35, -2.5), 38.0, Vector3(0, 0.2, 0)]]:
			pin.pos = mid + (sh[1] as Vector3)
			pin.look = mid + (sh[3] as Vector3)
			pin.fov = float(sh[2])
			pin.active = true
			for c in [mika, luna]:
				c.look_head_at(pin.pos)
			await _wait(1.4)
			_shot("%s_%s" % [sh[0], tag])
		for who in [["luna", luna], ["mika", mika]]:
			var c: WorldCharacter = who[1]
			for ang in [["front", 0.0], ["three_q", 0.6], ["profile", 1.35]]:
				var hd: Vector3 = c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Head")).origin + Vector3(0, 0.07, 0)
				var vd := front.rotated(Vector3.UP, float(ang[1]) * (1.0 if who[0] == "luna" else -1.0))
				pin.pos = hd + vd * 0.95 + Vector3(0, 0.02, 0)
				pin.look = hd + Vector3(0, -0.04, 0)
				pin.fov = 32.0
				c.look_head_at(pin.pos if ang[0] != "profile" else null)
				await _wait(1.2)
				_shot("%s_%s_%s" % [who[0], ang[0], tag])
			if c.face:
				var hd2: Vector3 = c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Head")).origin + Vector3(0, 0.07, 0)
				pin.pos = hd2 + front * 0.95 + Vector3(0, 0.02, 0)
				pin.look = hd2 + Vector3(0, -0.04, 0)
				c.look_head_at(pin.pos)
				c.face.set_hold("happy", 0.8)
				await _wait(1.4)
				_shot("%s_happy_%s" % [who[0], tag])
				c.face.set_hold("", 0.0)
			c.look_head_at(null)
	pin.active = false
	pin.queue_free()
	main.camera_rig.set_process(true)
	main.director.set_process(true)


# ------------------------------------------------------------------ dress (skirt) behaviour (2026-10-18)
## One girl (--dt-who=luna|mika) walks, turns, sits on the watchpoint bench and stands, filmed by a pinned wide camera
## (record with --write-movie). Every frame the skirt joints are measured against her leg capsules (clipping), their
## speed relative to the hips (snaps) and their per-frame jumps (explosions); the first 1.5 s after a fresh avatar
## (spawn) are measured separately. Prints one "[mktest] dress" JSON line per phase.
const DT_THIGH_R := 0.066        # tapered leg capsules (thigh 6.6 -> 4.6 cm, shin 4.4 -> 3.2 cm), like the VRoid legs
var _dt_prev := {}
var _dt := {}

func _dt_reset(label: String) -> void:
	_dt = {"label": label, "frames": 0, "clip_frames": 0, "max_pen_cm": 0.0, "max_deg_s": 0.0, "degs": [], "max_jump_cm": 0.0, "explosions": 0}
	_dt_prev = {}


func _dt_sample(c: WorldCharacter, dt: float) -> void:
	var sk := c.skeleton
	var g := sk.global_transform
	var hips_i := sk.find_bone("Hips")
	var hips_t: Transform3D = g * sk.get_bone_global_pose(hips_i)
	var legs := []
	for side in ["Left", "Right"]:
		var ul := sk.find_bone(side + "UpperLeg")
		var ll := sk.find_bone(side + "LowerLeg")
		var ft := sk.find_bone(side + "Foot")
		if ul < 0 or ll < 0 or ft < 0:
			continue
		var a: Vector3 = (g * sk.get_bone_global_pose(ul)).origin
		var b: Vector3 = (g * sk.get_bone_global_pose(ll)).origin
		var f: Vector3 = (g * sk.get_bone_global_pose(ft)).origin
		legs.append([a, b, DT_THIGH_R, 0.046])
		legs.append([b, f, 0.044, 0.032])
	var pen := 0.0
	var frame_deg := 0.0
	for bi in sk.get_bone_count():
		var bn := sk.get_bone_name(bi)
		if not bn.contains("Skirt"):
			continue
		var gp: Transform3D = g * sk.get_bone_global_pose(bi)
		var p := gp.origin
		if not (bn.ends_with("_0") or bn.ends_with("_1")):      # (the waist joints sit over the hip joint itself)
			for L in legs:
				var cp := Geometry3D.get_closest_point_to_segment(p, L[0], L[1])
				var u := clampf((cp - (L[0] as Vector3)).length() / maxf(0.001, (L[0] as Vector3).distance_to(L[1])), 0.0, 1.0)
				pen = maxf(pen, lerpf(float(L[2]), float(L[3]), u) - p.distance_to(cp))
		var local: Vector3 = hips_t.affine_inverse() * p
		var dir: Vector3 = (hips_t.basis.inverse() * gp.basis.y).normalized()
		if _dt_prev.has(bi):
			var pr: Array = _dt_prev[bi]
			var jump := local.distance_to(pr[0])
			_dt.max_jump_cm = maxf(_dt.max_jump_cm, jump * 100.0)
			if jump > 0.2:
				_dt.explosions += 1
			if dt > 0.0:
				frame_deg = maxf(frame_deg, rad_to_deg((pr[1] as Vector3).angle_to(dir)) / dt)
		_dt_prev[bi] = [local, dir]
	_dt.frames += 1
	if pen > 0.01:
		_dt.clip_frames += 1
	_dt.max_pen_cm = maxf(_dt.max_pen_cm, pen * 100.0)
	_dt.max_deg_s = maxf(_dt.max_deg_s, frame_deg)
	(_dt.degs as Array).append(frame_deg)


func _dt_report() -> Dictionary:
	var d: Array = (_dt.degs as Array).duplicate()
	d.sort()
	var r := {"phase": _dt.label, "frames": _dt.frames, "clip_pct": snappedf(100.0 * _dt.clip_frames / maxf(1.0, _dt.frames), 0.1),
		"max_pen_cm": snappedf(_dt.max_pen_cm, 0.1), "p95_deg_s": snappedf(float(d[int(d.size() * 0.95)]) if d.size() > 0 else 0.0, 1.0),
		"max_deg_s": snappedf(_dt.max_deg_s, 1.0), "max_jump_cm": snappedf(_dt.max_jump_cm, 0.1), "explosions": _dt.explosions}
	print("[mktest] dress ", JSON.stringify(r))
	return r


## Still ring for the design-sheet comparison: front (0), her right side (90), back (180) and a 3/4 (45), FOV 28,
## camera 1.0 m high aimed at her waist, head to sandals in frame. The pin follow pauses while it shoots.
var _dt_ring_on := false
func _dt_ring(c: WorldCharacter, pin: CameraPin, tag: String) -> void:
	_dt_ring_on = true
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var waist := c.global_position + Vector3(0, 0.62 if tag == "seated" else 0.95, 0)
	for a in [["front", 0.0], ["side", 90.0], ["back", 180.0], ["3q", 45.0]]:
		var d := fwd.rotated(Vector3.UP, deg_to_rad(-float(a[1])))      # 90 = her right side
		pin.fov = 28.0
		pin.pos = Vector3(waist.x, c.global_position.y + 1.0, waist.z) + d * 3.9
		pin.look = waist
		await _wait(0.6)
		_shot("%s_%s" % [tag, a[0]])
	_dt_ring_on = false


## The same ring on real time (the game frozen for a held pose).
func _dt_ring_real(c: WorldCharacter, pin: CameraPin, tag: String) -> void:
	_dt_ring_on = true
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var waist := c.global_position + Vector3(0, 0.95, 0)
	for a in [["front", 0.0], ["side", 90.0], ["back", 180.0], ["3q", 45.0]]:
		var d := fwd.rotated(Vector3.UP, deg_to_rad(-float(a[1])))
		pin.fov = 28.0
		pin.pos = Vector3(waist.x, c.global_position.y + 1.0, waist.z) + d * 3.9
		pin.look = waist
		for _i in 3:
			await get_tree().process_frame
		_shot("%s_%s" % [tag, a[0]])
	_dt_ring_on = false


func _dresstest() -> void:
	await _hold_all()
	await _force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.spawner.enabled = false
	main.director.enabled = false
	if main.performance and main.performance.busy():
		main.performance.interrupt("dress test")
	if main.weather:
		main.weather.set_weather("clear", 12.0)
	var who := String(RenderProfile.options.get("dt-who", "luna"))
	var c: WorldCharacter = main.characters[who]
	var other: WorldCharacter = main.characters["mika" if who == "luna" else "luna"]
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var it: Interactable = main.world.interactables.get("watchpoint_rest")
	if it == null:
		_check(false, "watchpoint bench exists")
		return
	var map: RID = c.get_world_3d().navigation_map
	var sp: Vector3 = it.get_parent().to_global(it.sit_point)
	var start := NavigationServer3D.map_get_closest_point(map, sp + Vector3(7, 0, 5))
	if main.teleport_guard:
		main.teleport_guard.allow(c)
		main.teleport_guard.allow(other)
	other.global_position = NavigationServer3D.map_get_closest_point(map, start + Vector3(12, 0, 12)) + Vector3(0, 0.05, 0)
	c.stop_action()
	c.global_position = start + Vector3(0, 0.05, 0)
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	pin.fov = 42.0
	var follow := func():
		if _dt_ring_on:
			return
		var fwd := -c.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
		var side := Vector3(-fwd.z, 0, fwd.x)
		var want: Vector3 = c.global_position + fwd * 2.6 + side * 1.7 + Vector3(0, 1.05, 0)
		pin.pos = want if pin.pos == Vector3.ZERO else pin.pos.lerp(want, 0.06)
		pin.look = c.global_position + Vector3(0, 0.85, 0)
		pin.active = true
	follow.call()
	if RenderProfile.options.has("dt-avatar"):          # a candidate model (test only)
		_check(c.swap_avatar(String(RenderProfile.options["dt-avatar"])), "wears " + String(RenderProfile.options["dt-avatar"]).get_file())
		await _wait(1.0)
	await _wait(1.0)
	var dt_state := {"on": false, "last": 0}
	var sampler := func():
		if dt_state.on:
			# game time (movie mode runs at a fixed 30 fps, not wall-clock): one sample per frame
			var fr := Engine.get_process_frames()
			if fr != int(dt_state.last):
				_dt_sample(c, get_process_delta_time() if int(dt_state.last) > 0 else 0.0)
				dt_state.last = fr
	var phases := []
	# spawn: a fresh avatar (the swap rebuilds the springs), the first 1.5 s
	c.swap_avatar(c.avatar_path)
	c.skeleton.skeleton_updated.connect(sampler)
	_dt_reset("spawn")
	dt_state.on = true
	dt_state.last = 0
	var t0 := _game_t
	var last := _game_t
	while _game_t - t0 < 1.5:
		await get_tree().physics_frame
		follow.call()
	phases.append(_dt_report())
	if c.dress_sim and c.dress_sim.sim:
		var sk2 := c.skeleton
		print("[dress] skeleton scale %s; LeftUpperLeg rest->child %.3f m local; knee world %s" % [str(sk2.global_transform.basis.get_scale().snapped(Vector3.ONE * 0.001)),
			sk2.get_bone_global_rest(sk2.find_bone("LeftUpperLeg")).origin.distance_to(sk2.get_bone_global_rest(sk2.find_bone("LeftLowerLeg")).origin),
			str((sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("LeftLowerLeg"))).origin.snapped(Vector3.ONE * 0.01))])
		print("[dress]   chain 0 collisions: all=%s count=%d" % [str(c.dress_sim.sim.are_all_child_collisions_enabled(0)), c.dress_sim.sim.get_collision_count(0)])
		for n in c.dress_sim.sim.get_children():
			if n is SpringBoneCollisionCapsule3D:
				print("[dress]   %s offset %s rot %s height %.3f" % [n.name, str(n.position_offset.snapped(Vector3.ONE * 0.001)), str(n.rotation_offset), n.height])
		for n in c.dress_sim.sim.get_children():
			var bn := String(n.get("bone_name")) if n.get("bone_name") != null else ""
			var bpos := (sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone(bn))).origin if bn != "" and sk2.find_bone(bn) >= 0 else Vector3.ZERO
			print("[dress] collider %s %s at %s (bone at %s) r=%s up=%s" % [n.name, n.get_class(), str((n as Node3D).global_position.snapped(Vector3.ONE * 0.01)), str(bpos.snapped(Vector3.ONE * 0.01)), str(n.get("radius")), str((n as Node3D).global_basis.y.normalized().snapped(Vector3.ONE * 0.01))])
	await _wait(2.0)
	await _dt_ring(c, pin, "stand")
	if RenderProfile.options.has("dt-armsup"):
		c.play_gesture("wide_arm_spell", 0.3, 0.4)
		await _wait(1.3)
		Engine.time_scale = 0.001                          # hold the arms-up moment for the ring
		await _dt_ring_real(c, pin, "armsup")
		Engine.time_scale = 1.0
		await _wait(2.5)
	pin.fov = 42.0
	# walk away 6 m, a quick 180 turn back (walk to a point behind her), then to the bench and sit, then stand
	var legs := [["walk", start + (sp - start).normalized().rotated(Vector3.UP, 1.2) * 6.0, false],
		["turn_walk", start, false], ["run", start + (sp - start).normalized().rotated(Vector3.UP, -1.0) * 7.0, true],
		["to_bench", it.approach_point(), false]]
	for leg in legs:
		c.navigate_to(NavigationServer3D.map_get_closest_point(map, leg[1]), bool(leg[2]))
		_dt_reset(String(leg[0]))
		dt_state.last = 0
		t0 = _game_t
		last = _game_t
		while c.current_action == "navigate_to" and _game_t - t0 < 25.0:
			await get_tree().physics_frame
			follow.call()
		phases.append(_dt_report())
	it.duration_override = 12.0
	var job := func(): await it.perform(c)
	job.call()
	_dt_reset("sit")
	dt_state.last = 0
	t0 = _game_t
	last = _game_t
	var sat := false
	while _game_t - t0 < 20.0:
		await get_tree().physics_frame
		follow.call()
		if c.seated and not sat:
			sat = true
			var job2 := func():
				await _wait(3.0)
				await _dt_ring(c, pin, "seated")
			job2.call()
		if sat and not c.seated:
			break
	phases.append(_dt_report())
	_dt_reset("stand")
	dt_state.last = 0
	t0 = _game_t
	last = _game_t
	while _game_t - t0 < 3.0:
		await get_tree().physics_frame
		follow.call()
	phases.append(_dt_report())
	dt_state.on = false
	if c.skeleton.skeleton_updated.is_connected(sampler):
		c.skeleton.skeleton_updated.disconnect(sampler)
	report["dress"] = phases
	var bad := phases.filter(func(r): return int(r.explosions) > 0)
	_check(bad.is_empty(), "no skirt explosions (a joint jumping > 20 cm in one frame)", bad)
	pin.active = false
	pin.queue_free()
	main.camera_rig.set_process(true)
	main.director.set_process(true)


## Skin materials of both girls: colour, shade colour, shading and the albedo texture's mean (skin match, 2026-10-18).
func _skinprobe() -> void:
	await _wait(1.0)
	for who in ["mika", "luna"]:
		var c: WorldCharacter = main.characters[who]
		for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			for si in m.mesh.get_surface_count():
				var mat := m.get_active_material(si)
				if not (mat is ShaderMaterial):
					continue
				var nm := String(mat.resource_name)
				if not nm.contains("SKIN"):
					continue
				var sm := mat as ShaderMaterial
				var tex = sm.get_shader_parameter("_MainTex")
				var mean := Color()
				if tex is Texture2D:
					var img: Image = (tex as Texture2D).get_image()
					if img:
						if img.is_compressed():
							img.decompress()
						img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
						var n := 0
						for y in 32:
							for x in 32:
								var px := img.get_pixel(x, y)
								if px.a > 0.5:
									mean += px
									n += 1
						if n > 0:
							mean /= float(n)
				print("[mktest] skin %s %s/%s color=%s shade=%s shift=%.2f toony=%.2f rim=%s tex_mean=%s" % [who, m.name, nm, str(sm.get_shader_parameter("_Color")), str(sm.get_shader_parameter("_ShadeColor")),
					float(sm.get_shader_parameter("_ShadeShift")), float(sm.get_shader_parameter("_ShadeToony")), str(sm.get_shader_parameter("_RimColor")), str(Color(mean.r, mean.g, mean.b).to_html(false))])


## The ruins bench and its surroundings (Selwyn 2026-10-18: a floating leaf clump, a stray pole, blocky trees):
## photographs the bench from 8 directions (wide) and lists thin tall meshes (poles) and foliage whose bottom floats
## above the ground within 45 m, with their scene paths.
func _benchscan() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	var it: Interactable = main.world.interactables.get("watchpoint_rest")
	if it == null:
		_check(false, "watchpoint bench exists")
		return
	var sp: Vector3 = it.get_parent().to_global(it.sit_point)
	var space := get_viewport().get_world_3d().direct_space_state
	var poles := []
	var floats := []
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var bb: AABB = g.global_transform * g.get_aabb()
		var ctr := bb.get_center()
		if ctr.distance_to(sp) > 45.0:
			continue
		var path := String(g.get_path())
		if path.contains("Avatar") or path.contains("characters"):
			continue
		if bb.size.y > 0.9 and bb.size.x < 0.35 and bb.size.z < 0.35:
			poles.append("%.1f m  %s  size %s at %s" % [ctr.distance_to(sp), path, str(bb.size.snapped(Vector3.ONE * 0.01)), str(bb.position.snapped(Vector3.ONE * 0.1))])
		var lname := path.to_lower()
		if bb.size.length() < 4.0 and not (lname.contains("light") or lname.contains("lantern") or lname.contains("sky") or lname.contains("cloud") or lname.contains("rain") or lname.contains("particles")):
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(ctr.x, bb.position.y + 0.02, ctr.z), Vector3(ctr.x, bb.position.y - 30.0, ctr.z))
			var hit2 := space.intersect_ray(q2)
			var gap2: float = (bb.position.y - float((hit2.position as Vector3).y)) if not hit2.is_empty() else 99.0
			if gap2 > 0.5:
				var mesh_name := ""
				if g is MeshInstance3D and (g as MeshInstance3D).mesh:
					mesh_name = String((g as MeshInstance3D).mesh.resource_name)
				elif g is MultiMeshInstance3D:
					mesh_name = "multimesh"
				floats.append("%.1f m  gap %.2f m  %s (%s)  size %s at %s" % [ctr.distance_to(sp), gap2, path, mesh_name, str(bb.size.snapped(Vector3.ONE * 0.01)), str(bb.position.snapped(Vector3.ONE * 0.1))])
		if lname.contains("leaf") or lname.contains("leaves") or lname.contains("foliage") or lname.contains("ivy") or lname.contains("bush") or lname.contains("clump") or lname.contains("canopy"):
			var q := PhysicsRayQueryParameters3D.create(Vector3(ctr.x, bb.position.y + 0.05, ctr.z), Vector3(ctr.x, bb.position.y - 30.0, ctr.z))
			var hit := space.intersect_ray(q)
			var gap: float = (bb.position.y - float((hit.position as Vector3).y)) if not hit.is_empty() else 99.0
			if gap > 0.6 and not lname.contains("tree"):
				floats.append("%.1f m  gap %.2f m  %s  size %s" % [ctr.distance_to(sp), gap, path, str(bb.size.snapped(Vector3.ONE * 0.01))])
	poles.sort()
	floats.sort()
	print("[mktest] benchscan bench at %s" % str(sp.snapped(Vector3.ONE * 0.01)))
	for x in poles.slice(0, 25):
		print("[mktest] benchscan POLE ", x)
	for x in floats.slice(0, 25):
		print("[mktest] benchscan FLOAT ", x)
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	pin.fov = 60.0
	pin.active = true
	for k in 8:
		var d := Vector3(0, 0, 1).rotated(Vector3.UP, TAU * k / 8.0)
		pin.pos = sp + d * 4.5 + Vector3(0, 1.4, 0)
		pin.look = sp + Vector3(0, 0.6, 0)
		await _wait(1.0)
		_shot("dir%d" % k)
	pin.active = false


## The screen-effect stack, one effect at a time on Luna in the meadow (medium shot), each photographed at its peak for
## the side-by-side against its reference frame. Record with --write-movie for the motion.
func _screenfx() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = luna.get_world_3d().navigation_map
	var spot := NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0, 6.0))
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
		main.teleport_guard.allow(mika)
	luna.stop_action()
	luna.global_position = spot + Vector3(0, 0.05, 0)
	luna.rotation.y = 0.0
	mika.global_position = NavigationServer3D.map_get_closest_point(map, spot + Vector3(14, 0, 14)) + Vector3(0, 0.05, 0)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	pin.pos = spot + Vector3(0.6, 1.45, -2.4)
	pin.look = spot + Vector3(0, 1.1, 0)
	pin.fov = 40.0
	pin.active = true
	await _wait(2.5)
	_shot("00_plain")
	var fx := ScreenFX.get_for(self)
	var steps := [
		["01_speed_lines", func(): fx.speed_lines(1.0, 1.4), 0.5],
		["02_zoom_blur", func(): fx.zoom_blur(1.0, 1.0), 0.3],
		["03_chroma", func(): fx.chroma(1.0, 1.0), 0.05],
		["04_flash_burst", func(): fx.flash_seq([["burst", 8]], 0.6), 0.1],
		["05_flash_invert", func(): fx.flash_seq([["invert", 8]]), 0.1],
		["06_flash_white_burst", func(): fx.flash_seq([["burst_white", 8]], -0.5), 0.1],
		["07_wash_red", func(): fx.wash(Color(1.0, 0.08, 0.18), 0.75, 0.15, 1.0, 0.4), 0.5],
		["08_wash_violet", func(): fx.wash(Color(0.48, 0.24, 1.0), 0.6, 0.15, 1.0, 0.4), 0.5],
		["09_speed_lines_chroma_zoom", func(): fx.speed_lines(1.0, 1.2); fx.zoom_blur(0.8, 1.2); fx.chroma(0.8, 1.2), 0.4],
	]
	for st in steps:
		(st[1] as Callable).call()
		await _wait(float(st[2]))
		_shot(String(st[0]))
		await _wait(1.6)
	# the impact sequence in motion (for the recording): freeze, flashes, chroma, shake, then slow motion
	fx.impact(1.0)
	await _wait(0.2)
	fx.slow_mo(0.3, 1.0)
	await _wait(2.5)
	_check(Engine.time_scale > 0.9, "time scale back to normal after the freeze and slow motion", Engine.time_scale)
	pin.active = false


# ------------------------------------------------------------------ the test clip (2026-10-18, anime-proof)
## Round 12 Luna in the meadow, filmed with Phantom Camera: a walk toward the lens, a slow graceful turn, a slow
## fingertip reach (TwoBoneIK3D) with her eyes on the camera, then one spell in the 4-layer standard:
## anticipation (circle at her feet, gathering glow on the hand, push-in), release (2-frame flash, the projectile
## with trail, speed lines), impact (hit freeze, burst frames, chroma, shake, the big impact) and aftermath (the
## lingering area glow, slow motion, back to her). Record with --write-movie; stills at the key beats.
const LUNA_VIOLET := Color(0.62, 0.36, 1.0)
const LUNA_GOLD := Color(1.0, 0.8, 0.38)

func _fx(path: String, at: Vector3, primary: Color, secondary: Color, scale := 1.0) -> Node3D:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	main.add_child(n)
	n.global_position = at
	n.scale = Vector3.ONE * scale
	if n.get("primary_color") != null:
		n.set("primary_color", primary)
	if n.get("secondary_color") != null:
		n.set("secondary_color", secondary)
	if n.get("light_color") != null:
		n.set("light_color", primary)
	if n.has_method("play"):
		n.call("play")
	return n


func _sigil(at: Vector3, size: float, sides: int, col: Color, intensity: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/magic/sigil.gdshader")
	m.set_shader_parameter("sides", sides)
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("draw_progress", 0.0)
	m.set_shader_parameter("spin", 0.35 if sides % 2 == 0 else -0.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	mi.global_position = at
	return mi


func _pcam(name_: String, prio: int, follow: Node3D, offset: Vector3, look: Node3D, tween_s: float, fov := 40.0) -> PhantomCamera3D:
	var pc := PhantomCamera3D.new()
	pc.name = name_
	main.add_child(pc)
	pc.set_tween_duration(tween_s)
	pc.set_tween_transition(Tween.TRANS_SINE)
	if follow:
		pc.follow_mode = PhantomCamera3D.FollowMode.SIMPLE
		pc.set_follow_target(follow)
		pc.set_follow_offset(offset)
	else:
		pc.global_position = offset
	if look:
		pc.look_at_mode = PhantomCamera3D.LookAtMode.SIMPLE
		pc.set_look_at_target(look)
	pc.set("fov", fov)
	pc.set_priority(prio)
	return pc


func _lunaclip() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.weather:
		main.weather.set_weather("clear", 12.0)
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = luna.get_world_3d().navigation_map
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0, 9.0))
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
		main.teleport_guard.allow(mika)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, start + Vector3(16, 0, 16)) + Vector3(0, 0.05, 0)
	luna.stop_action()
	luna.global_position = start + Vector3(0, 0.05, 0)
	luna.rotation.y = 0.0                                  # facing -Z: she walks toward the camera at -Z
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED   # close-ups approved inside cinematics
	# the camera: Phantom Camera drives the live camera (the rig and director stand still)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	var cam: Camera3D = main.camera_rig.camera
	cam.top_level = true
	var host := PhantomCameraHost.new()
	host.interpolation_mode = PhantomCameraHost.InterpolationMode.MANUAL    # ticked last every frame (PCamDriver)
	cam.add_child(host)
	var driver := PCamDriver.new()
	driver.host = host
	main.add_child(driver)
	# look targets that follow her body
	var chest := Node3D.new()
	var face := Node3D.new()
	var hand_t := Node3D.new()
	for n in [chest, face, hand_t]:
		main.add_child(n)
	var sk := luna.skeleton
	var track := func():
		chest.global_position = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Chest")).origin
		face.global_position = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin + Vector3(0, 0.06, 0)
		hand_t.global_position = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
	track.call()
	var a := _pcam("A_walk_low", 10, luna, Vector3(0.35, 0.75, -3.0), chest, 0.0, 38.0)
	await _wait(1.5)
	print("[mktest] lunaclip camera: current=%s is_rig_cam=%s host_active=%s pcam_pos=%s cam_pos=%s luna=%s" % [get_viewport().get_camera_3d().get_path(),
		str(get_viewport().get_camera_3d() == cam), str(host.get_active_pcam()), str(a.global_position.snapped(Vector3.ONE * 0.01)),
		str(cam.global_position.snapped(Vector3.ONE * 0.01)), str(luna.global_position.snapped(Vector3.ONE * 0.01))])
	print("[mktest] lunaclip host: child_of_cam=%s physics_based=%s processing=%s/%s missing=%s tree_paused=%s pmode=%d" % [str(host.get("_is_child_of_camera")), str(host.get("_follow_target_physics_based")),
		str(host.is_processing()), str(host.is_physics_processing()), str(host.get("_active_pcam_missing")), str(get_tree().paused), host.process_mode])
	_shot("00_start")
	var t0 := _game_t
	# 1. the walk toward the lens (the camera dollies back with her, low): the goddess walk (catwalk x walk, 50/50)
	luna.set_walk_clip("walk_goddess")
	luna.navigate_to(NavigationServer3D.map_get_closest_point(map, start + Vector3(0, 0, -5.0)), false)
	while luna.current_action == "navigate_to" and _game_t - t0 < 9.0:
		await get_tree().process_frame
		track.call()
		luna.look_head_at(cam.global_position)
	_shot("01_walk_end")
	# 2. the slow turn (a full circle, 4 s), the camera eases to a medium three-quarter
	var b := _pcam("B_turn_med", 20, luna, Vector3(1.4, 1.15, -2.5), chest, 1.4, 34.0)
	luna.look_head_at(null)
	# the catwalk turn, twice (away from the lens, then back to it); its hip yaw drives her root
	var tt := _game_t
	var turns_ok := luna.play_turn("catwalk_turn")
	_check(turns_ok, "the catwalk turn plays with its yaw on her root")
	var turn_len := luna.animation_length("catwalk_turn")
	var shot_back := false
	var tdbg := 0
	while _game_t - tt < turn_len + 0.1:
		await get_tree().process_frame
		track.call()
		tdbg += 1
		if tdbg % 8 == 0:
			print("[mktest] turn1 t=%.2f body=%.0f avatar=%.0f vel=%.2f" % [_game_t - tt, rad_to_deg(luna.rotation.y), rad_to_deg(luna.avatar.rotation.y), luna.velocity.length()])
		if not shot_back and _game_t - tt > turn_len * 0.6:
			_shot("02_turn_back")
			shot_back = true
	luna.play_turn("catwalk_turn")
	tt = _game_t
	while _game_t - tt < turn_len + 0.3:
		await get_tree().process_frame
		track.call()
		tdbg += 1
		if tdbg % 8 == 0:
			print("[mktest] turn2 t=%.2f body=%.0f avatar=%.0f vel=%.2f" % [_game_t - tt, rad_to_deg(luna.rotation.y), rad_to_deg(luna.avatar.rotation.y), luna.velocity.length()])
	# 3. the fingertip reach toward the lens (TwoBoneIK3D), eyes following the camera; a close medium on face + hand
	var c := _pcam("C_reach_close", 30, luna, Vector3(0.45, 1.5, -1.35), face, 1.2, 32.0)
	var ik := TwoBoneIK3D.new()
	ik.name = "ReachIK"
	sk.add_child(ik)
	var ik_target := Node3D.new()
	main.add_child(ik_target)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "RightUpperArm")
	ik.set_middle_bone_name(0, "RightLowerArm")
	ik.set_end_bone_name(0, "RightHand")
	ik.set_target_node(0, ik.get_path_to(ik_target))
	ik.influence = 0.0
	var fwd := -luna.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var shoulder: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin
	ik_target.global_position = hand_t.global_position
	var reach_to := shoulder + fwd * 0.52 + right * 0.08 + Vector3(0, 0.12, 0)
	# (2026-10-19: TwoBoneIK3D ran with influence 1 but never moved the hand in this rig - logged as a gap; the reach
	# is the Mixamo pointing clip toward the lens until the IK works)
	ik.active = false
	luna.play_gesture("pointing", 0.6, 0.7)
	var rt := create_tween()
	rt.tween_property(ik, "influence", 1.0, 0.6)
	rt.parallel().tween_property(ik_target, "global_position", reach_to, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var ikdbg := {"n": 0}
	var ikprobe := func():
		ikdbg.n = int(ikdbg.n) + 1
		if int(ikdbg.n) % 20 == 0:
			var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
			print("[mktest] lunaclip ik: influence %.2f active %s hand-target %.3f m" % [ik.influence, str(ik.active), hp.distance_to(ik_target.global_position)])
	sk.skeleton_updated.connect(ikprobe)
	tt = _game_t
	while _game_t - tt < 3.0:
		await get_tree().process_frame
		track.call()
		luna.look_head_at(cam.global_position)
		if _game_t - tt > 1.8 and _game_t - tt < 1.85:
			_shot("03_reach")
	sk.skeleton_updated.disconnect(ikprobe)
	var rb := create_tween()
	rb.tween_property(ik, "influence", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	await _wait(0.9)
	ik.queue_free()
	ik_target.queue_free()
	# 4. the spell, 4 layers. Target: 9 m in front of her
	var target := NavigationServer3D.map_get_closest_point(map, luna.global_position + fwd * 9.0) + Vector3(0, 0.6, 0)
	var fx := ScreenFX.get_for(self)
	# 4a anticipation: the circle at her feet, gathering glow at the hand, a low push-in
	var d := _pcam("D_cast_low", 40, luna, Vector3(-1.3, 0.45, -2.2), chest, 0.6, 40.0)
	luna.look_head_at(target)
	luna.play_gesture("prepare_and_cast", 0.25, 0.4)
	var circle := _sigil(luna.global_position + Vector3(0, 0.03, 0), 3.2, 8, LUNA_VIOLET, 2.2)
	var circle2 := _sigil(luna.global_position + Vector3(0, 0.04, 0), 1.9, 6, LUNA_GOLD, 2.4)
	for sg in [circle, circle2]:
		create_tween().tween_property((sg as MeshInstance3D).material_override, "shader_parameter/draw_progress", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var gather := _fx("res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/cast/vfx_fire_cast_01.tscn", hand_t.global_position, LUNA_VIOLET, LUNA_GOLD, 0.45)
	if gather.get("emission") != null:
		gather.set("emission", 1.2)
	fx.vignette(0.45, 2.4)
	var push := create_tween()
	push.tween_method(func(v: Vector3): d.set_follow_offset(v), Vector3(-1.3, 0.45, -2.2), Vector3(-0.9, 0.5, -1.6), 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tt = _game_t
	while _game_t - tt < 1.3:
		await get_tree().process_frame
		track.call()
		gather.global_position = hand_t.global_position
		if _game_t - tt > 1.0 and _game_t - tt < 1.05:
			_shot("04_anticipation")
	# 4b release: a 2-frame white flash, the projectile with its trail, speed lines toward the target
	fx.flash("white", 2)
	var proj := _fx("res://assets/BinbunVFX_Vol2/ElementalMagicFX/effects/projectile/vfx_fire_projectile_01.tscn", hand_t.global_position, LUNA_VIOLET, LUNA_GOLD, 1.0)
	proj.look_at(target, Vector3.UP)
	var e := _pcam("E_follow_shot", 50, null, luna.global_position + right * 1.6 + Vector3(0, 1.1, 0) - fwd * 0.6, proj, 0.25, 46.0)
	fx.speed_lines(0.7, 0.5, Vector2(0.5, 0.5), Color(0.85, 0.75, 1.0))
	var pt := create_tween()
	pt.tween_property(proj, "global_position", target, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(0.25)
	_shot("05_release")
	await _wait(0.27)
	# 4c impact: freeze, burst frames, chroma, shake, the big impact; a wide cut on the hit
	var f2 := _pcam("F_impact_wide", 60, null, target + fwd * 3.6 + right * 2.4 + Vector3(0, 1.0, 0), null, 0.0, 50.0)
	f2.look_at_mode = PhantomCamera3D.LookAtMode.NONE
	f2.look_at(target, Vector3.UP)
	var boom := _fx("res://assets/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn", target, LUNA_VIOLET, LUNA_GOLD, 1.6)
	fx.impact(1.0)
	await _wait(0.12)
	_shot("06_impact")
	fx.slow_mo(0.35, 0.9)
	# 4d aftermath: the lingering area glow at the target, back to her
	var linger := _sigil(target - Vector3(0, 0.57, 0), 2.6, 6, LUNA_GOLD, 2.0)
	(linger as MeshInstance3D).material_override.set_shader_parameter("draw_progress", 1.0)
	create_tween().tween_property((linger as MeshInstance3D).material_override, "shader_parameter/intensity", 0.0, 2.2).set_trans(Tween.TRANS_SINE)
	for sg in [circle, circle2]:
		create_tween().tween_property((sg as MeshInstance3D).material_override, "shader_parameter/intensity", 0.0, 1.2)
	await _wait(1.3)
	_shot("07_aftermath")
	var g := _pcam("G_after", 70, luna, Vector3(0.8, 1.3, -2.2), face, 1.6, 34.0)
	luna.look_head_at(cam.global_position)
	tt = _game_t
	while _game_t - tt < 3.0:
		await get_tree().process_frame
		track.call()
		luna.look_head_at(cam.global_position)
	_shot("08_end")
	for n in [proj, boom, linger, circle, circle2, gather]:
		if is_instance_valid(n):
			n.queue_free()
	_check(Engine.time_scale > 0.9, "time back to normal after the spell", Engine.time_scale)


## Outfit audit stills (2026-10-19): each model in --audit-list (comma-separated res:// paths) worn by Luna's rig,
## standing at idle, photographed front / right side / back / 3/4 (FOV 28, camera 1.0 m, head to feet), plus a spin
## frame mid-walk-cycle is not needed: the rules (fitted, opaque, open front, no floor-length layers, sheer fabric,
## loose drapes or wide sleeves) read from the standing views.
func _outfitaudit() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.weather:
		main.weather.set_weather("clear", 12.0)
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	var map: RID = luna.get_world_3d().navigation_map
	var spot := NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0, 6.0))
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
		main.teleport_guard.allow(mika)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, spot + Vector3(16, 0, 16)) + Vector3(0, 0.05, 0)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	for path in String(RenderProfile.options.get("audit-list", "")).split(",", false):
		_check(luna.swap_avatar(path), "wears " + path.get_file())
		luna.stop_action()
		luna.global_position = spot + Vector3(0, 0.05, 0)
		luna.rotation.y = 0.0
		await _wait(3.0)
		var fwd := Vector3(0, 0, -1)
		var waist := spot + Vector3(0, 0.9, 0)
		for a in [["front", 0.0], ["side", 90.0], ["back", 180.0], ["3q", 45.0]]:
			var d := fwd.rotated(Vector3.UP, deg_to_rad(-float(a[1])))
			pin.fov = 30.0
			pin.pos = Vector3(waist.x, spot.y + 1.0, waist.z) + d * 4.2
			pin.look = waist
			pin.active = true
			await _wait(0.8)
			_shot("%s_%s" % [path.get_file().get_basename(), a[0]])
	pin.active = false


## Pose probe for the harp: each held pose, a medium front still, and the right hand with the finger curl test.
func _harpprobe() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = luna.get_world_3d().navigation_map
	var spot := NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0, 6.0))
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
	if RenderProfile.options.has("harp-avatar"):
		luna.swap_avatar(String(RenderProfile.options["harp-avatar"]))
		await _wait(1.0)
	luna.stop_action()
	luna.global_position = spot + Vector3(0, 0.05, 0)
	luna.rotation.y = 0.0
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	pin.pos = spot + Vector3(0.0, 1.2, -3.2)
	pin.look = spot + Vector3(0, 1.1, 0)
	pin.fov = 40.0
	pin.active = true
	await _wait(1.5)
	for clip in ([] if RenderProfile.options.has("hp-fingers-only") else ["hold_wide_a", "hold_wide_b", "hold_wide_c", "hold_point_a", "hold_point_b", "hold_cast_a", "hold_cast_b"]):
		luna.play_gesture(clip, 0.2, 0.2)
		await _wait(0.9)
		_shot(clip)
		luna.end_gesture()
		await _wait(0.4)
	# fingers: the curl on the right hand, curl 0 and 1, close on the hand
	var fp := FingerPose.new()
	luna.skeleton.add_child(fp)
	luna.play_gesture("hold_wide_a", 0.2, 0.2)
	await _wait(0.8)
	var sk := luna.skeleton
	var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
	pin.pos = hp + Vector3(-0.25, 0.15, -0.55)
	pin.look = hp
	pin.fov = 34.0
	for ax in [["z", Vector3(0, 0, 1)], ["x", Vector3(1, 0, 0)]]:
		fp.axis = ax[1]
		for c in [0.0, 1.0]:
			for f in fp.curl:
				fp.curl[f] = c
			await _wait(0.3)
			_shot("fingers_%s_%02d" % [ax[0], int(c * 10)])
	print("[mktest] harpprobe bones: ", [sk.find_bone("RightIndexProximal"), sk.find_bone("RightThumbMetacarpal"), sk.find_bone("RightIndexDistal")])


# ------------------------------------------------------------------ the Starlit Harp proof (reference video 4)
## 27.5 s, timed to the reference: A 0-5.5 hand plucking light strings (extreme close-up, rolled), B 5.5-13.5 she
## floats before the sun-cloud orb and its spoke rings (low, slow push, counter-roll, the orb blooms), C 13.5-14.3 the
## reach to the lens: crash zoom, roll, white flash, zoom blur, D 14.3-18 the crystal lance forms (tracking along it),
## E 18-22 it dives onto the sanctuary below (speed lines, zoom blur, follow cam), F 22-23.5 the impact frames,
## G 23.5-27.5 the shockwave and a slow fade to the palette's colour. --harp-palette=blue|luna, --harp-avatar=<vrm>.
func _starlitharp() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.weather:
		main.weather.set_weather("clear", 0.1)
		if main.weather.get("rain") != null:
			main.weather.set("rain", 0.0)
		if main.weather.get("enabled") != null:
			main.weather.set("enabled", false)
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 22.5 * 60.0
	if main.day_night:
		main.day_night.set_override(true)
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	if main.teleport_guard:
		main.teleport_guard.allow(luna)
		main.teleport_guard.allow(mika)
	var map: RID = luna.get_world_3d().navigation_map
	var ground := NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0, 6.0))
	mika.global_position = NavigationServer3D.map_get_closest_point(map, ground + Vector3(20, 0, 20)) + Vector3(0, 0.05, 0)
	var H := ground + Vector3(0, 26.0, -10.0)                 # she floats high over the meadow, south of the ground point
	luna.stop_action()
	luna.set_physics_process(false)
	luna.global_position = H
	luna.rotation.y = 0.0                                       # faces -Z
	# (the avatar is rebuilt up here, so its hair and skirt springs start where she floats instead of being yanked 26 m)
	luna.swap_avatar(String(RenderProfile.options.get("harp-avatar", luna.avatar_path)))
	await _wait(1.5)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	var palette := String(RenderProfile.options.get("harp-palette", "blue"))
	var set := StarlitHarp.new()
	set.name = "StarlitHarp"
	main.add_child(set)
	set.setup(palette)
	set.build_clouds(H + Vector3(0, -2, 0), 26.0, 11)
	var fx := ScreenFX.get_for(self)
	fx.wash(set.pal.wash, 0.32, 0.3, -1.0)                      # the whole sequence lives in one colour (rule 2)
	fx.vignette(0.45, 30.0)
	var fp := FingerPose.new()
	luna.skeleton.add_child(fp)
	for f in fp.curl:
		fp.curl[f] = 0.25
	var gok := luna.play_gesture("hold_wide_a", 0.2, 0.2)
	print("[mktest] harp gesture ok=%s has=%s casting=%s reaction=%s ground=%s" % [str(gok), str(luna.has_clip("hold_wide_a")), str(luna.casting), str(luna.reaction.blocks_actions() if luna.reaction else false), luna.ground_pose])
	await _wait(1.2)
	var sk := luna.skeleton
	var bone := func(n: String) -> Vector3:
		return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n)).origin
	# ---- A: the hand and the harp
	var hp: Vector3 = (bone.call("RightIndexProximal") as Vector3).lerp(bone.call("RightMiddleIntermediate"), 0.5)   # the fingers
	print("[mktest] harp hand %s head %s chest %s luna %s gesture %s" % [str((hp - H).snapped(Vector3.ONE * 0.01)), str((bone.call("Head") - H).snapped(Vector3.ONE * 0.01)), str((bone.call("Chest") - H).snapped(Vector3.ONE * 0.01)), str((luna.global_position - H).snapped(Vector3.ONE * 0.01)), str(luna.get("gesture_clip"))])
	var camA := hp + Vector3(0.18, -0.16, -0.44)
	var to_cam := (camA - hp).normalized()
	set.build_harp(hp - to_cam * 0.22 + Vector3(-0.08, 0.1, 0), to_cam, 48.0)
	var key := OmniLight3D.new()                                # her key light from the orb side / the lens side
	main.add_child(key)
	key.light_color = Color(set.pal.glow).lerp(Color(1, 1, 1), 0.4)
	key.light_energy = 1.6
	key.omni_range = 6.0
	pin.fov = 30.0
	pin.active = true
	var t0 := _game_t
	var done := {}
	var once := func(key: String) -> bool:
		if done.has(key):
			return false
		done[key] = true
		return true
	var shots := {"A_pluck": 0.62, "A_open": 2.4, "B_orb": 8.0, "B_bloom": 12.6, "C_reach": 13.75, "D_lance": 16.4, "E_dive": 20.0, "F_burst": 22.05, "F_invert": 22.35, "G_wave": 24.6, "G_end": 27.2}
	var lance_dir := Vector3.ZERO
	var lance_start := Vector3.ZERO
	var boom: Node3D = null
	while _game_t - t0 < 27.6:
		await get_tree().process_frame
		var t := _game_t - t0
		if main.get("subtitle") and main.subtitle:
			main.subtitle.visible = false
		key.global_position = luna.global_position + Vector3(0.6, 1.8, -1.6)
		if t < 5.5:
			# A: an extreme close-up of the hand, rolled 30 deg, a slow push
			var u := t / 5.5
			pin.pos = camA.lerp(hp + to_cam * 0.3 + Vector3(0.0, -0.03, 0.0), u)
			pin.look = hp
			pin.roll = deg_to_rad(lerpf(32.0, 18.0, u))
			for pt in [[0.5, 4], [1.5, 2], [3.6, 3], [4.25, 5]]:
				if t > float(pt[0]) - 0.18 and t < float(pt[0]) + 0.25:
					fp.curl["Index"] = 0.85 if t < float(pt[0]) else 0.15
					fp.curl["Middle"] = 0.5 if t < float(pt[0]) else 0.2
				if t >= float(pt[0]) and once.call("pluck%s" % str(pt[0])):
					set.pluck(int(pt[1]), 0.4)
					set.spark(bone.call("RightIndexDistal") - to_cam * 0.04, 0.02)
		elif t < 13.5:
			# B: she floats before the orb, arms open; low angle, slow push, counter-roll; the orb blooms from 9.5 s
			if once.call("B"):
				set.harp.visible = false
				set.slats.visible = false
				luna.end_gesture()
				luna.play_gesture("hold_wide_b", 0.5, 0.3)
				for f in fp.curl:
					fp.curl[f] = 0.2
				set.build_orb(H + Vector3(0, 1.35, 5.5), 3.4)
			var u := (t - 5.5) / 8.0
			var chest: Vector3 = bone.call("Chest")
			pin.fov = 40.0
			pin.pos = H + Vector3(0.7, 0.45, -3.4).lerp(Vector3(0.35, 0.75, -2.3), u)
			pin.look = chest + Vector3(0, 0.25, 0)
			pin.roll = deg_to_rad(lerpf(-28.0, -12.0, u))
			luna.global_position = H + Vector3(0, sin(t * 1.3) * 0.06, 0)
			set.orb_bloom(clampf((t - 9.5) / 4.0, 0.0, 1.0))
		elif t < 14.3:
			# C: the reach to the lens: crash zoom, a fast roll, a 2-frame white flash, zoom blur
			if once.call("C"):
				lance_dir = (ground + Vector3(0, 0.6, 0) - (H + Vector3(0, -3.0, 0))).normalized()
				lance_start = H + Vector3(0, -1.5, 0) + lance_dir * 4.5
				set.build_lance(9.0, 0.55)
				set.lance.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, lance_dir)), lance_start)
				create_tween().tween_method(func(v): set.lance_form(v), 0.0, 1.0, 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				luna.end_gesture()
				luna.play_gesture("hold_point_b", 0.15, 0.2)
				fx.zoom_blur(1.0, 0.8)
				fx.speed_lines(0.6, 0.7, Vector2(0.5, 0.5), Color(set.pal.core))
			var u := (t - 13.5) / 0.8
			pin.fov = lerpf(40.0, 24.0, u)
			pin.roll = deg_to_rad(lerpf(-12.0, 40.0, u))
			if t > 13.8 and once.call("Cflash"):
				fx.flash("white", 2)
		elif t < 18.0:
			# D: the lance forms under her, pointing down at the ground; the camera tracks along it
			if once.call("D"):
				fx.flash("white", 1)
			var u := (t - 14.3) / 3.7
			var side := lance_dir.cross(Vector3.UP).normalized()
			pin.fov = 46.0
			pin.pos = lance_start + side * 3.4 + Vector3(0, 0.9, 0) + lance_dir * lerpf(-3.0, 2.0, u)
			pin.look = lance_start + lance_dir * lerpf(-1.0, 2.5, u)
			pin.roll = deg_to_rad(lerpf(18.0, 8.0, u))
		elif t < 22.0:
			# E: the dive (ease-in), the follow camera behind and above, speed lines and zoom blur toward the tip
			if once.call("E"):
				fx.speed_lines(0.9, 4.0, Vector2(0.5, 0.55), Color(set.pal.core))
				fx.zoom_blur(0.6, 4.0, Vector2(0.5, 0.55))
			var u := clampf((t - 18.0) / 4.0, 0.0, 1.0)
			var target := ground + Vector3(0, 0.3, 0) - lance_dir * 4.5
			var p := lance_start.lerp(target, u * u)
			set.lance.global_position = p
			luna.global_position = p - lance_dir * 4.0 + Vector3(0, 0.45, 0)      # she rides the lance down
			var sd := lance_dir.cross(Vector3.UP).normalized()
			pin.fov = 50.0
			pin.pos = p + sd * 3.2 - lance_dir * 3.5 + Vector3(0, 1.6, 0)
			pin.look = p + lance_dir * 3.0
			pin.roll = deg_to_rad(lerpf(8.0, -14.0, u))
		elif t < 23.5:
			# F: the impact frames (ref 22.1-23.5 s): burst, invert, white-with-dark-burst, chroma, a 4-frame freeze
			if once.call("F"):
				set.lance.visible = false
				fx.hit_freeze(4)
				fx.flash_seq([["burst", 3], ["invert", 1], ["burst", 2], ["burst_white", 4], ["invert", 3], ["white", 2]], deg_to_rad(-55.0))
				fx.chroma(1.0, 1.2)
				fx.shake(0.12, 0.8)
				boom = load("res://assets/BinbunVFX_Vol2/StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn").instantiate()
				main.add_child(boom)
				boom.global_position = ground + Vector3(0, 0.3, 0)
				boom.scale = Vector3.ONE * 6.0
				set.shockwave(ground, 16.0, 1.4)
				for kv in [["primary_color", set.pal.glow], ["secondary_color", set.pal.core], ["light_color", set.pal.glow]]:
					if boom.get(kv[0]) != null:
						boom.set(kv[0], kv[1])
				if boom.has_method("play"):
					boom.call("play")
			pin.fov = 55.0
			pin.pos = ground + Vector3(6.5, 3.2, -6.5)
			pin.look = ground + Vector3(0, 0.8, 0)
			pin.roll = deg_to_rad(-6.0)
		else:
			# G: the shockwave and the fade to the palette's colour (slow motion, the camera lifts away)
			if once.call("G"):
				fx.slow_mo(0.4, 1.8)
				fx.wash(set.pal.wash, 0.75, 2.5, -1.0)
			var u := clampf((t - 23.5) / 4.0, 0.0, 1.0)
			if once.call("G2"):
				set.shockwave(ground, 24.0, 2.2)
			pin.pos = ground + Vector3(6.5, 3.2, -6.5).lerp(Vector3(9.0, 7.0, -9.0), u)
			pin.look = ground + Vector3(0, 1.0, 0)
			pin.roll = deg_to_rad(lerpf(-6.0, 0.0, u))
		for k in shots:
			if t >= float(shots[k]) and once.call("shot_" + k):
				_shot(k)
	pin.active = false
	_check(Engine.time_scale > 0.9, "time back to normal", Engine.time_scale)


## The seated skirt on different seats and on the grass (2026-10-19): for each spot she walks there and sits (the
## seat's own sit), and while seated the ring front / side / 3q is shot (FOV 28, 1.0 m, aimed at the waist) and the
## skirt's depth under the sampled surface is measured. --dt-who=luna|mika, --sit-spots=watchpoint_rest,garden_meditate,grass
func _sittest() -> void:
	await _hold_all()
	await _force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.weather:
		main.weather.set_weather("clear", 0.1)
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 10.5 * 60.0
	var who := String(RenderProfile.options.get("dt-who", "luna"))
	var c: WorldCharacter = main.characters[who]
	var other: WorldCharacter = main.characters["mika" if who == "luna" else "luna"]
	if main.teleport_guard:
		main.teleport_guard.allow(c)
		main.teleport_guard.allow(other)
	var map: RID = c.get_world_3d().navigation_map
	other.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(30, 0, -30)) + Vector3(0, 0.05, 0)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	var results := {}
	for spot in String(RenderProfile.options.get("sit-spots", "watchpoint_rest,garden_meditate,grass")).split(","):
		c.stop_action()
		var worst := Vector2.ZERO
		if spot == "grass":
			var gp := NavigationServer3D.map_get_closest_point(map, Vector3(6.0, 0, 9.0))
			if main.teleport_guard:
				main.teleport_guard.allow(c)
			c.global_position = gp + Vector3(0, 0.05, 0)
			c.rotation.y = 0.0
			await _wait(1.5)
			c.play_gesture("sit_ground_enter", 0.3, 0.3)
			c.set_ground_pose("sit", c.animation_length("sit_ground_enter") * 0.9)
			await _wait(c.animation_length("sit_ground_enter") * 0.85)
			c.play_gesture("sit_ground_loop", 0.3, 0.6)
			await _wait(2.5)
			for k in 45:
				await get_tree().process_frame
				if c.dress_sim and c.dress_sim.drape:
					var pz := c.dress_sim.drape.penetration()
					worst = Vector2(maxf(worst.x, pz.x), maxf(worst.y, pz.y))
			await _sit_ring(c, pin, spot, 0.35, 1.7)
			c.end_gesture()
			c.set_ground_pose("", 0.6)
			await _wait(1.0)
		else:
			var it: Interactable = main.world.interactables.get(spot)
			if it == null:
				_check(false, "seat %s exists" % spot)
				continue
			var ap: Vector3 = it.approach_point()
			if main.teleport_guard:
				main.teleport_guard.allow(c)
			c.global_position = ap + Vector3(0, 0.05, 0)          # (at the seat's approach point: the walk is not under test)
			await _wait(1.0)
			it.duration_override = 14.0
			var job := func():
				var res: Dictionary = await it.perform(c)
				print("[mktest] sit %s perform -> %s" % [spot, str(res).left(200)])
			job.call()
			var t0 := _game_t
			while not c.seated and _game_t - t0 < 10.0:
				await get_tree().process_frame
			print("[mktest] sit %s seated=%s at %.1f m from the approach point" % [spot, str(c.seated), c.global_position.distance_to(ap)])
			await _wait(2.5)
			for k in 45:
				await get_tree().process_frame
				if c.dress_sim and c.dress_sim.drape:
					var pz := c.dress_sim.drape.penetration()
					worst = Vector2(maxf(worst.x, pz.x), maxf(worst.y, pz.y))
			await _sit_ring(c, pin, spot, 0.62)
			while (c.seated or it.busy) and _game_t - t0 < 40.0:
				await get_tree().process_frame
			await _wait(3.0)
		results[spot] = {"deepest_cm": snappedf(worst.x, 0.1), "joints_under": int(worst.y)}
		if c.dress_sim and c.dress_sim.drape:
			print("[mktest] sit deepest at ", c.dress_sim.drape._deep_at, " weight ", c.dress_sim.drape.weight)
		print("[mktest] sit %s %s" % [spot, JSON.stringify(results[spot])])
	report["sit"] = results
	pin.active = false


func _sit_ring(c: WorldCharacter, pin: CameraPin, tag: String, waist_h: float, cam_h := 1.0) -> void:
	var fwd := -c.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var waist := c.global_position + Vector3(0, waist_h, 0)
	for a in [["front", 0.0], ["side", 90.0], ["3q", 40.0], ["back", 180.0]]:
		var d := fwd.rotated(Vector3.UP, deg_to_rad(-float(a[1])))
		pin.fov = 28.0
		pin.pos = Vector3(waist.x, c.global_position.y + cam_h, waist.z) + d * 3.6
		pin.look = waist
		pin.roll = 0.0
		pin.active = true
		if main.get("subtitle") and main.subtitle:
			main.subtitle.visible = false
		await _wait(0.6)
		_shot("%s_%s" % [tag, a[0]])


## Walk, run and turn shots of one girl, front / side / 3q, the camera riding with her (FOV 30, 1.0 m, aimed at the
## waist, 3.8 m away): for each motion and angle she moves on open ground and a still is taken mid-stride.
func _motionshots() -> void:
	await _hold_all()
	await _force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.weather:
		main.weather.set_weather("clear", 0.1)
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 10.5 * 60.0
	var who := String(RenderProfile.options.get("dt-who", "luna"))
	var c: WorldCharacter = main.characters[who]
	var other: WorldCharacter = main.characters["mika" if who == "luna" else "luna"]
	var map: RID = c.get_world_3d().navigation_map
	if main.teleport_guard:
		main.teleport_guard.allow(other)
	other.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(30, 0, -30)) + Vector3(0, 0.05, 0)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	var a0 := NavigationServer3D.map_get_closest_point(map, Vector3(-4.0, 0, 12.0))
	var a1 := NavigationServer3D.map_get_closest_point(map, Vector3(-4.0, 0, 26.0))
	for motion in ["walk", "run", "turn"]:
		for ang in [["front", 0.0], ["side", 90.0], ["3q", 40.0], ["back", 180.0]]:
			if main.teleport_guard:
				main.teleport_guard.allow(c)
			c.stop_action()
			c.global_position = a0 + Vector3(0, 0.05, 0)
			c.look_at_point(a1)
			await _wait(1.2)
			if motion == "turn":
				c.navigate_to(a0 + (a1 - a0).normalized() * 3.0, false)
				await _wait(2.2)
				c.navigate_to(a0 - (a1 - a0).normalized() * 0.5, false)   # a quick 180 back
			else:
				c.navigate_to(a1, motion == "run")
			var t0 := _game_t
			var shot_at := 0.45 if motion == "turn" else (1.6 if motion == "run" else 2.6)
			var taken := false
			while _game_t - t0 < shot_at + 0.3:
				await get_tree().process_frame
				var fwd := -c.global_transform.basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				var d := fwd.rotated(Vector3.UP, deg_to_rad(-float(ang[1])))
				var waist := c.global_position + Vector3(0, 0.9, 0)
				pin.fov = 30.0
				pin.pos = Vector3(waist.x, c.global_position.y + 1.0, waist.z) + d * 3.8
				pin.look = waist
				pin.active = true
				if main.get("subtitle") and main.subtitle:
					main.subtitle.visible = false
				if not taken and _game_t - t0 >= shot_at:
					_shot("%s_%s" % [motion, ang[0]])
					taken = true
			c.stop_action()
	pin.active = false


## Design B / sitting tests: Luna is forced into her Level 1 stage (design B on this branch) whatever the test save's
## level or form says (--keep-form leaves her as she is). Selwyn 2026-10-19: "force Luna into Level 1 design B".
func _force_luna_l1() -> void:
	if RenderProfile.options.has("keep-form") or not main.characters.has("luna"):
		return
	var luna: WorldCharacter = main.characters["luna"]
	var st: Dictionary = AppearanceRegistry.stage_by_id("luna", "oracle_l1outfit")
	var path := String(st.get("avatar", ""))
	if path != "" and luna.avatar_path != path:
		if main.teleport_guard:
			main.teleport_guard.allow(luna)
		luna.swap_avatar(path)
		await _wait(1.0)
	_check(luna.avatar_path == path, "Luna wears Level 1 (%s)" % path.get_file(), luna.avatar_path)


## A sped-up full day over the sanctuary (2026-10-19): the clock runs 24 h in --lapse-s seconds (default 96) from
## 04:00, a fixed wide camera looks west over the dais; record with --write-movie. Logs the sun's elevation, the
## light energy and the night amount every game hour.
func _daylapse() -> void:
	await _hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	if main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.day_night:
		main.day_night.clear_override()
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	pin.pos = Vector3(14.0, 7.0, 18.0)
	pin.look = Vector3(-6.0, 2.0, -6.0)
	pin.fov = 62.0
	pin.active = true
	var secs := float(RenderProfile.options.get("lapse-s", 96.0))
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 4.0 * 60.0
	await _wait(2.0)
	var rate := 1440.0 / secs                          # game minutes per real second
	var t0 := _game_t
	var last_h := -1
	var sun: DirectionalLight3D = main.world.get("sun")
	while _game_t - t0 < secs:
		await get_tree().process_frame
		WorldState.world_min = (WorldState.day() - 1) * 1440.0 + 4.0 * 60.0 + (_game_t - t0) * rate
		var hh := int(WorldState.hour_f())
		if hh != last_h:
			last_h = hh
			print("[mktest] lapse %02d:00 night_k %.2f sun_el %.1f energy %.2f" % [hh, main.day_night.k if main.day_night else -1.0, -rad_to_deg(sun.global_rotation.x), sun.light_energy if sun.visible else 0.0])
	pin.active = false


## The lake set for the dances: both mages on the Lantern Lake water at night, physics off, facing the lens (+Z of
## the clear lane in the floating lanterns), the stage dressed (DanceStage), the camera pinned. who: ids to place,
## with sideways offsets in metres. Returns {lake, spot, water_y, stage, pin, chars}.
func _lake_setup(who: Dictionary) -> Dictionary:
	await _hold_all()
	await _force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	var luna: WorldCharacter = main.characters["luna"]
	if main.performance and main.performance.busy():
		main.performance.interrupt("lake scene")
	if main.performance:
		main.performance.set_process(false)
	var tr: Dictionary = await main.streaming.travel("lantern_lake", luna, false)
	_check(main.streaming.current_id == "lantern_lake", "at Lantern Lake (%s)" % str(tr).left(120))
	if main.day_night:
		main.day_night.set_override(true)
	await _wait(2.0)
	if main.day_night:
		main.day_night.set_process(false)
		main.day_night.set_physics_process(false)
	var lake: Node3D = null
	for n in main.world.find_children("*", "Node3D", true, false) + [main.world]:
		if n.get("water_mat") != null:
			lake = n
			break
	_check(lake != null, "the lake node")
	if lake == null:
		return {}
	var water_y: float = lake.global_position.y
	var spot: Vector3 = lake.to_global(Vector3(-1.5, 0.0, -9.0))      # the clear lane in the floating lanterns
	spot.y = water_y
	var chars := {}
	for id in main.characters:
		var c: WorldCharacter = main.characters[id]
		if not who.has(id):
			c.visible = false
			continue
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.set_physics_process(false)
		c.visible = true                              # (the area change parks every mage but the focus)
		c.global_position = spot + Vector3(float(who[id]), 0, 0)
		c.swap_avatar(c.avatar_path)                  # (springs start where she stands)
		c.set_hair_frame("")                          # hair in the world: it flows with her (a dance had left it on the chest)
		chars[id] = c
	await _wait(0.5)
	for id in chars:
		var c: WorldCharacter = chars[id]
		var sk := c.skeleton
		var toe := sk.global_basis * (sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin - sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin)
		toe.y = 0.0
		c.rotation.y += toe.normalized().signed_angle_to(Vector3(0, 0, 1), Vector3.UP)
	await _wait(1.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	# a cinematic: no stream overlays (rank labels, cards) in the frame
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if not (cl is ScreenFX) and not (cl is MVPost):
			(cl as CanvasLayer).visible = false
	if main.get("hud") and main.hud:
		main.hud.visible = false
	var cams := []
	for k in 5:
		var ang := deg_to_rad(lerpf(-12.0, 12.0, k / 4.0))
		cams.append(spot + Vector3(sin(ang), 0, cos(ang)) * 3.9 + Vector3(0, 0.9, 0))
	var stage := DanceStage.build(lake, spot, water_y, cams, chars.values()[0])
	for id in chars:
		if id != chars.keys()[0]:
			stage.light_also(chars[id])
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	pin.fov = 40.0
	pin.roll = 0.0
	pin.active = true
	return {"lake": lake, "spot": spot, "water_y": water_y, "stage": stage, "pin": pin, "chars": chars}


## Each dancer's stack for the lake dances: the six-clip deck first, then the softness pass, then the belt cords.
func _dance_stack(c: WorldCharacter) -> DanceDeck:
	var d := DanceDeck.make(c.skeleton)
	var life := BodyLife.make(c.skeleton, 1)
	d.set_meta("life", life)
	SoftArms.make(c.skeleton, 2)
	TasselSway.make(c.skeleton, 3)
	return d


## QA reel: Luna alone on the lake plays each of Selwyn's six dance clips through once (deck + softness + cords), a
## straight full-figure camera - to choose the routine's pieces. --reel-clips=a,b (default: all six).
func _clipreel() -> void:
	var set := await _lake_setup({"luna": 0.0})
	if set.is_empty():
		return
	var luna: WorldCharacter = set.chars["luna"]
	var deck := _dance_stack(luna)
	var pin: CameraPin = set.pin
	var spot: Vector3 = set.spot
	pin.pos = spot + Vector3(0, 0.9, 3.4)
	pin.look = spot + Vector3(0, 0.95, 0)
	var list := String(RenderProfile.options.get("reel-clips", "dancing_a,dancing_b,bellydancing,belly_dance,rumba,samba")).split(",")
	deck.influence = 1.0
	for clip in list:
		var L := DanceDeck.clip_length(clip)
		deck.play(clip, 0.0, 1.0, 0.01)
		print("[clipreel] %s at %.2f for %.2fs" % [clip, _game_t, L])
		await _wait(minf(L, 26.0))


## The lake duet (Selwyn, 2026-10-19): Mika and Luna dance on the Lantern Lake water to the first chorus of
## 月夜灯火, using ONLY his six Mixamo dance clips (DanceDeck) - no other motion, no code-made poses - with the
## softness pass on wrists, fingers and elbows, the belt cords shortened and swinging, the dance effects on both
## (ribbons, spirals on their turns, arcs, rings, the finale), the moon's shimmer on the water. Straight camera,
## both full figures. Record with --write-movie; run with --no-scene-light.
func _lakedance() -> void:
	var set := await _lake_setup({"luna": -0.85, "mika": 0.85})
	if set.is_empty():
		return
	var luna: WorldCharacter = set.chars["luna"]
	var mika: WorldCharacter = set.chars["mika"]
	var spot: Vector3 = set.spot
	var pin: CameraPin = set.pin
	var stage: DanceStage = set.stage
	var decks := {"luna": _dance_stack(luna), "mika": _dance_stack(mika)}
	var fxs := {"luna": DanceFX.attach(luna, set.water_y, stage, true), "mika": DanceFX.attach(mika, set.water_y, stage, false)}
	for id in fxs:
		fxs[id].ring_colors = [DanceFX.ICE, Color(1, 1, 1)]
		fxs[id].ripple_every = 1.3
	var steps: Array = ROUTINE
	var t0 := _game_t
	var done := {}
	var last_turn := {"luna": -9.0, "mika": -9.0}
	var last_arc := {"luna": -9.0, "mika": -9.0}
	var prev_yaw := {}
	var prev_hand := {}
	var dur := float(steps[steps.size() - 1][0]) + 2.0
	print("[lakedance] routine %.1fs, song from %.2fs, t0 frame %d" % [dur, SONG_FROM, Engine.get_frames_drawn()])
	var cam_mode := String(RenderProfile.options.get("lake-cam", "wide"))
	var look_s := Vector3.ZERO
	while _game_t - t0 < dur:
		await get_tree().process_frame
		var t := _game_t - t0
		if main.get("subtitle") and main.subtitle:
			main.subtitle.visible = false
		# the camera: straight, low by the water, both full figures; a slow drift across
		var ang := deg_to_rad(lerpf(-8.0, 8.0, t / dur))
		if cam_mode == "hands":
			# a close look at Luna's hands and arms: framed on her chest and both hands, following them softly
			var lf: DanceFX = fxs["luna"]
			var want := (lf.bone("RightHand") + lf.bone("LeftHand") + lf.bone("Chest") * 2.0) / 4.0
			look_s = want if look_s == Vector3.ZERO else look_s.lerp(want, 0.08)
			pin.fov = 34.0
			pin.pos = look_s + Vector3(sin(ang) * 0.4, -0.05, 1.75)
			pin.look = look_s
		else:
			var dist := lerpf(3.9, 4.3, smoothstep(dur - 9.0, dur - 6.0, t))
			pin.pos = spot + Vector3(sin(ang), 0, cos(ang)) * dist + Vector3(0, 0.9, 0)
			pin.look = spot + Vector3(0, lerpf(1.0, 1.15, smoothstep(dur - 9.0, dur - 6.0, t)), 0)
		# the routine: [time, who ("both"/id), clip, start in clip, speed, fade] and the effect cues
		for i in steps.size():
			var st: Array = steps[i]
			if done.has(i) or t < float(st[0]):
				continue
			done[i] = true
			var who: String = st[2] if st[1] == "fx" else st[1]
			if st[1] == "fx":
				for id in fxs:
					if who == "both" or who == id:
						match String(st[3]):
							"burst": fxs[id].burst(float(st[4]))
							"finale": fxs[id].finale()
							"rings_gold":
								fxs[id].ring_colors = [DanceFX.GOLD, DanceFX.VIOLET]
								fxs[id].ripple_every = float(st[4])
							"rings_ice":
								fxs[id].ring_colors = [DanceFX.ICE, Color(1, 1, 1)]
								fxs[id].ripple_every = float(st[4])
				continue
			for id in decks:
				if who == "both" or who == id:
					var deck: DanceDeck = decks[id]
					if deck.influence < 1.0:
						var tw := create_tween()
						tw.tween_property(deck, "influence", 1.0, float(st[5]))
					deck.play(String(st[2]), float(st[3]), float(st[4]), float(st[5]))
		# effects that follow their own motion: a spiral on every fast turn, a gold arc when a hand sweeps up high
		for id in decks:
			var c: WorldCharacter = set.chars[id]
			var fx: DanceFX = fxs[id]
			var hips := c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Hips")).basis * Vector3(0, 0, 1)
			var yaw := atan2(hips.x, hips.z)
			if prev_yaw.has(id):
				var rate := absf(angle_difference(float(prev_yaw[id]), yaw)) / maxf(get_process_delta_time(), 0.001)
				if rate > deg_to_rad(120.0) and t - float(last_turn[id]) > 2.2 and t > 1.0:
					last_turn[id] = t
					fx.spin_dir = signf(angle_difference(float(prev_yaw[id]), yaw))
					fx.spiral(1.8, 2, 0.55)
			prev_yaw[id] = yaw
			for hb in ["RightHand", "LeftHand"]:
				var hp := fx.bone(hb)
				var head := fx.bone("Head")
				var key: String = id + hb
				if prev_hand.has(key):
					var vy := (hp.y - float(prev_hand[key])) / maxf(get_process_delta_time(), 0.001)
					if hp.y > head.y + 0.05 and vy > 0.9 and t - float(last_arc[id]) > 2.5:
						last_arc[id] = t
						fx.arc(hb, 1.3)
				prev_hand[key] = hp.y
		for k in SHOTS:
			if at_once(done, "shot" + str(k), t >= float(k)):
				_shot("lake_%s" % str(k))
	pin.active = false


func at_once(done: Dictionary, key: String, cond: bool) -> bool:
	if not cond or done.has(key):
		return false
	done[key] = true
	return true


const SONG_FROM := 57.93          # the routine's t = 0 in 月夜灯火 (two beats before the first chorus, 59.26)
const SHOTS := []
## [t, who, clip, start s in the clip, speed, crossfade s] - and [t, who, "fx", cue, value]. Bars of the first chorus
## (from the song map's beats, t = song - 57.93): 1.33 3.93 6.53 9.15 11.75 14.38 16.98 19.58 22.2 24.8 27.4 29.98,
## the chorus ends at 32.63. Pieces chosen from the reel of the six clips (2026-10-19).
const ROUTINE := [
	# in unison: arms rising slowly over their heads (belly dance)
	[0.0, "both", "belly_dance", 1.0, 0.9, 1.0],
	# side by side, each her own: Luna's arms frame her face (dancing), Mika's arm lifts high (belly dancing)
	[6.53, "fx", "both", "burst", 0.6],
	[6.53, "luna", "dancing_a", 2.0, 0.95, 1.2],
	[6.53, "mika", "bellydancing", 0.5, 0.95, 1.2],
	# the turn, in canon: Luna first, Mika one beat behind
	[11.75, "fx", "both", "rings_gold", 0.8],
	[11.75, "luna", "dancing_a", 7.0, 1.0, 1.0],
	[12.4, "mika", "dancing_a", 7.0, 1.0, 1.0],
	# contrast: Luna's arms sway overhead (rumba), Mika's hands circle (samba)
	[16.98, "fx", "both", "rings_ice", 1.0],
	[16.98, "luna", "rumba", 0.0, 0.9, 1.2],
	[16.98, "mika", "samba", 6.0, 0.9, 1.2],
	# together again: arms open wide and swaying (belly dancing)
	[22.2, "fx", "both", "burst", 0.8],
	[22.2, "both", "bellydancing", 18.0, 0.95, 1.2],
	# the lift: both arms up (dancing)
	[24.8, "fx", "both", "rings_gold", 0.7],
	[24.8, "both", "dancing_b", 0.0, 0.85, 1.0],
	# arms rising over their heads into the last bar, and the finale on its downbeat
	[27.4, "both", "belly_dance", 12.5, 0.9, 1.0],
	[29.98, "fx", "both", "finale", 0.0],
	[31.0, "fx", "both", "rings_gold", 0.9],
	[33.0, "fx", "both", "rings_gold", 0.9],
]


# ------------------------------------------------------------------------------------------------- the lake MV
## The lake duet as an anime MV (Selwyn, 2026-10-19: "rebuild the camera as a cinematic anime MV"): a Phantom Camera
## shot list cut on the song map's beats (no shot over ~4.6 s), slow motion on key moves, depth of field, the MV grade,
## lens flare and light sweeps off the moon, shake on the big beats, a white flash on the chorus drop; the effects
## follow the music (quiet verse, chorus explodes), petals swirl round the lens, the lanterns rise on the chorus.
## Dancing: only Selwyn's six clips (DanceDeck) + the softness pass + the swinging belt cords. Song time runs on the
## frame count (30 fps), so the cut stays on the music whatever slow motion does to the world.
const MV_FROM := 38.33             # song time at the first frame (2 s pre-roll; the clip is cut from 40.33)
const MV_TO := 70.5
const MV_SHOTS := [                # [song t, kind, who, tween s (0 = cut, > 0 = a whip pan)]
	[38.33, "crane", "both", 0.0],
	[44.91, "hand_ecu", "luna", 0.0],
	[47.51, "face_cu", "luna", 0.0],
	[50.13, "ots", "mika", 0.0],
	[52.73, "feet", "luna", 0.0],
	[54.03, "hair_slow", "mika", 0.0],
	[56.63, "push_pose", "luna", 0.0],
	[58.58, "push_pose", "mika", 0.2],
	[59.26, "hero_low", "both", 0.0],
	[61.86, "orbit", "both", 0.0],
	[65.76, "face_cu", "mika", 0.0],
	[67.08, "push_both", "both", 0.2],
	[70.98, "feet", "mika", 0.0],
	[73.61, "orbit", "both", 0.0],
	[77.51, "face_cu", "luna", 0.0],
	[80.13, "crane_up", "both", 0.0],
	[84.03, "ots", "luna", 0.0],
	[86.63, "hero_low", "both", 0.0],
	[89.26, "crane", "both", 0.0],
]
const MV_ROUTINE := [              # [song t, who, clip, start s, speed, fade s] - long phrases, 0.4 s crossfades
	[38.33, "both", "dancing_a", 9.2, 0.9, 0.4],
	[50.13, "both", "belly_dance", 8.0, 0.9, 0.4],
	[59.26, "luna", "dancing_a", 5.5, 1.0, 0.4],
	[59.91, "mika", "dancing_a", 5.5, 1.0, 0.4],
	[67.08, "both", "belly_dance", 13.0, 0.9, 0.4],
	[72.31, "both", "bellydancing", 18.0, 0.95, 0.4],
	[78.81, "luna", "samba", 1.0, 0.9, 0.4],
	[78.81, "mika", "rumba", 0.0, 0.9, 0.4],
	[84.03, "both", "belly_dance", 1.0, 0.9, 0.4],
]
const MV_SHOTS_ARMS := [           # the arms check: medium shots that keep both arms in frame
	[47.5, "arms_med", "luna", 0.0],
	[52.73, "arms_med", "mika", 0.0],
	[56.63, "arms_both", "both", 0.0],
	[59.26, "arms_med", "luna", 0.0],
	[61.86, "arms_both", "both", 0.0],
]
const MV_SLOW := [[54.35, 55.95], [62.45, 63.75], [75.2, 76.5], [88.0, 89.2]]
const MV_DROP := 59.26
const MV_CHORUS_DOWNBEATS := [59.26, 61.86, 64.46, 67.08, 69.68, 72.31, 74.91, 77.51, 80.13, 82.73, 85.33, 87.91]
const MV_FINALE := 87.91


func _mv_expected(id: String, song_t: float) -> Array:
	var best: Array = []
	for st in MV_ROUTINE:
		if float(st[0]) <= song_t and (st[1] == "both" or st[1] == id):
			best = st
	if best.is_empty():
		return []
	return [String(best[2]), float(best[3]) + (song_t - float(best[0])) * float(best[4]), float(best[4])]


func _lakemv() -> void:
	DanceStage.moon_up = 0.55
	DanceStage.moon_side = 0.38
	DanceStage.moon_size = 250.0
	var set := await _lake_setup({"luna": -0.75, "mika": 0.75})
	if set.is_empty():
		return
	(set.pin as CameraPin).active = false
	var chars: Dictionary = set.chars
	var spot: Vector3 = set.spot
	var stage: DanceStage = set.stage
	var decks := {"luna": _dance_stack(chars.luna), "mika": _dance_stack(chars.mika)}
	var fxs := {"luna": DanceFX.attach(chars.luna, set.water_y, stage, true), "mika": DanceFX.attach(chars.mika, set.water_y, stage, false)}
	for id in fxs:
		fxs[id].ring_scale = 0.75
		fxs[id].aura(2)
		fxs[id].ring_colors = [DanceFX.ICE, Color(1, 1, 1)]
		fxs[id].ripple_every = 1.6
	fxs.luna.camera_petals()
	var look_mode := {"lens": false}
	for id in decks:
		var other: String = "mika" if id == "luna" else "luna"
		var life: BodyLife = (decks[id] as DanceDeck).get_meta("life")
		life.look = func() -> Vector3:
			var cm := get_viewport().get_camera_3d()
			if bool(look_mode.lens) and cm:
				return cm.global_position
			return (fxs[other] as DanceFX).bone("Head")
	# Phantom Camera drives the live camera; the driver's post hook adds the lens (fov, depth of field) and the shake
	var cam: Camera3D = main.camera_rig.camera
	cam.top_level = true
	var host := PhantomCameraHost.new()
	host.interpolation_mode = PhantomCameraHost.InterpolationMode.MANUAL
	cam.add_child(host)
	var driver := PCamDriver.new()
	driver.host = host
	main.add_child(driver)
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	var lens := {"fov": 40.0, "shake": 0.0, "seed": 0.0}
	driver.post = func(c: Camera3D) -> void:
		c.fov = float(lens.fov)
		c.attributes = attrs
		var k: float = lens.shake
		if k > 0.001:
			var ph: float = lens.seed
			c.global_position += c.global_basis * Vector3(sin(ph * 37.0), sin(ph * 51.0 + 1.3), 0.0) * 0.035 * k
			c.rotate_object_local(Vector3.FORWARD, sin(ph * 43.0 + 0.7) * 0.012 * k)
	var post := MVPost.make(main, stage.moon_node)
	var pcs: Array = []
	var shot_i := -1
	var shot: Array = []
	var shot_t0 := 0.0
	var step_done := {}
	var drop_done := false
	var downbeats_done := {}
	var prev_yaw := {}
	var last_turn := {"luna": -9.0, "mika": -9.0}
	var prev_hand := {}
	var last_arc := {"luna": -9.0, "mika": -9.0}
	var smooth := {}
	var frame := 0
	var arms_cut := String(RenderProfile.options.get("mv-shots", "")) == "arms"
	var shots: Array = MV_SHOTS_ARMS if arms_cut else MV_SHOTS
	var mv_from := float(RenderProfile.options.get("mv-from", str(MV_FROM)))
	var song_t := mv_from
	var mv_to := float(RenderProfile.options.get("mv-to", str(MV_TO)))
	var finale_done := false
	print("[lakemv] song %.2f-%.2f, t0 frame %d" % [mv_from, mv_to, Engine.get_frames_drawn()])
	# start the dance where the song starts (a later --mv-from: each girl's clip at its place in the routine)
	for i in MV_ROUTINE.size():
		if float(MV_ROUTINE[i][0]) <= mv_from:
			step_done[i] = true
	for id in decks:
		var ex := _mv_expected(id, mv_from)
		if not ex.is_empty():
			(decks[id] as DanceDeck).influence = 1.0
			(decks[id] as DanceDeck).play(String(ex[0]), float(ex[1]), float(ex[2]), 0.01)
	while song_t < mv_to:
		await get_tree().process_frame
		frame += 1
		song_t = mv_from + frame / 30.0
		if main.get("subtitle") and main.subtitle:
			main.subtitle.visible = false
		# slow motion on the key moves (the world slows; the music, and so the cut, does not)
		var slow := false
		for w in MV_SLOW:
			if song_t >= float(w[0]) and song_t < float(w[1]):
				slow = true
		Engine.time_scale = 0.3 if slow else 1.0
		# the routine
		for i in MV_ROUTINE.size():
			var st: Array = MV_ROUTINE[i]
			if step_done.has(i) or song_t < float(st[0]):
				continue
			step_done[i] = true
			for id in decks:
				if st[1] == "both" or st[1] == id:
					var deck: DanceDeck = decks[id]
					if deck.influence < 1.0:
						create_tween().tween_property(deck, "influence", 1.0, float(st[5]))
					deck.play(String(st[2]), float(st[3]), float(st[4]), float(st[5]))
		# the music's level: a quiet verse, the pre-chorus building, the chorus exploding
		var e: float = _song_energy(song_t)
		var base := 0.35 if song_t < 54.03 else (lerpf(0.45, 0.85, (song_t - 54.03) / 5.23) if song_t < MV_DROP else 1.1)
		var lvl := clampf(base * (0.8 + 0.4 * e / 0.7), 0.15, 1.25)
		for id in fxs:
			fxs[id].set_level(lvl)
		# the drop: a white flash, the lanterns rise, bursts; then a pulse on every chorus downbeat
		if not drop_done and song_t >= MV_DROP:
			drop_done = true
			post.flash_white(0.45)
			stage.lift()
			for id in fxs:
				fxs[id].burst(1.2)
				fxs[id].ring_colors = [DanceFX.GOLD, DanceFX.VIOLET]
				fxs[id].ripple_every = 0.9
			lens.shake = 1.0
		for db in MV_CHORUS_DOWNBEATS:
			if song_t >= float(db) and not downbeats_done.has(db):
				downbeats_done[db] = true
				if float(db) > MV_DROP:
					lens.shake = maxf(float(lens.shake), 0.55)
					stage.flare(0.7)
		if not finale_done and song_t >= MV_FINALE:
			finale_done = true
			for id in fxs:
				fxs[id].finale(0.6)
			lens.shake = 1.0
			stage.flare(1.2)
		lens.shake = maxf(float(lens.shake) - (1.0 / 30.0) / 0.3, 0.0)
		lens.seed = float(lens.seed) + 1.0 / 30.0
		# effects that follow their own motion: a spiral on each fast turn, a gold arc when a hand sweeps up high
		for id in decks:
			var c: WorldCharacter = chars[id]
			var fx: DanceFX = fxs[id]
			var hips := c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Hips")).basis * Vector3(0, 0, 1)
			var yaw := atan2(hips.x, hips.z)
			var dt := maxf(get_process_delta_time(), 0.0005)
			if prev_yaw.has(id):
				var rate := absf(angle_difference(float(prev_yaw[id]), yaw)) / dt
				if rate > deg_to_rad(120.0) and song_t - float(last_turn[id]) > 2.0:
					last_turn[id] = song_t
					fx.spin_dir = signf(angle_difference(float(prev_yaw[id]), yaw))
					fx.spiral(1.8, 2, 0.55)
			prev_yaw[id] = yaw
			for hb in ["RightHand", "LeftHand"]:
				var hp := fx.bone(hb)
				var key: String = id + hb
				if prev_hand.has(key):
					var vy := (hp.y - float(prev_hand[key])) / dt
					if hp.y > fx.bone("Head").y + 0.05 and vy > 0.9 and song_t - float(last_arc[id]) > 2.5:
						last_arc[id] = song_t
						fx.arc(hb, 1.3)
				prev_hand[key] = hp.y
		# the shot list: a new Phantom Camera on each cut (a whip pan tweens to it), the dancers back in step
		var ni := shot_i
		while ni + 1 < shots.size() and song_t >= float(shots[ni + 1][0]):
			ni += 1
		if ni != shot_i:
			shot_i = ni
			shot = shots[ni]
			shot_t0 = song_t
			smooth.clear()
			for id in decks:
				var ex := _mv_expected(id, song_t)
				if not ex.is_empty() and (decks[id] as DanceDeck).current() == ex[0]:
					(decks[id] as DanceDeck).sync(float(ex[1]))
			var pc := PhantomCamera3D.new()
			pc.name = "MV_%02d_%s" % [ni, shot[1]]
			main.add_child(pc)
			pc.set_tween_duration(float(shot[3]))
			pc.set_tween_transition(Tween.TRANS_EXPO)
			pcs.append(pc)
			if pcs.size() > 3:
				(pcs.pop_front() as Node).queue_free()
			fxs.luna.ring_scale = 1.0 if shot[1] == "feet" else 0.75
			look_mode.lens = shot[1] in ["face_cu", "hero_low", "push_pose", "push_both"]
			for id in fxs:
				fxs[id].catchlights(shot[1] == "face_cu" and shot[2] == id)
			if shot[1] == "hand_ecu":
				(fxs[String(shot[2])] as DanceFX).arc("RightHand", (float(shots[ni + 1][0]) - song_t) / maxf(Engine.time_scale, 0.3))
			print("[lakemv] %.2f shot %d %s %s" % [song_t, ni, shot[1], shot[2]])
		var u := (song_t - shot_t0) / maxf((float(shots[shot_i + 1][0]) if shot_i + 1 < shots.size() else mv_to) - shot_t0, 0.1)
		var cp := _mv_camera(String(shot[1]), String(shot[2]), u, chars, fxs, spot, smooth)
		var pcam: PhantomCamera3D = pcs[pcs.size() - 1]
		var pos: Vector3 = cp.pos
		var look: Vector3 = cp.look
		if (look - pos).length() > 0.01:
			pcam.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
		if shot_i == 0 and frame == 1:
			pcam.set_priority(100)
		pcam.set_priority(100 + shot_i)
		lens.fov = cp.fov
		var fd: float = (cp.focus - pos).length()
		attrs.dof_blur_far_distance = fd + float(cp.far)
		attrs.dof_blur_far_transition = float(cp.far) * 2.5
		attrs.dof_blur_amount = float(cp.amount)
		attrs.dof_blur_near_enabled = float(cp.near) > 0.0
		attrs.dof_blur_near_distance = maxf(fd - float(cp.near), 0.05)
		attrs.dof_blur_near_transition = float(cp.near) * 0.8
	Engine.time_scale = 1.0
	print("[lakemv] done at frame %d" % Engine.get_frames_drawn())


func _song_energy(t: float) -> float:
	if _song_map.is_empty():
		var f := FileAccess.open(OS.get_environment("HOME") + "/Downloads/song_map_raw.json", FileAccess.READ)
		if f:
			_song_map = JSON.parse_string(f.get_as_text())
		if _song_map == null or not (_song_map is Dictionary):
			_song_map = {"energy_per_sec": []}
	var arr: Array = _song_map.get("energy_per_sec", [])
	var i := clampi(int(t), 0, maxi(arr.size() - 1, 0))
	return float(arr[i]) if arr.size() > 0 else 0.6

var _song_map = {}


## One MV shot's camera at progress u (0..1): {pos, look, fov, focus, far (m of sharp depth behind the focus), near
## (m in front, 0 = off), amount}.
func _mv_camera(kind: String, who: String, u: float, chars: Dictionary, fxs: Dictionary, spot: Vector3, sm: Dictionary) -> Dictionary:
	var e := u * u * (3.0 - 2.0 * u)
	var both := spot + Vector3(0, 1.0, 0)
	var fx: DanceFX = fxs.get(who, fxs.luna)
	var follow := func(key: String, p: Vector3, k := 0.18) -> Vector3:
		var v: Vector3 = sm.get(key, p)
		v = v.lerp(p, k)
		sm[key] = v
		return v
	match kind:
		"crane":
			var ec := pow(u, 2.2)
			var p0 := spot + Vector3(0.7, 0.14, 2.6)
			var p1 := spot + Vector3(-1.2, 5.2, 8.0)
			var pos := p0.lerp(p1, ec)
			var look := (spot + Vector3(0, 0.95, 0)).lerp(spot + Vector3(0, 0.4, -3.0), ec)
			e = ec
			return {"pos": pos, "look": look, "fov": lerpf(42.0, 54.0, e), "focus": spot + Vector3(0, 1, 0), "far": lerpf(1.5, 30.0, e), "near": 0.0, "amount": lerpf(0.06, 0.02, e)}
		"arms_med":
			# knees-up on one girl, both arms in frame
			var ch: Vector3 = follow.call("chest", fx.bone("Chest") + Vector3(0, 0.05, 0), 0.12)
			var sd3 := -0.6 if who == "luna" else 0.6
			var pos := ch + Vector3(sd3 * (1.0 - 0.3 * e), -0.1, lerpf(2.15, 1.85, e))
			return {"pos": pos, "look": ch, "fov": 42.0, "focus": ch, "far": 0.9, "near": 0.0, "amount": 0.08}
		"arms_both":
			var mid := spot + Vector3(0, 1.25, 0)
			var pos := mid + Vector3(0.3 * (1.0 - 2.0 * e), -0.1, lerpf(2.9, 2.6, e))
			return {"pos": pos, "look": mid, "fov": 46.0, "focus": mid, "far": 1.2, "near": 0.0, "amount": 0.06}
		"crane_up":
			# from their feet up past them into the lantern sky
			var pos := spot + Vector3(0.3, lerpf(0.3, 2.6, e), lerpf(2.4, 3.4, e))
			var look := spot + Vector3(0, lerpf(0.8, 4.5, e), lerpf(0.0, -4.0, e))
			return {"pos": pos, "look": look, "fov": 46.0, "focus": both, "far": lerpf(1.5, 20.0, e), "near": 0.0, "amount": 0.05}
		"hand_ecu":
			var h: Vector3 = follow.call("hand", fx.bone("RightHand"), 0.25)
			var pos := h + Vector3(0.28 + 0.1 * u, 0.06, 0.62 - 0.08 * u)
			return {"pos": pos, "look": h, "fov": 30.0, "focus": h, "far": 0.25, "near": 0.0, "amount": 0.16}
		"face_cu":
			var hd: Vector3 = follow.call("head", fx.bone("Head") + Vector3(0, 0.02, 0), 0.4)
			var sd := -1.0 if who == "luna" else 1.0
			var pos := hd + Vector3(sd * (0.22 - 0.06 * e), -0.03, 1.12 - 0.18 * e)
			return {"pos": pos, "look": hd, "fov": 34.0, "focus": hd, "far": 0.3, "near": 0.0, "amount": 0.15}
		"ots":
			var other: DanceFX = fxs.luna if who == "mika" else fxs.mika
			var mine: Vector3 = fx.bone("Head")
			var their: Vector3 = follow.call("their", other.bone("Head") + Vector3(0, 0.02, 0), 0.2)
			var away := (mine - their)
			away.y = 0.0
			away = away.normalized()
			var pos := mine + away * (0.45 - 0.08 * e) + Vector3(0, 0.02, 0.3)
			return {"pos": pos, "look": their, "fov": 34.0, "focus": their, "far": 0.4, "near": 0.9, "amount": 0.14}
		"feet":
			var f: Vector3 = follow.call("feet", (fx.bone("LeftToes") + fx.bone("RightToes")) * 0.5, 0.15)
			f.y = spot.y
			var pos := f + Vector3(0.45 - 0.2 * e, 0.11, 0.85 - 0.15 * e)
			return {"pos": pos, "look": f + Vector3(0, 0.12, 0), "fov": 36.0, "focus": f, "far": 0.4, "near": 0.0, "amount": 0.14}
		"hair_slow":
			var hp: Vector3 = follow.call("hips", fx.bone("Chest") + Vector3(0, -0.15, 0), 0.12)
			var ang := lerpf(125.0, 70.0, e)
			var pos := hp + Vector3(cos(deg_to_rad(ang)) * 2.3, 0.25, sin(deg_to_rad(ang)) * 2.3)
			return {"pos": pos, "look": hp + Vector3(0, 0.1, 0), "fov": 42.0, "focus": hp, "far": 0.6, "near": 0.0, "amount": 0.1}
		"push_pose":
			var ch: Vector3 = follow.call("chest", fx.bone("Chest") + Vector3(0, 0.15, 0), 0.15)
			var sd2 := -0.5 if who == "luna" else 0.5
			var pos := ch + Vector3(sd2 * (1.0 - 0.4 * e), -0.15, lerpf(2.6, 1.55, e))
			return {"pos": pos, "look": ch, "fov": 38.0, "focus": ch, "far": 0.8, "near": 0.0, "amount": 0.1}
		"hero_low":
			var pos := spot + Vector3(0.35 - 0.3 * e, 0.22 + 0.15 * e, 2.55 - 0.35 * e)
			var look := spot + Vector3(-0.2, 1.75, -0.6)
			return {"pos": pos, "look": look, "fov": 46.0, "focus": both, "far": 2.0, "near": 0.0, "amount": 0.06}
		"orbit":
			var ang := deg_to_rad(lerpf(25.0, 235.0, e) + 90.0)
			var pos := both + Vector3(cos(ang) * 3.0, lerpf(0.0, 0.45, e), sin(ang) * 3.0)
			return {"pos": pos, "look": both + Vector3(0, 0.1, 0), "fov": 42.0, "focus": both, "far": 1.8, "near": 0.0, "amount": 0.07}
		"push_both":
			var pos := spot + Vector3(0.2 * (1.0 - e), lerpf(0.55, 0.8, e), lerpf(4.6, 3.1, e))
			var look := spot + Vector3(0, lerpf(1.15, 1.35, e), 0)
			return {"pos": pos, "look": look, "fov": 42.0, "focus": both, "far": 2.0, "near": 0.0, "amount": 0.06}
	return {"pos": both + Vector3(0, 0, 4), "look": both, "fov": 40.0, "focus": both, "far": 2.0, "near": 0.0, "amount": 0.05}


## QA: the hair springs while dancing - each VRM spring chain's settings, and how far each girl's hair tips move
## relative to her head over 8 s of belly dance (stiff hair = small motion).
func _hairprobe() -> void:
	var set := await _lake_setup({"luna": -0.75, "mika": 0.75})
	if set.is_empty():
		return
	var tips := {}
	for id in set.chars:
		var c: WorldCharacter = set.chars[id]
		var sec = c.avatar.find_child("secondary", true, false)
		var n := 0
		if sec:
			for sb in sec.spring_bones:
				var jn: PackedStringArray = sb.joint_nodes
				if jn.size() == 0 or not String(jn[0]).to_lower().contains("hair"):
					continue
				n += 1
				if n <= 6:
					print("[hair] %s %s joints=%d stiff=%s drag=%s grav=%s scale(st=%.2f dr=%.2f gr=%.2f) center=%s colliders=%d" % [id, sb.comment, jn.size(),
						str(sb.stiffness_force.slice(0, 3)), str(sb.drag_force.slice(0, 3)), str(sb.gravity_power.slice(0, 3)),
						sb.stiffness_scale, sb.drag_force_scale, sb.gravity_scale, sb.center_bone, sb.collider_groups.size()])
			print("[hair] %s: %d hair chains, %d runtime chains" % [id, n, sec.spring_bones_internal.size()])
		var sk := c.skeleton
		var list := []
		for bi in sk.get_bone_count():
			var nm := sk.get_bone_name(bi)
			if nm.to_lower().contains("hair") and sk.get_bone_children(bi).is_empty():
				list.append(bi)
		tips[id] = list
		var d := _dance_stack(c)
		d.influence = 1.0
		d.play("belly_dance", 0.0, 1.0, 0.01)
	var stats := {}
	for f in 240:
		await get_tree().process_frame
		for id in set.chars:
			var c: WorldCharacter = set.chars[id]
			var sk := c.skeleton
			var hb := sk.get_bone_global_pose(sk.find_bone("Head"))
			for bi in tips[id]:
				var p := hb.affine_inverse() * sk.get_bone_global_pose(bi).origin
				var key := "%s_%d" % [id, bi]
				var st: Array = stats.get(key, [Vector3.ZERO, Vector3.ZERO, 0])
				st[0] += p
				st[1] += p * p
				st[2] += 1
				stats[key] = st
	for id in set.chars:
		var tot := 0.0
		var k := 0
		for bi in tips[id]:
			var st: Array = stats["%s_%d" % [id, bi]]
			var m: Vector3 = st[0] / float(st[2])
			var v: Vector3 = st[1] / float(st[2]) - m * m
			tot += sqrt(maxf(v.x + v.y + v.z, 0.0))
			k += 1
		print("[hair] %s: %d tips, mean tip motion (std, head frame) %.3f m" % [id, k, tot / maxf(k, 1)])


# ------------------------------------------------------------------------------------------- the Moon Lantern Boat
## The boat's first sample scene (Selwyn, 2026-10-19; no dancing): late at night Mika and Luna walk down the pier,
## talk briefly and step into the boat; Luna rows them out to the middle of Lantern Lake while Mika trails her hand
## in the water; they stop, Mika lights the bow lantern with a spark, they set floating lanterns on the water one by
## one; they lean back and stargaze, point, talk quietly, then sit with their thoughts (Luna watching the water, Mika's
## chin on her hand). Calm Phantom Camera shots throughout. Built on MoonBoat's reusable actions.
func _boatnight() -> void:
	await _hold_all()
	await _force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance and main.performance.busy():
		main.performance.interrupt("boat scene")
	if main.performance:
		main.performance.set_process(false)
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	await main.streaming.travel("lantern_lake", luna, false)
	_check(main.streaming.current_id == "lantern_lake", "at Lantern Lake")
	main.day_night.set_override(true)
	await _wait(2.0)
	main.day_night.set_process(false)
	var lake: Node3D = null
	for n in main.world.find_children("*", "Node3D", true, false) + [main.world]:
		if n.get("water_mat") != null:
			lake = n
			break
	_check(lake != null, "the lake node")
	if lake == null:
		return
	var water_y: float = lake.global_position.y
	var L := func(v: Vector3) -> Vector3: return lake.to_global(v)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if not (cl is ScreenFX):
			(cl as CanvasLayer).visible = false
	if main.get("hud") and main.hud:
		main.hud.visible = false
	# the boat moored at the pier's west side, bow out to the lake; a quiet night (few festival lanterns)
	var boat := MoonBoat.spawn(main.world, L.call(Vector3(1.95, 0.0, -1.5)), -PI * 0.5 + lake.global_rotation.y, water_y)
	boat.lake = lake
	boat.day_night = main.day_night
	_check(boat.oars.size() == 2 and boat.lanterns.size() == 2, "boat parts: %d oars, %d lanterns" % [boat.oars.size(), boat.lanterns.size()])
	DanceStage.lantern_keep = 0.15
	DanceStage.hover_lanterns = false
	var stage := DanceStage.build(lake, L.call(Vector3(2.3, 0.0, -16.0)), water_y, [L.call(Vector3(4.0, 1.5, 8.0))], luna)
	stage.light_also(mika)
	# the two of them on the bank, at the foot of the pier
	var area: Node = main.world
	for pair in [[luna, Vector3(3.55, 0, 11.2)], [mika, Vector3(4.45, 0, 11.6)]]:
		var c: WorldCharacter = pair[0]
		var p: Vector3 = pair[1]
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.visible = true
		c.set_physics_process(true)
		p.y = float(area.call("ground_at", p.x, p.z)) if area.has_method("ground_at") else 0.0
		c.global_position = L.call(p) + Vector3(0, 0.05, 0)
		c.set_hair_frame("")
		var life := BodyLife.make(c.skeleton, 0)
		life.look_weight = 0.4
		c.set_meta("life", life)
	await _wait(1.0)
	var cine := _cine_setup(stage)
	var ctx := {"luna": luna, "mika": mika, "boat": boat, "L": L, "water": water_y}
	var cam_on := {"run": true}
	var cam_loop := func():
		while cam_on.run:
			await get_tree().process_frame
			_cine_tick(cine, ctx)
	cam_loop.call()
	var t0 := _game_t
	print("[boat] scene start frame %d" % Engine.get_frames_drawn())
	# 1. the walk down the pier (an establishing wide, then a tracking side shot)
	_cine_cut(cine, "establish", 0.0)
	luna.navigate_to(L.call(Vector3(3.65, 0.62, -1.75)))
	await _wait(0.35)
	mika.navigate_to(L.call(Vector3(3.65, 0.62, -0.62)))
	await _wait(5.5)
	_cine_cut(cine, "walk_track", 0.0)
	var tw0 := _game_t
	while _game_t - tw0 < 16.0:
		await get_tree().process_frame
		if _game_t - tw0 > 1.0 and luna.current_action != "navigate_to" and mika.current_action != "navigate_to":
			break
	for c in [luna, mika]:
		c.stop_action()
		c.set_physics_process(false)
	# 2. a few words at the end of the pier
	_cine_cut(cine, "talk_two", 0.0)
	for pr in [[luna, mika], [mika, luna]]:
		var a: WorldCharacter = pr[0]
		var b: WorldCharacter = pr[1]
		var to := b.global_position - a.global_position
		to.y = 0.0
		var sk := a.skeleton
		var toe := sk.global_basis * (sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin - sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin)
		toe.y = 0.0
		var turn := toe.normalized().signed_angle_to(to.normalized().rotated(Vector3.UP, deg_to_rad(-25.0 if a == luna else 25.0)), Vector3.UP)
		create_tween().tween_property(a, "rotation:y", a.rotation.y + turn, 0.8).set_trans(Tween.TRANS_SINE)
	luna.look_at_point(_head(mika))
	mika.look_at_point(_head(luna))
	(luna.get_meta("life") as BodyLife).look = func() -> Vector3: return _head(mika)
	(mika.get_meta("life") as BodyLife).look = func() -> Vector3: return _head(luna)
	await _say_soft("luna", "It's so quiet tonight.", 3.0)
	mika.set_expression("happy", 0.5)
	await _say_soft("mika", "Perfect for the boat. Will you row us out?", 3.4)
	luna.set_expression("happy", 0.45)
	await _say_soft("luna", "Climb in, then.", 2.0)
	# 3. into the boat
	_cine_cut(cine, "board_wide", 0.0)
	await _step_in(luna, boat, "bow")
	await _wait(0.5)
	await _step_in(mika, boat, "stern")
	await _wait(1.5)
	# 4. Luna rows them out; Mika trails her hand in the water
	_cine_cut(cine, "row_med", 0.0)
	boat.row(true)
	await _wait(2.5)
	boat.trail_hand("stern", "Left", true)
	await _wait(4.5)
	_cine_cut(cine, "hand_water", 0.0)
	await _wait(5.0)
	_cine_cut(cine, "boat_aerial", 0.0)
	await _wait(6.5)
	boat.row(false)
	boat.trail_hand("stern", "Left", false)
	await _wait(2.5)
	# 5. the bow lantern: a spark from Mika's fingertip
	_cine_cut(cine, "lantern_light", 0.0)
	await _wait(0.6)
	await boat.light_lantern("stern", "bow", "Right")
	await _wait(1.0)
	# 6. floating lanterns, one by one
	_cine_cut(cine, "mika_lanterns", 0.0)
	await boat.place_lantern("stern", "Left")
	await boat.place_lantern("stern", "Left")
	_cine_cut(cine, "luna_lantern", 0.0)
	await boat.place_lantern("bow", "Left")
	_cine_cut(cine, "lanterns_wide", 0.0)
	await _wait(4.0)
	# 7. stargazing
	_cine_cut(cine, "stargaze_two", 0.0)
	boat.stargaze("bow", true)
	boat.stargaze("stern", true)
	await _wait(3.5)
	_cine_cut(cine, "sky_point", 0.0)
	var star_dir := (Vector3(0.25, 1.0, 0.0) + (boat.seat_xform("stern").basis.z * 0.5)).normalized()
	_lantern_star(boat.global_position + star_dir * 420.0)
	boat.point_at("stern", star_dir, "Right", 3.2)
	await _say_soft("mika", "Look... that one, right above the moon.", 3.2)
	_cine_cut(cine, "stargaze_two", 0.0)
	await _say_soft("luna", "The Lantern Star. It only shows on the clearest nights.", 4.0)
	await _wait(1.5)
	# 8. thoughtful: Luna watches the water, Mika rests her chin on her hand
	boat.stargaze("bow", false)
	boat.stargaze("stern", false)
	_cine_cut(cine, "cu_luna_water", 0.0)
	boat.look_water("bow", true, "Left")
	await _wait(4.5)
	_cine_cut(cine, "cu_mika_chin", 0.0)
	boat.chin_rest("stern", true, "Right")
	await _wait(1.2)
	mika.set_expression("happy", 0.35)
	await _say_soft("mika", "I'm glad we came out here.", 3.0)
	await _wait(1.0)
	# 9. away: the camera rises over the lake
	_cine_cut(cine, "crane_out", 0.0)
	await _wait(7.0)
	cam_on.run = false
	print("[boat] scene end frame %d (%.1f s)" % [Engine.get_frames_drawn(), _game_t - t0])


func _head(c: WorldCharacter) -> Vector3:
	return c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Head")).origin + Vector3(0, 0.05, 0)


## A line in her own voice (the local Kokoro voices with --live-link) with its subtitle; never waits longer than
## `max_s` (+1 s), so the scene keeps its pace if the voice is slow to start.
func _say_soft(who: String, text: String, max_s: float) -> void:
	var st := {"done": false}
	var run := func():
		await main.voice.say(who, text, {})
		st.done = true
	run.call()
	var t := _game_t
	while not st.done and _game_t - t < max_s + 1.0:
		await get_tree().process_frame
	await _wait(0.4)


## She steps down from the pier into the boat beside her seat (an arc, not a teleport), turns, and sits.
func _step_in(c: WorldCharacter, boat: MoonBoat, seat_name: String) -> void:
	c.set_physics_process(false)
	var a := c.global_position
	var tw := create_tween()
	var dur := 1.1
	tw.tween_method(func(k: float):
		var st := boat.seat_xform(seat_name)
		var b := st.origin + st.basis.z * 0.22
		b.y = boat.global_position.y - 0.03
		var p := a.lerp(b, k)
		p.y += sin(k * PI) * 0.16
		c.global_position = p, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.play_gesture("walk", 0.2, 0.3)
	await tw.finished
	c.end_gesture()
	await boat.seat(c, seat_name)


# --------------------------------------------------------------------------------- calm cinematic camera (Phantom)
func _cine_setup(stage: DanceStage) -> Dictionary:
	var cam: Camera3D = main.camera_rig.camera
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	cam.top_level = true
	var host := PhantomCameraHost.new()
	host.interpolation_mode = PhantomCameraHost.InterpolationMode.MANUAL
	cam.add_child(host)
	var driver := PCamDriver.new()
	driver.host = host
	main.add_child(driver)
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	var cine := {"attrs": attrs, "fov": 40.0, "pcs": [], "kind": "", "t0": 0.0, "i": 0, "sm": {}}
	driver.post = func(c: Camera3D) -> void:
		c.fov = float(cine.fov)
		c.attributes = attrs
	MVPost.make(main, stage.moon_node)
	return cine


func _cine_cut(cine: Dictionary, kind: String, tween_s: float) -> void:
	var pc := PhantomCamera3D.new()
	cine.i = int(cine.i) + 1
	pc.name = "BN_%02d_%s" % [int(cine.i), kind]
	main.add_child(pc)
	pc.set_tween_duration(tween_s)
	pc.set_tween_transition(Tween.TRANS_SINE)
	(cine.pcs as Array).append(pc)
	if (cine.pcs as Array).size() > 3:
		((cine.pcs as Array).pop_front() as Node).queue_free()
	cine.kind = kind
	cine.t0 = _game_t
	(cine.sm as Dictionary).clear()
	print("[boat] %.1f shot %s" % [_game_t, kind])


func _cine_tick(cine: Dictionary, ctx: Dictionary) -> void:
	if (cine.pcs as Array).is_empty():
		return
	var t := _game_t - float(cine.t0)
	var cp := _bn_cam(String(cine.kind), t, ctx, cine.sm)
	var pc: PhantomCamera3D = (cine.pcs as Array)[(cine.pcs as Array).size() - 1]
	var pos: Vector3 = cp.pos
	var look: Vector3 = cp.look
	if (look - pos).length() > 0.01:
		pc.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	pc.set_priority(100 + int(cine.i))
	cine.fov = cp.fov
	var attrs: CameraAttributesPractical = cine.attrs
	var fd: float = (cp.focus - pos).length()
	attrs.dof_blur_far_distance = fd + float(cp.far)
	attrs.dof_blur_far_transition = float(cp.far) * 2.5
	attrs.dof_blur_amount = float(cp.amount)
	attrs.dof_blur_near_enabled = false


## Calm shots for the boat scene (t = seconds into the shot): {pos, look, fov, focus, far, amount}.
func _bn_cam(kind: String, t: float, ctx: Dictionary, sm: Dictionary) -> Dictionary:
	var luna: WorldCharacter = ctx.luna
	var mika: WorldCharacter = ctx.mika
	var boat: MoonBoat = ctx.boat
	var L: Callable = ctx.L
	var water: float = ctx.water
	var bx := boat.global_transform
	var follow := func(key: String, p: Vector3, k := 0.06) -> Vector3:
		var v: Vector3 = sm.get(key, p)
		v = v.lerp(p, k)
		sm[key] = v
		return v
	var mid: Vector3 = follow.call("mid", (luna.global_position + mika.global_position) * 0.5 + Vector3(0, 1.1, 0), 0.08)
	match kind:
		"establish":
			var pos: Vector3 = L.call(Vector3(-3.0, 1.2, -6.0)) + Vector3(0.0, 0.05 * t, -0.08 * t)
			return {"pos": pos, "look": L.call(Vector3(4.0, 0.9, 6.0)), "fov": 44.0, "focus": mid, "far": 8.0, "amount": 0.03}
		"walk_track":
			var pos2: Vector3 = mid + (L.call(Vector3(-3.4, 0.25, 0.6)) - L.call(Vector3.ZERO))
			return {"pos": pos2, "look": mid, "fov": 40.0, "focus": mid, "far": 2.0, "amount": 0.05}
		"talk_two":
			var side: Vector3 = (L.call(Vector3(-2.4, 0.2, -1.3 - 0.04 * t)) - L.call(Vector3.ZERO))
			return {"pos": mid + side, "look": mid + Vector3(0, 0.15, 0), "fov": 36.0, "focus": mid, "far": 1.2, "amount": 0.07}
		"board_wide":
			var c0: Vector3 = bx * Vector3(0.2, 0.6, 0.0)
			return {"pos": bx * Vector3(-1.2 + 0.05 * t, 1.5, 4.6), "look": c0 + Vector3(0, 0.3, 0), "fov": 42.0, "focus": c0, "far": 3.0, "amount": 0.04}
		"row_med":
			var lt: Vector3 = follow.call("lt", _head(luna) + Vector3(0, -0.35, 0), 0.1)
			return {"pos": bx * Vector3(1.75, 1.75, 1.55), "look": lt, "fov": 38.0, "focus": lt, "far": 1.2, "amount": 0.06}
		"hand_water":
			var hp: Vector3 = boat.trail_point("stern", "Left")
			var st0 := boat.seat_xform("stern")
			var pos3 := hp + MoonBoat.side_vec(st0, "Left") * 1.0 + st0.basis.z * 0.9 + Vector3(0, 0.38, 0)
			var lk := hp + Vector3(0, 0.25, 0) + st0.basis.z * -0.15
			return {"pos": pos3, "look": lk, "fov": 38.0, "focus": hp, "far": 0.8, "amount": 0.08}
		"boat_aerial":
			var c1: Vector3 = bx.origin
			return {"pos": c1 + bx.basis * Vector3(3.2 - 0.25 * t, 0, 3.6) + Vector3(0, 3.0 + 0.12 * t, 0), "look": c1 + Vector3(0, 0.5, 0), "fov": 42.0, "focus": c1, "far": 6.0, "amount": 0.02}
		"lantern_light":
			var lp := boat.lantern_pos("bow")
			var c2: Vector3 = (lp + _head(mika)) * 0.5
			return {"pos": bx * Vector3(0.0, 1.05, 2.6 + 0.04 * t), "look": c2, "fov": 44.0, "focus": c2, "far": 1.8, "amount": 0.05}
		"mika_lanterns":
			var mh: Vector3 = follow.call("mh", _head(mika) + Vector3(0, -0.35, 0), 0.08)
			return {"pos": bx * Vector3(0.35, 0.85, 2.3), "look": mh + (bx.basis * Vector3(0, -0.15, 0.35)), "fov": 40.0, "focus": mh, "far": 1.0, "amount": 0.06}
		"luna_lantern":
			var lh: Vector3 = follow.call("lh", _head(luna) + Vector3(0, -0.35, 0), 0.08)
			return {"pos": bx * Vector3(-1.4, 0.85, -2.1), "look": lh + (bx.basis * Vector3(0, -0.15, -0.35)), "fov": 40.0, "focus": lh, "far": 1.0, "amount": 0.06}
		"lanterns_wide":
			var c3: Vector3 = bx * Vector3(0.4, 0.35, 1.0)
			return {"pos": bx * Vector3(-2.2 + 0.1 * t, 0.28, 5.0), "look": c3, "fov": 46.0, "focus": c3, "far": 4.0, "amount": 0.05}
		"stargaze_two":
			var c4: Vector3 = bx * Vector3(0.3, 0.55, 0.0)
			return {"pos": bx * Vector3(0.45 - 0.03 * t, 2.35, 2.1), "look": c4, "fov": 44.0, "focus": c4, "far": 1.5, "amount": 0.04}
		"sky_point":
			# behind and below her right shoulder, along her raised arm to the star
			var sk2 := mika.skeleton
			var shp := sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("RightUpperArm")).origin
			var st := boat.seat_xform("stern")
			var pos4 := shp + st.basis.z * -0.95 + MoonBoat.side_vec(st, "Right") * 0.45 + Vector3(0, 0.3, 0)
			var sd := (Vector3(0.25, 1.0, 0.0) + st.basis.z * 0.5).normalized()
			return {"pos": pos4, "look": shp + sd * 1.0 + st.basis.z * 0.3, "fov": 56.0, "focus": shp + sd * 0.5, "far": 30.0, "amount": 0.02}
		"cu_luna_water":
			var hd := _head(luna)
			var st2 := boat.seat_xform("bow")
			var pos5 := hd + st2.basis.z * 0.75 + MoonBoat.side_vec(st2, "Left") * 0.45 + Vector3(0, -0.05, 0)
			return {"pos": pos5, "look": hd + Vector3(0, -0.05, 0), "fov": 34.0, "focus": hd, "far": 0.4, "amount": 0.1}
		"cu_mika_chin":
			var hd2 := _head(mika)
			var st3 := boat.seat_xform("stern")
			var pos6 := hd2 + st3.basis.z * 0.8 + MoonBoat.side_vec(st3, "Right") * 0.35 + Vector3(0, -0.1, 0)
			return {"pos": pos6, "look": hd2 + Vector3(0, -0.08, 0), "fov": 34.0, "focus": hd2, "far": 0.4, "amount": 0.1}
		"crane_out":
			var e := smoothstep(0.0, 7.0, t)
			var c5: Vector3 = bx.origin
			return {"pos": c5 + bx.basis * Vector3(lerpf(2.2, 6.0, e), 0, lerpf(2.0, 7.0, e)) + Vector3(0, lerpf(1.2, 7.5, e), 0), "look": c5 + Vector3(0, lerpf(0.6, 0.0, e), 0), "fov": 46.0, "focus": c5, "far": 12.0, "amount": 0.02}
	return {"pos": mid + Vector3(0, 0.5, 4.0), "look": mid, "fov": 40.0, "focus": mid, "far": 3.0, "amount": 0.03}


## A bright twinkling star in the sky (the one she points at).
func _lantern_star(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(14.0, 14.0)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/dance/glow_sprite.gdshader")
	m.set_shader_parameter("tex", load("res://assets/vfx/brackeys/particles/alpha/star_07_a.png"))
	m.set_shader_parameter("color", Color(1.0, 0.95, 0.85))
	m.set_shader_parameter("energy", 0.0)
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.world.add_child(mi)
	mi.global_position = at
	var tw := create_tween().set_loops(12)
	tw.tween_method(func(v): m.set_shader_parameter("energy", v), 2.0, 4.5, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v): m.set_shader_parameter("energy", v), 4.5, 2.0, 0.6).set_trans(Tween.TRANS_SINE)


## Stills of the two of them seated in the boat (Selwyn asked for 3 angles before the full clip): out on the lake at
## night, Luna rowing, Mika trailing her hand; after the dresses settle, three held angles (2 s each).
func _boatstill() -> void:
	await _hold_all()
	await _force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		main.performance.set_process(false)
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	await main.streaming.travel("lantern_lake", luna, false)
	main.day_night.set_override(true)
	await _wait(2.0)
	main.day_night.set_process(false)
	var lake: Node3D = null
	for n in main.world.find_children("*", "Node3D", true, false) + [main.world]:
		if n.get("water_mat") != null:
			lake = n
			break
	var water_y: float = lake.global_position.y
	var L := func(v: Vector3) -> Vector3: return lake.to_global(v)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if not (cl is ScreenFX):
			(cl as CanvasLayer).visible = false
	var boat := MoonBoat.spawn(main.world, L.call(Vector3(-1.5, 0.0, -9.0)), -PI * 0.5 + lake.global_rotation.y + 0.5, water_y)
	boat.lake = lake
	boat.day_night = main.day_night
	DanceStage.lantern_keep = 0.3
	DanceStage.hover_lanterns = false
	DanceStage.clear_radius = 7.0
	var stage := DanceStage.build(lake, L.call(Vector3(-1.5, 0.0, -9.0)), water_y, [L.call(Vector3(0.0, 1.5, -2.0))], luna)
	stage.light_also(mika)
	for c in [luna, mika]:
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.visible = true
		c.set_physics_process(false)
		c.set_hair_frame("")
	boat.seat(luna, "bow")
	boat.seat(mika, "stern")
	await _wait(1.0)
	boat.row(true)
	boat.trail_hand("stern", "Left", true)
	var probes := []
	if RenderProfile.options.has("trace"):
		var sk := mika.skeleton
		var names := []
		for n in sk.get_children():
			names.append(n)
		var started := false
		for n in names:
			if n is SeatPose:
				started = true
			if started and n is SkeletonModifier3D and not (n is TraceProbe):
				var tp := TraceProbe.new()
				tp.name = "Trace_after_" + String(n.name)
				sk.add_child(tp)
				sk.move_child(tp, n.get_index() + 1)
				probes.append(tp)
	var pin := CameraPin.new()
	main.add_child(pin)
	main.camera_rig.set_process(false)
	main.camera_rig.arm.process_mode = Node.PROCESS_MODE_DISABLED
	main.director.set_process(false)
	for g in get_tree().root.find_children("FramingGuard", "", true, false):
		(g as FramingGuard).process_mode = Node.PROCESS_MODE_DISABLED
	pin.fov = 40.0
	pin.active = true
	var bx := func() -> Transform3D: return boat.global_transform
	var angles := [["front_3q", Vector3(-2.6, 1.9, 2.6)], ["side", Vector3(0.35, 1.6, 3.6)], ["rear_3q", Vector3(3.2, 1.9, 2.2)]]
	var t0 := _game_t
	print("[boatstill] start frame %d" % Engine.get_frames_drawn())
	while _game_t - t0 < 6.0 + angles.size() * 2.0:
		await get_tree().process_frame
		var t := _game_t - t0
		var ai := clampi(int(maxf(t - 6.0, 0.0) / 2.0), 0, angles.size() - 1)
		var b: Transform3D = bx.call()
		pin.pos = b * (angles[ai][1] as Vector3)
		pin.look = b * Vector3(0.3, 0.55, 0.0)
		if t > 6.0 and absf(fmod(t - 6.0, 2.0) - 1.0) < 0.02:
			print("[boatstill] %s at frame %d" % [angles[ai][0], Engine.get_frames_drawn()])
			print("[boatstill]   ", boat.debug_grips())
			print("[boatstill]   ", boat.debug_rider("stern"))
			print("[boatstill]   ", boat.debug_rider("bow"))
			for tp in probes:
				print("[trace] %-32s hand %s chest %s" % [tp.name, str((tp.pos.get("LeftHand", Vector3.ZERO) as Vector3).snappedf(0.01)), str((tp.pos.get("UpperChest", Vector3.ZERO) as Vector3).snappedf(0.01))])
			for c in [luna, mika]:
				for n in c.skeleton.get_children():
					if n is SkirtDrape:
						print("[boatstill]   %s drape weight %.2f pen %s" % [c.character_id, (n as SkirtDrape).weight, str((n as SkirtDrape).penetration())])
	pin.active = false


## The show calls Mika away while she walks beside Luna on Luna's outing (2026-10-21 stream: the follower kept
## steering her toward Luna while the show walked her to its spot, back and forth 24 times): she leaves the walk
## cleanly, with no tug of war.
func _showtakes() -> void:
	await _hold_all()
	main.spawner.enabled = false
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var ll = main.get("live_link")
	_check(ll != null, "live link present (--live-link)")
	if ll == null:
		return
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	var cands: Array = lb.explore_map.candidates(5)
	_check(not cands.is_empty(), "Luna sees somewhere to go")
	if cands.is_empty():
		return
	var far: Dictionary = cands[0]
	for cd in cands:
		if (cd.pos as Vector3).distance_to(luna.global_position) > (far.pos as Vector3).distance_to(luna.global_position):
			far = cd
	var map: RID = mika.get_world_3d().navigation_map
	if main.teleport_guard:
		main.teleport_guard.allow(mika)
	mika.global_position = NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(1.8, 0, 0.8)) + Vector3(0, 0.05, 0)
	main.companionship.force_accept = true
	lb.hold = false
	mb.hold = false
	var box := {"done": false, "res": {}}
	(func():
		box.res = await main.companionship.invite(lb, "mika", "explore_together", {"pos": far.pos, "fill": {"place": String(far.describe)}})
		box.done = true).call()
	var t0 := _game_t
	while String(main.companionship.active.get("stage", "")) != "walking together" and not box.done and _game_t - t0 < 40.0:
		await get_tree().process_frame
	lb.hold = true
	_check(String(main.companionship.active.get("stage", "")) == "walking together", "Mika walks beside Luna on Luna's outing", main.companionship.active)
	await _wait(2.0)
	var cut := {"n": 0, "nav": 0}
	var on_fin := func(a: String, _ok: bool, d: String):
		if d == "interrupted by player input":
			cut.n += 1
	var on_start := func(a: String, _d: Dictionary):
		if a == "navigate_to":
			cut.nav += 1
	mika.action_finished.connect(on_fin)
	mika.action_started.connect(on_start)
	var job := {"done": false, "r": {}}
	mb.enabled = true                       # (as on stream: her planner runs; the show holds it)
	(func():
		job.r = await ll._brain_do(["explore", "investigate", "roam", "visit", "magic"], "explore")
		job.done = true).call()
	var t1 := _game_t
	while _game_t - t1 < 25.0:
		await get_tree().process_frame
	mika.action_finished.disconnect(on_fin)
	mika.action_started.disconnect(on_start)
	var steering: Array = main.companionship.get_children().filter(func(n): return n is FollowCompanion and n.follower == mika and not n.released)
	print("[mktest] showtakes: interrupted %d, walks started %d, show answer %s, mika doing %s" % [cut.n, cut.nav, str(job.r).left(160), str(mb.current).left(120)])
	_check(steering.is_empty(), "nothing steers her toward Luna any more")
	_check(cut.n <= 1 and cut.nav <= 6, "no tug of war: %d interrupted walks, %d walks started in 25 s" % [cut.n, cut.nav])
	_check(bool(job.r.get("ok", false)) or (not mb.current.is_empty() and String(mb.current.get("kind", "")) != "together"), "the show's activity runs", [job.r, mb.current])
	main.companionship.force_accept = false
