class_name MilestoneITest
extends Node
## --mitest=<mode>: Milestone I checks. Disposable saves only (user://test_regress_*.json).
##   form1 / form2   a form reached at Level 10 is her permanent appearance: survives a restart; previews
##                   and an Orbit Surge never change it
##   background      Mika (followed) travels away: Luna drops to the background, simulates only honest
##                   activities (no new knowledge, discoveries, victories or items), and is rebuilt exactly where
##                   she was when the Sanctuary returns
##   focus           cross-area camera focus: switching to the mage in the unloaded area loads it and rebuilds her;
##                   switching back restores the first; nothing is rewarded or lost in between
##   luna_read       Luna notices a book, reads it through her own planner: pages + knowledge in HER mind only
##   luna_alchemy    Luna experiments at the alchemy table: the result is her discovery only
## (exploration / interaction / audience / music modes are added by later stages)

var main: Node
var mode := ""
var checks: Array = []
var failed := false
var report := {}
var dir := ""


func _ready() -> void:
	mode = String(RenderProfile.options.get("mitest", ""))
	dir = RenderProfile.shots_dir + "/mitest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _check(ok: bool, what: String, detail = "") -> void:
	checks.append({"ok": ok, "check": what, "detail": str(detail).left(400)})
	print("[mitest]   %s %s %s" % ["ok  " if ok else "FAIL", what, ("(" + str(detail).left(220) + ")") if str(detail) != "" else ""])
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
	print("[mitest] mode=%s save=%s persistent=%s mages=%s" % [mode, WorldState.save_path, WorldState.persistent, main.mages])
	if not WorldState.save_path.begins_with("user://test_regress_"):
		_check(false, "refusing to run: tests need a disposable user://test_regress_*.json save", WorldState.save_path)
		_finish()
		return
	await _wait(2.0)
	await dispatch()
	_finish()


func _finish() -> void:
	var f := FileAccess.open("%s/%s.json" % [dir, mode], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"mode": mode, "passed": not failed, "checks": checks, "report": report}, "  "))
		f.close()
	print("[mitest] %s %s" % ["FAIL" if failed else "PASS", mode])
	get_tree().quit(1 if failed else 0)


## Stop a mage's own planner from starting anything new AND wait until her current activity is over, so
## the test is the only thing driving her (one controller per character).
func _hold(b: SanctuaryBrain) -> void:
	b.hold = true
	var t0 := Time.get_ticks_msec()
	while not b.current.is_empty() and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame


func _snapshot(who: String) -> Dictionary:
	var m := WorldState.mind(who)
	return {"knowledge": m.knowledge.keys().filter(func(k): return not String(k).begins_with("noticed")), "inventory": m.inventory.duplicate(),
		"xp": float(m.progress.xp), "level": m.level(), "trials": m.trials_done.keys(), "seq": m.activity_seq}


# ------------------------------------------------------------------ permanent forms
func _form1() -> void:
	var m := WorldState.mind("mika")
	var mika: WorldCharacter = main.characters["mika"]
	_check(TransformationDirector.appearance("mika") == "" and mika.avatar_path.ends_with("Mika.vrm"), "fresh: base appearance")
	# fixture: the gate was passed (the real path is covered by mhtest=levelup); the unlock plays the full sequence
	m.progress.level = 10
	(m.progress.forms_unlocked as Array).append("bloom")
	var res: Dictionary = await main.transformer.play("mika", "full", false)
	_check(res.get("permanent", false) and TransformationDirector.appearance("mika") == "bloom" and mika.avatar_path.ends_with("Mika_Level10.vrm"), "the unlock makes Bloom Form her appearance", res)
	await _wait(1.0)
	await main.transformer.play("mika", "short", true)
	await _wait(2.0)
	_check(mika.avatar_path.ends_with("Mika_Level10.vrm"), "a preview returns her to Bloom Form (not the base)", mika.avatar_path)
	_check(WorldState.save_game(), "saved")


