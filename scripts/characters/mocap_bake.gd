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
## Clips where a hand holds a prop (Selwyn: replace the tracked fingers there with a grip fitted to it), per side:
## grip (a hilt, a spear shaft, a staff, the bow), draw (the bow string hand), lantern (a ring handle). Every other
## hand falls back to a relaxed curl on frames the tracker is unsure of.
const GRIPS := {
	"stick_sword_play": {"r": "grip"}, "ult_heaven_spear": {"r": "grip"}, "ult_sky_rending_slash": {"l": "grip", "r": "grip"},
	"ult_star_archer": {"l": "grip", "r": "draw"}, "bow_draw_release": {"l": "grip", "r": "draw"},
	"iaido_draw_slash": {"r": "grip"}, "sword_combo_invisible": {"r": "grip"}, "dance_lantern_lift": {"l": "lantern", "r": "lantern"},
}
## Step 2 of the body pass (One Euro filter, foot lock, hips held in the gather, fitted grips): OFF until Selwyn has
## seen the trembling's root cause (2026-10-20).
## Step 2 is on: the hand tracks cleaned first (tools/mocap/clean_hands.py: swaps, holds, 0.2 s crossfades), the palm
## held by the body tracker's knuckles while the hand tracker is away, a fitted hand shape per gesture, sign and elbow
## continuity, then the One Euro filter, the hips held in the gather and the feet locked.
const CLEANUP := true
## The hand shape a gesture falls back to while the tracker cannot see the fingers (overlapping, hidden): palms
## together, a cupped orb, a two-finger sign, a pointing finger. Per clip and side; anything not listed is relaxed.
const SHAPES := {
	"domain_expand": {"l": "flat", "r": "flat"}, "seal_finish": {"l": "flat", "r": "flat"}, "ult_final_seal_bow": {"l": "flat", "r": "flat"},
	"ult_duo_hand_join_push": {"l": "flat", "r": "flat"}, "barrier_raise": {"l": "flat", "r": "flat"}, "ult_blooming_domain": {"l": "flat", "r": "flat"},
	"orb_gather": {"l": "cup", "r": "cup"}, "ult_eclipse_ring": {"l": "cup", "r": "cup"}, "ult_crossed_arms_burst": {"l": "fist", "r": "fist"},
	"ult_twin_hand_sigil": {"l": "sign", "r": "sign"}, "sign_weave_fast": {"l": "sign", "r": "sign"},
	"finger_snap_point": {"r": "point"}, "sky_call_point": {"r": "point"}, "array_air_draw": {"r": "point"}, "ult_spiral_ascension": {"r": "point"},
}
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
	var grips: Dictionary = GRIPS.get(json_path.get_file().get_basename(), {})
	var shapes: Dictionary = SHAPES.get(json_path.get_file().get_basename(), {})
	var hpath := json_path.get_basename() + ".hands.json"
	if CLEANUP and FileAccess.file_exists(json_path.get_basename() + ".hands.clean.json"):
		hpath = json_path.get_basename() + ".hands.clean.json"
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
	# her foot's rest angle to her shin (her shoes: about 116 deg barefoot, 141 to 151 in heels)
	var foot_rest := {}
	for side in ["Left", "Right"]:
		if B.call(side + "Toes") >= 0:
			var a_r: Vector3 = rest_pos.call(side + "Foot")
			foot_rest[side + "Foot"] = rad_to_deg(((rest_pos.call(side + "LowerLeg") as Vector3) - a_r).angle_to((rest_pos.call(side + "Toes") as Vector3) - a_r))
	var limb_of := {}
	for l in limbs:
		limb_of[l[0]] = l
	var last_q := {}                                     # track -> its previous key (sign continuity)
	var prev_h := {}                                     # thigh / upper arm -> its hinge direction last frame (skeleton space)
	var prev_e := {}                                     # thigh / upper arm -> the knee / elbow point chosen last frame
	for fi in frames.size():
		var P: Array = frames[fi]
		var time := float(fi) / fps
		var mid_hip := (_v(P, 23) + _v(P, 24)) * 0.5
		var mid_sh := (_v(P, 11) + _v(P, 12)) * 0.5
		var hipsC := _frame(_v(P, 23) - _v(P, 24), mid_sh - mid_hip)
		var chestC := _frame(_v(P, 11) - _v(P, 12), mid_sh - mid_hip)
		var ears := (_v(P, 7) + _v(P, 8)) * 0.5
		var headC := _frame(_v(P, 7) - _v(P, 8), (ears - mid_sh) + (_v(P, 0) - ears).project(Vector3.UP) * 0.0, _v(P, 0) - ears)
		var HL := {}                                      # side -> [21 points or null, weight, fallback hand shape] this frame
		if not hands.is_empty():
			for sd in [["Left", "l"], ["Right", "r"]]:
				var arr: Array = hands[sd[1]]
				var prop := grips.has(sd[1])
				var shape := String(grips.get(sd[1], shapes.get(sd[1], "relaxed")))
				var pts_f = arr[fi] if fi < arr.size() else null
				var w_f := 0.0
				if hands.has(sd[1] + "w"):
					# cleaned: the weight already crossfades (0.2 s) to the fallback over unreliable stretches
					w_f = float((hands[sd[1] + "w"] as Array)[fi]) if fi < (hands[sd[1] + "w"] as Array).size() else 0.0
				else:
					var q := float((hands[sd[1] + "q"] as Array)[fi]) if fi < (hands[sd[1] + "q"] as Array).size() else 0.0
					w_f = smoothstep(0.15, 0.5, q)
				# a hand on a prop (hilt, bow, staff) keeps a fitted grip: the tracker cannot see fingers round a handle
				if pts_f == null or (CLEANUP and prop):
					w_f = 0.0
				var L2: Dictionary = LM_LEFT if sd[0] == "Left" else LM_RIGHT
				HL[sd[0]] = [pts_f, w_f, shape, [_v(P, int(L2.Wrist)), _v(P, int(L2.Index)), _v(P, int(L2.Pinky))]]
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
						if n.ends_with("Foot") and foot_rest.has(n):
							# (2026-10-20) the actor is barefoot, she is in her shoes: the actor's ankle BEND from a
							# standing foot goes onto her foot from its own rest, not the actor's absolute foot angle
							# (copied as it was, a heel was pressed flat, toes up 35 to 70 deg inside the shoe)
							var L3: Dictionary = LM_LEFT if n.begins_with("Left") else LM_RIGHT
							aim = _foot_aim(aim, F * (_v(P, int(L3.Knee)) - _v(P, int(L3.Ankle))), float(foot_rest[n]))
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
								var ph: Vector3 = prev_h.get(n, Vector3.ZERO) if CLEANUP else Vector3.ZERO
								var best_d := _upper(D, d0, HINGE[n], F, Sx, Ex, Wx, ph)
								var best_c := _cost(best_d, rest_b, pg, prb, lim, leg, hips_g, hips_rb, foot_yaw, F, Sx, Ex, Wx)
								var pe: Vector3 = prev_e.get(n, Vector3.INF) if CLEANUP else Vector3.INF
								# (continuity: an elbow / knee that would jump from where it was last frame costs 4 per cm, so a near-straight
								# limb never flips to the other side of its swing between two frames)
								var jump := func(e: Vector3) -> float: return 0.0 if pe == Vector3.INF else (e - Sx - pe).length() * 400.0
								if best_c > 0.0:
									var axis := (Wx - Sx).normalized()
									var best_e := Ex
									for k in range(1, 36):
										var phi := deg_to_rad(float(k) * 10.0 - (360.0 if k > 18 else 0.0))
										var e2 := Sx + Basis(axis, phi) * (Ex - Sx)
										var d2 := _upper(D, d0, HINGE[n], F, Sx, e2, Wx, ph)
										var c2 := _cost(d2, rest_b, pg, prb, lim, leg, hips_g, hips_rb, foot_yaw, F, Sx, e2, Wx) + float(jump.call(e2)) - float(jump.call(Ex))
										if c2 < best_c - 0.01:
											best_c = c2
											best_d = d2
											best_e = e2
									(P as Array)[int(lm[1])] = [best_e.x, best_e.y, best_e.z]
								d = best_d
								prev_h[n] = (best_d * (HINGE[n] as Vector3)).normalized()
								prev_e[n] = _v(P, int(lm[1])) - Sx
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
			var qk := (pg.inverse() * (G[bi] as Basis)).get_rotation_quaternion().normalized()
			if last_q.has(n) and (last_q[n] as Quaternion).dot(qk) < 0.0:
				qk = -qk                                       # (the same rotation, kept on the previous key's side)
			last_q[n] = qk
			anim.rotation_track_insert_key(tracks[n], time, qk)
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
	if CLEANUP:
		# the noise last: One Euro per region on every track, then the gather's still hips and planted feet
		clean(anim)
		hold_hips(anim, json_path.get_file().get_basename())
		lock_feet(sk, anim)
	return anim


