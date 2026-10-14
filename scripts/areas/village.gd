extends ForestRegion
## C1 Village Square + C2 Lantern Market + C3 Craft Workshop (Fantasy Village) - rebuilt on the realistic toolkit
## (world-quality gate). A real village in a forest clearing: masonry-and-half-timber houses (HouseBuilder: stone
## ground storeys with doorways and windows, jettied timber-framed upper storeys, slate roofs, chimneys smoking)
## lining cobbled streets that leave the square for the river road (west), the mountain road (north), the quarry
## road to the caverns (east) and the market lane (north-east); the well under its little roof in the square, the
## lantern market's stalls under strings of lights, the open craft workshop with its forge, lamp posts, gardens;
## the forest all round. The stair up to the observatory hill climbs from the north-west corner.

const SQUARE := Vector2(0, 0)
const MARKET_A := Vector2(8, -8)
const MARKET_B := Vector2(34, -32)
const WORKSHOP := Vector2(20, 22)
const STAIR := Vector2(-26, -30)
const GATE_RIVER := Vector2(-134, 4)
const GATE_HIGHLAND := Vector2(4, -134)
const GATE_CAVES := Vector2(134, 14)

var m: Dictionary
var houses: HouseBuilder
var stone: ShaderMaterial


func _init() -> void:
	trails = [
		[[GATE_RIVER, Vector2(-90, 2), Vector2(-50, 0), Vector2(-16, 0), SQUARE], 4.2, "main"],
		[[SQUARE, Vector2(2, -20), Vector2(0, -50), Vector2(6, -90), GATE_HIGHLAND], 4.0, "main"],
		[[SQUARE, Vector2(18, 4), Vector2(50, 8), Vector2(90, 12), GATE_CAVES], 4.0, "main"],
		[[SQUARE, MARKET_A, MARKET_B], 5.0, "main"],
		[[SQUARE, Vector2(8, 10), WORKSHOP + Vector2(-3, -4)], 2.6, "main"],
		[[SQUARE, Vector2(-12, -14), STAIR + Vector2(3, 3)], 2.6, "main"],
	]
	clearings = [[SQUARE, 15.0, "clearing"], [Vector2(6, -6), 46.0, "glade"]]
	streams = []


func gate_spots() -> Array:
	return [GATE_RIVER, GATE_HIGHLAND, GATE_CAVES]