func _form2() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	_check(WorldState.load_report.get("result", "") == "loaded", "restart loaded the save", WorldState.load_report)
	_check(TransformationDirector.appearance("mika") == "bloom" and mika.avatar_path.ends_with("Mika_Level10.vrm"), "after the restart she is still in Bloom Form", mika.avatar_path)
	_check(main.characters.has("luna") and main.characters["luna"].avatar_path.ends_with("Luna_Level01.vrm"), "Luna keeps her own (base) appearance")
	var res: Dictionary = await main.transformer.surge("mika")
	_check(res.get("surge", false) and mika.avatar_path.ends_with("Mika_Level10.vrm") and mika.has_meta("form_power"), "Orbit Surge: power, no costume change", res)
	main.transformer.surges["mika"].until = 0.0
	await _wait(1.5)
	_check(not mika.has_meta("form_power") and mika.avatar_path.ends_with("Mika_Level10.vrm"), "surge ended, form kept")
	var t0 := Time.get_ticks_msec()
	mika.navigate_to(mika.global_position + Vector3(2.5, 0, 1.0))
	while mika.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	_shot("bloom_walking")
	_check(mika.anim_tree.active and mika.body_player.has_animation("mx/walk"), "she walks in her form (animation tree intact)")


# ------------------------------------------------------------------ background simulation
func _background() -> void:
	var luna: WorldCharacter = main.characters["luna"]
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	await _wait(3.0)
	_check(main.sim_mode("luna") == "nearby" and luna.visible, "Luna is nearby (same area, simulated in full)", main.sim_mode("luna"))
	# Mika (followed) goes to the library: the Sanctuary unloads (Luna between activities, as in play)
	await _hold(lb)
	var before := _snapshot("luna")
	var r: Dictionary = await main.streaming.travel("arcane_library", main.characters["mika"])
	var pos0 := WorldState.mind("luna").location_pos()      # where she was when her area unloaded
	lb.hold = false
	_check(r.get("ok", false), "the library loaded for Mika")
	_check(main.sim_mode("luna") == "background" and not luna.visible and WorldState.mind("luna").location.get("area", "") == "sanctuary", "Luna is now in the background, remembered in the Sanctuary", WorldState.mind("luna").location)
	var secs := float(RenderProfile.options.get("seconds", "150"))
	await _wait(secs)
	var after := _snapshot("luna")
	var new_keys: Array = after.knowledge.filter(func(k): return not before.knowledge.has(k))
	report["bg_log"] = lb.bg_log
	report["new_keys"] = new_keys
	report["deferred"] = WorldState.mind("luna").deferred
	_check(lb.bg_log.size() >= 2, "she kept living in the background (%d simulated activities)" % lb.bg_log.size(), lb.bg_log.map(func(e): return e.activity))
	_check(new_keys.filter(func(k): return not (String(k).begins_with("journal") or String(k) == "journal_cursor")).is_empty(), "no new knowledge, discoveries, reactions or victories were invented", new_keys)
	_check(after.inventory == before.inventory, "no items appeared", [before.inventory, after.inventory])
	var practice_ok: int = lb.bg_log.filter(func(e): return e.activity == "practice" and e.get("success", false)).size()
	_check(float(after.xp) - float(before.xp) <= practice_ok * 4.0 + 0.01, "XP only from repeat practice under the normal decaying rule (+%.1f for %d successful practices)" % [float(after.xp) - float(before.xp), practice_ok])
	_check(WorldState.mind("luna").activity_log.filter(func(e): return int(e.seq) > int(before.seq)).all(func(e): return e.activity.get("sim", "") == "background"), "every background record is labelled as simulated")
	# Mika returns: Luna is rebuilt where she was (measured before her own planner moves her again)
	lb.hold = true
	var r2: Dictionary = await main.streaming.travel("sanctuary", main.characters["mika"])
	await get_tree().physics_frame
	_check(r2.get("ok", false) and luna.visible and main.sim_mode("luna") == "nearby", "back in the Sanctuary: Luna is present again")
	_check(luna.global_position.distance_to(pos0) < 1.5, "she is rebuilt where she was, on the nearest walkable point (%.2f m)" % luna.global_position.distance_to(pos0))


