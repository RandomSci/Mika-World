class_name PoseAuthor
extends RefCounted
## Choreography for the humanoid VRM skeleton, authored as POSES and solved against the actual skeleton's rest
## (visual pass 2: Oriel's transformation dance). A pose names where limbs POINT in the character's own space
## (skeleton space of a VRM 1.0 body: +Y up, +Z the way she faces, +X her left) and how the spine, neck and head
## TURN; the solver walks the bones parent-first, aims each named bone (shortest arc from the direction it
## inherits) and writes the local rotations as cubic keyframes. The same keys fit every VRoid body.
##   pose = {"aim": {"LeftUpperArm": Vector3(...), ...}, "turn": {"Head": Vector3(pitch, yaw, roll) degrees}}
## Right-side bones mirror the left ones when a pose is built with `mirror()` / `sym()`.

static func _bone_dir(sk: Skeleton3D, b: int) -> Vector3:
	var kids := sk.get_bone_children(b)
	if kids.is_empty():
		return Vector3.UP
	var pick := int(kids[0])
	for k in kids:
		var nm := sk.get_bone_name(int(k))
		if nm.contains("Middle") or nm.contains("LowerArm") or nm.contains("LowerLeg") or nm.contains("Hand") or nm.contains("Foot") or nm.contains("Neck") or nm.contains("Head") or nm.contains("Spine") or nm.contains("Chest"):
			pick = int(k)
			break
	var p := sk.get_bone_rest(pick).origin
	return p.normalized() if p.length() > 1e-4 else Vector3.UP


## Local rotation per bone name for one pose (parents first; untouched bones keep their rest rotation).
static func solve(sk: Skeleton3D, pose: Dictionary) -> Dictionary:
	var aim: Dictionary = pose.get("aim", {})
	var turn: Dictionary = pose.get("turn", {})
	var glob := {}
	var out := {}
	for b in sk.get_bone_count():
		var p := sk.get_bone_parent(b)
		var rest := sk.get_bone_rest(b)
		var pb: Basis = glob[p] if p >= 0 and glob.has(p) else Basis()
		var g: Basis = pb * rest.basis.orthonormalized()
		var nm := sk.get_bone_name(b)
		if turn.has(nm):
			var e: Vector3 = turn[nm]
			g = Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))) * g
		if aim.has(nm):
			var d0: Vector3 = (g * _bone_dir(sk, b)).normalized()
			var d1: Vector3 = (aim[nm] as Vector3).normalized()
			if d0.dot(d1) < 0.9999:
				g = Basis(Quaternion(d0, d1)) * g
		glob[b] = g
		out[nm] = (pb.inverse() * g).get_rotation_quaternion()
	return out


## Mirror a left-side pose dictionary onto the right side (X flips; yaw and roll flip for turns).
static func sym(pose: Dictionary) -> Dictionary:
	var out := {"aim": {}, "turn": {}}
	for k in pose.get("aim", {}):
		out.aim[k] = pose.aim[k]
		if String(k).begins_with("Left"):
			var v: Vector3 = pose.aim[k]
			var rk := "Right" + String(k).trim_prefix("Left")
			if not pose.aim.has(rk):
				out.aim[rk] = Vector3(-v.x, v.y, v.z)
	for k in pose.get("turn", {}):
		out.turn[k] = pose.turn[k]
	return out


## Merge poses (later keys win).
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"aim": (a.get("aim", {}) as Dictionary).duplicate(), "turn": (a.get("turn", {}) as Dictionary).duplicate()}
	out.aim.merge(b.get("aim", {}), true)
	out.turn.merge(b.get("turn", {}), true)
	return out


## An Animation from timed poses: keys = [[t, pose], ...]. Only bones named somewhere in the keys (and their
## chains) get tracks; fingers and the rest stay with whatever the character plays underneath.
static func build(sk: Skeleton3D, skel_path: String, keys: Array, length: float) -> Animation:
	var names := {}
	for kp in keys:
		var pose: Dictionary = kp[1]
		for n in pose.get("aim", {}):
			names[n] = true
		for n in pose.get("turn", {}):
			names[n] = true
	var anim := Animation.new()
	anim.length = length
	var tracks := {}
	for n in names:
		if sk.find_bone(String(n)) < 0:
			continue
		var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(ti, NodePath(skel_path + ":" + String(n)))
		anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_CUBIC)
		tracks[n] = ti
	var prev := {}
	for kp in keys:
		var t: float = kp[0]
		var q := solve(sk, kp[1])
		for n in tracks:
			var r: Quaternion = q.get(n, Quaternion())
			if prev.has(n) and (prev[n] as Quaternion).dot(r) < 0.0:
				r = -r
			prev[n] = r
			anim.rotation_track_insert_key(tracks[n], t, r)
	return anim
