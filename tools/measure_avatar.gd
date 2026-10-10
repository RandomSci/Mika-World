extends SceneTree
## Prints Mika's rest-pose landmark heights (metres above the feet) for sizing props like lecterns.
func _init():
	var root: Node3D = (load("res://assets/characters/mika/Mika.vrm") as PackedScene).instantiate()
	get_root().add_child(root)
	var sk: Skeleton3D = root.find_child("GeneralSkeleton", true, false)
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftEye", "LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]:
		var i := sk.find_bone(b)
		if i >= 0:
			var p := (sk.global_transform * sk.get_bone_global_rest(i)).origin
			print("BONE %-14s y=%.3f x=%.3f z=%.3f" % [b, p.y, p.x, p.z])
	var top := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		top = maxf(top, a.end.y)
	print("MESH TOP y=%.3f" % top)
	quit()
