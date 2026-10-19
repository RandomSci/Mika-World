extends RefCounted
## --mktest=persist_walk: the kill / resume proof for an ordinary walk (v1 item 1). Needs --persist --game-clock and a
## test_regress_* save. Phase 1: in the sanctuary Luna walks to a far point; once a save taken mid-walk is on disk:
## READY_FOR_KILL (the shell sends SIGKILL). Phase 2 (same save): she is where that save put her (within 5 cm, the
## same facing), she walks on toward the same destination (closer after 3 s), no teleport home; level/XP unchanged.

const C := preload("res://scripts/tests/ext/persist_common.gd")


static func run(t) -> void:
	print("[persist_walk] phase %s, save %s (%s), persistent %s" % [C.phase(), WorldState.save_path, WorldState.load_report.get("result", "new"), WorldState.persistent])
	if not WorldState.persistent:
		t._check(false, "the kill/resume test needs --persist (a persistent test_regress_* save)")
		return
	if C.phase() == "1":
		await _phase1(t)
	else:
		await _phase2(t)


static func _phase1(t) -> void:
	var main: Node = t.main
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	var luna: WorldCharacter = main.characters["luna"]
	var map: RID = luna.get_world_3d().navigation_map
	var goal := NavigationServer3D.map_get_closest_point(map, luna.global_position + Vector3(22.0, 0.0, -16.0))
	luna.navigate_to(goal, false)
	var truth := {}
	main.scene_persist.captured.connect(func(d: Dictionary):
		C.add_truth(truth, {"seq": int(d.seq), "unix": int(d.unix), "area": main.streaming.current_id, "pos": [luna.global_position.x, luna.global_position.y, luna.global_position.z],
			"yaw": luna.global_rotation.y, "action": String(luna.current_action), "goal": [goal.x, goal.y, goal.z], "mages": {"luna": C.level_xp("luna")}}))
	var t0: float = t._game_t
	while t._game_t - t0 < 60.0:
		await t._wait(0.25)
		if t._game_t - t0 > 4.0 and luna.current_action == "navigate_to" and bool(WorldState.last_save.get("ok", false)) and not truth.is_empty():
			var ks := truth.keys()
			ks.sort_custom(func(a, b): return int(a) < int(b))
			if String((truth[ks.back()] as Dictionary).action) == "navigate_to":
				break
	t._check(luna.current_action == "navigate_to", "saved mid-walk (%s)" % luna.current_action)
	C.still(t, "before_kill")
	await C.await_kill(t)


static func _phase2(t) -> void:
	var main: Node = t.main
	var sp: ScenePersist = main.scene_persist
	var w0: float = t._game_t
	while not sp.resumed_done and t._game_t - w0 < 30.0:
		await t.get_tree().process_frame
	var rep: Dictionary = sp.report
	print("[persist_walk] resume report: %s" % JSON.stringify(rep).left(800))
	var truths := C.read_truth()
	var seq := int(WorldState.scene.get("seq", -1))
	var tr: Dictionary = truths.get(str(seq), {})
	if tr.is_empty() and not truths.is_empty():
		var ks := truths.keys()
		ks.sort_custom(func(a, b): return int(a) < int(b))
		tr = truths[ks.back()]
	t._check(not tr.is_empty(), "the truth of the loaded snapshot #%d" % seq)
	if tr.is_empty():
		return
	var luna: WorldCharacter = main.characters["luna"]
	var at := Vector3(float(tr.pos[0]), float(tr.pos[1]), float(tr.pos[2]))
	var goal := Vector3(float(tr.goal[0]), float(tr.goal[1]), float(tr.goal[2]))
	t._check(main.streaming.current_id == String(tr.area), "same area (%s)" % main.streaming.current_id)
	var placed: Array = rep.get("mages", {}).get("luna", {}).get("placed", [])
	var d0 := Vector2(float(placed[0]) - at.x, float(placed[2]) - at.z).length() if placed.size() == 3 else 9.9
	t._check(d0 < 0.05, "placed where the save put her (%.3f m off)" % d0)
	t._check(luna.current_action == "navigate_to", "walking on after the restart (%s)" % luna.current_action)
	var g0 := luna.global_position.distance_to(goal)
	C.still(t, "after_resume")
	await t._wait(3.0)
	var g1 := luna.global_position.distance_to(goal)
	t._check(g1 < g0 - 0.5, "she walks on toward the same destination (%.1f -> %.1f m)" % [g0, g1])
	var ng: Vector3 = luna.get("_nav_goal")
	t._check(luna.current_action == "navigate_to" and ng.distance_to(goal) < 0.3, "nothing replaced the resumed walk (goal %.2f m from the saved one)" % ng.distance_to(goal))
	var lx := C.level_xp("luna")
	var lt: Dictionary = tr.mages.luna
	t._check(int(lx.level) == int(lt.level) and absf(float(lx.xp) - float(lt.xp)) < 1e-4, "level and XP unchanged (%s vs %s)" % [str(lx), str(lt)])
	C.still(t, "after_resume_3s")
