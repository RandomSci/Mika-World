extends Node
## --qareel=<who> [--qa-stage=<stage id>]: the look-quality reel, recorded with Movie Maker (--write-movie <file>.avi
## --fixed-fps 30). Every action from several sides with a caption naming it, so each second can be checked against the
## design sheet: a slow orbit, a close orbit of the upper body, walk, run (side / front / back), both casts (front / side),
## weapon draw and attack, a heavy hit, head turns, and sitting. About 75 s. Changes no saved progress.

var main: Node
var who := "mika"
var caption: Label
var only: PackedStringArray = []        # --qa-only=sit,cast,... : film just these parts (orbit, walk, run, cast, head, weapon, hit, sit)


func _ready() -> void:
	who = String(RenderProfile.options.get("qareel", "mika"))
	if RenderProfile.options.has("qa-only"):
		only = String(RenderProfile.options["qa-only"]).split(",")
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _want(part: String) -> bool:
	return only.is_empty() or part in only


func _say(text: String) -> void:
	caption.text = "%s  |  %s" % [String(AppearanceRegistry.current(who).get("name", "")), text]
	print("[qareel] %.1f %s" % [Time.get_ticks_msec() / 1000.0, text])


## the camera rides with her for `seconds`: view = front / side / back / side_l / front34 / orbit / close_orbit
func _cam(m: WorldCharacter, seconds: float, view: String, dist := 3.2, h := 0.95) -> void:
	var rig: ThirdPersonCamera = main.camera_rig
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var fwd := -m.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var c := m.global_position + Vector3(0, h, 0)
		var d: Vector3
		match view:
			"front": d = fwd
			"back": d = -fwd
			"side": d = right
			"side_l": d = -right
			"front34": d = (fwd + right * 0.8).normalized()
			"orbit", "close_orbit": d = fwd.rotated(Vector3.UP, t / seconds * TAU)
		rig.set_shot(c + d * dist + Vector3(0, 0.2, 0), c, 40.0)


func _open_direction(m: WorldCharacter, dist: float) -> Vector3:
	var space := m.get_world_3d().direct_space_state
	var best := -m.global_transform.basis.z
	var best_d := -1.0
	for k in 16:
		var a := k * TAU / 16.0
		var d := Vector3(sin(a), 0, cos(a))
		var free := dist
		for hh in [0.5, 1.2]:
			var q := PhysicsRayQueryParameters3D.create(m.global_position + Vector3(0, hh, 0), m.global_position + Vector3(0, hh, 0) + d * dist)
			q.exclude = [m.get_rid()]
			var r := space.intersect_ray(q)
			if not r.is_empty():
				free = minf(free, (r.position - q.from).length())
		if free > best_d:
			best_d = free
			best = d
	return best


func _gait(m: WorldCharacter, home: Vector3, run: bool, views: Array) -> void:
	for v in views:
		m.global_position = home
		var dir := _open_direction(m, 10.0)
		m.rotation.y = atan2(-dir.x, -dir.z)
		await _cam(m, 0.7, v)                  # the camera settles on her before she sets off
		_say(("run" if run else "walk") + " - " + String(v))
		m.set_move_input(dir, run)
		await _cam(m, 3.0, v)
		m.set_move_input(Vector3.ZERO, false)
		await _cam(m, 0.8, v)


func _run() -> void:
	var m: WorldCharacter = main.characters[who]
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	for k in ["overlay_ui", "rank_tag"]:
		if main.get(k):
			main.get(k).visible = false
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(16, 12)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(caption)
	var want := String(RenderProfile.options.get("qa-stage", ""))
	if want != "":
		AppearanceRegistry.preview(who, want)
		m.swap_avatar(AppearanceRegistry.avatar_for(who))
	var other: WorldCharacter = main.characters.get("luna" if who == "mika" else "mika")
	if other:
		# every reel is filmed on the same clear spot (Mika's start, by the garden's Still Stone): Luna's own start has
		# a training dummy and rocks in the camera's way
		if who != "mika":
			m.global_position = other.global_position
			m.rotation.y = other.rotation.y
		# out of every shot: the reel is about this look (both mages on screen is the perf test's job)
		other.global_position = m.global_position + Vector3(40, 0, 40)
		other.visible = false
		other.process_mode = Node.PROCESS_MODE_DISABLED
	# nobody else drives her while she is filmed (the sanctuary brain sends Luna off to train and cast on her own)
	for k in ["brain", "duel", "companionship", "attention", "impacts", "mage_talk", "performance"]:
		var n: Node = main.get(k)
		if n:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	m.set("_glance_t", 1e9)
	var home := m.global_position
	await _cam(m, 2.0, "front")

	if _want("orbit"):
		_say("idle - full orbit")
		await _cam(m, 7.0, "orbit", 3.0)
		_say("idle - upper body orbit")
		await _cam(m, 5.0, "close_orbit", 1.4, 1.35)
	if _want("walk"):
		await _gait(m, home, false, ["side", "front"])
	if _want("run"):
		await _gait(m, home, true, ["side", "front", "back"])
	m.global_position = home
	await _wait(0.6)
	for clip in (["spell_casting", "wide_arm_spell"] if _want("cast") else []):
		for v in ["front", "side"]:
			if m.play_gesture(clip, 0.25, 0.4):
				_say("cast %s - %s" % [clip, v])
				await _cam(m, 3.2, v)
	m.set("_glance_t", 4.0)
	var hfwd := -m.global_transform.basis.z
	var hright := hfwd.cross(Vector3.UP).normalized()
	for side in ([1.0, -1.0] if _want("head") else []):
		_say("head turn " + ("right" if side > 0 else "left"))
		m.look_head_at(m.global_position + Vector3(0, 1.5, 0) + hright * 2.0 * side + hfwd * 0.4)
		await _cam(m, 2.0, "front34", 1.8, 1.3)
	m.look_head_at(null)
	if m.sword and m.sword.available and _want("weapon"):
		_say("weapon draw")
		await m.sword.draw()
		await _cam(m, 1.0, "front34")
		for v in ["front", "side", "back"]:
			_say("weapon attack - " + v)
			m.sword.attack()
			await _cam(m, 2.0, v)
		m.sword.sheathe()
		await _cam(m, 1.2, "front34")
	var it: Interactable = main.world.interactables.get("garden_meditate") if "interactables" in main.world else null
	if it and _want("sit"):
		m.global_position = it.approach_point() + Vector3(0, 0.1, 0) + (it.approach_point() - it.global_position).normalized() * 0.8
		await _wait(0.4)
		it.duration_override = 14.0
		var job := func(): await it.perform(m)
		job.call()
		_say("sit")
		await _cam(m, 4.0, "front34", 2.6, 0.7)
		_say("sit - orbit")
		await _cam(m, 6.0, "orbit", 2.6, 0.7)
		_say("stand up")
		await _cam(m, 5.0, "front34")          # she stands up (the sit lasts 14 s) before the hit
	# the heavy hit comes last: afterwards the impact behaviours make her back away for a while
	for v in (["front", "side"] if _want("hit") else []):
		_say("heavy hit - " + v)
		m.take_hit(m.global_position - m.global_transform.basis.z * 2.0 + Vector3(0, 1.2, 0), true)
		await _cam(m, 2.6, v)
	print("[qareel] done")
	get_tree().quit()
