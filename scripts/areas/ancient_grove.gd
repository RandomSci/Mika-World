extends ForestRegion
## B1 Ancient Grove + B4 Forgotten Forest Shrine (Enchanted Forest) - rebuilt on the Whispering Woods' realistic
## toolkit (the world-quality gate). The oldest forest in the realm: a 280 m wood of colossal trees.
##   S  the track from the Whispering Woods enters through ferny woodland and climbs gently north
##   C  the GROVE: a moss-carpeted clearing under a ring of colossal trees; the ELDEST TREE (its root flare taller
##      than a person), a FALLEN GIANT lying across the west side, glowcaps lighting the roots after dark
##   B  the BROOK crossing the wood west to east, forded on stepping stones
##   N  the SHRINE HILL: worn steps up to the FORGOTTEN SHRINE - a terrace, a facade with an arched door between
##      two guardian statues, broken pillars, an altar with a rune plate, glyph stones in an arc below
##   NE the forest track down to the River Valley
## Gates: south edge -> Whispering Woods (it lies south-east), north-east corner -> River Valley.

const GROVE := Vector2(-4, 30)
const ELDEST := Vector2(-16, 22)
const SHRINE := Vector2(6, -66)
const SHRINE_TOP := 5.0          # the hill rises this much above the wood
const FORD := Vector2(4, -14)
const GATE_WOODS := Vector2(34, 134)
const GATE_RIVER := Vector2(110, -134)

var stone: ShaderMaterial
var glyph_mats: Array = []
var _shrine_root: Node3D


func _init() -> void:
	trails = [
		[[GATE_WOODS, Vector2(30, 116), Vector2(18, 96), Vector2(22, 76), Vector2(10, 56), GROVE + Vector2(6, 8)], 3.0, "main"],
		[[GROVE + Vector2(4, -6), Vector2(6, 6), Vector2(5, -4), FORD, Vector2(3, -26), Vector2(5, -40), SHRINE + Vector2(0, 16)], 2.8, "main"],
		[[Vector2(5, -40), Vector2(26, -50), Vector2(48, -66), Vector2(70, -88), Vector2(92, -112), GATE_RIVER], 2.6, "main"],
		[[GROVE + Vector2(-8, 4), ELDEST + Vector2(4, 4)], 1.6, "narrow"],
		[[GROVE + Vector2(-10, -4), Vector2(-34, -2), Vector2(-50, 6), Vector2(-62, 20)], 1.2, "hidden"],
	]
	clearings = [[GROVE, 15.0, "grove"], [SHRINE, 14.0, "ruin_court"], [GATE_WOODS + Vector2(0, -10), 9.0, "glade"]]
	streams = [[[Vector2(-140, -6), Vector2(-90, -18), Vector2(-46, -10), Vector2(-14, -16), FORD, Vector2(34, -8), Vector2(80, -20), Vector2(140, -12)], 2.6, 1.3]]


func gate_spots() -> Array:
	return [GATE_WOODS, GATE_RIVER]


