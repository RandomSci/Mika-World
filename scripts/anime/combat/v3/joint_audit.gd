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
