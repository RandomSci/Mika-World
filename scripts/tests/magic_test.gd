class_name MagicTest
extends Node
## --magictest: elemental interaction regression in the Sanctuary (rendered, with screenshots).
## Each case puts Mika at a clear casting spot, casts a real spell at a real target through
## MagicSystem, and records the full result (outcome, reaction, state before/after, mastery change),
## a screenshot just after impact, and the spell phase timeline vs. the animation clock.
## Writes <shots>/magictest/magic_test_<profile>.json and quits.

var main: Node
var report := {"cases": [], "refusals": [], "phases": [], "spells_before": [], "spells_after": []}
var dir := ""
var _phase_log := []
var _cast_t0 := 0.0


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/magictest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	MagicEvents.spell_phase.connect(func(_c, sid, ph, el, _p): _phase_log.append({"spell": sid, "phase": ph, "element": el, "t": snappedf(Time.get_ticks_msec() / 1000.0 - _cast_t0, 0.001)}))
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> String:
	var path := "%s/%s_%s.png" % [dir, RenderProfile.profile.to_lower(), tag]
	get_viewport().get_texture().get_image().save_png(path)
	return path


## Stand about `dist` metres from the target on the navmesh with a clear, castable line to it
## (preferring the side toward `toward`), facing it. Mirrors what a player or the brain would choose.
func _stand_near(target: ReactiveElement, dist: float, toward := Vector3.ZERO, spell := "arcane_orb") -> void:
	var m: WorldCharacter = main.characters["mika"]
	var tp := target.aim_point()
	var pref := Vector3(toward.x - tp.x, 0, toward.z - tp.z)
	var base_ang := atan2(pref.x, pref.z) if pref.length() > 0.1 else 0.0
	var map := m.get_world_3d().navigation_map
	var chosen = null
	for ring in [dist, dist * 0.8, dist * 1.2, dist * 0.65]:
		for k in 16:
			var ang: float = base_ang + (k / 2) * 0.4 * (1.0 if k % 2 == 0 else -1.0)
			var want: Vector3 = tp + Vector3(sin(ang), 0, cos(ang)) * float(ring)
			var p := NavigationServer3D.map_get_closest_point(map, want)
			if p.distance_to(Vector3(want.x, p.y, want.z)) > 0.6:
				continue
			m.global_position = p + Vector3(0, 0.05, 0)
			var d0 := Vector3(tp.x - p.x, 0, tp.z - p.z)
			m.rotation.y = atan2(-d0.x, -d0.z)
			await get_tree().physics_frame
			if main.magic.validate(spell, m, target).ok and main.world.has_space_for_magic(p):
				chosen = p
				break
		if chosen != null:
			break
	if chosen == null:
		chosen = NavigationServer3D.map_get_closest_point(map, tp + Vector3(sin(base_ang), 0, cos(base_ang)) * dist)
	m.velocity = Vector3.ZERO
	m.global_position = chosen + Vector3(0, 0.1, 0)
	var d := Vector3(tp.x - chosen.x, 0, tp.z - chosen.z)
	m.rotation.y = atan2(-d.x, -d.z)
	await _wait(0.6)


func _frame(target: ReactiveElement) -> void:
	var m: WorldCharacter = main.characters["mika"]
	var tp := target.aim_point()
	var mp := m.global_position
	var side := (tp - mp).cross(Vector3.UP).normalized()
	var mid := (tp + mp) * 0.5
	main.camera_rig.set_shot(mid + side * (2.5 + mp.distance_to(tp) * 0.55) + Vector3(0, 1.6, 0) - (tp - mp).normalized() * 1.0, mid + Vector3(0, 1.0, 0), 55.0)


