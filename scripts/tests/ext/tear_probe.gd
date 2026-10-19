## Debug for tear_check: with Luna standing idle (no dance), the worst-stretched edge of each part with its two
## vertices, rest and skinned positions, and the bones/weights behind them. A sane skinning gives ~1.0 everywhere.

const PARTS := ["Skirt", "Sleeve", "BackBow", "Hair"]


static func run(t) -> void:
	var set: Dictionary = await t._lake_setup({"luna": -0.8, "mika": 0.8})
	if set.is_empty():
		return
	var luna: WorldCharacter = set.chars.luna
	var cap := InvCommon.capture(luna)
	if RenderProfile.options.has("tp-dance"):
		var dk: DanceDeck = t._dance_stack(luna)
		dk.influence = 1.0
		dk.play("dancing_a", 6.0, 1.0, 0.01)
		await t._wait(1.2)
	else:
		await t._wait(2.0)
	# the body mesh against her own bones: is the CPU skin in the same space as the poses?
	var skb := luna.skeleton
	var hp: Vector3 = skb.global_transform * (cap.poses[skb.find_bone("Hips")] as Transform3D).origin
	var uc: Vector3 = skb.global_transform * (cap.poses[skb.find_bone("UpperChest")] as Transform3D).origin
	print("[tearprobe] hips %s upper chest %s (node %s)" % [str(hp.snappedf(0.01)), str(uc.snappedf(0.01)), str(luna.global_position.snappedf(0.01))])
	for mi in luna.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).contains("Body") or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var r := InvCommon.skin(m, skb, cap.poses, si)
			var S: PackedVector3Array = r[0]
			var lo := Vector3.INF
			var hi := -Vector3.INF
			var near := 0
			for v in S:
				var w := skb.global_transform * v
				lo = lo.min(w)
				hi = hi.max(w)
				if w.distance_to(Geometry3D.get_closest_point_to_segment(w, hp, uc)) < 0.2:
					near += 1
			print("[tearprobe] body %s s%d: %d verts, world box %s .. %s, %d within 20 cm of the spine" % [m.name, si, S.size(), str(lo.snappedf(0.01)), str(hi.snappedf(0.01)), near])
	var sk := luna.skeleton
	var poses: Array = cap.poses
	print("[tearprobe] %d poses captured, %d bones" % [poses.size(), sk.get_bone_count()])
	for mi in luna.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var part := ""
		for p in PARTS:
			if String(m.name).contains(p):
				part = p
		if part == "" or m.mesh == null:
			continue
		print("[tearprobe] mesh %s skin %s binds %d surfaces %d node scale %s" % [m.name, str(m.skin != null), m.skin.get_bind_count() if m.skin else -1, m.mesh.get_surface_count(), str(m.global_transform.basis.get_scale().snappedf(0.001))])
		for si in m.mesh.get_surface_count():
			var r := InvCommon.skin(m, sk, poses, si)
			var S: PackedVector3Array = r[0]
			var R: PackedVector3Array = r[1]
			var arr := m.mesh.surface_get_arrays(si)
			var I = arr[Mesh.ARRAY_INDEX]
			if I == null:
				continue
			var idx: PackedInt32Array = I
			var worst := 1.0
			var wa := -1
			var wb := -1
			var ratios := []
			for tt in range(0, idx.size(), 3):
				for e in 3:
					var a: int = idx[tt + e]
					var b: int = idx[tt + (e + 1) % 3]
					var rl := R[a].distance_to(R[b])
					if rl < 0.003:
						continue
					var q := S[a].distance_to(S[b]) / rl
					ratios.append(q)
					if q > worst:
						worst = q
						wa = a
						wb = b
			ratios.sort()
			var med: float = ratios[ratios.size() / 2] if not ratios.is_empty() else 0.0
			print("[tearprobe] %s s%d: %d verts, median ratio %.3f, worst %.2f" % [m.name, si, R.size(), med, worst])
			if wa >= 0:
				var BI = arr[Mesh.ARRAY_BONES]
				var BW = arr[Mesh.ARRAY_WEIGHTS]
				var per: int = (BI as PackedInt32Array).size() / maxi(R.size(), 1) if BI is PackedInt32Array else (BI as Array).size() / maxi(R.size(), 1)
				for v in [wa, wb]:
					var bones := []
					for k in per:
						var w: float = BW[v * per + k]
						if w > 0.0001:
							var bidx: int = BI[v * per + k]
							var bb := m.skin.get_bind_bone(bidx)
							if bb < 0:
								bb = sk.find_bone(m.skin.get_bind_name(bidx))
							bones.append("%s:%.2f" % [sk.get_bone_name(bb) if bb >= 0 else "?" + String(m.skin.get_bind_name(bidx)), w])
					print("[tearprobe]    v%d rest %s skinned %s bones %s" % [v, str(R[v].snappedf(0.001)), str(S[v].snappedf(0.001)), str(bones)])
