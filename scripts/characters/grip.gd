class_name Grip
extends RefCounted
## Holding things properly (residents' tools; anything parented to a hand bone). A prop is never placed at the
## wrist with a guessed rotation: its grip is MEASURED from both sides and matched.
##   the hand    from the skeleton's rest pose: the palm just behind the knuckles (wrist -> middle_01), the
##               axis across the palm (pinky -> index), the knuckle direction, the palmar side (where the thumb
##               sits) - so a closed fist encloses the grip point
##   the prop    from its own vertices:
##     "tool"    (hammer, axe, hatchet, ...) the long axis is the handle; the end with the bigger cross-section
##               is the head; the grip is ~20 % up the handle from its end; the head's mass says which way the
##               blade / face points. Held as a hand holds it: handle across the palm, head on the thumb side,
##               blade along the knuckles (it leads the swing).
##     "hang"    (lantern, bucket) held by the top of its bail and hanging upright under the fist (Grip.hang()
##               each frame keeps it level whatever the wrist does).

const SIDE_BONES := ["hand", "middle_01", "index_01", "pinky_01", "thumb_01"]


## The grip frame in the hand bone's own space (origin: where the handle sits in a closed fist;
## X: across the palm toward the index finger; Y: the knuckle direction; Z: X x Y). Empty basis if bones are missing.
static func hand_frame(sk: Skeleton3D, side: String) -> Transform3D:
	var ids := {}
	for b in SIDE_BONES:
		var i := sk.find_bone("%s_%s" % [b, side])
		if i < 0:
			return Transform3D()
		ids[b] = i
	var th := sk.get_bone_global_rest(ids.hand)
	var h := th.origin
	var m := sk.get_bone_global_rest(ids.middle_01).origin
	var ix := sk.get_bone_global_rest(ids.index_01).origin
	var pk := sk.get_bone_global_rest(ids.pinky_01).origin
	var tb := sk.get_bone_global_rest(ids.thumb_01).origin
	var f := (m - h).normalized()
	var a := ix - pk
	a = (a - f * a.dot(f)).normalized()
	var n := f.cross(a)
	var t := tb - h
	t = t - f * t.dot(f) - a * t.dot(a)
	if t.dot(n) < 0.0:
		n = -n                                         # the palm faces the side the thumb is on
	var gp := h + (m - h) * 0.9 + n * 0.03
	# a real grip runs DIAGONALLY across the palm (base of the index finger to the heel of the hand), so the head /
	# blade leans ~45 degrees toward the knuckles: raised to guard, a blade points AT the opponent (not up past
	# its own face), and raised to the shoulder it stands clear of the head
	var x := (a + f * 1.0).normalized()
	var y := (f - x * f.dot(x)).normalized()
	var g := Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), gp)
	return th.affine_inverse() * g


