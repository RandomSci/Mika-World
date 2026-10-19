class_name MeleeFighter
extends Node
## Combat v3: one girl's procedural fight body. Her pose is a few numbers (MeleeBook: hips, spine, wrists, ankles,
## elbows, fists) blended between key poses with fast timing curves; FightBody writes the hips / spine / head and
## places four TwoBoneIK3D targets (arms and legs), FightBodyPost makes the fists and lays the feet, TraceFight reads
## the final pose back. Feet stay planted on the ground and step when the body moves away from them; a strike's
## limb can follow a live world point (the other girl's face, or her forearm when she blocks) so it really lands.
## Hit reactions are springs pushed from the blow's direction (the head snaps away from the side it came from).

const ARM_BONES := {"lh": ["LeftUpperArm", "LeftLowerArm", "LeftHand"], "rh": ["RightUpperArm", "RightLowerArm", "RightHand"]}
const LEG_BONES := {"lf": ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], "rf": ["RightUpperLeg", "RightLowerLeg", "RightFoot"]}
const FINGERS := ["Index", "Middle", "Ring", "Little"]
## Her walking / resting helpers would pull a kicking foot back to the ground or push a fist off a face: off while
## the fight rig owns her body (their `active` flag; turned back on in teardown).
const OFF_WHILE_FIGHTING := ["FootGuard", "FootLock", "ClothClearance", "HandGuard", "BodyLanguage"]
const W := 24.0                          # reaction springs: stiffness (rad/s) and damping ratio
const Z := 0.42

var id := ""
var d: FightDirector
var c: WorldCharacter
var sk: Skeleton3D
var k := 1.0                             # her size against Mika's
var P := {}                              # the current pose (MeleeBook keys, scaled to her)
var trace := {}                          # final bone positions (TraceFight)
var traced := 0
var look_at := Vector3.INF               # world point her eyes and head follow
var rig_w := 1.0                         # 1 = this rig, 0 = the clip (knock-down / get-up)
var palm := {"lh": "guard", "rh": "guard"}
var vibrate := false                     # shaken during hit-stop (the one who was hit)
var feet := {}
var strike_limb := ""
var move_tag := ""                       # QA: the move she is in (joint audit faults name it)                    # the limb in a strike (its foot leaves the ground, its fist leads)
var life_t := 0.0

var _segs: Array = []
var _cur := {}
var _dyn := {}                           # limb -> {fn, from, ctrl, e}
var _ids := {}
var _rest := {}
var _ik := {}
var _tgt := {}
var _pole := {}
var _body: FightBody
var _post: FightBodyPost
var _trace: TraceFight
var _sp := {"spine": [Vector3.ZERO, Vector3.ZERO], "head": [Vector3.ZERO, Vector3.ZERO], "hip": [Vector3.ZERO, Vector3.ZERO],
	"lh": [Vector3.ZERO, Vector3.ZERO], "rh": [Vector3.ZERO, Vector3.ZERO]}
var _guard_drop := 0.0
var _ankle_h := 0.148
var _rig := 1.0
var _switched_off: Array = []
var _skim_until := -1.0
var _skim_len := 0.1
var _last_root := Vector3.INF
var _apply_root := Vector3.INF
var last_sink := 0.0                     # QA: how far her hips sank this frame to keep a planted foot in reach
var _root_vel := Vector3.ZERO


static func make(director: FightDirector, who: String) -> MeleeFighter:
	var f := MeleeFighter.new()
	f.name = "MeleeFighter_" + who
	f.id = who
	f.d = director
	f.c = director.F[who].c
	f.sk = f.c.skeleton
	director.add_child(f)
	f._build()
	return f


func _build() -> void:
	k = sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y / 0.955
	_ankle_h = sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin.y
	for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftHand", "RightHand",
			"LeftLowerArm", "RightLowerArm", "LeftUpperArm", "RightUpperArm", "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg",
			"LeftUpperLeg", "RightUpperLeg"]:
		_ids[b] = sk.find_bone(b)
	for s in ["Left", "Right"]:
		for fn in FINGERS:
			for seg in ["Proximal", "Intermediate", "Distal"]:
				_ids[s + fn + seg] = sk.find_bone(s + fn + seg)
		for seg in ["Metacarpal", "Proximal", "Distal"]:
			_ids[s + "Thumb" + seg] = sk.find_bone(s + "Thumb" + seg)
	for b in _ids:
		if int(_ids[b]) >= 0:
			_rest[b] = sk.get_bone_rest(int(_ids[b]))
	# the stack: FightBody, four limb IKs, FightBodyPost, and the reader at the very end
	_body = FightBody.new()
	_body.name = "FightBody"
	_body.fighter = self
	sk.add_child(_body)
	var host := Node3D.new()
	host.name = "MeleeTargets_" + id
	host.top_level = true
	d.add_child(host)
	for limb in ["lh", "rh", "lf", "rf"]:
		var bones: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
		var t := Node3D.new()
		t.name = "T_" + limb
		host.add_child(t)
		var p := Node3D.new()
		p.name = "P_" + limb
		host.add_child(p)
		var ik := TwoBoneIK3D.new()
		ik.name = "FightIK_" + limb
		sk.add_child(ik)
		ik.setting_count = 1
		ik.set_root_bone_name(0, bones[0])
		ik.set_middle_bone_name(0, bones[1])
		ik.set_end_bone_name(0, bones[2])
		ik.set_target_node(0, ik.get_path_to(t))
		ik.set_pole_node(0, ik.get_path_to(p))
		ik.influence = 1.0
		_ik[limb] = ik
		_tgt[limb] = t
		_pole[limb] = p
	_post = FightBodyPost.new()
	_post.name = "FightBodyPost"
	_post.fighter = self
	sk.add_child(_post)
	_trace = TraceFight.new()
	_trace.name = "TraceFight"
	_trace.fighter = self
	sk.add_child(_trace)
	PosePipeline.arrange_for(sk)
	# what would fight the rig: her walking-feet helpers, the hand pushes, the clip's look-at
	for n in OFF_WHILE_FIGHTING:
		var m := sk.get_node_or_null(n) as SkeletonModifier3D
		if m and m.active:
			m.active = false
			_switched_off.append(m)
	if c.head_look:
		c.head_look.influence = 0.0
	_calibrate_stance()
	P = scaled(MeleeBook.GUARD)
	var gx := sk.global_transform
	for side in ["lf", "rf"]:
		var w: Vector3 = gx * Vector3((P[side] as Vector3).x, 0.0, (P[side] as Vector3).z)
		w.y = c.global_position.y
		feet[side] = {"plant": w, "pos": w, "step": {}, "air": false, "free": false}


func teardown() -> void:
	for n in [_body, _post, _trace]:
		if is_instance_valid(n):
			n.queue_free()
	for l in _ik:
		if is_instance_valid(_ik[l]):
			(_ik[l] as Node).queue_free()
	var host := d.get_node_or_null("MeleeTargets_" + id)
	if host:
		host.queue_free()
	for m in _switched_off:
		if is_instance_valid(m):
			(m as SkeletonModifier3D).active = true
	queue_free()


