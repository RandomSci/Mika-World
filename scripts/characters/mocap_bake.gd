class_name MocapBake
extends RefCounted
## Move Library clips (Part A, 2026-10-19): MediaPipe world landmarks (tools/mocap/extract_landmarks.py, already
## smoothed) turned into an Animation for THIS skeleton - so each girl and every form gets her own fit, with no export
## step. Every bone of her humanoid rig is aimed, parents first, along the direction the matching landmarks give
## (shoulder -> elbow, elbow -> wrist, hip -> knee ...), its twist carried from its parent; the hips and the torso take
## their full orientation from the hip and shoulder lines; the head from the ears and nose. Her hips sit as high above
## the floor as the actor's do, scaled by leg length (so seated clips sit). The hands (2026-10-20): where
## tools/mocap/extract_hands.py read the actor's 21 hand points (<clip>.hands.json next to the clip), the palm takes its
## full orientation from them (roll included) and every finger joint is aimed along its own knuckle -> knuckle line;
## frames the hand tracker was unsure of blend back to the forearm-aimed hand and resting fingers.

const LM_LEFT := {"Shoulder": 11, "Elbow": 13, "Wrist": 15, "Pinky": 17, "Index": 19, "Hip": 23, "Knee": 25, "Ankle": 27, "Heel": 29, "FootIdx": 31}
## The knee / elbow hinge of each upper limb bone in skeleton space at rest (a knee folds about her left axis, the
## left elbow about -Y, the right about +Y - the fight rig's convention), and its landmarks root, middle, end.
const HINGE := {"LeftUpperLeg": Vector3(1, 0, 0), "RightUpperLeg": Vector3(1, 0, 0), "LeftUpperArm": Vector3(0, -1, 0), "RightUpperArm": Vector3(0, 1, 0)}
const HINGE_LM := {"LeftUpperLeg": [23, 25, 27], "RightUpperLeg": [24, 26, 28], "LeftUpperArm": [11, 13, 15], "RightUpperArm": [12, 14, 16]}
## Each finger bone and the two hand points it runs between (MediaPipe Hands: 0 wrist, 1-4 thumb, 5-8 index ...).
const FINGER_LM := {"ThumbMetacarpal": [1, 2], "ThumbProximal": [2, 3], "ThumbDistal": [3, 4],
	"IndexProximal": [5, 6], "IndexIntermediate": [6, 7], "IndexDistal": [7, 8],
	"MiddleProximal": [9, 10], "MiddleIntermediate": [10, 11], "MiddleDistal": [11, 12],
	"RingProximal": [13, 14], "RingIntermediate": [14, 15], "RingDistal": [15, 16],
	"LittleProximal": [17, 18], "LittleIntermediate": [18, 19], "LittleDistal": [19, 20]}
const WRIST_MAX := 80.0                 # deg the hand may turn away from the forearm's carried rest
const FINGER_MAX := 105.0               # deg one finger joint may turn from its parent's carried rest
const LM_RIGHT := {"Shoulder": 12, "Elbow": 14, "Wrist": 16, "Pinky": 18, "Index": 20, "Hip": 24, "Knee": 26, "Ankle": 28, "Heel": 30, "FootIdx": 32}