## All vertices of the meshes under `root`, in `root`'s space.
static func _verts(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var rel := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			rel = (n as Node3D).transform * rel
			n = n.get_parent()
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				out.append(rel * v)
	return out


## The prop's grip frame in `root`'s space (same axis meaning as hand_frame), for a "tool".
static func tool_frame(root: Node3D) -> Dictionary:
	var vs := _verts(root)
	if vs.is_empty():
		return {}
	var lo := vs[0]
	var hi := vs[0]
	for v in vs:
		lo = lo.min(v)
		hi = hi.max(v)
	var ext := hi - lo
	var k := 0 if ext.x >= ext.y and ext.x >= ext.z else (1 if ext.y >= ext.z else 2)
	var p := (k + 1) % 3
	var q := (k + 2) % 3
	var u0 := lo[k]
	var length := ext[k]
	# cross-section of each end third: the head is the fat end
	var ends := [[INF, -INF, INF, -INF, 0], [INF, -INF, INF, -INF, 0]]
	var handle_c := Vector2.ZERO
	var handle_n := 0
	for v in vs:
		var f := (v[k] - u0) / maxf(length, 1e-4)
		var e := -1
		if f < 0.3:
			e = 0
		elif f > 0.7:
			e = 1
		if e >= 0:
			var en: Array = ends[e]
			en[0] = minf(en[0], v[p]); en[1] = maxf(en[1], v[p]); en[2] = minf(en[2], v[q]); en[3] = maxf(en[3], v[q]); en[4] += 1
	var area0: float = (ends[0][1] - ends[0][0]) * (ends[0][3] - ends[0][2])
	var area1: float = (ends[1][1] - ends[1][0]) * (ends[1][3] - ends[1][2])
	var head_hi := area1 >= area0
	var sgn := 1.0 if head_hi else -1.0
	var handle_end := lo[k] if head_hi else hi[k]
	# the handle's centre line, from the slice where it is held, and the head's mass offset from it
	var grip_u := handle_end + sgn * maxf(0.07, length * 0.2)
	var head_c := Vector2.ZERO
	var head_n := 0
	for v in vs:
		var f2 := (v[k] - u0) / maxf(length, 1e-4)
		var in_head := f2 > 0.75 if head_hi else f2 < 0.25
		if absf(v[k] - grip_u) < length * 0.08:
			handle_c += Vector2(v[p], v[q])
			handle_n += 1
		elif in_head:
			head_c += Vector2(v[p], v[q])
			head_n += 1
	if handle_n > 0:
		handle_c /= handle_n
	if head_n > 0:
		head_c /= head_n
	var x := Vector3.ZERO
	x[k] = sgn
	var off := head_c - handle_c
	var y := Vector3.ZERO
	if off.length() > length * 0.04:
		y[p] = off.x
		y[q] = off.y
	else:
		# a symmetric head (a cross-pein hammer): along the head's longer side
		var he: Array = ends[1] if head_hi else ends[0]
		if (he[1] - he[0]) >= (he[3] - he[2]):
			y[p] = 1.0
		else:
			y[q] = 1.0
	y = y.normalized()
	var o := Vector3.ZERO
	o[k] = grip_u
	o[p] = handle_c.x
	o[q] = handle_c.y
	return {"xf": Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), o), "length": length, "axis": k, "head_hi": head_hi}


