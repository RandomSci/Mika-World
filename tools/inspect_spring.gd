extends SceneTree
func _init():
	var root: Node = (load("res://assets/characters/mika/Mika.vrm") as PackedScene).instantiate()
	var sec = root.find_child("secondary", true, false)
	var sbs = sec.get("spring_bones")
	print("spring groups: ", sbs.size())
	var all_cg := {}
	for b in sbs:
		var j: PackedStringArray = b.joint_nodes
		print("  SB ", b.comment, " joints=", j.size(), " first=", j[0] if j.size() else "", " cgs=", b.collider_groups.size(), " grav=", b.gravity_power.slice(0,2), " stiff=", b.stiffness_force.slice(0,2), " r=", b.hit_radius.slice(0,2))
		for cg in b.collider_groups:
			all_cg[cg] = true
	for cg in all_cg:
		for c in cg.colliders:
			print("  COLL bone=", c.bone, " off=", c.offset, " tail=", c.tail, " r=", c.radius, " cap=", c.is_capsule)
	quit()
