class_name BodySurface
extends RefCounted
## Her real surface, clothing included, for penetration tests (Selwyn, 2026-10-20: "sized from the real VRM mesh
## including clothing"). Built once per avatar from the rest pose: every vertex of every skinned mesh goes to its
## dominant bone; torso, legs and head (and the skirt panels, which follow her hips) are kept as point clouds in that
## bone's own rest frame, decimated on a 1.2 cm grid, each point with its normal. A query point is taken into each
## bone's frame of the current pose (the body moves rigidly with its bones at this scale), the nearest surface point
## gives the signed distance: negative inside her. Arm radii are measured from her own forearm and hand vertices.

const GRID := 0.012
## The surfaces an arm, a hand or a finger may never enter (her own arms are tested against each other separately).
const SOLID := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"]

var cloud := {}                          # bone -> [PackedVector3Array local points, PackedVector3Array local normals]
var radius := {}                         # "LeftLowerArm" / "LeftHand" ... -> metres from the bone line to her skin
var _cell := {}                          # bone -> {Vector3i: [indices]} spatial hash (cell = 4 cm)
var _box := {}                           # bone -> AABB of its points (local), to skip far bones
const HASH := 0.04
static var _cache := {}


## The surface of character c's current avatar (cached by avatar path).
static func of(c: Node, sk: Skeleton3D) -> BodySurface:
	var key := String(c.get("avatar_path")) + ":" + str(sk.get_bone_count())
	if _cache.has(key):
		return _cache[key]
	var s := BodySurface.new()
	s._build(c, sk)
	_cache[key] = s
	return s