func shape(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	# the town is level-ish; the observatory hill rises north-west
	h *= 0.5 + 0.5 * smoothstep(30.0, 60.0, p.length())
	h += 10.0 * (1.0 - smoothstep(10.0, 40.0, p.distance_to(Vector2(-52, -56))))
	return h


func density(p: Vector2, f: float) -> float:
	return f * smoothstep(46.0, 64.0, p.distance_to(Vector2(6, -6)))


func features() -> Array:
	return [_mats_and_paving, _houses, _well, _market_stalls, _market_lights, _workshop, _street_lamps, _gardens,
		func(): dress_clearing(Vector2(-30, 26), 8.0, true), func(): dress_clearing(Vector2(34, -4), 6.0, true)]


func _v(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x, height(p.x, p.y) + lift, p.y)


## Streets are cobbled (the terrain's path layer becomes cobblestones here), the materials for the rest.
func _mats_and_paving() -> void:
	m = village_mats()
	stone = RealKit.stone_mat("castle_wall_slates") if RealKit.enabled() else m.stone
	m["stone"] = stone
	magic_receivers = [stone]
	var tm: ShaderMaterial = mats.terrain
	tm.set_shader_parameter("path_alb", RealKit.ph_tex("cobblestone_floor_08", "diff"))
	tm.set_shader_parameter("path_nrm", RealKit.ph_tex("cobblestone_floor_08", "nor_gl"))


# ------------------------------------------------------------------ houses
func _houses() -> void:
	houses = HouseBuilder.new(self, height)
	var lots := []
	# round the square: eight houses facing it
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		var p := SQUARE + Vector2.from_angle(a) * 21.0
		lots.append([p, -a + PI * 0.5 - PI * 0.5, 7.0 + (i % 3), 5.6 + (i % 2) * 0.8, 2 if i % 4 != 2 else 1])
	# along the roads: houses set back from each side, facing the street
	for road in [[Vector2(-26, 0), Vector2(-62, 1)], [Vector2(2, -30), Vector2(1, -64)], [Vector2(30, 6), Vector2(66, 10)]]:
		var a2: Vector2 = road[0]
		var b2: Vector2 = road[1]
		var dir := (b2 - a2).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var n := int(a2.distance_to(b2) / 11.0)
		for k in n:
			for side: float in [-1.0, 1.0]:
				var q := a2 + dir * (5.0 + k * 11.0 + (2.5 if side > 0 else 0.0)) + nrm * side * 10.5
				lots.append([q, 0.0, 6.5 + (k % 3) * 0.8, 5.4 + ((k + int(side)) % 2) * 0.7, 2 if (k + int(side > 0)) % 3 != 1 else 1, -nrm * side])
	var seed := 31
	for lot in lots:
		var p: Vector2 = lot[0]
		var facing: Vector2 = lot[5] if lot.size() > 5 else (SQUARE - p).normalized()
		# keep clear of the market lane, the workshop and the stair
		if WhisperingWoods._seg_dist(p, MARKET_A, MARKET_B) < 9.0 or p.distance_to(WORKSHOP) < 10.0 or p.distance_to(STAIR) < 8.0 or trail_at(p.x, p.y) > 0.05:
			continue
		var yaw := atan2(facing.x, facing.y)
		var base := height(p.x, p.y)
		for dx in [-3.0, 3.0]:
			for dz in [-3.0, 3.0]:
				base = minf(base, height(p.x + dx, p.y + dz))
		houses.house(Vector3(p.x, base, p.y), yaw, float(lot[2]), float(lot[3]), seed, int(lot[4]))
		seed += 7
	add_location("village_square", Vector3(SQUARE.x, 0, SQUARE.y), 16.0, _v(SQUARE + Vector2(3, 3)), "a cobbled square of stone-and-timber houses round a well")


func _well() -> void:
	var c := _v(SQUARE)
	var sb := StoneBuilder.new(height, 171)
	for i in 14:
		var a := TAU * i / 14.0
		sb.block(Transform3D(Basis(Vector3.UP, -a), c + Vector3(cos(a) * 1.25, 0.25, sin(a) * 1.25)), Vector3(0.62, 0.5, 0.36), 0.15, 0.04)
		sb.block(Transform3D(Basis(Vector3.UP, -a + 0.22), c + Vector3(cos(a + 0.22) * 1.25, 0.72, sin(a + 0.22) * 1.25)), Vector3(0.6, 0.44, 0.36), 0.35, 0.04)
	sb.finish(self, stone, "Well")
	Kit.mesh_node(self, Kit.lathe([Vector2(0.0, 0.3), Vector2(1.05, 0.3)], 24), Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.05, 0.1, 0.12), "deep": Color(0.01, 0.02, 0.03)}), Kit.xf(c), false)
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.45
	cyl.height = 1.0
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = c + Vector3(0, 0.5, 0)
	body.add_child(cs)
	add_child(body)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(0.18, 2.3, 0.18), Kit.xf(c + Vector3(sx * 1.15, 2.05, 0)), m.timber, false, 0.02)
	Kit.mesh_node(self, Kit.gable_roof(2.8, 1.8, 0.7, 0.2, 0.08), m.roof, Kit.xf(c + Vector3(0, 3.1, 0), PI * 0.5))
	Kit.mesh_node(self, Kit.lathe([Vector2(0.08, 0), Vector2(0.08, 2.4)], 8), m.timber, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c + Vector3(1.2, 2.55, 0)))
	Kit.place_prop_all(self, "wooden_bucket_01", Kit.xf(c + Vector3(0.6, 0.95, 0.4), 0.4, Vector3.ONE * 1.2))
	add_poi("village_well", c, "Stone well at the heart of the square", "village_square", 2.4)


