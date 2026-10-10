extends KitArea
## F1 Academy Courtyard + F3 Advanced Magic Arena + F4 Academy Gardens (Grand Academy).
## A monumental paved courtyard framed by a great hall with tall arched windows and round towers,
## an arena with tiered seating around a rune circle, and formal gardens with hedges and a fountain.

const COURT := Vector3(0, 0, 0)
const ARENA := Vector3(44, 0, 6)
const GARDEN := Vector3(-42, 0, 6)
const SKY := "res://assets/polyhaven/hdris/alps_field/alps_field_2k.hdr"

var stone: ShaderMaterial
var marble: ShaderMaterial
var roof: StandardMaterial3D
var glass_day: Material
var glass_night: Material


static func resources() -> Array:
	return textures(["castle_wall_slates", "marble_01", "large_grey_tiles", "roof_slates_02", "stony_dirt_path", "forrest_ground_01", "dark_wooden_planks"]) + \
		textures(["leafy_grass", "monastery_stone_floor"], "2k") + \
		models(["gothic_statue", "shrub_02", "flower_gazania", "flower_ursinia", "flower_empodium", "potted_plant_01", "Lantern_01", "large_castle_door"]) + [SKY, TREE_NEAR, TREE_FAR]


func env_preset() -> Dictionary:
	return {"sky_day": SKY,
		"day": {"sun_rot": Vector3(-32, -150, 0), "sun_energy": 2.3, "sun_color": Color(1.0, 0.88, 0.72), "fog": 0.0006, "fog_color": Color(0.62, 0.68, 0.76), "vol_fog": 0.003, "exposure": 0.92, "bg_energy": 0.85},
		"night": {"fog": 0.003, "ambient": 1.4, "exposure": 1.35},
		"vista": {"mountains": false, "ridge_height": 360.0, "ridge_seed": 55, "haze": Color(0.6, 0.66, 0.76), "snow_line": 260.0}}


func height(x: float, z: float) -> float:
	return smoothstep(52.0, 64.0, Vector2(x * 0.8, z).length()) * 5.0 + sin(x * 0.07) * 0.15


func build_steps() -> Array:
	return [_ground, _great_hall, _towers, _wings, _fountain_court, _arena, _gardens_layout, _gardens_plants, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-62, -4, -40), Vector3(124, 20, 84))
	stone = Kit.tri("castle_wall_slates", "1k", 0.45, 0.1, Color(0.92, 0.9, 0.86))
	marble = Kit.tri("marble_01", "1k", 0.25, 0.0, Color(0.95, 0.94, 0.9))
	roof = Kit.uvmat("roof_slates_02", "1k", Vector2(5, 3), Color(0.5, 0.56, 0.64))
	glass_day = Kit.metal(Color(0.12, 0.16, 0.22), 0.06)
	glass_night = Kit.emissive(Color(1.0, 0.75, 0.45), 2.6)
	magic_receivers = [stone, marble]
	var mat := Kit.terrain_mat("leafy_grass", "stony_dirt_path", "large_grey_tiles", Color(0.78, 0.9, 0.62), Color(0.85, 0.82, 0.76), "2k")
	mat.set_shader_parameter("path_tiling", 0.28)
	Kit.terrain(self, 140.0, 1.0, height, func(x, z):
		var court := float(absf(x) < 22.0 and z > -14.0 and z < 26.0)
		var to_arena := float(x > 20.0 and x < 32.0 and absf(z - 6.0) < 2.5)
		var to_garden := float(x < -20.0 and x > -30.0 and absf(z - 6.0) < 2.5)
		var walk := maxf(maxf(court, to_arena), to_garden)
		var gp := Vector2(x - GARDEN.x, z - GARDEN.z)
		var gravel := float(absf(gp.x) < 1.6 or absf(gp.y) < 1.6) * float(gp.length() < 16.0) + float(absf(gp.length() - 6.5) < 1.2)
		return Color(walk, clampf(gravel, 0.0, 1.0) * (1.0 - walk), 0.0), mat)
	boundary_box(Vector3(0, 0, 4), Vector3(122, 20, 80))


