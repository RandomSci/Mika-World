extends RefCounted
## Combat v3 probe: FightPhysics on Mika - one blow on her head, then per frame: the head-to-neck distance on the final pose (a stretched mesh shows as a bone far from its
## parent), and the simulator's influence.

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	await t._wait(1.0)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 5, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 5, "length": 9999.0, "demo": true})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	await t._wait(1.0)
	var f: MeleeFighter = sim.F.mika
	var ph: FightPhysics = f.phys
	t._check(ph != null, "physics built")
	ph.hit("head", Vector3(1, 0, 0), 1.0)
	var worst := 0.0
	for i in 20:
		await t.get_tree().process_frame
		var hd: Vector3 = f.trace.get("Head", Vector3.ZERO)
		var nk: Vector3 = f.trace.get("Neck", Vector3.ZERO)
		worst = maxf(worst, hd.distance_to(nk))
		var line := "[phys] f%d infl %.2f head-neck %.3f" % [i, ph.sim.influence, hd.distance_to(nk)]
		print(line)
	t._check(worst < 0.2, "head stays on her neck (worst %.3f m)" % worst)
	# 2. the stomach chain while she slides back at knock-back speed (the case that stretched in the renders)
	await t._wait(0.6)
	sim.S.mika.vel = Vector3(-3.5, 0, 0)
	ph.hit("stomach", Vector3(-1, 0, 0), 1.0)
	var worst2 := 0.0
	var who := ""
	for i in 14:
		await t.get_tree().process_frame
		var line2 := "[phys2] f%d infl %.2f" % [i, ph.sim.influence]
		var parent_d := {}
		for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftUpperLeg", "LeftLowerLeg"]:
			var bi := f.sk.find_bone(b)
			var pi := f.sk.get_bone_parent(bi)
			var dd := f.sk.get_bone_global_pose(bi).origin.distance_to(f.sk.get_bone_global_pose(pi).origin) if pi >= 0 else 0.0
			var rest_d := f.sk.get_bone_global_rest(bi).origin.distance_to(f.sk.get_bone_global_rest(pi).origin) if pi >= 0 else 0.0
			var stretch := absf(dd - rest_d)
			if stretch > worst2:
				worst2 = stretch
				who = b
			line2 += " %s %.3f" % [b, stretch]
		print(line2)
	t._check(worst2 < 0.05, "no bone pulled from its parent while sliding (worst %.3f m, %s)" % [worst2, who])
	# the clip bake's joint fix works on a skeleton outside the tree (clips are also baked while characters spawn)
	var anim := MocapBake.bake(f.sk, "res://assets/animations/movelib/cartwheel_evade.json")
	var raw := MocapBake.bake(f.sk, "res://assets/animations/movelib/cartwheel_evade.json")
	var bare := PoseSkel.from(f.sk)
	var bad := 0
	for i in int(anim.length * 30.0):
		JointAudit.pose_at(bare, anim, float(i) / 30.0)
		if not JointAudit.check(bare).is_empty():
			bad += 1
	# positive control: a knee bent backwards on that out-of-tree skeleton must be caught
	for bi in bare.get_bone_count():
		bare.set_bone_pose(bi, bare.get_bone_rest(bi))
	var kn := bare.find_bone("LeftLowerLeg")
	for ang in [1.0, -1.0]:
		bare.set_bone_pose_rotation(kn, bare.get_bone_rest(kn).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, 0.9 * ang))
		bare.force_update_all_bone_transforms()
		bare.force_update_bone_child_transform(0)
		print("[phys] control knee %+.1f rad: %s" % [0.9 * ang, JSON.stringify(JointAudit.check(bare))])
	bare.set_bone_pose_rotation(kn, bare.get_bone_rest(kn).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, 0.9))
	bare.force_update_all_bone_transforms()
	bare.force_update_bone_child_transform(0)
	var c1 := JointAudit.check(bare).size()
	bare.set_bone_pose_rotation(kn, bare.get_bone_rest(kn).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, -0.9))
	bare.force_update_all_bone_transforms()
	bare.force_update_bone_child_transform(0)
	var c2 := JointAudit.check(bare).size()
	t._check((c1 > 0) != (c2 > 0), "plain-data audit catches the backwards knee (one of +/-0.9 rad flagged: %d / %d)" % [c1, c2])
	t._check(bad <= 12, "the baked cartwheel is human (%d frames with any fault, legs included)" % bad)
	sim.teardown()
	d.teardown()
