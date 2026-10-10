class_name AlchemyTest
extends Node
## --alchemytest: physical alchemy. (1) an uninformed experiment (moonwater + ember salt) -> fizz;
## (2) Mika travels to the library and really reads "On Gathering" (the recipe); (3) back at the table she
## brews the Luminous Draught. Screenshots during reach / pour / result; hand-to-object distances logged.

var main: Node
var report := {"runs": []}
var dir := ""
var _shots := []


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/alchemytest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> void:
	var path := "%s/%s_%s.png" % [dir, RenderProfile.profile.to_lower(), tag]
	get_viewport().get_texture().get_image().save_png(path)
	_shots.append(path)


func _frame_table() -> void:
	var t: AlchemyTable = main.world.alchemy
	var m: WorldCharacter = main.characters["mika"]
	var mid := (t.bowl_pos + m.global_position) * 0.5
	main.camera_rig.set_shot(mid + Vector3(0.6, 0.9, 1.9), t.bowl_pos + Vector3(0.25, 0.25, 0), 45.0)


func _experiment(tag: String, ingredients: Array, stir) -> Dictionary:
	var m: WorldCharacter = main.characters["mika"]
	var it: Interactable = main.world.interactables["alchemy_table"]
	m.global_position = it.approach_point() + Vector3(0, 0.1, 0)
	await _wait(0.5)
	var t: AlchemyTable = main.world.alchemy
	it.custom_activity = func(c): return await t.experiment(c, ingredients, stir)
	var watch := {"min_palm_to_target": 9.0}
	var job := [null]
	var runner := func(): job[0] = await it.perform(m)
	runner.call()
	var t0 := Time.get_ticks_msec()
	var shot_times := [2.6, 5.2, 7.0]
	var k := 0
	while job[0] == null and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		_frame_table()
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if m.handler.ik.influence > 0.9:
			watch.min_palm_to_target = minf(watch.min_palm_to_target, m.handler.palm().distance_to(m.handler.target.global_position + (m.handler.palm() - m.right_hand.global_position) * 0.6))
		if k < shot_times.size() and el > shot_times[k]:
			_shot("%s_%d" % [tag, k])
			k += 1
	await _wait(0.6)
	_shot(tag + "_result")
	var r: Dictionary = job[0] if job[0] != null else {"ok": false, "detail": "timeout"}
	r["palm_tracking"] = watch
	r["table_after"] = t.describe()
	r["inventory"] = WorldState.inventory.duplicate()
	print("[alchemytest] %s -> %s | %s" % [tag, r.get("activity", {}).get("outcome", "?"), str(r.get("activity", {}).get("steps", []))])
	main.camera_rig.clear_shot()
	return r


func _run() -> void:
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	await _wait(4.0)
	report.runs.append(await _experiment("uninformed", ["moonwater", "ember_salt"], false))
	main.world.alchemy._reset_at = 0.1   # drain now (the table normally waits ~40 s)
	await _wait(0.5)
	var m: WorldCharacter = main.characters["mika"]
	await main.streaming.travel("arcane_library", m)
	await _wait(1.5)
	var it: Interactable = main.world.interactables["desk_gathering"]
	m.global_position = it.approach_point() + Vector3(0, 0.1, 0)
	await _wait(0.4)
	report["reading"] = await it.perform(m)
	print("[alchemytest] read On Gathering -> learned ", report.reading.get("reading", {}).get("learned", []))
	await main.streaming.travel("sanctuary", m)
	await _wait(1.5)
	report.runs.append(await _experiment("recipe", [], null))
	report["shots"] = _shots
	var f := FileAccess.open("%s/alchemy_test_%s.json" % [dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[alchemytest] done")
	get_tree().quit()
