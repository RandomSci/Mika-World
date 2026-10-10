extends KitArea
## C1 Village Square + C2 Lantern Market + C3 Craft Workshop (Fantasy Village).
## Timber-framed, slate-roofed houses around a cobbled square with a stone well; a market lane of
## fabric-canopied stalls under strings of lanterns; an open workshop with forge and alchemy bench.

const SQUARE := Vector3(0, 0, 0)
const MARKET := Vector3(22, 0, -18)
const WORKSHOP := Vector3(17, 0, 17)
const SKY_DAY := "res://assets/polyhaven/hdris/kloppenheim_06_puresky/kloppenheim_06_puresky_2k.hdr"

var m: Dictionary
var stone: ShaderMaterial


static func resources() -> Array:
	return textures(["castle_wall_slates", "plastered_wall_02", "dark_wooden_planks", "roof_slates_02", "forrest_ground_01", "fabric_pattern_05", "wood_table_001"]) + \
		textures(["cobblestone_floor_08", "leafy_grass"], "2k") + \
		models(["Lantern_01", "wooden_crate_01", "wicker_basket_01", "ceramic_vase_01", "brass_vase_01", "Barrel_01", "wooden_barrels_01", "wooden_bucket_01",
			"bench_vice_01", "cross_pein_hammer", "handsaw_wood", "hand_plane_no4", "hatchet", "chemistry_set", "stone_fire_pit", "folding_wooden_stool", "potted_plant_01", "planter_box_01", "shrub_02"]) + \
		[SKY_DAY, TREE_NEAR, TREE_FAR]


func env_preset() -> Dictionary:
	return {"sky_day": SKY_DAY,
		"day": {"sun_rot": Vector3(-22, -120, 0), "sun_energy": 2.1, "sun_color": Color(1.0, 0.82, 0.64), "fog": 0.0025, "fog_color": Color(0.58, 0.62, 0.68), "vol_fog": 0.004, "exposure": 0.95, "bg_energy": 0.8},
		"night": {"fog": 0.006, "fog_color": Color(0.06, 0.07, 0.1), "vol_fog": 0.012, "vol_albedo": Color(0.9, 0.8, 0.7), "ambient": 1.3, "exposure": 1.3},
		"vista": {"mountains": true, "ridge_height": 380.0, "ridge_seed": 12, "haze": Color(0.55, 0.6, 0.68), "snow_line": 280.0, "green": Color(0.17, 0.24, 0.15)},
	}


# ------------------------------------------------------------------ ground
func _street_dist(p: Vector2) -> float:
	var segs := [[Vector2(-46, 2), Vector2(0, 0)], [Vector2(0, 0), Vector2(46, 8)], [Vector2(0, 0), Vector2(0, -46)],
		[Vector2(4, -4), Vector2(30, -26)], [Vector2(6, 6), Vector2(17, 13)], [Vector2(-4, -4), Vector2(-20, -24)]]
	var best := 1e9
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return minf(best, p.length() - 13.0)


func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var town := 1.0 - smoothstep(30.0, 46.0, p.length())
	return (sin(x * 0.05) * 0.6 + cos(z * 0.06) * 0.5) * (1.0 - town * 0.85) + smoothstep(36.0, 52.0, p.length()) * 6.0 + z * -0.015


func build_steps() -> Array:
	return [_ground, _houses_square, _houses_streets, _well, _market_stalls, _market_lights, _workshop, _street_lamps, _greenery, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-48, -4, -48), Vector3(96, 16, 96))
	m = village_mats()
	stone = m.stone
	magic_receivers = [stone]
	var mat := Kit.terrain_mat("leafy_grass", "forrest_ground_01", "cobblestone_floor_08", Color(0.78, 0.88, 0.66), Color(0.5, 0.55, 0.42), "2k")
	mat.set_shader_parameter("path_albedo", load("res://assets/polyhaven/textures/cobblestone_floor_08/cobblestone_floor_08_diff_2k.jpg"))
	mat.set_shader_parameter("path_normal", load("res://assets/polyhaven/textures/cobblestone_floor_08/cobblestone_floor_08_nor_gl_2k.jpg"))
	mat.set_shader_parameter("path_rough", load("res://assets/polyhaven/textures/cobblestone_floor_08/cobblestone_floor_08_rough_2k.jpg"))
	mat.set_shader_parameter("path_tiling", 0.45)
	Kit.terrain(self, 110.0, 1.0, height, func(x, z):
		var d := _street_dist(Vector2(x, z))
		return Color(1.0 - smoothstep(2.6, 3.6, d), smoothstep(30.0, 40.0, Vector2(x, z).length()) * 0.7, 0.0), mat)
	boundary_circle(Vector3.ZERO, 47.0)


