class_name SeatPose
extends SkeletonModifier3D
## A seated body that can do things (the Moon Lantern Boat, 2026-10-19): on top of the sitting clip, the spine leans
## (forward to row, back to stargaze, sideways over the gunwale), and two-bone IK puts each hand where an action
## needs it (an oar grip, the water, a lantern, her chin, a star) and each foot flat on the boat's floor. Every part
## has a weight that eases toward its goal, so actions blend in and out. Targets are world points (set each frame by
## the activity); poles say where the elbow / knee points (her body frame: x right, y up, z forward).

var lean := 0.0                          # radians: + forward, - back (about her right axis)
var roll := 0.0                          # radians: + toward her right
var twist := 0.0                         # radians: + turns her chest to her left
var arm := {"Left": {"target": Vector3.INF, "w": 0.0, "goal": 0.0, "pole": Vector3(-0.4, -0.6, -0.5)},
	"Right": {"target": Vector3.INF, "w": 0.0, "goal": 0.0, "pole": Vector3(0.4, -0.6, -0.5)}}
var _palm_off := {"Left": Vector3.ZERO, "Right": Vector3.ZERO}     # skeleton space, wrist -> palm centre
var leg := {"Left": {"target": Vector3.INF, "w": 0.0, "goal": 0.0, "pole": Vector3(0.0, 0.3, 1.0)},
	"Right": {"target": Vector3.INF, "w": 0.0, "goal": 0.0, "pole": Vector3(0.0, 0.3, 1.0)}}
var ease_rate := 3.0                     # 1/s: how fast weights move toward their goals
var _lean_s := 0.0
var _roll_s := 0.0
var _twist_s := 0.0
var _dt := 1.0 / 30.0
var _frame := Basis()
var _ids := {}
var _ok := false


static func make(sk: Skeleton3D, at := 0) -> SeatPose:
	var p := SeatPose.new()
	p.name = "SeatPose"
	sk.add_child(p)
	PosePipeline.arrange_for(sk)
	return p


## palm: the target is where her PALM closes (an oar grip), not her wrist - the wrist is aimed short of it by the
## wrist-to-palm offset measured after last frame's solve (the hand turns with the forearm, so it is only known then).
func reach(side: String, target: Vector3, w := 1.0, pole := Vector3.INF, palm := false) -> void:
	arm[side].target = target
	arm[side].goal = w
	arm[side].palm = palm
	if pole != Vector3.INF:
		arm[side].pole = pole


func release(side: String) -> void:
	arm[side].goal = 0.0


func plant(side: String, target: Vector3, w := 1.0) -> void:
	leg[side].target = target
	leg[side].goal = w


func _process(delta: float) -> void:
	_dt = delta
	var k := 1.0 - exp(-delta * ease_rate)
	for d in [arm.Left, arm.Right, leg.Left, leg.Right]:
		d.w = lerpf(float(d.w), float(d.goal), k)
	_lean_s = lerpf(_lean_s, lean, k)
	_roll_s = lerpf(_roll_s, roll, k)
	_twist_s = lerpf(_twist_s, twist, k)


func _setup() -> void:
	var sk := get_skeleton()
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck"]:
		_ids[n] = sk.find_bone(n)
	for s in ["Left", "Right"]:
		_ids[s + "Arm"] = [sk.find_bone(s + "UpperArm"), sk.find_bone(s + "LowerArm"), sk.find_bone(s + "Hand")]
		_ids[s + "Leg"] = [sk.find_bone(s + "UpperLeg"), sk.find_bone(s + "LowerLeg"), sk.find_bone(s + "Foot")]
	var rest := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(n)).origin
	var u: Vector3 = (rest.call("Head") - rest.call("Hips")).normalized()
	var r: Vector3 = rest.call("RightUpperArm") - rest.call("LeftUpperArm")
	r = (r - u * r.dot(u)).normalized()
	var f := r.cross(u)
	var toe: Vector3 = rest.call("LeftToes") - rest.call("LeftFoot")
	if f.dot(toe) < 0.0:
		f = -f
	r = f.cross(u).normalized()               # her right (facing f with u up); the arm difference only set the plane
	_frame = Basis(r, u, f)
	_ok = true


