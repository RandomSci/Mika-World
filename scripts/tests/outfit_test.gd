class_name OutfitTest
extends Node
## --outfittest: appearance-stage QA for a new look (--outfit-who=mika|luna, default mika; the stage her level picks; --outfit-stage=<id>
## previews another one, e.g. the archived look for a baseline). Rendered, with Luna in the scene (--luna).
##  * idle / walk / sit / cast, each from the front, back and side (+ face close-ups with expressions, blink and the
##    lip-sync mouth) -> <shots>/outfittest/<tag>_<state>_<view>.png
##  * at every capture the skeleton deformation (global pose x global rest^-1 per bone, skeleton space) is written
##    so the clip check can skin the exact runtime pose (springs included) offline -> <tag>_poses.json
##  * spring settling: per chain-tip jitter (std of its position relative to the hips) while she stands still
##  * cost: triangles of each mage's meshes, draw calls / primitives in frame, video / texture / buffer memory,
##    frame rate over a fixed window with Mika and Luna both framed -> <tag>_report.json
## Changes no progress (test flags make the world non-persistent).

var main: Node
var dir := ""
var tag := "outfit"
var report := {}
var poses := {}


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/outfittest"
	tag = String(RenderProfile.options.get("outfittag", "outfit"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> String:
	await _frames(2)
	var path := "%s/%s_%s.png" % [dir, tag, name]
	get_viewport().get_texture().get_image().save_png(path)
	return path


func _bone(m: WorldCharacter, b: String) -> Vector3:
	var sk := m.skeleton
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin


## The FINAL pose (after the spring bones and the other SkeletonModifier3Ds): read inside skeleton_updated - outside of
## it the skeleton holds the animation pose only.
func _dump_pose(m: WorldCharacter, name: String) -> void:
	var sk := m.skeleton
	await sk.skeleton_updated
	var d := {}
	for i in sk.get_bone_count():
		var D: Transform3D = sk.get_bone_global_pose(i) * sk.get_bone_global_rest(i).affine_inverse()
		var b := D.basis
		d[sk.get_bone_name(i)] = [b.x.x, b.y.x, b.z.x, D.origin.x, b.x.y, b.y.y, b.z.y, D.origin.y, b.x.z, b.y.z, b.z.z, D.origin.z]
	poses[name] = d


## Camera around her: front / back / side (her right) / three-quarter, framed on the body.
func _views(m: WorldCharacter, state: String, height := 0.95, dist := 3.1, views := ["front", "back", "side"]) -> void:
	var rig: ThirdPersonCamera = main.camera_rig
	var fwd := -m.global_transform.basis.z          # she faces -Z of her body (as in the pose test)
	fwd.y = 0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var c := m.global_position + Vector3(0, height, 0)
	var dirs := {"front": fwd, "back": -fwd, "side": right, "side_l": -right, "front34": (fwd + right * 0.8).normalized()}
	await _dump_pose(m, state)
	for v in views:
		c = m.global_position + Vector3(0, height, 0)       # she may be running: frame where she is now
		rig.set_shot(c + dirs[v] * dist + Vector3(0, 0.15, 0), c, 38.0)
		report.get_or_add("shots", []).append(await _shot("%s_%s" % [state, v]))


func _tris(c: WorldCharacter) -> Dictionary:
	var t := 0
	var meshes := {}
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var n := 0
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			n += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		meshes[String(m.name)] = n
		t += n
	return {"total": t, "meshes": meshes}


## Hair through her shoulders / arms: every hair joint (J_Sec_Hair*, not the ribbons) against capsules of her real
## shoulders (collarbone to arm joint, 5.5 cm) and upper arms (4.5 cm), every frame for `seconds`. A strand is
## ~1.5 cm thick, so a joint closer than radius + 1.5 cm means hair inside her. -> {frames, frames_inside_pct, max_cm, worst_joint}
func _hair_clip(m: WorldCharacter, seconds: float) -> Dictionary:
	var sk := m.skeleton
	var hair := []
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		if nm.begins_with("J_Sec_Hair") and not nm.contains("Ribbon"):
			hair.append(i)
	var segs := []
	for side in ["Left", "Right"]:
		var sh := sk.find_bone(side + "Shoulder")
		var ua := sk.find_bone(side + "UpperArm")
		var la := sk.find_bone(side + "LowerArm")
		if sh >= 0 and ua >= 0:
			segs.append([sh, ua, 0.055])
		if ua >= 0 and la >= 0:
			segs.append([ua, la, 0.045])
	var frames := 0
	var inside := 0
	var worst := 0.0
	var worst_nm := ""
	var t0 := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) / 1e6 < seconds:
		await sk.skeleton_updated
		frames += 1
		var any := false
		for s in segs:
			var a := sk.get_bone_global_pose(s[0]).origin
			var b := sk.get_bone_global_pose(s[1]).origin
			for j in hair:
				var p := sk.get_bone_global_pose(j).origin
				var d := p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))
				var depth := float(s[2]) + 0.015 - d
				if depth > 0.0:
					any = true
					if depth > worst:
						worst = depth
						worst_nm = sk.get_bone_name(j)
		if any:
			inside += 1
	return {"frames": frames, "frames_inside_pct": snappedf(100.0 * inside / maxf(frames, 1), 0.1), "max_cm": snappedf(worst * 100.0, 0.1), "worst_joint": worst_nm}