# ------------------------------------------------------------------ houses
func _h(p: Vector2, facing: Vector2, w: float, d: float, seed: int, floors := 2) -> void:
	var yaw := atan2(facing.x, facing.y)  # house front (+Z local) faces `facing`
	var y := height(p.x, p.y) - 0.15
	house(Vector3(p.x, y, p.y), yaw, w, d, m, seed, floors)


func _houses_square() -> void:
	# ring of houses around the square, fronts facing the well
	var spots := [[-16, -9, 7.0, 6.5], [-17, 6, 6.5, 6.0], [-8, -17, 7.5, 6.0], [10, -16, 6.0, 6.0], [18, -4, 7.0, 6.5], [17, 10, 6.0, 6.0], [-6, 17, 7.0, 6.0], [-15, 17.5, 5.5, 6.0]]
	for i in spots.size():
		var s: Array = spots[i]
		var p := Vector2(s[0], s[1])
		_h(p, -p.normalized(), s[2], s[3], 100 + i, 2 if i % 3 else 1 + 1)
	add_location("village_square", SQUARE, 15.0, Vector3(3.0, height(3, 3), 3.0))


func _houses_streets() -> void:
	# west road
	for i in 3:
		var x := -26.0 - i * 8.0
		_h(Vector2(x, -7.5), Vector2(0, 1), 6.5, 5.5, 200 + i, 2 - i % 2)
		_h(Vector2(x - 3.0, 9.0), Vector2(0, -1), 6.0, 5.5, 210 + i, 2)
	# north road
	for i in 2:
		_h(Vector2(-8.0, -26.0 - i * 9.0), Vector2(1, 0), 6.0, 6.0, 220 + i, 2)
		_h(Vector2(8.5, -30.0 - i * 9.0), Vector2(-1, 0), 6.5, 6.0, 230 + i, 1 + i)


func _well() -> void:
	var c := Vector3(SQUARE.x, height(0, 0), SQUARE.z)
	Kit.mesh_node(self, Kit.lathe([Vector2(1.25, 0), Vector2(1.3, 0.75), Vector2(1.38, 0.82), Vector2(1.38, 0.95), Vector2(1.0, 0.95), Vector2(1.0, 0.1)], 24, true, false), stone, Kit.xf(c))
	Kit.mesh_node(self, Kit.lathe([Vector2(0.0, 0.3), Vector2(1.0, 0.3)], 24), Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.05, 0.1, 0.12), "deep": Color(0.01, 0.02, 0.03)}), Kit.xf(c), false)
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
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
	# goods
	for i in 4:
		var x := -1.1 + i * 0.75
		match (seed + i) % 4:
			0: Kit.place_prop_all(root, "wooden_crate_01", Kit.xf(Vector3(x, 0.9, 0.35), r.randf_range(-0.2, 0.2), Vector3.ONE * 0.8))
			1: Kit.mesh_node(root, Kit.prop("wicker_basket_01"), null, Kit.xf(Vector3(x, 0.9, 0.35), r.randf() * TAU, Vector3.ONE * 1.4))
			2: Kit.mesh_node(root, Kit.prop("ceramic_vase_01"), null, Kit.xf(Vector3(x, 0.9, 0.4), r.randf() * TAU))
			3: Kit.mesh_node(root, Kit.prop("brass_vase_01"), null, Kit.xf(Vector3(x, 0.9, 0.4), r.randf() * TAU, Vector3.ONE * 0.6))
	Kit.mesh_node(root, Kit.prop("Barrel_01"), null, Kit.xf(Vector3(1.9, 0, 0.3), r.randf() * TAU))


func _market_stalls() -> void:
	var a := Vector2(6, -6)
	var b := Vector2(30, -27)
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	for i in 5:
		var p := a + dir * (4.0 + i * 5.2)
		for side: float in [-1.0, 1.0]:
			var q := p + nrm * side * 4.2
			_stall(Vector3(q.x, height(q.x, q.y), q.y), atan2(-nrm.x * side, -nrm.y * side), i * 2 + int(side > 0))
	add_location("lantern_market", MARKET, 12.0, Vector3(MARKET.x - 4, height(MARKET.x - 4, MARKET.z + 4), MARKET.z + 4))


