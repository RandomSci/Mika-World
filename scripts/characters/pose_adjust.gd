class_name PoseAdjust
extends SkeletonModifier3D
## Post-animation pose corrections, blended by `influence` (SkeletonModifier3D), applied after the
## AnimationTree and before the VRM spring bones read the pose:
##  * seated adduction: the Mixamo "Sitting Idle" opens the knees wide, which looks wrong in a dress.
##    Each thigh is turned about the vertical axis at the hip toward the midline by `knee_close_deg`, and the
##    shin gets the inverse turn at the knee so it stays vertical and the feet remain planted.
## Skeleton space: the VRM faces +Z, the character's left is +X.

var knee_close_deg := 14.0
var last_knee_gap := 0.0   # measured after the correction (for tests)
var _idx := {}


func _bone(n: String) -> int:
	if not _idx.has(n):
		_idx[n] = get_skeleton().find_bone(n)
	return _idx[n]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or influence <= 0.001:
		return
	for side in [["LeftUpperLeg", "LeftLowerLeg", -1.0], ["RightUpperLeg", "RightLowerLeg", 1.0]]:
		var up := _bone(side[0])
		var low := _bone(side[1])
		if up < 0 or low < 0:
			continue
		var ang: float = deg_to_rad(knee_close_deg) * side[2]
		var r := Basis(Vector3.UP, ang)
		_rotate_global(sk, up, r)
		_rotate_global(sk, low, r.inverse())
	var lk := _bone("LeftLowerLeg")
	var rk := _bone("RightLowerLeg")
	if lk >= 0 and rk >= 0:
		last_knee_gap = sk.get_bone_global_pose(lk).origin.distance_to(sk.get_bone_global_pose(rk).origin)


## Rotate a bone by `r` (skeleton space, about the bone's own head) by rewriting its local rotation.
func _rotate_global(sk: Skeleton3D, idx: int, r: Basis) -> void:
	var g := sk.get_bone_global_pose(idx)
	var parent := sk.get_bone_parent(idx)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var new_global := r * g.basis
	var local := (pg.basis.inverse() * new_global).orthonormalized()
	sk.set_bone_pose_rotation(idx, local.get_rotation_quaternion())