## The clip as an Animation with tracks "X:<Bone>" (the caller sets the skeleton path), at the JSON's frame rate.
static func bake(sk: Skeleton3D, json_path: String) -> Animation:
	var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("frames"):
		push_warning("[mocap] cannot read %s" % json_path)
		return null
	var frames: Array = data.frames
	var fps := float(data.get("fps", 30.0))
	var B := func(n: String) -> int: return sk.find_bone(n)
	# her rest frame in skeleton space: left (from her right shoulder to her left), up, forward
	var rest_pos := func(n: String) -> Vector3: return sk.get_bone_global_rest(B.call(n)).origin if B.call(n) >= 0 else Vector3.ZERO
	var left := ((rest_pos.call("LeftUpperArm") as Vector3) - (rest_pos.call("RightUpperArm") as Vector3)).normalized()
	var up := ((rest_pos.call("Neck") as Vector3) - (rest_pos.call("Hips") as Vector3))
	up = (up - left * up.dot(left)).normalized()
	var F := Basis(left, up, left.cross(up)).orthonormalized()      # canonical (x left, y up, z forward) -> skeleton
	var Fi := F.inverse()
	var girl_leg := (rest_pos.call("LeftUpperLeg") as Vector3).distance_to(rest_pos.call("LeftLowerLeg")) \
		+ (rest_pos.call("LeftLowerLeg") as Vector3).distance_to(rest_pos.call("LeftFoot"))
	var hips_rest_h: float = (rest_pos.call("Hips") as Vector3).dot(up) - minf((rest_pos.call("LeftFoot") as Vector3).dot(up), (rest_pos.call("RightFoot") as Vector3).dot(up))
	# limbs: bone -> [child bone (its rest direction), landmark from, landmark to]
	var limbs := []
	for side in ["Left", "Right"]:
		var L: Dictionary = LM_LEFT if side == "Left" else LM_RIGHT
		limbs.append([side + "UpperArm", side + "LowerArm", L.Shoulder, L.Elbow])
		limbs.append([side + "LowerArm", side + "Hand", L.Elbow, L.Wrist])
		limbs.append([side + "Hand", side + "MiddleProximal", L.Wrist, -1])        # -1: the knuckles' middle
		limbs.append([side + "UpperLeg", side + "LowerLeg", L.Hip, L.Knee])
		limbs.append([side + "LowerLeg", side + "Foot", L.Knee, L.Ankle])
		limbs.append([side + "Foot", side + "Toes", L.Ankle, L.FootIdx])
	var order := []                                      # every bone we drive, parents first
	for bi in sk.get_bone_count():
		order.append(bi)
	var anim := Animation.new()
	anim.length = float(frames.size() - 1) / fps
	var tracks := {}
	var drive := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]
	for l in limbs:
		drive.append(l[0])
	# the hands: 21 points per hand per frame (or null), a confidence per frame
	var hands := {}
	var hpath := json_path.get_basename() + ".hands.json"
	if FileAccess.file_exists(hpath):
		var hd = JSON.parse_string(FileAccess.get_file_as_string(hpath))
		if typeof(hd) == TYPE_DICTIONARY and hd.has("l"):
			hands = hd
	var finger_d0 := {}                   # finger bone -> its rest direction (skeleton space)
	if not hands.is_empty():
		for side in ["Left", "Right"]:
			for fb in FINGER_LM:
				var bi_f: int = B.call(side + fb)
				if bi_f < 0:
					continue
				var nxt := ""
				var keys := FINGER_LM.keys()
				var ki := keys.find(fb)
				if ki + 1 < keys.size() and String(keys[ki + 1]).substr(0, 4) == fb.substr(0, 4):
					nxt = side + String(keys[ki + 1])
				var o: Vector3 = rest_pos.call(side + fb)
				var dir := Vector3.ZERO
				if nxt != "" and B.call(nxt) >= 0:
					dir = (rest_pos.call(nxt) as Vector3) - o
				else:
					var par_f := sk.get_bone_parent(bi_f)
					dir = o - sk.get_bone_global_rest(par_f).origin
				if dir.length() > 1e-5:
					finger_d0[side + fb] = dir.normalized()
					drive.append(side + fb)
	for n in drive:
		if B.call(n) >= 0:
			var t := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(t, NodePath("X:" + n))
			tracks[n] = t
	var hips_t := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_t, NodePath("X:Hips"))
	var actor_leg := 0.0
	for f in frames:
		var P: Array = f
		actor_leg = maxf(actor_leg, _v(P, 23).distance_to(_v(P, 25)) + _v(P, 25).distance_to(_v(P, 27)))
	var limb_of := {}
	for l in limbs:
		limb_of[l[0]] = l
	for fi in frames.size():
		var P: Array = frames[fi]
		var time := float(fi) / fps
		var mid_hip := (_v(P, 23) + _v(P, 24)) * 0.5
		var mid_sh := (_v(P, 11) + _v(P, 12)) * 0.5
		var hipsC := _frame(_v(P, 23) - _v(P, 24), mid_sh - mid_hip)
		var chestC := _frame(_v(P, 11) - _v(P, 12), mid_sh - mid_hip)
		var ears := (_v(P, 7) + _v(P, 8)) * 0.5
		var headC := _frame(_v(P, 7) - _v(P, 8), (ears - mid_sh) + (_v(P, 0) - ears).project(Vector3.UP) * 0.0, _v(P, 0) - ears)
		var HL := {}                                      # side -> [21 points, weight] this frame
		if not hands.is_empty():
			for sd in [["Left", "l"], ["Right", "r"]]:
				var arr: Array = hands[sd[1]]
				if fi < arr.size() and arr[fi] != null:
					var q := float((hands[sd[1] + "q"] as Array)[fi]) if fi < (hands[sd[1] + "q"] as Array).size() else 0.0
					HL[sd[0]] = [arr[fi], smoothstep(0.15, 0.5, q)]
		var R := {}                                       # bone -> rotation delta from rest (skeleton space)
		var rot_of := func(C: Basis) -> Basis: return F * C * Fi
		var G := {}                                       # bone -> new global basis
		for bi in order:
			var n := sk.get_bone_name(bi)
			var par := sk.get_bone_parent(bi)
			var D: Basis = R.get(par, Basis.IDENTITY) if par >= 0 else Basis.IDENTITY
			var rest_b := sk.get_bone_global_rest(bi).basis.orthonormalized()
			var d := D
			match n:
				"Hips":
					d = rot_of.call(hipsC)
				"Spine":
					d = Basis((rot_of.call(hipsC) as Basis).get_rotation_quaternion().slerp((rot_of.call(chestC) as Basis).get_rotation_quaternion(), 0.35))
				"Chest":
					d = Basis((rot_of.call(hipsC) as Basis).get_rotation_quaternion().slerp((rot_of.call(chestC) as Basis).get_rotation_quaternion(), 0.7))
				"UpperChest":
					d = rot_of.call(chestC)
				"Neck":
					d = Basis((rot_of.call(chestC) as Basis).get_rotation_quaternion().slerp((rot_of.call(headC) as Basis).get_rotation_quaternion(), 0.5))
				"Head":
					d = rot_of.call(headC)
				_:
					if limb_of.has(n):
						var l: Array = limb_of[n]
						var c := B.call(String(l[1])) as int
						var to: Vector3 = ((_v(P, LM_LEFT.Index if n.begins_with("Left") else LM_RIGHT.Index) + _v(P, LM_LEFT.Pinky if n.begins_with("Left") else LM_RIGHT.Pinky)) * 0.5) if int(l[3]) < 0 else _v(P, int(l[3]))
						var aim := F * (to - _v(P, int(l[2])))
						if c >= 0 and aim.length() > 1e-4:
							var d0 := (sk.get_bone_global_rest(c).origin - sk.get_bone_global_rest(bi).origin).normalized()
							if HINGE.has(n):
								# a thigh / upper arm: aimed at the knee / elbow, turned about itself so its hinge lies
								# across the bend (the crease folds the human way). If that needs a twist no hip /
								# shoulder can make, or puts a knee behind her (front-camera depth errors flip the
								# plane), the knee / elbow point swings about the hip -> ankle / shoulder -> wrist line
								# (hand and foot stay put) to the nearest human answer - and the lower bone follows it
								var lm: Array = HINGE_LM[n]
								var Sx := _v(P, int(lm[0]))
								var Ex := _v(P, int(lm[1]))
								var Wx := _v(P, int(lm[2]))
								var pg: Basis = G[par] if par >= 0 else Basis.IDENTITY
								var prb := sk.get_bone_global_rest(par).basis.orthonormalized() if par >= 0 else Basis.IDENTITY
								var hips_g: Basis = G.get(B.call("Hips"), Basis.IDENTITY)
								var hips_rb := sk.get_bone_global_rest(B.call("Hips")).basis.orthonormalized()
								var leg := n.ends_with("UpperLeg")
								var lim := 56.0 if leg else 96.0
								var foot_yaw := 0.0
								if leg:
									var fl: Array = [29, 31] if n.begins_with("Left") else [30, 32]
									var fdir := F * (_v(P, int(fl[1])) - _v(P, int(fl[0])))
									var pfw := hips_g * hips_rb.inverse() * Vector3(0, 0, 1)
									var pup := hips_g * hips_rb.inverse() * Vector3(0, 1, 0)
									var ff := fdir - pup * fdir.dot(pup)
									var fp := pfw - pup * pfw.dot(pup)
									if ff.length() > 0.02 and fp.length() > 0.2:
										foot_yaw = rad_to_deg(fp.signed_angle_to(ff, pup))
									foot_yaw = clampf(foot_yaw, -35.0, 50.0) if n.begins_with("Left") else clampf(foot_yaw, -50.0, 35.0)
								var best_d := _upper(D, d0, HINGE[n], F, Sx, Ex, Wx)
								var best_c := _cost(best_d, rest_b, pg, prb, lim, leg, hips_g, hips_rb, foot_yaw, F, Sx, Ex, Wx)
								if best_c > 0.0:
									var axis := (Wx - Sx).normalized()
									var best_e := Ex
									for k in range(1, 36):
										var phi := deg_to_rad(float(k) * 10.0 - (360.0 if k > 18 else 0.0))
										var e2 := Sx + Basis(axis, phi) * (Ex - Sx)
										var d2 := _upper(D, d0, HINGE[n], F, Sx, e2, Wx)
										var c2 := _cost(d2, rest_b, pg, prb, lim, leg, hips_g, hips_rb, foot_yaw, F, Sx, e2, Wx)
										if c2 < best_c - 0.01:
											best_c = c2
											best_d = d2
											best_e = e2
									(P as Array)[int(lm[1])] = [best_e.x, best_e.y, best_e.z]
								d = best_d
							else:
								var cur := D * d0
								d = Basis(Quaternion(cur.normalized(), aim.normalized())) * D
			if not HL.is_empty():
				d = _hand_bone(sk, n, d, D, HL, finger_d0, F, rest_pos)
			R[bi] = d.orthonormalized()
			G[bi] = (d * rest_b).orthonormalized()
		for n in tracks:
			var bi: int = B.call(n)
			var par := sk.get_bone_parent(bi)
			var pg: Basis = G[par] if par >= 0 else Basis.IDENTITY
			anim.rotation_track_insert_key(tracks[n], time, (pg.inverse() * (G[bi] as Basis)).get_rotation_quaternion().normalized())
		# hips height above the floor, as the actor's, scaled by leg length (her hips stay over her rest x/z)
		var floor_y := minf(minf(_v(P, 29).y, _v(P, 30).y), minf(_v(P, 31).y, _v(P, 32).y))
		var h := (mid_hip.y - floor_y) * (girl_leg / maxf(actor_leg, 0.1))
		if data.has("hip_h") and fi < (data.hip_h as Array).size():
			# a jump / flip: the hips' height above the floor read from the 2D image (world landmarks are centred on
			# the hips every frame, so the feet-based height above never leaves the ground)
			h = float(data.hip_h[fi]) * (girl_leg / maxf(actor_leg, 0.1))
		var hp: Vector3 = sk.get_bone_rest(B.call("Hips")).origin
		anim.position_track_insert_key(hips_t, time, hp + up * (h - hips_rest_h))
	# the joint rules on the baked pose itself: any frame a knee / elbow folds the wrong way, a hip / shoulder turns
	# past a human twist or a knee points behind her is made human (JointAudit.fix_anim)
	JointAudit.fix_anim(sk, anim)
	return anim


