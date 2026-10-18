class_name BodyLife
extends SkeletonModifier3D
## Procedural secondary motion over the dance clips (2026-10-19, Selwyn: "the bodies are still stiff and robotic"):
##  - overlap: the chest, neck and head follow the hips' turns a moment late, so a turn flows up the spine;
##  - breathing: the chest rises and settles, the shoulders with it;
##  - loose shoulders: relaxed a little down at rest, riding up as an arm lifts over the shoulder line;
##  - a soft look: the head turns part of the way toward a target (the partner, the lens), smoothed and limited.
## Runs right after the clip (DanceDeck), before the softness pass on the arms.

var look: Callable                       # -> world point to look toward, or Vector3.INF for none
var look_weight := 0.35
var look_max := deg_to_rad(38.0)
var follow := 5.0                        # 1/s: how fast the upper body catches up with the hips
var overlap_max := deg_to_rad(14.0)
var breath_hz := 0.24
var breath_deg := 1.3
var shoulder_rest_deg := -3.0
var shoulder_lift_deg := 9.0

var _dt := 1.0 / 30.0
var _t := 0.0
var _ids := {}
var _frame := Basis()
var _head_fwd := Vector3.FORWARD
var _hips_s := Quaternion.IDENTITY
var _look_s := Quaternion.IDENTITY
var _ready_ok := false


static func make(sk: Skeleton3D, at := 1) -> BodyLife:
	var b := BodyLife.new()
	b.name = "BodyLife"
	sk.add_child(b)
	sk.move_child(b, at)
	return b


func _process(delta: float) -> void:
	_dt = delta
	_t += delta


func _setup() -> void:
	var sk := get_skeleton()
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm"]:
		_ids[n] = sk.find_bone(n)
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
	_head_fwd = sk.get_bone_global_rest(_ids.Head).basis.inverse() * f
	_hips_s = sk.get_bone_global_pose(_ids.Hips).basis.get_rotation_quaternion()
	_ready_ok = true


func _rot(bi: int, q: Quaternion) -> void:
	if bi < 0:
		return
	var sk := get_skeleton()
	var g := sk.get_bone_global_pose(bi)
	sk.set_bone_global_pose(bi, Transform3D(Basis(q) * g.basis, g.origin))


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ready_ok:
		_setup()
	var r: Vector3 = _frame.x
	var u: Vector3 = _frame.y
	var f: Vector3 = _frame.z
	# overlap: the upper body lags the hips' rotation a little
	var qh := sk.get_bone_global_pose(_ids.Hips).basis.get_rotation_quaternion()
	_hips_s = _hips_s.slerp(qh, 1.0 - exp(-_dt * follow))
	var lag := _hips_s * qh.inverse()
	var la := lag.get_angle()
	if la > overlap_max:
		lag = Quaternion.IDENTITY.slerp(lag, overlap_max / la)
	_rot(_ids.Chest, Quaternion.IDENTITY.slerp(lag, 0.3))
	_rot(_ids.UpperChest, Quaternion.IDENTITY.slerp(lag, 0.2))
	_rot(_ids.Neck, Quaternion.IDENTITY.slerp(lag, 0.25))
	# breathing: chest and shoulders
	var br := sin(TAU * breath_hz * _t)
	_rot(_ids.Chest, Quaternion(r, deg_to_rad(breath_deg) * br * 0.6))
	_rot(_ids.UpperChest, Quaternion(r, deg_to_rad(breath_deg) * br * 0.4))
	# shoulders: relaxed, riding up with the arm (and a touch with each breath)
	for side in ["Left", "Right"]:
		var sb: int = _ids[side + "Shoulder"]
		var ua: int = _ids[side + "UpperArm"]
		var la_: int = _ids[side + "LowerArm"]
		if sb < 0 or ua < 0 or la_ < 0:
			continue
		var arm := (sk.get_bone_global_pose(la_).origin - sk.get_bone_global_pose(ua).origin).normalized()
		var lift := clampf(arm.dot(u) + 0.15, 0.0, 1.0)
		var deg := shoulder_rest_deg + shoulder_lift_deg * lift + 0.6 * br
		var axis := -f if side == "Right" else f        # (a positive turn about these lifts that shoulder)
		_rot(sb, Quaternion(axis, deg_to_rad(deg)))
	# the look: part of the way toward the target, smoothed, within a cone
	var want := Quaternion.IDENTITY
	if look.is_valid():
		var tp: Vector3 = look.call()
		if tp != Vector3.INF:
			var hg := sk.get_bone_global_pose(_ids.Head)
			var to := sk.global_transform.affine_inverse() * tp - hg.origin
			var cur := (hg.basis * _head_fwd).normalized()
			if to.length() > 0.05:
				var q := Quaternion(cur, to.normalized())
				var a := q.get_angle()
				if a > look_max:
					q = Quaternion.IDENTITY.slerp(q, look_max / a)
				want = Quaternion.IDENTITY.slerp(q, look_weight)
	_look_s = _look_s.slerp(want, 1.0 - exp(-_dt * 4.0))
	_rot(_ids.Neck, Quaternion.IDENTITY.slerp(_look_s, 0.4))
	_rot(_ids.Head, Quaternion.IDENTITY.slerp(_look_s, 0.6))
