class_name HandGuard
extends SkeletonModifier3D
## Hands never inside a body (2026-10-19, Selwyn: "Mika's hand is inside her cheek in the close up. Add self collision
## for hands on both girls."). Every frame, after the animation and every pose correction: invisible shapes are built
## from her own bones (a head/face sphere, neck, chest, hips, thighs, shins and the OTHER arm), and from the other
## girl's body too; each hand and its fingertips are tested against them; a hand inside one is pushed out to the
## surface with two-bone IK on its arm (the elbow bends, the hand slides along the skin instead of sinking in).
## settle() puts it last among the pose modifiers (just before the dress simulation).

const MARGIN := 0.012                    # skin clearance
var others: Array = []                   # other WorldCharacters whose bodies count too
var pushes := 0                          # QA: frames a hand was pushed out (since the start)
var last_depth := 0.0                    # QA: the deepest penetration found this frame (m)
var skip := {"Left": false, "Right": false}   # set by the PosePipeline: a hand an action holds on purpose (an oar grip)
var _ids := {}
var _frame := Basis()
var _ok := false
# the push, smoothed: in fast, out slower. Applied raw it snapped the arm for single frames whenever a hand brushed
# past her body in a dance (the push switching on at 2 mm, its direction flipping between shapes): 13-16 deg jitter
const PUSH_IN_S := 0.03
const PUSH_OUT_S := 0.12
var _push_s := {"Left": Vector3.ZERO, "Right": Vector3.ZERO}


static func attach(sk: Skeleton3D) -> HandGuard:
	for n in sk.get_children():
		if n is HandGuard:
			return n
	var g := HandGuard.new()
	g.name = "HandGuard"
	sk.add_child(g)
	g.settle()
	return g


## Its place in the stack is the PosePipeline's (collision stage).
func settle() -> void:
	var sk0 := get_skeleton()
	if sk0:
		PosePipeline.arrange_for(sk0)
		return
	var sk := get_skeleton()
	if sk == null:
		return
	var at := sk.get_child_count() - 1
	for n in sk.get_children():
		if n is DressSim or n.get_class() == "SpringBoneSimulator3D" or n is SkirtDrape or String(n.name) == "HeadLook":
			at = mini(at, n.get_index())
			break
	sk.move_child(self, maxi(at - (1 if get_index() < at else 0), 0))


func _setup() -> void:
	var sk := get_skeleton()
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
			"RightLowerArm", "RightHand", "LeftMiddleDistal", "LeftIndexDistal", "LeftLittleDistal", "LeftThumbDistal",
			"RightMiddleDistal", "RightIndexDistal", "RightLittleDistal", "RightThumbDistal"]:
		_ids[n] = sk.find_bone(n)
	var rest := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(n)).origin
	var u: Vector3 = (rest.call("Head") - rest.call("Hips")).normalized()
	var toe: Vector3 = rest.call("LeftToes") - rest.call("LeftFoot") if sk.find_bone("LeftToes") >= 0 else Vector3(0, 0, 1)
	toe = (toe - u * toe.dot(u)).normalized()
	_frame = Basis(toe.cross(u).normalized(), u, toe)
	_ok = true


## The body as capsules [a, b, r] (a == b: a sphere), in THIS skeleton's space. hands_side: the side whose hand is
## being tested (its own arm is left out; the other arm counts).
func _shapes(sk: Skeleton3D, hands_side: String) -> Array:
	var P := func(n: String) -> Vector3:
		var bi: int = _ids.get(n, -1)
		return sk.get_bone_global_pose(bi).origin if bi >= 0 else Vector3.INF
	var u: Vector3 = _frame.y
	var f: Vector3 = _frame.z
	var hips: Vector3 = P.call("Hips")
	var chest: Vector3 = P.call("Chest")
	var upper: Vector3 = P.call("UpperChest") if int(_ids.UpperChest) >= 0 else chest
	var neck: Vector3 = P.call("Neck")
	var head: Vector3 = P.call("Head")
	var hb: Basis = sk.get_bone_global_pose(_ids.Head).basis.orthonormalized()
	var hf: Vector3 = (hb * (sk.get_bone_global_rest(_ids.Head).basis.inverse() * f)).normalized()
	var hu: Vector3 = (hb * (sk.get_bone_global_rest(_ids.Head).basis.inverse() * u)).normalized()
	var out := [
		[head + hu * 0.075, head + hu * 0.075, 0.098],                               # skull
		[head + hu * 0.045 + hf * 0.045, head + hu * 0.045 + hf * 0.045, 0.072],     # face (cheeks, mouth, chin)
		[neck, head, 0.048],
		[upper, neck, 0.1],
		[chest, upper, 0.11],
		[upper + f * 0.065 - u * 0.045, upper + f * 0.065 - u * 0.045, 0.075],       # bust
		[hips, chest, 0.115],
	]
	for s in ["Left", "Right"]:
		out.append([P.call(s + "UpperLeg"), P.call(s + "LowerLeg"), 0.075])
		out.append([P.call(s + "LowerLeg"), P.call(s + "Foot"), 0.05])
	var other_side := "Right" if hands_side == "Left" else "Left"
	out.append([P.call(other_side + "UpperArm"), P.call(other_side + "LowerArm"), 0.042])
	out.append([P.call(other_side + "LowerArm"), P.call(other_side + "Hand"), 0.035])
	return out


