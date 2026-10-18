class_name SkirtDrape
extends SkeletonModifier3D
## The seated skirt (2026-10-19, Selwyn: "the long panels pass through the bench top and sink into the floor; it must
## work on every seat in every area"). Runs after the skirt simulation. When she sits - on any seat, rock, step, log
## or on the grass - the surface under her is sampled once with a grid of physics rays (a height map: seat top, seat
## edges, the floor around it), and each skirt chain is laid joint by joint over that surface and her legs:
##  * a joint never goes below the surface (a max-filtered height map, so the fabric clears the seat edge too);
##  * the long panels hang (a strong gravity pull): over the seat edge, down in front of / behind the seat, and the
##    part that reaches the floor rests on it;
##  * the short front panel (chains near her front) stays light and lies on her lap (the thigh capsules hold it up).
## The drape blends in with the sit itself (her pose-correction influence), so the skirt settles while she lowers.

const CELL := 0.07
const HALF := 1.05                    # the sampled square is 2.1 m across, centred on her hips
const MARGIN := 0.018                 # fabric thickness over a surface
const LEG_MARGIN := 0.018             # and over her legs
var c: WorldCharacter
var chains: Array = []                # [bone ids], root first
var front: Array = []                 # per chain: true for the front panel
var weight := 0.0
var _hf := PackedFloat32Array()
var _n := 0
var _origin := Vector2.ZERO
var _active_kind := ""
var _legs: Array = []
var _dbg := 0                 # [a, b, r] per leg segment (world), refreshed every frame


static func attach(ch: WorldCharacter, chain_roots: Array) -> SkirtDrape:
	for n in ch.skeleton.get_children():
		if n is SkirtDrape:
			n.queue_free()
	var d := SkirtDrape.new()
	d.name = "SkirtDrape"
	d.c = ch
	ch.skeleton.add_child(d)
	d._find(chain_roots)
	return d


func _find(roots: Array) -> void:
	var sk := c.skeleton
	var hips := sk.find_bone("Hips")
	var hips_rest: Transform3D = sk.get_bone_global_rest(hips)
	for r in roots:
		var bi := sk.find_bone(String(r))
		if bi < 0:
			continue
		var ids := [bi]
		while true:
			var kids := sk.get_bone_children(ids[ids.size() - 1])
			if kids.is_empty():
				break
			ids.append(kids[0])
		chains.append(ids)
		# front = the root sits ahead of the hips (VRM faces +Z in skeleton space), within ~40 deg of straight ahead
		var off: Vector3 = sk.get_bone_global_rest(bi).origin - hips_rest.origin
		off.y = 0.0
		front.append(off.length() > 0.01 and off.normalized().dot(Vector3(0, 0, 1)) > 0.76)


func _sitting_kind() -> String:
	if c.seated:
		return "seat"
	if c.ground_pose == "sit":
		return "ground"
	return ""


