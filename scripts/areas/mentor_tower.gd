extends KitArea
## A4 Mentor's Tower (Arcane Sanctuary). A round stone tower on a grassy rise; an external spiral
## stair climbs to a lookout balcony; at its foot an advanced-magic circle and the mentor's desk.

const TOWER := Vector3(0, 0, -6)
const R := 4.2
const BALCONY_Y := 7.2

var stone: ShaderMaterial
var circle_mat: ShaderMaterial


static func resources() -> Array:
	return textures(["mossy_rock", "monastery_stone_floor"], "2k") + textures(["roof_slates_02", "forrest_ground_01", "stony_dirt_path", "dark_wooden_planks", "wood_table_001"]) + \
		textures(["leafy_grass"], "2k") + models(["book_encyclopedia_set_01", "brass_candleholders", "rock_moss_set_02", "fern_02", "magnifying_glass_01"]) + [TREE_NEAR, TREE_FAR]


func env_preset() -> Dictionary:
	return {"day": {"sun_rot": Vector3(-28, -100, 0), "sun_energy": 2.3, "fog": 0.0006, "vol_fog": 0.004, "exposure": 0.95},
		"night": {"fog": 0.004, "ambient": 1.5, "exposure": 1.3},
		"vista": {"mountains": false, "ridge_height": 300.0, "ridge_seed": 3, "haze": Color(0.58, 0.66, 0.76)}}


func height(x: float, z: float) -> float:
	var d := Vector2(x - TOWER.x, z - TOWER.z).length()
	return 3.0 * (1.0 - smoothstep(9.0, 30.0, d)) + sin(x * 0.11) * 0.4 + cos(z * 0.09) * 0.4 + smoothstep(32.0, 46.0, Vector2(x, z).length()) * 4.0


func build_steps() -> Array:
	return [_ground, _tower, _spiral, _balcony, _circle, _desk, _surroundings, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 20, 80))
	nav_agent_climb = 0.25
	stone = Kit.tri("mossy_rock", "2k", 0.4, 0.45, Color(0.95, 0.93, 0.9))
	magic_receivers = [stone]
	var mat := Kit.terrain_mat("leafy_grass", "forrest_ground_01", "stony_dirt_path", Color(0.8, 0.92, 0.66), Color(0.5, 0.56, 0.42), "2k")
	Kit.terrain(self, 100.0, 1.0, height, func(x, z):
		var p := Vector2(x, z)
		var trail := 1.0 - smoothstep(1.0, 2.5, absf(p.x * 0.35 + p.y * 0.0 - 0.0) if p.y > 4.0 and absf(p.x) < 3.0 else 9.0)
		return Color(trail, smoothstep(26.0, 36.0, p.length()), 0.0), mat)
	boundary_circle(Vector3.ZERO, 40.0)


func _tower() -> void:
	var y0 := height(TOWER.x, TOWER.z) - 0.4
	var prof := [Vector2(R + 0.5, 0), Vector2(R + 0.5, 1.0), Vector2(R, 1.2), Vector2(R - 0.15, 13.5), Vector2(R + 0.35, 13.8), Vector2(R + 0.35, 14.6), Vector2(R, 14.7)]
	Kit.mesh_node(self, Kit.lathe(prof, 40, true, true), stone, Kit.xf(TOWER + Vector3(0, y0, 0)))
	var cyl := CylinderShape3D.new()
	cyl.radius = R
	cyl.height = 15.0
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = TOWER + Vector3(0, y0 + 7.5, 0)
	body.add_child(cs)
	add_child(body)
	# crenellations
	for i in 16:
		var a := TAU * i / 16.0
		if i % 2 == 0:
			Kit.block(self, Vector3(1.2, 0.9, 0.6), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), TOWER + Vector3(cos(a) * (R + 0.1), y0 + 15.05, sin(a) * (R + 0.1))), stone, false, 0.04)
	# conical slate roof over an inner turret
	Kit.mesh_node(self, Kit.lathe([Vector2(2.6, 0), Vector2(2.4, 3.0)], 24), stone, Kit.xf(TOWER + Vector3(0, y0 + 14.6, 0)))
	Kit.mesh_node(self, Kit.lathe([Vector2(3.2, 0), Vector2(0.05, 5.0)], 24), Kit.uvmat("roof_slates_02", "1k", Vector2(3, 2)), Kit.xf(TOWER + Vector3(0, y0 + 17.6, 0)))
	# windows glowing at night
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		var wy := y0 + 3.5 + (i % 3) * 3.3
		var p := TOWER + Vector3(cos(a) * (R - 0.05), wy, sin(a) * (R - 0.05))
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.7, 1.3, 0.2), 0.02), Kit.metal(Color(0.06, 0.07, 0.09), 0.15), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p), false)
		night_only(Kit.mesh_node(self, Kit.box_mesh(Vector3(0.62, 1.2, 0.22), 0.02), Kit.emissive(Color(1.0, 0.72, 0.4), 3.0), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p), false))
	# door
	Kit.block(self, Vector3(1.5, 2.6, 0.3), Kit.xf(TOWER + Vector3(0, y0 + 1.3, R + 0.05)), Kit.tri("dark_wooden_planks", "1k", 1.0, 0.0, Color(0.55, 0.42, 0.3)), false, 0.02)