## The hand and its fingers from the hand tracker: the palm's full frame (wrist -> middle knuckle, index knuckle ->
## little knuckle) replaces the forearm-aimed hand, each finger joint swings onto its knuckle line; both weighted by how
## sure the tracker was, and held inside a human wrist / finger range.
static func _hand_bone(sk: Skeleton3D, n: String, d: Basis, D: Basis, HL: Dictionary, finger_d0: Dictionary, F: Basis,
		rest_pos: Callable) -> Basis:
	var side := "Left" if n.begins_with("Left") else ("Right" if n.begins_with("Right") else "")
	if side == "" or not HL.has(side):
		return d
	var pts: Array = HL[side][0]
	var w: float = HL[side][1]
	if w <= 0.001:
		return d
	var hv := func(i: int) -> Vector3: return F * _v(pts, i)
	if n == side + "Hand":
		var a_r: Vector3 = (rest_pos.call(side + "MiddleProximal") as Vector3) - (rest_pos.call(side + "Hand") as Vector3)
		var c_r: Vector3 = (rest_pos.call(side + "IndexProximal") as Vector3) - (rest_pos.call(side + "LittleProximal") as Vector3)
		var a_t: Vector3 = (hv.call(9) as Vector3) - (hv.call(0) as Vector3)
		var c_t: Vector3 = (hv.call(5) as Vector3) - (hv.call(17) as Vector3)
		if a_r.length() < 1e-5 or c_r.length() < 1e-5 or a_t.length() < 1e-5 or c_t.length() < 1e-5:
			return d
		var dm := _frame2(a_t, c_t) * _frame2(a_r, c_r).inverse()
		# a human wrist: never more than WRIST_MAX from the forearm's carried rest
		var rel := Quaternion((D.inverse() * dm).orthonormalized())
		var ang := rad_to_deg(rel.get_angle())
		if ang > WRIST_MAX:
			rel = Quaternion.IDENTITY.slerp(rel, WRIST_MAX / ang)
		dm = D * Basis(rel)
		return Basis(d.get_rotation_quaternion().slerp(dm.get_rotation_quaternion(), w))
	var fb := n.trim_prefix(side)
	if not FINGER_LM.has(fb) or not finger_d0.has(n):
		return d
	var lm: Array = FINGER_LM[fb]
	var aim: Vector3 = (hv.call(int(lm[1])) as Vector3) - (hv.call(int(lm[0])) as Vector3)
	if aim.length() < 1e-5:
		return d
	var cur: Vector3 = (D * (finger_d0[n] as Vector3)).normalized()
	aim = aim.normalized()
	var ang2 := cur.angle_to(aim)
	if ang2 < 1e-4:
		return d
	var turn := minf(ang2, deg_to_rad(FINGER_MAX))
	var axis := cur.cross(aim).normalized()
	var dm2 := Basis(axis, turn) * D
	return Basis(D.get_rotation_quaternion().slerp(dm2.get_rotation_quaternion(), w))


