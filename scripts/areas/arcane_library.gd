extends KitArea
## A3 Ancient Spell Library: a vaulted hall beneath the sanctuary's west ruins.
## Stone ribs and pillars, tall shelves of books, reading desks with real scanned books,
## lantern chandeliers, moonlight shafts through ceiling grates, a glowing spell lectern.

const W := 16.0
const L := 30.0
const H := 8.0

var stone: ShaderMaterial
var wood: ShaderMaterial


static func resources() -> Array:
	return textures(["castle_wall_slates", "large_grey_tiles", "wood_table_001", "dark_wooden_planks"]) + \
		models(["book_encyclopedia_set_01", "brass_candleholders", "lantern_chandelier_01", "magnifying_glass_01", "GothicCabinet_01", "folding_wooden_stool", "treasure_chest", "brass_vase_01"])


func env_preset() -> Dictionary:
	return {"bg": Color(0.01, 0.01, 0.015), "sun_shadows": false,
		"day": {"ambient_color": Color(0.38, 0.35, 0.4), "ambient": 0.75, "sun_energy": 0.0, "fog": 0.02, "fog_color": Color(0.08, 0.07, 0.06), "vol_fog": 0.03, "vol_albedo": Color(0.8, 0.85, 1.0), "exposure": 1.15},
		"night": {"ambient_color": Color(0.22, 0.24, 0.34), "ambient": 0.45, "sun_energy": 0.0, "fog": 0.02, "fog_color": Color(0.05, 0.05, 0.07), "vol_fog": 0.03, "exposure": 1.2}}


func build_steps() -> Array:
	return [_shell, _vault, _shelves, _desks, _lectern, _lights, _links]


func _shell() -> void:
	nav_aabb = AABB(Vector3(-W * 0.5, -1, -L * 0.5), Vector3(W, 6, L + 4))
	stone = Kit.tri("castle_wall_slates", "1k", 0.45, 0.15, Color(0.9, 0.88, 0.85))
	wood = Kit.tri("wood_table_001", "1k", 0.8, 0.0, Color(0.7, 0.55, 0.45))
	magic_receivers = [stone]
	Kit.block(self, Vector3(W + 2, 0.4, L + 2), Kit.xf(Vector3(0, -0.2, 0)), Kit.tri("large_grey_tiles", "1k", 0.33, 0.0, Color(0.75, 0.72, 0.7)))
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(1.0, H, L + 2), Kit.xf(Vector3(sx * (W * 0.5 + 0.5), H * 0.5, 0)), stone)
	Kit.block(self, Vector3(W + 2, H, 1.0), Kit.xf(Vector3(0, H * 0.5, -L * 0.5 - 0.5)), stone)
	# south wall with the stair opening
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(W * 0.5 - 1.4, H, 1.0), Kit.xf(Vector3(sx * (W * 0.25 + 0.7), H * 0.5, L * 0.5 + 0.5)), stone)
	Kit.block(self, Vector3(2.8, H - 3.2, 1.0), Kit.xf(Vector3(0, 3.2 + (H - 3.2) * 0.5, L * 0.5 + 0.5)), stone)
	for k in 10:  # stair up toward the sanctuary, fading into darkness
		Kit.block(self, Vector3(2.6, 0.22 * (k + 1), 0.45), Kit.xf(Vector3(0, 0.11 * (k + 1), L * 0.5 + 1.2 + k * 0.45)), stone, k < 2, 0.02)
	Kit.block(self, Vector3(2.8, 0.4, 6), Kit.xf(Vector3(0, 3.4, L * 0.5 + 3.5)), stone, false)
	Kit.block(self, Vector3(W + 2, 0.6, L + 2), Kit.xf(Vector3(0, H + 0.3, 0)), stone, false)


func _vault() -> void:
	# transverse ribs on pillars every 5 m
	for i in 7:
		var z := -L * 0.5 + 0.5 + i * 4.83
		for sx: float in [-1.0, 1.0]:
			Kit.mesh_node(self, Kit.lathe([Vector2(0.5, 0), Vector2(0.55, 0.3), Vector2(0.4, 0.5), Vector2(0.36, 4.4), Vector2(0.5, 4.7), Vector2(0.5, 4.9)], 10, false), stone,
				Kit.xf(Vector3(sx * (W * 0.5 - 0.45), 0, z)))
		arch(Vector3(0, 4.9, z), PI * 0.5, W - 1.0, 0.45, 0.6, stone, 13)
	# longitudinal ridge rib
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.5, 0.4, L), 0.05), stone, Kit.xf(Vector3(0, H - 0.4, 0)))
	# moonlight grates in the vault
	for z in [-8.0, 2.0]:
		Kit.mesh_node(self, Kit.box_mesh(Vector3(1.4, 0.05, 1.4), 0.01), Kit.emissive(Color(0.55, 0.65, 0.9), 2.0, true), Kit.xf(Vector3(0, H - 0.02, z)), false)
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, H - 0.1, z)
		spot.rotation_degrees = Vector3(-90, 0, 0)
		spot.light_color = Color(0.6, 0.7, 1.0)
		spot.light_energy = 6.0
		spot.spot_range = 12.0
		spot.spot_angle = 14.0
		spot.light_volumetric_fog_energy = 3.0
		add_child(spot)