func _market_lights() -> void:
	var a := Vector2(6, -6)
	var b := Vector2(30, -27)
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	bulb.radial_segments = 8
	bulb.rings = 4
	var xs := []
	for i in 6:
		var p0 := a + dir * (1.5 + i * 5.2)
		var l := p0 + nrm * 3.3
		var r := p0 - nrm * 3.3
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
	var c := Vector3(WORKSHOP.x, height(WORKSHOP.x, WORKSHOP.z), WORKSHOP.z)
	var yaw := atan2(-WORKSHOP.x, -WORKSHOP.z)  # open front faces the square
	var root := Node3D.new()
	root.transform = Kit.xf(c, yaw)
	add_child(root)
	Kit.block(root, Vector3(8.4, 0.25, 6.4), Kit.xf(Vector3(0, 0.05, 0)), stone, true, 0.03)
	Kit.block(root, Vector3(8.4, 3.6, 0.4), Kit.xf(Vector3(0, 1.8, -3.0)), m.plaster, true, 0.03)
	for sx: float in [-1.0, 1.0]:
		Kit.block(root, Vector3(0.4, 3.6, 6.2), Kit.xf(Vector3(sx * 4.0, 1.8, 0)), m.stone, true, 0.03)
	for x in [-2.0, 2.0]:
		Kit.block(root, Vector3(0.22, 3.6, 0.22), Kit.xf(Vector3(x, 1.8, 3.0)), m.timber, true, 0.02)
	Kit.mesh_node(root, Kit.box_mesh(Vector3(8.8, 0.25, 0.25), 0.02), m.timber, Kit.xf(Vector3(0, 3.55, 3.0)))
	Kit.mesh_node(root, Kit.gable_roof(8.4, 6.4, 2.2, 0.5, 0.14), m.roof, Kit.xf(Vector3(0, 3.7, 0)))
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(root, Kit.gable_end(6.4, 2.2, 0.2), m.plaster, Kit.xf(Vector3(sx * 4.0, 3.7, 0)))
	# workbench with real tools
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
	# alchemy bench
	Kit.block(root, Vector3(2.0, 0.9, 0.9), Kit.xf(Vector3(2.4, 0.45, -2.2)), wood, true, 0.02)
	Kit.place_prop_all(root, "chemistry_set", Kit.xf(Vector3(1.95, 0.9, -2.25), 0.0, Vector3.ONE * 1.3))
	Kit.omni(root, Vector3(2.4, 2.0, -1.6), Color(0.5, 1.0, 0.7), 0.6, 4.0)
	# forge pit + barrels
	Kit.place_prop(root, "stone_fire_pit", Kit.xf(Vector3(2.6, 0.18, 0.8)), "", true)
	Kit.omni(root, Vector3(2.6, 0.9, 0.8), Color(1.0, 0.5, 0.2), 1.4, 5.0)
	Kit.place_prop_all(root, "wooden_barrels_01", Kit.xf(Vector3(5.5, 0, 1.8), 0.4, Vector3.ONE * 0.9), true)
	add_location("craft_workshop", WORKSHOP, 9.0, c + Basis(Vector3.UP, yaw) * Vector3(0, 0.2, 4.4))
	add_interactable(Interactable.make("workbench_craft", "Carve a wand core at the workbench", "craft", "craft_workshop",
		c + Basis(Vector3.UP, yaw) * Vector3(-1.5, 0.2, -1.2), {"items": {"wand_core": 1}, "skills": {"crafting": 0.2}}, "", 5.0))
	world_req(interactables["workbench_craft"], {"items": {"crystal_shard": 1}})
	var brew := Interactable.make("alchemy_brew", "Brew a mana tonic at the alchemy bench", "craft", "craft_workshop",
		c + Basis(Vector3.UP, yaw) * Vector3(2.4, 0.2, -1.2), {"items": {"mana_tonic": 1}, "knowledge": {"recipe:mana_tonic": 1}}, "", 4.0)
	brew.requires = {"items": {"luminous_water": 1}}
	add_interactable(brew).radius = 2.2
	add_interactable(Interactable.make("workshop_inspect_tools", "Inspect the craftsman's tools", "inspect", "craft_workshop",
		c + Basis(Vector3.UP, yaw) * Vector3(-0.5, 0.2, -1.0), {"knowledge": {"lore:village_crafts": 1}}, "look_around", 3.0)).radius = 2.4


func world_req(it: Interactable, req: Dictionary) -> void:
	it.requires = req
	it.radius = 2.4


