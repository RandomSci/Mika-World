class_name SoftArms
extends SkeletonModifier3D
## The softness pass on wrists, fingers and elbows (2026-10-19, the lake duet): mocap arms read stiff - locked-straight
## elbows, hands that move rigidly with the forearm, flat fingers. On top of the dance:
##  - elbows: never locked straight; a soft minimum bend that eases in (no kink as the arm extends);
##  - wrists: the hand follows its arm with a little drag, so it trails a fast sweep and flows after it (capped);
##  - fingers: a relaxed, graceful dancer's hand - each finger a little more curved toward the little finger, gently
##    alive - blended over the clip's own fingers.

const CURL := {"Thumb": 0.2, "Index": 0.14, "Middle": 0.24, "Ring": 0.32, "Little": 0.4}

var elbow_min := deg_to_rad(18.0)
var wrist_follow := 9.0                  # 1/s: how fast the hand catches up with its arm (lower = more drag)
var wrist_max := deg_to_rad(26.0)
var finger_weight := 0.7
var finger_angle := 1.15                 # radians per joint at curl 1 (as FingerPose)

var _dt := 1.0 / 30.0
var _t := 0.0
var _smooth := {}
var _arm := {}                           # side -> [upper, lower, hand]
var _fingers := {}                       # side -> [[bone, curl, rest rotation, k]]
var _fwd := Vector3.FORWARD


static func make(sk: Skeleton3D, at := 1) -> SoftArms:
	var s := SoftArms.new()
	s.name = "SoftArms"
	sk.add_child(s)
	sk.move_child(s, at)
	return s


func _process(delta: float) -> void:
	_dt = delta
	_t += delta


func _setup() -> void:
	var sk := get_skeleton()
	var toe := sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin - sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin
	toe.y = 0.0
	_fwd = toe.normalized() if toe.length() > 0.001 else Vector3.FORWARD
	for side in ["Left", "Right"]:
		_arm[side] = [sk.find_bone(side + "UpperArm"), sk.find_bone(side + "LowerArm"), sk.find_bone(side + "Hand")]
		var list := []
		var k := 0
		for f in CURL:
			for j in (["Metacarpal", "Proximal", "Distal"] if f == "Thumb" else ["Proximal", "Intermediate", "Distal"]):
				var bi := sk.find_bone(side + f + j)
				if bi >= 0:
					list.append([bi, float(CURL[f]) * (0.7 if f == "Thumb" else 1.0), sk.get_bone_rest(bi).basis.get_rotation_quaternion(), k])
			k += 1
		_fingers[side] = list


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _arm.is_empty():
		_setup()
	for side in _arm:
		var ids: Array = _arm[side]
		if ids.has(-1):
			continue
		# elbow: a soft minimum bend, sqrt(a^2 + m^2), so it eases in as the arm straightens
		var gu := sk.get_bone_global_pose(ids[0])
		var gl := sk.get_bone_global_pose(ids[1])
		var gh := sk.get_bone_global_pose(ids[2])
		var a := (gl.origin - gu.origin).normalized()
		var b := (gh.origin - gl.origin).normalized()
		var ang := a.angle_to(b)
		var need := sqrt(ang * ang + elbow_min * elbow_min) - ang
		if need > 0.002:
			var axis := a.cross(b)
			if axis.length() < 0.05:
				axis = a.cross(_fwd)                          # straight: bend toward her front
			if axis.length() > 0.0001:
				sk.set_bone_global_pose(ids[1], Transform3D(Basis(Quaternion(axis.normalized(), need)) * gl.basis, gl.origin))
		# wrist: the hand trails its arm a little and flows after it
		gh = sk.get_bone_global_pose(ids[2])
		var qa := gh.basis.get_rotation_quaternion()
		var s: Quaternion = _smooth.get(side, qa)
		s = s.slerp(qa, 1.0 - exp(-_dt * wrist_follow))
		var d := s.angle_to(qa)
		if d > wrist_max:
			s = qa.slerp(s, wrist_max / d)
		_smooth[side] = s
		sk.set_bone_global_pose(ids[2], Transform3D(Basis(s).scaled(gh.basis.get_scale()), gh.origin))
		# fingers: a relaxed dancer's hand, gently alive
		var sgn := -1.0 if side == "Right" else 1.0
		for f in _fingers[side]:
			var c: float = float(f[1]) + 0.05 * sin(_t * 1.3 + float(f[3]) * 0.7)
			var target := (f[2] as Quaternion) * Quaternion(Vector3(0, 0, 1), c * finger_angle * sgn)
			sk.set_bone_pose_rotation(int(f[0]), sk.get_bone_pose_rotation(int(f[0])).slerp(target, finger_weight))