# ------------------------------------------------------------------ market
func _stall(pos: Vector3, yaw: float, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var root := Node3D.new()
	root.transform = Kit.xf(pos, yaw)
	add_child(root)
	for c in [Vector2(-1.4, -0.8), Vector2(1.4, -0.8), Vector2(-1.4, 0.8), Vector2(1.4, 0.8)]:
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.12, 2.5 if c.y < 0 else 2.1, 0.12), 0.015), m.timber, Kit.xf(Vector3(c.x, (2.5 if c.y < 0 else 2.1) * 0.5, c.y)))
	Kit.block(root, Vector3(3.0, 0.9, 1.0), Kit.xf(Vector3(0, 0.45, 0.35)), Kit.tri("wood_table_001", "1k", 0.9, 0.0, Color(0.75, 0.6, 0.48)), true, 0.02)
	var cloth := Kit.uvmat("fabric_pattern_05", "1k", Vector2(2, 2), [Color(0.75, 0.25, 0.2), Color(0.25, 0.4, 0.62), Color(0.8, 0.65, 0.3), Color(0.4, 0.55, 0.35)][seed % 4], true)
	var canopy := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(3.4, 2.1)
	canopy.mesh = q
	canopy.material_override = cloth
	canopy.transform = Transform3D(Basis(Vector3.RIGHT, 0.19), Vector3(0, 2.35, 0.05))
	root.add_child(canopy)
	for i in 4:
		var x := -1.1 + i * 0.75
		match (seed + i) % 4:
			0: Kit.place_prop_all(root, "wooden_crate_01", Kit.xf(Vector3(x, 0.9, 0.35), r.randf_range(-0.2, 0.2), Vector3.ONE * 0.8))
			1: Kit.mesh_node(root, Kit.prop("wicker_basket_01"), null, Kit.xf(Vector3(x, 0.9, 0.35), r.randf() * TAU, Vector3.ONE * 1.4))
			2: Kit.mesh_node(root, Kit.prop("ceramic_vase_01"), null, Kit.xf(Vector3(x, 0.9, 0.4), r.randf() * TAU))
			3: Kit.mesh_node(root, Kit.prop("brass_vase_01"), null, Kit.xf(Vector3(x, 0.9, 0.4), r.randf() * TAU, Vector3.ONE * 0.6))
	Kit.place_prop_all(root, "wooden_barrels_01", Kit.xf(Vector3(2.1, 0, 0.3), r.randf() * TAU, Vector3.ONE * 0.75))


func _market_stalls() -> void:
	var dir := (MARKET_B - MARKET_A).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	for i in 5:
		var p := MARKET_A + dir * (4.0 + i * 5.6)
		for side: float in [-1.0, 1.0]:
			var q := p + nrm * side * 4.4
			_stall(_v(q), atan2(-nrm.x * side, -nrm.y * side), i * 2 + int(side > 0))
	var mid := (MARKET_A + MARKET_B) * 0.5
	add_location("lantern_market", Vector3(mid.x, 0, mid.y), 14.0, _v(mid + Vector2(-4, 4)), "a market lane of stalls under strings of lanterns")


func _market_lights() -> void:
	var dir := (MARKET_B - MARKET_A).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	bulb.radial_segments = 8
	bulb.rings = 4
	var xs := []
	for i in 6:
		var p0 := MARKET_A + dir * (1.5 + i * 5.6)
		var l := p0 + nrm * 3.4
		var r := p0 - nrm * 3.4
		var yl := height(l.x, l.y)
		Kit.block(self, Vector3(0.12, 4.2, 0.12), Kit.xf(Vector3(l.x, yl + 2.1, l.y)), m.timber, true, 0.02)
		Kit.block(self, Vector3(0.12, 4.2, 0.12), Kit.xf(Vector3(r.x, height(r.x, r.y) + 2.1, r.y)), m.timber, true, 0.02)
		for k in 13:
			var t := k / 12.0
			var pp := l.lerp(r, t)
			xs.append(Transform3D(Basis.IDENTITY, Vector3(pp.x, yl + 4.0 - sin(t * PI) * 0.8, pp.y)))
		if i % 2 == 0:
			var c := (l + r) * 0.5
			night_only(Kit.omni(self, Vector3(c.x, yl + 3.4, c.y), Color(1.0, 0.7, 0.4), 1.2, 9.0))
	Kit.multimesh(self, bulb, xs, 80.0, false, Kit.emissive(Color(1.0, 0.72, 0.4), 5.0, true))