# ------------------------------------------------------------------------------------------------ poses
const STANCE_FRONT := 20.0               # deg: her front knee in the athletic fighting stance
const STANCE_REAR := 27.5                # deg: her rear knee (the weight sits a little back, on it)
var stance_corr := 0.0                    # m added to every hip height so HER front knee sits at STANCE_FRONT
var rise := 0.0                           # m she is up on the ball of her support foot (a high kick)
var quiet_t := 0.0                        # s she has stood still in her stance (no move, no step, no reaction)
var stance_shift := 0.0                   # m her hips sit back (-) / forward (+) so the rear knee sits at STANCE_REAR


## The front foot of the stance (the one further toward the opponent).
func front_leg() -> String:
	return "lf" if float((MeleeBook.GUARD.lf as Vector3).z) >= float((MeleeBook.GUARD.rf as Vector3).z) else "rf"


## Her own legs decide how high her hips sit in the stance: from her skeleton's rest lengths, the guard's foot
## spots and hip turn, the hip height at which each leg bends its stance angle (law of cosines); the lower wins.
func _calibrate_stance() -> void:
	var g: Dictionary = MeleeBook.GUARD
	var H0 := sk.get_bone_global_rest(_ids.Hips).origin
	var rot := Basis.from_euler(_rad(g.hip_rot))
	var best := -INF
	for limb in ["lf", "rf"]:
		var b: Array = LEG_BONES[limb]
		var j := sk.get_bone_global_rest(sk.find_bone(b[0])).origin - H0
		var a := sk.get_bone_global_rest(sk.find_bone(b[0])).origin.distance_to(sk.get_bone_global_rest(sk.find_bone(b[1])).origin)
		var c2 := sk.get_bone_global_rest(sk.find_bone(b[1])).origin.distance_to(sk.get_bone_global_rest(sk.find_bone(b[2])).origin)
		var flex := STANCE_FRONT if limb == front_leg() else STANCE_REAR
		var dstar := sqrt(a * a + c2 * c2 + 2.0 * a * c2 * cos(deg_to_rad(flex)))
		var hip_xz := Vector3((g.hip as Vector3).x, 0.0, (g.hip as Vector3).z) * k
		var jr := rot * j
		var joint_xz := Vector3(H0.x, 0, H0.z) + hip_xz + Vector3(jr.x, 0, jr.z)
		var ank: Vector3 = (g[limb] as Vector3) * k
		var horiz := Vector2(ank.x - joint_xz.x, ank.z - joint_xz.z).length()
		var dv := sqrt(maxf(dstar * dstar - horiz * horiz, 0.01))
		var joint_y := _ankle_h + dv                       # where this leg wants its hip joint
		var hip_y := joint_y - jr.y - H0.y                 # -> the hips offset for it
		best = hip_y if best == -INF else minf(best, hip_y)   # (the lower of the two: neither knee straighter than its angle)
	stance_corr = best - float((g.hip as Vector3).y) * k


## A full pose: the guard with `over` laid on it, every length scaled to her.
func scaled(over: Dictionary) -> Dictionary:
	var out := {}
	for key in MeleeBook.GUARD:
		out[key] = over.get(key, MeleeBook.GUARD[key])
		if out[key] is Vector3 and not (key in ["hip_rot", "spine", "head", "lp", "rp"]):
			out[key] = (out[key] as Vector3) * k
	for key in over:
		if over[key] is Callable:
			out[key] = over[key]
	return out


## Play key poses in order: each {dur, ease, pose (over the guard), dyn {limb: Callable -> world point}, arc {limb:
## Vector3}, start: Callable, end: Callable}. A new play starts from wherever she is now (no reset pose).
func play(segs: Array) -> void:
	_segs = segs.duplicate()
	_cur = {}
	_dyn.clear()
	_next()


func busy() -> bool:
	return not _cur.is_empty()


func _next() -> void:
	for key in ["hip_rot", "spine"]:
		var v: Vector3 = P[key]
		P[key] = Vector3(v.x, wrapf(v.y, -180.0, 180.0), v.z)
	for key in ["lfy", "rfy"]:
		P[key] = wrapf(float(P[key]), -180.0, 180.0)
	if _segs.is_empty():
		_cur = {}
		_dyn.clear()
		if not move_tag.begins_with("react:"):
			move_tag = ""                        # back in her stance (a reaction's tag is the sim's to end)
		return
	var seg: Dictionary = _segs.pop_front()
	var to := scaled(seg.get("pose", {}))
	for limb in seg.get("dyn", {}):
		to[limb] = seg.dyn[limb]
	_cur = {"seg": seg, "t": 0.0, "from": P.duplicate(), "to": to}
	_dyn.clear()
	# a live limb is on its point from this very frame (the frame of impact switches active -> hold)
	var e0 := ease_k(0.0, String(seg.get("ease", "inout")))
	for limb in seg.get("dyn", {}):
		_dyn[limb] = {"fn": seg.dyn[limb], "from": P[limb], "e": e0, "arc": (seg.get("arc", {}).get(limb, Vector3.ZERO) as Vector3) * k}
	if seg.has("start"):
		(seg.start as Callable).call()


static func ease_k(u: float, kind: String) -> float:
	match kind:
		"in":
			return u * u * u
		"out":
			return 1.0 - pow(1.0 - u, 3.0)
		"snap":
			return 1.0 - pow(1.0 - u, 4.5)
		"hold":
			return 1.0
	return u * u * (3.0 - 2.0 * u)


# ------------------------------------------------------------------------------------------------ per frame
func update(dt: float) -> void:
	life_t += dt
	if not _cur.is_empty():
		var seg: Dictionary = _cur.seg
		_cur.t = float(_cur.t) + dt
		var dur := maxf(float(seg.get("dur", 0.1)), 0.001)
		var u := clampf(float(_cur.t) / dur, 0.0, 1.0)
		var e := ease_k(u, String(seg.get("ease", "inout")))
		var from: Dictionary = _cur.from
		var to: Dictionary = _cur.to
		var arc: Dictionary = seg.get("arc", {})
		for key in to:
			var b = to[key]
			if b is Callable:
				_dyn[key] = {"fn": b, "from": from[key], "e": e, "arc": (arc.get(key, Vector3.ZERO) as Vector3) * k}
				continue
			var a = from[key]
			if a is Vector3 and arc.has(key):
				var ctrl: Vector3 = ((a as Vector3) + (b as Vector3)) * 0.5 + (arc[key] as Vector3) * k   # (a curved path)
				P[key] = (a as Vector3).lerp(ctrl, e).lerp(ctrl.lerp(b, e), e)
			elif a is Vector3:
				P[key] = (a as Vector3).lerp(b, e)
			else:
				P[key] = lerpf(float(a), float(b), e)
		if u >= 1.0:
			var end_fn: Callable = seg.get("end", Callable())
			_next()
			if end_fn.is_valid():
				end_fn.call()
	# reaction springs (fight time: hit-stop freezes them)
	for key in _sp:
		var s: Array = _sp[key]
		var acc: Vector3 = -(s[0] as Vector3) * W * W - (s[1] as Vector3) * 2.0 * Z * W
		s[1] = (s[1] as Vector3) + acc * dt
		s[0] = (s[0] as Vector3) + (s[1] as Vector3) * dt
	_guard_drop = maxf(_guard_drop - dt / 0.3, 0.0)
	var still := move_tag == "" and _cur.is_empty() and _root_vel.length() < 0.2 and rs_hip_len() < 0.02
	for side in feet:
		if not (feet[side].step as Dictionary).is_empty() or bool(feet[side].air):
			still = false
	quiet_t = quiet_t + dt if still else 0.0
	# the stance holds its knees at STANCE_FRONT / STANCE_REAR: in a quiet stance frame, measure both knees on the
	# final pose; the front knee moves the hips up / down, the rear-front difference moves them back / forward (a slow
	# loop; every pose is an offset from the stance)
	if move_tag == "" and _cur.is_empty() and dt > 0.0005 and traced > 3 and rs_hip_len() < 0.01:
		var quiet := true
		for side in feet:
			if not (feet[side].step as Dictionary).is_empty() or bool(feet[side].air):
				quiet = false
		if quiet:
			var fl := front_leg()
			var bf := bend_of(fl)
			var br := bend_of("rf" if fl == "lf" else "lf")
			stance_corr = clampf(stance_corr + (bf - STANCE_FRONT) * 0.0006 * k, -0.16, 0.06)
			stance_shift = clampf(stance_shift + ((br - bf) - (STANCE_REAR - STANCE_FRONT)) * 0.0004 * k, -0.08 * k, 0.04 * k)
	_rig = move_toward(_rig, rig_w, dt / 0.15)
	_body.influence = _rig
	_post.influence = _rig
	for l in _ik:
		(_ik[l] as TwoBoneIK3D).influence = _rig
	_feet(dt)
	if c.get("_head_target") and look_at != Vector3.INF:
		(c._head_target as Node3D).global_position = look_at