func _arched_window(parent: Node3D, pos: Vector3, w: float, h: float) -> void:
	Kit.mesh_node(parent, Kit.box_mesh(Vector3(w, h, 0.12), 0.01), glass_day, Kit.xf(pos), false)
	Kit.mesh_node(parent, Kit.lathe([Vector2(w * 0.5, 0), Vector2(0, 0.001)], 16, false, false), glass_day, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1, 1, 1)), pos + Vector3(0, h * 0.5, 0)), false)
	night_only(Kit.mesh_node(parent, Kit.box_mesh(Vector3(w * 0.92, h * 0.95, 0.13), 0.01), glass_night, Kit.xf(pos), false))
	Kit.mesh_node(parent, Kit.box_mesh(Vector3(w + 0.35, 0.25, 0.4), 0.02), marble, Kit.xf(pos - Vector3(0, h * 0.5 + 0.12, -0.1)))
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(parent, Kit.box_mesh(Vector3(0.22, h, 0.32), 0.02), marble, Kit.xf(pos + Vector3(sx * (w * 0.5 + 0.1), 0, 0.08)))


func _great_hall() -> void:
	var c := Vector3(0, 0, -22)
	var w := 40.0
	var h := 16.0
	Kit.block(self, Vector3(w, h, 12), Kit.xf(c + Vector3(0, h * 0.5, 0)), stone, true, 0.08)
	var front := c.z + 6.05
	var root := Node3D.new()
	add_child(root)
	for i in 9:
		var x := -16.0 + i * 4.0
		if absf(x) < 3.0:
			continue
		_arched_window(root, Vector3(x, 6.5, front + 0.02), 2.0, 5.6)
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.8, h, 0.5), 0.03), marble, Kit.xf(Vector3(x + 2.0, h * 0.5, front + 0.15)))
	# grand portal
	arch(Vector3(0, 6.5, front + 0.4), 0.0, 5.0, 0.9, 1.2, marble, 13)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(1.3, 6.5, 1.4), Kit.xf(Vector3(sx * 3.15, 3.25, front + 0.4)), marble, true, 0.05)
	for p in Kit.prop_parts("large_castle_door"):
		Kit.mesh_node(self, p[0], null, Transform3D(Basis.IDENTITY.scaled(Vector3(2.4, 2.2, 2.0)), Vector3(0, 0.0, front + 0.05)) * p[1])
	Kit.block(self, Vector3(w + 1, 0.8, 13), Kit.xf(c + Vector3(0, h + 0.4, 0)), marble, false, 0.06)
	Kit.mesh_node(self, Kit.gable_roof(w, 12.6, 4.5, 0.6, 0.2), roof, Kit.xf(c + Vector3(0, h + 0.8, 0)))
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(self, Kit.gable_end(12.6, 4.5, 0.4), stone, Kit.xf(c + Vector3(sx * w * 0.5, h + 0.8, 0)))
	# central lantern spire with a clock-like rose window
	Kit.block(self, Vector3(6, 8, 6), Kit.xf(c + Vector3(0, h + 4.0 + 1.5, 0)), stone, false, 0.05)
	Kit.mesh_node(self, Kit.lathe([Vector2(4.6, 0), Vector2(0.1, 9.0)], 4, false), roof, Transform3D(Basis(Vector3.UP, PI * 0.25), c + Vector3(0, h + 9.5, 0)))
	var rose := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.2, 4.2)
	rose.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/magic/sigil.gdshader")
	sm.set_shader_parameter("sides", 12)
	sm.set_shader_parameter("color", Color(1.0, 0.75, 0.4))
	sm.set_shader_parameter("intensity", 0.9)
	sm.set_shader_parameter("spin", 0.03)
	rose.material_override = sm
	rose.position = c + Vector3(0, h + 5.5, 3.05)
	add_child(rose)