## The hand and its fingers from the hand tracker: the palm's full frame (wrist -> middle knuckle, index knuckle ->
## little knuckle) replaces the forearm-aimed hand, each finger joint swings onto its knuckle line; both weighted by how
## sure the tracker was, and held inside a human wrist / finger range.
static func _hand_bone(sk: Skeleton3D, n: String, d: Basis, D: Basis, HL: Dictionary, finger_d0: Dictionary, F: Basis,
		rest_pos: Callable) -> Basis:
	var side := "Left" if n.begins_with("Left") else ("Right" if n.begins_with("Right") else "")
	if side == "" or not HL.has(side):
		return d
	var w: float = HL[side][1]
	var fb0 := n.trim_prefix(side)
	var d_fb := d
	if FINGER_LM.has(fb0) and CLEANUP:
		# the fallback hand shape (no tracking, a weak frame, or a prop): each joint curled about its own closing axis
		var bi := sk.find_bone(n)
		var amt := _grip_curl(String(HL[side][2]), fb0)
		var ax_g := (sk.get_bone_global_rest(bi).basis.orthonormalized() * SoftArms._curl_axis(sk, bi)).normalized()
		d_fb = D * Basis(ax_g, amt * 1.15)
	var d_hand_fb := d
	if n == side + "Hand" and CLEANUP:
		# the palm while the hand tracker is away: the body tracker's wrist, index and little knuckles give its
		# facing (only the aim came from them before, so the palm's roll snapped when the hand tracker dropped)
		var pk: Array = HL[side][3]
		var a_p: Vector3 = F * ((((pk[1] as Vector3) + (pk[2] as Vector3)) * 0.5) - (pk[0] as Vector3))
		var c_p: Vector3 = F * ((pk[1] as Vector3) - (pk[2] as Vector3))
		var a_r0: Vector3 = (rest_pos.call(side + "MiddleProximal") as Vector3) - (rest_pos.call(side + "Hand") as Vector3)
		var c_r0: Vector3 = (rest_pos.call(side + "IndexProximal") as Vector3) - (rest_pos.call(side + "LittleProximal") as Vector3)
		if a_p.length() > 1e-4 and c_p.length() > 1e-4 and absf(a_p.normalized().dot(c_p.normalized())) < 0.95:
			var dmf := _frame2(a_p, c_p) * _frame2(a_r0, c_r0).inverse()
			var relf := Quaternion((D.inverse() * dmf).orthonormalized())
			var angf := rad_to_deg(relf.get_angle())
			if angf > WRIST_MAX:
				relf = Quaternion.IDENTITY.slerp(relf, WRIST_MAX / angf)
			d_hand_fb = D * Basis(relf)
	if w <= 0.001 or HL[side][0] == null:
		return d_hand_fb if n == side + "Hand" else d_fb
	var pts: Array = HL[side][0]
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
		return Basis(d_hand_fb.get_rotation_quaternion().slerp(dm.get_rotation_quaternion(), w))
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
	return Basis(d_fb.get_rotation_quaternion().slerp(dm2.get_rotation_quaternion(), w))


