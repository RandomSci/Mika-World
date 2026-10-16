extends Node
## --transformvideo=<who>:<level> [--tv-prev=<stage id>]: a showcase clip of a look, recorded with Godot's Movie Maker
## (run with --write-movie <file>.avi --fixed-fps 30). Level 10/20/30: she starts in the previous look (tv-prev), the
## full transformation plays (15 s), then she runs, casts and attacks in her new look. Level 1 (no transformation): an
## orbit around her, a walk, a run, a cast and an attack. Every clip is longer than 15 s. Changes no saved progress.

var main: Node
var who := "mika"
var level := 10
var t0 := 0.0


func _ready() -> void:
	var arg := String(RenderProfile.options.get("transformvideo", "mika:10"))
	who = arg.get_slice(":", 0)
	level = int(arg.get_slice(":", 1))
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _follow(m: WorldCharacter, seconds: float, mode: String) -> void:
	var rig: ThirdPersonCamera = main.camera_rig
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var fwd := -m.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var c := m.global_position + Vector3(0, 1.0, 0)
		match mode:
			"orbit":
				var a := t / seconds * TAU
				var d := fwd.rotated(Vector3.UP, a)
				rig.set_shot(c + d * 3.2 + Vector3(0, 0.25, 0), c, 40.0)
			"side":
				rig.set_shot(c + right * 3.4 + fwd * 0.6 + Vector3(0, 0.2, 0), c, 42.0)
			"front":
				rig.set_shot(c + fwd * 3.3 + Vector3(0, 0.25, 0), c, 40.0)
			"front34":
				rig.set_shot(c + (fwd + right * 0.7).normalized() * 3.2 + Vector3(0, 0.3, 0), c, 40.0)


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


func _run() -> void:
	var m: WorldCharacter = main.characters[who]
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	if main.get("overlay_ui"):
		main.overlay_ui.visible = false
	if main.get("rank_tag"):
		main.rank_tag.visible = false
	for k in ["brain", "duel", "companionship", "attention", "impacts", "mage_talk", "performance"]:
		var n: Node = main.get(k)
		if n:
			n.process_mode = Node.PROCESS_MODE_DISABLED
	var other: WorldCharacter = main.characters.get("luna" if who == "mika" else "mika")
	if other and who != "mika":
		# filmed on Mika's clear start spot; the other mage steps out of frame
		var spot := other.global_position
		var rot := other.rotation.y
		other.global_position = spot + Vector3(40, 0, 40)
		other.visible = false
		m.global_position = spot
		m.rotation.y = rot
	var prev := String(RenderProfile.options.get("tv-prev", ""))
	if prev != "":
		AppearanceRegistry.preview(who, prev)
		m.swap_avatar(AppearanceRegistry.avatar_for(who))
	await _follow(m, 2.5, "front34")
	print("[transformvideo] start %.2f" % (Time.get_ticks_msec() / 1000.0))
	t0 = Time.get_ticks_msec() / 1000.0
	if level >= 10 and main.transformer:
		# a moment in the previous look, then the full awakening
		await _follow(m, 1.5, "front34")
		var res: Dictionary = await main.transformer.play(who, "full", false, level)
		print("[transformvideo] transformation ", JSON.stringify(res))
		AppearanceRegistry.preview(who, "")
	else:
		await _follow(m, 5.0, "orbit")
	# the new look in action: run, cast, attack
	var dir := _open_direction(m, 9.0)
	m.rotation.y = atan2(-dir.x, -dir.z)
	await _wait(0.2)
	m.set_move_input(dir, true)
	await _follow(m, 2.6, "side")
	m.set_move_input(Vector3.ZERO, false)
	await _follow(m, 0.8, "front34")
	if m.play_gesture("spell_casting", 0.25, 0.4):
		await _follow(m, 2.6, "front")
	if m.sword and m.sword.available:
		m.sword.draw()
		await _follow(m, 1.2, "front34")
		m.sword.attack()
		await _follow(m, 1.8, "side")
		m.sword.sheathe()
	else:
		m.play_gesture("magic_attack_2h", 0.25, 0.4)
		await _follow(m, 2.4, "front34")
	await _follow(m, 1.5, "front")
	print("[transformvideo] done %.1f s" % (Time.get_ticks_msec() / 1000.0 - t0))
	get_tree().quit()
