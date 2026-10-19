class_name FootLock
extends SkeletonModifier3D
## Planted feet do not slide (v1 item 9). The walk and run clips are played at a speed matched to her body, but never
## exactly: a planted foot drifted 2-6 cm per step. As in most games (foot locking): when the ball of a foot comes
## down, its spot on the ground is remembered, and a two-bone leg IK holds the foot there - the clip's own foot angle
## and height kept - until the clip lifts it (or it would have to stretch further than LET_GO), then it eases back
## to the clip. Only while she walks or runs on the floor: off when she sits, lies, flies, dances or fights.
## IK stage, right after FootGuard (which first lifts the hips so no foot is inside the floor).

const PLANT := 0.025            # m above its standing height: the ball is down
const LIFT := 0.045             # m: the clip lifts it - let go
const LET_GO := 0.18            # m between the clip's foot and the lock: let go rather than stretch the leg
const IN_S := 0.06              # s to blend a lock in / out
const OUT_S := 0.12
const SETTLE_AFTER := 1.0      # s standing still before the feet ease into the idle stance
const SETTLE_S := 0.35         # s for a settle step
const STEP_MIN := 0.015         # m: a smaller difference is let go without a step
const STEP_UP := 0.05           # m the settling foot lifts at mid-step

var enabled := true
var locks := 0                  # (tests) locks made
var _ids := {}                  # side -> [upper, lower, foot, ball]
var _rest_h := {}               # side -> the ball's height above her origin when standing
var _lock := {}                 # side -> world point (or absent)
var _w := {"Left": 0.0, "Right": 0.0}
var _last_pos := Vector3.INF
var _moving := 0.0
var _still := 0.0
var _floor := {}                # side -> the lowest this foot's planted point has been lately (above her origin)
var _held := {}                 # side -> the locked spot, kept while the lock fades out
var _stepping := ""             # the side taking its settle step


func _wc() -> WorldCharacter:
	var n := get_parent()
	while n != null and not (n is WorldCharacter):
		n = n.get_parent()
	return n as WorldCharacter


func _setup(sk: Skeleton3D) -> void:
	for s in ["Left", "Right"]:
		var ball := sk.find_bone(s + "Toes")
		var foot := sk.find_bone(s + "Foot")
		_ids[s] = [sk.find_bone(s + "UpperLeg"), sk.find_bone(s + "LowerLeg"), foot, ball if ball >= 0 else foot]
		_rest_h[s] = sk.get_bone_global_rest(int(_ids[s][3])).origin.y


