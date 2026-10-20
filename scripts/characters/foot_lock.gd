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
const LET_GO_SLOW := 0.08       # m: stopping or turning on the spot - a step comes sooner
const IN_S := 0.06              # s to blend a lock in / out
const OUT_S := 0.12
const SETTLE_AFTER := 1.0      # s standing still before the feet ease into the idle stance
const SETTLE_S := 0.35         # s for a settle step
const STEP_MIN := 0.015         # m: a smaller difference is let go without a step
const STEP_UP := 0.05           # m the settling foot lifts at mid-step
const STEP_BELOW := 1.0         # m/s: slower than a walk (stopping, turning), a foot that must move steps
const LIFT_FAR := 0.06          # m held from the clip's foot when it lifts: released as a quick step
const SLIDE_V := 0.12           # m/s: a planted foot the clip moves faster than this, standing, is held (then steps)
const LAND := 0.12              # step weight under which the foot is down again: it locks there

var enabled := true
var locks := 0                  # (tests) locks made
var _ids := {}                  # side -> [upper, lower, foot, ball]
var _rest_h := {}               # side -> the ball's height above her origin when standing
var _lock := {}                 # side -> world point (or absent)
var _w := {"Left": 0.0, "Right": 0.0}
var _last_pos := Vector3.INF
var _last_yaw := NAN
var _moving := 0.0
var _still := 0.0
var _floor := {}                # side -> the lowest this foot's planted point has been lately (above her origin)
var _held := {}                 # side -> the locked spot, kept while the lock fades out
var _dbg := false
var _prev_ball := {}           # side -> the clip's ball last frame (world)
var _was_on := false
var _quick := {}                # side -> its step is a quick one (released at speed)
var _up := {}                   # side -> lifted off the floor since its last lock
var _stepping := {}             # side -> true while it takes a step (a settle, or a let-go with the foot still down)


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
	_dbg = RenderProfile.options.get("fl-debug", "") == c.character_id
	var at := c.global_position
	var jumped := _last_pos != Vector3.INF and at.distance_to(_last_pos) > 1.0
	var spd := 0.0 if _last_pos == Vector3.INF else Vector2(at.x - _last_pos.x, at.z - _last_pos.z).length() / dt
	_last_pos = at
	var yaw := c.global_rotation.y
	var turn := 0.0 if is_nan(_last_yaw) else absf(wrapf(yaw - _last_yaw, -PI, PI)) / dt
	_last_yaw = yaw
	var busy := spd > 0.05 or turn > 0.6                 # (turning on the spot counts: feet step round, never swivel)
	_moving = 0.6 if busy else maxf(_moving - dt, 0.0)
	_still = 0.0 if busy else _still + dt
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
	if settle and _stepping.is_empty() and keep:
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
			_stepping[far] = true
			_lock.erase(far)
	for s in balls:
		var ids: Array = _ids[s]
		var ball_w: Vector3 = balls[s]
		var last_ball = _prev_ball.get(s)
		_prev_ball[s] = ball_w
		var h := ball_w.y - at.y
		# her own floor for this foot: the lowest it has been lately (shoes with heels never bring an ankle down to its
		# T-pose height - Luna's rig has no toe joint, so her ankle is the planted point)
		var fl: float = _floor.get(s, h)
		fl = h if (h < fl or jumped) else fl + dt * 0.03
		_floor[s] = fl
		if not keep:
			_floor.erase(s)                              # (sitting, lying, dancing: their feet say nothing of her floor -
			# after a ground sit it stayed 26 cm low and no foot locked for seconds)
			_lock.erase(s)
			if jumped:
				_w[s] = 0.0                              # (moved far in one frame: never reach back to the old spot)
				_stepping.erase(s)
				_quick.erase(s)
		elif _lock.has(s):
			var lk: Vector3 = _lock[s]
			if h > fl + LIFT:
				_lock.erase(s)
				if Vector2(ball_w.x - lk.x, ball_w.z - lk.z).length() > LIFT_FAR:
					# the clip lifts it while it is held far back (breaking into a run, the leg stretched): a quick
					# lifted step - faded out, the stretched leg scraped it 7 cm along the ground
					_stepping[s] = true
					_quick[s] = true
			elif Vector2(ball_w.x - lk.x, ball_w.z - lk.z).length() > (LET_GO if spd >= 0.3 else LET_GO_SLOW):
				_lock.erase(s)
				if spd < STEP_BELOW:                     # (also every step of a turn on the spot)
					_stepping[s] = true                  # (a stop: the clip moved it along the ground - step, never slide)
				elif h < fl + PLANT:
					# still down at speed (a walk breaking into a run: 1.5 -> 4 m/s in two frames): a quick lifted
					# step to the clip's foot - faded along the ground it dragged 33 cm
					_stepping[s] = true
					_quick[s] = true
		elif (on or (last_ball != null and Vector2(ball_w.x - last_ball.x, ball_w.z - last_ball.z).length() / dt > SLIDE_V)) \
				and h < fl + PLANT and (float(_w[s]) < 0.05 or _up.get(s, false)) and not _stepping.has(s):
			# (standing too, when the clip drags a planted foot along the ground: the end of a gesture slid one 28 cm)
			if not _was_on and float(_w[s]) <= 0.0 and last_ball != null and not jumped:
				# she starts to move or turn from standing: the foot holds where it stood last frame (drawn there,
				# so no pop) at once - locking a frame later at the blend-in rate let it swivel 5 cm first
				_lock[s] = last_ball
				_w[s] = 1.0
			elif float(_w[s]) >= 0.05:
				# down again while the last lock still fades out (a stop mid-stride): it locks where it is drawn now,
				# at once (left unlocked it skidded 4-7 cm as it landed)
				var hd: Vector3 = _held.get(s, ball_w)
				var wf: float = _w[s]
				_lock[s] = ball_w + Vector3(hd.x - ball_w.x, 0.0, hd.z - ball_w.z) * wf
				_w[s] = 1.0
			else:
				_lock[s] = ball_w
			_held[s] = _lock[s]
			_up[s] = false
			locks += 1
		if h > fl + LIFT:
			_up[s] = true                                # (lifted since its last lock: it may lock again as it lands)
		var goal := 1.0 if _lock.has(s) else 0.0
		var rate := IN_S if goal > 0.5 else (SETTLE_S if _stepping.has(s) and not _quick.has(s) else OUT_S)
		_w[s] = move_toward(float(_w[s]), goal, dt / rate)
		var w: float = _w[s]
		if _stepping.has(s) and not _quick.has(s) and w < LAND and keep and _held.has(s):
			# the step comes down: it locks where it lands (left to follow the clip, a foot still turning with her
			# body slid the last few cm of every step of a turn)
			var hd: Vector3 = _held[s]
			var land := ball_w + Vector3(hd.x - ball_w.x, 0.0, hd.z - ball_w.z) * (w * w * (3.0 - 2.0 * w))
			_stepping.erase(s)
			_lock[s] = land
			_held[s] = land
			_w[s] = 1.0
			w = 1.0
			locks += 1
		if _stepping.has(s) and w <= 0.0:
			_stepping.erase(s)
			_quick.erase(s)
		if _dbg:
			var hd: Vector3 = _held.get(s, ball_w)
			print("[fldbg] f %d %s %s keep %s on %s spd %.2f turn %.2f h-fl %.3f lock %s w %.2f step %s off %.3f" % [Engine.get_process_frames(), c.character_id, s,
				keep, on, spd, turn, h - fl, _lock.has(s), w, _stepping.has(s), Vector2(hd.x - ball_w.x, hd.z - ball_w.z).length()])
		if w < 0.001:
			continue
		var held: Vector3 = _held.get(s, ball_w)          # (kept through the fade-out: no snap on release)
		var off := Vector3(held.x - ball_w.x, 0.0, held.z - ball_w.z)
		var shift := off * w                              # (height: the clip's, over the floor)
		if _stepping.has(s):
			# a step: up first, across while it is up, down last - nothing of it drags along the floor
			shift = off * (w * w * (3.0 - 2.0 * w))
			shift.y = clampf(off.length() * 0.25, STEP_UP * 0.6, STEP_UP * 1.6) * sin(PI * (1.0 - w))
		if shift.length() < 0.0005:
			continue
		var foot_t: Vector3 = inv * (gsk * sk.get_bone_global_pose(int(ids[2])).origin + shift)
		if not _two_bone(sk, ids, foot_t) and _lock.has(s) and not _stepping.has(s):
			# out of the leg's reach (her body lurched ahead: breaking into a run) or the leg straight: held on, the
			# stretched leg dragged the foot 7 cm - it lets go and takes a quick lifted step from where it is drawn
			var now_b: Vector3 = gsk * sk.get_bone_global_pose(int(ids[3])).origin
			_lock.erase(s)
			_held[s] = Vector3(now_b.x, ball_w.y, now_b.z)
			_stepping[s] = true
			_quick[s] = true
	_was_on = on


## Upper/lower leg turned so the foot bone lands on `t` (skeleton space), the knee staying on its own side; the foot
## keeps its global rotation (the clip's angle on the ground).
func _two_bone(sk: Skeleton3D, ids: Array, t: Vector3) -> bool:
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
		return false
	var n := (b - a).cross(cc - b)
	if n.length() < 1e-5:
		return false
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
	return at.length() < l1 + l2 + 0.004                 # (false: the foot fell short of `t`)


## A dance or fight deck driving her: their own feet, never locked.
func _deck_on(sk: Skeleton3D) -> bool:
	for n in sk.get_children():
		if (n is DanceDeck or String(n.name).begins_with("FightDeck")) and float(n.get("influence")) > 0.05:
			return true
	return false