## A hanging prop's hold point (top of its bail), in `root`'s space.
static func hang_point(root: Node3D) -> Vector3:
	var vs := _verts(root)
	if vs.is_empty():
		return Vector3.ZERO
	var lo := vs[0]
	var hi := vs[0]
	for v in vs:
		lo = lo.min(v)
		hi = hi.max(v)
	# a real point of the prop (the bail's top, or the rim if the bail lies folded): never the empty middle of an
	# opening - the top-most vertices, the one nearest the vertical axis
	var axis := Vector2((lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5)
	var best := Vector3((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5)
	var bd := INF
	for v in vs:
		if v.y < hi.y - 0.03:
			continue
		var d := Vector2(v.x, v.z).distance_to(axis)
		if d < bd:
			bd = d
			best = v
	return best - Vector3(0, 0.01, 0)


## Keep a hanging prop upright under the fist: `holder` (top_level) hangs from the grip point of `hand`.
static func hang(holder: Node3D, hand: Node3D, hand_grip: Transform3D, hold_at: Vector3, yaw: float, scale := 1.0) -> void:
	var at := hand.global_transform * hand_grip.origin
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	holder.global_transform = Transform3D(b, at - b * hold_at)


## A bladed weapon (sword, sabre, dagger, machete): the handle is the narrow length that ends at a guard or where
## the blade widens; the fist closes round its middle; the blade rises from the thumb side and its EDGE (the blade's
## wider cross-section) leads along the knuckles. Same axis meaning as hand_frame; plus "tip" (root space).
static func blade_frame(root: Node3D) -> Dictionary:
	var vs := _verts(root)
	if vs.is_empty():
		return {}
	var lo := vs[0]
	var hi := vs[0]
	for v in vs:
		lo = lo.min(v)
		hi = hi.max(v)
	var ext := hi - lo
	var k := 0 if ext.x >= ext.y and ext.x >= ext.z else (1 if ext.y >= ext.z else 2)
	var p := (k + 1) % 3
	var q := (k + 2) % 3
	var length := ext[k]
	const N := 40
	var wmax := []
	var wp := []
	var wq := []
	var cen := []
	for i in N:
		wmax.append(0.0)
		wp.append([INF, -INF])
		wq.append([INF, -INF])
		cen.append(Vector2.ZERO)
	var cnt := []
	cnt.resize(N)
	cnt.fill(0)
	for v in vs:
		var i := clampi(int((v[k] - lo[k]) / maxf(length, 1e-4) * N), 0, N - 1)
		wp[i] = [minf(wp[i][0], v[p]), maxf(wp[i][1], v[p])]
		wq[i] = [minf(wq[i][0], v[q]), maxf(wq[i][1], v[q])]
		cen[i] += Vector2(v[p], v[q])
		cnt[i] += 1
	for i in N:
		if cnt[i] > 0:
			wmax[i] = maxf(wp[i][1] - wp[i][0], wq[i][1] - wq[i][0])
			cen[i] /= cnt[i]
	# FIRST by shape: a handle is ROUND (thick both ways), a blade is FLAT (wide but millimetres thin). The end whose
	# slices are least flat is the handle, and it runs until the cross-section turns flat (the blade begins). This
	# holds for a machete or a cleaver whose blade widens toward the tip (the width rule below would pick the tip).
	var flat := func(i: int) -> float:
		if cnt[i] == 0:
			return 0.0
		var a: float = wp[i][1] - wp[i][0]
		var b: float = wq[i][1] - wq[i][0]
		return maxf(a, b) / maxf(minf(a, b), 0.002)
	var end_flat := [0.0, 0.0]
	for e in 2:
		var tot := 0.0
		var nn := 0
		for j in range(1, int(N * 0.18)):
			var i0 := (N - 1 - j) if e == 1 else j
			if cnt[i0] > 0:
				tot += float(flat.call(i0))
				nn += 1
		end_flat[e] = tot / maxf(nn, 1)
	if absf(float(end_flat[0]) - float(end_flat[1])) > 1.0 and minf(end_flat[0], end_flat[1]) < 2.6:
		var fh0: bool = float(end_flat[1]) < float(end_flat[0])
		var hl := 2
		for j in range(2, int(N * 0.5)):
			var i1 := (N - 1 - j) if fh0 else j
			if cnt[i1] > 0 and float(flat.call(i1)) > 2.6:
				hl = j
				break
			hl = j
		var best0 := {"ratio": 9.0, "from_hi": fh0, "g": hl, "by": "shape"}
		return _blade_from(best0, lo, hi, k, p, q, length, N, wp, wq, cen, cnt)
	# otherwise by width: the widest slice within the first 40 % (the guard / where the blade starts), and how much
	# wider it is than what lies between it and the end (a handle is narrow)
	var best := {"ratio": 0.0}
	for from_hi in [false, true]:
		var g := -1
		var gw := -1.0
		for j in range(1, int(N * 0.4)):
			var i := (N - 1 - j) if from_hi else j
			if float(wmax[i]) > gw:
				gw = float(wmax[i])
				g = j
		if g < 2:
			continue
		var hw := []
		for j in range(0, g):
			var i2 := (N - 1 - j) if from_hi else j
			if cnt[i2] > 0:
				hw.append(float(wmax[i2]))
		if hw.is_empty():
			continue
		hw.sort()
		var med: float = hw[hw.size() >> 1]
		var ratio := gw / maxf(med, 1e-4)
		if ratio > float(best.ratio):
			best = {"ratio": ratio, "from_hi": from_hi, "g": g}
	if best.ratio < 1.2:
		return {}
	return _blade_from(best, lo, hi, k, p, q, length, N, wp, wq, cen, cnt)


static func _blade_from(best: Dictionary, lo: Vector3, hi: Vector3, k: int, p: int, q: int, length: float, N: int, wp: Array, wq: Array, cen: Array, cnt: Array) -> Dictionary:
	var fh: bool = best.from_hi
	var gj: int = best.g
	var grip_j := maxi(1, int(gj * 0.5))
	var gi := (N - 1 - grip_j) if fh else grip_j
	var u := lo[k] + (float(gi) + 0.5) / N * length
	var x := Vector3.ZERO
	x[k] = -1.0 if fh else 1.0                        # handle -> blade
	# the edge: the blade's wider side, measured over the blade's middle
	var ep := 0.0
	var eq := 0.0
	for j in range(gj + 2, N - 2):
		var i3 := (N - 1 - j) if fh else j
		if cnt[i3] > 0:
			ep += wp[i3][1] - wp[i3][0]
			eq += wq[i3][1] - wq[i3][0]
	var y := Vector3.ZERO
	if ep >= eq:
		y[p] = 1.0
	else:
		y[q] = 1.0
	var o := Vector3.ZERO
	o[k] = u
	o[p] = (cen[gi] as Vector2).x
	o[q] = (cen[gi] as Vector2).y
	var tip := o
	tip[k] = lo[k] if fh else hi[k]
	return {"xf": Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), o), "length": length, "tip": tip, "ratio": snappedf(float(best.ratio), 0.01), "by": String(best.get("by", "width"))}