func _spiral() -> void:
	# external spiral stair: wedge treads around the tower (collision = smooth helical ramp segments)
	var y0 := height(TOWER.x, TOWER.z) - 0.4 + 1.0
	var steps := 36
	var rise := (BALCONY_Y - 1.0) / steps
	var a0 := PI * 0.5
	var sweep := PI * 1.6
	var width := 1.5
	for k in steps:
		var a := a0 - sweep * (k + 0.5) / steps
		var r := R + width * 0.5 + 0.05
		var p := TOWER + Vector3(cos(a) * r, y0 + rise * (k + 1) - 0.12, sin(a) * r)
		var tread_len := sweep / steps * (R + width) + 0.08
		Kit.mesh_node(self, Kit.box_mesh(Vector3(tread_len, 0.24, width), 0.02), stone, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p))
		if k % 3 == 1:
			Kit.mesh_node(self, Kit.box_mesh(Vector3(0.12, 1.0, 0.12), 0.01), stone, Kit.xf(p + Vector3(cos(a) * (width * 0.5 - 0.06), 0.6, sin(a) * (width * 0.5 - 0.06))))
	# smooth ramp colliders, one per 3 steps (approximate helix)
	for k in range(0, steps, 3):
		var a_mid := a0 - sweep * (k + 1.5) / steps
		var r := R + width * 0.5 + 0.05
		var y_mid := y0 + rise * (k + 1.5)
		var seg_len := sweep / steps * 3.0 * r + 0.2
		var slope := atan2(rise * 3.0, sweep / steps * 3.0 * r)
		var b := Basis(Vector3.UP, -a_mid + PI * 0.5) * Basis(Vector3.FORWARD, -slope)
		Kit.static_box(self, Vector3(seg_len, 0.2, width), Transform3D(b, TOWER + Vector3(cos(a_mid) * r, y_mid - 0.1, sin(a_mid) * r)))
		Kit.static_box(self, Vector3(seg_len, 1.2, 0.1), Transform3D(Basis(Vector3.UP, -a_mid + PI * 0.5), TOWER + Vector3(cos(a_mid) * (r + width * 0.5), y_mid + 0.6, sin(a_mid) * (r + width * 0.5))))


func _balcony() -> void:
	var y0 := height(TOWER.x, TOWER.z) - 0.4
	var a_end := PI * 0.5 - PI * 1.6
	# ring balcony at the stair top
	var ring := Kit.lathe([Vector2(R, BALCONY_Y - 0.25), Vector2(R + 2.3, BALCONY_Y - 0.25), Vector2(R + 2.3, BALCONY_Y), Vector2(R, BALCONY_Y)], 40, false, false)
	Kit.mesh_node(self, ring, stone, Kit.xf(TOWER + Vector3(0, y0, 0)))
	for i in 20:
		var a := TAU * i / 20.0
		var p := TOWER + Vector3(cos(a) * (R + 1.15), y0 + BALCONY_Y - 0.12, sin(a) * (R + 1.15))
		Kit.static_box(self, Vector3(TAU * (R + 1.15) / 20.0 + 0.2, 0.25, 2.3), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p))
		var ang_from_stair := wrapf(a - a_end, -PI, PI)
		if absf(ang_from_stair) > 0.35:
			Kit.block(self, Vector3(TAU * (R + 2.2) / 20.0, 0.9, 0.18), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), TOWER + Vector3(cos(a) * (R + 2.2), y0 + BALCONY_Y + 0.45, sin(a) * (R + 2.2))), stone, true, 0.03)
	var look := TOWER + Vector3(cos(-PI * 0.5) * (R + 1.4), y0 + BALCONY_Y, sin(-PI * 0.5) * (R + 1.4))
	add_poi("tower_lookout", look, "Lookout balcony high on the Mentor's Tower", "mentors_tower")