## Both feet off the ground for `dur` s of fight time (a back step, a side step, a dash: the body travels faster than
## steps can follow - she skims, the feet low and trailing, and lands with both).
func skim(dur: float) -> void:
	_skim_until = life_t + dur
	_skim_len = maxf(dur, 0.01)


## Plant both feet where her stance puts them now (after she was placed somewhere new).
func replant() -> void:
	var gx := sk.global_transform
	for side in ["lf", "rf"]:
		var w: Vector3 = gx * Vector3((P[side] as Vector3).x, 0.0, (P[side] as Vector3).z)
		w.y = c.global_position.y - float(d.F[id].lift)
		feet[side] = {"plant": w, "pos": w, "step": {}, "air": false, "free": false}
	_last_root = gx.origin
	quiet_t = 0.0


## A blow from world direction `dir` (where it travels): the head snaps away, the spine gives, the hips are shoved,
## the guard drops. power 0..1. `where`: high / mid / low.
func react(dir: Vector3, where: String, power: float) -> void:
	var l := sk.global_transform.basis.inverse() * dir
	l.y = 0.0
	l = l.normalized()
	var v := 760.0 * power
	if where == "high":
		_kick("head", Vector3(l.z * v * 0.9, l.x * v, -l.x * v * 0.55))
		_kick("spine", Vector3(l.z * v * 0.35, l.x * v * 0.4, -l.x * v * 0.3))
	else:
		_kick("spine", Vector3(v * 0.8, l.x * v * 0.5, -l.x * v * 0.3))
		_kick("head", Vector3(v * 0.5, l.x * v * 0.3, 0.0))
	_kick("hip", l * 1.6 * power)
	_guard_drop = minf(1.0, 0.45 + power * 0.6)


## A blocked blow: the arms and body take a small shove.
func absorb(dir: Vector3, arm: String, power: float) -> void:
	var l := sk.global_transform.basis.inverse() * dir
	l.y = 0.0
	l = l.normalized()
	_kick("spine", Vector3(l.z * 180.0 * power, l.x * 160.0 * power, 0.0))
	_kick("hip", l * 0.7 * power)
	for a in (["lh", "rh"] if arm == "both" else [arm]):
		if _sp.has(a):
			_kick(a, l * 1.4 * power)


func _kick(key: String, vel: Vector3) -> void:
	_sp[key][1] = (_sp[key][1] as Vector3) + vel


func _feet(dt: float) -> void:
	var gx := sk.global_transform
	var lift := float(d.F[id].lift)
	var gy := c.global_position.y - lift
	if _last_root != Vector3.INF and (gx.origin - _last_root).length() > 0.6:
		replant()                                     # (she was placed somewhere new: her feet go with her)
		return
	if _last_root != Vector3.INF and dt > 0.0005:
		var v := (gx.origin - _last_root) / dt
		v.y = 0.0
		_root_vel = _root_vel.lerp(v, 0.35)
	_last_root = gx.origin
	var skimming := life_t < _skim_until
	var stepping := false
	for side in feet:
		var st0: Dictionary = feet[side].step
		if not st0.is_empty() and float(st0.t) / float(st0.dur) < 0.5:
			stepping = true                          # (the other foot may start once this one is half way)
	for side in ["lf", "rf"]:
		var ft: Dictionary = feet[side]
		var wl: Vector3 = P[side]
		var ww: Vector3 = gx * Vector3(wl.x, 0.0, wl.z)
		ww.y = gy
		var air: bool = wl.y > 0.03 * k or lift > 0.03 or bool(ft.free) or skimming
		if air:
			var sk_h := 0.0
			if skimming:
				var u := 1.0 - (_skim_until - life_t) / _skim_len
				sk_h = sin(PI * clampf(u, 0.0, 1.0)) * (0.05 if side == "lf" else 0.07) * k
			ft.pos = ww + Vector3(0, wl.y + lift + sk_h, 0)
			ft.plant = ww
			ft.step = {}
			ft.air = true
			continue
		if ft.air:
			ft.air = false
			ft.plant = ww
			ft.pos = ww
			continue
		var st: Dictionary = ft.step
		if not st.is_empty():
			st.t = float(st.t) + dt
			var u := clampf(float(st.t) / float(st.dur), 0.0, 1.0)
			var to: Vector3 = ww + (st.get("lead", Vector3.ZERO) as Vector3)       # (lands where the body is going)
			var e := ease_k(u, "inout")
			ft.pos = (st.from as Vector3).lerp(to, e) + Vector3(0, sin(PI * u) * float(st.h), 0)
			if u >= 1.0:
				ft.plant = to
				ft.pos = to
				ft.step = {}
			continue
		var ahead := ww + _root_vel * 0.12                  # (where her body will be when a step would land)
		var off := Vector3(ahead.x - (ft.plant as Vector3).x, 0, ahead.z - (ft.plant as Vector3).z).length()
		ft.urgent = bool(ft.get("reach", false))
		if bool(ft.urgent):
			off = maxf(off, 0.2 * k)                     # (the body left it behind: it steps now, never locks the knee)
		ft.reach = false
		var thr := 0.11 * k
		if move_tag == "" and _root_vel.length() < 0.2:
			thr = 0.035 * k                              # (a quiet stance: small settling steps keep her feet on their spots)
			# near a straight leg a 2 cm slip is 10 deg of knee: a foot whose knee is off its stance angle and that
			# is off its spot at all settles too
			var want := STANCE_FRONT if side == front_leg() else STANCE_REAR
			if traced > 3 and absf(bend_of(side) - want) > 5.0 and off > 0.012 * k:
				off = maxf(off, thr + 0.001)
		if off > thr and (not stepping or bool(ft.get("urgent", false)) or _root_vel.length() > 0.9):
			var dur := clampf(off / 2.6, 0.07, 0.15)
			ft.step = {"from": ft.plant, "t": 0.0, "dur": dur, "h": clampf(off * 0.25, 0.025, 0.08), "lead": _root_vel * dur * 0.7}
			stepping = true
		ft.pos = Vector3((ft.plant as Vector3).x, gy, (ft.plant as Vector3).z)


