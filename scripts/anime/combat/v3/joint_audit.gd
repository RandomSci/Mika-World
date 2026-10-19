class_name JointAudit
extends RefCounted
## Combat v3: the human joint rules for ANY pose of a VRM skeleton - the fight rig's (MeleeFighter.audit) applied to a
## clip, a mocap bake, a cutscene pose. Per limb: a knee / elbow that folds against its own hinge, a thigh / upper arm
## turned about itself past a human hip / shoulder, a knee pointing behind her pelvis (the hip -> ankle line, her
## pelvis's left axis turned with her foot, as MeleeFighter.knee_dir). Bend under 8 deg is straight: not judged.

const ARMS := {"lh": ["LeftUpperArm", "LeftLowerArm", "LeftHand"], "rh": ["RightUpperArm", "RightLowerArm", "RightHand"]}
const LEGS := {"lf": ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], "rf": ["RightUpperLeg", "RightLowerLeg", "RightFoot"]}
const HINGE := {"lf": Vector3(1, 0, 0), "rf": Vector3(1, 0, 0), "lh": Vector3(0, -1, 0), "rh": Vector3(0, 1, 0)}
const TWIST_LIMIT := {"lh": 100.0, "rh": 100.0, "lf": 60.0, "rf": 60.0}


## The faults of this pose: [{limb, why, bend, twist}]. `sk` must have its pose set (global poses up to date).
static func check(sk) -> Array:
	var out := []
	var hips: int = sk.find_bone("Hips")
	if hips < 0:
		return out
	var hb: Basis = sk.get_bone_global_pose(hips).basis.orthonormalized()
	for limb in ["lf", "rf", "lh", "rh"]:
		var b: Array = LEGS[limb] if LEGS.has(limb) else ARMS[limb]
		var ri: int = sk.find_bone(b[0])
		var mi: int = sk.find_bone(b[1])
		var ei: int = sk.find_bone(b[2])
		if ri < 0 or mi < 0 or ei < 0:
			continue
		var R: Transform3D = sk.get_bone_global_pose(ri)
		var M: Transform3D = sk.get_bone_global_pose(mi)
		var E: Transform3D = sk.get_bone_global_pose(ei)
		var up := M.origin - R.origin
		var fo := E.origin - M.origin
		var bend := rad_to_deg(up.angle_to(fo))
		var tw := twist(sk, ri)
		if absf(tw) > float(TWIST_LIMIT[limb]) + 6.0:
			out.append({"limb": limb, "why": "%s turned %.0f deg about itself (human limit %.0f)" % ["thigh" if LEGS.has(limb) else "upper arm", tw, TWIST_LIMIT[limb]], "bend": snappedf(bend, 1.0), "twist": snappedf(tw, 1.0)})
			continue
		if bend < 8.0:
			continue
		var h: Vector3 = (R.basis.orthonormalized() * (sk.get_bone_global_rest(ri).basis.orthonormalized().inverse() * (HINGE[limb] as Vector3))).normalized()
		var n := up.cross(fo).normalized()
		if n.dot(h) < -0.2:
			out.append({"limb": limb, "why": "folds against its hinge (%.0f deg)" % bend, "bend": snappedf(bend, 1.0), "twist": snappedf(tw, 1.0)})
			continue
		if LEGS.has(limb):
			# her knee's way: the hip -> ankle line crossed with the pelvis's left axis turned by the foot's yaw from it
			var line := E.origin - R.origin
			var fwd_f: Vector3 = E.basis.orthonormalized() * (sk.get_bone_global_rest(ei).basis.orthonormalized().inverse() * Vector3(0, 0, 1))
			var fwd_p := hb * Vector3(0, 0, 1)
			var upv := hb * Vector3(0, 1, 0)
			var ff := fwd_f - upv * fwd_f.dot(upv)
			var fp := fwd_p - upv * fwd_p.dot(upv)
			var rel := 0.0
			if ff.length() > 0.2 and fp.length() > 0.2:
				rel = rad_to_deg(fp.signed_angle_to(ff, upv))
			rel = clampf(rel, -35.0, 50.0) if limb == "lf" else clampf(rel, -50.0, 35.0)
			var hp := (hb * (Basis(Vector3.UP, deg_to_rad(rel)) * Vector3(1, 0, 0))).normalized()
			var kd := line.normalized().cross(hp)
			if kd.length() > 0.05:
				var off := M.origin - (R.origin + line * 0.5)
				off -= line.normalized() * off.dot(line.normalized())
				if off.length() > 0.01 and off.normalized().dot(kd.normalized()) < -0.2:
					out.append({"limb": limb, "why": "knee points behind her (%.0f deg)" % bend, "bend": snappedf(bend, 1.0), "twist": snappedf(tw, 1.0)})
	return out


