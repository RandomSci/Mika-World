extends RefCounted
## Rig facts for the procedural fight rig: the modifier stack order, key bone rest positions (skeleton space) and the
## local axes of the arm / finger bones in skeleton space.

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	for id in ["mika", "luna"]:
		var c: WorldCharacter = main.characters[id]
		var sk := c.skeleton
		print("[rig] %s stack: %s" % [id, ", ".join(sk.get_children().map(func(n): return "%s(%s)" % [n.name, n.get_class()]))])
		print("[rig] %s skeleton basis %s scale %s motion_scale %.3f" % [id, str(sk.global_transform.basis), str(sk.global_transform.basis.get_scale()), sk.motion_scale])
		for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftIndexProximal", "LeftIndexIntermediate", "LeftThumbProximal", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperArm", "RightHand", "RightFoot"]:
			var bi := sk.find_bone(b)
			if bi < 0:
				print("[rig]   no ", b)
				continue
			var g := sk.get_bone_global_rest(bi)
			print("[rig]   %s pos %s  x %s y %s z %s" % [b, str(g.origin.snappedf(0.001)), str(g.basis.x.normalized().snappedf(0.01)), str(g.basis.y.normalized().snappedf(0.01)), str(g.basis.z.normalized().snappedf(0.01))])
		var names := []
		for i in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		print("[rig] %s bones: %s" % [id, " ".join(names)])
	t._check(true, "probed")