func _tower(p: Vector3, r: float, h: float) -> void:
	Kit.mesh_node(self, Kit.lathe([Vector2(r + 0.4, 0), Vector2(r + 0.4, 1.0), Vector2(r, 1.3), Vector2(r, h), Vector2(r + 0.5, h + 0.4), Vector2(r + 0.5, h + 1.2)], 24), stone, Kit.xf(p))
	var cyl := CylinderShape3D.new()
	cyl.radius = r + 0.3
	cyl.height = h
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = p + Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	Kit.mesh_node(self, Kit.lathe([Vector2(r + 0.9, 0), Vector2(r * 0.15, h * 0.45), Vector2(0.0, h * 0.5)], 24), roof, Kit.xf(p + Vector3(0, h + 1.2, 0)))
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var wp := p + Vector3(cos(a) * (r + 0.02), h * 0.7, sin(a) * (r + 0.02))
		var root := Node3D.new()
		root.transform = Transform3D(Basis(Vector3.UP, -a + PI * 0.5), wp)
		add_child(root)
		_arched_window(root, Vector3.ZERO, 1.0, 2.6)


func _towers() -> void:
	_tower(Vector3(-22.5, 0, -16.5), 4.0, 24.0)
	_tower(Vector3(22.5, 0, -16.5), 4.0, 24.0)


func _wings() -> void:
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * 27.0, 0, 6.0)
		# wing body in two halves with a real 5 m archway passage at the walkway (z ≈ 6)
		Kit.block(self, Vector3(8, 10, 10.5), Kit.xf(c + Vector3(0, 5, -7.75)), stone, true, 0.06)
		Kit.block(self, Vector3(8, 10, 10.5), Kit.xf(c + Vector3(0, 5, 7.75)), stone, true, 0.06)
		Kit.block(self, Vector3(8, 5.6, 5.2), Kit.xf(c + Vector3(0, 7.2, 0)), stone, true, 0.06)
		arch(c + Vector3(-sx * 4.1, 4.4, 0), PI * 0.5, 4.2, 0.6, 0.5, Kit.tri("marble_01", "1k", 0.25, 0.0, Color(0.95, 0.94, 0.9)), 9)
		var root := Node3D.new()
		root.transform = Kit.xf(Vector3(c.x - sx * 4.02, 0, c.z), sx * PI * 0.5)
		add_child(root)
		for i in 6:
			if i == 2 or i == 3:
				continue  # passage
			_arched_window(root, Vector3(-10.0 + i * 4.0, 5.0, 0.0), 1.6, 4.0)
		Kit.mesh_node(self, Kit.gable_roof(26.0, 8.2, 3.0, 0.4, 0.18), roof, Kit.xf(c + Vector3(0, 10.0, 0), PI * 0.5))
		for sz: float in [-1.0, 1.0]:
			Kit.mesh_node(self, Kit.gable_end(8.2, 3.0, 0.3), stone, Transform3D(Basis(Vector3.UP, PI * 0.5), c + Vector3(0, 10.0, sz * 13.0)))


func _fountain_court() -> void:
	var c := Vector3(0, 0, 6)
	Kit.mesh_node(self, Kit.lathe([Vector2(4.2, 0), Vector2(4.4, 0.6), Vector2(4.6, 0.7), Vector2(4.6, 0.8), Vector2(4.1, 0.8), Vector2(4.1, 0.2), Vector2(0.0, 0.2)], 40), marble, Kit.xf(c))
	Kit.mesh_node(self, Kit.lathe([Vector2(0.0, 0.62), Vector2(4.1, 0.62)], 40), Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.15, 0.3, 0.32), "deep": Color(0.03, 0.08, 0.1)}), Kit.xf(c), false)
	var cyl := CylinderShape3D.new()
	cyl.radius = 4.5
	cyl.height = 0.85
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = c + Vector3(0, 0.42, 0)
	body.add_child(cs)
	add_child(body)
	Kit.block(self, Vector3(1.8, 1.4, 1.8), Kit.xf(c + Vector3(0, 0.9, 0)), marble, false, 0.04)
	Kit.place_prop(self, "gothic_statue", Kit.xf(c + Vector3(0, 1.6, 0), PI, Vector3.ONE * 1.5))
	for p in [Vector3(-14, 0, 18), Vector3(14, 0, 18), Vector3(-14, 0, -4), Vector3(14, 0, -4)]:
		lantern_post(p, village_mats(), 1.2)
	add_location("academy_courtyard", Vector3(0, 0, 6), 20.0, Vector3(0, 0.05, 14.0))