func _focus() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	await _wait(3.0)
	var mb := _snapshot("mika")
	var lbs := _snapshot("luna")
	await main.streaming.travel("arcane_library", mika)
	await _wait(2.0)
	var mika_lib_pos := mika.global_position
	report["loc_before"] = WorldState.mind("mika").location.duplicate()
	report["pos_before"] = str(mika_lib_pos)
	var res: Dictionary = await main.focus_mage("luna")
	report["loc_after_switch"] = WorldState.mind("mika").location.duplicate()
	report["to_luna"] = res
	_check(res.get("ok", false) and res.get("area_change", false) and main.streaming.current_id == "sanctuary", "focus Luna: her area (the Sanctuary) loaded", res)
	_check(main.focus == "luna" and luna.visible and not mika.visible and main.sim_mode("mika") == "background", "Luna followed; Mika in the background in the library")
	_check(main.director.mika == luna and main.camera_rig.target == luna, "camera follows Luna")
	await _wait(20.0)
	_shot("luna_focus")
	var res2: Dictionary = await main.focus_mage("mika")
	report["to_mika"] = res2
	report["pos_after"] = str(mika.global_position)
	report["loc_after_return"] = WorldState.mind("mika").location.duplicate()
	_check(res2.get("ok", false) and main.streaming.current_id == "arcane_library" and mika.visible and main.focus == "mika", "focus back to Mika: the library reloads", res2)
	_check(mika.global_position.distance_to(mika_lib_pos) < 1.0, "Mika is where she was in the library (%.2f m)" % mika.global_position.distance_to(mika_lib_pos))
	var ma := _snapshot("mika")
	var la := _snapshot("luna")
	_check(ma.inventory == mb.inventory and la.inventory == lbs.inventory, "no items gained or lost across the switches")
	_check(ma.knowledge.filter(func(k): return not mb.knowledge.has(k) and not String(k).begins_with("journal")).is_empty(), "Mika gained no knowledge while out of view")


# ------------------------------------------------------------------ Luna's widened capabilities
func _luna_read() -> void:
	var luna: WorldCharacter = main.characters["luna"]
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	await _hold(lb)
	main.mage_brains["mika"].set_enabled(false)
	var it: Node3D = main.world.interactables.get("scroll_first_circle")
	_check(it != null, "the scroll exists")
	_check(lb.options().filter(func(o): return o.kind == "research").is_empty(), "before noticing anything she has no books to read")
	var map: RID = luna.get_world_3d().navigation_map
	luna.global_position = NavigationServer3D.map_get_closest_point(map, it.global_position + Vector3(1.5, 0, 1.5)) + Vector3(0, 0.1, 0)
	await _wait(1.0)
	lb.perceive()
	_check(WorldState.mind("luna").knowledge.has("noticed:scroll_first_circle") and not WorldState.mind("mika").knowledge.has("noticed:scroll_first_circle"), "standing near it, she notices the scroll (her memory only)")
	var opts := lb.options().filter(func(o): return o.kind == "research" and o.book == "scroll_first_circle")
	_check(not opts.is_empty(), "now her planner can choose to read it")
	if opts.is_empty():
		return
	var mika_read := BookLibrary.pages_read("scroll_first_circle", "mika").duplicate()
	var res: Dictionary = await lb.run_activity(opts[0])
	report["read"] = {"ok": res.get("ok"), "detail": res.get("detail")}
	_check(not BookLibrary.pages_read("scroll_first_circle", "luna").is_empty(), "the pages she read are in HER memory", BookLibrary.pages_read("scroll_first_circle", "luna"))
	_check(BookLibrary.pages_read("scroll_first_circle", "mika") == mika_read, "Mika's reading record did not change")
	_check(WorldState.mind("luna").knowledge.keys().any(func(k): return String(k).begins_with("lore:")) and WorldState.mind("luna").trials_done.has("read_first_circle"), "she learned the lore and completed the trial herself")


func _luna_alchemy() -> void:
	var lb: SanctuaryBrain = main.mage_brains["luna"]
	await _hold(lb)
	main.mage_brains["mika"].set_enabled(false)
	var mika_k := WorldState.mind("mika").knowledge.keys().filter(func(k): return String(k).begins_with("alchemy:"))
	var opts := lb.options().filter(func(o): return o.kind == "alchemy")
	_check(not opts.is_empty(), "alchemy is one of Luna's options")
	if opts.is_empty():
		return
	var res: Dictionary = await lb.run_activity(opts[0])
	report["alchemy"] = res.get("detail", res)
	_check(res.get("ok", false), "she finished the experiment", res.get("detail", ""))
	var lk := WorldState.mind("luna").knowledge.keys().filter(func(k): return String(k).begins_with("alchemy:"))
	_check(not lk.is_empty() or String(res.get("detail", "")).contains("inert"), "the result is in HER memory", lk)
	_check(WorldState.mind("mika").knowledge.keys().filter(func(k): return String(k).begins_with("alchemy:")) == mika_k, "Mika learned nothing from it")


## Explicit dispatch (each mode is a coroutine; later stages add theirs here).
func dispatch() -> void:
	match mode:
		"form1": await _form1()
		"form2": await _form2()
		"background": await _background()
		"focus": await _focus()
		"luna_read": await _luna_read()
		"luna_alchemy": await _luna_alchemy()
		_: _check(false, "unknown mode " + mode)
