class_name HairGuard
extends SkeletonModifier3D
## Hair never sinks into her upper arms (v1 item 10). Her hair hangs past her shoulders; when an arm lifts in a dance
## it sweeps up through the strands, and the VRM springs have no arm colliders (adding capsules to the springs made
## them catch and pile up: 15 -> 103 points under her skin). Instead, like SeamGuard, this runs after all the
## simulation and only shapes what is drawn: every hair joint found inside an upper-arm capsule (the arm's own
## thickness, measured from her body mesh, plus MARGIN for the strand around the joint) is pushed out to its surface,
## the chain re-aimed from its root down. The springs keep their own state.

const MARGIN := 0.035            # m: a strand's half-thickness around its line, and a little air
const FRONT := 1.8               # back hair in front of an arm within this many radii goes behind it
const MIN_W := 0.5               # body vertices at least this much on the upper arm measure its thickness

var enabled := true
var pushed := 0                  # (tests) joints pushed out in the last frame
var _hair: Array = []            # hair joints below a chain's root, parents first
var _chain := {}                 # bone -> its chain's name prefix
var _arms: Array = []            # [bone, next bone, capsule radius, side hair only]
var _back := {}                  # hair joints of the back hair
var _back_rest := Vector3.ZERO   # behind her, in the rest pose (skeleton space)
var _chest := -1


static func attach(c: WorldCharacter) -> HairGuard:
	var g := HairGuard.new()
	g.name = "HairGuard"
	c.skeleton.add_child(g, false, Node.INTERNAL_MODE_BACK)      # behind the springs (and SeamGuard)
	g._build(c)
	return g


func _build(c: WorldCharacter) -> void:
	var sk := c.skeleton
	var re := RegEx.create_from_string("^(J_Sec_.*Hair.*)_(\\d+)$")
	for bi in sk.get_bone_count():
		var mt := re.search(sk.get_bone_name(bi))
		if mt and int(mt.get_string(2)) >= 1:
			_hair.append(bi)
			_chain[bi] = mt.get_string(1)
	_hair.sort()                                         # (a parent's index is always below its children's)
	# behind her: from her head to the roots of the back hair, level (rest pose)
	var head := sk.find_bone("Head")
	var acc := Vector3.ZERO
	for bi in _hair:
		if String(_chain[bi]).contains("Back"):
			_back[bi] = true
			if int(String(sk.get_bone_name(bi)).get_slice("_", String(sk.get_bone_name(bi)).get_slice_count("_") - 1)) == 1 and head >= 0:
				acc += sk.get_bone_global_rest(bi).origin - sk.get_bone_global_rest(head).origin
	acc.y = 0.0
	_back_rest = acc.normalized() if acc.length() > 1e-4 else Vector3.ZERO
	_chest = sk.find_bone("UpperChest") if sk.find_bone("UpperChest") >= 0 else sk.find_bone("Chest")
	for side in ["Left", "Right"]:
		# the upper arm, shoulder joint to elbow; and the shoulder (collarbone to shoulder joint) for the side hair that
		# rests on it - only the side hair (pushing the back hair off the shoulders too moved it about: 1 -> 52)
		# (and the slope from the neck out to the shoulder, where a side lock lay 1.3 cm deep)
		for seg in [["UpperArm", "LowerArm", false], ["Shoulder", "UpperArm", true], ["Shoulder", "Neck", true]]:
			var u := sk.find_bone(side + String(seg[0]))
			var l := sk.find_bone(String(seg[1]) if seg[1] == "Neck" else side + String(seg[1]))
			if u < 0 or l < 0:
				continue
			var r := _arm_radius(c, u, l)
			if r > 0.0:
				_arms.append([u, l, r + MARGIN, seg[2]])
	print("[hairguard] %s: %d hair joints, arm capsules %s" % [c.character_id, _hair.size(), str(_arms.map(func(a): return snappedf(float(a[2]), 0.001)))])