func shape(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	# the shrine hill: a broad rounded rise, its top levelled for the court
	var d := p.distance_to(SHRINE)
	h += SHRINE_TOP * (1.0 - smoothstep(15.0, 52.0, d))
	# the grove sits in a shallow bowl (moist, mossy)
	h -= 0.8 * (1.0 - smoothstep(10.0, 36.0, p.distance_to(GROVE)))
	# the wood falls away gently north-east toward the river valley
	h -= smoothstep(20.0, 140.0, x - z * 0.4) * 3.0
	return h


func density(p: Vector2, f: float) -> float:
	# the deep old wood west of the grove is the densest; open, ferny woodland near the entry
	f += 0.2 * (1.0 - smoothstep(30.0, 90.0, p.distance_to(Vector2(-70, 20))))
	f -= 0.2 * (1.0 - smoothstep(20.0, 50.0, p.distance_to(GATE_WOODS)))
	return f


func _ford_at(p: Vector2) -> bool:
	return p.distance_to(FORD) < 4.5


func features() -> Array:
	return [_giants, _fallen_giant, _ford_stones, _shrine, _glyph_stones, _glowcaps,
		func(): dress_clearing(GROVE, 15.0, true, [[ELDEST, 4.0]]),
		func(): dress_clearing(SHRINE + Vector2(0, 26), 8.0, true, [[SHRINE + Vector2(0, 14), 4.0]])]


func _v(p: Vector2) -> Vector3:
	return Vector3(p.x, height(p.x, p.y), p.y)


func _stone() -> ShaderMaterial:
	if stone == null:
		stone = RealKit.stone_mat("mossy_stone_wall") if RealKit.enabled() else Kit.tri("mossy_rock", "2k", 0.4, 0.95)
	return stone


# ------------------------------------------------------------------ the colossal trees
func _giants() -> void:
	var root := Node3D.new()
	root.name = "Giants"
	add_child(root)
	# a ring of colossal trees round the grove (and a few through the old wood): 3-4x a forest tree
	var spots := [[ELDEST, 7.0, "CommonTree_3"], [GROVE + Vector2(19, 8), 5.4, "CommonTree_1"], [GROVE + Vector2(13, -17), 5.0, "CommonTree_5"],
		[GROVE + Vector2(-20, -11), 5.2, "CommonTree_4"], [GROVE + Vector2(-5, 24), 4.8, "CommonTree_2"], [GROVE + Vector2(22, 24), 4.6, "CommonTree_4"],
		[Vector2(-60, -40), 5.2, "CommonTree_3"], [Vector2(-82, 40), 5.6, "CommonTree_1"], [Vector2(-40, 70), 4.6, "CommonTree_2"],
		[Vector2(48, 30), 5.0, "CommonTree_5"], [Vector2(-28, -44), 4.4, "CommonTree_3"], [Vector2(40, -36), 4.8, "CommonTree_2"]]
	var by_model := {}
	var trunk_xf := []
	var roots := []
	for sp in spots:
		var p: Vector2 = sp[0]
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * float(sp[1])), _v(p) - Vector3(0, 0.4, 0))
		(by_model.get_or_add(String(sp[2]), []) as Array).append(xf)
		trunk_xf.append(xf)
		roots.append(p)
	for id in by_model:
		NatureKit.scatter(root, NatureKit.mesh(String(id)), by_model[id], {"shadow": true, "vis_end": 400.0, "name": "Giant_" + String(id)})
	NatureKit.trunk_colliders(root, trunk_xf, 0.33, 4.0)
	# moss-wrapped root flares round every giant, the eldest's taller than a person
	for i in roots.size():
		var p2: Vector2 = roots[i]
		var s := 2.0 if i == 0 else 1.5
		for k in (4 if i == 0 else 3):
			var off := Vector2.from_angle(k * TAU / (4.0 if i == 0 else 3.0) + i) * (1.7 if i == 0 else 1.2)
			var rc := Kit.place_prop(root, "root_cluster_01", Kit.xf(_v(p2 + off) - Vector3(0, 0.45, 0), k * 2.1 + i, Vector3.ONE * s), "", false)
			rc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_location("ancient_grove", Vector3(GROVE.x, 0, GROVE.y), 26.0, _v(GROVE + Vector2(2, 0)), "a moss-carpeted clearing under a ring of colossal trees")


func _fallen_giant() -> void:
	var at := _v(Vector2(-30, 34))
	Kit.place_prop(self, "dead_tree_trunk_02", Kit.xf(at - Vector3(0, 0.25, 0), 0.4, Vector3.ONE * 1.9), "", true)
	# a whole fallen tree beside it: the trunk on the ground, its dead crown in the ferns
	var fall := Transform3D(Basis(Vector3.UP, 1.9) * Basis(Vector3.FORWARD, PI * 0.5 - 0.06).scaled(Vector3.ONE * 2.4), _v(Vector2(-46, 46)) + Vector3(0, 0.5, 0))
	NatureKit.scatter(self, NatureKit.mesh("DeadTree_2"), [fall], {"shadow": true, "vis_end": 200.0, "name": "FallenGiant"})
	Kit.place_prop(self, "tree_stump_02", Kit.xf(_v(Vector2(-41, 25)) - Vector3(0, 0.1, 0), 1.2, Vector3.ONE * 2.6), "", true)
	for spec in [[Vector2(-22, 12), "rock_moss_set_01_rock02", 1.8], [Vector2(18, 38), "rock_moss_set_01_rock05", 2.0], [Vector2(-34, 44), "rock_moss_set_01_rock04", 1.9],
			[Vector2(10, 50), "rock_moss_set_01_rock06", 1.5], [Vector2(28, 14), "rock_moss_set_01_rock01", 2.2], [Vector2(-8, -30), "rock_moss_set_01_rock03", 1.7]]:
		var p: Vector2 = spec[0]
		Kit.place_prop(self, "rock_moss_set_01", Kit.xf(_v(p) - Vector3(0, 0.35, 0), rng.randf() * TAU, Vector3.ONE * float(spec[2])), String(spec[1]), true)


func _ford_stones() -> void:
	for i in 7:
		var p := FORD + Vector2(-3.0 + i * 1.0, rng.randf_range(-0.7, 0.7)).rotated(0.3)
		var mi := Kit.mesh_node(self, Kit.rock_mesh(0.44, 700 + i, 0.25, Vector3(1.3, 0.42, 1.0)), _stone(), Kit.xf(_v(p) + Vector3(0, 0.95, 0), i))
		Kit.convex_collide(mi)
	add_poi("brook_ford", _v(FORD), "Stepping stones across the brook", "ancient_grove")