# ------------------------------------------------------------------------------------------------ the pose stages
## FightBody: hips, spine, shoulders, head; the four IK targets.
func apply(s: Skeleton3D) -> void:
	var gx := s.global_transform
	var inv := gx.affine_inverse()
	if _apply_root != Vector3.INF and (gx.origin - _apply_root).length() > 0.6:
		replant()                                     # (placed somewhere new this frame: her feet go with her)
	_apply_root = gx.origin
	for limb in _dyn:
		var dy: Dictionary = _dyn[limb]
		var bl: Vector3 = inv * ((dy.fn as Callable).call() as Vector3)
		var a: Vector3 = dy.from
		var e: float = dy.e
		var ctrl: Vector3 = (a + bl) * 0.5 + (dy.arc as Vector3)
		P[limb] = a.lerp(ctrl, e).lerp(ctrl.lerp(bl, e), e)
	var bob := sin(life_t * TAU * 1.7) * 0.0025 * k
	var hip_off: Vector3 = (P.hip as Vector3) + (_sp.hip[0] as Vector3) + Vector3(0, bob + stance_corr, stance_shift)
	if vibrate and d._freeze > 0:
		hip_off.x += (0.012 if Engine.get_frames_drawn() % 2 == 0 else -0.012) * k
	var hi: int = _ids.Hips
	var rest_h: Transform3D = _rest.Hips
	s.set_bone_pose_position(hi, rest_h.origin + hip_off)
	s.set_bone_pose_rotation(hi, rest_h.basis.get_rotation_quaternion() * _q(P.hip_rot as Vector3))
	# a high kick: when the kicking foot's point is above what her leg reaches from here, she rises onto the ball of
	# her support foot (the heel lifts, up to 7 cm) - the hips go up with it
	var want_rise := 0.0
	if strike_limb in ["lf", "rf"] and _dyn.has(strike_limb):
		var tl: Vector3 = P[strike_limb]
		var hj0 := s.get_bone_global_pose(_ids[LEG_BONES[strike_limb][0]]).origin
		var lmax := limb_len(strike_limb) * 0.99
		var hz := Vector2(tl.x - hj0.x, tl.z - hj0.z).length()
		var dy := tl.y - hj0.y
		if (tl - hj0).length() > lmax and dy > 0.0:
			want_rise = dy - sqrt(maxf(lmax * lmax - hz * hz, 0.0)) if hz < lmax else dy
			want_rise = clampf(want_rise, 0.0, 0.07 * k)
	rise = move_toward(rise, want_rise, 1.8 * k * maxf(get_process_delta_time(), 0.001))
	if rise > 0.0005:
		s.set_bone_pose_position(hi, s.get_bone_pose_position(hi) + Vector3(0, rise, 0))
	# balance: a planted foot never ends beyond her reach - she sinks onto the leg (hips lower, up to 8 cm) rather
	# than lock the knee
	var sink := 0.0
	for limb in ["lf", "rf"]:
		if limb == strike_limb or bool(feet[limb].air):
			continue
		var ank_l: Vector3 = inv * ((feet[limb].pos as Vector3) + Vector3(0, _ankle_h + rise, 0))
		var hj := s.get_bone_global_pose(_ids[LEG_BONES[limb][0]]).origin
		var dm := reach_max(limb) * 0.995
		var v := hj - ank_l
		if v.length() > dm:
			var h2 := v.x * v.x + v.z * v.z
			sink = maxf(sink, v.y - sqrt(maxf(dm * dm - h2, 0.0)))
	if sink > 0.0:
		sink = minf(sink, 0.08 * k)
		s.set_bone_pose_position(hi, s.get_bone_pose_position(hi) - Vector3(0, sink, 0))
	last_sink = sink
	var sp: Vector3 = P.spine
	var chest_a := Vector3.ZERO
	var fr := {"Spine": 0.3, "Chest": 0.3, "UpperChest": 0.4}
	for b in fr:
		var bi: int = _ids[b]
		s.set_bone_pose_rotation(bi, (_rest[b] as Transform3D).basis.get_rotation_quaternion() * _q(sp * float(fr[b])))
	chest_a = s.get_bone_global_pose(_ids.UpperChest).origin
	var rsp: Vector3 = _sp.spine[0]
	var fr2 := {"Spine": 0.2, "Chest": 0.3, "UpperChest": 0.5}
	for b in fr2:
		var bi2: int = _ids[b]
		s.set_bone_pose_rotation(bi2, s.get_bone_pose_rotation(bi2) * _q(rsp * float(fr2[b])))
	var chest_b := s.get_bone_global_pose(_ids.UpperChest).origin
	var lean := chest_b - chest_a
	# shoulders forward on a strike
	for side in ["Left", "Right"]:
		var amt := float(P.lsh if side == "Left" else P.rsh)
		if absf(amt) > 0.1:
			var bi3: int = _ids[side + "Shoulder"]
			var g := s.get_bone_global_pose(bi3)
			var q := Quaternion(Vector3.UP, deg_to_rad(-amt if side == "Left" else amt))
			s.set_bone_global_pose(bi3, Transform3D(Basis(q) * g.basis, g.origin))
	# the head and neck follow her opponent, plus the snap of a blow
	if look_at != Vector3.INF:
		var tl: Vector3 = inv * look_at
		for pair in [["Neck", 0.4], ["Head", 1.0]]:
			var bi4: int = _ids[pair[0]]
			var g2 := s.get_bone_global_pose(bi4)
			var cur := g2.basis.z.normalized()
			var want := (tl - g2.origin).normalized()
			var ang := cur.angle_to(want)
			if ang > 0.001:
				var axis := cur.cross(want).normalized()
				if axis.length() > 0.5:
					var turn := minf(ang, deg_to_rad(60.0)) * float(pair[1])
					s.set_bone_global_pose(bi4, Transform3D(Basis(axis, turn) * g2.basis, g2.origin))
	var hd: int = _ids.Head
	s.set_bone_pose_rotation(hd, s.get_bone_pose_rotation(hd) * _q((P.head as Vector3) + (_sp.head[0] as Vector3)))
	# the IK targets
	# a hand that is not striking stays where it is ON HER BODY: hand targets are authored for the guard's torso and
	# carried by how her hips and spine turn, lean and drop from it (a spin takes the guard round with her, a deep
	# lean takes it down with her chest); a pose may pin them to the ground frame instead ("hands": "root")
	var g_rot := Basis.from_euler(_rad(MeleeBook.GUARD.hip_rot)) * Basis.from_euler(_rad(MeleeBook.GUARD.spine))
	var n_rot := Basis.from_euler(_rad(P.hip_rot)) * Basis.from_euler(_rad(P.spine))
	var carry := n_rot * g_rot.inverse()
	var pivot_g: Vector3 = rest_h.origin + (MeleeBook.GUARD.hip as Vector3) * k
	var pivot_n: Vector3 = rest_h.origin + hip_off
	var root_hands := String(_cur.get("seg", {}).get("pose", {}).get("hands", "")) == "root"
	for limb in ["lh", "rh"]:
		var at: Vector3 = P[limb]
		if not _dyn.has(limb):
			if not root_hands:
				at = pivot_n + carry * (at - pivot_g)
			at += lean + Vector3(0, -0.22, -0.04) * _guard_drop * k + (_sp[limb][0] as Vector3)
			if limb != strike_limb:
				at.y += bob * 0.6
		var sh := s.get_bone_global_pose(_ids[ARM_BONES[limb][0]]).origin
		var pd: Vector3 = (P.lp if limb == "lh" else P.rp)
		var cb := s.get_bone_global_pose(_ids.UpperChest).basis.orthonormalized()
		var pole := (sh + at) * 0.5 + (cb * pd).normalized() * 0.4 * k     # (the elbow's way in HER chest's frame: it turns with her)
		(_tgt[limb] as Node3D).global_position = gx * at
		(_pole[limb] as Node3D).global_position = gx * pole
	for limb in ["lf", "rf"]:
		var ft: Dictionary = feet[limb]
		var ankle: Vector3 = (ft.pos as Vector3) + Vector3(0, _ankle_h, 0)
		if limb != strike_limb and not bool(ft.air):
			ankle.y += rise                             # (up on the ball of the support foot)
		if _dyn.has(limb):
			ankle = gx * (P[limb] as Vector3)
		var al: Vector3 = inv * ankle
		var hipj := s.get_bone_global_pose(_ids[LEG_BONES[limb][0]]).origin
		# a planted foot the body was shoved away from (a hit, a block, a knock-back) skids along the ground after
		# it - the sole stays down and the knee keeps its bend - until the step it triggers lands
		if limb != strike_limb and not _dyn.has(limb) and not bool(ft.air):
			var dsk := reach_max(limb) * 0.99
			var vv := al - hipj
			if vv.length() > dsk:
				var hz := Vector2(vv.x, vv.z)
				var allow := sqrt(maxf(dsk * dsk - vv.y * vv.y, 0.0))
				if hz.length() > 0.0001 and allow > 0.0:
					var nh := hz.normalized() * allow
					var al2 := Vector3(hipj.x + nh.x, al.y, hipj.z + nh.y)
					var w2: Vector3 = gx * al2
					ft.pos = Vector3(w2.x, (ft.pos as Vector3).y, w2.z)
					if (ft.step as Dictionary).is_empty():
						ft.plant = ft.pos
					else:
						ft.step.from = ft.pos
					al = al2
					ankle = gx * al
					feet[limb].reach = true                 # (and a step follows on the next frame)
		# never further than the leg can reach with its knee still bent MIN_FLEX deg: a planted foot left behind by
		# the body is held at that reach (the heel rises) and steps on the next frame; a kick reaches fully
		var dmax := reach_max(limb) if limb != strike_limb else limb_len(limb) * 0.995
		reach_ratio[limb] = (al - hipj).length() / limb_len(limb)
		var want_l: Vector3 = P[limb]
		var spot_off := Vector2(al.x - want_l.x, al.z - want_l.z).length()
		if limb != strike_limb and (al - hipj).length() > dmax * 0.998 and spot_off > 0.03 * k:
			feet[limb].reach = true                     # (at the limit AND off its spot: a step brings it back under her)
		if (al - hipj).length() > dmax:
			al = hipj + (al - hipj).normalized() * dmax
			ankle = gx * al
			if limb != strike_limb and spot_off > 0.03 * k:
				feet[limb].reach = true
		# the knee bends like a human's: forward of the hip-ankle line in HER pelvis frame, over her toes (the knee
		# hinge is the pelvis's left-right axis turned with the foot); a straight-up leg gets its knee up, a back
		# kick its knee down - never backwards
		var knee := (hipj + al) * 0.5 + knee_dir(s, limb, al - hipj) * 0.5 * k
		(_tgt[limb] as Node3D).global_position = ankle
		(_pole[limb] as Node3D).global_position = gx * knee


