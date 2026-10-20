class_name MocapBake
extends RefCounted
## Move Library clips (Part A, 2026-10-19): MediaPipe world landmarks (tools/mocap/extract_landmarks.py, already
## smoothed) turned into an Animation for THIS skeleton - so each girl and every form gets her own fit, with no export
## step. Every bone of her humanoid rig is aimed, parents first, along the direction the matching landmarks give
## (shoulder -> elbow, elbow -> wrist, hip -> knee ...), its twist carried from its parent; the hips and the torso take
## their full orientation from the hip and shoulder lines; the head from the ears and nose. Her hips sit as high above
## the floor as the actor's do, scaled by leg length (so seated clips sit). Fingers keep their rest (SoftArms curls them).

const LM_LEFT := {"Shoulder": 11, "Elbow": 13, "Wrist": 15, "Pinky": 17, "Index": 19, "Hip": 23, "Knee": 25, "Ankle": 27, "Heel": 29, "FootIdx": 31}
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
							var cur := D * d0
							d = Basis(Quaternion(cur.normalized(), aim.normalized())) * D
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
		var hp: Vector3 = sk.get_bone_rest(B.call("Hips")).origin
		anim.position_track_insert_key(hips_t, time, hp + up * (h - hips_rest_h))
	return anim


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