# ------------------------------------------------------------------ the forgotten shrine
func _shrine() -> void:
	_shrine_root = Node3D.new()
	_shrine_root.name = "Shrine"
	add_child(_shrine_root)
	var c := _v(SHRINE)
	var sb := StoneBuilder.new(height, 61)
	sb.base_y = c.y - 0.6
	sb.top_y = c.y + 9.0
	# the terrace (a low retaining wall round the court) and the worn steps up its south face
	var ty := c.y + 0.9
	sb.block(Transform3D(Basis.IDENTITY, Vector3(c.x, ty - 0.55, c.z - 2.0)), Vector3(17.0, 1.1, 12.0), 0.5, 0.1)
	sb.steps(Vector3(c.x, height(c.x, c.z + 13.0), c.z + 13.0), Vector3(c.x, ty, c.z + 4.2), 4.6, 0.46, 0.15, 0.6)
	# the facade: a wall with an arched doorway (dark beyond), cornice with missing blocks
	var fz := c.z - 7.5
	sb.wall(Vector3(c.x - 8.0, ty, fz), Vector3(c.x - 2.0, ty, fz), 6.4, 1.4, 0.15)
	sb.wall(Vector3(c.x + 2.0, ty, fz), Vector3(c.x + 8.0, ty, fz), 6.4, 1.4, 0.25)
	sb.arch(Vector3(c.x, ty, fz), 0.0, 4.0, 3.4, 0.9, 1.4, true, 0.0)
	for i in 10:
		if i == 2 or i == 7:
			continue
		sb.block(Transform3D(Basis.IDENTITY, Vector3(c.x - 7.6 + i * 1.7, ty + 6.7, fz)), Vector3(1.6, 0.55, 1.9), 0.6, 0.06)
	# broken pillars along the court, an altar before the door
	var ph := [4.4, 2.2, 3.6, 1.4]
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		sb.column(Vector3(c.x + sx * 6.6, ty, c.z - 4.6 + floorf(i / 2.0) * 5.0), 0.46, ph[i])
	sb.block(Transform3D(Basis.IDENTITY, Vector3(c.x, ty + 0.5, c.z - 3.4)), Vector3(1.8, 1.0, 1.0), 0.3, 0.06)
	sb.collider(Transform3D(Basis.IDENTITY, Vector3(c.x, ty + 0.5, c.z - 3.4)), Vector3(1.8, 1.0, 1.0))
	# behind the door, a small roofless sanctum (side walls and a back wall): the doorway opens into shadow
	sb.wall(Vector3(c.x - 3.0, ty, fz - 0.6), Vector3(c.x - 3.0, ty, fz - 5.0), 5.2, 0.9, 0.2)
	sb.wall(Vector3(c.x + 3.0, ty, fz - 0.6), Vector3(c.x + 3.0, ty, fz - 5.0), 5.2, 0.9, 0.3)
	sb.wall(Vector3(c.x - 3.4, ty, fz - 5.2), Vector3(c.x + 3.4, ty, fz - 5.2), 5.6, 1.0, 0.1)
	sb.finish(_shrine_root, _stone(), "ShrineStone")
	# guardian statues flanking the door, on plinths
	for sx: float in [-1.0, 1.0]:
		var plinth := Vector3(c.x + sx * 4.4, ty, fz + 1.6)
		Kit.block(_shrine_root, Vector3(2.0, 0.6, 1.6), Kit.xf(plinth + Vector3(0, 0.3, 0)), _stone(), true, 0.05)
		Kit.place_prop(_shrine_root, "gothic_statue", Kit.xf(plinth + Vector3(0, 0.6, 0), PI + sx * 0.22, Vector3.ONE * 1.5), "", false)
	# the rune plate on the altar (it brightens when an offering is made)
	var g := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 0.85)
	g.mesh = q
	g.material_override = _glyph_mat(Color(0.35, 0.9, 0.75), 6)
	g.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(c.x, ty + 1.02, c.z - 3.4))
	_shrine_root.add_child(g)
	Kit.omni(_shrine_root, Vector3(c.x, ty + 1.8, c.z - 3.0), Color(0.4, 1.0, 0.8), 0.9, 6.0)
	add_location("forgotten_forest_shrine", Vector3(c.x, 0, c.z), 16.0, Vector3(c.x, ty, c.z - 1.0), "a forgotten runic shrine on a wooded hill")
	add_poi("shrine_stairs", _v(SHRINE + Vector2(0, 14)), "Foot of the shrine steps", "forgotten_forest_shrine")