# ------------------------------------------------------------------ workshop
func _workshop() -> void:
	var c := _v(WORKSHOP)
	var yaw := atan2(-WORKSHOP.x, -WORKSHOP.y)
	var root := Node3D.new()
	root.transform = Kit.xf(c, yaw)
	add_child(root)
	var sb := StoneBuilder.new(height, 181)
	var xf := root.transform
	# coursed rubble at a building's scale (courses ~0.26 m), the same masonry as the houses
	sb.wall(xf * Vector3(-4.0, 0, -3.0), xf * Vector3(4.0, 0, -3.0), 3.4, 0.45, 0.0, 0.26, 0.0, c.y)
	sb.wall(xf * Vector3(-4.0, 0, -3.0), xf * Vector3(-4.0, 0, 3.0), 3.4, 0.45, 0.0, 0.26, 0.0, c.y)
	sb.wall(xf * Vector3(4.0, 0, -3.0), xf * Vector3(4.0, 0, 3.0), 3.4, 0.45, 0.0, 0.26, 0.0, c.y)
	sb.finish(self, stone, "WorkshopWalls")
	Kit.block(root, Vector3(8.4, 0.25, 6.4), Kit.xf(Vector3(0, 0.05, 0)), Kit.tri("monastery_stone_floor", "2k", 0.5, 0.0, Color(0.8, 0.78, 0.74)), true, 0.03)   # worn flags, not moss
	for x in [-2.0, 2.0]:
		Kit.block(root, Vector3(0.22, 3.6, 0.22), Kit.xf(Vector3(x, 1.8, 3.0)), m.timber, true, 0.02)
	Kit.mesh_node(root, Kit.box_mesh(Vector3(8.8, 0.25, 0.25), 0.02), m.timber, Kit.xf(Vector3(0, 3.55, 3.0)))
	Kit.mesh_node(root, Kit.gable_roof(8.4, 6.4, 2.2, 0.5, 0.14), m.roof, Kit.xf(Vector3(0, 3.7, 0)))
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(root, Kit.gable_end(6.4, 2.2, 0.2), m.plaster, Kit.xf(Vector3(sx * 4.0, 3.7, 0)))
	var wood := Kit.tri("wood_table_001", "1k", 0.9, 0.0, Color(0.72, 0.58, 0.45))
	Kit.block(root, Vector3(3.2, 0.1, 1.0), Kit.xf(Vector3(-1.5, 0.95, -2.2)), wood, false, 0.02)
	for p in [Vector2(-3.0, -2.6), Vector2(0.0, -2.6), Vector2(-3.0, -1.8), Vector2(0.0, -1.8)]:
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.1, 0.9, 0.1), 0.01), wood, Kit.xf(Vector3(p.x, 0.45, p.y)))
	Kit.static_box(root, Vector3(3.2, 1.0, 1.0), Kit.xf(Vector3(-1.5, 0.5, -2.2)))
	Kit.place_prop_all(root, "bench_vice_01", Kit.xf(Vector3(-2.6, 1.0, -2.0), 0.0, Vector3.ONE * 1.2))
	Kit.mesh_node(root, Kit.prop("cross_pein_hammer"), null, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-1.6, 1.03, -2.0)))
	Kit.mesh_node(root, Kit.prop("handsaw_wood"), null, Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, 0.3), Vector3(-0.9, 1.02, -2.3)))
	Kit.mesh_node(root, Kit.prop("hand_plane_no4"), null, Kit.xf(Vector3(-0.4, 1.0, -2.0), 0.6))
	Kit.mesh_node(root, Kit.prop("hatchet"), null, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-2.0, 1.03, -2.5)))
	Kit.block(root, Vector3(2.0, 0.9, 0.9), Kit.xf(Vector3(2.4, 0.45, -2.2)), wood, true, 0.02)
	Kit.place_prop_all(root, "chemistry_set", Kit.xf(Vector3(1.95, 0.9, -2.25), 0.0, Vector3.ONE * 1.3))
	Kit.omni(root, Vector3(2.4, 2.0, -1.6), Color(0.5, 1.0, 0.7), 0.6, 4.0)
	Kit.place_prop(root, "stone_fire_pit", Kit.xf(Vector3(2.6, 0.18, 0.8)), "", true)
	Kit.omni(root, Vector3(2.6, 0.9, 0.8), Color(1.0, 0.56, 0.28), 0.7, 5.0)
	Kit.place_prop_all(root, "wooden_barrels_01", Kit.xf(Vector3(5.5, 0, 1.8), 0.4, Vector3.ONE * 0.9), true)
	add_location("craft_workshop", Vector3(c.x, 0, c.z), 10.0, c + Basis(Vector3.UP, yaw) * Vector3(0, 0.2, 4.4), "an open craft workshop with a forge and an alchemy bench")
	add_interactable(Interactable.make("workbench_craft", "Carve a wand core at the workbench", "craft", "craft_workshop",
		c + Basis(Vector3.UP, yaw) * Vector3(-1.5, 0.2, -1.2), {"items": {"wand_core": 1}, "skills": {"crafting": 0.2}}, "", 5.0))
	interactables["workbench_craft"].requires = {"items": {"crystal_shard": 1}}
	interactables["workbench_craft"].radius = 2.4
	var brew := Interactable.make("alchemy_brew", "Brew a mana tonic at the alchemy bench", "craft", "craft_workshop",
		c + Basis(Vector3.UP, yaw) * Vector3(2.4, 0.2, -1.2), {"items": {"mana_tonic": 1}, "knowledge": {"recipe:mana_tonic": 1}}, "", 4.0)
	brew.requires = {"items": {"luminous_water": 1}}
	add_interactable(brew).radius = 2.2
	add_interactable(Interactable.make("workshop_inspect_tools", "Inspect the craftsman's tools", "inspect", "craft_workshop",
		c + Basis(Vector3.UP, yaw) * Vector3(-0.5, 0.2, -1.0), {"knowledge": {"lore:village_crafts": 1}}, "look_around", 3.0)).radius = 2.4


