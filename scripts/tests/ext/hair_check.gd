## v1 item 10: Luna's hair flows. While she dances (his clips): every hair spring chain is simulated in the world
## (no chest-locked frame left on), the strand tips really swing (their motion relative to her head, in the final pose
## after the springs), and no hair vertex sinks into her body or into Mika. Tearing is tear_check's job.

static var _dbg_done := false
const CELL := 0.04                      # m: the body-vertex grid for the under-the-skin test
const DEEP := 0.85                      # a hair vertex counts as inside her when deeper than 15% of her own radius
const MIN_SWING := 0.02                  # m: the tips' mean motion (std, head frame) must be at least this


static func run(t) -> void:
	var set: Dictionary = await t._lake_setup({"luna": -0.8, "mika": 0.8})
	if set.is_empty():
		return
	var luna: WorldCharacter = set.chars.luna
	var mika: WorldCharacter = set.chars.mika
	var cap := InvCommon.capture(luna)
	var capm := InvCommon.capture(mika)
	# what is under her skin while she stands idle is how the model is made (hair roots tucked in at the nape):
	# only what goes under it while she dances counts
	await t._wait(0.5)
	var base := {}
	_inside(luna, cap.poses, mika, capm.poses, {}, base)
	print("[hair] %d hair points already under her skin standing idle (the model's own overlap)" % base.size())
	var decks := {}
	for id in set.chars:
		decks[id] = t._dance_stack(set.chars[id])
		(decks[id] as DanceDeck).influence = 1.0
		(decks[id] as DanceDeck).play("dancing_a", 6.0, 1.0, 0.01)      # (the turn: the hair should fly)
	# 1. the frame every hair chain is simulated in
	var sec = luna.avatar.find_child("secondary", true, false)
	var locked := []
	if sec:
		for sb in sec.spring_bones:
			if String(sb.comment).begins_with("Hair") and (String(sb.get("center_bone")) != "" or sb.get("center_node") != NodePath()):
				locked.append(String(sb.comment))
		if bool(sec.get("override_springbone_center")):
			locked.clear()
	t._check(locked.is_empty(), "every hair chain simulated in the world (chest-locked: %s)" % str(locked))
	# 2. the tips swing, 3. no hair inside a body
	var sk := luna.skeleton
	var tips := []
	for bi in sk.get_bone_count():
		var nm := sk.get_bone_name(bi)
		if nm.contains("Hair") and sk.get_bone_children(bi).is_empty():
			tips.append(bi)
	var head := sk.find_bone("Head")
	var acc := {}
	var inside_self := 0
	var inside_other := 0
	var t0: float = t._game_t
	var next := 1.0
	while t._game_t - t0 < 9.0:
		await t.get_tree().process_frame
		var poses: Array = cap.poses
		if poses.is_empty():
			continue
		var hinv := (poses[head] as Transform3D).affine_inverse()
		for bi in tips:
			var p: Vector3 = hinv * (poses[bi] as Transform3D).origin
			var st: Array = acc.get(bi, [Vector3.ZERO, Vector3.ZERO, 0])
			st[0] += p
			st[1] += p * p
			st[2] += 1
			acc[bi] = st
		if t._game_t - t0 >= next:
			next += 1.0
			var counts := _inside(luna, poses, mika, capm.poses, base)
			inside_self = maxi(inside_self, counts.x)
			inside_other = maxi(inside_other, counts.y)
	var tot := 0.0
	for bi in acc:
		var st: Array = acc[bi]
		var m: Vector3 = st[0] / float(st[2])
		var v: Vector3 = st[1] / float(st[2]) - m * m
		tot += sqrt(maxf(v.x + v.y + v.z, 0.0))
	var swing := tot / maxf(acc.size(), 1)
	print("[hair] luna: %d tips, mean swing %.3f m, worst %d hair vertices inside her body, %d inside Mika" % [tips.size(), swing, inside_self, inside_other])
	t._check(swing >= MIN_SWING, "hair tips swing (%.3f m >= %.2f)" % [swing, MIN_SWING])
	t._check(inside_self == 0 and inside_other == 0, "no hair inside a body (self %d, Mika %d)" % [inside_self, inside_other])


