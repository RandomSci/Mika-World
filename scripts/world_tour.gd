class_name WorldTour
extends Node
## Automated multi-region verification (--worldtour[=loc1,loc2,...]).
## Travels Mika through real gates (walk mode, predictive preload), and at each location:
## checks only one area is instantiated and navigation regions don't accumulate, measures
## FPS/frame time/memory, captures showcase screenshots (day; optional night), optionally casts,
## performs one interaction, then writes screenshots/worldtour_<profile>.json and quits.

var main: Node
var report := {"profile": RenderProfile.profile, "visits": [], "checks": {}}
var _vp_rid: RID
var _journey_done := false
var _journey_result := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RenderProfile.shots_dir))
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	main.travel.journey_event.connect(func(ev):
		if ev.event == "journey_finished":
			_journey_result = ev
			_journey_done = true)
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
	return {"fps": snappedf(frames / el, 0.1), "avg_frame_ms": snappedf(1000.0 * el / frames, 0.01), "worst_frame_ms": snappedf(worst, 0.01),
		"gpu_ms": snappedf(gpu / frames, 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects_in_frame": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"nav_regions": int(Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT)),
		"instantiated_areas": get_tree().get_nodes_in_group("streamed_area").size()}


func _shot(tag: String) -> String:
	var path := "%s/%s_%s.png" % [RenderProfile.shots_dir, RenderProfile.profile.to_lower(), tag]
	get_viewport().get_texture().get_image().save_png(path)
	return path


func _go(location: String, mode := "walk") -> Dictionary:
	_journey_done = false
	var r: Dictionary = main.travel.travel_to(location, mode)
	if not r.get("ok", false):
		return {"ok": false, "detail": r.get("error", "?")}
	var t0 := Time.get_ticks_msec()
	while not _journey_done and Time.get_ticks_msec() - t0 < 240000:
		await get_tree().process_frame
	if not _journey_done:
		main.travel.cancel("tour timeout")
		return {"ok": false, "detail": "timeout"}
	return _journey_result


func _run() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	var rig: ThirdPersonCamera = main.camera_rig
	await _wait(3.0)
	var plan: PackedStringArray
	var opt := String(RenderProfile.options.get("worldtour", "true"))
	if opt == "true":
		plan = PackedStringArray(["ritual_sanctuary", "ancient_spell_library", "ritual_sanctuary", "ancient_grove", "forgotten_forest_shrine"])
	else:
		plan = opt.split(",")
	var casts: PackedStringArray = String(RenderProfile.options.get("tourcast", "")).split(",", false)
	var night: bool = RenderProfile.options.has("tournight")
	var baseline := await _measure(1.0)
	report.checks["start"] = baseline
	for loc in plan:
		var visit := {"location": loc}
		if WorldState.current_location != loc or WorldState.area_of(loc) != main.streaming.current_id:
			var j := await _go(loc)
			visit["journey"] = j
			if not j.get("ok", false):
				print("[worldtour] FAILED to reach ", loc, ": ", j.get("detail", ""), " pos=", mika.global_position, " on_floor=", mika.is_on_floor(), " vel=", mika.velocity, " hits=", range(mika.get_slide_collision_count()).map(func(i): return str(mika.get_slide_collision(i).get_collider().get_parent().name) + "/" + str(mika.get_slide_collision(i).get_collider().get_parent().get_parent().name) + " n=" + str(mika.get_slide_collision(i).get_normal().snapped(Vector3.ONE * 0.01))))
				report.visits.append(visit)
				continue
		await _wait(1.0)
		rig.clear_shot()
		rig.snap_behind()
		await _wait(1.2)
		visit["perf_explore"] = await _measure(2.0)
		visit["shot_chase"] = _shot(loc + "_chase")
		var shots: Array = main.world.call("showcase_shots", loc) if main.world.has_method("showcase_shots") else []
		var si := 0
		for s in shots:
			rig.set_shot(s[0], s[1], s[2] if s.size() > 2 else 55.0)
			await _wait(1.0)
			visit["shot_%d" % si] = _shot("%s_view%d" % [loc, si])
			si += 1
		rig.clear_shot()
		if night:
			WorldState.night = true
			main.world.set_night(true)
			await _wait(0.8)
			if not shots.is_empty():
				rig.set_shot(shots[0][0], shots[0][1], shots[0][2] if shots[0].size() > 2 else 55.0)
				await _wait(1.0)
			visit["shot_night"] = _shot(loc + "_night")
			visit["perf_night"] = await _measure(1.5)
			rig.clear_shot()
			WorldState.night = false
			main.world.set_night(false)
		# one real interaction at this location if available
		for id in main.world.interactables:
			var it: Interactable = main.world.interactables[id]
			if it.location_id == loc and it.requires.is_empty():
				mika.navigate_to(it.global_position)
				var t0 := Time.get_ticks_msec()
				while mika.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 30000:
					await get_tree().process_frame
				visit["interaction"] = await it.perform(mika)
				break
		if loc in casts:
			rig.snap_behind()
			var spell = mika.cast_spell(ArcaneOrbSpell, "prepare_and_cast")
			if spell:
				var frames := 0
				var t0 := Time.get_ticks_usec()
				var worst := 0.0
				var last := t0
				var shot_done := false
				var skip_next := false
				while is_instance_valid(spell):
					await get_tree().process_frame
					var now := Time.get_ticks_usec()
					if not skip_next:
						worst = maxf(worst, (now - last) / 1000.0)  # the frame that saved a PNG is excluded
					skip_next = false
					last = now
					frames += 1
					if not shot_done and spell.t > spell.duration * 0.6:
						visit["shot_cast"] = _shot(loc + "_cast")
						shot_done = true
						skip_next = true
						last = Time.get_ticks_usec()
				var el := (Time.get_ticks_usec() - t0) / 1e6
				visit["perf_cast"] = {"fps": snappedf(frames / el, 0.1), "worst_frame_ms": snappedf(worst, 0.01), "seconds": snappedf(el, 0.01)}
		visit["world_state"] = WorldState.snapshot()
		report.visits.append(visit)
		print("[worldtour] ", loc, " ", JSON.stringify({"explore": visit.perf_explore, "cast": visit.get("perf_cast", {}), "interaction": visit.get("interaction", {}).get("detail", "")}))
	report.checks["transitions"] = main.streaming.history
	report.checks["end"] = await _measure(1.0)
	var f := FileAccess.open("%s/worldtour_%s.json" % [RenderProfile.shots_dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[worldtour] done")
	get_tree().quit()
