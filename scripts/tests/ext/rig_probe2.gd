extends RefCounted
## The fight rig's modifier order and whether the arm IK reaches a fixed target (Combat v3 debugging).

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 3, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 3, "length": 999.0})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.F["mika"] = MeleeFighter.make(d, "mika")
	var f: MeleeFighter = sim.F.mika
	var sk := f.sk
	print("[rig2] stack: ", ", ".join(sk.get_children().filter(func(n): return n is SkeletonModifier3D).map(func(n): return "%s(%.2f)" % [n.name, n.influence])))
	for i in 40:
		f.update(1.0 / 30.0)
		await t.get_tree().process_frame
	# put the left wrist on a point 0.35 m in front of her left shoulder
	var sh: Vector3 = f.trace.get("LeftUpperArm", Vector3.ZERO)
	var fwd := sk.global_transform.basis * Vector3(0, 0, 1)
	var goal := sh + fwd.normalized() * 0.35
	f.play([{"dur": 0.2, "ease": "out", "pose": {}, "dyn": {"lh": func() -> Vector3: return goal}}, {"dur": 5.0, "ease": "hold", "pose": {}, "dyn": {"lh": func() -> Vector3: return goal}}])
	for i in 30:
		f.update(1.0 / 30.0)
		await t.get_tree().process_frame
	var hand: Vector3 = f.trace.get("LeftHand", Vector3.ZERO)
	print("[rig2] goal %s ik target %s hand %s err %.3f; target node err %.3f" % [str(goal.snappedf(0.01)), str(f.ik_target("lh").snappedf(0.01)), str(hand.snappedf(0.01)), hand.distance_to(goal), f.ik_target("lh").distance_to(goal)])
	# the same with every other modifier after the IK switched off
	var after := false
	for n in sk.get_children():
		if n is SkeletonModifier3D:
			if after and not (String(n.name) in ["FightBodyPost", "TraceFight"]):
				print("[rig2]   after IK: ", n.name, " active=", n.active)
				(n as SkeletonModifier3D).active = false
			if String(n.name) == "FightIK_rf":
				after = true
	for i in 10:
		f.update(1.0 / 30.0)
		await t.get_tree().process_frame
	hand = f.trace.get("LeftHand", Vector3.ZERO)
	print("[rig2] with later modifiers off: hand err %.3f" % hand.distance_to(goal))
	t._check(true, "probed")
