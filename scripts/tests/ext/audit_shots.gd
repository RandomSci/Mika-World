extends RefCounted
## The audit's eye check (Selwyn, 2026-10-20: "the audit must fail what my eye fails"): each flagged moment held still
## and filmed close on the bone the rule is about, from her front and from her side. --shots=clip@t@Bone;... --girl=mika
## Marks "[shot] <clip> <t> <bone> <view> at frame N".

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		main.performance.set_process(false)
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, 13.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "axis_deg": 0.0, "bare": true})
	d.set_process(true)
	var c0: Vector3 = d.center
	var who := String(RenderProfile.options.get("girl", "mika"))
	var other := "luna" if who == "mika" else "mika"
	d.F[who].pos = c0
	d.F[other].pos = c0 + Vector3(9.0, 0, 0)
	await t._wait(0.6)
	(d.F[other].c as Node3D).visible = false
	var mc: WorldCharacter = d.F[who].c
	for n in MeleeFighter.OFF_WHILE_FIGHTING:
		var m := mc.skeleton.get_node_or_null(n) as SkeletonModifier3D
		if m:
			m.active = false
	if mc.head_look:
		mc.head_look.influence = 0.0
	# the final pose is read from the end of her modifier stack (a bone read from outside returns the pose before the
	# deck, not what is drawn)
	var tap := TremblePos.new()
	tap.name = "TraceShots"
	mc.skeleton.add_child(tap)
	PosePipeline.of(mc).arrange()
	# (the director takes its first cut late: a warm-up cut on her before the shots)
	d.cut(d.ft + 0.001, "fixed", who, {"pos": c0 + Vector3(2.3, 1.15, 0), "look": c0 + Vector3(0, 1.0, 0), "fov": 40.0})
	await t._wait(0.8)
	var shots := String(RenderProfile.options.get("shots", "")).split(";", false)
	var n_ok := 0
	for sh in shots:
		var clip := sh.get_slice("@", 0)
		var tt := float(sh.get_slice("@", 1))
		var bone := sh.get_slice("@", 2)
		if not mc.has_clip("ml_" + clip):
			continue
		d.F[who].pos = c0
		d.anim(who, "ml_" + clip, tt, tt + 0.001, 0.01, 0.01)
		await t._wait(0.5)
		var sk := mc.skeleton
		var b: Vector3 = tap.pos.get(bone, d.bone(who, bone))
		var fwd: Vector3 = d._flat(d.pos(other) - d.pos(who)).normalized()        # (she faces the other girl)
		var left: Vector3 = Vector3.UP.cross(fwd).normalized()
		var dist := 1.0
		print("[shot] debug %s tap %s probe %s hips %s head %s her pos %s fwd %s" % [bone, str(tap.pos.get(bone, "none")), str(d.bone(who, bone)),
			str(tap.pos.get("Hips", "none")), str(tap.pos.get("Head", "none")), str(d.pos(who)), str(fwd)])
		for view in [["front", fwd], ["side", left if bone.begins_with("Left") else -left]]:
			var dir: Vector3 = view[1]
			d.cut(d.ft + 0.001, "fixed", who, {"pos": b + dir * dist + Vector3.UP * 0.12, "look": b, "fov": 38.0})
			await t._wait(0.35)
			print("[shot] %s %.2f %s %s at frame %d" % [clip, tt, bone, view[0], Engine.get_frames_drawn()])
			await t._wait(0.1)
		n_ok += 1
	t._check(n_ok > 0, "%d shots" % n_ok)
	d.teardown()


class TremblePos extends SkeletonModifier3D:
	var pos := {}

	func _process_modification() -> void:
		var sk := get_skeleton()
		for b in ["LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "Hips", "Head"]:
			var bi := sk.find_bone(b)
			if bi >= 0:
				pos[b] = sk.global_transform * sk.get_bone_global_pose(bi).origin