## Hair vertices (every 3rd) under her own skin - the nearest skinned body vertex within 4 cm, the hair point more
## than 1.2 cm behind its surface (its normal) - and inside the other girl. (A round torso capsule counted hair lying
## ON her back as inside: her spine runs close to her back.) Returns Vector2i(self, other).
static func _inside(c: WorldCharacter, poses: Array, o: WorldCharacter, oposes: Array, skip := {}, found := {}) -> Vector2i:
	var sk := c.skeleton
	var gx := sk.global_transform
	var grid := {}
	var bp := PackedVector3Array()
	var bn := PackedVector3Array()
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).contains("Body") or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var r := InvCommon.skin_n(m, sk, poses, si)
			bp.append_array(r[0])
			bn.append_array(r[1])
	if not _dbg_done:
		_dbg_done = true
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for q in bp:
			lo = lo.min(q)
			hi = hi.max(q)
		var hm: MeshInstance3D = null
		for mi2 in c.avatar.find_children("*", "MeshInstance3D", true, false):
			if String(mi2.name).contains("Hair"):
				hm = mi2
		var hs: PackedVector3Array = InvCommon.skin(hm, sk, poses, 0)[0] if hm else PackedVector3Array()
		var lo2 := Vector3.INF
		var hi2 := -Vector3.INF
		for q in hs:
			lo2 = lo2.min(q)
			hi2 = hi2.max(q)
		print("[hair] dbg body box %s..%s  hair box %s..%s" % [str(lo.snappedf(0.01)), str(hi.snappedf(0.01)), str(lo2.snappedf(0.01)), str(hi2.snappedf(0.01))])
	for i in bp.size():
		var key := Vector3i((bp[i] / CELL).floor())
		if not grid.has(key):
			grid[key] = []                               # (an Array: a packed array here would be a copy)
		(grid[key] as Array).append(i)
	var theirs := []
	if not oposes.is_empty():
		var B := func(s: Skeleton3D, ps: Array, n: String) -> Vector3:
			var bi := s.find_bone(n)
			return s.global_transform * (ps[bi] as Transform3D).origin if bi >= 0 and bi < ps.size() else Vector3.INF
		var osk := o.skeleton
		theirs = [[B.call(osk, oposes, "Hips"), B.call(osk, oposes, "Neck"), 0.12], [B.call(osk, oposes, "Head"), B.call(osk, oposes, "Head") + Vector3(0, 0.15, 0), 0.1]]
	var n_self := 0
	var n_other := 0
	var near := 0
	var deepest := 0.0
	var near_bone := {}
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).contains("Hair") or m.mesh == null:
			continue
		var r := InvCommon.skin(m, sk, poses, 0)
		var S: PackedVector3Array = r[0]
		for vi in range(0, S.size(), 3):
			var p := S[vi]
			var k0 := Vector3i((p / CELL).floor())
			var best := -1
			var bd := 0.04
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var cell = grid.get(k0 + Vector3i(dx, dy, dz))
						if cell == null:
							continue
						for j in (cell as Array):
							var d := p.distance_to(bp[j])
							if d < bd:
								bd = d
								best = j
			if best >= 0:
				near += 1
				deepest = minf(deepest, (p - bp[best]).dot(bn[best]))
			if best >= 0 and (p - bp[best]).dot(bn[best]) < -0.012:
				var vk := "%s:%d" % [m.name, vi]
				found[vk] = true
				if not skip.has(vk):
					n_self += 1
					var nb := ""
					var nd := 9.0
					for bn2 in ["Head", "Neck", "UpperChest", "Chest", "Spine", "Hips", "LeftUpperArm", "RightUpperArm", "LeftShoulder", "RightShoulder"]:
						var bi2 := sk.find_bone(bn2)
						if bi2 >= 0 and bi2 < poses.size():
							var dd := p.distance_to((poses[bi2] as Transform3D).origin)
							if dd < nd:
								nd = dd
								nb = bn2
					near_bone[nb] = int(near_bone.get(nb, 0)) + 1
			var wp := gx * p
			for cp in theirs:
				if cp[0] != Vector3.INF and cp[1] != Vector3.INF and wp.distance_to(Geometry3D.get_closest_point_to_segment(wp, cp[0], cp[1])) < float(cp[2]) - 0.01:
					n_other += 1
					break
	if not near_bone.is_empty():
		print("[hair] new points under her skin, by nearest bone: %s" % str(near_bone))
	print("[hair] %d of the hair points lie within 4 cm of her skin (body %d vertices); deepest %.3f m under it" % [near, bp.size(), -deepest])
	return Vector2i(n_self, n_other)


## Her own torso radius round the hips -> upper chest line, from the rest pose: the median distance of the body
## vertices skinned mostly (> 0.5) to her spine bones to the rest hips -> upper chest line. (Cached per character.)
static var _tr_cache := {}

static func _torso_r(c: WorldCharacter, _poses: Array, _a: Vector3, _b: Vector3) -> float:
	if _tr_cache.has(c.character_id):
		return _tr_cache[c.character_id]
	var sk := c.skeleton
	var spine := {}
	for n in ["Hips", "Spine", "Chest", "UpperChest"]:
		spine[sk.find_bone(n)] = true
	var ra := sk.get_bone_global_rest(sk.find_bone("Hips")).origin
	var rb := sk.get_bone_global_rest(sk.find_bone("UpperChest")).origin
	var ds := []
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).contains("Body") or m.mesh == null or m.skin == null:
			continue
		var arr := m.mesh.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var BI = arr[Mesh.ARRAY_BONES]
		var BW = arr[Mesh.ARRAY_WEIGHTS]
		if BI == null or BW == null or V.is_empty():
			continue
		var per: int = (BI as PackedInt32Array).size() / V.size() if BI is PackedInt32Array else (BI as Array).size() / V.size()
		for vi in range(0, V.size(), 3):
			var on_spine := 0.0
			for k in per:
				var b := m.skin.get_bind_bone(int(BI[vi * per + k]))
				if b < 0:
					b = sk.find_bone(m.skin.get_bind_name(int(BI[vi * per + k])))
				if spine.has(b):
					on_spine += float(BW[vi * per + k])
			if on_spine > 0.5:
				var q := Geometry3D.get_closest_point_to_segment(V[vi], ra, rb)
				ds.append(V[vi].distance_to(q))
	var r0 := 0.1
	if ds.size() >= 50:
		ds.sort()
		r0 = ds[ds.size() / 2]
	print("[hair] %s torso radius %.3f m from the rest pose (%d spine vertices)" % [c.character_id, r0, ds.size()])
	_tr_cache[c.character_id] = r0
	return r0
