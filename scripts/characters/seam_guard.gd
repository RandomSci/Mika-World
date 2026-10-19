class_name SeamGuard
extends SkeletonModifier3D
## Skirts and hair never split at their seams (v1 items 8 and 10). VRoid skirts and hair are sheets skinned to many
## spring chains; where a vertex is shared by two neighbouring chains, the chains swinging apart (a turn, a spin)
## stretched the sheet between them into long glassy slivers (tear check 2026-10-19: hem edges 3.6 mm apart at rest
## opening 9-50 cm). Every pair of chain joints that some vertex is skinned to BOTH of is coupled (read from the meshes
## once), and after all the simulation - this runs last, behind the VRM springs and the skirt simulator - each
## coupled pair is pulled back to at most STRETCH times its rest distance, the chains re-aimed joint by joint.
## The simulations keep their own state: this only shapes what is drawn.

const STRETCH := 1.3
const SLACK := 0.008             # m always allowed on top
const MIN_W := 0.1               # a vertex couples two joints when each carries at least this much of it
const ITER := 3

var enabled := true
var pairs: Array = []            # [bone a, bone b, max distance]
var pulled := 0                  # (tests) pairs pulled in the last frame
var _depth := {}                 # bone -> [chain, depth]
var _order: Array = []           # coupled bones, roots first
var _told := false


static func attach(c: WorldCharacter) -> SeamGuard:
	var g := SeamGuard.new()
	g.name = "SeamGuard"
	c.skeleton.add_child(g, false, Node.INTERNAL_MODE_BACK)      # behind the VRM springs and the skirt simulator
	g._build(c)
	return g


func _build(c: WorldCharacter) -> void:
	var sk := c.skeleton
	var re := RegEx.create_from_string("^(J_Sec_.*)_(\\d+)$")
	var seen := {}
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		if m.mesh == null or m.skin == null or not (nm.contains("Skirt") or nm.contains("Hair")):
			continue
		var bind := []
		for bi in m.skin.get_bind_count():
			var b := m.skin.get_bind_bone(bi)
			bind.append(b if b >= 0 else sk.find_bone(m.skin.get_bind_name(bi)))
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var BI = arr[Mesh.ARRAY_BONES]
			var BW = arr[Mesh.ARRAY_WEIGHTS]
			var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if BI == null or BW == null or nv == 0:
				continue
			var per: int = (BI as PackedInt32Array).size() / nv if BI is PackedInt32Array else (BI as Array).size() / nv
			for vi in nv:
				var js := []
				for k in per:
					if float(BW[vi * per + k]) < MIN_W:
						continue
					var b: int = bind[int(BI[vi * per + k])]
					if b < 0:
						continue
					if not _depth.has(b):
						var mt := re.search(sk.get_bone_name(b))
						_depth[b] = [mt.get_string(1), int(mt.get_string(2))] if mt else ["", -1]
					if int(_depth[b][1]) >= 1:
						js.append(b)
				for i in js.size():
					for j in range(i + 1, js.size()):
						var a: int = js[i]
						var b2: int = js[j]
						if String(_depth[a][0]) == String(_depth[b2][0]):
							continue                      # (along one chain: its own bones keep their lengths)
						var key := Vector2i(mini(a, b2), maxi(a, b2))
						if seen.has(key):
							continue
						seen[key] = true
						var rd := sk.get_bone_global_rest(a).origin.distance_to(sk.get_bone_global_rest(b2).origin)
						pairs.append([a, b2, rd * STRETCH + SLACK])
	var bones := {}
	for p in pairs:
		bones[p[0]] = true
		bones[p[1]] = true
	_order = bones.keys()
	_order.sort_custom(func(x, y): return int(_depth[x][1]) < int(_depth[y][1]))
	print("[seamguard] %s: %d coupled joint pairs over %d joints" % [c.character_id, pairs.size(), _order.size()])


func _process_modification() -> void:
	var sk := get_skeleton()
	pulled = 0
	if sk == null or not enabled or pairs.is_empty():
		return
	if not _told:
		_told = true
		var mods := sk.get_children(true).filter(func(n): return n is SkeletonModifier3D).map(func(n): return String(n.name))
		print("[seamguard] modifier order: %s" % ", ".join(mods.slice(maxi(mods.size() - 5, 0))))
	var pos := {}
	for b in _order:
		var g := sk.get_bone_global_pose(b)
		if g.basis.get_scale().x < 0.5:
			continue                                     # (a seated panel folded away: left as it is)
		pos[b] = g.origin
	for it in ITER:
		for p in pairs:
			if not (pos.has(p[0]) and pos.has(p[1])):
				continue
			var a: Vector3 = pos[p[0]]
			var b: Vector3 = pos[p[1]]
			var d := a.distance_to(b)
			var mx: float = p[2]
			if d <= mx or d < 1e-6:
				continue
			var fix := (b - a) / d * ((d - mx) * 0.5)
			pos[p[0]] = a + fix
			pos[p[1]] = b - fix
			if it == 0:
				pulled += 1
	if pulled == 0:
		return
	# re-aim each chain from its root down: the parent joint turns so this joint lands on its pulled point
	for b in _order:
		if not pos.has(b):
			continue
		var par := sk.get_bone_parent(b)
		if par < 0 or not String(sk.get_bone_name(par)).begins_with(String(_depth[b][0]) + "_"):
			continue                                     # (only the previous joint of the same chain turns)
		var gp := sk.get_bone_global_pose(par)
		var cur := sk.get_bone_global_pose(b).origin
		var u := cur - gp.origin
		var v: Vector3 = (pos[b] as Vector3) - gp.origin
		if u.length() < 1e-5 or v.length() < 1e-5 or u.normalized().dot(v.normalized()) > 0.99999:
			continue
		sk.set_bone_global_pose(par, Transform3D(Basis(Quaternion(u.normalized(), v.normalized())) * gp.basis, gp.origin))
