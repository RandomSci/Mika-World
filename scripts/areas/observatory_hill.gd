extends KitArea
## C4 Village Observatory (Fantasy Village). A paved circular terrace on a hilltop with a brass
## telescope on a stone pier, a star-chart table and benches, overlooking the village below.

const TERRACE := Vector3(0, 0, 0)

var stone: ShaderMaterial


static func resources() -> Array:
	return textures(["castle_wall_slates", "forrest_ground_01", "stony_dirt_path", "wood_table_001", "dark_wooden_planks", "large_grey_tiles"]) + textures(["leafy_grass"], "2k") + \
		models(["Lantern_01", "fern_02", "shrub_02", "folding_wooden_stool"]) + [TREE_NEAR, TREE_FAR, "res://assets/polyhaven/hdris/kloppenheim_06_puresky/kloppenheim_06_puresky_2k.hdr"]


func env_preset() -> Dictionary:
	return {"sky_day": "res://assets/polyhaven/hdris/kloppenheim_06_puresky/kloppenheim_06_puresky_2k.hdr",
		"day": {"sun_rot": Vector3(-20, -110, 0), "sun_energy": 2.1, "sun_color": Color(1.0, 0.8, 0.6), "fog": 0.0015, "vol_fog": 0.003, "exposure": 0.95, "bg_energy": 0.85},
		"night": {"fog": 0.002, "ambient": 1.4, "exposure": 1.35, "bg_energy": 1.2},
		"vista": {"mountains": true, "ridge_height": 420.0, "ridge_seed": 12, "haze": Color(0.56, 0.62, 0.7), "snow_line": 260.0}}


func height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	return -smoothstep(12.0, 40.0, d) * 9.0 + sin(x * 0.13) * 0.3 + cos(z * 0.11) * 0.3 * smoothstep(10.0, 14.0, d)


func build_steps() -> Array:
	return [_ground, _terrace, _telescope, _furniture, _surroundings, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-30, -12, -30), Vector3(60, 20, 60))
	stone = Kit.tri("castle_wall_slates", "1k", 0.45, 0.35)
	magic_receivers = [stone]
	var mat := Kit.terrain_mat("leafy_grass", "forrest_ground_01", "stony_dirt_path", Color(0.78, 0.9, 0.66), Color(0.5, 0.55, 0.42), "2k")
	Kit.terrain(self, 80.0, 1.0, height, func(x, z):
		var path := (1.0 - smoothstep(1.2, 2.6, absf(x - z) * 0.7071)) * float(x > 6.0 and z > 6.0)
		return Color(path, smoothstep(18.0, 30.0, Vector2(x, z).length()) * 0.6, 0.0), mat)
	boundary_circle(Vector3.ZERO, 26.0)


func _terrace() -> void:
	var tiles := Kit.tri("large_grey_tiles", "1k", 0.35, 0.1, Color(0.8, 0.78, 0.75))
	Kit.mesh_node(self, Kit.lathe([Vector2(9.5, -0.6), Vector2(9.5, 0.06), Vector2(0, 0.06)], 48), tiles, Kit.xf(TERRACE))
	var cyl := CylinderShape3D.new()
	cyl.radius = 9.5
	cyl.height = 0.66
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = TERRACE + Vector3(0, -0.27, 0)
	body.add_child(cs)
	add_child(body)
	# balustrade with an opening toward the village (south-east)
	for i in 36:
		var a := TAU * i / 36.0
		if absf(wrapf(a - PI * 0.25, -PI, PI)) < 0.25:
			continue
		var p := Vector3(cos(a) * 9.3, 0.6, sin(a) * 9.3)
		Kit.block(self, Vector3(TAU * 9.3 / 36.0 + 0.05, 0.12, 0.35), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p + Vector3(0, 0.45, 0)), stone, true, 0.02)
		Kit.mesh_node(self, Kit.lathe([Vector2(0.1, 0), Vector2(0.14, 0.15), Vector2(0.07, 0.45), Vector2(0.12, 0.85)], 8), stone, Kit.xf(p + Vector3(0, -0.45, 0)))
	add_location("village_observatory", TERRACE, 12.0, Vector3(3.0, 0.2, 3.0))