## How far a finger joint closes (0 open .. 1 a fist) in a fallback hand shape.
static func _grip_curl(shape: String, bone: String) -> float:
	var f := "Thumb" if bone.begins_with("Thumb") else ("Index" if bone.begins_with("Index") else ("Middle" if bone.begins_with("Middle")
		else ("Ring" if bone.begins_with("Ring") else "Little")))
	match shape:
		"grip":
			return 0.45 if f == "Thumb" else 0.95
		"draw":
			return {"Thumb": 0.35, "Index": 0.6, "Middle": 0.65, "Ring": 0.9, "Little": 0.95}[f]
		"lantern":
			return 0.4 if f == "Thumb" else 0.8
		"flat":
			return 0.05 if f == "Thumb" else 0.04
		"cup":
			return {"Thumb": 0.2, "Index": 0.3, "Middle": 0.34, "Ring": 0.38, "Little": 0.42}[f]
		"fist":
			return 0.55 if f == "Thumb" else 1.0
		"sign":
			return {"Thumb": 0.6, "Index": 0.03, "Middle": 0.03, "Ring": 0.95, "Little": 0.95}[f]
		"point":
			return {"Thumb": 0.55, "Index": 0.02, "Middle": 0.9, "Ring": 0.95, "Little": 0.95}[f]
	return {"Thumb": 0.15, "Index": 0.14, "Middle": 0.24, "Ring": 0.32, "Little": 0.4}[f]