## How far a bone is turned about its own axis from the plain swing out of its rest, in its parent's frame (deg) -
## the anatomical twist (MeleeFighter.anat_twist).
static func twist(sk, bi: int) -> float:
	var par: int = sk.get_bone_parent(bi)
	if par < 0:
		return 0.0
	var rel_now: Basis = sk.get_bone_global_pose(par).basis.orthonormalized().inverse() * sk.get_bone_global_pose(bi).basis.orthonormalized()
	var rel_rest: Basis = sk.get_bone_global_rest(par).basis.orthonormalized().inverse() * sk.get_bone_global_rest(bi).basis.orthonormalized()
	var a0 := (rel_rest * Vector3.UP).normalized()
	var a1 := (rel_now * Vector3.UP).normalized()
	var q := Quaternion(rel_now) * Quaternion(rel_rest).inverse()
	var sw := Quaternion(a0, a1) if a0.dot(a1) > -0.999 else Quaternion(a0.cross(Vector3.RIGHT).normalized(), PI)
	var tw := sw.inverse() * q
	return rad_to_deg(wrapf(2.0 * atan2(Vector3(tw.x, tw.y, tw.z).dot(a0), tw.w), -PI, PI))


## A bare copy of a skeleton (bones, parents, rests) to pose clips on offline.
static func bare_copy(src: Skeleton3D) -> Skeleton3D:
	var sk := Skeleton3D.new()
	for i in src.get_bone_count():
		sk.add_bone(src.get_bone_name(i))
	for i in src.get_bone_count():
		sk.set_bone_parent(i, src.get_bone_parent(i))
		sk.set_bone_rest(i, src.get_bone_rest(i))
		sk.set_bone_pose(i, src.get_bone_rest(i))
	return sk


## Pose `sk` at time `t` of an Animation whose tracks are "<anything>:<Bone>" (rotation / position).
static func pose_at(sk, anim: Animation, t: float) -> void:
	for ti in anim.get_track_count():
		var bone := String(anim.track_get_path(ti)).get_slice(":", 1)
		var bi: int = sk.find_bone(bone)
		if bi < 0:
			continue
		match anim.track_get_type(ti):
			Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bi, anim.rotation_track_interpolate(ti, t))
			Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bi, anim.position_track_interpolate(ti, t))



## How un-human one limb is right now: degrees of twist past the limit, plus 200 for a fold against the hinge, plus 200
## for a knee behind her (0 = a human limb).
static func limb_cost(sk, limb: String) -> float:
	var c := 0.0
	for f in check(sk):
		if String(f.limb) != limb:
			continue
		if String(f.why).contains("turned"):
			c += absf(float(f.twist)) - float(TWIST_LIMIT[limb])
		else:
			c += 200.0
	return c