func _telescope() -> void:
	var brass := Kit.metal(Color(0.78, 0.58, 0.3), 0.28)
	var dark := Kit.metal(Color(0.12, 0.1, 0.09), 0.4)
	Kit.mesh_node(self, Kit.lathe([Vector2(0.9, 0.15), Vector2(0.9, 0.35), Vector2(0.55, 0.45), Vector2(0.45, 1.1), Vector2(0.6, 1.2), Vector2(0.6, 1.3)], 16, false), stone, Kit.xf(Vector3(-2, 0, -2)))
	Kit.static_box(self, Vector3(1.2, 1.3, 1.2), Kit.xf(Vector3(-2, 0.65, -2)))
	var mount := Node3D.new()
	mount.position = Vector3(-2, 1.35, -2)
	mount.rotation = Vector3(0, -0.6, 0)
	add_child(mount)
	Kit.mesh_node(mount, Kit.lathe([Vector2(0.18, 0), Vector2(0.12, 0.35)], 12), brass, Transform3D.IDENTITY)
	var tube := Node3D.new()
	tube.position = Vector3(0, 0.45, 0)
	tube.rotation = Vector3(0.75, 0, 0)
	mount.add_child(tube)
	Kit.mesh_node(tube, Kit.lathe([Vector2(0.11, -1.2), Vector2(0.12, -0.2), Vector2(0.16, -0.15), Vector2(0.16, 0.15), Vector2(0.14, 0.2), Vector2(0.17, 1.5), Vector2(0.2, 1.55), Vector2(0.2, 1.75)], 18), brass, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	Kit.mesh_node(tube, Kit.lathe([Vector2(0.05, 0), Vector2(0.05, 0.3)], 8), dark, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.05, 1.25)))
	add_poi("brass_telescope", Vector3(-2, 0.15, -2), "Brass telescope on a stone pier", "village_observatory", 2.0)


func _furniture() -> void:
	var wood := Kit.tri("wood_table_001", "1k", 0.9, 0.0, Color(0.7, 0.55, 0.42))
	Kit.block(self, Vector3(1.6, 0.08, 1.0), Kit.xf(Vector3(3.2, 0.95, -3.2), 0.6), wood, false, 0.02)
	Kit.static_box(self, Vector3(1.6, 0.95, 1.0), Kit.xf(Vector3(3.2, 0.5, -3.2), 0.6))
	for c in [Vector2(-0.7, -0.4), Vector2(0.7, -0.4), Vector2(-0.7, 0.4), Vector2(0.7, 0.4)]:
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.07, 0.8, 0.07), 0.01), wood, Transform3D(Basis(Vector3.UP, 0.6), Vector3(3.2, 0.55, -3.2) + Basis(Vector3.UP, 0.6) * Vector3(c.x, 0, c.y)))
	# star chart: an original circular chart drawn with the sigil shader
	var chart := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	chart.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/magic/sigil.gdshader")
	sm.set_shader_parameter("sides", 8)
	sm.set_shader_parameter("color", Color(0.9, 0.8, 0.5))
	sm.set_shader_parameter("intensity", 0.6)
	sm.set_shader_parameter("spin", 0.0)
	chart.material_override = sm
	chart.transform = Transform3D(Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, -PI * 0.5), Vector3(3.2, 1.0, -3.2))
	add_child(chart)
	for p in [Vector3(5.5, 0.15, 3.5), Vector3(-5.5, 0.15, 3.0)]:
		Kit.block(self, Vector3(2.2, 0.45, 0.6), Kit.xf(p + Vector3(0, 0.22, 0), atan2(p.x, p.z)), stone, true, 0.03)
	for p in [Vector3(7.8, 0.15, -4.0), Vector3(-7.8, 0.15, -4.0), Vector3(0, 0.15, -8.6)]:
		lantern_post(p, village_mats(), 1.0)


func _surroundings() -> void:
	for p in [Vector2(-16, -10), Vector2(14, -14), Vector2(-18, 12), Vector2(-4, -20)]:
		tree(Vector3(p.x, height(p.x, p.y) - 0.2, p.y), rng.randf_range(1.0, 1.4), rng.randf() * TAU, true)
	var h := height
	scatter("shrub_02", "shrub_02_b", 14, Vector2.ZERO, 11.0, 24.0, 0.8, 1.3, h, func(p: Vector2) -> bool: return not (p.x > 4.0 and p.y > 4.0), 60.0)
	scatter("fern_02", "fern_02_a", 40, Vector2.ZERO, 10.5, 24.0, 0.9, 1.5, h, func(p: Vector2) -> bool: return not (p.x > 4.0 and p.y > 4.0), 45.0)


func _links() -> void:
	add_gate("village", Vector3(18.0, height(18, 18), 18.0), Vector3(12.5, height(12.5, 12.5) + 0.05, 12.5), PI * 0.25 + PI, 2.4)
	add_interactable(Interactable.make("telescope_observe", "Observe the sky through the brass telescope", "observe", "village_observatory",
		Vector3(-2, 0.15, -2), {"knowledge": {"astronomy:constellations": 1}, "discover": ["celestial_observatory"]}, "look_around", 5.0)).radius = 2.0
	add_interactable(Interactable.make("star_chart_study", "Study the star chart", "study", "village_observatory",
		Vector3(3.2, 0.15, -3.2), {"knowledge": {"astronomy:star_chart": 1}}, "", 4.0)).radius = 2.0


func showcase_shots(_loc: String) -> Array:
	return [[Vector3(7, 1.8, 7), Vector3(-2, 1.6, -2), 55.0], [Vector3(-4, 2.0, -6), Vector3(600, -40, 700), 50.0]]
