class_name BrainRun
extends Node
## --brainrun[=seconds]: Mika decides everything herself (planner + director + visitors), for a long time.
## Records the decision log, activity kinds and durations, repetition statistics, story progress,
## conversations, journal entries, curiosity proposals, FPS samples and a screenshot every minute.

var main: Node
var report := {"samples": []}
var dir := ""


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/brainrun"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _run() -> void:
	var secs := float(RenderProfile.options.get("brainrun", "1500"))
	if secs <= 1.0:
		secs = 1500.0
	main.hud.visible = false
	await get_tree().create_timer(4.0).timeout
	main.set_brain(true)
	var t0 := Time.get_ticks_msec()
	var next_shot := 20.0
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var frames := 0
	var gpu := 0.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var k := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < secs:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		var el := (Time.get_ticks_msec() - t0) / 1000.0
		if el >= next_shot:
			next_shot += 60.0
			var s0 := Time.get_ticks_usec()
			get_viewport().get_texture().get_image().save_png("%s/%s_%02d.png" % [dir, RenderProfile.profile.to_lower(), k])
			var shot_ms := (Time.get_ticks_usec() - s0) / 1000.0
			report.samples.append({"t": snappedf(el, 0.1), "fps": snappedf(frames / 60.0 if k > 0 else frames / 20.0, 0.1), "gpu_ms": snappedf(gpu / maxi(frames, 1), 0.01),
				"worst_frame_ms": snappedf(worst, 0.1), "activity": main.brain.current.duplicate(), "camera": main.director.mode,
				"area": main.streaming.current_id, "story_stage": main.story.stage, "visitors": main.npcs.present.keys(), "screenshot_ms": snappedf(shot_ms, 0.1)})
			print("[brainrun] %.0fs %s | %s | stage %s | fps %.1f" % [el, main.brain.current.get("label", "-"), main.director.mode, main.story.stage, frames / (60.0 if k > 0 else 20.0)])
			frames = 0
			gpu = 0.0
			worst = 0.0
			last = Time.get_ticks_usec()
			k += 1
	main.set_brain(false)
	var h: Array = main.brain.history
	var kinds := {}
	var labels := {}
	var max_same_kind := 0
	var run_len := 0
	var prev := ""
	for e in h:
		kinds[e.kind] = kinds.get(e.kind, 0) + 1
		labels[e.label] = labels.get(e.label, 0) + 1
		run_len = run_len + 1 if e.kind == prev else 1
		prev = e.kind
		max_same_kind = maxi(max_same_kind, run_len)
	var max_label := 0
	for l in labels:
		max_label = maxi(max_label, labels[l])
	report["decisions"] = h
	report["stats"] = {"activities": h.size(), "kinds": kinds, "distinct_labels": labels.size(), "max_consecutive_same_kind": max_same_kind,
		"most_repeated_label_count": max_label, "ok_rate": snappedf(float(h.filter(func(e): return e.ok).size()) / maxi(h.size(), 1), 0.01),
		"durations_s": h.map(func(e): return e.seconds)}
	report["story"] = main.story.describe()
	report["mission"] = WorldState.mission_state()
	report["journal"] = WorldState.knowledge.get("journal", [])
	report["npcs"] = WorldState.npc_state.duplicate(true)
	report["npc_manager"] = main.npcs.describe()
	report["curiosity"] = main.curiosity.log.duplicate()
	report["voice"] = main.voice.log.map(func(v): return {"speaker": v.speaker, "text": v.text, "audio": v.audio})
	report["skills"] = WorldState.skills.duplicate()
	report["inventory"] = WorldState.inventory.duplicate()
	# Milestone H: every mage's own record (decisions, level, inventory) + creatures, talks, transformations
	var mages := {}
	for who in main.mage_brains:
		var bh: Array = main.mage_brains[who].history
		var kinds2 := {}
		for e in bh:
			kinds2[e.kind] = kinds2.get(e.kind, 0) + 1
		var mm := WorldState.mind(who)
		mages[who] = {"activities": bh.size(), "kinds": kinds2, "ok_rate": snappedf(float(bh.filter(func(e): return e.ok).size()) / maxi(bh.size(), 1), 0.01),
			"progress": Progression.describe(who), "inventory": mm.inventory.duplicate(), "skills": mm.skills.duplicate(),
			"knowledge_count": mm.knowledge.size(), "vigor": snappedf(mm.vigor, 0.01), "decisions": bh}
	report["mages"] = mages
	report["creatures"] = main.spawner.log.duplicate() if main.spawner else []
	report["talks"] = main.mage_talk.log.duplicate() if main.mage_talk else []
	report["transformations"] = main.transformer.log.duplicate() if main.transformer else []
	report["fusions"] = main.magic.fusion.log.duplicate() if main.magic.fusion else []
	report["xp_events"] = main.progression.recent.duplicate() if main.progression else []
	report["script_note"] = "decisions/history above (report.decisions) are Mika's for backward compatibility"
	var f := FileAccess.open("%s/brain_run_%s.json" % [dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[brainrun] done")
	get_tree().quit()