func _rot(bi: int, q: Quaternion) -> void:
	if bi < 0:
		return
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(bi)
	sk.set_bone_global_pose(bi, Transform3D(Basis(q) * g.basis, g.origin))


## Analytic two-bone IK in skeleton space: bones [upper, lower, end], target point, pole (skeleton-space direction).
func _two_bone(ids: Array, target: Vector3, pole: Vector3, w: float) -> void:
	if w < 0.002 or ids.has(-1):
		return
	var sk := get_skeleton()
	var ga := sk.get_bone_global_pose(ids[0])
	var gb := sk.get_bone_global_pose(ids[1])
	var gc := sk.get_bone_global_pose(ids[2])
	var A := ga.origin
	var la := (gb.origin - A).length()
	var lb := (gc.origin - gb.origin).length()
	var to := target - A
	var d := clampf(to.length(), absf(la - lb) + 0.01, la + lb - 0.005)
	var dir := to.normalized() if to.length() > 0.0001 else (gc.origin - A).normalized()
	var bend := pole - dir * pole.dot(dir)
	if bend.length() < 0.0001:
		bend = (gb.origin - A) - dir * (gb.origin - A).dot(dir)
	bend = bend.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var E := A + dir * (la * cos_a) + bend * (la * sqrt(1.0 - cos_a * cos_a))
	var q1 := Quaternion((gb.origin - A).normalized(), (E - A).normalized())
	sk.set_bone_global_pose(ids[0], Transform3D(Basis(Quaternion.IDENTITY.slerp(q1, w)) * ga.basis, ga.origin))
	gb = sk.get_bone_global_pose(ids[1])
	gc = sk.get_bone_global_pose(ids[2])
	var T := A + dir * d
	var q2 := Quaternion((gc.origin - gb.origin).normalized(), (T - gb.origin).normalized())
	sk.set_bone_global_pose(ids[1], Transform3D(Basis(Quaternion.IDENTITY.slerp(q2, w)) * gb.basis, gb.origin))


var calls := 0
func _process_modification() -> void:
	calls += 1
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ok:
		_setup()
	var r: Vector3 = _frame.x
	var u: Vector3 = _frame.y
	# the spine: lean, roll and twist shared down the back
	for pair in [["Spine", 0.4], ["Chest", 0.35], ["UpperChest", 0.25]]:
		var bi: int = _ids[pair[0]]
		var k: float = pair[1]
		# (about her right axis a negative angle bends her forward; about her forward axis a positive one tips her right)
		_rot(bi, Quaternion(r, -_lean_s * k) * Quaternion(_frame.z, _roll_s * k) * Quaternion(u, _twist_s * k))
	# legs, then arms (targets are world points)
	var inv := sk.global_transform.affine_inverse()
	for s in ["Left", "Right"]:
		var lg: Dictionary = leg[s]
		if lg.target != Vector3.INF:
			_two_bone(_ids[s + "Leg"], inv * (lg.target as Vector3), _frame * (lg.pole as Vector3), float(lg.w))
	for s in ["Left", "Right"]:
		var am: Dictionary = arm[s]
		if am.target != Vector3.INF:
			var palm := bool(am.get("palm", false))
			var tgt: Vector3 = inv * (am.target as Vector3) - ((_palm_off[s] as Vector3) if palm else Vector3.ZERO)
			_two_bone(_ids[s + "Arm"], tgt, _frame * (am.pole as Vector3), float(am.w))
			if palm:
				var mp := sk.find_bone(s + "MiddleProximal")
				if mp >= 0:
					var off := (sk.get_bone_global_pose(mp).origin - sk.get_bone_global_pose(int(_ids[s + "Arm"][2])).origin) * 0.5
					_palm_off[s] = (_palm_off[s] as Vector3).lerp(off, 0.5)