func _case(tag: String, spell: String, target_id: String, mastery = null, toward := Vector3.ZERO, dist := 5.0) -> Dictionary:
	var m: WorldCharacter = main.characters["mika"]
	var magic: MagicSystem = main.magic
	var target: ReactiveElement = magic.reactives().get(target_id)
	if mastery != null:
		WorldState.skills[spell] = float(mastery)
	if target:
		await _stand_near(target, dist, toward, spell)
		_frame(target)
	# same-camera baseline just before the cast (isolates the spell's own cost from the scene's)
	await _wait(0.5)
	var vpb := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vpb, true)
	var bf := 0
	var bg := 0.0
	var bt0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - bt0 < 1000:
		await get_tree().process_frame
		bf += 1
		bg += RenderingServer.viewport_get_measured_render_time_gpu(vpb)
	var baseline := {"fps": snappedf(bf / 1.0, 0.1), "gpu_ms": snappedf(bg / maxi(bf, 1), 0.01)}
	_phase_log.clear()
	_cast_t0 = Time.get_ticks_msec() / 1000.0
	var shot_path := [""]
	var watcher := func(_c, _sid, ph, _el, _p):
		if ph in ["impact", "blocked", "missed"] and shot_path[0] == "":
			shot_path[0] = "pending"
	MagicEvents.spell_phase.connect(watcher)
	var job := [null]
	var runner := func(): job[0] = await magic.cast(m, spell, target_id)
	runner.call()
	var t0 := Time.get_ticks_msec()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var frames := 0
	var gpu := 0.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var skip := false
	var cpu_r := 0.0
	var proc := 0.0
	var phys := 0.0
	var frame_times := []
	var shot_us := 0
	var last_raw := Time.get_ticks_usec()
	while job[0] == null and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if not skip:
			worst = maxf(worst, (now - last) / 1000.0)
		skip = false
		last = now
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu_r += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		frame_times.append(snappedf((now - last_raw) / 1000.0, 0.1))
		last_raw = now
		if shot_path[0] == "pending":
			await _wait(0.35)
			var s0 := Time.get_ticks_usec()
			shot_path[0] = _shot(tag)
			shot_us += Time.get_ticks_usec() - s0
			skip = true
			last = Time.get_ticks_usec()
			last_raw = last
	MagicEvents.spell_phase.disconnect(watcher)
	var r: Dictionary = job[0] if job[0] != null else {"ok": false, "outcome": "timeout"}
	if shot_path[0] == "" or shot_path[0] == "pending":
		shot_path[0] = _shot(tag)
	r["shot"] = shot_path[0]
	var el := (Time.get_ticks_msec() - t0) / 1000.0 - shot_us / 1e6  # the screenshot readback is not gameplay time
	r["perf_baseline"] = baseline
	r["perf"] = {"fps": snappedf(frames / maxf(el, 0.01), 0.1), "gpu_ms": snappedf(gpu / maxi(frames, 1), 0.01), "worst_frame_ms": snappedf(worst, 0.01),
		"render_cpu_ms": snappedf(cpu_r / maxi(frames, 1), 0.01), "process_ms": snappedf(proc / maxi(frames, 1), 0.01), "physics_ms": snappedf(phys / maxi(frames, 1), 0.01)}
	r["frame_times_ms"] = frame_times
	r["tag"] = tag
	r["phases"] = _phase_log.duplicate()
	report.cases.append(r)
	print("[magictest] %s %s -> %s %s %s" % [tag, spell, r.get("outcome", "?"), r.get("effect", ""), str(r.get("reason", r.get("detail", ""))).left(90)])
	main.camera_rig.clear_shot()
	await _wait(0.8)
	return r


