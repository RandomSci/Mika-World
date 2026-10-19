## v1 item 10: Luna's hair flows. While she dances (his clips): every hair spring chain is simulated in the world
## (no chest-locked frame left on), the strand tips really swing (their motion relative to her head, in the final pose
## after the springs), and no hair vertex sinks into her body or into Mika. Tearing is tear_check's job.

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
			var counts := _inside(luna, poses, mika, capm.poses)
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


## Hair vertices (every 3rd) inside her own torso/legs capsules (shrunk 1 cm: hair resting ON her is fine) and inside
## the other girl. Returns Vector2i(self, other).
static func _inside(c: WorldCharacter, poses: Array, o: WorldCharacter, oposes: Array) -> Vector2i:
	var sk := c.skeleton
	var B := func(s: Skeleton3D, ps: Array, n: String) -> Vector3:
		var bi := s.find_bone(n)
		return s.global_transform * (ps[bi] as Transform3D).origin if bi >= 0 and bi < ps.size() else Vector3.INF
	var hp: Vector3 = B.call(sk, poses, "Hips")
	var uc: Vector3 = B.call(sk, poses, "UpperChest")
	var mine := [[hp, uc, _torso_r(c, poses, hp, uc)], [B.call(sk, poses, "LeftUpperLeg"), B.call(sk, poses, "LeftLowerLeg"), 0.06],
		[B.call(sk, poses, "RightUpperLeg"), B.call(sk, poses, "RightLowerLeg"), 0.06]]
	var theirs := []
	if not oposes.is_empty():
		var osk := o.skeleton
		theirs = [[B.call(osk, oposes, "Hips"), B.call(osk, oposes, "Neck"), 0.12], [B.call(osk, oposes, "Head"), B.call(osk, oposes, "Head") + Vector3(0, 0.15, 0), 0.1]]
	var n_self := 0
	var n_other := 0
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).contains("Hair") or m.mesh == null:
			continue
		var r := InvCommon.skin(m, sk, poses, 0)
		var S: PackedVector3Array = r[0]
		for vi in range(0, S.size(), 3):
			var wp := sk.global_transform * S[vi]
			for cp in mine:
				if cp[0] != Vector3.INF and cp[1] != Vector3.INF and wp.distance_to(Geometry3D.get_closest_point_to_segment(wp, cp[0], cp[1])) < float(cp[2]) * DEEP:
					n_self += 1
					break
			for cp in theirs:
				if cp[0] != Vector3.INF and cp[1] != Vector3.INF and wp.distance_to(Geometry3D.get_closest_point_to_segment(wp, cp[0], cp[1])) < float(cp[2]) - 0.01:
					n_other += 1
					break
	return Vector2i(n_self, n_other)


## Her own torso radius round the hips -> upper chest line: the median distance of her body mesh's vertices there
## (a fixed 10 cm counted hair lying ON her slim back as inside).
static func _torso_r(c: WorldCharacter, poses: Array, a: Vector3, b: Vector3) -> float:
	var sk := c.skeleton
	var ds := []
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).contains("Body") or m.mesh == null:
			continue
		var r := InvCommon.skin(m, sk, poses, 0)
		var S: PackedVector3Array = r[0]
		for vi in range(0, S.size(), 7):
			var wp := sk.global_transform * S[vi]
			var q := Geometry3D.get_closest_point_to_segment(wp, a, b)
			if q.distance_to(a) > 0.02 and q.distance_to(b) > 0.02:
				ds.append(wp.distance_to(q))
	if ds.size() < 50:
		return 0.1
	ds.sort()
	var r0: float = ds[ds.size() / 2]
	print("[hair] %s torso radius %.3f m (%d body samples)" % [c.character_id, r0, ds.size()])
	return r0