## FightBodyPost: the hands (fist or open, the knuckles leading) and the feet (flat, heel up, or pointed in a kick).
func post(s: Skeleton3D) -> void:
	if _hinge.is_empty():
		_hinges(s)
	for limb in ["lf", "rf", "lh", "rh"]:
		_fix_twist(s, limb)
	for side in ["Left", "Right"]:
		var limb := "lh" if side == "Left" else "rh"
		var hi: int = _ids[side + "Hand"]
		var hg := s.get_bone_global_pose(hi)
		var lg := s.get_bone_global_pose(_ids[side + "LowerArm"])
		var y := (hg.origin - lg.origin).normalized()
		var sgn := 1.0 if side == "Left" else -1.0
		var pn := Vector3(-0.75 * sgn, 0.0, -0.55)                    # the guard: fists upright, palms in toward her face
		match String(palm[limb]):
			"down":
				pn = Vector3.DOWN
			"in":
				pn = Vector3(-sgn, -0.2, 0.0)
			"back":
				pn = Vector3(0, 0.1, -1.0)
			"fwd":
				pn = y
				y = (Vector3.UP * 0.85 + y * 0.15).normalized()
		var z := (pn - y * pn.dot(y))
		if z.length() > 0.05:
			z = z.normalized()
			var b := Basis(y.cross(z), y, z).orthonormalized()
			var q := hg.basis.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), 0.9)
			s.set_bone_global_pose(hi, Transform3D(Basis(q), hg.origin))
		var fist := float(P.lfist if side == "Left" else P.rfist)
		var curl := [lerpf(8.0, 82.0, fist), lerpf(10.0, 98.0, fist), lerpf(6.0, 62.0, fist)]
		for fn in FINGERS:
			var segs := ["Proximal", "Intermediate", "Distal"]
			for i in 3:
				var nm: String = side + fn + segs[i]
				var bi: int = _ids.get(nm, -1)
				if bi >= 0:
					s.set_bone_pose_rotation(bi, (_rest[nm] as Transform3D).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, deg_to_rad(float(curl[i]))))
		for i2 in 3:
			var segs2 := ["Metacarpal", "Proximal", "Distal"]
			var nm2: String = side + "Thumb" + segs2[i2]
			var bi2: int = _ids.get(nm2, -1)
			if bi2 >= 0:
				s.set_bone_pose_rotation(bi2, (_rest[nm2] as Transform3D).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, deg_to_rad(lerpf(4.0, 28.0, fist) * (1.0 if i2 > 0 else 0.5))))
	for limb in ["lf", "rf"]:
		var side2 := "Left" if limb == "lf" else "Right"
		var fi: int = _ids[side2 + "Foot"]
		var fg := s.get_bone_global_pose(fi)
		var yaw := deg_to_rad(foot_yaw(limb))
		var pitch := deg_to_rad(float(P.lfp if limb == "lf" else P.rfp))
		if limb != strike_limb and not bool(feet[limb].air) and rise > 0.002:
			pitch += asin(clampf(rise / (0.14 * k), 0.0, 0.9))        # (heel up, the ball stays down)
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		var yv := (fwd * cos(pitch) - Vector3.UP * sin(pitch)).normalized()
		var up := (Vector3.UP * cos(pitch) + fwd * sin(pitch)).normalized()
		if limb == strike_limb or bool(feet[limb].air):
			var shin := (fg.origin - s.get_bone_global_pose(_ids[side2 + "LowerLeg"]).origin).normalized()
			var w := 0.85 if limb == strike_limb else 0.4
			yv = yv.lerp(shin, w).normalized()
			up = (up - yv * up.dot(yv)).normalized()
		var fb := Basis(yv.cross(up), yv, up).orthonormalized()
		s.set_bone_global_pose(fi, Transform3D(fb, fg.origin))
	_land(s)