static func _frame2(a: Vector3, c: Vector3) -> Basis:
	var x := a.normalized()
	var z := (c - x * c.dot(x)).normalized()
	return Basis(x, z.cross(x), z).orthonormalized()


## A thigh / upper arm's delta rotation: swung from its parent's delta onto shoulder -> elbow (S -> E, canonical
## landmarks), then turned about itself so its hinge lies across the S -> E -> W bend (when there is a bend).
## `prev_h` (the hinge direction chosen last frame, or zero): while the limb is nearly straight its bend plane is
## undefined and flips with the smallest noise, so there the hinge is carried from the previous frame, blended over to
## the bend's own plane as the bend grows (5 to 25 degrees), and the bend plane's sign is kept on the previous side.
static func _upper(D: Basis, d0: Vector3, hinge: Vector3, F: Basis, S: Vector3, E: Vector3, W: Vector3, prev_h := Vector3.ZERO) -> Basis:
	var aim := F * (E - S)
	var cur := D * d0
	var d := Basis(Quaternion(cur.normalized(), aim.normalized())) * D
	var b1 := F * (W - E)
	var bend_n := aim.cross(b1)
	var ax := aim.normalized()
	var h := d * hinge
	var hp := h - ax * h.dot(ax)
	var sin_b := bend_n.length() / maxf(aim.length() * b1.length(), 1e-6)
	if prev_h != Vector3.ZERO:
		var pp := prev_h - ax * prev_h.dot(ax)
		var np2 := bend_n - ax * bend_n.dot(ax)
		var want := pp.normalized() if pp.length() > 1e-4 else Vector3.ZERO
		var k := smoothstep(sin(deg_to_rad(5.0)), sin(deg_to_rad(25.0)), sin_b)
		if np2.length() > 1e-4 and want != Vector3.ZERO:
			var nn := np2.normalized()
			if nn.dot(want) < 0.0 and k < 1.0:
				nn = -nn
			want = want.slerp(nn, k).normalized() if absf(want.dot(nn)) < 0.9999 else nn
		elif np2.length() > 1e-4:
			want = np2.normalized()
		if want != Vector3.ZERO and hp.length() > 1e-4:
			d = Basis(ax, hp.signed_angle_to(want, ax)) * d
		return d.orthonormalized()
	if bend_n.length() > 0.12 * aim.length() * b1.length():
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


## The actor's standing foot to her shin (MediaPipe ankle -> foot index against ankle -> knee): the median of every
## still, upright frame of the move library (557 frames, 2026-10-20), 101.8 deg.
const ACTOR_FOOT_NEUTRAL := 101.8


## The actor's foot direction turned in the plane of the shin so that the actor's neutral lands on her rest angle:
## her bend from neutral is the actor's bend from neutral.
static func _foot_aim(aim: Vector3, up_shin: Vector3, rest_deg: float) -> Vector3:
	var ax := up_shin.cross(aim)
	if ax.length() < 1e-6 or aim.length() < 1e-6:
		return aim
	return Basis(ax.normalized(), deg_to_rad(rest_deg - ACTOR_FOOT_NEUTRAL)) * aim


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

# ------------------------------------------------------------------------------------------------ cleaning
## One Euro filter settings per body region [min cutoff Hz, beta (Hz per rad/s)] (Casiez et al. 2012): slow motion is
## smoothed hard (MediaPipe's noise lives there), fast motion lets the cutoff rise so a cast keeps its snap. Fingers
## filtered hardest, the spine lightest. Tuned by eye at 10 fps (Selwyn's start: 1.2 Hz, 0.02).
const EURO := {"finger": [0.8, 0.01], "hand": [1.0, 0.015], "arm": [1.2, 0.02], "spine": [1.6, 0.02], "head": [1.4, 0.02],
	"hips": [1.0, 0.02], "leg": [1.2, 0.02], "foot": [1.0, 0.02]}
