class_name TraceFight
extends SkeletonModifier3D
## Combat v3: the FINAL pose (PosePipeline stage 90, after every modifier): world positions of the bones the contact
## solver and QA read - so a fist is aimed at where her forearm really is, not where the clip put it.

const BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftMiddleProximal", "RightMiddleProximal", "LeftUpperLeg",
	"LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

var fighter: Object
var _ids := {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or fighter == null:
		return
	if _ids.is_empty():
		for b in BONES:
			_ids[b] = sk.find_bone(b)
	if fighter.get("phys"):
		fighter.phys.keep_lengths()
	var gx := sk.global_transform
	var tr: Dictionary = fighter.trace
	for b in BONES:
		var bi: int = _ids[b]
		if bi >= 0:
			tr[b] = gx * sk.get_bone_global_pose(bi).origin
	for s in ["Left", "Right"]:
		var h: Vector3 = tr.get(s + "Hand", Vector3.ZERO)
		var m: Vector3 = tr.get(s + "MiddleProximal", h)
		tr["fist_" + s] = m + (m - h).normalized() * 0.03        # the front of the closed fist
		var f: Vector3 = tr.get(s + "Foot", Vector3.ZERO)
		var k: Vector3 = tr.get(s + "LowerLeg", f)
		tr["shin_" + s] = f + (k - f) * 0.18                       # the lower shin / instep (a kick's contact)
		tr["ball_" + s] = tr.get(s + "Toes", f)
	tr["basis"] = gx.basis
	fighter.traced += 1
	fighter.audit(sk)