func _glyph_mat(col: Color, sides: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/magic/sigil.gdshader")
	m.set_shader_parameter("sides", sides)
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", 0.9)
	m.set_shader_parameter("spin", 0.05)
	m.set_shader_parameter("seed", float(sides))
	glyph_mats.append(m)
	return m


func _glyph_stones() -> void:
	var sb := StoneBuilder.new(height, 67)
	var c := SHRINE + Vector2(0, 24)
	var spots := []
	for i in 5:
		var ang := PI * 0.5 + (i - 2) * 0.38
		var p := c + Vector2(cos(ang), -sin(ang)) * -12.0
		var y := height(p.x, p.y)
		var yaw := atan2(c.x - p.x, c.y - 10.0 - p.y)
		sb.block(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, rng.randf_range(-0.07, 0.07)), Vector3(p.x, y + 1.1, p.y)), Vector3(1.1, 2.7, 0.55), 0.55, 0.07)
		sb.collider(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + 1.1, p.y)), Vector3(1.1, 2.7, 0.55))
		spots.append([p, y, yaw])
	sb.finish(self, _stone(), "GlyphStones")
	for i in spots.size():
		var p2: Vector2 = spots[i][0]
		var yaw2: float = spots[i][2]
		var gm := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.75, 0.75)
		gm.mesh = q
		gm.material_override = _glyph_mat(Color(0.3, 0.85, 0.7), 3 + i)
		gm.transform = Transform3D(Basis(Vector3.UP, yaw2 + PI), Vector3(p2.x, float(spots[i][1]) + 1.5, p2.y) + Basis(Vector3.UP, yaw2) * Vector3(0, 0, -0.3))
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(gm)


# ------------------------------------------------------------------ glowcaps
func _glowcaps() -> void:
	# small bioluminescent mushrooms in clusters at the giants' roots and along the brook (faint by day, they light
	# the grove after dark)
	var cap := Kit.lathe([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.022, 0.09), Vector2(0.09, 0.1), Vector2(0.075, 0.14), Vector2(0.0, 0.16)], 10)
	var bases := [ELDEST, GROVE + Vector2(17, 8), GROVE + Vector2(-18, -10), Vector2(-30, 34), FORD + Vector2(-6, 3), FORD + Vector2(8, -2), GROVE + Vector2(12, -15)]
	var xs := []
	for i in int(320 * float(RenderProfile.get_setting("foliage_density"))):
		var base: Vector2 = bases[i % bases.size()]
		var p: Vector2 = base + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.6, 5.5)
		if trail_at(p.x, p.y) > 0.3:
			continue
		var s := rng.randf_range(0.6, 1.9)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height(p.x, p.y) - 0.02, p.y)))
	Kit.multimesh(self, cap, xs, 45.0, false, Kit.emissive(Color(0.35, 0.75, 1.0), 2.2))
	for b in [ELDEST, GROVE + Vector2(-18, -10), FORD]:
		night_only(Kit.omni(self, _v(b) + Vector3(0, 0.6, 0), Color(0.35, 0.7, 1.0), 0.6, 5.0))
	add_poi("glowcap_patch", _v(ELDEST + Vector2(3, 2)), "Glowing mushrooms among the eldest tree's roots", "ancient_grove")


# ------------------------------------------------------------------ links
func links() -> void:
	edge_gate("whispering_woods", GATE_WOODS)
	edge_gate("river_valley", GATE_RIVER)
	add_interactable(Interactable.make("giant_tree_listen", "Rest a hand on the eldest tree and listen", "meditate", "ancient_grove",
		_v(ELDEST + Vector2(3.0, 2.0)), {"knowledge": {"lore:grove_whispers": 1}}, "look_around", 4.0)).radius = 2.6
	add_interactable(Interactable.make("collect_glowcap", "Gather a glowcap mushroom", "collect", "ancient_grove",
		_v(ELDEST + Vector2(3.5, 3.0)), {"items": {"glowcap": 1}}, "", 2.0)).radius = 2.6
	var top := height(SHRINE.x, SHRINE.y) + 0.9
	add_interactable(Interactable.make("shrine_glyphs_read", "Read the runic glyphs on the shrine stones", "study", "forgotten_forest_shrine",
		Vector3(SHRINE.x, top, SHRINE.y - 1.8), {"knowledge": {"lore:runic_script": 1}}, "look_around", 4.0)).radius = 2.4
	interactables["shrine_glyphs_read"].book_id = "shrine_glyph_stones"   # a real text: read page by page (data/books.json)
	var offer := Interactable.make("shrine_offering", "Leave a glowcap as an offering at the shrine altar", "pray", "forgotten_forest_shrine",
		Vector3(SHRINE.x, top, SHRINE.y - 1.8), {"skills": {"arcane_orb": 0.2}, "knowledge": {"blessing:forest_shrine": 1}}, "spell_casting", 4.2)
	offer.requires = {"items": {"glowcap": 1}}
	offer.radius = 2.4
	offer.on_done = func():
		for m in glyph_mats:
			m.set_shader_parameter("intensity", 2.2)
	add_interactable(offer)
