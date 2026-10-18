class_name FingerPose
extends SkeletonModifier3D
## Procedural finger curls on top of the animation (the harp plucks, a reaching hand): per finger a curl 0..1 bends
## its three joints around the bone's own curl axis. side = "Right" / "Left".
var side := "Right"
var curl := {"Thumb": 0.0, "Index": 0.0, "Middle": 0.0, "Ring": 0.0, "Little": 0.0}
var spread := 0.0                       # fingers fanned apart (radians at the knuckles)
var axis := Vector3(0, 0, 1)            # curl axis in bone space (VRM: fingers lie along X, bend about Z)
var max_angle := 1.25                   # radians per joint at curl 1
var _bones := {}


func _setup() -> void:
	var sk := get_skeleton()
	_bones.clear()
	for f in curl:
		var ids := []
		for j in (["Metacarpal", "Proximal", "Distal"] if f == "Thumb" else ["Proximal", "Intermediate", "Distal"]):
			var bi := sk.find_bone(side + f + j)
			if bi >= 0:
				ids.append(bi)
		_bones[f] = ids


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		_setup()
	var sgn := -1.0 if side == "Right" else 1.0
	var k := 0
	for f in curl:
		var ids: Array = _bones.get(f, [])
		for n in ids.size():
			var bi: int = ids[n]
			var q := sk.get_bone_pose_rotation(bi)
			var c := float(curl[f]) * max_angle * (0.7 if f == "Thumb" else 1.0)
			var add := Quaternion(axis, c * sgn)
			if n == 0 and f != "Thumb":
				add = add * Quaternion(Vector3(0, 1, 0), (k - 1.5) * spread * 0.4)
			sk.set_bone_pose_rotation(bi, q * add)
		k += 1