func _street_lamps() -> void:
	for p in [Vector2(-10, -4), Vector2(10, 4), Vector2(-4, 11), Vector2(4, -11), Vector2(-30, 4.5), Vector2(-50, -3.5), Vector2(32, 9.5), Vector2(4.5, -34), Vector2(-3.5, -52), Vector2(54, 12)]:
		lantern_post(_v(p), m, 1.1)


func _gardens() -> void:
	for p in [Vector2(-12, 14), Vector2(13, -13), Vector2(14, 6), Vector2(-14, -7)]:
		Kit.place_prop_all(self, "planter_box_01", Kit.xf(_v(p), atan2(-p.x, -p.y), Vector3.ONE * 1.4))


func links() -> void:
	edge_gate("river_valley", GATE_RIVER)
	edge_gate("highland_path", GATE_HIGHLAND)
	edge_gate("crystal_caverns", GATE_CAVES)
	# the stair up the observatory hill (north-west)
	var base := _v(STAIR)
	var top := stairs(base, atan2(1.0, 1.0) + PI, 3.0, 9, 0.2, 0.45, stone)
	add_gate("observatory_hill", top, base + Vector3(2.2, 0.05, 2.2), atan2(-1.0, -1.0) + PI, 1.6)
	Kit.block(self, Vector3(3.6, 0.3, 3.6), Kit.xf(top + Vector3(0, -0.15, 0)), stone, true, 0.03)
	add_interactable(Interactable.make("well_draw_water", "Draw water from the well", "collect", "village_square",
		_v(SQUARE + Vector2(1.6, 0)), {"items": {"well_water": 1}}, "", 3.0)).radius = 2.4
	var mid := (MARKET_A + MARKET_B) * 0.5
	add_interactable(Interactable.make("market_buy_herbs", "Trade for dried herbs at the market", "trade", "lantern_market",
		_v(mid + Vector2(-4, 4)), {"items": {"herbs": 1}}, "wave", 3.0)).radius = 3.0
	var nb := SQUARE + Vector2(-5, 6)
	add_interactable(Interactable.make("notice_board", "Read the village notice board", "read", "village_square",
		_v(nb), {"knowledge": {"news:village": 1}, "discover": ["village_observatory", "mountain_path", "crystal_entrance"]}, "look_around", 3.0)).radius = 2.4
	Kit.block(self, Vector3(1.6, 1.1, 0.12), Kit.xf(_v(nb + Vector2(0, 0.6), 1.4), PI * 0.2), Kit.tri("wood_table_001", "1k", 1.0, 0.0, Color(0.6, 0.5, 0.4)), true, 0.02)
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.12, 1.9, 0.12), 0.01), m.timber, Kit.xf(_v(nb + Vector2(-0.6, 0.65), 0.95)))
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.12, 1.9, 0.12), 0.01), m.timber, Kit.xf(_v(nb + Vector2(0.6, 0.55), 0.95)))
	print("[village] houses ", houses.stats if houses else {})


func showcase_shots(loc: String) -> Array:
	var mid := (MARKET_A + MARKET_B) * 0.5
	match loc:
		"lantern_market":
			return [[_v(MARKET_A + Vector2(-2, 3), 2.0), _v(MARKET_B, 2.5), 58.0]]
		"craft_workshop":
			return [[_v(WORKSHOP + Vector2(-6, -6), 2.2), _v(WORKSHOP, 1.0), 55.0]]
	return [[_v(Vector2(-12, 12), 2.4), _v(Vector2(6, -8), 3.0), 58.0], [_v(Vector2(-40, 1), 2.0), _v(SQUARE, 3.5), 50.0]]