func _shelves() -> void:
	# tall shelf units between the pillars; books are instanced blocks with per-book colour (cheap, dense)
	var book_mesh := Kit.box_mesh(Vector3(0.05, 0.28, 0.2), 0.008)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = book_mesh
	var xs := []
	var cols := []
	var palette := [Color(0.35, 0.08, 0.06), Color(0.12, 0.18, 0.3), Color(0.15, 0.24, 0.12), Color(0.42, 0.3, 0.16), Color(0.2, 0.12, 0.08), Color(0.5, 0.42, 0.3)]
	for i in 6:
		var zc := -L * 0.5 + 0.5 + (i + 0.5) * 4.83
		for sx: float in [-1.0, 1.0]:
			var x := sx * (W * 0.5 - 0.35)
			Kit.block(self, Vector3(0.5, 4.2, 3.8), Kit.xf(Vector3(x, 2.1, zc)), wood, true, 0.02)
			for shelf in 6:
				var y := 0.25 + shelf * 0.68
				Kit.mesh_node(self, Kit.box_mesh(Vector3(0.52, 0.05, 3.7), 0.01), wood, Kit.xf(Vector3(x - sx * 0.02, y - 0.03, zc)), false)
				var z := zc - 1.75
				while z < zc + 1.75:
					var w := rng.randf_range(0.035, 0.07)
					var hgt := rng.randf_range(0.2, 0.32)
					var lean := rng.randf_range(-0.12, 0.12) if rng.randf() < 0.12 else 0.0
					xs.append(Transform3D(Basis(Vector3.RIGHT, lean).scaled(Vector3(rng.randf_range(0.8, 1.15), hgt / 0.28, w / 0.05)).rotated(Vector3.UP, PI * 0.5),
						Vector3(x - sx * 0.12, y + hgt * 0.5, z + w * 0.5)))
					cols.append(palette[rng.randi() % palette.size()] * rng.randf_range(0.8, 1.25))
					z += w + (0.002 if rng.randf() > 0.06 else 0.12)
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.62
	bm.albedo_texture = load("res://assets/polyhaven/textures/dark_wooden_planks/dark_wooden_planks_rough_1k.jpg")
	bm.uv1_scale = Vector3(0.3, 0.3, 0.3)
	mmi.material_override = bm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# two scanned gothic cabinets at the north end
	for sx: float in [-1.0, 1.0]:
		Kit.place_prop_all(self, "GothicCabinet_01", Kit.xf(Vector3(sx * 4.0, 0, -L * 0.5 + 0.6), 0.0), true)


func _desk(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.transform = Kit.xf(pos, yaw)
	add_child(root)
	Kit.block(root, Vector3(2.2, 0.08, 1.0), Kit.xf(Vector3(0, 0.78, 0)), wood, false, 0.02)
	for c in [Vector2(-1, -0.42), Vector2(1, -0.42), Vector2(-1, 0.42), Vector2(1, 0.42)]:
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.09, 0.76, 0.09), 0.01), wood, Kit.xf(Vector3(c.x, 0.38, c.y)))
	Kit.static_box(root, Vector3(2.2, 0.85, 1.0), Kit.xf(Vector3(0, 0.42, 0)))
	var b1 := Kit.mesh_node(root, Kit.prop("book_encyclopedia_set_01", "book_encyclopedia_set_01_book02"), null,
		Transform3D(Basis(Vector3.UP, 0.3) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.2), Vector3(-0.4, 0.84, 0.1)))
	Kit.mesh_node(root, Kit.prop("book_encyclopedia_set_01", "book_encyclopedia_set_01_book05"), null,
		Transform3D(Basis(Vector3.UP, -0.4) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.2), Vector3(0.3, 0.84, -0.15)))
	Kit.mesh_node(root, Kit.prop("brass_candleholders", "brass_candleholder_02"), null, Kit.xf(Vector3(0.85, 0.82, 0.25)))
	Kit.mesh_node(root, SphereMesh.new(), Kit.emissive(Color(1.0, 0.7, 0.35), 8.0, true), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.025), Vector3(0.85, 1.25, 0.25)), false)
	Kit.omni(root, Vector3(0.85, 1.35, 0.25), Color(1.0, 0.68, 0.38), 0.7, 3.5)
	for sx: float in [-0.6, 0.6]:
		Kit.mesh_node(root, Kit.prop("folding_wooden_stool"), null, Kit.xf(Vector3(sx, 0, 0.85), rng.randf()))


