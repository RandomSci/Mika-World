class_name FightReach
extends SkeletonModifier3D
## A hand put on a point in the world over whatever the clip does (after the softness pass): the high five after a
## duel, the hand held out to help her up, a palm kept on the shield she is holding. Analytic two-bone IK (as
## SeatPose), the elbow bent down and out; the weight eases in and out so a reach never snaps.

var target := {"Left": Vector3.INF, "Right": Vector3.INF}     # world points (INF = off)
var weight := {"Left": 0.0, "Right": 0.0}                     # what the weight is easing toward
var palm_to := {"Left": Vector3.INF, "Right": Vector3.INF}    # optional: the palm faces this world point
var ease_rate := 7.0
var _w := {"Left": 0.0, "Right": 0.0}
var _ids := {}
var _dt := 1.0 / 30.0
var _fwd := Vector3(0, 0, 1)
var _left := Vector3(1, 0, 0)


static func make(sk: Skeleton3D) -> FightReach:
	var r := FightReach.new()
	r.name = "FightReach"
	sk.add_child(r)
	return r


func reach(side: String, at: Vector3, w := 1.0) -> void:
	target[side] = at
	weight[side] = w


func release(side: String) -> void:
	weight[side] = 0.0


func _process(delta: float) -> void:
	_dt = delta


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _ids.is_empty():
		for s in ["Left", "Right"]:
			_ids[s] = [sk.find_bone(s + "UpperArm"), sk.find_bone(s + "LowerArm"), sk.find_bone(s + "Hand")]
		var toe := sk.get_bone_global_rest(sk.find_bone("LeftToes")).origin - sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin
		toe.y = 0.0
		_fwd = toe.normalized() if toe.length() > 0.001 else Vector3(0, 0, 1)
		_left = (sk.get_bone_global_rest(sk.find_bone("LeftUpperArm")).origin - sk.get_bone_global_rest(sk.find_bone("RightUpperArm")).origin)
		_left.y = 0.0
		_left = _left.normalized()
	var inv := sk.global_transform.affine_inverse()
	for s in ["Left", "Right"]:
		_w[s] = lerpf(float(_w[s]), float(weight[s]), 1.0 - exp(-_dt * ease_rate))
		var w: float = _w[s]
		if w < 0.003 or target[s] == Vector3.INF:
			continue
		var ids: Array = _ids[s]
		if ids.has(-1):
			continue
		var tgt: Vector3 = inv * (target[s] as Vector3)
		var side := 1.0 if s == "Left" else -1.0
		# elbow pole: down, out to her side and a little back (skeleton space, from her rest frame)
		var pole := (_left * 0.6 * side + Vector3.DOWN - _fwd * 0.35).normalized()
		_two_bone(sk, ids, tgt, pole, w)
		if palm_to[s] != Vector3.INF:
			var gh := sk.get_bone_global_pose(ids[2])
			var to := (inv * (palm_to[s] as Vector3) - gh.origin).normalized()
			var palm := (gh.basis * Vector3(0, 0, 1)).normalized()        # (approx.: the palm normal of a VRM hand)
			var q := Quaternion(palm, to)
			sk.set_bone_global_pose(ids[2], Transform3D(Basis(Quaternion.IDENTITY.slerp(q, w * 0.6)) * gh.basis, gh.origin))


static func _two_bone(sk: Skeleton3D, ids: Array, target_p: Vector3, pole: Vector3, w: float) -> void:
	var ga := sk.get_bone_global_pose(ids[0])
	var gb := sk.get_bone_global_pose(ids[1])
	var gc := sk.get_bone_global_pose(ids[2])
	var A := ga.origin
	var la := (gb.origin - A).length()
	var lb := (gc.origin - gb.origin).length()
	var to := target_p - A
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
