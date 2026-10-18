class_name PoseAim
extends SkeletonModifier3D
## A held dance pose on top of the animation (the lake dance, 2026-10-19: Selwyn's targets T1 spin, T2 raised arm,
## T3 arms wide): each listed bone is turned so it points along a direction in her own body frame (x = her right,
## y = up, z = her forward), parents first. The frame comes from the rest pose, so it works whatever the import
## axes are. `influence` (SkeletonModifier3D) blends the pose in and out.

const CHILD := {"UpperArm": "LowerArm", "LowerArm": "Hand", "Hand": "MiddleProximal", "UpperLeg": "LowerLeg",
	"LowerLeg": "Foot", "Foot": "Toes", "Neck": "Head"}

const POSES := {
	# T1 spin: the right arm reaching out ahead of the turn, the left trailing low behind
	"spin": {"RightUpperArm": Vector3(0.85, 0.08, 0.5), "RightLowerArm": Vector3(0.8, 0.22, 0.55), "RightHand": Vector3(0.8, 0.28, 0.5),
		"LeftUpperArm": Vector3(-0.75, -0.55, -0.3), "LeftLowerArm": Vector3(-0.7, -0.6, 0.0), "LeftHand": Vector3(-0.7, -0.5, 0.1)},
	# T2 pose: the right arm raised to the sky, the left out low, the left leg drawn up (a passé)
	"reach": {"RightUpperArm": Vector3(0.28, 0.95, 0.1), "RightLowerArm": Vector3(0.14, 1.0, 0.14), "RightHand": Vector3(0.1, 1.0, 0.2),
		"LeftUpperArm": Vector3(-0.85, -0.42, 0.15), "LeftLowerArm": Vector3(-0.85, -0.3, 0.3), "LeftHand": Vector3(-0.8, -0.2, 0.35),
		"LeftUpperLeg": Vector3(-0.35, -0.12, 0.93), "LeftLowerLeg": Vector3(0.5, -0.84, -0.15), "LeftFoot": Vector3(0.15, -0.85, 0.45),
		"Neck": Vector3(0.06, 1.0, -0.28)},
	# T3 finale: both arms open wide and up, the face lifted
	"open": {"RightUpperArm": Vector3(0.82, 0.55, 0.12), "RightLowerArm": Vector3(0.76, 0.65, 0.12), "RightHand": Vector3(0.7, 0.7, 0.15),
		"LeftUpperArm": Vector3(-0.82, 0.55, 0.12), "LeftLowerArm": Vector3(-0.76, 0.65, 0.12), "LeftHand": Vector3(-0.7, 0.7, 0.15),
		"Neck": Vector3(0.0, 1.0, -0.15)},
}

var aims := {}                # bone name -> Vector3 in her body frame
var _frame := Basis()          # columns: her right, up, forward in skeleton space
var _ids: Array = []           # [bone, child, direction]


static func make(sk: Skeleton3D, pose: String) -> PoseAim:
	var p := PoseAim.new()
	p.name = "Pose_" + pose
	p.aims = POSES[pose]
	p.influence = 0.0
	sk.add_child(p)
	sk.move_child(p, 0)        # before the dress sim and every look/drape modifier, so the dress follows the pose
	return p


func _setup_ids() -> void:
	var sk := get_skeleton()
	var rest := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(n)).origin
	var u: Vector3 = (rest.call("Head") - rest.call("Hips")).normalized()
	var r: Vector3 = rest.call("RightUpperArm") - rest.call("LeftUpperArm")
	r = (r - u * r.dot(u)).normalized()
	var f := r.cross(u)
	var toe: Vector3 = rest.call("LeftToes") - rest.call("LeftFoot")
	if f.dot(toe) < 0.0:
		f = -f
	_frame = Basis(r, u, f)
	_ids.clear()
	var order := []
	for n in aims:
		var bi := sk.find_bone(n)
		var suffix := String(n).trim_prefix("Right").trim_prefix("Left")
		var cn: String = String(n).replace(suffix, CHILD.get(suffix, "")) if CHILD.has(suffix) else ""
		var ci := sk.find_bone(cn) if cn != "" else -1
		if bi >= 0 and ci >= 0:
			order.append([bi, ci, (aims[n] as Vector3).normalized()])
	order.sort_custom(func(a, b): return a[0] < b[0])
	_ids = order


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		_setup_ids()
	for e in _ids:
		var gp := sk.get_bone_global_pose(int(e[0]))
		var cp := sk.get_bone_global_pose(int(e[1]))
		var cur := cp.origin - gp.origin
		if cur.length() < 0.0001:
			continue
		cur = cur.normalized()
		var want: Vector3 = (_frame * (e[2] as Vector3)).normalized()
		if cur.dot(want) < -0.999:
			continue
		var q := Quaternion(cur, want)
		sk.set_bone_global_pose(int(e[0]), Transform3D(Basis(q) * gp.basis, gp.origin))