func _desks() -> void:
	_desk(Vector3(-2.6, 0, -6.0), 0.0)
	_desk(Vector3(2.6, 0, -6.0), 0.0)
	_desk(Vector3(-2.6, 0, 4.0), 0.0)
	_desk(Vector3(2.6, 0, 4.0), PI)
	# map table with a magnifying glass
	Kit.block(self, Vector3(1.6, 0.9, 1.6), Kit.xf(Vector3(4.6, 0.45, 9.5)), wood, true, 0.03)
	Kit.mesh_node(self, Kit.box_mesh(Vector3(1.4, 0.01, 1.1), 0.002), Kit.uvmat("plastered_wall_02", "1k", Vector2.ONE, Color(0.95, 0.85, 0.62)), Kit.xf(Vector3(4.6, 0.91, 9.5), 0.2), false)
	Kit.place_prop(self, "magnifying_glass_01", Kit.xf(Vector3(4.8, 0.92, 9.4), 0.7, Vector3.ONE * 1.3))
	Kit.place_prop_all(self, "treasure_chest", Kit.xf(Vector3(-6.4, 0, 11.0), PI * 0.5), true)
	Kit.place_prop(self, "brass_vase_01", Kit.xf(Vector3(-6.6, 0, -12.5), 0.0, Vector3.ONE * 1.6))


func _lectern() -> void:
	var c := Vector3(0, 0, -11.0)
	rune_disc(c, 4.3, Color(0.85, 0.6, 0.3), Color(1.0, 0.8, 0.45), 9.0)
	Kit.mesh_node(self, Kit.lathe([Vector2(0.45, 0.12), Vector2(0.45, 0.25), Vector2(0.2, 0.32), Vector2(0.16, 1.0), Vector2(0.3, 1.08)], 8, false), stone, Kit.xf(c))
	Kit.static_box(self, Vector3(0.7, 1.1, 0.7), Kit.xf(c + Vector3(0, 0.55, 0)))
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.7, 0.06, 0.5), 0.01), wood, Transform3D(Basis(Vector3.RIGHT, 0.35), c + Vector3(0, 1.15, 0)))
	var book := Kit.mesh_node(self, Kit.prop("book_encyclopedia_set_01", "book_encyclopedia_set_01_book09"), null,
		Transform3D(Basis(Vector3.RIGHT, 0.35) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.4), c + Vector3(-0.1, 1.2, -0.05)))
	Kit.omni(self, c + Vector3(0, 1.9, 0.6), Color(1.0, 0.75, 0.45), 1.4, 6.0)
	add_location("ancient_spell_library", Vector3(0, 0, 0), 18.0, Vector3(0, 0, -2.0))


func _lights() -> void:
	for z in [-9.0, 0.0, 9.0]:
		Kit.mesh_node(self, Kit.prop("lantern_chandelier_01"), null, Kit.xf(Vector3(0, H - 2.4, z), 0.0, Vector3.ONE * 1.3))
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.04, 1.2, 0.04), 0.005), Kit.metal(Color(0.15, 0.12, 0.1), 0.5), Kit.xf(Vector3(0, H - 0.6, z)), false)
		Kit.omni(self, Vector3(0, H - 2.6, z), Color(1.0, 0.7, 0.42), 3.0, 13.0)


func _links() -> void:
	add_gate("sanctuary", Vector3(0, 0.5, L * 0.5 + 1.6), Vector3(0, 0.05, L * 0.5 - 3.0), 0.0, 1.3)
	add_interactable(Interactable.make("lectern_warding_glyph", "Study the Warding Glyph on the spell lectern", "study", "ancient_spell_library",
		Vector3(0, 0, -10.2), {"knowledge": {"spell:warding_glyph_theory": 1, "lore:library_lectern": 1}}, "look_around", 5.0)).radius = 2.4
	add_interactable(Interactable.make("research_desk", "Research at the reading desk", "study", "ancient_spell_library",
		Vector3(-2.6, 0, 3.0), {"knowledge": {"lore:history_of_the_sanctuary": 1}, "skills": {"arcane_orb": 0.05}}, "", 5.0)).radius = 2.2
	add_interactable(Interactable.make("map_table", "Examine the old map of the realm", "inspect", "ancient_spell_library",
		Vector3(4.6, 0, 8.5), {"knowledge": {"geography:realm_map": 1}, "discover": ["village_square", "crystal_entrance", "cloud_temple", "academy_courtyard"]}, "look_around", 4.0)).radius = 2.2
