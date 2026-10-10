extends KitArea
## D1 Crystal Entrance + D2 Luminous Crystal Hall (Crystal Caverns).
## A rocky quarry ravine narrows to a cave mouth framed by boulders; inside, a high chamber of
## giant luminous crystal formations in cyan and violet, lit almost entirely by the crystals.

const HALL := Vector3(0, 0, -16)
const MOUTH_Z := 6.0

var rock: ShaderMaterial
var cave_rock: ShaderMaterial
var crystal_cols := [Color(0.25, 0.85, 1.0), Color(0.55, 0.45, 1.0), Color(0.3, 1.0, 0.85)]


static func resources() -> Array:
	return textures(["rock_wall_10", "rocky_terrain_02", "forrest_ground_01", "stony_dirt_path"]) + textures(["cliff_side"], "2k") + \
		models(["namaqualand_cliff_01", "boulder_01", "rock_moss_set_02", "moon_rock_01", "moon_rock_03", "moon_rock_05", "wooden_crate_01", "Lantern_01", "fern_02"]) + \
		["res://assets/polyhaven/hdris/alps_field/alps_field_2k.hdr"]


func env_preset() -> Dictionary:
	return {"sky_day": "res://assets/polyhaven/hdris/alps_field/alps_field_2k.hdr",
		"day": {"sun_rot": Vector3(-35, 160, 0), "sun_energy": 2.2, "ambient": 0.35, "fog": 0.01, "fog_color": Color(0.1, 0.16, 0.2), "vol_fog": 0.02, "vol_albedo": Color(0.7, 0.85, 1.0), "exposure": 1.05, "bg_energy": 0.8},
		"night": {"ambient": 0.3, "fog": 0.012, "fog_color": Color(0.03, 0.05, 0.08), "vol_fog": 0.02, "exposure": 1.3},
		"vista": {"mountains": false, "ridge_height": 340.0, "ridge_seed": 21, "haze": Color(0.55, 0.62, 0.7)}}


func height(x: float, z: float) -> float:
	if z < MOUTH_Z:
		return sin(x * 0.3) * 0.25 + cos(z * 0.23) * 0.2 - smoothstep(MOUTH_Z, -10.0, z) * 1.2
	var ravine := smoothstep(6.0, 16.0, absf(x)) * (6.0 + (z - MOUTH_Z) * 0.15)
	return ravine + sin(z * 0.15) * 0.3 + z * 0.02


func build_steps() -> Array:
	return [_ground, _shell, _mouth, _ravine, _crystals_entrance, _crystal_hall, _hall_detail, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-24, -4, -40), Vector3(48, 20, 84))
	rock = Kit.tri("cliff_side", "2k", 0.14, 0.15)
	cave_rock = Kit.tri("rock_wall_10", "1k", 0.25, 0.0, Color(0.62, 0.66, 0.72), {"wetness": 0.45, "grime_height": 0.0, "two_sided": true})
	magic_receivers = [rock, cave_rock]
	var mat := Kit.terrain_mat("rocky_terrain_02", "rock_wall_10", "stony_dirt_path", Color(0.9, 0.9, 0.86), Color(0.45, 0.48, 0.52))
	Kit.terrain(self, 90.0, 1.0, height, func(x, z):
		return Color(1.0 - smoothstep(1.5, 3.0, absf(x)) if z > MOUTH_Z else 0.0, 1.0 if z < MOUTH_Z else smoothstep(8.0, 14.0, absf(x)), 0.0), mat)
	boundary_box(Vector3(0, 0, 4), Vector3(40, 16, 86))


func _shell() -> void:
	var c := HALL + Vector3(0, 3.0, 0)
	var radii := Vector3(17.0, 12.0, 21.0)
	var shell := Kit.cave_shell(radii, 9, 0.25, func(d: Vector3) -> bool:
		# open the mouth toward +Z near the floor
		return not (d.z > 0.88 and d.y < 0.35 and absf(d.x) < 0.42), 44, 24)
	var mi := Kit.mesh_node(self, shell, cave_rock, Kit.xf(c))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	Kit.trimesh_collide(mi)