## Sample the surfaces under her: a height map around her hips. Props and seats are sampled on their VISIBLE shape
## (their meshes - a rock's collision is often a box wider and flatter than the rock, and cloth on that box sticks out
## like a board); the ground under them comes from physics with those small prop bodies left out. Plants and anything
## with transparency are ignored (the skirt does not sit on leaves).
func _sample() -> void:
	var space := c.get_world_3d().direct_space_state
	var sk := c.skeleton
	var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Hips")).origin
	_n = int(HALF * 2.0 / CELL) + 1
	_origin = Vector2(hp.x - HALF, hp.z - HALF)
	_hf.resize(_n * _n)
	var floor_y := c.global_position.y - 0.4
	var top_y := hp.y - 0.06
	var region := AABB(Vector3(hp.x - HALF - 0.2, hp.y - 3.0, hp.z - HALF - 0.2), Vector3(HALF * 2.0 + 0.4, 3.0, HALF * 2.0 + 0.4))
	# 1. physics, minus small bodies (seats, rocks, logs: their visible meshes are used instead)
	var excl: Array[RID] = []
	for cw in c.get_tree().root.find_children("*", "WorldCharacter", true, false):
		excl.append((cw as CollisionObject3D).get_rid())
	var qp := PhysicsShapeQueryParameters3D.new()
	var bx := BoxShape3D.new()
	bx.size = region.size
	qp.shape = bx
	qp.transform = Transform3D(Basis.IDENTITY, region.get_center())
	for hit in space.intersect_shape(qp, 64):
		var col = hit.get("collider")
		if col is StaticBody3D and _small_body(col as StaticBody3D):
			excl.append((col as StaticBody3D).get_rid())
	# 2. the visible props in the region
	var props: Array = []
	for mi in c.get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or String(m.get_path()).contains("Avatar"):
			continue
		var bb: AABB = m.global_transform * m.get_aabb()
		if not bb.intersects(region) or bb.size.length() > 6.0 or _see_through(m):
			continue
		var tm := m.mesh.generate_triangle_mesh()
		if tm:
			props.append([tm, m.global_transform.affine_inverse(), m.global_transform])
	for j in _n:
		for i in _n:
			var x := _origin.x + i * CELL
			var z := _origin.y + j * CELL
			var from := Vector3(x, top_y, z)
			var q := PhysicsRayQueryParameters3D.create(from, Vector3(x, hp.y - 3.0, z))
			q.exclude = excl
			var hit := space.intersect_ray(q)
			var h := float((hit.position as Vector3).y) if not hit.is_empty() else floor_y
			for pr in props:
				var inv: Transform3D = pr[1]
				var lf: Vector3 = inv * from
				var lt: Vector3 = inv * Vector3(x, hp.y - 3.0, z)
				var r: Dictionary = (pr[0] as TriangleMesh).intersect_segment(lf, lt)
				if not r.is_empty():
					h = maxf(h, ((pr[2] as Transform3D) * (r.position as Vector3)).y)
			_hf[j * _n + i] = h
	# max filter (one cell): the fabric clears a seat's edge instead of cutting its corner
	var src := _hf.duplicate()
	for j in _n:
		for i in _n:
			var m := -INF
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ii := clampi(i + di, 0, _n - 1)
					var jj := clampi(j + dj, 0, _n - 1)
					m = maxf(m, src[jj * _n + ii])
			_hf[j * _n + i] = m
	var lo := INF
	var hi := -INF
	for v in _hf:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	print("[drape] %s sampled %dx%d (%d visible props) around hips y %.2f: surface %.2f .. %.2f" % [c.character_id, _n, _n, props.size(), hp.y, lo, hi])


static func _small_body(b: StaticBody3D) -> bool:
	for sh in b.get_children():
		if sh is CollisionShape3D and (sh as CollisionShape3D).shape:
			var s = (sh as CollisionShape3D).shape
			if s is BoxShape3D and (s as BoxShape3D).size.length() < 3.5:
				return true
	return false


