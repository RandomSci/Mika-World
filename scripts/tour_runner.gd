class_name TourRunner
extends Node
## Automated verification run (--tour): real screenshots from cinematic camera positions,
## a scripted movement test, a cast captured at several phases, day + night, and
## measured performance written to screenshots/report_<profile>.json. Then quits.

var main: Node
var report := {"shots": [], "tests": {}}
var _vp_rid: RID


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RenderProfile.shots_dir))
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _measure(sec: float) -> Dictionary:
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	var last := t0
	var gpu := 0.0
	var cpu := 0.0
	while (Time.get_ticks_usec() - t0) < sec * 1e6:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()
	var elapsed := (Time.get_ticks_usec() - t0) / 1e6
	return {
		"fps": snappedf(frames / elapsed, 0.1),
		"avg_frame_ms": snappedf(1000.0 * elapsed / frames, 0.01),
		"worst_frame_ms": snappedf(worst, 0.01),
		"gpu_ms": snappedf(gpu / frames, 0.01),
		"render_cpu_ms": snappedf(cpu / frames, 0.01),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
	}


func _shot(name: String, pos: Vector3, look: Vector3, fov := 50.0, settle := 1.2, measure := true) -> void:
	var rig: ThirdPersonCamera = main.camera_rig
	if pos != Vector3.ZERO:
		rig.set_shot(pos, look, fov)
	await _wait(settle)
	var perf := {}
	if measure:
		perf = await _measure(1.5)
	var tag := "%s_%s" % [RenderProfile.profile.to_lower(), name]
	var path := "%s/%s.png" % [RenderProfile.shots_dir, tag]
	get_viewport().get_texture().get_image().save_png(path)
	perf["name"] = tag
	report.shots.append(perf)
	print("[tour] ", tag, " ", JSON.stringify(perf))