func _arena() -> void:
	var c := Vector3(ARENA.x, 0, ARENA.z)
	rune_disc(c, 4.3, Color(1.0, 0.45, 0.25), Color(1.0, 0.8, 0.4), 55.0)
	Kit.mesh_node(self, Kit.lathe([Vector2(13.0, 0.0), Vector2(13.0, 0.02), Vector2(0, 0.02)], 48), Kit.tri("monastery_stone_floor", "2k", 0.25, 0.0, Color(0.85, 0.8, 0.72)), Kit.xf(c), false)
	for tier in 4:
		var r0 := 13.5 + tier * 1.6
		var y := 0.55 + tier * 0.55
		var ring := Kit.lathe([Vector2(r0, 0), Vector2(r0, y), Vector2(r0 + 1.6, y), Vector2(r0 + 1.6, 0)], 56, false, false)
		Kit.mesh_node(self, ring, stone, Kit.xf(c))
	for i in 28:
		var a := TAU * i / 28.0
		if absf(wrapf(a - PI, -PI, PI)) < 0.22:
			continue  # entrance gap facing the courtyard (west)
		Kit.static_box(self, Vector3(TAU * 13.6 / 28.0 + 0.2, 2.6, 0.6), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), c + Vector3(cos(a) * 13.7, 1.3, sin(a) * 13.7)))
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		var p := c + Vector3(cos(a) * 20.5, 0, sin(a) * 20.5)
		Kit.mesh_node(self, Kit.lathe([Vector2(0.5, 0), Vector2(0.42, 5.5), Vector2(0.65, 5.9)], 12), marble, Kit.xf(p))
		Kit.mesh_node(self, SphereMesh.new(), Kit.emissive(Color(1.0, 0.6, 0.3), 5.0, true), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.25), p + Vector3(0, 6.2, 0)), false)
	Kit.omni(self, c + Vector3(0, 6, 0), Color(1.0, 0.65, 0.35), 2.0, 20.0)
	add_location("advanced_magic_arena", c, 13.0, c + Vector3(-6.0, 0.15, 0))


func _gardens_layout() -> void:
	var c := Vector3(GARDEN.x, 0, GARDEN.z)
	Kit.mesh_node(self, Kit.lathe([Vector2(2.2, 0), Vector2(2.3, 0.55), Vector2(2.0, 0.6), Vector2(2.0, 0.15), Vector2(0, 0.15)], 32), marble, Kit.xf(c))
	Kit.mesh_node(self, Kit.lathe([Vector2(0.0, 0.48), Vector2(2.0, 0.48)], 32), Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.15, 0.3, 0.32), "deep": Color(0.03, 0.08, 0.1)}), Kit.xf(c), false)
	Kit.mesh_node(self, Kit.lathe([Vector2(0.3, 0.1), Vector2(0.18, 1.2), Vector2(0.8, 1.35), Vector2(0.6, 1.5), Vector2(0.12, 1.6), Vector2(0.06, 2.2)], 16), marble, Kit.xf(c))
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.3
	cyl.height = 0.7
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = c + Vector3(0, 0.35, 0)
	body.add_child(cs)
	add_child(body)
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var p := c + Vector3(cos(a) * 9.0, 0, sin(a) * 9.0)
		Kit.block(self, Vector3(2.0, 0.45, 0.55), Kit.xf(p + Vector3(0, 0.22, 0), -a), marble, true, 0.03)
		Kit.place_prop_all(self, "potted_plant_01", Kit.xf(c + Vector3(cos(a) * 3.4, 0, sin(a) * 3.4)), false)
	add_location("academy_gardens", c, 16.0, c + Vector3(4.5, 0.05, 4.5))