## The last few cm of a punch: the IK put the WRIST on its target, but the knuckles sit wherever the wrist and
## fingers put them - two CCD passes (elbow about its hinge, then the shoulder) bring the real front of the fist
## onto the contact point, eased in over the end of the strike.
var land_at := {}                         # limb -> world contact point of the strike (set by the sim each frame)


func _land(s: Skeleton3D) -> void:
	if not (strike_limb in ["lh", "rh"]) or not _dyn.has(strike_limb) or not land_at.has(strike_limb):
		return
	var w := smoothstep(0.8, 1.0, float(_dyn[strike_limb].e))
	if w <= 0.0:
		return
	var side := "Left" if strike_limb == "lh" else "Right"
	var tgt: Vector3 = s.global_transform.affine_inverse() * (land_at[strike_limb] as Vector3)
	var ui: int = _ids[side + "UpperArm"]
	var li: int = _ids[side + "LowerArm"]
	var hi: int = _ids[side + "Hand"]
	var mi: int = _ids.get(side + "MiddleProximal", -1)
	if mi < 0:
		return
	for it in 2:
		for j in [li, ui]:
			var hp := s.get_bone_global_pose(hi).origin
			var mp := s.get_bone_global_pose(mi).origin
			var fist := mp + (mp - hp).normalized() * 0.03
			var jg := s.get_bone_global_pose(j)
			var a := fist - jg.origin
			var b := tgt - jg.origin
			if j == li:
				var ax := (jg.basis.orthonormalized() * (_hinge[strike_limb][1] as Vector3)).normalized()
				a -= ax * a.dot(ax)
				b -= ax * b.dot(ax)
				if a.length() < 0.01 or b.length() < 0.01:
					continue
				var ang := clampf(a.signed_angle_to(b, ax), -0.35, 0.35) * w
				s.set_bone_global_pose(j, Transform3D(Basis(ax, ang) * jg.basis, jg.origin))
			else:
				if a.length() < 0.01 or b.length() < 0.01:
					continue
				var q := Quaternion(a.normalized(), b.normalized())
				var ang2 := minf(q.get_angle(), 0.35) * w
				if ang2 > 0.0005:
					s.set_bone_global_pose(j, Transform3D(Basis(q.get_axis().normalized(), ang2) * jg.basis, jg.origin))


## Which way her knee must point for the hip -> ankle line `u` (skeleton space): u x hinge, the hinge being the
## pelvis's left axis turned by how far the foot is turned from the pelvis.
func knee_dir(s: Skeleton3D, limb: String, u: Vector3) -> Vector3:
	var hb := s.get_bone_global_pose(_ids.Hips).basis.orthonormalized()
	var rel := deg_to_rad(foot_yaw(limb) - float((P.hip_rot as Vector3).y))
	var h := (hb * (Basis(Vector3.UP, rel) * Vector3(1, 0, 0))).normalized()
	var b := u.normalized().cross(h)
	if b.length() < 0.05:
		b = hb * Vector3(0, 0, 1)
	return b.normalized()


## Where her foot points (deg, skeleton space): the pose's foot yaw, but never further from her pelvis than a hip
## can turn (left leg: 35 in / 50 out, right leg mirrored) - so a planted support foot PIVOTS with her hips in a
## kick, and a knee always sits over its toes.
func foot_yaw(limb: String) -> float:
	var hy := float((P.hip_rot as Vector3).y)
	var raw := float(P.lfy if limb == "lf" else P.rfy)
	var rel := wrapf(raw - hy, -180.0, 180.0)
	if limb == "lf":
		rel = clampf(rel, -35.0, 50.0)
	else:
		rel = clampf(rel, -50.0, 35.0)
	return hy + rel


## The hinge of each knee / elbow in its two bones' own frames, from the T-pose: a knee folds about her left axis
## (+X), the left elbow about -Y, the right elbow about +Y (thigh x shin, upper arm x forearm on a human bend).
var _hinge := {}


func _hinges(s: Skeleton3D) -> void:
	var defs := {"lf": [LEG_BONES.lf, Vector3(1, 0, 0)], "rf": [LEG_BONES.rf, Vector3(1, 0, 0)],
		"lh": [ARM_BONES.lh, Vector3(0, -1, 0)], "rh": [ARM_BONES.rh, Vector3(0, 1, 0)]}
	for limb in defs:
		var bones: Array = defs[limb][0]
		var hs: Vector3 = defs[limb][1]
		var out := []
		for i in 2:
			var rb := s.get_bone_global_rest(s.find_bone(bones[i])).basis.orthonormalized()
			out.append(rb.inverse() * hs)
		_hinge[limb] = out


## After the IK: turn the upper bone about its own axis so its knee / elbow hinge lies across the bend the IK made,
## then the lower bone about its axis the same way (the end stays where the IK put it). The crease of the knee or
## elbow then always folds the human way - an IK alone sets where the joint is, never which way the limb faces.
const TWIST_LIMIT := {"lh": 100.0, "rh": 100.0, "lf": 60.0, "rf": 60.0}     # shoulder / hip rotation about the bone (deg)


## How far the upper bone (upper arm / thigh) is turned about its own axis away from the plain swing out of her
## T-pose, measured in its parent's frame (the shoulder / pelvis) - the anatomical twist, whatever the clip did.
func anat_twist(s: Skeleton3D, limb: String) -> float:
	var bones: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
	var bi: int = _ids[bones[0]]
	var par := s.get_bone_parent(bi)
	var pb := s.get_bone_global_pose(par).basis.orthonormalized()
	var rb := s.get_bone_global_pose(bi).basis.orthonormalized()
	var rel_now := pb.inverse() * rb
	var rel_rest := s.get_bone_global_rest(par).basis.orthonormalized().inverse() * s.get_bone_global_rest(bi).basis.orthonormalized()
	var a0 := (rel_rest * Vector3.UP).normalized()
	var a1 := (rel_now * Vector3.UP).normalized()
	var q := Quaternion(rel_now) * Quaternion(rel_rest).inverse()
	var sw := Quaternion(a0, a1) if a0.dot(a1) > -0.999 else Quaternion(a0.cross(Vector3.RIGHT).normalized(), PI)
	var tw := sw.inverse() * q
	var ang := 2.0 * atan2(Vector3(tw.x, tw.y, tw.z).dot(a0), tw.w)
	return rad_to_deg(wrapf(ang, -PI, PI))