const EURO_DCUT := 1.0                  # Hz, the speed estimate's own smoothing


static func region_of(bone: String) -> String:
	for f in ["Thumb", "Index", "Middle", "Ring", "Little"]:
		if f in bone:
			return "finger"
	if bone.ends_with("Hand"):
		return "hand"
	if "Arm" in bone or "Shoulder" in bone:
		return "arm"
	if bone in ["Spine", "Chest", "UpperChest", "Neck"]:
		return "spine"
	if bone == "Head":
		return "head"
	if bone == "Hips":
		return "hips"
	if "Leg" in bone:
		return "leg"
	return "foot"


static func _alpha(cut: float, dt: float) -> float:
	var tau := 1.0 / (TAU * maxf(cut, 0.001))
	return 1.0 / (1.0 + tau / maxf(dt, 1e-4))


## One Euro over a rotation key list, forward then backward (zero phase: no lag on releases). Slerp based.
static func euro_rot(qs: Array, ts: PackedFloat32Array, mincut: float, beta: float) -> Array:
	var out := qs.duplicate()
	for pass_i in 2:
		var idx := range(out.size()) if pass_i == 0 else range(out.size() - 1, -1, -1)
		var xf: Quaternion = out[idx[0]]
		var dxf := 0.0
		var prev_t: float = ts[idx[0]]
		for k in range(1, idx.size()):
			var i: int = idx[k]
			var dt := absf(ts[i] - prev_t)
			prev_t = ts[i]
			var q: Quaternion = out[i]
			if xf.dot(q) < 0.0:
				q = -q
			var dx := xf.angle_to(q) / maxf(dt, 1e-4)
			dxf = lerpf(dxf, dx, _alpha(EURO_DCUT, dt))
			xf = xf.slerp(q, _alpha(mincut + beta * dxf, dt)).normalized()
			out[i] = xf
	return out


## Every rotation track of a baked clip through its region's One Euro filter (and the hips' height with the hips').
static func clean(anim: Animation, scale := 1.0) -> void:
	for ti in anim.get_track_count():
		var ty := anim.track_get_type(ti)
		var bone := String(anim.track_get_path(ti)).get_slice(":", 1)
		var n := anim.track_get_key_count(ti)
		if n < 4:
			continue
		var ts := PackedFloat32Array()
		for k in n:
			ts.append(anim.track_get_key_time(ti, k))
		var pr: Array = EURO[region_of(bone)]
		if ty == Animation.TYPE_ROTATION_3D:
			var qs := []
			for k in n:
				qs.append(anim.track_get_key_value(ti, k))
			var f := euro_rot(qs, ts, float(pr[0]) / scale, float(pr[1]))
			for k in n:
				anim.track_set_key_value(ti, k, f[k])
		elif ty == Animation.TYPE_POSITION_3D:
			# (the hips: each axis as a scalar One Euro, metres)
			var vs := []
			for k in n:
				vs.append(anim.track_get_key_value(ti, k))
			for pass_i in 2:
				var idx := range(n) if pass_i == 0 else range(n - 1, -1, -1)
				var xf: Vector3 = vs[idx[0]]
				var dxf := 0.0
				for kk in range(1, n):
					var i: int = idx[kk]
					var dt := absf(ts[i] - ts[idx[kk - 1]])
					var v: Vector3 = vs[i]
					var dx := xf.distance_to(v) / maxf(dt, 1e-4)
					dxf = lerpf(dxf, dx, _alpha(EURO_DCUT, dt))
					xf = xf.lerp(v, _alpha(float(pr[0]) / scale + 2.0 * dxf, dt))
					vs[i] = xf
			for k in n:
				anim.track_set_key_value(ti, k, vs[k])


