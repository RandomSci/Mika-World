class_name FightProbe
extends SkeletonModifier3D
## Last in a fighter's modifier stack: records where her bones really are after every modifier (the clip, the softness
## pass, the IK, the hand guard, the dress), so effects, the camera and the checks read the pose that is drawn.
## (A bone read from outside the stack returns the animation tree's pose, not the fight's.)

const NAMES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
	"RightLowerArm", "RightHand", "LeftFoot", "RightFoot", "LeftToes", "RightToes"]

var pos := {}
var _ids := {}
var scan_nan := false                    # QA (--fight-camdebug): report any bone whose pose is not finite
var nan_bones := {}
var _frames := 0


static func make(sk: Skeleton3D) -> FightProbe:
	var p := FightProbe.new()
	p.name = "FightProbe"
	sk.add_child(p)
	return p


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		for n in NAMES:
			_ids[n] = sk.find_bone(n)
	var g := sk.global_transform
	if scan_nan:
		_frames += 1
		for bi in sk.get_bone_count():
			var t := sk.get_bone_global_pose(bi)
			if not (t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite()):
				var key := sk.get_bone_name(bi)
				if not nan_bones.has(key):
					nan_bones[key] = _frames
					print("[fightnan] %s bone %s NaN at probe frame %d" % [sk.get_parent().get_parent().name if sk.get_parent() else "", key, _frames])
	for n in _ids:
		if int(_ids[n]) >= 0:
			pos[n] = g * sk.get_bone_global_pose(int(_ids[n])).origin