func _fix_twist(s: Skeleton3D, limb: String) -> void:
	_align_hinge(s, limb)
	# a bend the shoulder / hip cannot make: swing the whole limb about its root -> end line (the end stays put)
	# until the twist is inside the human range, then line the hinge up again
	var lim: float = TWIST_LIMIT[limb] - 4.0
	var bones: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
	var ri: int = _ids[bones[0]]
	var u := (s.get_bone_global_pose(_ids[bones[2]]).origin - s.get_bone_global_pose(ri).origin).normalized()
	var tau := anat_twist(s, limb)
	if absf(tau) > lim:
		# measure how the twist answers a small swing of the limb about the line, then step there (Newton, 4 steps)
		var d0 := 0.12
		_swing(s, ri, u, d0, limb)
		var tau1 := anat_twist(s, limb)
		var slope := wrapf(tau1 - tau, -180.0, 180.0) / rad_to_deg(d0)
		tau = tau1
		for i in 4:
			if absf(tau) <= lim or absf(slope) < 0.15:
				break
			var want := clampf(tau, -lim, lim)
			var phi := deg_to_rad(wrapf(want - tau, -180.0, 180.0) / slope)
			_swing(s, ri, u, phi, limb)
			var tau2 := anat_twist(s, limb)
			if absf(phi) > 0.001:
				slope = clampf(wrapf(tau2 - tau, -180.0, 180.0) / rad_to_deg(phi), -3.0, 3.0)
			tau = tau2
	if absf(tau) > lim or _knee_behind(s, limb):
		_scan_swing(s, limb, ri, u, lim)
	twist[limb] = anat_twist(s, limb)


## How bad the limb is now: degrees of twist past the limit, plus a big penalty for a knee pointing behind her.
func _limb_cost(s: Skeleton3D, limb: String, lim: float) -> float:
	return maxf(absf(anat_twist(s, limb)) - lim, 0.0) + (200.0 if _knee_behind(s, limb) else 0.0)


func _knee_behind(s: Skeleton3D, limb: String) -> bool:
	if not (limb in ["lf", "rf"]):
		return false
	var b: Array = LEG_BONES[limb]
	var R := s.get_bone_global_pose(_ids[b[0]]).origin
	var M := s.get_bone_global_pose(_ids[b[1]]).origin
	var E := s.get_bone_global_pose(_ids[b[2]]).origin
	var line := E - R
	var off := M - (R + line * 0.5)
	off -= line.normalized() * off.dot(line.normalized())
	return off.length() > 0.004 and off.normalized().dot(knee_dir(s, limb, line)) < 0.0


## Try the whole swing circle (10 deg steps) about the root -> end line and keep the most human one (the end stays).
func _scan_swing(s: Skeleton3D, limb: String, ri: int, u: Vector3, lim: float) -> void:
	var bones: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
	var mi: int = _ids[bones[1]]
	var q0 := s.get_bone_pose_rotation(ri)
	var q1 := s.get_bone_pose_rotation(mi)
	var best := 0.0
	var best_c := _limb_cost(s, limb, lim)
	for i in range(1, 36):
		var phi := deg_to_rad(float(i) * 10.0 - (360.0 if i > 18 else 0.0))
		s.set_bone_pose_rotation(ri, q0)
		s.set_bone_pose_rotation(mi, q1)
		_swing(s, ri, u, phi, limb)
		var cst := _limb_cost(s, limb, lim)
		if cst < best_c - 0.01 or (absf(cst - best_c) <= 0.01 and absf(phi) < absf(best)):
			best_c = cst
			best = phi
	s.set_bone_pose_rotation(ri, q0)
	s.set_bone_pose_rotation(mi, q1)
	if best != 0.0:
		_swing(s, ri, u, best, limb)


func _swing(s: Skeleton3D, ri: int, u: Vector3, phi: float, limb: String) -> void:
	var R := s.get_bone_global_pose(ri)
	s.set_bone_global_pose(ri, Transform3D(Basis(u, phi) * R.basis, R.origin))
	_align_hinge(s, limb)


func _align_hinge(s: Skeleton3D, limb: String) -> void:
	var bones: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
	var ri: int = _ids[bones[0]]
	var mi: int = _ids[bones[1]]
	var ei: int = _ids[bones[2]]
	var R := s.get_bone_global_pose(ri)
	var M := s.get_bone_global_pose(mi)
	var E := s.get_bone_global_pose(ei)
	var up := M.origin - R.origin
	var fo := E.origin - M.origin
	var n := up.cross(fo)
	if n.length() < 0.06 * up.length() * fo.length():
		return                                            # (nearly straight: no bend to line up with)
	n = n.normalized()
	var ax := up.normalized()
	var h := R.basis.orthonormalized() * (_hinge[limb][0] as Vector3)
	var ang := (h - ax * h.dot(ax)).signed_angle_to(n - ax * n.dot(ax), ax)
	if absf(ang) > 0.002:
		s.set_bone_global_pose(ri, Transform3D(Basis(ax, ang) * R.basis, R.origin))
	var ax2 := fo.normalized()
	var mb := M.basis
	var h2 := mb.orthonormalized() * (_hinge[limb][1] as Vector3)
	var ang2 := (h2 - ax2 * h2.dot(ax2)).signed_angle_to(n - ax2 * n.dot(ax2), ax2)
	s.set_bone_global_pose(mi, Transform3D(Basis(ax2, ang2) * mb, M.origin))


## QA, every frame on the final pose: does any knee or elbow fold backwards? (bend > 8 deg and the fold against
## its bone's own hinge, or a knee pointing behind her pelvis). Returns the faults this frame.
var joint_faults: Array = []
var twist := {"lf": 0.0, "rf": 0.0, "lh": 0.0, "rh": 0.0}
var joint_frames := 0
var frames_by_pose := {}                  # QA: audited frames per kind of pose (stance / move / guard / react:...)


var audit_hold := 0                       # frames the audit skips: a test harness is placing her by hand


func audit(s: Skeleton3D) -> void:
	if audit_hold > 0:
		audit_hold -= 1
		return
	if _hinge.is_empty() or life_t < 0.5:
		return
	joint_frames += 1
	var kind := "stance" if move_tag == "" else move_tag.get_slice(":", 0)
	if move_tag.begins_with("react:"):
		kind = "react:" + move_tag.get_slice(":", 1).get_slice("_", 0)       # (react:high / mid / low / knockdown)
	elif move_tag != "" and not move_tag.contains(":"):
		kind = "strike"
	if rig_w < 0.5:
		kind += " (clip)"
	frames_by_pose[kind] = int(frames_by_pose.get(kind, 0)) + 1
	for limb in ["lf", "rf", "lh", "rh"]:
		var bones: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
		var R := s.get_bone_global_pose(_ids[bones[0]])
		var M := s.get_bone_global_pose(_ids[bones[1]])
		var E := s.get_bone_global_pose(_ids[bones[2]])
		var up := M.origin - R.origin
		var fo := E.origin - M.origin
		var bend := rad_to_deg(up.angle_to(fo))
		var leg: bool = limb in ["lf", "rf"]
		var planted: bool = leg and not bool(feet[limb].air) and limb != strike_limb
		if planted and float(reach_ratio[limb]) > 1.0:
			_fault(limb, "foot target %.0f%% of her leg away from the hip (out of reach)" % (100.0 * float(reach_ratio[limb])), bend)
		if planted and bend < MIN_FLEX - 0.5:
			_fault(limb, "knee locked straight (%.1f deg)" % bend, bend)
			continue
		if leg and planted and quiet_t > 0.3:              # (standing in her stance - after the settling steps)
			var want := STANCE_FRONT if limb == front_leg() else STANCE_REAR
			if absf(bend - want) > 8.0:
				_fault(limb, "stance knee %.0f deg (%.0f-%.0f)" % [bend, want - 8.0, want + 8.0], bend)
		if bend < 3.0:
			continue
		var n := up.cross(fo).normalized()
		var h := (R.basis.orthonormalized() * (_hinge[limb][0] as Vector3)).normalized()
		var bad := n.dot(h) < -0.2
		var why := "folds against its hinge (%.0f deg)" % bend
		if not bad and leg:
			var kd := knee_dir(s, limb, E.origin - R.origin)
			var off := M.origin - (R.origin + (E.origin - R.origin) * 0.5)
			off -= (E.origin - R.origin).normalized() * off.dot((E.origin - R.origin).normalized())
			if off.length() > 0.004 and off.normalized().dot(kd) < 0.0:
				bad = true
				why = "shin angled behind the knee - knee points behind her (%.0f deg)" % bend
		if not bad and absf(float(twist[limb])) > float(TWIST_LIMIT[limb]) + 6.0:
			bad = true
			why = "%s turned %.0f deg about itself (human limit %.0f)" % ["thigh" if limb in ["lf", "rf"] else "upper arm", float(twist[limb]), float(TWIST_LIMIT[limb])]
		if bad:
			_fault(limb, why, bend)