## Make one limb human on this pose: swing it about its root -> end line (10 deg steps round the circle; the end stays
## put), each try with the knee / elbow hinge lined up across the bend, and keep the best. The hand / foot keeps its
## world orientation. Returns true if the pose changed.
static func fix_limb(sk, limb: String) -> bool:
	var b: Array = LEGS[limb] if LEGS.has(limb) else ARMS[limb]
	var ri: int = sk.find_bone(b[0])
	var mi: int = sk.find_bone(b[1])
	var ei: int = sk.find_bone(b[2])
	var c0 := limb_cost(sk, limb)
	if c0 <= 0.0:
		return false
	var q0: Quaternion = sk.get_bone_pose_rotation(ri)
	var q1: Quaternion = sk.get_bone_pose_rotation(mi)
	var q2: Quaternion = sk.get_bone_pose_rotation(ei)
	var end_g: Basis = sk.get_bone_global_pose(ei).basis
	var u: Vector3 = (sk.get_bone_global_pose(ei).origin - sk.get_bone_global_pose(ri).origin).normalized()
	var best := INF
	var best_c := c0
	for k in 36:
		var phi := deg_to_rad(float(k) * 10.0 - (360.0 if k > 18 else 0.0))
		sk.set_bone_pose_rotation(ri, q0)
		sk.set_bone_pose_rotation(mi, q1)
		sk.set_bone_pose_rotation(ei, q2)
		var R: Transform3D = sk.get_bone_global_pose(ri)
		sk.set_bone_global_pose(ri, Transform3D(Basis(u, phi) * R.basis, R.origin))
		_align(sk, limb, ri, mi, ei)
		var cst := limb_cost(sk, limb)
		if cst < best_c - 0.01 or (absf(cst - best_c) <= 0.01 and absf(phi) < absf(best)):
			best_c = cst
			best = phi
	sk.set_bone_pose_rotation(ri, q0)
	sk.set_bone_pose_rotation(mi, q1)
	sk.set_bone_pose_rotation(ei, q2)
	if best == INF:
		return false
	var R2: Transform3D = sk.get_bone_global_pose(ri)
	sk.set_bone_global_pose(ri, Transform3D(Basis(u, best) * R2.basis, R2.origin))
	_align(sk, limb, ri, mi, ei)
	if best_c > 0.0:
		# no swing keeps the end AND makes the limb human (a flip, a deep crouch on a cropped clip): turn the hip /
		# shoulder back inside its range about the bone itself - the hand / foot moves a little instead
		var tw := twist(sk, ri)
		var lim: float = float(TWIST_LIMIT[limb]) - 2.0
		if absf(tw) > lim:
			var Rt: Transform3D = sk.get_bone_global_pose(ri)
			var ax: Vector3 = (sk.get_bone_global_pose(mi).origin - Rt.origin).normalized()
			var dl := deg_to_rad(clampf(tw, -lim, lim) - tw)
			var qa: Quaternion = sk.get_bone_pose_rotation(ri)
			var ca := limb_cost(sk, limb)
			var keep_q := qa
			for sgn in [1.0, -1.0]:
				sk.set_bone_pose_rotation(ri, qa)
				sk.set_bone_global_pose(ri, Transform3D(Basis(ax, dl * sgn) * Rt.basis, Rt.origin))
				var cs := limb_cost(sk, limb)
				if cs < ca - 0.01:
					ca = cs
					keep_q = sk.get_bone_pose_rotation(ri)
			sk.set_bone_pose_rotation(ri, keep_q)          # (only if it is more human than the best swing)
	var E: Transform3D = sk.get_bone_global_pose(ei)
	sk.set_bone_global_pose(ei, Transform3D(end_g, E.origin))
	return true


## Turn the upper bone, then the lower, about their own axes so the hinge lies across the bend (MeleeFighter._align_hinge).
static func _align(sk, limb: String, ri: int, mi: int, ei: int) -> void:
	var R: Transform3D = sk.get_bone_global_pose(ri)
	var M: Transform3D = sk.get_bone_global_pose(mi)
	var E: Transform3D = sk.get_bone_global_pose(ei)
	var up := M.origin - R.origin
	var fo := E.origin - M.origin
	var n := up.cross(fo)
	if n.length() < 0.06 * up.length() * fo.length():
		return
	n = n.normalized()
	var hs: Vector3 = HINGE[limb]
	var ax := up.normalized()
	var h: Vector3 = R.basis.orthonormalized() * (sk.get_bone_global_rest(ri).basis.orthonormalized().inverse() * hs)
	var ang := (h - ax * h.dot(ax)).signed_angle_to(n - ax * n.dot(ax), ax)
	sk.set_bone_global_pose(ri, Transform3D(Basis(ax, ang) * R.basis, R.origin))
	M = sk.get_bone_global_pose(mi)
	var ax2 := fo.normalized()
	var h2: Vector3 = M.basis.orthonormalized() * (sk.get_bone_global_rest(mi).basis.orthonormalized().inverse() * hs)
	var ang2 := (h2 - ax2 * h2.dot(ax2)).signed_angle_to(n - ax2 * n.dot(ax2), ax2)
	sk.set_bone_global_pose(mi, Transform3D(Basis(ax2, ang2) * M.basis, M.origin))