## A gesture's gather is a still body (Selwyn): through GestureBook's gather window the hips hold where they are at its
## start (eased in and out over 0.15 s) unless the source clearly moves them there (more than 10 degrees or 4 cm).
static func hold_hips(anim: Animation, clip: String) -> void:
	var g := GestureBook.of(clip)
	if g.is_empty():
		return
	var a := float(g.gather[0])
	var b := float(g.gather[1])
	var rt := anim.find_track(NodePath("X:Hips"), Animation.TYPE_ROTATION_3D)
	var pt := anim.find_track(NodePath("X:Hips"), Animation.TYPE_POSITION_3D)
	if rt < 0 or b - a < 0.3:
		return
	var q0 := anim.rotation_track_interpolate(rt, a)
	var p0: Vector3 = anim.position_track_interpolate(pt, a) if pt >= 0 else Vector3.ZERO
	var moved := 0.0
	var lift := 0.0
	for k in anim.track_get_key_count(rt):
		var t := anim.track_get_key_time(rt, k)
		if t >= a and t <= b:
			moved = maxf(moved, rad_to_deg((anim.track_get_key_value(rt, k) as Quaternion).angle_to(q0)))
			if pt >= 0:
				lift = maxf(lift, absf((anim.position_track_interpolate(pt, t) as Vector3).y - p0.y))
	if moved > 10.0 or lift > 0.04:
		return
	var ramp := 0.15
	for tr in [rt, pt]:
		if tr < 0:
			continue
		for k in anim.track_get_key_count(tr):
			var t := anim.track_get_key_time(tr, k)
			var w := smoothstep(a - ramp, a, t) * (1.0 - smoothstep(b, b + ramp, t))
			if w <= 0.0:
				continue
			if tr == rt:
				anim.track_set_key_value(tr, k, (anim.track_get_key_value(tr, k) as Quaternion).slerp(q0, w))
			else:
				anim.track_set_key_value(tr, k, (anim.track_get_key_value(tr, k) as Vector3).lerp(p0, w))


## Planted feet stay put (Selwyn: lock feet to the ground when foot speed is under 5 cm per second): each run of frames
## where an ankle moves slower than that holds the ankle at the run's start, the leg re-solved with a two-bone solve in
## its own bend plane, the foot keeping its angle; 3 frames of blend at each end of a run.
static func lock_feet(src: Skeleton3D, anim: Animation) -> int:
	var ps := PoseSkel.from(src)
	var ref := anim.find_track(NodePath("X:Hips"), Animation.TYPE_ROTATION_3D)
	if ref < 0:
		return 0
	var n := anim.track_get_key_count(ref)
	var fps := float(n - 1) / maxf(anim.length, 0.01)
	var locked := 0
	for side in ["Left", "Right"]:
		var ids := [ps.find_bone(side + "UpperLeg"), ps.find_bone(side + "LowerLeg"), ps.find_bone(side + "Foot")]
		var trs := []
		for bn in [side + "UpperLeg", side + "LowerLeg", side + "Foot"]:
			trs.append(anim.find_track(NodePath("X:" + bn), Animation.TYPE_ROTATION_3D))
		if ids.has(-1) or trs.has(-1):
			continue
		var ank := []
		for k in n:
			JointAudit.pose_at(ps, anim, anim.track_get_key_time(ref, k))
			ank.append(ps.get_bone_global_pose(ids[2]).origin)
		# the planted runs
		var plant := []
		for k in n:
			var v := 0.0 if k == 0 else (ank[k] as Vector3).distance_to(ank[k - 1]) * fps
			plant.append(v < 0.05)
		var k0 := 0
		while k0 < n:
			if not plant[k0]:
				k0 += 1
				continue
			var k1 := k0
			while k1 + 1 < n and plant[k1 + 1]:
				k1 += 1
			if k1 - k0 >= 2:
				var tgt: Vector3 = ank[k0]
				for k in range(maxi(k0 - 3, 0), mini(k1 + 4, n)):
					var w := 1.0
					if k < k0:
						w = float(k - (k0 - 4)) / 4.0
					elif k > k1:
						w = float((k1 + 4) - k) / 4.0
					var t := anim.track_get_key_time(ref, k)
					JointAudit.pose_at(ps, anim, t)
					var want: Vector3 = (ank[k] as Vector3).lerp(tgt, clampf(w, 0.0, 1.0))
					if (want - (ank[k] as Vector3)).length() < 0.0005:
						continue
					_leg_to(ps, ids, want)
					for j in 3:
						var kk := anim.track_find_key(trs[j], t, Animation.FIND_MODE_APPROX)
						if kk >= 0:
							anim.track_set_key_value(trs[j], kk, ps.get_bone_pose_rotation(ids[j]))
					locked += 1
			k0 = k1 + 1
	return locked