## Her knee / elbow bend now (deg, final pose), for QA.
func bend_of(limb: String) -> float:
	var b: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
	var r: Vector3 = trace.get(b[0], Vector3.ZERO)
	var m: Vector3 = trace.get(b[1], r)
	var e: Vector3 = trace.get(b[2], m)
	return rad_to_deg((m - r).angle_to(e - m))


func rs_hip_len() -> float:
	return (_sp.hip[0] as Vector3).length()


func _fault(limb: String, why: String, bend: float) -> void:
	if joint_faults.size() < 2000:
		joint_faults.append({"t": snappedf(life_t, 0.01), "limb": limb, "why": why, "pose": move_tag if move_tag != "" else "stance",
			"bend": snappedf(bend, 1.0), "twist": snappedf(float(twist[limb]), 1.0), "frame": Engine.get_frames_drawn()})


static func _rad(deg: Vector3) -> Vector3:
	return Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))


static func _q(deg: Vector3) -> Quaternion:
	return Quaternion(Basis.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))))


const MIN_FLEX := 8.0                    # deg: a planted knee is never straighter than this (no locked / goat legs)
var reach_ratio := {"lf": 0.0, "rf": 0.0}  # QA: how far the foot TARGET was from the hip, in leg lengths, before the cap


## The furthest a foot may be from its hip joint with the knee still bent MIN_FLEX deg (law of cosines).
var _reach_cache := {}


func reach_max(limb: String) -> float:
	if _reach_cache.has(limb):
		return _reach_cache[limb]
	var b: Array = LEG_BONES[limb]
	var a := sk.get_bone_global_rest(sk.find_bone(b[0])).origin.distance_to(sk.get_bone_global_rest(sk.find_bone(b[1])).origin)
	var c2 := sk.get_bone_global_rest(sk.find_bone(b[1])).origin.distance_to(sk.get_bone_global_rest(sk.find_bone(b[2])).origin)
	_reach_cache[limb] = sqrt(a * a + c2 * c2 + 2.0 * a * c2 * cos(deg_to_rad(MIN_FLEX)))
	return _reach_cache[limb]


func ik_target(limb: String) -> Vector3:
	return (_tgt[limb] as Node3D).global_position


func limb_len(limb: String) -> float:
	var b: Array = ARM_BONES[limb] if ARM_BONES.has(limb) else LEG_BONES[limb]
	var a := sk.get_bone_global_rest(sk.find_bone(b[0])).origin
	var m := sk.get_bone_global_rest(sk.find_bone(b[1])).origin
	var e := sk.get_bone_global_rest(sk.find_bone(b[2])).origin
	return a.distance_to(m) + m.distance_to(e)


## World point on her (from the final pose): face / chin / temple_l / temple_r / chest / stomach / ribs_l / ribs_r /
## ankle_l / ankle_r, a few cm off the surface toward `from` (where the blow comes from).
func target_point(aim: String, from: Vector3) -> Vector3:
	var bs: Basis = trace.get("basis", sk.global_transform.basis)
	var fwd := (bs * Vector3(0, 0, 1)).normalized()
	var left := (bs * Vector3(1, 0, 0)).normalized()
	var hd: Vector3 = trace.get("Head", d.bone(id, "Head"))
	var p := hd
	match aim:
		"face":
			p = hd + Vector3.UP * 0.07 * k + fwd * 0.10 * k
		"chin":
			p = hd + Vector3.UP * 0.0 + fwd * 0.08 * k
		"crown":
			p = hd + Vector3.UP * 0.16 * k + fwd * 0.03 * k
		"temple_l":
			p = hd + Vector3.UP * 0.08 * k + left * 0.085 * k + fwd * 0.02 * k
		"temple_r":
			p = hd + Vector3.UP * 0.08 * k - left * 0.085 * k + fwd * 0.02 * k
		"chest":
			p = (trace.get("UpperChest", hd) as Vector3) + fwd * 0.11 * k
		"stomach":
			p = (trace.get("Spine", hd) as Vector3) + fwd * 0.12 * k + Vector3.UP * 0.04 * k
		"ribs_l":
			p = (trace.get("Chest", hd) as Vector3) + left * 0.13 * k + fwd * 0.02 * k
		"ribs_r":
			p = (trace.get("Chest", hd) as Vector3) - left * 0.13 * k + fwd * 0.02 * k
		"ankle_l":
			p = (trace.get("LeftFoot", hd) as Vector3) + Vector3.UP * 0.05 * k + left * 0.04 * k
		"ankle_r":
			p = (trace.get("RightFoot", hd) as Vector3) + Vector3.UP * 0.05 * k - left * 0.04 * k
	var away := (from - p)
	away.y *= 0.3
	return p + away.normalized() * 0.015


## The middle of her blocking forearm (final pose), on the side facing `from`.
func forearm_point(arm: String, from: Vector3) -> Vector3:
	var s := "Left" if arm == "lh" else "Right"
	var a: Vector3 = trace.get(s + "LowerArm", Vector3.ZERO)
	var b: Vector3 = trace.get(s + "Hand", a)
	var m := a.lerp(b, 0.55)
	return m + (from - m).normalized() * 0.035 * k


## Where the striking surface of a limb is now (final pose): fist / palm / ball (of the foot) / shin.
func surface(limb: String, kind: String) -> Vector3:
	var s := "Left" if limb in ["lh", "lf"] else "Right"
	match kind:
		"fist":
			return trace.get("fist_" + s, Vector3.ZERO)
		"palm":
			return (trace.get(s + "MiddleProximal", Vector3.ZERO) as Vector3).lerp(trace.get(s + "Hand", Vector3.ZERO), 0.4)
		"ball":
			return trace.get("ball_" + s, Vector3.ZERO)
		"heel":
			return trace.get(s + "Foot", Vector3.ZERO)
	return trace.get("shin_" + s, Vector3.ZERO)
