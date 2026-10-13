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
var mode := ""             # "" (seat) | "sit" (on the ground: knees up) | "lie" (on the back: breathing)
var ground_thigh_deg := 24.0   # how far the thighs rise toward the chest when sitting on the ground
var floor_y := 0.33            # the floor in skeleton space while the visual root is lowered (set by the character)
var sole := 0.07               # ankle bone to sole
var _idx := {}
var _t := 0.0
var debug := {}            # last solve (tests)


func _bone(n: String) -> int:
	if not _idx.has(n):
		_idx[n] = get_skeleton().find_bone(n)
	return _idx[n]


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or influence <= 0.001:
		return
	_t += get_process_delta_time() if is_inside_tree() else 0.016
	if mode == "lie":
		# breathing: the chest rises and falls, the head settles a touch — a still body is a dead body on camera
		var chest := _bone("Chest")
		var spine := _bone("Spine")
		var br := sin(_t * 1.1) * deg_to_rad(1.6)
		if chest >= 0:
			_rotate_global(sk, chest, Basis(Vector3.RIGHT, br))
		if spine >= 0:
			_rotate_global(sk, spine, Basis(Vector3.RIGHT, br * 0.5))
		return
	if mode == "sit":
		# on the ground: thighs up toward the chest, knees folded, so the feet rest in front instead of underground
		for side2 in [["LeftUpperLeg", "LeftLowerLeg", -1.0], ["RightUpperLeg", "RightLowerLeg", 1.0]]:
			var up2 := _bone(side2[0])
			var low2 := _bone(side2[1])
			if up2 < 0 or low2 < 0:
				continue
			# skeleton space: the character faces +Z, so pitching about +X swings a leg up and forward
			_rotate_global(sk, up2, Basis(Vector3.RIGHT, -deg_to_rad(ground_thigh_deg)))
			# then open the knee just enough for the heel to rest on the floor (a one-joint solve, bisection)
			var foot := _bone(side2[1].replace("LowerLeg", "Foot"))
			if foot >= 0:
				var lo_a := -1.9      # fully extended (the heel high in front)
				var hi_a := 0.0       # the clip's own bend (the heel lowest)
				for it in 9:
					var mid_a := (lo_a + hi_a) * 0.5
					var saved := sk.get_bone_pose_rotation(low2)
					_rotate_global(sk, low2, Basis(Vector3.RIGHT, mid_a))
					var fy := sk.get_bone_global_pose(foot).origin.y - sole
					sk.set_bone_pose_rotation(low2, saved)
					if fy < floor_y:
						hi_a = mid_a      # the heel is under the floor: extend the knee further (toward lo_a)
					else:
						lo_a = mid_a
				_rotate_global(sk, low2, Basis(Vector3.RIGHT, (lo_a + hi_a) * 0.5))
				debug[side2[1]] = {"a": snappedf((lo_a + hi_a) * 0.5, 0.01), "foot_y": snappedf(sk.get_bone_global_pose(foot).origin.y, 0.01), "floor": floor_y, "t": snappedf(_t, 0.1)}
			_rotate_global(sk, up2, Basis(Vector3.UP, deg_to_rad(knee_close_deg * 0.6) * side2[2]))
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