func _mouth() -> void:
	# boulder frame around the opening + overhanging lintel rock
	for spec in [[Vector3(-4.8, 0, MOUTH_Z - 1), 2.8], [Vector3(4.9, 0, MOUTH_Z - 0.6), 2.6], [Vector3(-6.5, 2.5, MOUTH_Z - 2), 2.2], [Vector3(6.8, 2.8, MOUTH_Z - 2.2), 2.4]]:
		var p: Vector3 = spec[0]
		var mi := Kit.mesh_node(self, Kit.rock_mesh(spec[1], int(p.x * 10), 0.35, Vector3(1.0, 1.5, 1.0), 2), rock, Kit.xf(Vector3(p.x, height(p.x, p.z) + p.y, p.z), p.x))
		Kit.convex_collide(mi)
	Kit.mesh_node(self, Kit.rock_mesh(1.0, 41, 0.3, Vector3(8.0, 2.4, 3.2), 2), rock, Kit.xf(Vector3(0, 6.3, MOUTH_Z - 1.2)))
	# miner's crates and a lantern at the entrance
	Kit.place_prop_all(self, "wooden_crate_01", Kit.xf(Vector3(3.2, height(3.2, MOUTH_Z + 3), MOUTH_Z + 3), 0.3), true)
	Kit.place_prop_all(self, "wooden_crate_01", Kit.xf(Vector3(3.4, height(3.4, MOUTH_Z + 3) + 0.32, MOUTH_Z + 2.9), -0.2))
	Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(Vector3(3.3, height(3.3, MOUTH_Z + 3) + 0.66, MOUTH_Z + 2.7), 0.0, Vector3.ONE * 1.4))
	Kit.omni(self, Vector3(3.3, height(3.3, MOUTH_Z + 3) + 1.0, MOUTH_Z + 2.7), Color(1.0, 0.68, 0.36), 1.0, 6.0)


func _ravine() -> void:
	for i in 8:
		var z := MOUTH_Z + 6.0 + i * 5.0
		for sx: float in [-1.0, 1.0]:
			var x := sx * rng.randf_range(10.5, 13.0)
			var s := rng.randf_range(1.6, 2.4)
			Kit.place_prop(self, "namaqualand_cliff_01", Kit.xf(Vector3(x, height(x, z) - 1.5, z), (PI * 0.5 if sx > 0 else -PI * 0.5) + rng.randf_range(-0.3, 0.3), Vector3(s, s * 1.5, s)), "", true)
	for i in 10:
		var p := Vector2(rng.randf_range(-7, 7), rng.randf_range(MOUTH_Z + 4, 40))
		if absf(p.x) < 2.0:
			continue
		Kit.place_prop(self, ["moon_rock_01", "moon_rock_03", "moon_rock_05"][i % 3], Kit.xf(Vector3(p.x, height(p.x, p.y) - 0.1, p.y), rng.randf() * TAU, Vector3.ONE * rng.randf_range(1.5, 4.0)), "", true)
	var h := height
	scatter("fern_02", "fern_02_c", 30, Vector2(0, 26), 3.0, 14.0, 0.8, 1.4, h, func(p: Vector2) -> bool: return absf(p.x) > 2.5, 40.0)
	add_location("crystal_entrance", Vector3(0, 0, MOUTH_Z + 6.0), 12.0, Vector3(0.5, height(0.5, MOUTH_Z + 8.0), MOUTH_Z + 8.0))


func _cluster(center: Vector3, count: int, size: float, col: Color, seed: int, up := Vector3.UP) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var mat := Kit.crystal(col, 2.6)
	for i in count:
		var len := size * r.randf_range(0.45, 1.0)
		var tilt := Basis(Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized(), r.randf_range(0.0, 0.7))
		var base_b := Basis.IDENTITY if up == Vector3.UP else Basis(Vector3.RIGHT, PI)
		var off := Vector3(r.randf_range(-0.4, 0.4), 0, r.randf_range(-0.4, 0.4)) * size * 0.4
		Kit.mesh_node(self, Kit.crystal_mesh(len, len * r.randf_range(0.12, 0.2), seed * 10 + i), mat, Transform3D(base_b * tilt, center + off), false)
	if size > 1.5:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = size * 0.35
		cyl.height = size
		cs.shape = cyl
		cs.position = center + Vector3(0, size * 0.5 * (1 if up == Vector3.UP else -1), 0)
		body.add_child(cs)
		add_child(body)


func _crystals_entrance() -> void:
	_cluster(Vector3(-3.2, height(-3.2, 2.0), 2.0), 5, 0.9, crystal_cols[0], 1)
	_cluster(Vector3(3.6, height(3.6, 0.0), 0.0), 6, 1.2, crystal_cols[2], 2)
	Kit.omni(self, Vector3(0, 1.5, 1.0), crystal_cols[0], 1.0, 7.0)