## The final pass of a mocap bake: every key frame posed on a bare copy of `src`; any limb the joint rules reject is
## made human (fix_limb) and its three bones' keys rewritten. Tracks are "<anything>:<Bone>". Returns frames fixed.
static func fix_anim(src: Skeleton3D, anim: Animation) -> int:
	var sk := PoseSkel.from(src)                        # (plain data: works anywhere, even while characters are built)
	var tr := {}
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
			tr[String(anim.track_get_path(ti)).get_slice(":", 1)] = ti
	var ref: int = tr.get("Hips", -1)
	if ref < 0:
		return 0
	var fixed := 0
	var good := {}                                      # limb -> its last human [upper, lower] local rotations
	for ki in anim.track_get_key_count(ref):
		var t := anim.track_get_key_time(ref, ki)
		pose_at(sk, anim, t)
		var any := false
		for limb in ["lf", "rf", "lh", "rh"]:
			var b0: Array = LEGS[limb] if LEGS.has(limb) else ARMS[limb]
			var changed := fix_limb(sk, limb)
			if limb_cost(sk, limb) > 0.0 and good.has(limb):
				# still not human (a glitch of the source): hold its last human pose for this frame, hand / foot
				# keeping their world orientation
				var ei: int = sk.find_bone(b0[2])
				var end_g: Basis = sk.get_bone_global_pose(ei).basis
				sk.set_bone_pose_rotation(sk.find_bone(b0[0]), good[limb][0])
				sk.set_bone_pose_rotation(sk.find_bone(b0[1]), good[limb][1])
				sk.set_bone_global_pose(ei, Transform3D(end_g, sk.get_bone_global_pose(ei).origin))
				changed = true
			if limb_cost(sk, limb) <= 0.0:
				good[limb] = [sk.get_bone_pose_rotation(sk.find_bone(b0[0])), sk.get_bone_pose_rotation(sk.find_bone(b0[1]))]
			if changed:
				any = true
				var b: Array = b0
				for bn in b:
					if tr.has(bn):
						var ti2: int = tr[bn]
						var kk := anim.track_find_key(ti2, t, Animation.FIND_MODE_APPROX)
						if kk >= 0:
							anim.track_set_key_value(ti2, kk, sk.get_bone_pose_rotation(sk.find_bone(bn)))
		if any:
			fixed += 1
	return fixed


# ------------------------------------------------------------------------------------------------ the full body rules
## Selwyn's limits (2026-10-20): the old audit only checked folds against the hinge, upper arm / thigh twist and knees
## behind her; bent back wrists, candy wrapped elbows and a forearm inside her waist all passed.
const LIM := {
	"elbow_flex": 150.0, "elbow_hyper": 5.0, "knee_flex": 150.0, "knee_hyper": 5.0,
	"wrist_flex": 75.0, "wrist_ext": 70.0, "wrist_radial": 20.0, "wrist_ulnar": 35.0,
	# no twist bones in the VRMs: the forearm's turn shows as a twist of the lower arm (wrapping at the elbow) or of
	# the hand (wrapping at the wrist); past these the skin visibly wraps like a sweet wrapper
	"elbow_twist": 45.0, "wrist_twist": 50.0,
	"finger_back_proximal": 25.0, "finger_back_distal": 10.0,
	"penetration": 0.01,
}
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]