func _run() -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var world: Sanctuary = main.world
	var rig: ThirdPersonCamera = main.camera_rig
	report["renderer"] = "%s/%s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()]
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["profile"] = RenderProfile.profile
	report["resolution"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	main.player.enabled = false  # scripted control only during the tour
	print("[tour] warming up (shader compilation)...")
	await _wait(5.0)

	# --- avatar validation from multiple angles (day)
	var mp := mika.global_position
	await _shot("mika_front", mp + Vector3(0.35, 1.25, -1.9), mp + Vector3(0, 1.0, 0), 42.0)
	if RenderProfile.options.has("quick"):
		await _shot("establishing", Vector3(12.5, 3.4, 14.5), Vector3(0, 1.8, -3.0), 55.0)
		await _shot("dais_lowangle", Vector3(3.2, 0.95, 6.5), Vector3(-0.5, 1.6, -4.0), 55.0)
		await _shot("altar_detail", Vector3(1.3, 1.75, -1.0), Vector3(0, 1.75, -2.6), 45.0)
		await _shot("floor_detail", Vector3(1.5, 2.2, 3.0), Vector3(0, 0.6, 0.0), 50.0)
		if RenderProfile.options.has("probe"):
			await _perf_probe()
		if RenderProfile.options.has("cast"):
			await _cast_sequence("day")
		get_tree().quit()
		return
	await _shot("mika_portrait", mp + Vector3(0.25, 1.42, -0.85), mp + Vector3(0, 1.33, 0), 35.0, 0.6, false)
	await _shot("mika_side", mp + Vector3(2.2, 1.0, 0.2), mp + Vector3(0, 0.85, 0), 42.0, 0.6, false)
	await _shot("mika_back", mp + Vector3(-0.6, 1.5, 2.6), mp + Vector3(0, 1.0, -1.0), 45.0, 0.6, false)

	# --- environment composition
	await _shot("establishing", Vector3(12.5, 3.4, 14.5), Vector3(0, 1.8, -3.0), 55.0)
	await _shot("dais_lowangle", Vector3(3.2, 0.95, 6.5), Vector3(-0.5, 1.6, -4.0), 55.0)
	await _shot("colonnade_ground", Vector3(8.2, 0.35, 4.5), Vector3(-2.0, 3.2, -7.0), 60.0)
	await _shot("through_arch", Vector3(0.6, 1.7, -26.0), Vector3(0, 1.6, 0), 50.0)
	await _shot("altar_detail", Vector3(1.3, 1.75, -1.0), Vector3(0, 1.75, -2.6), 45.0)
	await _shot("west_ruins", Vector3(-6.0, 1.6, 6.0), Vector3(-15.0, 1.5, -4.0), 55.0)
	await _shot("training_clearing", Vector3(17.0, 2.4, 13.0), Vector3(26.0, 0.8, 4.0), 55.0)

	# --- movement test (real physics): walk forward 2.5 s, run 2.5 s, check ground contact
	rig.clear_shot()
	rig.yaw = PI
	var p0 := mika.global_position
	mika.set_move_input(Vector3(0, 0, 1), false)   # south, down the dais
	await _wait(1.3)
	await _shot("walk_chase", Vector3.ZERO, Vector3.ZERO, 52.0, 0.0, false)
	await _wait(1.2)
	var p1 := mika.global_position
	mika.set_move_input(Vector3(0.3, 0, 1).normalized(), true)
	await _wait(1.2)
	await _shot("run_chase", Vector3.ZERO, Vector3.ZERO, 52.0, 0.0, false)
	await _wait(1.3)
	var p2 := mika.global_position
	mika.set_move_input(Vector3.ZERO, false)
	await _wait(1.0)
	report.tests["movement"] = {"walk_distance_m": snappedf(p0.distance_to(p1), 0.01), "run_distance_m": snappedf(p1.distance_to(p2), 0.01),
		"walk_speed_mps": snappedf(Vector2(p1.x - p0.x, p1.z - p0.z).length() / 2.5, 0.01), "run_speed_mps": snappedf(Vector2(p2.x - p1.x, p2.z - p1.z).length() / 2.5, 0.01),
		"on_floor_after": mika.is_on_floor(), "end_position": [p2.x, p2.y, p2.z],
		"ground_height_at_end": world.terrain.height(p2.x, p2.z)}
	print("[tour] movement ", JSON.stringify(report.tests.movement))

	# --- AI bridge: navigate back to the ritual circle via the structured interface
	var reply: Dictionary = main.bridge.handle({"id": "tour-1", "cmd": "navigate_to", "target": "ritual_circle"})
	var nav_result := {"reply": reply}
	var done := [false]
	var cb := func(a, ok, d):
		if a == "navigate_to":
			nav_result["finished"] = {"ok": ok, "detail": d}
			done[0] = true
	mika.action_finished.connect(cb)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	mika.action_finished.disconnect(cb)
	nav_result["seconds"] = (Time.get_ticks_msec() - t0) / 1000.0
	report.tests["bridge_navigate"] = nav_result
	main.bridge.handle({"id": "tour-2", "cmd": "look_at", "target": "spell_altar"})
	await _wait(1.5)
	report.tests["bridge_observe"] = main.bridge.handle({"id": "tour-3", "cmd": "observe"})
	print("[tour] bridge ", JSON.stringify(report.tests))

	# --- cast captured at several phases (day)
	await _cast_sequence("day")

	# --- night variation
	world.set_night(true)
	await _wait(1.0)
	await _shot("night_establishing", Vector3(12.5, 3.4, 14.5), Vector3(0, 1.8, -3.0), 55.0)
	await _shot("night_dais", Vector3(3.2, 0.95, 6.5), Vector3(-0.5, 1.6, -4.0), 55.0)
	await _cast_sequence("night")
	world.set_night(false)

	var f := FileAccess.open("%s/report_%s.json" % [RenderProfile.shots_dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[tour] done")
	get_tree().quit()


func _cast_sequence(tag: String) -> void:
	var mika: WorldCharacter = main.characters["mika"]
	var rig: ThirdPersonCamera = main.camera_rig
	var mp := mika.global_position
	var fwd := -mika.global_transform.basis.z
	var right := mika.global_transform.basis.x
	var cam := mp + fwd * 1.6 + right * 3.6 + Vector3(0, 1.25, 0)
	var look := mp + fwd * 1.9 + Vector3(0, 1.7, 0)
	rig.set_shot(cam, look, 52.0)
	await _wait(0.8)
	var spell: ArcaneOrbSpell = mika.cast_spell(ArcaneOrbSpell, "prepare_and_cast")
	if spell == null:
		report.tests["cast_" + tag] = {"ok": false}
		return
	var dur := spell.duration
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var marks := [0.1, 0.25, 0.4, 0.5, 0.6, 0.66, 0.72, 0.8, 0.9, 0.97]
	var mi := 0
	var start := Time.get_ticks_msec()
	while is_instance_valid(spell) and mi < marks.size():
		await get_tree().process_frame
		frames += 1
		var nt := spell.t / dur  # spell clock == animation clock (both advance by frame delta)
		if nt >= marks[mi]:
			var path := "%s/%s_cast_%s_%02d.png" % [RenderProfile.shots_dir, RenderProfile.profile.to_lower(), tag, int(marks[mi] * 100)]
			get_viewport().get_texture().get_image().save_png(path)
			mi += 1
	while is_instance_valid(spell):
		await get_tree().process_frame
		frames += 1
	var el := (Time.get_ticks_usec() - t0) / 1e6
	report.tests["cast_" + tag] = {"ok": true, "clip_seconds": snappedf(dur, 0.01), "avg_fps_during_cast": snappedf(frames / el, 0.1), "action_after": mika.current_action}
	print("[tour] cast ", tag, " ", JSON.stringify(report.tests["cast_" + tag]))


## Measure the cost of each world category by hiding it (same camera as the establishing shot).
func _perf_probe() -> void:
	main.camera_rig.set_shot(Vector3(12.5, 3.4, 14.5), Vector3(0, 1.8, -3.0), 55.0)
	await _wait(1.0)
	var base := await _measure(1.5)
	var probe := {"all": base}
	for cat in ["terrain", "architecture", "rocks", "trees", "foliage", "grass", "props"]:
		var nodes := get_tree().get_nodes_in_group("cat_" + cat)
		for n in nodes: n.visible = false
		await _wait(0.4)
		var m := await _measure(1.2)
		probe["without_" + cat] = {"fps": m.fps, "gpu_ms": m.gpu_ms, "primitives": m.primitives, "saves_gpu_ms": snappedf(base.gpu_ms - m.gpu_ms, 0.01), "saves_prims": base.primitives - m.primitives}
		for n in nodes: n.visible = true
	var sun: DirectionalLight3D = main.world.sun
	sun.shadow_enabled = false
	await _wait(0.4)
	var ns := await _measure(1.2)
	probe["without_sun_shadows"] = {"gpu_ms": ns.gpu_ms, "primitives": ns.primitives, "saves_gpu_ms": snappedf(base.gpu_ms - ns.gpu_ms, 0.01)}
	sun.shadow_enabled = true
	var env: Environment = main.world.env
	for fx in ["ssr_enabled", "ssil_enabled", "ssao_enabled", "volumetric_fog_enabled", "glow_enabled"]:
		var was = env.get(fx)
		env.set(fx, false)
		await _wait(0.4)
		var m := await _measure(1.2)
		probe["without_" + fx] = {"gpu_ms": m.gpu_ms, "saves_gpu_ms": snappedf(base.gpu_ms - m.gpu_ms, 0.01)}
		env.set(fx, was)
	get_viewport().use_taa = false
	await _wait(0.4)
	var mt := await _measure(1.2)
	probe["without_taa"] = {"gpu_ms": mt.gpu_ms, "saves_gpu_ms": snappedf(base.gpu_ms - mt.gpu_ms, 0.01)}
	get_viewport().use_taa = true
	report["perf_probe"] = probe
	for k in probe: print("[probe] ", k, " ", JSON.stringify(probe[k]))