func _gardens_plants() -> void:
	var c := Vector2(GARDEN.x, GARDEN.z)
	# low hedges: dense, trimmed rows of shrub clusters along the quadrant edges
	var hx := []
	for q in 4:
		var sx := -1.0 if q % 2 == 0 else 1.0
		var sz := -1.0 if q < 2 else 1.0
		for i in 9:
			for side in 2:
				var p := c + Vector2(sx * (2.4 + i * 1.4), sz * (15.0 if side == 0 else 2.4))
				hx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.75, 0.55, 0.75)), Vector3(p.x, 0.0, p.y)))
	Kit.multimesh(self, Kit.prop("shrub_02", "shrub_02_b"), hx, 70.0, false)
	# flowerbeds in each quadrant
	var flowers := [["flower_gazania", ""], ["flower_ursinia", ""], ["flower_empodium", ""]]
	for k in flowers.size():
		var xs := []
		for i in int(110 * float(RenderProfile.get_setting("foliage_density"))):
			var q := rng.randi() % 4
			var sx := -1.0 if q % 2 == 0 else 1.0
			var sz := -1.0 if q < 2 else 1.0
			var p := c + Vector2(sx * rng.randf_range(3.2, 13.5), sz * rng.randf_range(3.2, 13.5))
			if absf(Vector2(p.x - c.x, p.y - c.y).length() - 6.5) < 1.5:
				continue
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.0, 1.8)), Vector3(p.x, 0.0, p.y)))
		Kit.multimesh(self, Kit.prop(flowers[k][0], flowers[k][1]), xs, 45.0, false)
	for p in [Vector2(-58, -10), Vector2(-58, 22), Vector2(-28, 26), Vector2(-28, -12), Vector2(60, 26), Vector2(60, -14)]:
		tree(Vector3(p.x, height(p.x, p.y) - 0.2, p.y), rng.randf_range(1.1, 1.5), rng.randf() * TAU, true)


func _links() -> void:
	# ley-line portal back to the sanctuary, at the south edge of the courtyard
	var pz := 30.0
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(0.7, 3.6, 0.7), Kit.xf(Vector3(sx * 1.6, 1.75, pz)), stone, true, 0.05)
	Kit.block(self, Vector3(4.2, 0.6, 0.8), Kit.xf(Vector3(0, 3.8, pz)), stone, true, 0.05)
	var portal := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 3.4)
	portal.mesh = q
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/magic/sigil.gdshader")
	pm.set_shader_parameter("sides", 7)
	pm.set_shader_parameter("color", Color(0.55, 0.45, 1.0))
	pm.set_shader_parameter("intensity", 1.3)
	pm.set_shader_parameter("spin", 0.25)
	portal.material_override = pm
	portal.position = Vector3(0, 1.75, pz)
	add_child(portal)
	Kit.omni(self, Vector3(0, 1.8, pz - 0.8), Color(0.6, 0.5, 1.0), 1.0, 5.0)
	add_gate("sanctuary", Vector3(0, 0, pz), Vector3(0, 0.05, pz - 4.0), 0.0, 1.2)
	add_gate("great_library", Vector3(0, 0, -15.6), Vector3(0, 0.05, -11.0), PI, 1.8)
	add_interactable(Interactable.make("statue_plaque", "Read the founder's plaque on the fountain statue", "read", "academy_courtyard",
		Vector3(0, 0, 11.0), {"knowledge": {"lore:academy_founding": 1}}, "look_around", 3.0)).radius = 2.4
	add_interactable(Interactable.make("arena_drill", "Run a casting drill in the arena", "practice", "advanced_magic_arena",
		Vector3(ARENA.x - 3.0, 0.15, ARENA.z), {"skills": {"arcane_orb": 0.35}}, "magic_attack_2h", 2.8)).radius = 3.0
	add_interactable(Interactable.make("garden_herbs", "Gather medicinal herbs in the gardens", "collect", "academy_gardens",
		Vector3(GARDEN.x + 6.0, 0, GARDEN.z + 6.0), {"items": {"herbs": 1}, "knowledge": {"botany:academy_gardens": 1}}, "", 3.0)).radius = 3.0
	add_interactable(Interactable.make("garden_fountain_rest", "Rest by the garden fountain", "rest", "academy_gardens",
		Vector3(GARDEN.x + 3.0, 0, GARDEN.z), {"knowledge": {"calm:academy_gardens": 1}}, "", 3.5)).radius = 2.4


func showcase_shots(loc: String) -> Array:
	match loc:
		"advanced_magic_arena":
			return [[ARENA + Vector3(-9.5, 2.6, 6.5), ARENA + Vector3(2, 1.2, -2), 62.0]]
		"academy_gardens":
			return [[GARDEN + Vector3(13, 2.6, -11), GARDEN + Vector3(0, 0.6, 1), 58.0]]
	return [[Vector3(-10, 2.2, 26), Vector3(0, 9, -22), 62.0], [Vector3(14, 1.8, 18), Vector3(-6, 6, -16), 60.0]]