func _run() -> void:
	var m: WorldCharacter = main.characters["mika"]
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	await _wait(3.0)
	var magic: MagicSystem = main.magic
	report.spells_before = magic.known_spells()
	# unknown spell is refused before its incantation is learned
	var rf: Dictionary = await magic.cast(m, "wind_gust", "brazier_se")
	report.refusals.append({"case": "unlearned wind_gust", "result": rf})
	# the reading system grants these; here the test grants them directly to exercise casting
	for k in ["incantation:wind_gust", "incantation:water_ripple", "incantation:ember_control", "incantation:rune_activation", "incantation:elemental_charge"]:
		WorldState.knowledge[k] = 1
	var dais_out := Vector3(0, 0, 12)
	if String(RenderProfile.options.get("magictest", "")) == "quick":
		await _case("wind_weak_brazier", "wind_gust", "brazier_se", 0.0, dais_out)
		await _case("arcane_orb_brazier", "arcane_orb", "brazier_nw", null, Vector3(-12, 0, -2))
		var fq := FileAccess.open("%s/magic_quick.json" % dir, FileAccess.WRITE)
		fq.store_string(JSON.stringify(report, "  "))
		fq.close()
		get_tree().quit()
		return
	# braziers: wind weak -> flicker, then strong -> extinguished; fire relights; water steam; arcane recolour
	await _case("wind_weak_brazier", "wind_gust", "brazier_se", 0.0, dais_out)
	await _case("wind_strong_brazier", "wind_gust", "brazier_se", 1.2, dais_out)
	await _wait(1.5)
	await _case("ember_relight_brazier", "ember_control", "brazier_se", 0.5, dais_out)
	await _case("water_steam_brazier", "water_ripple", "brazier_sw", 0.3, Vector3(-12, 0, 8))
	await _case("arcane_orb_brazier", "arcane_orb", "brazier_nw", null, Vector3(-12, 0, -2))
	await _case("ember_flare_brazier", "ember_control", "brazier_ne", 0.6, Vector3(10, 0, -2))
	# pond
	await _case("water_surge_pond", "water_ripple", "pond", 1.0, Vector3(9, 0, 13), 5.5)
	await _case("wind_ruffle_pond", "wind_gust", "pond", 0.5, Vector3(9, 0, 13), 5.5)
	await _case("arcane_ring_pond", "arcane_orb", "pond", null, Vector3(9, 0, 13), 5.5)
	# training grounds
	await _case("orb_rune_target", "arcane_orb", "rune_target_2", null, SanctuaryTerrain.TRAINING_CENTER_3D, 4.5)
	await _case("wind_dummy", "wind_gust", "practice_dummy", 0.8, SanctuaryTerrain.TRAINING_CENTER_3D, 4.5)
	await _case("ember_dummy", "ember_control", "practice_dummy", 0.6, SanctuaryTerrain.TRAINING_CENTER_3D, 4.5)
	await _case("water_crystal_weak", "water_ripple", "practice_crystal", 0.0, SanctuaryTerrain.TRAINING_CENTER_3D, 4.5)
	await _case("orb_crystal_shatter", "arcane_orb", "practice_crystal", null, SanctuaryTerrain.TRAINING_CENTER_3D, 4.5)
	# story clue: rune activation reveals the marked stone; incompatible target refused
	await _case("rune_marked_stone", "rune_activation", "marked_stone", 0.2, Vector3(-4.0, 0, -21.5), 3.2)
	var inc: Dictionary = await magic.cast(m, "rune_activation", "brazier_ne")
	report.refusals.append({"case": "rune_activation on a brazier", "result": inc})
	# out of range / no line of sight
	await _stand_near(magic.reactives().practice_crystal, 3.5, SanctuaryTerrain.TRAINING_CENTER_3D)
	var far: Dictionary = await magic.cast(m, "rune_activation", "marked_stone")
	report.refusals.append({"case": "marked stone from the training grounds", "result": far})
	m.global_position = Vector3(-13.0, 0.2, -17.5)
	await _wait(0.5)
	var los: Dictionary = await magic.cast(m, "arcane_orb", "heartstone")
	report.refusals.append({"case": "heartstone from outside the chamber wall", "result": los})
	# elemental charge (self) then a charged cast
	m.global_position = Vector3(0, Sanctuary.DAIS_TOP + 0.1, 1.5)
	await _wait(0.5)
	await _case("elemental_charge", "elemental_charge", "", 0.3)
	await _case("charged_wind_brazier", "wind_gust", "brazier_ne", 0.3, Vector3(10, 0, -2))
	# heartstone resonance (inside the chamber)
	await _case("orb_heartstone", "arcane_orb", "heartstone", null, Vector3(-16.0, 0, -21.0), 4.0)
	# reversibility: wait for the extinguished brazier to relight on its own
	var br: Brazier = magic.reactives().brazier_ne
	report["brazier_ne_state_now"] = br.state.duplicate()
	report.spells_after = magic.known_spells()
	report["recent_magic_events"] = MagicEvents.recent.duplicate()
	var f := FileAccess.open("%s/magic_test_%s.json" % [dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[magictest] done")
	get_tree().quit()