func _process_modification() -> void:
	var sk := get_skeleton()
	var c := _wc()
	if sk == null or c == null or not sk.is_inside_tree():
		return
	if _ids.is_empty():
		_setup(sk)
	var dt := maxf(get_process_delta_time() if is_inside_tree() else 0.016, 0.001)
	var at := c.global_position
	var jumped := _last_pos != Vector3.INF and at.distance_to(_last_pos) > 1.0
	var spd := 0.0 if _last_pos == Vector3.INF else Vector2(at.x - _last_pos.x, at.z - _last_pos.z).length() / dt
	_last_pos = at
	_moving = 0.6 if spd > 0.05 else maxf(_moving - dt, 0.0)
	_still = 0.0 if spd > 0.05 else _still + dt
	# a lock is kept through a stop (dropping it at once slid the foot to the idle clip's spot: 12 cm on the pier);
	# new locks only while she moves; after a second standing still the feet settle into the idle stance slowly
	var keep := enabled and not jumped and not c.seated and c.ground_pose == "" and not c.lifted \
		and (c.is_on_floor() or not c.is_physics_processing()) and not (c.pose_adjust and c.pose_adjust.influence > 0.05) and not _deck_on(sk)
	var on := keep and _moving > 0.0
	var settle := _still > SETTLE_AFTER
	var gsk := sk.global_transform
	var inv := gsk.affine_inverse()
	var balls := {}
	for s in ["Left", "Right"]:
		if not (_ids[s] as Array).has(-1):
			balls[s] = gsk * sk.get_bone_global_pose(int(_ids[s][3])).origin
	# settling after a stop: one foot at a time takes a small step to where the idle clip has it (never a slide)
	if settle and _stepping == "" and keep:
		var far := ""
		var far_d := 0.0
		for s in _lock:
			var off := Vector2((_lock[s] as Vector3).x - (balls[s] as Vector3).x, (_lock[s] as Vector3).z - (balls[s] as Vector3).z).length()
			if off < STEP_MIN:
				_lock.erase(s)                           # (close enough: no step, nothing to see)
			elif off > far_d:
				far = s
				far_d = off
		if far != "":
			_stepping = far
			_lock.erase(far)
	for s in balls:
		var ids: Array = _ids[s]
		var ball_w: Vector3 = balls[s]
		var h := ball_w.y - at.y
		# her own floor for this foot: the lowest it has been lately (shoes with heels never bring an ankle down to its
		# T-pose height - Luna's rig has no toe joint, so her ankle is the planted point)
		var fl: float = _floor.get(s, h)
		fl = h if (h < fl or jumped) else fl + dt * 0.03
		_floor[s] = fl
		if not keep:
			_lock.erase(s)
			if jumped:
				_w[s] = 0.0                              # (moved far in one frame: never reach back to the old spot)
				_stepping = ""
		elif _lock.has(s):
			var lk: Vector3 = _lock[s]
			if h > fl + LIFT or Vector2(ball_w.x - lk.x, ball_w.z - lk.z).length() > LET_GO:
				_lock.erase(s)
		elif on and h < fl + PLANT and float(_w[s]) < 0.05 and _stepping != s:
			_lock[s] = ball_w
			_held[s] = ball_w
			locks += 1
		var goal := 1.0 if _lock.has(s) else 0.0
		var rate := IN_S if goal > 0.5 else (SETTLE_S if _stepping == s else OUT_S)
		_w[s] = move_toward(float(_w[s]), goal, dt / rate)
		var w: float = _w[s]
		if _stepping == s and w <= 0.0:
			_stepping = ""
		if w < 0.001:
			continue
		var held: Vector3 = _held.get(s, ball_w)          # (kept through the fade-out: no snap on release)
		var shift := Vector3(held.x - ball_w.x, 0.0, held.z - ball_w.z) * w     # (height: the clip's, over the floor)
		if _stepping == s:
			shift.y = STEP_UP * sin(PI * (1.0 - w))      # the settle step lifts the foot on its way
		if shift.length() < 0.0005:
			continue
		var foot_t: Vector3 = inv * (gsk * sk.get_bone_global_pose(int(ids[2])).origin + shift)
		_two_bone(sk, ids, foot_t)


## Upper/lower leg turned so the foot bone lands on `t` (skeleton space), the knee staying on its own side; the foot
## keeps its global rotation (the clip's angle on the ground).
func _two_bone(sk: Skeleton3D, ids: Array, t: Vector3) -> void:
	var ga := sk.get_bone_global_pose(int(ids[0]))
	var gb := sk.get_bone_global_pose(int(ids[1]))
	var gc := sk.get_bone_global_pose(int(ids[2]))
	var a := ga.origin
	var b := gb.origin
	var cc := gc.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(cc)
	var at := t - a
	var d := clampf(at.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	if at.length() < 0.001:
		return
	var n := (b - a).cross(cc - b)
	if n.length() < 1e-5:
		return
	n = n.normalized()
	var alpha := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var dir := at.normalized()
	var k1 := a + Quaternion(n, alpha) * dir * l1
	var k2 := a + Quaternion(n, -alpha) * dir * l1
	var knee := k1 if k1.distance_to(b) < k2.distance_to(b) else k2
	var q1 := Quaternion((b - a).normalized(), (knee - a).normalized())
	sk.set_bone_global_pose(int(ids[0]), Transform3D(Basis(q1) * ga.basis, a))
	var gb2 := sk.get_bone_global_pose(int(ids[1]))
	var gc2 := sk.get_bone_global_pose(int(ids[2]))
	var q2 := Quaternion((gc2.origin - gb2.origin).normalized(), (a + dir * d - gb2.origin).normalized())
	sk.set_bone_global_pose(int(ids[1]), Transform3D(Basis(q2) * gb2.basis, gb2.origin))
	var gc3 := sk.get_bone_global_pose(int(ids[2]))
	sk.set_bone_global_pose(int(ids[2]), Transform3D(gc.basis, gc3.origin))


## A dance or fight deck driving her: their own feet, never locked.
func _deck_on(sk: Skeleton3D) -> bool:
	for n in sk.get_children():
		if (n is DanceDeck or String(n.name).begins_with("FightDeck")) and float(n.get("influence")) > 0.05:
			return true
	return false
