class_name WorldTargets
extends RefCounted
## Real things in the world a hand, a foot or a seat can meet (2026-10-20, the action player's contact behaviours:
## "hands land on the real surface of the tree, flower, rail, water or Luna, seats and ledges are found in the world").
## Each finder returns a target {kind, node, point (the surface point the hand goes to), stand (where she stands),
## face (what she faces), radius} or {} when there is none near enough.
##   tree    a tree in cat_trees: the trunk's real radius at chest height, measured from its own mesh (the navigation
##           cylinder round it is a metre wide, far outside the bark)
##   flower  a GatherNode plant that is not picked: its top
##   water   any node in group "water" (the lake's surface): the surface point nearest to her
##   seat    an Interactable with a seat (sit_point): the seat's edge
##   partner the other girl: her chest / shoulder / hand, as the behaviour asks
##   ground  the ground in front of her (always there)

const SEARCH := 22.0                     # m round her
static var _trunk_cache := {}            # mesh resource id -> local radius at chest height


static func find(c: WorldCharacter, kind: String, bone_height := 1.15) -> Dictionary:
	match kind:
		"tree":
			return tree(c, bone_height)
		"flower":
			return flower(c)
		"water":
			return water(c)
		"seat":
			return seat(c)
		"partner":
			return partner(c)
	return ground(c)


static func tree(c: WorldCharacter, h := 1.15) -> Dictionary:
	var best: Node3D = null
	var bd := SEARCH
	for t in c.get_tree().get_nodes_in_group("cat_trees"):
		var n := t as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var d := _flat(n.global_position - c.global_position).length()
		if d < bd:
			bd = d
			best = n
	if best == null:
		return {}
	var s := best.global_transform.basis.get_scale().x
	var r_local := _trunk_radius(best, h / maxf(s, 0.01))
	var r := r_local * s
	var axis := best.global_position
	var y := axis.y + h
	var to_me := _flat(c.global_position - axis).normalized()
	if to_me == Vector3.ZERO:
		to_me = Vector3.FORWARD
	var p := Vector3(axis.x, y, axis.z) + to_me * r
	return {"kind": "tree", "node": best, "point": p, "stand": Vector3(axis.x, c.global_position.y, axis.z) + to_me * (r + 0.55),
		"face": Vector3(axis.x, y, axis.z), "radius": r}


## The trunk's radius at height h (the tree's local frame): the vertices of its nearest drawn parts in a 30 cm band at
## that height, nearest the axis (a branch or the root flare never widens it).
static func _trunk_radius(root: Node3D, h: float) -> float:
	var key := root.get_instance_id()
	for ch in root.get_children():
		var mi := ch as MeshInstance3D
		if mi == null or mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var mk := mi.mesh.get_instance_id()
		if _trunk_cache.has(mk):
			return float(_trunk_cache[mk])
		var ds := []
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in V:
				var lv: Vector3 = mi.transform * v
				if absf(lv.y - h) < 0.15:
					ds.append(Vector2(lv.x, lv.z).length())
		if ds.size() > 8:
			ds.sort()
			var r := float(ds[int(ds.size() * 0.25)])
			_trunk_cache[mk] = r
			return r
	_trunk_cache[key] = 0.3
	return 0.3


static func flower(c: WorldCharacter) -> Dictionary:
	var best: Node3D = null
	var bd := SEARCH
	for g in c.get_tree().get_nodes_in_group("gatherable"):
		var n := g as Node3D
		if n == null or not n.is_visible_in_tree() or bool(n.get("picked")):
			continue
		var d := _flat(n.global_position - c.global_position).length()
		if d < bd:
			bd = d
			best = n
	if best == null:
		return {}
	var top := best.global_position + Vector3(0, 0.25, 0)
	var plant: Node3D = best.get("_plant")
	if plant:
		var bb := _aabb(plant)
		if bb.size != Vector3.ZERO:
			top = Vector3(best.global_position.x, bb.end.y, best.global_position.z)
	var to_me := _flat(c.global_position - best.global_position).normalized()
	if to_me == Vector3.ZERO:
		to_me = Vector3.FORWARD
	return {"kind": "flower", "node": best, "point": top, "stand": best.global_position + to_me * 0.55, "face": top, "radius": 0.1}


static func water(c: WorldCharacter) -> Dictionary:
	var best: Node3D = null
	var bd := SEARCH
	for w in c.get_tree().get_nodes_in_group("water"):
		var n := w as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var d := _flat(n.global_position - c.global_position).length()
		if d < bd:
			bd = d
			best = n
	if best == null:
		return {}
	var bb := _aabb(best)
	var q := c.global_position
	var p := Vector3(clampf(q.x, bb.position.x, bb.end.x), bb.end.y, clampf(q.z, bb.position.z, bb.end.z))
	var to_me := _flat(q - p).normalized()
	return {"kind": "water", "node": best, "point": p, "stand": p + to_me * 0.6, "face": p, "radius": 0.0}


static func seat(c: WorldCharacter) -> Dictionary:
	var main = c.get_tree().root.get_node_or_null("Main")
	var w = main.get("world") if main else null
	if w == null or w.get("interactables") == null:
		return {}
	var best = null
	var bd := SEARCH
	for id in w.interactables:
		var it = w.interactables[id]
		if it.get("sit_point") == null or bool(it.get("busy")):
			continue
		var d := _flat((it as Node3D).global_position - c.global_position).length()
		if d < bd:
			bd = d
			best = it
	if best == null:
		return {}
	var sp: Vector3 = (best as Node3D).get_parent().to_global(best.sit_point)
	return {"kind": "seat", "node": best, "point": sp, "stand": best.approach_point(), "face": sp + (sp - (best.approach_point() as Vector3)), "radius": 0.0}


static func partner(c: WorldCharacter) -> Dictionary:
	var main = c.get_tree().root.get_node_or_null("Main")
	if main == null:
		return {}
	var other: WorldCharacter = null
	for id in main.characters:
		var o: WorldCharacter = main.characters[id]
		if o != c and o.visible and String(o.character_id) in ["mika", "luna"]:
			other = o
	if other == null:
		return {}
	var sk := other.skeleton
	var chest: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("UpperChest")).origin
	var to_me := _flat(c.global_position - other.global_position).normalized()
	if to_me == Vector3.ZERO:
		to_me = Vector3.FORWARD
	return {"kind": "partner", "node": other, "point": chest + to_me * 0.12, "stand": other.global_position + to_me * 0.75, "face": chest, "radius": 0.12}


static func ground(c: WorldCharacter) -> Dictionary:
	var fwd := -c.global_transform.basis.z
	var p := c.global_position + _flat(fwd).normalized() * 0.5
	return {"kind": "ground", "node": null, "point": p, "stand": c.global_position, "face": p, "radius": 0.0}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var bb := m.global_transform * m.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out