static func _frame2(a: Vector3, c: Vector3) -> Basis:
	var x := a.normalized()
	var z := (c - x * c.dot(x)).normalized()
	return Basis(x, z.cross(x), z).orthonormalized()


## A thigh / upper arm's delta rotation: swung from its parent's delta onto shoulder -> elbow (S -> E, canonical
## landmarks), then turned about itself so its hinge lies across the S -> E -> W bend (when there is a bend).
static func _upper(D: Basis, d0: Vector3, hinge: Vector3, F: Basis, S: Vector3, E: Vector3, W: Vector3) -> Basis:
	var aim := F * (E - S)
	var cur := D * d0
	var d := Basis(Quaternion(cur.normalized(), aim.normalized())) * D
	var b1 := F * (W - E)
	var bend_n := aim.cross(b1)
	if bend_n.length() > 0.12 * aim.length() * b1.length():
		var ax := aim.normalized()
		var h := d * hinge
		var hp := h - ax * h.dot(ax)
		var np := bend_n - ax * bend_n.dot(ax)
		if hp.length() > 1e-4 and np.length() > 1e-4:
			d = Basis(ax, hp.signed_angle_to(np, ax)) * d
	return d.orthonormalized()


## How un-human that limb is: degrees of twist past the limit (in its parent's frame, from the swing out of rest),
## plus 200 for a knee pointing behind her (pelvis left axis turned with the foot, as MeleeFighter.knee_dir).
static func _cost(d: Basis, rest_b: Basis, pg: Basis, prb: Basis, lim: float, leg: bool, hips_g: Basis, hips_rb: Basis,
		foot_yaw: float, F: Basis, S: Vector3, E: Vector3, W: Vector3) -> float:
	var g := (d * rest_b).orthonormalized()
	var rel_now := pg.inverse() * g
	var rel_rest := prb.inverse() * rest_b
	var a0 := (rel_rest * Vector3.UP).normalized()
	var a1 := (rel_now * Vector3.UP).normalized()
	var q := Quaternion(rel_now.orthonormalized()) * Quaternion(rel_rest.orthonormalized()).inverse()
	var sw := Quaternion(a0, a1) if a0.dot(a1) > -0.999 else Quaternion(a0.cross(Vector3.RIGHT).normalized(), PI)
	var tw := sw.inverse() * q
	var twd := absf(rad_to_deg(wrapf(2.0 * atan2(Vector3(tw.x, tw.y, tw.z).dot(a0), tw.w), -PI, PI)))
	var c := maxf(twd - lim, 0.0)
	if leg:
		var line := F * (W - S)
		var off := F * (E - (S + W) * 0.5)
		off -= line.normalized() * off.dot(line.normalized())
		var pl := hips_g * hips_rb.inverse()
		var hp := (pl * (Basis(Vector3.UP, deg_to_rad(foot_yaw)) * Vector3(1, 0, 0))).normalized()
		var kd := line.normalized().cross(hp)
		if kd.length() > 0.05 and off.length() > 0.01 and off.normalized().dot(kd.normalized()) < -0.2:
			c += 200.0
	return c


static func _v(P: Array, i: int) -> Vector3:
	var a: Array = P[i]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## An orthonormal frame (canonical: x left, y up, z forward) from a left-pointing and an up-pointing vector; with
## `fwd` given, up is taken as the part of it square to x and fwd decides the facing.
static func _frame(x: Vector3, y: Vector3, fwd := Vector3.ZERO) -> Basis:
	var xx := x.normalized()
	if fwd != Vector3.ZERO:
		var zz := (fwd - xx * fwd.dot(xx)).normalized()
		return Basis(xx, zz.cross(xx), zz).orthonormalized()
	var yy := (y - xx * y.dot(xx)).normalized()
	return Basis(xx, yy, xx.cross(yy)).orthonormalized()