func _jitter(m: WorldCharacter, seconds: float) -> Dictionary:
	var sk := m.skeleton
	var tips := []
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		if nm.begins_with("J_Sec_") and sk.get_bone_children(i).is_empty():
			tips.append(i)
	var hips := sk.find_bone("Hips")
	var samples := {}
	var t := 0.0
	var t0 := Time.get_ticks_usec()
	while t < seconds:
		await sk.skeleton_updated                    # final pose, springs included
		t = (Time.get_ticks_usec() - t0) / 1e6
		var hp := sk.get_bone_global_pose(hips)
		for i in tips:
			var p := hp.affine_inverse() * sk.get_bone_global_pose(i).origin
			samples.get_or_add(i, []).append(p)
	var out := {}
	var hfo := {}
	var spk := {}
	var worst := 0.0
	var worst_hf := 0.0
	for i in tips:
		var arr: Array = samples[i]
		var mean := Vector3.ZERO
		for p in arr: mean += p
		mean /= arr.size()
		var v := 0.0
		for p in arr: v += (p - mean).length_squared()
		var sd := sqrt(v / arr.size())
		var hf := 0.0
		for k in range(1, arr.size() - 1):
			hf += (arr[k + 1] - arr[k] * 2.0 + arr[k - 1]).length_squared()
		var spikes := 0
		for k in range(1, arr.size() - 1):
			if (arr[k + 1] - arr[k] * 2.0 + arr[k - 1]).length() > 0.002:
				spikes += 1
		hf = sqrt(hf / maxf(arr.size() - 2, 1))
		var chain := sk.get_bone_name(i).trim_prefix("J_Sec_").rstrip("0123456789").trim_suffix("_")
		out[chain] = maxf(float(out.get(chain, 0.0)), snappedf(sd * 1000.0, 0.01))
		hfo[chain] = maxf(float(hfo.get(chain, 0.0)), snappedf(hf * 1000.0, 0.001))
		spk[chain] = maxi(int(spk.get(chain, 0)), spikes)
		worst = maxf(worst, sd)
		worst_hf = maxf(worst_hf, hf)
	return {"tip_std_mm_by_chain": out, "worst_tip_std_mm": snappedf(worst * 1000.0, 0.01),
		"tip_hf_mm_per_frame2_by_chain": hfo, "frames_over_2mm_by_chain": spk, "frames": samples[tips[0]].size() if tips.size() > 0 else 0, "worst_tip_hf_mm": snappedf(worst_hf * 1000.0, 0.001), "tips": tips.size(), "seconds": seconds}


func _open_direction(m: WorldCharacter, dist: float) -> Vector3:
	var space := m.get_world_3d().direct_space_state
	var best := -m.global_transform.basis.z
	var best_d := -1.0
	for k in 16:
		var a := k * TAU / 16.0
		var d := Vector3(sin(a), 0, cos(a))
		var free := dist
		for h in [0.5, 1.2]:
			var q := PhysicsRayQueryParameters3D.create(m.global_position + Vector3(0, h, 0), m.global_position + Vector3(0, h, 0) + d * dist)
			q.exclude = [m.get_rid()]
			var r := space.intersect_ray(q)
			if not r.is_empty():
				free = minf(free, (r.position - q.from).length())
		if free > best_d:
			best_d = free
			best = d
	return best


func _perf(seconds: float) -> Dictionary:
	var fps := []
	var t := 0.0
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var dts: Array[float] = []
	while t < seconds:
		await get_tree().process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		dts.append((now - last) / 1000.0)
		last = now
		t = (now - t0) / 1e6
	var sorted_dts := dts.duplicate()
	sorted_dts.sort()
	var slow := dts.filter(func(d): return d > 50.0)
	var rs := RenderingServer
	return {
		"avg_fps": snappedf(frames / t, 0.01), "engine_fps": Engine.get_frames_per_second(), "max_fps_cap": Engine.max_fps,
		"primitives_in_frame": rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"draw_calls_in_frame": rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_mem_mb": snappedf(rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(rs.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(rs.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"window_s": snappedf(t, 0.01), "frames": frames,
		"frame_ms_p50": snappedf(sorted_dts[sorted_dts.size() / 2], 0.1), "frame_ms_p99": snappedf(sorted_dts[int(sorted_dts.size() * 0.99)], 0.1),
		"frame_ms_max": snappedf(sorted_dts[-1], 0.1), "frames_over_50ms": slow.size(),
		"stall_at_s": snappedf(dts.slice(0, dts.find(sorted_dts[-1])).reduce(func(a, b): return a + b, 0.0) / 1000.0, 0.01)}