func _street_lamps() -> void:
	for p in [Vector2(-9, -3), Vector2(9, 3), Vector2(-3, 10), Vector2(3, -10), Vector2(-24, 3.5), Vector2(-36, -2.5), Vector2(24, 7), Vector2(3.5, -26), Vector2(-3.5, -38)]:
		lantern_post(Vector3(p.x, height(p.x, p.y), p.y), m, 1.1)


func _greenery() -> void:
	for p in [Vector2(-30, 24), Vector2(30, 26), Vector2(-34, -24), Vector2(34, -36), Vector2(-40, 10), Vector2(40, -8)]:
		tree(Vector3(p.x, height(p.x, p.y) - 0.2, p.y), rng.randf_range(1.0, 1.4), rng.randf() * TAU, true)
	for p in [Vector2(-11, 13), Vector2(12, -12), Vector2(13, 5), Vector2(-13, -6)]:
		Kit.place_prop_all(self, "planter_box_01", Kit.xf(Vector3(p.x, height(p.x, p.y), p.y), atan2(-p.x, -p.y), Vector3.ONE * 1.4))
	var h := height
	var ok := func(p: Vector2) -> bool: return _street_dist(p) > 4.0 and p.length() > 24.0
	for part in ["shrub_02_a", "shrub_02_b", "shrub_02_d"]:
		scatter("shrub_02", part, 18, Vector2.ZERO, 24.0, 44.0, 0.8, 1.4, h, ok, 70.0)


func _links() -> void:
	add_gate("river_valley", Vector3(-45.5, height(-45.5, 2), 2.0), Vector3(-40.0, height(-40, 1.8) + 0.05, 1.8), PI * 0.5, 2.6)
	add_gate("highland_path", Vector3(0.0, height(0, -45.5), -45.5), Vector3(0.0, height(0, -40) + 0.05, -40.0), PI, 2.6)
	add_gate("crystal_caverns", Vector3(45.5, height(45.5, 8), 8.0), Vector3(40.0, height(40, 7.2) + 0.05, 7.2), -PI * 0.5, 2.6)
	# hill stairway up to the observatory (north-west)
	var base := Vector3(-20.0, height(-20, -24), -24.0)
	var top := stairs(base, atan2(1.0, 1.0) + PI, 3.0, 9, 0.2, 0.45, stone)
	add_gate("observatory_hill", top + Vector3(0, 0.0, 0), base + Vector3(2.2, 0.05, 2.2), atan2(-1.0, -1.0) + PI, 1.6)
	Kit.block(self, Vector3(3.6, 0.3, 3.6), Kit.xf(top + Vector3(0, -0.15, 0)), stone, true, 0.03)
	add_interactable(Interactable.make("well_draw_water", "Draw water from the well", "collect", "village_square",
		Vector3(1.4, height(1.4, 0), 0), {"items": {"well_water": 1}}, "", 3.0)).radius = 2.4
	add_interactable(Interactable.make("market_buy_herbs", "Trade for dried herbs at the market", "trade", "lantern_market",
		Vector3(MARKET.x - 4, height(MARKET.x - 4, MARKET.z + 4), MARKET.z + 4), {"items": {"herbs": 1}}, "wave", 3.0)).radius = 3.0
	add_interactable(Interactable.make("notice_board", "Read the village notice board", "read", "village_square",
		Vector3(-4.0, height(-4, 4), 4.0), {"knowledge": {"news:village": 1}, "discover": ["village_observatory", "mountain_path", "crystal_entrance"]}, "look_around", 3.0)).radius = 2.4
	Kit.block(self, Vector3(1.6, 1.1, 0.12), Kit.xf(Vector3(-4.0, height(-4, 4) + 1.4, 4.6), PI * 0.2), Kit.tri("wood_table_001", "1k", 1.0, 0.0, Color(0.6, 0.5, 0.4)), true, 0.02)
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.12, 1.9, 0.12), 0.01), m.timber, Kit.xf(Vector3(-4.6, height(-4, 4) + 0.95, 4.65)))
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.12, 1.9, 0.12), 0.01), m.timber, Kit.xf(Vector3(-3.4, height(-4, 4) + 0.95, 4.55)))


func showcase_shots(loc: String) -> Array:
	match loc:
		"lantern_market":
			return [[Vector3(4, 2.0, -3), Vector3(26, 2.5, -24), 58.0]]
		"craft_workshop":
			return [[WORKSHOP + Vector3(-6, 2.2, -6), WORKSHOP + Vector3(0, 1.0, 0), 55.0]]
	return [[Vector3(-12, 2.4, 12), Vector3(6, 3.0, -8), 58.0], [Vector3(-38, 2.0, 1), Vector3(0, 3.5, 0), 50.0]]