func _circle() -> void:
	var c := Vector3(0, height(0, 9.0), 9.0)
	circle_mat = rune_disc(c, 4.3, Color(0.85, 0.35, 0.9), Color(1.0, 0.7, 0.4), 21.0)
	for i in 6:
		var a := TAU * i / 6.0
		var p := c + Vector3(cos(a) * 5.4, 0, sin(a) * 5.4)
		Kit.block(self, Vector3(0.5, 1.6, 0.5), Kit.xf(Vector3(p.x, height(p.x, p.z) + 0.7, p.z), a), stone, true, 0.05)
		Kit.mesh_node(self, Kit.crystal_mesh(0.5, 0.09, i), Kit.crystal(Color(0.85, 0.4, 1.0), 3.0), Kit.xf(Vector3(p.x, height(p.x, p.z) + 1.5, p.z)), false)
	Kit.omni(self, c + Vector3(0, 2.5, 0), Color(0.8, 0.5, 1.0), 1.2, 9.0)
	add_location("mentors_tower", Vector3(0, 0, 0), 20.0, c + Vector3(0, 0.12, 2.0))
	add_poi("advanced_magic_circle", c, "Advanced-magic circle at the foot of the tower", "mentors_tower", 4.0)


func _desk() -> void:
	var p := TOWER + Vector3(-3.5, height(TOWER.x - 3.5, TOWER.z + 6.5), 6.5)
	var wood := Kit.tri("wood_table_001", "1k", 0.9, 0.0, Color(0.7, 0.55, 0.42))
	Kit.block(self, Vector3(1.8, 0.08, 0.9), Kit.xf(p + Vector3(0, 0.78, 0), 0.3), wood, false, 0.02)
	Kit.static_box(self, Vector3(1.8, 0.82, 0.9), Kit.xf(p + Vector3(0, 0.41, 0), 0.3))
	for c in [Vector2(-0.8, -0.38), Vector2(0.8, -0.38), Vector2(-0.8, 0.38), Vector2(0.8, 0.38)]:
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.08, 0.78, 0.08), 0.01), wood, Transform3D(Basis(Vector3.UP, 0.3), p + Basis(Vector3.UP, 0.3) * Vector3(c.x, 0.39, c.y)))
	Kit.mesh_node(self, Kit.prop("book_encyclopedia_set_01", "book_encyclopedia_set_01_book11"), null, Transform3D(Basis(Vector3.UP, 0.6) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.3), p + Vector3(0.1, 0.84, 0)))
	Kit.place_prop(self, "magnifying_glass_01", Kit.xf(p + Vector3(-0.5, 0.83, 0.1), 1.0, Vector3.ONE * 1.2))
	add_interactable(Interactable.make("mentor_notes", "Read the mentor's notes on advanced casting", "study", "mentors_tower",
		p + Vector3(0.3, 0, 1.0), {"knowledge": {"lore:advanced_casting": 1}, "skills": {"arcane_orb": 0.1}}, "look_around", 4.0)).radius = 2.4


func _surroundings() -> void:
	for p in [Vector2(-18, -14), Vector2(16, -18), Vector2(-22, 10), Vector2(20, 14), Vector2(-6, 26), Vector2(24, -2)]:
		tree(Vector3(p.x, height(p.x, p.y) - 0.2, p.y), rng.randf_range(1.0, 1.5), rng.randf() * TAU, true)
	rocks_ring(Vector3(0, 0, 0), 24.0, 10, 0.8, 1.8, stone, height, 600)
	var h := height
	for part in ["fern_02_a", "fern_02_b"]:
		scatter("fern_02", part, 60, Vector2.ZERO, 10.0, 34.0, 0.9, 1.6, h, func(p: Vector2) -> bool: return p.distance_to(Vector2(0, 9)) > 6.5 and p.distance_to(Vector2(TOWER.x, TOWER.z)) > 7.5, 45.0)


func _links() -> void:
	add_gate("sanctuary", Vector3(-30.0, height(-30, 22), 22.0), Vector3(-25.0, height(-25, 18) + 0.05, 18.0), atan2(25.0, 18.0), 2.6)
	add_interactable(Interactable.make("advanced_circle_practice", "Practise advanced casting in the circle", "practice", "mentors_tower",
		Vector3(0, height(0, 9.0) + 0.12, 9.0), {"skills": {"arcane_orb": 0.3}}, "magic_attack_2h", 2.8)).radius = 3.6
	add_interactable(Interactable.make("lookout_survey", "Survey the realm from the tower lookout", "observe", "mentors_tower",
		points_of_interest["tower_lookout"].position, {"knowledge": {"geography:from_tower": 1}, "discover": ["academy_courtyard", "village_square"]}, "look_around", 4.0)).radius = 2.4


func showcase_shots(_loc: String) -> Array:
	return [[Vector3(14, 3.5, 22), TOWER + Vector3(0, 7, 0), 55.0], [TOWER + Vector3(0, 8.6, -6.5), Vector3(0, 6, -60), 60.0]]