## Two-bone leg solve on a posed PoseSkel: the ankle onto `want`, the knee kept in its current bend plane, the foot's
## world orientation kept.
static func _leg_to(ps: PoseSkel, ids: Array, want: Vector3) -> void:
	var Hg := ps.get_bone_global_pose(ids[0])
	var Kg := ps.get_bone_global_pose(ids[1])
	var Ag := ps.get_bone_global_pose(ids[2])
	var H := Hg.origin
	var K := Kg.origin
	var A := Ag.origin
	var l1 := H.distance_to(K)
	var l2 := K.distance_to(A)
	var to := want - H
	var dd := clampf(to.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var dir := to.normalized()
	var nrm := (K - H).cross(A - K)
	if nrm.length() < 1e-5:
		nrm = Hg.basis.x
	var up := nrm.normalized().cross(dir).normalized()
	if (K - H).dot(up) < 0.0:
		up = -up
	var a := (l1 * l1 - l2 * l2 + dd * dd) / (2.0 * dd)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var K2 := H + dir * a + up * h
	var q1 := Quaternion((K - H).normalized(), (K2 - H).normalized())
	ps.set_bone_global_pose(ids[0], Transform3D(Basis(q1) * Hg.basis, H))
	var Kg2 := ps.get_bone_global_pose(ids[1])
	var A2 := ps.get_bone_global_pose(ids[2]).origin
	var q2 := Quaternion((A2 - Kg2.origin).normalized(), (H + dir * dd - Kg2.origin).normalized())
	ps.set_bone_global_pose(ids[1], Transform3D(Basis(q2) * Kg2.basis, Kg2.origin))
	var A3 := ps.get_bone_global_pose(ids[2]).origin
	ps.set_bone_global_pose(ids[2], Transform3D(Ag.basis, A3))


# ------------------------------------------------------------------------------------------------ the prebaked cache
## Selwyn (2026-10-20): no first-use hitch on stream (a lazy bake cost 67-130 ms). Every clip is baked offline per
## skeleton (tests/ext/movelib_prebake.gd) into BAKED_DIR/<rest key>/<clip>.res, signed with its sources; at load a
## character pulls hers in on background threads. A cache whose sources or bake version changed is never used.
const BAKED_DIR := "res://assets/animations/movelib_baked/"
const BAKE_VERSION := 4                  # (bump when the bake itself changes: every cached clip is rebuilt)


## The skeleton's identity for the cache: its bone names and rest transforms (two avatars with the same names but other
## proportions get their own bakes).
static func rest_key(sk) -> String:
	var parts := PackedStringArray()
	for i in sk.get_bone_count():
		var r: Transform3D = sk.get_bone_rest(i)
		parts.append("%s %.4f %.4f %.4f %.3f %.3f %.3f %.3f" % [sk.get_bone_name(i), r.origin.x, r.origin.y, r.origin.z,
			r.basis.get_rotation_quaternion().x, r.basis.get_rotation_quaternion().y, r.basis.get_rotation_quaternion().z, r.basis.get_rotation_quaternion().w])
	return ",".join(parts).md5_text().left(16)


## The sources a clip's bake depends on: the body landmarks, the hand tracks (clean or raw) and the bake version.
static func source_sig(json_path: String) -> String:
	var s := str(BAKE_VERSION) + "|" + str(CLEANUP)
	for p in [json_path, json_path.get_basename() + ".hands.clean.json", json_path.get_basename() + ".hands.json"]:
		if FileAccess.file_exists(p):
			s += "|" + FileAccess.get_md5(p)
	return s.md5_text()


static func cache_path(key: String, clip: String) -> String:
	return BAKED_DIR + key + "/" + clip + ".res"


## The prebaked clip for this skeleton, or null when there is none or it is stale.
static func cached(sk, json_path: String) -> Animation:
	if RenderProfile.options.has("no-prebake"):
		return null                               # (QA: measure the live bake it replaces)
	var p := cache_path(rest_key(sk), json_path.get_file().get_basename())
	if not ResourceLoader.exists(p):
		return null
	var a := load(p) as Animation
	if a == null or String(a.get_meta("src", "")) != source_sig(json_path):
		return null
	return a


## Bake and store one clip for this skeleton (the prebake tool). Returns the Animation.
static func bake_to_cache(sk: Skeleton3D, json_path: String) -> Animation:
	var a := bake(sk, json_path)
	if a == null:
		return null
	a.set_meta("src", source_sig(json_path))
	var p := cache_path(rest_key(sk), json_path.get_file().get_basename())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	ResourceSaver.save(a, p, ResourceSaver.FLAG_COMPRESS)
	return a
