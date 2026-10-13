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