func _build(c: Node, sk: Skeleton3D) -> void:
	var owner_of := {}                    # bone index -> the SOLID bone it counts as (skirt and hair chains under the hips -> Hips)
	for bi in sk.get_bone_count():
		var b := bi
		var nm := sk.get_bone_name(bi)
		if nm in SOLID:
			owner_of[bi] = nm
			continue
		if nm.begins_with("J_Sec") or nm.begins_with("J_Adj"):
			# springs and helpers: the nearest humanoid ancestor in SOLID (skirt panels and belt cords -> Hips). Hair
			# (anything under the head or neck) is not solid: it is cloth, the springs keep it off the arms
			var via_arm := false
			while b >= 0 and not (sk.get_bone_name(b) in SOLID):
				var bn := sk.get_bone_name(b)
				if bn.ends_with("Shoulder") or bn.ends_with("UpperArm") or bn.ends_with("LowerArm") or bn.ends_with("Hand"):
					via_arm = true                    # (sleeves and cuffs move with her arm, never solid body)
				b = sk.get_bone_parent(b)
			if via_arm:
				continue
			if b >= 0 and not (sk.get_bone_name(b) in ["Head", "Neck"]):
				owner_of[bi] = sk.get_bone_name(b)
	var pts := {}
	var nrm := {}
	var seen := {}
	var arm_d := {}                       # arm bone -> distances of its vertices to its bone line
	for m in c.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.skin == null or not mi.visible:
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var BI = arr[Mesh.ARRAY_BONES]
			var BW = arr[Mesh.ARRAY_WEIGHTS]
			if BI == null or BW == null or V.is_empty():
				continue
			var per := int(BI.size() / V.size())
			for vi in V.size():
				var best_w := 0.0
				var best_b := -1
				for k in per:
					var w := float(BW[vi * per + k])
					if w > best_w:
						best_w = w
						var bb := mi.skin.get_bind_bone(int(BI[vi * per + k]))
						if bb < 0:
							bb = sk.find_bone(mi.skin.get_bind_name(int(BI[vi * per + k])))
						best_b = bb
				if best_b < 0:
					continue
				var p: Vector3 = mi.transform * V[vi]                 # (mesh nodes sit at the skeleton's origin)
				var bname := sk.get_bone_name(best_b)
				if bname.ends_with("LowerArm") or bname.ends_with("Hand") or bname.ends_with("UpperArm"):
					var g := sk.get_bone_global_rest(best_b)
					var kids := sk.get_bone_children(best_b)
					if not kids.is_empty():
						var e := sk.get_bone_global_rest(kids[0]).origin
						var ab := e - g.origin
						var u := clampf((p - g.origin).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
						if not arm_d.has(bname):
							arm_d[bname] = []
						(arm_d[bname] as Array).append(p.distance_to(g.origin + ab * u))
					continue
				if not owner_of.has(best_b):
					continue
				var own: String = owner_of[best_b]
				var ob := sk.find_bone(own)
				var inv := sk.get_bone_global_rest(ob).affine_inverse()
				var lp: Vector3 = inv * p
				var cell := Vector3i((lp / GRID).floor())
				var key := own + str(cell)
				if seen.has(key):
					continue
				seen[key] = true
				if not pts.has(own):
					pts[own] = []                          # (plain Arrays while building: a packed array cast is a copy)
					nrm[own] = []
				(pts[own] as Array).append(lp)
				(nrm[own] as Array).append((inv.basis * (mi.transform.basis * N[vi])).normalized())
	for own in pts:
		var P := PackedVector3Array(pts[own])
		cloud[own] = [P, PackedVector3Array(nrm[own])]
		var h := {}
		for i in P.size():
			var cc := Vector3i((P[i] / HASH).floor())
			if not h.has(cc):
				h[cc] = []
			(h[cc] as Array).append(i)
		_cell[own] = h
		var bx := AABB(P[0], Vector3.ZERO)
		for q in P:
			bx = bx.expand(q)
		_box[own] = bx.grow(HASH * 1.5)
	for b in arm_d:
		var d: Array = arm_d[b]
		d.sort()
		# (the nearest 5 % of the vertices round the bone are her skin; wide sleeves and the dress lie further out)
		radius[b] = float(d[int(d.size() * 0.05)]) if not d.is_empty() else 0.03


## Signed distance from world-or-skeleton point p (skeleton space) to her solid surface, the bone it belongs to, and
## that surface's normal (skeleton space): [dist, bone, normal]. `gpose(bone_index)` returns the current global pose.
func signed(p: Vector3, sk, gpose: Callable) -> Array:
	var best := [INF, "", Vector3.ZERO]
	for own in cloud:
		var bi: int = sk.find_bone(own)
		var g: Transform3D = gpose.call(bi)
		var lp: Vector3 = g.affine_inverse() * p
		if not (_box[own] as AABB).has_point(lp):
			continue
		var c0 := Vector3i((lp / HASH).floor())
		var P: PackedVector3Array = cloud[own][0]
		var N: PackedVector3Array = cloud[own][1]
		var h: Dictionary = _cell[own]
		# the 4 nearest surface points must agree she is inside (a thin collar, frill or sleeve edge has normals that
		# point either way; one stray point never decides)
		var near: Array = []                      # [d2, i] up to 4
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var cc := c0 + Vector3i(dx, dy, dz)
					if not h.has(cc):
						continue
					for i in (h[cc] as Array):
						var dd := lp.distance_squared_to(P[i])
						if near.size() < 4 or dd < float(near[near.size() - 1][0]):
							near.append([dd, i])
							near.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
							if near.size() > 4:
								near.pop_back()
		if near.is_empty():
			continue
		var inside := 0
		var sd_sum := 0.0
		for e in near:
			var sd := (lp - P[int(e[1])]).dot(N[int(e[1])])
			if sd < 0.0:
				inside += 1
				sd_sum += sd
		var dist := sqrt(float(near[0][0]))
		var val := (sd_sum / float(inside)) if inside == near.size() and near.size() >= 3 else dist
		if val < float(best[0]):
			best = [val, own, (g.basis * N[int(near[0][1])]).normalized()]
	return best
