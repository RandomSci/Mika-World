extends RefCounted
## Combat v3, deliverable 1: a live close-combat exchange (MeleeSim on the procedural fight rig) between Mika and Luna
## at the training clearing, --fight-seed=N for the dice, --fight-length=S (default 15). Checks the rules: the
## defender never reacts before 0.10 s after the windup starts, fists / feet really touch (contact error at the hit
## frame), exchanges keep flowing (gaps between actions), a mix of hits, blocks, dodges.

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		if main.performance.busy():
			main.performance.interrupt("fight test")
			var w0: float = t._game_t
			while main.performance.busy() and t._game_t - w0 < 8.0:
				await t.get_tree().process_frame
		main.performance.set_process(false)
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	var seed := int(RenderProfile.options.get("fight-seed", "11"))
	FightDirector.set_hour(main, float(RenderProfile.options.get("fight-hour", "17.6")))
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
		main.weather.cloud = 0.0
		main.weather.rain = 0.0
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(2.0)
	if main.get("voice") and main.voice:
		main.voice.stop()
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": seed, "axis_deg": float(seed * 37 % 360), "bare": true})
	# --ult-at=mika=14,luna=22 (fight seconds of each girl's ultimate), --ult-pick=mika=ult_x,luna=ult_y
	var ua := {}
	for kv in String(RenderProfile.options.get("ult-at", "")).split(",", false):
		ua[kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
	var up := {}
	for kv in String(RenderProfile.options.get("ult-pick", "")).split(",", false):
		up[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
	var sim := MeleeSim.make(d, {"seed": seed, "length": float(RenderProfile.options.get("fight-length", "15")), "ult_at": ua, "ult_pick": up})
	d.cut(0.0, "duo", "mika", {"k": 1.0, "high": 0.35})
	d.set_process(true)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	sim.start()
	if RenderProfile.options.has("jitter-log"):
		# (the trembling probe) every rendered frame: each girl's root and the final rotation of her main bones
		for id in ["mika", "luna"]:
			var jt := JitterTap.new()
			jt.name = "TraceJitter"
			jt.id = id
			jt.c = (sim.F[id] as MeleeFighter).c
			(sim.F[id] as MeleeFighter).sk.add_child(jt)
			PosePipeline.arrange_for((sim.F[id] as MeleeFighter).sk)
	if RenderProfile.options.has("jitter-layers"):
		# (which layer adds the tremble) a tap after every modifier of Luna's stack
		var sk: Skeleton3D = (sim.F.luna as MeleeFighter).sk
		var mods := []
		for m in sk.get_children():
			if m is SkeletonModifier3D:
				mods.append(m)
		var order := PackedStringArray()
		for m in mods:
			order.append(String(m.name) + ("" if (m as SkeletonModifier3D).active else "(off)"))
			var lt := LayerJit.new()
			lt.name = "LJ_" + String(m.name)
			lt.layer = String(m.name)
			sk.add_child(lt)
			sk.move_child(lt, (m as Node).get_index() + 1)
		print("[ljit] order %s" % ", ".join(order))
	await t._wait(0.6)
	# she faces the other girl: skeleton +Z toward her
	var fm: MeleeFighter = sim.F.mika
	var fz := (fm.sk.global_transform.basis * Vector3(0, 0, 1))
	fz.y = 0.0
	var to := d.pos("luna") - d.pos("mika")
	to.y = 0.0
	t._check(fz.normalized().dot(to.normalized()) > 0.9, "skeleton +Z faces the opponent (dot %.2f)" % fz.normalized().dot(to.normalized()))
	print("[melee] fight starts at frame %d" % Engine.get_frames_drawn())
	while not sim.done:
		await t.get_tree().process_frame
	var r: Dictionary = sim.result()
	await t._wait(0.4)
	print("[melee] result ", JSON.stringify({"length": r.length, "outcomes": r.outcomes, "exchanges": r.exchanges, "gaps": r.gaps, "vfx": r.vfx}))
	for a in r.attacks:
		print("[melee]   %s" % JSON.stringify(a))
	for e in r.events:
		print("[melee]   ev %s" % JSON.stringify(e))
	t.report["melee"] = r
	var errs: Array = r.contact_err
	var worst := 0.0
	var mean := 0.0
	for e in errs:
		worst = maxf(worst, float(e))
		mean += float(e)
	mean /= maxf(errs.size(), 1)
	var delays: Array = r.react_delays
	var early := delays.filter(func(x): return float(x) < 0.099)
	var gaps: Array = r.gaps
	var gmax := 0.0
	for g in gaps:
		gmax = maxf(gmax, float(g))
	var n: int = (r.attacks as Array).size()
	t._check(n >= 10, "%d attacks in %.0f s" % [n, float(r.length)])
	t._check(errs.size() >= 3 and mean < 0.05 and worst < 0.09, "contact: fist / foot to the point it lands on, mean %.3f m, worst %.3f m over %d hits and blocks" % [mean, worst, errs.size()])
	t._check(early.is_empty(), "no defender moves before 0.10 s after the windup starts (%d reactions, min %.2f s)" % [delays.size(), delays.min() if not delays.is_empty() else -1.0])
	var oc: Dictionary = r.outcomes
	t._check(oc.size() >= 3, "a mix of outcomes: %s" % str(oc))
	t._check(gmax < 1.3, "actions keep coming: longest gap between any two actions %.2f s" % gmax)
	sim.teardown()
	d.teardown()


## (--jitter-log) "[jit] <id> <frame> <px> <py> <pz> <yaw> then x y z w per bone" of the final pose, every frame.
class JitterTap extends SkeletonModifier3D:
	const BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
	var id := ""
	var c: Node3D

	func _process_modification() -> void:
		var sk := get_skeleton()
		var parts := PackedStringArray()
		var g := sk.global_transform
		parts.append("%.4f %.4f %.4f %.4f" % [g.origin.x, g.origin.y, g.origin.z, c.rotation.y if c else 0.0])
		for b in BONES:
			var q := sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
			parts.append("%.4f %.4f %.4f %.4f" % [q.x, q.y, q.z, q.w])
		print("[jit] %s %d %s" % [id, Engine.get_frames_drawn(), " ".join(parts)])
		if RenderProfile.options.has("ankle-log"):
			var al := PackedStringArray()
			for side in ["Left", "Right"]:
				var a := JointAudit.ankle(sk, side)
				al.append("%s %.1f %.1f %.1f" % [side, a.flex, a.side, a.twist])
			var fm: MeleeFighter = null
			print("[ank] %s %d %s" % [id, Engine.get_frames_drawn(), " ".join(al)])


## (--jitter-layers) after one modifier: "[ljit] <layer> <frame> x y z w" for Head, RightHand, RightUpperLeg, UpperChest.
class LayerJit extends SkeletonModifier3D:
	var layer := ""

	func _process_modification() -> void:
		var sk := get_skeleton()
		var parts := PackedStringArray()
		for b in ["Head", "RightHand", "RightUpperLeg", "UpperChest"]:
			var q := sk.get_bone_global_pose(sk.find_bone(b)).basis.get_rotation_quaternion()
			parts.append("%.4f %.4f %.4f %.4f" % [q.x, q.y, q.z, q.w])
		print("[ljit] %s %d %s" % [layer, Engine.get_frames_drawn(), " ".join(parts)])