func _others_shapes(sk: Skeleton3D) -> Array:
	var out := []
	var inv := sk.global_transform.affine_inverse()
	for o in others:
		if o == null or not is_instance_valid(o) or not o.visible:
			continue
		var osk: Skeleton3D = o.skeleton
		var g := osk.global_transform
		var Q := func(n: String) -> Vector3:
			var bi := osk.find_bone(n)
			return inv * (g * osk.get_bone_global_pose(bi).origin) if bi >= 0 else Vector3.INF
		out.append([Q.call("Head"), Q.call("Head") + (Q.call("Head") - Q.call("Neck")) * 0.8, 0.11])
		out.append([Q.call("Hips"), Q.call("Neck"), 0.13])
		for s in ["Left", "Right"]:
			out.append([Q.call(s + "UpperLeg"), Q.call(s + "LowerLeg"), 0.08])
			out.append([Q.call(s + "LowerLeg"), Q.call(s + "Foot"), 0.055])
			out.append([Q.call(s + "UpperArm"), Q.call(s + "Hand"), 0.045])
	return out


func _push(p: Vector3, shapes: Array) -> Vector3:
	var push := Vector3.ZERO
	for sh in shapes:
		var a: Vector3 = sh[0]
		var b: Vector3 = sh[1]
		if a == Vector3.INF or b == Vector3.INF:
			continue
		var c := a if a.is_equal_approx(b) else Geometry3D.get_closest_point_to_segment(p + push, a, b)
		var d := (p + push) - c
		var need: float = float(sh[2]) + MARGIN - d.length()
		if need > 0.0:
			var n := d.normalized() if d.length() > 0.0001 else _frame.z
			push += n * need
			last_depth = maxf(last_depth, need)
	return push


var _scan := 0.0


func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = 2.0
		var me := get_skeleton().get_parent()
		while me and not (me is WorldCharacter):
			me = me.get_parent()
		others.clear()
		for w in get_tree().root.find_children("*", "WorldCharacter", true, false):
			if w != me:
				others.append(w)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ok:
		_setup()
	if RenderProfile.options.has("no-hand-guard"):
		return
	var dt := maxf(get_process_delta_time() if is_inside_tree() else 0.016, 0.001)
	last_depth = 0.0
	var theirs := _others_shapes(sk)
	for side in ["Left", "Right"]:
		var ids := [_ids[side + "UpperArm"], _ids[side + "LowerArm"], _ids[side + "Hand"]]
		if ids.has(-1) or bool(skip.get(side, false)):
			continue
		var shapes := _shapes(sk, side) + theirs
		var hand := sk.get_bone_global_pose(ids[2]).origin
		var push := Vector3.ZERO
		for it in 2:
			var p := _push(hand + push, shapes)
			for tip in ["MiddleDistal", "IndexDistal", "LittleDistal", "ThumbDistal"]:
				var bi: int = _ids.get(side + tip, -1)
				if bi >= 0:
					var tpush := _push(sk.get_bone_global_pose(bi).origin + push + p, shapes)
					if tpush.length() > 0.0:
						p += tpush
			if p.length() < 0.0005:
				break
			push += p
		# smoothed toward the push this frame needs (fast in, slower out), so the arm glides, never snaps
		var cur: Vector3 = _push_s[side]
		var rate := PUSH_IN_S if push.length() > cur.length() else PUSH_OUT_S
		cur = cur.lerp(push, 1.0 - exp(-dt / rate))
		_push_s[side] = cur
		if cur.length() < 0.0005:
			continue
		pushes += 1
		_reach(ids, hand + cur)


## Two-bone IK: the hand to `target` (skeleton space); its own global rotation kept.
func _reach(ids: Array, target: Vector3) -> void:
	var sk := get_skeleton()
	var ga := sk.get_bone_global_pose(ids[0])
	var gb := sk.get_bone_global_pose(ids[1])
	var gc := sk.get_bone_global_pose(ids[2])
	var hand_rot := gc.basis
	var A := ga.origin
	var la := (gb.origin - A).length()
	var lb := (gc.origin - gb.origin).length()
	var to := target - A
	var d := clampf(to.length(), absf(la - lb) + 0.01, la + lb - 0.002)
	var dir := to.normalized()
	var bend := (gb.origin - A) - dir * (gb.origin - A).dot(dir)            # keep the elbow on its side
	if bend.length() < 0.0001:
		bend = -_frame.y - dir * (-_frame.y).dot(dir)
	bend = bend.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var E := A + dir * (la * cos_a) + bend * (la * sqrt(1.0 - cos_a * cos_a))
	var q1 := Quaternion((gb.origin - A).normalized(), (E - A).normalized())
	sk.set_bone_global_pose(ids[0], Transform3D(Basis(q1) * ga.basis, ga.origin))
	gb = sk.get_bone_global_pose(ids[1])
	gc = sk.get_bone_global_pose(ids[2])
	var T := A + dir * d
	var q2 := Quaternion((gc.origin - gb.origin).normalized(), (T - gb.origin).normalized())
	sk.set_bone_global_pose(ids[1], Transform3D(Basis(q2) * gb.basis, gb.origin))
	gc = sk.get_bone_global_pose(ids[2])
	sk.set_bone_global_pose(ids[2], Transform3D(hand_rot, gc.origin))