static func _see_through(m: MeshInstance3D) -> bool:
	var mats: Array = [m.material_override]
	for si in m.mesh.get_surface_count():
		mats.append(m.get_active_material(si))
	for mt in mats:
		if mt is BaseMaterial3D and (mt as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return false


func _height(p: Vector3) -> float:
	if _n == 0:
		return -INF
	var fx := (p.x - _origin.x) / CELL
	var fz := (p.z - _origin.y) / CELL
	if fx < 0.0 or fz < 0.0 or fx > _n - 1 or fz > _n - 1:
		return c.global_position.y - 0.4
	var i := int(fx)
	var j := int(fz)
	var i1 := mini(i + 1, _n - 1)
	var j1 := mini(j + 1, _n - 1)
	# the higher of the neighbours (conservative near steps and seat edges)
	return maxf(maxf(_hf[j * _n + i], _hf[j * _n + i1]), maxf(_hf[j1 * _n + i], _hf[j1 * _n + i1]))


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or c == null:
		return
	var kind := _sitting_kind()
	if kind != "" and kind != _active_kind:
		_sample()
	_active_kind = kind
	# the drape follows the sit: her pose correction blends in while she lowers onto the seat
	var target := clampf(c.pose_adjust.influence, 0.0, 1.0) if kind != "" else 0.0
	weight = move_toward(weight, target, 0.08)
	_dbg += 1
	if kind != "" and _dbg % 300 == 0 and RenderProfile.options.has("drape-debug"):
		print("[drape] kind %s target %.2f weight %.2f n %d" % [kind, target, weight, _n])
	if weight < 0.001 or _n == 0:
		return
	var g := sk.global_transform
	var gi := g.affine_inverse()

	_legs.clear()
	for side in ["Left", "Right"]:
		var a: Vector3 = g * sk.get_bone_global_pose(sk.find_bone(side + "UpperLeg")).origin
		var b: Vector3 = g * sk.get_bone_global_pose(sk.find_bone(side + "LowerLeg")).origin
		var f: Vector3 = g * sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin
		_legs.append([a.lerp(b, 0.12), b, 0.085 + LEG_MARGIN])
		_legs.append([b, f, 0.06 + LEG_MARGIN])
	for ci in chains.size():
		var ids: Array = chains[ci]
		var pull := 0.3 if front[ci] else 4.0          # how hard the panel hangs (front: rests on the lap; the rest hang limp)
		# current (simulated) joint positions, world
		var P: Array = []
		for b in ids:
			P.append(g * sk.get_bone_global_pose(b).origin)
		var Q: Array = [P[0]]
		for k in range(1, P.size()):
			var seg: float = (P[k] as Vector3).distance_to(P[k - 1])
			var d: Vector3 = ((P[k] as Vector3) - (P[k - 1] as Vector3)).normalized()
			d = (d + Vector3.DOWN * pull).normalized()
			var q: Vector3 = (Q[k - 1] as Vector3) + d * seg
			for it in 2:
				for L in _legs:
					var cp := Geometry3D.get_closest_point_to_segment(q, L[0], L[1])
					var off := q - cp
					var r: float = L[2]
					if off.length() < r:
						q = cp + (off.normalized() if off.length() > 0.0001 else Vector3.UP) * r
				var h := _height(q) + MARGIN
				if q.y < h:
					q.y = h
				q = (Q[k - 1] as Vector3) + (q - (Q[k - 1] as Vector3)).normalized() * seg
			var h2 := _height(q) + MARGIN
			if q.y < h2:
				q.y = h2                                     # (a hair longer than the segment, never through)
			Q.append(q)
		# aim each joint at its laid-out child, root first (blended by the drape weight)
		for k in range(0, ids.size() - 1):
			var b: int = ids[k]
			var cur: Transform3D = sk.get_bone_global_pose(b)
			var child_now: Vector3 = sk.get_bone_global_pose(ids[k + 1]).origin
			var want: Vector3 = gi * (Q[k + 1] as Vector3)
			var v0 := child_now - cur.origin
			var v1 := want - cur.origin
			if v0.length() < 1e-5 or v1.length() < 1e-5:
				continue
			var rot := Quaternion(v0.normalized(), v1.normalized())
			rot = Quaternion.IDENTITY.slerp(rot, weight)
			sk.set_bone_global_pose(b, Transform3D(Basis(rot) * cur.basis, cur.origin))
		if RenderProfile.options.has("drape-debug") and ci == 4 and _dbg % 600 == 0:
			var tip: Vector3 = g * sk.get_bone_global_pose(ids[ids.size() - 1]).origin
			print("[drape] chain4 tip now %s want %s (h %.2f) w %.2f" % [str(tip.snapped(Vector3.ONE * 0.01)), str((Q[Q.size() - 1] as Vector3).snapped(Vector3.ONE * 0.01)), _height(Q[Q.size() - 1]), weight])


## QA: skirt joints below the sampled surface (cm of the deepest one) and how many, now.
	_measure(sk, g)


var _deep_at := []
var _pen := Vector2.ZERO
## QA: the deepest skirt joint under the sampled surface (cm) and how many joints are under it, as rendered (measured
## inside the modifier pass: outside it the skeleton reports the pose without the modifiers).
func penetration() -> Vector2:
	return _pen


func _measure(sk: Skeleton3D, g: Transform3D) -> void:
	var deep := 0.0
	var cnt := 0
	for ids in chains:
		for b in ids:
			var p: Vector3 = g * sk.get_bone_global_pose(b).origin
			var d := _height(p) - p.y
			if d > 0.01:
				cnt += 1
				if d > deep:
					deep = d
					_deep_at = [p, _height(p), sk.get_bone_name(b)]
	_pen = Vector2(deep * 100.0, cnt)