func _run() -> void:
	var who := String(RenderProfile.options.get("outfit-who", "mika"))       # the mage whose look is tested
	var other_id := "luna" if who == "mika" else "mika"
	var m: WorldCharacter = main.characters[who]
	var luna: WorldCharacter = main.characters.get(other_id)                  # the other mage, framed for the cost check
	main.player.enabled = false
	# both mages' own minds paused (a mage walking off or casting mid-measurement is not her clothes misbehaving)
	for w in main.mage_brains:
		main.mage_brains[w].hold = true
	for w in main.mage_brains:
		var t0 := Time.get_ticks_msec()
		while not main.mage_brains[w].current.is_empty() and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().process_frame
	main.hud.visible = false
	main.prompt.visible = false
	if main.get("overlay_ui"):
		main.overlay_ui.visible = false
	var want := String(RenderProfile.options.get("outfit-stage", ""))
	if want != "":
		AppearanceRegistry.preview(who, want)
		m.swap_avatar(AppearanceRegistry.avatar_for(who))
	await _wait(3.0)
	var st := AppearanceRegistry.stage_for_avatar(who, m.avatar_path)
	report["who"] = who
	report["stage"] = st.get("id", "")
	report["avatar"] = m.avatar_path
	report["face_bound_shapes"] = m.face.bound_count() if m.face else -1
	report["profile"] = RenderProfile.profile
	for k in ["brain", "duel", "companionship", "attention", "impacts", "mage_talk", "performance"]:      # nobody else drives the mages during the test
		var n: Node = main.get(k)
		if n:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var rig: ThirdPersonCamera = main.camera_rig
	# a clear standing spot: where she spawned, facing the open side; Luna beside her
	var home := m.global_position
	if luna:
		luna.global_position = home + m.global_transform.basis.x * 1.6
		luna.rotation.y = m.rotation.y
	await _wait(2.5)

	# ---- cost first (Mika + Luna framed, nothing else changing)
	report["tris_" + who] = _tris(m)
	if luna:
		report["tris_" + other_id] = _tris(luna)
	var mid := home + m.global_transform.basis.x * 0.8 + Vector3(0, 1.0, 0)
	rig.set_shot(mid - m.global_transform.basis.z * 4.2 + Vector3(0, 0.3, 0), mid, 45.0)
	await _wait(float(RenderProfile.options.get("outfit-warmup-s", "2")))
	report["perf_mika_and_luna"] = await _perf(float(RenderProfile.options.get("outfit-perf-s", "10")))
	print("[outfittest] perf ", JSON.stringify(report["perf_mika_and_luna"]))
	if RenderProfile.options.has("outfit-perf-only"):
		var fp := FileAccess.open("%s/%s_report.json" % [dir, tag], FileAccess.WRITE)
		fp.store_string(JSON.stringify(report, "  "))
		fp.close()
		get_tree().quit()
		return
	if luna:
		# after the both-mages perf sample the other mage leaves every shot (she would walk over and block the camera)
		luna.global_position = home + Vector3(40, 0, 40)
		luna.visible = false
		luna.process_mode = Node.PROCESS_MODE_DISABLED

	# ---- idle: springs settle, then views, face, expressions. Her random idle glances are paused while the springs are
	# measured (a head turn swings the hair - that is motion, not jitter)
	m.set("_glance_t", 1e9)
	m.look_head_at(null)
	await _wait(4.0)
	var tc := Time.get_ticks_msec()
	while (m.casting or m.get("_action") != null and String(m.get("_action")) != "") and Time.get_ticks_msec() - tc < 15000:
		await get_tree().process_frame             # a cast (or action) she began before the pause finishes first
	await _wait(2.5)
	report["jitter_idle"] = await _jitter(m, 4.0)
	m.set("_glance_t", 4.0)
	print("[outfittest] jitter ", JSON.stringify(report["jitter_idle"]))
	if m.get("cloth_clearance"):
		print("[outfittest] hands at rest (folded in front): ", JSON.stringify(m.cloth_clearance.weight))
	await _views(m, "idle", 0.95, 3.1, ["front", "back", "side", "side_l", "front34"])
	var head := _bone(m, "Head")
	var fwd := -m.global_transform.basis.z
	for ex in [["neutral", "", 0.0], ["happy", "happy", 1.0], ["surprised", "surprised", 1.0], ["sad", "sad", 1.0], ["blink", "blink", 1.0], ["lipsync_aa", "aa", 0.9]]:
		if ex[1] != "":
			m.set_expression(ex[1], ex[2])
		var cam := head + Vector3(0, 0.05, 0) + fwd * 0.75
		m.look_head_at(cam)
		rig.set_shot(cam, head + Vector3(0, 0.02, 0), 35.0)
		await _wait(0.8)
		report.get_or_add("shots", []).append(await _shot("face_" + ex[0]))
		if ex[1] != "":
			m.set_expression(ex[1], 0.0)
	m.look_head_at(null)
	await _wait(0.5)

	# ---- walk (in a straight line; the camera rides along) and run
	for gait in [["walk", false], ["run", true]]:
		var dir3 := _open_direction(m, 9.0)
		m.rotation.y = atan2(-dir3.x, -dir3.z)
		await _wait(0.3)
		m.set_move_input(dir3, gait[1])
		await _wait(2.2)
		if gait[0] == "walk":
			report["jitter_walk"] = await _jitter(m, 2.0)
		report["hair_clip_" + gait[0]] = await _hair_clip(m, 1.5)

		print("[outfittest] hair_clip_%s %s" % [gait[0], JSON.stringify(report["hair_clip_" + gait[0]])])
		await _views(m, gait[0], 0.95, 3.4, ["front", "side", "back"])
		m.set_move_input(Vector3.ZERO, false)
		if gait[0] == "walk":
			m.set("_glance_t", 1e9)
			await _wait(2.0)
			report["settle_after_walk"] = await _jitter(m, 2.0)     # 2-4 s after stopping: should be calm
			m.set("_glance_t", 4.0)
		await _wait(1.2)
		m.global_position = home
		await _wait(1.0)

	# ---- cast (a real casting clip, captured mid-gesture)
	for clip in ["spell_casting", "wide_arm_spell"]:
		if m.play_gesture(clip, 0.25, 0.4):
			await _wait(1.3)
			await _views(m, "cast_" + clip, 0.95, 3.1, ["front", "side", "back"])
			await _wait(2.5)

	# ---- head turns (the hair and collar against the shoulders)
	m.global_position = home
	await _wait(0.8)
	var hfwd := -m.global_transform.basis.z
	var hright := hfwd.cross(Vector3.UP).normalized()
	for side in [["head_turn_r", 1.0], ["head_turn_l", -1.0]]:
		m.look_head_at(_bone(m, "Head") + hright * 2.0 * float(side[1]) + hfwd * 0.4)
		await _wait(1.0)
		await _views(m, side[0], 1.1, 2.6, ["front", "side"])
	m.look_head_at(null)
	await _wait(0.6)

	# ---- weapon: draw, attack mid-swing, sheathe (the look's weapon, or the default magic blade)
	if m.sword and m.sword.available:
		await m.sword.draw()
		await _wait(1.0)
		await _views(m, "weapon_drawn", 0.95, 3.1, ["front"])
		m.sword.attack()
		await _wait(0.55)
		await _views(m, "attack", 0.95, 3.1, ["front", "side", "back"])
		await _wait(1.5)
		m.sword.sheathe()
		await _wait(1.0)
	else:
		report["weapon"] = "no weapon layer on this character"

	# ---- taking a heavy hit from the front
	var hf := -m.global_transform.basis.z
	m.take_hit(m.global_position + hf * 2.0 + Vector3(0, 1.2, 0), true)
	await _wait(0.35)
	await _views(m, "hit", 0.95, 3.1, ["front", "side", "back"])
	await _wait(2.5)

	# ---- sit on the garden Still Stone (the interaction the game uses)
	var it: Interactable = main.world.interactables.get("garden_meditate") if "interactables" in main.world else null
	if it:
		m.global_position = it.approach_point() + Vector3(0, 0.1, 0) + (it.approach_point() - it.global_position).normalized() * 0.8
		await _wait(0.5)
		it.duration_override = 30.0                     # stay seated through the views and the settle measurement
		var job := func(): await it.perform(m)
		job.call()
		await _wait(0.6 + 0.35 + 3.0)
		await _views(m, "sit", 0.65, 2.6, ["front", "side", "back", "front34"])
		m.set("_glance_t", 1e9)
		report["sit_jitter"] = await _jitter(m, 2.0)
		await _wait(3.0)
		report["sit_jitter_settled"] = await _jitter(m, 3.0)      # 5-8 s after the views: has the hair come to rest?
	else:
		report["sit"] = "garden_meditate not loaded"

	rig.clear_shot()
	var f := FileAccess.open("%s/%s_report.json" % [dir, tag], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	var g := FileAccess.open("%s/%s_poses.json" % [dir, tag], FileAccess.WRITE)
	g.store_string(JSON.stringify(poses))
	g.close()
	print("[outfittest] done ", tag)
	get_tree().quit()