func _crystal_hall() -> void:
	var giants := [[Vector3(-9, 0, -18), 6.0, 0], [Vector3(9.5, 0, -22), 7.5, 1], [Vector3(-4, 0, -30), 5.0, 2], [Vector3(6, 0, -9), 4.0, 0], [Vector3(-11, 0, -8), 3.5, 1], [Vector3(0, 0, -24), 3.0, 0]]
	for i in giants.size():
		var g: Array = giants[i]
		var p: Vector3 = g[0]
		_cluster(Vector3(p.x, height(p.x, p.z) - 0.2, p.z), 7, g[1], crystal_cols[g[2]], 10 + i)
		if i < 4:
			Kit.omni(self, Vector3(p.x, height(p.x, p.z) + g[1] * 0.6, p.z), crystal_cols[g[2]], 2.2, g[1] * 3.0)
	# ceiling crystals hanging down
	for i in 14:
		var a := TAU * i / 14.0
		var p := HALL + Vector3(cos(a) * rng.randf_range(4, 11), 13.5 - rng.randf_range(0, 2.5), sin(a) * rng.randf_range(4, 13))
		_cluster(p, 4, rng.randf_range(0.8, 2.0), crystal_cols[i % 3], 40 + i, Vector3.DOWN)
	# floor scatter of small crystals (instanced)
	var small := Kit.crystal_mesh(0.35, 0.06, 99)
	var xs := []
	for i in 240:
		var p := Vector2(rng.randf_range(-14, 14), rng.randf_range(-34, 2))
		if Vector2(p.x / 15.0, (p.y - HALL.z) / 19.0).length() > 0.95 or absf(p.x) < 1.6:
			continue
		xs.append(Transform3D(Basis(Vector3(rng.randf(), 0, rng.randf()).normalized(), rng.randf_range(0, 0.8)).scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), Vector3(p.x, height(p.x, p.y) - 0.05, p.y)))
	Kit.multimesh(self, small, xs, 45.0, false, Kit.crystal(crystal_cols[0], 1.8))
	add_location("luminous_crystal_hall", HALL, 16.0, HALL + Vector3(1.5, height(1.5, HALL.z + 2), 2.0))


func _hall_detail() -> void:
	# a worn path of flat stones through the hall
	for i in 10:
		var z := MOUTH_Z - 2.0 - i * 3.2
		var mi := Kit.mesh_node(self, Kit.rock_mesh(0.8, 700 + i, 0.15, Vector3(1.3, 0.2, 1.0)), rock, Kit.xf(Vector3(sin(i * 0.7) * 0.8, height(0, z) - 0.08, z), i))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_poi("giant_crystal", Vector3(9.5, height(9.5, -22), -22.0), "Towering violet crystal formation", "luminous_crystal_hall", 4.5)


func _links() -> void:
	add_gate("village", Vector3(0.0, height(0, 42), 42.0), Vector3(0.0, height(0, 36) + 0.05, 36.0), 0.0, 2.6)
	add_gate("deep_caverns", Vector3(0.0, height(0, -34), -34.0), Vector3(0.0, height(0, -29) + 0.05, -29.0), PI, 2.2)
	Kit.mesh_node(self, Kit.box_mesh(Vector3(3.0, 3.6, 0.4), 0.02), Kit.emissive(Color(0.0, 0.0, 0.0), 0.0), Kit.xf(Vector3(0, height(0, -35.5) + 1.8, -35.6)), false)
	add_interactable(Interactable.make("collect_crystal_shard", "Chip a small shard from a crystal cluster", "collect", "luminous_crystal_hall",
		Vector3(6.0, height(6, -9), -9.0), {"items": {"crystal_shard": 1}}, "", 3.0)).radius = 3.0
	add_interactable(Interactable.make("crystal_resonance", "Listen to the crystals' resonance", "study", "luminous_crystal_hall",
		Vector3(-9.0, height(-9, -18), -18.0), {"knowledge": {"lore:crystal_resonance": 1}, "skills": {"arcane_orb": 0.1}}, "spell_casting", 4.2)).radius = 4.5
	add_interactable(Interactable.make("entrance_survey", "Examine the miners' crates at the cave mouth", "inspect", "crystal_entrance",
		Vector3(3.2, height(3.2, MOUTH_Z + 3), MOUTH_Z + 3.0), {"knowledge": {"lore:crystal_miners": 1}}, "look_around", 3.0)).radius = 2.4


func showcase_shots(loc: String) -> Array:
	if loc == "crystal_entrance":
		return [[Vector3(-3, 2.2, 26), Vector3(0, 3.0, MOUTH_Z), 55.0]]
	return [[Vector3(-2, 2.0, 0), Vector3(2, 4.0, -24), 60.0], [Vector3(8, 1.6, -12), Vector3(-6, 5, -24), 60.0]]
