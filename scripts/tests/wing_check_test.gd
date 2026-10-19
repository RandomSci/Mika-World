extends Node
## --wingcheck=<dir>: a winged form's wings against her design sheet. --outfit-who / --outfit-stage pick the look.
##  1. stills: front, back, side (her left), three-quarter back; idle wings (wide camera, face < 10 % of the frame)
##  2. a short motion test (record with --write-movie): idle flap, take off and hover (wingbeats), land, sit (fold),
##     stand, weapon drawn (spread), sheathe
## Writes <dir>/<tag>_<view>.png and <dir>/<tag>_wingcheck.json (phase frames). Changes no progress.

var main: Node
var m: WorldCharacter
var dir := ""
var tag := ""
var rep := {"phases": {}}
var _follow := false
var _cam_off := Vector3.ZERO
var _cam_look_y := 1.0


func _ready() -> void:
	dir = String(RenderProfile.options.get("wingcheck", "user://wingcheck"))
	DirAccess.make_dir_recursive_absolute(dir)
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _phase(n: String) -> void:
	rep.phases[n] = Engine.get_process_frames()
	print("[wingcheck] phase %s frame %d" % [n, Engine.get_process_frames()])


func _process(_d: float) -> void:
	if _follow and m:
		var c := m.global_position + Vector3(0, _cam_look_y, 0)
		(main.camera_rig as ThirdPersonCamera).set_shot(c + _cam_off, c, 42.0)


func _shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, tag, name])


## Tip-to-tip span right now (the hand tips), metres.
func _span() -> float:
	var sk := m.skeleton
	await sk.skeleton_updated            # the wings' pose exists only inside the modifier pass
	var a := sk.find_bone("J_Sec_WingL_HandTip")
	var b := sk.find_bone("J_Sec_WingR_HandTip")
	if a < 0 or b < 0:
		return -1.0
	return snappedf(sk.get_bone_global_pose(a).origin.distance_to(sk.get_bone_global_pose(b).origin), 0.01)


func _run() -> void:
	var who := String(RenderProfile.options.get("outfit-who", "mika"))
	m = main.characters[who]
	main.player.enabled = false
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
	for k in ["brain", "duel", "companionship", "attention", "impacts", "mage_talk", "performance", "director"]:
		var n: Node = main.get(k)
		if n:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var spot: Vector3 = (main.characters.mika as WorldCharacter).global_position
	for w in main.characters:
		if w != who:
			var o: WorldCharacter = main.characters[w]
			o.global_position = spot + Vector3(40, 0, 40)
			o.visible = false
			o.process_mode = Node.PROCESS_MODE_DISABLED
	var want := String(RenderProfile.options.get("outfit-stage", ""))
	if want != "":
		AppearanceRegistry.preview(who, want)
		m.swap_avatar(AppearanceRegistry.avatar_for(who))
	m.global_position = spot
	tag = "%s_%s" % [who, String(AppearanceRegistry.stage_for_avatar(who, m.avatar_path).get("id", "base"))]
	m.set("_glance_t", 1e9)
	await _wait(1.0)
	# face her where every camera position (front, back, sides, at 4.5 m) has a clear line to her
	var space := m.get_world_3d().direct_space_state
	var best_yaw := m.rotation.y
	var best_free := -1
	for k in 24:
		var yaw := k * TAU / 24.0
		var f2 := Vector3(-sin(yaw), 0, -cos(yaw))
		var r2 := f2.cross(Vector3.UP)
		var free := 0
		for d in [f2, -f2, -r2, (-f2 - r2 * 0.8).normalized(), (-f2 - r2 * 0.7).normalized()]:
			var clear := true
			var ball := SphereShape3D.new()
			ball.radius = 0.35
			for h in [0.4, 1.0, 1.6]:
				var sq := PhysicsShapeQueryParameters3D.new()
				sq.shape = ball
				sq.exclude = [m.get_rid()]
				var dd: Vector3 = d
				var from: Vector3 = m.global_position + Vector3(0, h, 0) + dd * 1.1
				sq.transform = Transform3D(Basis.IDENTITY, from)
				sq.motion = dd * 4.2
				if space.cast_motion(sq)[0] < 1.0:
					clear = false
			if clear:
				free += 1
		if free > best_free:
			best_free = free
			best_yaw = yaw
	m.rotation.y = best_yaw
	rep["clear_views"] = best_free
	await _wait(2.0)
	var fwd := -m.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()     # her right
	var rig: ThirdPersonCamera = main.camera_rig
	var wl: WingLayer = m.wing_layer
	var views := {"front": fwd, "back": -fwd, "side": -right}
	# 1. stills: rest (the sheet), spread, fold - front / back / side. 6.5 m at 42 deg: 5 m tall frame, face ~5 %
	for pose in ["sheet", "open", "fold"]:
		wl.override = pose
		await _wait(2.2)
		rep["span_" + pose] = await _span()
		for v in views:
			var c := m.global_position + Vector3(0, 1.1, 0)
			rig.set_shot(c + views[v] * 6.5 + Vector3(0, 0.2, 0), c, 42.0)
			await _wait(0.4)
			await _shot("%s_%s" % [pose, v])
	if wl.rig.is_empty():
		rep["rig"] = "legacy (no full wing rig)"
	# 2. in the air: the flap from the front, the back and the side - deep beats, hover beats, glide
	wl.override = "open"
	_cam_look_y = 1.0
	if m.flight:
		_phase("take_off")
		await m.flight.take_off(2.4)
	for v in views:
		_cam_off = views[v] * 6.5 + Vector3(0, 0.3, 0)
		_follow = true
		_phase("flap_" + v)
		wl.override = "flap"
		await _wait(3.4)
		_phase("hover_" + v)
		wl.override = "hover"
		await _wait(2.4)
		_phase("glide_" + v)
		wl.override = "glide"
		await _wait(1.8)
	# 3. slow motion (a quarter speed): two deep beats from behind and from the side
	for v in ["back", "side"]:
		_cam_off = views[v] * 6.0 + Vector3(0, 0.3, 0)
		wl.override = "flap"
		await _wait(0.8)
		_phase("slowmo_" + v)
		Engine.time_scale = 0.25
		await _wait(1.6)
		Engine.time_scale = 1.0
	# 4. landing: the real thing - she settles down and tucks her wings behind her back
	wl.override = ""
	_cam_off = (-fwd - right * 0.7).normalized() * 5.5 + Vector3(0, 0.3, 0)
	if m.flight:
		_phase("land")
		await m.flight.land()
	_phase("landed_fold")
	await _wait(3.0)
	_phase("end")
	_follow = false
	await _wait(0.5)
	rep["span_m"] = await _span()
	var f := FileAccess.open("%s/%s_wingcheck.json" % [dir, tag], FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	print("[wingcheck] done ", tag)
	get_tree().quit()