## Every measure of the pose per side, and the faults past LIM: {"values": {...}, "faults": [{rule, side, value, limit}]}.
## `surface` (a BodySurface, optional) adds the penetration of her forearms, hands and fingertips into her body.
static func measure(sk, surface = null, curl_axis := {}) -> Dictionary:
	var vals := {}
	var faults := []
	var gpose := func(bi: int) -> Transform3D: return sk.get_bone_global_pose(bi)
	var add := func(rule: String, side: String, v: float, lim: float):
		var sv := snappedf(v, 0.001 if rule == "penetration" else 0.1)
		vals[side + "_" + rule] = sv
		if v > lim:
			faults.append({"rule": rule, "side": side, "value": sv, "limit": lim})
	for side in ["Left", "Right"]:
		var ua: int = sk.find_bone(side + "UpperArm")
		var la: int = sk.find_bone(side + "LowerArm")
		var ha: int = sk.find_bone(side + "Hand")
		if ua < 0 or la < 0 or ha < 0:
			continue
		var limb := "lh" if side == "Left" else "rh"
		# elbow: flex 0 - 150, at most 5 of hyperextension (a bend against the hinge)
		var U: Vector3 = gpose.call(ua).origin
		var L: Vector3 = gpose.call(la).origin
		var H: Vector3 = gpose.call(ha).origin
		var bend := rad_to_deg((L - U).angle_to(H - L))
		var hinge: Vector3 = ((gpose.call(ua) as Transform3D).basis.orthonormalized() * (sk.get_bone_global_rest(ua).basis.orthonormalized().inverse() * (HINGE[limb] as Vector3))).normalized()
		var against := (L - U).cross(H - L).dot(hinge) < 0.0 and bend > 2.0
		add.call("elbow_flex", side, 0.0 if against else bend, LIM.elbow_flex)
		add.call("elbow_hyper", side, bend if against else 0.0, LIM.elbow_hyper)
		add.call("elbow_twist", side, absf(twist(sk, la)), LIM.elbow_twist)
		add.call("wrist_twist", side, absf(twist(sk, ha)), LIM.wrist_twist)
		# wrist: the hand's direction in the forearm's own rest frame - flexion toward the palm, extension away,
		# radial toward the thumb, ulnar toward the little finger
		var mp: int = sk.find_bone(side + "MiddleProximal")
		var tp: int = sk.find_bone(side + "ThumbProximal")
		if mp >= 0 and tp >= 0:
			var Lr: Transform3D = sk.get_bone_global_rest(la)
			var Hr: Transform3D = sk.get_bone_global_rest(ha)
			var f := (Hr.origin - Lr.origin).normalized()
			var t: Vector3 = sk.get_bone_global_rest(tp).origin - Hr.origin
			t = (t - f * t.dot(f)).normalized()
			var n := f.cross(t).normalized()
			if n.y > 0.0:
				n = -n                                  # (the palm faces down in the T-pose)
			var n0 := n                                 # (the rest palm normal, carried by the hand itself for the fingers)
			var carry: Basis = (gpose.call(la) as Transform3D).basis.orthonormalized() * Lr.basis.orthonormalized().inverse()
			var hcarry: Basis = (gpose.call(ha) as Transform3D).basis.orthonormalized() * Hr.basis.orthonormalized().inverse()
			# the hand's roll about the forearm (pronation / supination carried by the hand bone) turns the frame the
			# wrist bends in: flexion is toward the rolled palm, not toward where the palm faced at rest
			var qr := Quaternion((carry.inverse() * hcarry).orthonormalized())
			var tau := 2.0 * atan2(Vector3(qr.x, qr.y, qr.z).dot(f), qr.w)
			n = n.rotated(f, tau)
			t = t.rotated(f, tau)
			var h: Vector3 = carry.inverse() * (((gpose.call(mp) as Transform3D).origin - H).normalized())
			var h0: Vector3 = (sk.get_bone_global_rest(mp).origin - Hr.origin).normalized().rotated(f, tau)
			var flex := rad_to_deg(atan2(h.dot(n), h.dot(f))) - rad_to_deg(atan2(h0.dot(n), h0.dot(f)))
			var dev := rad_to_deg(atan2(h.dot(t), h.dot(f))) - rad_to_deg(atan2(h0.dot(t), h0.dot(f)))
			add.call("wrist_flex", side, maxf(flex, 0.0), LIM.wrist_flex)
			add.call("wrist_ext", side, maxf(-flex, 0.0), LIM.wrist_ext)
			add.call("wrist_radial", side, maxf(dev, 0.0), LIM.wrist_radial)
			add.call("wrist_ulnar", side, maxf(-dev, 0.0), LIM.wrist_ulnar)
			# fingers: never bent backwards. Each joint's own rotation from rest, its part about the joint's closing
			# axis (SoftArms._curl_axis, the axis the rig and the bake curl fingers about): negative = toward the back
			var worst_p := 0.0
			var worst_d := 0.0
			for fn in FINGERS:
				if fn == "Thumb":
					continue
				var chain := ["Proximal", "Intermediate", "Distal"]
				for j in chain.size():
					var a2: int = sk.find_bone(side + fn + chain[j])
					if a2 < 0:
						continue
					var ax: Vector3 = curl_axis.get(a2, Vector3.ZERO)
					if ax == Vector3.ZERO:
						continue
					var qrel: Quaternion = sk.get_bone_rest(a2).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(a2)
					if qrel.w < 0.0:
						qrel = -qrel
					var curl := rad_to_deg(2.0 * atan2(Vector3(qrel.x, qrel.y, qrel.z).dot(ax), qrel.w))
					if j == 0:
						worst_p = maxf(worst_p, -curl)
					else:
						worst_d = maxf(worst_d, -curl)
			add.call("finger_back_proximal", side, worst_p, LIM.finger_back_proximal)
			add.call("finger_back_distal", side, worst_d, LIM.finger_back_distal)
		# legs
		var ul: int = sk.find_bone(side + "UpperLeg")
		var ll: int = sk.find_bone(side + "LowerLeg")
		var fo: int = sk.find_bone(side + "Foot")
		if ul >= 0 and ll >= 0 and fo >= 0:
			var A: Vector3 = gpose.call(ul).origin
			var K: Vector3 = gpose.call(ll).origin
			var F: Vector3 = gpose.call(fo).origin
			var kb := rad_to_deg((K - A).angle_to(F - K))
			var lf := "lf" if side == "Left" else "rf"
			var kh: Vector3 = ((gpose.call(ul) as Transform3D).basis.orthonormalized() * (sk.get_bone_global_rest(ul).basis.orthonormalized().inverse() * (HINGE[lf] as Vector3))).normalized()
			var k_against := (K - A).cross(F - K).dot(kh) < 0.0 and kb > 2.0
			add.call("knee_flex", side, 0.0 if k_against else kb, LIM.knee_flex)
			add.call("knee_hyper", side, kb if k_against else 0.0, LIM.knee_hyper)
		# penetration: forearm line, hand centre and the fingertips against her body (torso, legs, head, clothing)
		if surface != null:
			var worst := 0.0
			var where := ""
			var probes := []
			for k in 5:
				probes.append([L.lerp(H, 0.2 + 0.18 * k), float(surface.radius.get(side + "LowerArm", 0.03))])
			var mpp: int = sk.find_bone(side + "MiddleProximal")
			if mpp >= 0:
				probes.append([H.lerp((gpose.call(mpp) as Transform3D).origin, 0.5), float(surface.radius.get(side + "Hand", 0.02)) * 0.7])
			for fn in FINGERS:
				var tip: int = sk.find_bone(side + fn + "Distal")
				if tip >= 0:
					probes.append([(gpose.call(tip) as Transform3D).origin, 0.008])
			for pr in probes:
				var r: Array = surface.signed(pr[0], sk, gpose)
				var depth := float(pr[1]) - float(r[0])
				if depth > worst:
					worst = depth
					where = String(r[1])
			add.call("penetration", side, worst, LIM.penetration)
			for fl in faults:
				if String(fl.rule) == "penetration" and String(fl.side) == side:
					fl["into"] = where
	return {"values": vals, "faults": faults}


## Each finger joint's closing axis in its own frame (bone index -> axis), from her rest skeleton (Skeleton3D).
static func finger_axes(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for side in ["Left", "Right"]:
		for fn in FINGERS:
			for seg in ["Proximal", "Intermediate", "Distal"]:
				var bi := sk.find_bone(side + fn + seg)
				if bi >= 0:
					out[bi] = SoftArms._curl_axis(sk, bi)
	return out
