## Shared helpers for the v1 invariant checks: the FINAL bone poses (after every modifier, the VRM springs included -
## read from the springs modifier's modification_processed signal) and CPU skinning of a mesh from them.
class_name InvCommon
extends RefCounted


## Starts capturing c's final bone poses; returns a Dictionary {"poses": Array[Transform3D]} that fills every frame.
static func capture(c: WorldCharacter) -> Dictionary:
	var box := {"poses": []}
	var sk := c.skeleton
	var last: SkeletonModifier3D = null
	for n in sk.get_children(true):
		if n is SkeletonModifier3D:
			last = n
	if last == null:
		return box
	last.modification_processed.connect(func():
		var arr := []
		arr.resize(sk.get_bone_count())
		for i in sk.get_bone_count():
			arr[i] = sk.get_bone_global_pose(i)
		box.poses = arr)
	return box


## The mesh's vertices skinned with `poses` (skeleton space), every `step`-th vertex. Returns [PackedVector3Array
## skinned, PackedVector3Array rest, PackedInt32Array index map] for surface `si`.
static func skin(m: MeshInstance3D, sk: Skeleton3D, poses: Array, si := 0) -> Array:
	var arr := m.mesh.surface_get_arrays(si)
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var BI = arr[Mesh.ARRAY_BONES]
	var BW = arr[Mesh.ARRAY_WEIGHTS]
	var out := PackedVector3Array()
	out.resize(V.size())
	if BI == null or BW == null or m.skin == null or poses.is_empty():
		return [V, V]
	var per: int = (BI as Array).size() / maxi(V.size(), 1) if BI is Array else (BI as PackedInt32Array).size() / maxi(V.size(), 1)
	var bind_bone := []
	for bi in m.skin.get_bind_count():
		var b := m.skin.get_bind_bone(bi)
		if b < 0:
			b = sk.find_bone(m.skin.get_bind_name(bi))
		bind_bone.append(b)
	for vi in V.size():
		var p := Vector3.ZERO
		for k in per:
			var w: float = BW[vi * per + k]
			if w <= 0.0001:
				continue
			var bidx: int = BI[vi * per + k]
			var bb: int = bind_bone[bidx]
			if bb < 0 or bb >= poses.size():
				continue
			p += ((poses[bb] as Transform3D) * m.skin.get_bind_pose(bidx) * V[vi]) * w
		out[vi] = p
	return [out, V]


## The worst triangle stretch of a skinned surface: max over edges of (skinned length / rest length), ignoring tiny
## rest edges.
static func stretch(m: MeshInstance3D, skinned: PackedVector3Array, rest: PackedVector3Array, si := 0) -> float:
	var arr := m.mesh.surface_get_arrays(si)
	var I = arr[Mesh.ARRAY_INDEX]
	if I == null:
		return 1.0
	var idx: PackedInt32Array = I
	var worst := 1.0
	for t in range(0, idx.size(), 3):
		for e in 3:
			var a: int = idx[t + e]
			var b: int = idx[t + (e + 1) % 3]
			var r := rest[a].distance_to(rest[b])
			if r < 0.003:
				continue
			worst = maxf(worst, skinned[a].distance_to(skinned[b]) / r)
	return worst
