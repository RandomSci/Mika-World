class_name TraceProbe
extends SkeletonModifier3D
## QA: records where a few bones are at its place in the modifier stack (insert one after each modifier to see which
## one moves a bone).
var bones := ["LeftHand", "UpperChest"]
var pos := {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in bones:
		var bi := sk.find_bone(b)
		if bi >= 0:
			pos[b] = sk.get_bone_global_pose(bi).origin