## The upper arm's thickness: how far its body vertices lie from the shoulder-elbow line, in the rest pose (the 80th
## percentile - the sleeve-less skin, not a stray vertex of the armpit).
func _arm_radius(c: WorldCharacter, u: int, l: int) -> float:
	var sk := c.skeleton
	var a := sk.get_bone_global_rest(u).origin
	var b := sk.get_bone_global_rest(l).origin
	var to_sk := sk.global_transform.affine_inverse()
	var ds := []
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).contains("Body") or m.mesh == null or m.skin == null:
			continue
		var xf := to_sk * m.global_transform
		var bind := -1
		for k in m.skin.get_bind_count():
			var bb := m.skin.get_bind_bone(k)
			if (bb if bb >= 0 else sk.find_bone(m.skin.get_bind_name(k))) == u:
				bind = k
		if bind < 0:
			continue
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var BI = arr[Mesh.ARRAY_BONES]
			var BW = arr[Mesh.ARRAY_WEIGHTS]
			if BI == null or BW == null or V.is_empty():
				continue
			var per: int = (BI as PackedInt32Array).size() / V.size() if BI is PackedInt32Array else (BI as Array).size() / V.size()
			for vi in V.size():
				for k in per:
					if int(BI[vi * per + k]) == bind and float(BW[vi * per + k]) >= MIN_W:
						var p := xf * V[vi]
						ds.append(p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b)))
						break
	if ds.size() < 8:
		return 0.0
	ds.sort()
	return float(ds[int(ds.size() * 0.8)])


func _process_modification() -> void:
	var sk := get_skeleton()
	pushed = 0
	if sk == null or not enabled or _hair.is_empty() or _arms.is_empty():
		return
	var caps := []
	for arm in _arms:
		caps.append([sk.get_bone_global_pose(int(arm[0])).origin, sk.get_bone_global_pose(int(arm[1])).origin, float(arm[2]), bool(arm[3])])
	var back := Vector3.ZERO
	if _back_rest != Vector3.ZERO and _chest >= 0:
		back = (sk.get_bone_global_pose(_chest).basis.orthonormalized() * sk.get_bone_global_rest(_chest).basis.orthonormalized().inverse() * _back_rest).normalized()
	for bi in _hair:
		var par := sk.get_bone_parent(bi)
		if par < 0 or not String(sk.get_bone_name(par)).begins_with(String(_chain[bi]) + "_"):
			continue                                     # (only the previous joint of the same chain turns)
		for cp in caps:
			if bool(cp[3]) and _back.has(bi):
				continue
			# the strand from the previous joint to this one against the arm's line: a strand crossing the arm between
			# two joints that are both outside it still cut through it
			var gp := sk.get_bone_global_pose(par)
			var p := sk.get_bone_global_pose(bi).origin
			var pts := Geometry3D.get_closest_points_between_segments(gp.origin, p, cp[0], cp[1])
			var d: Vector3 = pts[0] - pts[1]
			var r: float = cp[2]
			var bp := Vector3.ZERO
			if _back.has(bi) and back != Vector3.ZERO and not bool(cp[3]):
				var ad: Vector3 = (cp[1] - cp[0]).normalized()
				bp = (back - ad * back.dot(ad)).normalized()
			# back hair in front of an arm and near it counts too: left there while its neighbour went behind the arm,
			# the sheet between the two still cut through her shoulder (0 -> 36 points from one run to the next)
			var reach := r * FRONT if bp != Vector3.ZERO and d.dot(bp) < 0.0 else r
			if d.length() >= reach or d.length() < 1e-5:
				continue
			# the joint moves out by what the strand's closest point lacks, then the previous joint turns to it
			var target := p + d.normalized() * maxf(r - d.length(), 0.0)
			if bp != Vector3.ZERO and d.dot(bp) < r * 0.7:
				# back hair always goes out BEHIND the arm: two neighbouring strands pushed out on either side of a
				# raised arm left the sheet between them cutting through her shoulder
				target = p + (pts[1] + bp * r - pts[0])
			var u := p - gp.origin
			var v := target - gp.origin
			if u.length() < 1e-5 or v.length() < 1e-5:
				continue
			sk.set_bone_global_pose(par, Transform3D(Basis(Quaternion(u.normalized(), v.normalized())) * gp.basis, gp.origin))
			pushed += 1
