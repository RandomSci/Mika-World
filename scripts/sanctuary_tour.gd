class_name SanctuaryTour
extends Node
## Verification for the Arcane Sanctuary mini-region (--sanctuarytour[=shots|full]).
## For every sub-area in data/sanctuary.json: the establishing camera (day), FPS/GPU measurement,
## then (full) Mika walks to the sub-area's main activity and performs it while the camera director
## frames it, with a screenshot mid-activity. Night shots of the key sub-areas, a per-category GPU
## probe at the classic establishing view, and a short brain-driven run. Writes
## <shots_dir>/sanctuary/sanctuary_tour_<profile>.json and quits.

const MAIN_ACTIVITY := {
	"ritual_circle": "scroll_first_circle", "ancient_spell_library": "", "meditation_garden": "garden_meditate",
	"training_grounds": "rune_target_2", "ruined_forest_gate": "gate_inscription", "altar_chamber": "heartstone_attune",
	"watchpoint": "watchpoint_rest",
}

var main: Node
var report := {"profile": RenderProfile.profile, "sub_areas": {}, "night": {}, "probe": {}}
var dir := ""
var _vp_rid: RID


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/sanctuary"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _measure(sec: float) -> Dictionary:
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var worst := 0.0
	var gpu := 0.0
	while (Time.get_ticks_usec() - t0) < sec * 1e6:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	var el := (Time.get_ticks_usec() - t0) / 1e6
	return {"fps": snappedf(frames / el, 0.1), "worst_frame_ms": snappedf(worst, 0.01), "gpu_ms": snappedf(gpu / frames, 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}


func _tag() -> String:
	var t := String(RenderProfile.options.get("tag", ""))
	return ("_" + t) if t != "" else ""


func _shot(tag: String) -> String:
	var path := "%s/%s%s_%s.png" % [dir, RenderProfile.profile.to_lower(), _tag(), tag]
	get_viewport().get_texture().get_image().save_png(path)
	return path


func _cam(sub: Dictionary) -> Array:
	var c: Dictionary = sub.camera
	return [Vector3(c.pos[0], c.pos[1], c.pos[2]), Vector3(c.look[0], c.look[1], c.look[2])]


func _run() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var rig: ThirdPersonCamera = main.camera_rig
	var director = main.get("director")
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	var mode := String(RenderProfile.options.get("sanctuarytour", "true"))
	await _wait(3.0)
	report["build"] = main.streaming.history.back() if not main.streaming.history.is_empty() else {}
	var subs: Dictionary = WorldState.sanctuary.sub_areas
	if director:
		director.enabled = false
	for id in subs:
		var sub: Dictionary = subs[id]
		var rec := {}
		var cam := _cam(sub)
		rig.set_shot(cam[0], cam[1], 55.0)
		await _wait(1.2)
		rec["establishing"] = await _measure(1.5)
		rec["shot_establishing"] = _shot(id + "_establishing")
		report.sub_areas[id] = rec
		print("[sanctuarytour] ", id, " ", JSON.stringify(rec.establishing))
	rig.clear_shot()
	# Activities framed by the camera director
	if mode != "shots":
		if director:
			director.enabled = true
		for id in subs:
			var act: String = MAIN_ACTIVITY.get(id, "")
			if act == "" or not main.world.interactables.has(act):
				continue
			var it: Interactable = main.world.interactables[act]
			mika.navigate_to(it.approach_point(), true)
			var t0 := Time.get_ticks_msec()
			while mika.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 40000:
				await get_tree().process_frame
			var started := Time.get_ticks_msec()
			var res := [null]
			var job := func(): res[0] = await it.perform(mika)
			job.call()
			await _wait(minf(it.duration * 0.6 + 0.6, 4.0))
			report.sub_areas[id]["shot_activity"] = _shot(id + "_activity")
			report.sub_areas[id]["camera_mode"] = director.mode if director else ""
			report.sub_areas[id]["perf_activity"] = await _measure(1.0)
			while res[0] == null and Time.get_ticks_msec() - started < 20000:
				await get_tree().process_frame
			report.sub_areas[id]["activity"] = res[0]
			print("[sanctuarytour] activity ", act, " -> ", JSON.stringify(res[0]).left(200))
		if director:
			director.enabled = false
	# Night
	WorldState.night = true
	main.world.set_night(true)
	for id in ["ritual_circle", "meditation_garden", "altar_chamber", "watchpoint", "training_grounds"]:
		var cam := _cam(subs[id])
		rig.set_shot(cam[0], cam[1], 55.0)
		await _wait(1.4)
		report.night[id] = await _measure(1.2)
		report.night[id]["shot"] = _shot(id + "_night")
	WorldState.night = false
	main.world.set_night(false)
	# Per-category GPU cost at the classic establishing view (comparable with the earlier 29 ms probe)
	rig.set_shot(Vector3(12.5, 3.4, 14.5), Vector3(0, 1.8, -3.0), 55.0)
	await _wait(1.0)
	var base := await _measure(2.0)
	report.probe["all"] = base
	_shot("probe_view")
	for cat in ["terrain", "architecture", "rocks", "trees", "foliage", "props", "expansion", "ambient", "vista"]:
		var nodes: Array = get_tree().get_nodes_in_group("cat_" + cat)
		if cat == "vista":
			nodes = main.world.find_children("Vista", "", false, false)
		if cat == "ambient":
			nodes = main.world.find_children("AnimatedAmbientLife", "", false, false)
		for n in nodes: n.visible = false
		await _wait(0.4)
		var m := await _measure(1.2)
		report.probe["without_" + cat] = {"gpu_ms": m.gpu_ms, "saves_gpu_ms": snappedf(base.gpu_ms - m.gpu_ms, 0.01), "saves_prims": base.primitives - m.primitives, "nodes": nodes.size()}
		for n in nodes: n.visible = true
	rig.clear_shot()
	# Brain-driven minute (Mika chooses for herself) if available
	var brain = main.get("brain")
	if brain and mode == "full":
		brain.set_enabled(true)
		if director:
			director.enabled = true
		var t1 := Time.get_ticks_msec()
		var k := 0
		var walk := []
		while Time.get_ticks_msec() - t1 < 150000:
			await _wait(12.0)
			_shot("brain_%02d" % k)
			walk.append({"t": snappedf((Time.get_ticks_msec() - t1) / 1000.0, 0.1), "sub_area": SanctuaryBrain.sub_area(main.world, mika.global_position), "area": main.streaming.current_id,
				"decision": brain.last_decision.duplicate(), "camera": director.mode if director else ""})
			k += 1
		walk.append({"perf": await _measure(2.0)})
		brain.set_enabled(false)
		report["brain_run"] = {"log": brain.history.duplicate(), "samples": walk}
	report["final_state"] = WorldState.snapshot()
	report["mission"] = WorldState.mission_state()
	var f := FileAccess.open("%s/sanctuary_tour_%s%s.json" % [dir, RenderProfile.profile.to_lower(), _tag()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[sanctuarytour] done")
	get_tree().quit()
