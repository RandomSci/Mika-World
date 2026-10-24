class_name FruitTree
extends GatherNode
## A magic fruit tree (25 Oct, Selwyn: "magical fruits on trees"). One of the world's own tree models with glowing
## fruit hung in its crown, each region its own fruit (data/gatherables.json "trees"). The fruit grows too high to
## reach: a mage calls one down with a little spell (Mika frost and stars, Luna moonlight), it drifts down into her
## hands and she catches it (PickupAction). Picked fruit ripens again slowly, one at a time. Planted before the
## area's navmesh bake, so its trunk is solid and the paths go round it.

const FRUITS := 7
const TREE_MODEL := "CommonTree_2"
const TREE_SCALE := 0.72
const ELEMENT := {"mika": "water", "luna": "eclipse"}

var _fruit: Array = []        # [{node: Node3D, at: Vector3 (local), ripe: bool, regrow: float}]
var _glow: OmniLight3D
var _next := -1               # the fruit she is about to call down


## Plant `area_id`'s fruit trees in `area` (before its navmesh bake: the trunk carve goes into the bake).
static func plant(area: Node3D, area_id: String) -> Array:
	load_data()
	var out := []
	var i := 0
	var space := area.get_world_3d().direct_space_state
	for s in data.get("trees", {}).get(area_id, []):
		i += 1
		# the spots are world positions (tests/ext/fruitspots.gd); the ground under them from the area's own colliders
		var q := PhysicsRayQueryParameters3D.create(Vector3(float(s.pos[0]), 400.0, float(s.pos[1])), Vector3(float(s.pos[0]), -200.0, float(s.pos[1])), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var p: Vector3 = hit.position
		var n := FruitTree.new()
		n.name = "Animated_FruitTree_%s_%d" % [s.kind, i]
		n.gid = "%s_tree_%d" % [s.kind, i]
		n.kind = String(s.kind)
		n.def = data.kinds.get(n.kind, {})
		area.add_child(n)
		n.global_position = p
		NatureKit.trunk_colliders(area, [Transform3D(Basis(), area.to_local(p))], 0.32, 3.0)
		out.append(n)
	return out


func _ready() -> void:
	add_to_group("gatherable")
	_plant = Node3D.new()
	_plant.name = "Tree"
	add_child(_plant)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(gid)
	var mi := MeshInstance3D.new()
	mi.mesh = NatureKit.mesh(TREE_MODEL, "common")
	mi.scale = Vector3.ONE * TREE_SCALE
	mi.rotation.y = rng.randf() * TAU
	_plant.add_child(mi)
	var col: Array = def.get("color", [1, 1, 1])
	var c := Color(col[0], col[1], col[2])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = float(def.get("glow", 1.4))
	mat.roughness = 0.35
	var stem_m := StandardMaterial3D.new()
	stem_m.albedo_color = Color(0.22, 0.17, 0.1)
	for at in _fruit_spots(mi, rng):
		var f := Node3D.new()
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.24 if kind.ends_with("pear") else 0.2
		ball.mesh = sm
		ball.material_override = mat
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.add_child(ball)
		var stem := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.012
		cm.height = 0.16
		stem.mesh = cm
		stem.material_override = stem_m
		stem.position.y = 0.17
		f.add_child(stem)
		f.position = at
		_plant.add_child(f)
		_fruit.append({"node": f, "at": at, "ripe": true, "regrow": 0.0})
	_glow = FX.light(c, 0.6 * float(RenderProfile.get_setting("magic_light_scale")), 6.0)
	_glow.position = Vector3(0, _fruit_mid_y(), 0)
	_plant.add_child(_glow)


## Where the fruit hangs: leaf vertices on the lower, outer shell of the crown, spread round the tree (the leaf surface
## is the one sitting highest), so every fruit sits in foliage and shows from below.
func _fruit_spots(mi: MeshInstance3D, rng: RandomNumberGenerator) -> Array:
	var m: Mesh = mi.mesh
	var leaf_i := 0
	var best := -INF
	for i in m.get_surface_count():
		var vs: PackedVector3Array = m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		var sy := 0.0
		for v in vs:
			sy += v.y
		if vs.size() > 0 and sy / vs.size() > best:
			best = sy / vs.size()
			leaf_i = i
	var leaf: PackedVector3Array = m.surface_get_arrays(leaf_i)[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	var rmax := 0.0
	for v in leaf:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
		rmax = maxf(rmax, Vector2(v.x, v.z).length())
	var bins := []
	bins.resize(FRUITS)
	for v in leaf:
		if v.y > lo + (hi - lo) * 0.35 or Vector2(v.x, v.z).length() < rmax * 0.5:
			continue
		var b := int(fposmod(atan2(v.z, v.x), TAU) / TAU * FRUITS) % FRUITS
		if bins[b] == null or rng.randf() < 0.02:
			bins[b] = v
	var out := []
	for v in bins:
		if v != null:
			out.append(mi.transform * (v - Vector3(0, 0.12, 0)))
	return out


func _fruit_mid_y() -> float:
	var y := 0.0
	for f in _fruit:
		y += f.at.y
	return y / maxf(1.0, _fruit.size())


func label() -> String:
	return String(def.get("name", kind))


func available() -> bool:
	return _fruit.any(func(f): return f.ripe)


func _process(delta: float) -> void:
	for f in _fruit:
		if not f.ripe:
			f.regrow -= delta
			if f.regrow <= 0.0:
				f.ripe = true
				var n: Node3D = f.node
				n.position = f.at
				n.visible = true
				n.scale = Vector3.ONE * 0.05
				n.create_tween().tween_property(n, "scale", Vector3.ONE, 3.0).set_trans(Tween.TRANS_SINE)
		elif is_instance_valid(f.node):
			# a slow sway, each fruit its own phase
			(f.node as Node3D).position = f.at + Vector3(0, sin(Time.get_ticks_msec() / 900.0 + f.at.x * 3.0) * 0.025, 0)


## Stand under the ripe fruit nearest to her, a step out from the trunk.
func reach_point(from: Vector3) -> Vector3:
	var best := INF
	_next = -1
	for i in _fruit.size():
		if not _fruit[i].ripe:
			continue
		var g := to_global(_fruit[i].at)
		var d := Vector2(g.x - from.x, g.z - from.z).length()
		if d < best:
			best = d
			_next = i
	if _next < 0:
		return global_position
	var under := to_global(_fruit[_next].at)
	under.y = global_position.y
	var out := Vector3(under.x - global_position.x, 0, under.z - global_position.z)
	if out.length() < 1.4:
		under = global_position + (out.normalized() if out.length() > 0.1 else Vector3.FORWARD) * 1.4
	return under


## The magic: she raises a hand, the fruit loosens with a little burst and drifts down to float before her chest,
## trailed by her own colour of light. Returns the floating fruit (a detached copy) for her hands to catch.
func bring_down(c: WorldCharacter) -> Node3D:
	if _next < 0 or not _fruit[_next].ripe:
		reach_point(c.global_position)
	if _next < 0:
		return null
	var f: Dictionary = _fruit[_next]
	var from := to_global(f.at)
	c.look_at_point(from)
	c.look_head_at(from)
	await get_tree().create_timer(0.5).timeout
	var el: String = ELEMENT.get(c.character_id, "arcane")
	if c.has_clip("ml_cast_one_hand"):
		c.play_gesture("ml_cast_one_hand", 0.3, 0.5)
	await get_tree().create_timer(0.7).timeout
	var tok := (f.node as Node3D).duplicate() as Node3D
	get_parent().add_child(tok)
	tok.global_position = from
	(f.node as Node3D).visible = false
	f.ripe = false
	f.regrow = float(def.get("regrow_s", 1800.0))
	FX.burst(get_parent(), from, 18, 0.9, FX.pm_motes(el, "burst"), FX.mote_mesh(0.05))
	var trail := FX.particles(24, 0.8, FX.pm_motes(el, "trail"), FX.mote_mesh(0.04, true))
	tok.add_child(trail)
	trail.emitting = true
	var halo := FX.light(FX.palette(el)[0], 0.5, 2.0)
	tok.add_child(halo)
	if AudioDirector.instance:
		AudioDirector.instance.play3d("loot_pickup", from, "SFX", -12.0, "fruit_call")
	var fwd := -c.global_transform.basis.z
	var hold := c.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 0.42 + Vector3(0, 1.15, 0)
	var mid := (from + hold) * 0.5 + Vector3(0, 0.4, 0)
	var tw := tok.create_tween()
	tw.tween_method(func(k: float): if is_instance_valid(tok): tok.global_position = from.lerp(mid, k).lerp(mid.lerp(hold, k), k),
		0.0, 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	c.end_gesture()
	trail.emitting = false
	return tok


func harvest(c: WorldCharacter) -> Dictionary:
	var item := String(def.get("item", kind))
	var ch := WorldState.record_activity({"id": "gather:" + kind, "verb": "gather", "label": "Picked a %s" % label()},
		{"items": {item: 1}, "knowledge": {"material:" + item: 1}}, c.character_id)
	return {"ok": true, "detail": "caught a %s" % label().to_lower(), "changes": ch}
