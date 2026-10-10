extends KitArea
## F2 Great Library (Grand Academy, interior). A tall marble hall lined with two tiers of bookcases
## and an upper gallery, sunlight shafts through tall windows, rows of study tables with scanned
## books and candles, chandeliers, and a mosaic rune circle at the crossing.

const W := 24.0
const L := 40.0
const H := 14.0

var marble: ShaderMaterial
var wood: ShaderMaterial
var dark_wood: ShaderMaterial


static func resources() -> Array:
	return textures(["marble_01", "herringbone_parquet", "wood_table_001", "dark_wooden_planks", "large_grey_tiles"]) + textures(["monastery_stone_floor"], "2k") + \
		models(["book_encyclopedia_set_01", "brass_candleholders", "Chandelier_02", "folding_wooden_stool", "GothicCabinet_01", "magnifying_glass_01", "brass_vase_01", "large_castle_door"])


func env_preset() -> Dictionary:
	return {"bg": Color(0.02, 0.02, 0.025), "sun_shadows": false,
		"day": {"ambient_color": Color(0.55, 0.5, 0.45), "ambient": 0.55, "sun_energy": 0.0, "fog": 0.008, "fog_color": Color(0.2, 0.17, 0.13), "vol_fog": 0.02, "vol_albedo": Color(1.0, 0.95, 0.85), "exposure": 1.05},
		"night": {"ambient_color": Color(0.3, 0.3, 0.38), "ambient": 0.4, "sun_energy": 0.0, "fog": 0.008, "fog_color": Color(0.06, 0.06, 0.08), "vol_fog": 0.015, "exposure": 1.2}}


func build_steps() -> Array:
	return [_shell, _windows, _bookcases, _gallery, _tables, _crossing, _lights, _links]


func _shell() -> void:
	nav_aabb = AABB(Vector3(-W * 0.5, -1, -L * 0.5), Vector3(W, 6, L + 2))
	marble = Kit.tri("marble_01", "1k", 0.22, 0.0, Color(0.92, 0.9, 0.85))
	wood = Kit.tri("wood_table_001", "1k", 0.8, 0.0, Color(0.72, 0.56, 0.42))
	dark_wood = Kit.tri("dark_wooden_planks", "1k", 0.6, 0.0, Color(0.5, 0.36, 0.26))
	magic_receivers = [marble]
	Kit.block(self, Vector3(W + 2, 0.4, L + 2), Kit.xf(Vector3(0, -0.2, 0)), Kit.uvmat("herringbone_parquet", "1k", Vector2(14, 22)), true, 0.01)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(1.0, H, L + 2), Kit.xf(Vector3(sx * (W * 0.5 + 0.5), H * 0.5, 0)), marble)
	Kit.block(self, Vector3(W + 2, H, 1.0), Kit.xf(Vector3(0, H * 0.5, -L * 0.5 - 0.5)), marble)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(W * 0.5 - 1.8, H, 1.0), Kit.xf(Vector3(sx * (W * 0.25 + 0.9), H * 0.5, L * 0.5 + 0.5)), marble)
	Kit.block(self, Vector3(3.6, H - 5.0, 1.0), Kit.xf(Vector3(0, 5.0 + (H - 5.0) * 0.5, L * 0.5 + 0.5)), marble)
	for p in Kit.prop_parts("large_castle_door"):
		Kit.mesh_node(self, p[0], null, Transform3D(Basis.IDENTITY.scaled(Vector3(1.8, 1.7, 1.5)), Vector3(0, 0, L * 0.5 + 0.3)) * p[1])
	# coffered ceiling: beams across and along
	Kit.block(self, Vector3(W + 2, 0.6, L + 2), Kit.xf(Vector3(0, H + 0.3, 0)), marble, false)
	for i in 9:
		Kit.mesh_node(self, Kit.box_mesh(Vector3(W, 0.7, 0.5), 0.04), dark_wood, Kit.xf(Vector3(0, H - 0.35, -L * 0.5 + 2.0 + i * 4.5)))
	for x in [-6.0, 0.0, 6.0]:
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.5, 0.6, L), 0.04), dark_wood, Kit.xf(Vector3(x, H - 0.35, 0)))


func _windows() -> void:
	# tall clerestory windows above the gallery with daylight shafts
	for sx: float in [-1.0, 1.0]:
		for i in 5:
			var z := -L * 0.5 + 4.0 + i * 8.0
			var pos := Vector3(sx * (W * 0.5 - 0.02), 10.5, z)
			Kit.mesh_node(self, Kit.box_mesh(Vector3(0.1, 4.6, 2.0), 0.01), Kit.emissive(Color(1.0, 0.95, 0.85), 2.2, true), Kit.xf(pos), false)
			Kit.mesh_node(self, Kit.lathe([Vector2(1.0, 0), Vector2(0.0, 0.001)], 12, false, false), Kit.emissive(Color(1.0, 0.95, 0.85), 2.2, true), Transform3D(Basis(Vector3.FORWARD, PI * 0.5 * sx), pos + Vector3(0, 2.3, 0)), false)
			if i % 2 == 0:
				var spot := SpotLight3D.new()
				spot.position = pos + Vector3(-sx * 0.3, 0, 0)
				spot.look_at_from_position(spot.position, Vector3(-sx * 4.0, 0.0, z + 2.0))
				spot.light_color = Color(1.0, 0.92, 0.78)
				spot.light_energy = 7.0
				spot.spot_range = 22.0
				spot.spot_angle = 12.0
				spot.light_volumetric_fog_energy = 2.5
				add_child(spot)


func _bookcases() -> void:
	var book_mesh := Kit.box_mesh(Vector3(0.05, 0.28, 0.2), 0.008)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = book_mesh
	var xs := []
	var cols := []
	var palette := [Color(0.38, 0.08, 0.06), Color(0.1, 0.16, 0.32), Color(0.12, 0.24, 0.12), Color(0.45, 0.32, 0.15), Color(0.2, 0.1, 0.07), Color(0.55, 0.45, 0.3), Color(0.28, 0.12, 0.3)]
	for tier in 2:
		var y_base := 0.0 if tier == 0 else 4.6
		for sx: float in [-1.0, 1.0]:
			var x := sx * (W * 0.5 - 0.35)
			for i in 9:
				var zc := -L * 0.5 + 2.4 + i * 4.3
				if tier == 0 and absf(zc) < 3.0:
					continue
				Kit.block(self, Vector3(0.55, 4.0, 3.9), Kit.xf(Vector3(x, y_base + 2.0, zc)), dark_wood, tier == 0, 0.02)
				for shelf in 6:
					var y := y_base + 0.22 + shelf * 0.62
					var z := zc - 1.8
					while z < zc + 1.8:
						var w := rng.randf_range(0.035, 0.075)
						var hgt := rng.randf_range(0.2, 0.32)
						xs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(rng.randf_range(0.8, 1.15), hgt / 0.28, w / 0.05)).rotated(Vector3.UP, PI * 0.5), Vector3(x - sx * 0.15, y + hgt * 0.5, z + w * 0.5)))
						cols.append(palette[rng.randi() % palette.size()] * rng.randf_range(0.75, 1.3))
						z += w + (0.002 if rng.randf() > 0.05 else 0.14)
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.6
	mmi.material_override = bm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _gallery() -> void:
	# upper gallery walkway with balustrade along both long walls (visual; reached by future stairs)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(2.0, 0.35, L), Kit.xf(Vector3(sx * (W * 0.5 - 1.3), 4.45, 0)), dark_wood, false, 0.02)
		Kit.block(self, Vector3(0.12, 0.12, L), Kit.xf(Vector3(sx * (W * 0.5 - 2.3), 5.6, 0)), wood, false, 0.01)
		for i in 40:
			Kit.mesh_node(self, Kit.lathe([Vector2(0.05, 0), Vector2(0.07, 0.15), Vector2(0.035, 0.6), Vector2(0.06, 0.95)], 6), wood, Kit.xf(Vector3(sx * (W * 0.5 - 2.3), 4.62, -L * 0.5 + 0.5 + i * 1.0)), false)
		for i in 5:
			Kit.mesh_node(self, Kit.lathe([Vector2(0.35, 0), Vector2(0.3, 4.3), Vector2(0.45, 4.5)], 12), marble, Kit.xf(Vector3(sx * (W * 0.5 - 2.3), 0, -L * 0.5 + 4.0 + i * 8.0)))
			Kit.static_box(self, Vector3(0.7, 4.4, 0.7), Kit.xf(Vector3(sx * (W * 0.5 - 2.3), 2.2, -L * 0.5 + 4.0 + i * 8.0)))


func _table(pos: Vector3, seed: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	Kit.block(self, Vector3(4.0, 0.1, 1.3), Kit.xf(pos + Vector3(0, 0.78, 0)), wood, false, 0.02)
	for c in [Vector2(-1.8, -0.5), Vector2(1.8, -0.5), Vector2(-1.8, 0.5), Vector2(1.8, 0.5)]:
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.1, 0.76, 0.1), 0.01), wood, Kit.xf(pos + Vector3(c.x, 0.38, c.y)))
	Kit.static_box(self, Vector3(4.0, 0.85, 1.3), Kit.xf(pos + Vector3(0, 0.42, 0)))
	for i in 3:
		var part := "book_encyclopedia_set_01_book%02d" % (1 + (seed + i * 3) % 19)
		Kit.mesh_node(self, Kit.prop("book_encyclopedia_set_01", part), null,
			Transform3D(Basis(Vector3.UP, r.randf_range(-0.8, 0.8)) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.2), pos + Vector3(-1.4 + i * 1.3, 0.84, r.randf_range(-0.3, 0.3))))
	Kit.mesh_node(self, Kit.prop("brass_candleholders", "brass_candleholder_01"), null, Kit.xf(pos + Vector3(0.2, 0.83, 0)))
	Kit.mesh_node(self, SphereMesh.new(), Kit.emissive(Color(1.0, 0.7, 0.35), 8.0, true), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.022), pos + Vector3(0.2, 1.22, 0)), false)
	if seed % 2 == 0:
		Kit.omni(self, pos + Vector3(0.2, 1.4, 0), Color(1.0, 0.7, 0.4), 0.8, 4.0)
	for sx: float in [-1.4, 0.0, 1.4]:
		for sz: float in [-0.95, 0.95]:
			Kit.mesh_node(self, Kit.prop("folding_wooden_stool"), null, Kit.xf(pos + Vector3(sx, 0, sz), r.randf_range(-0.3, 0.3)))


func _tables() -> void:
	var i := 0
	for z in [-12.0, -6.0, 6.0, 12.0]:
		for x in [-4.5, 4.5]:
			_table(Vector3(x, 0, z), i)
			i += 1
	Kit.place_prop_all(self, "GothicCabinet_01", Kit.xf(Vector3(-3.5, 0, -L * 0.5 + 0.6)), true)
	Kit.place_prop_all(self, "GothicCabinet_01", Kit.xf(Vector3(3.5, 0, -L * 0.5 + 0.6)), true)
	Kit.place_prop(self, "magnifying_glass_01", Kit.xf(Vector3(-4.0, 0.84, 6.2), 0.8, Vector3.ONE * 1.3))


func _crossing() -> void:
	var c := Vector3(0, 0, 0)
	rune_disc(c, 4.3, Color(0.95, 0.75, 0.4), Color(0.7, 0.5, 1.0), 77.0)
	Kit.mesh_node(self, Kit.lathe([Vector2(0.5, 0.12), Vector2(0.5, 0.3), Vector2(0.22, 0.4), Vector2(0.18, 1.05), Vector2(0.32, 1.12)], 8, false), marble, Kit.xf(c + Vector3(0, 0, -2.5)))
	Kit.static_box(self, Vector3(0.8, 1.15, 0.8), Kit.xf(c + Vector3(0, 0.57, -2.5)))
	Kit.mesh_node(self, Kit.prop("book_encyclopedia_set_01", "book_encyclopedia_set_01_book14"), null,
		Transform3D(Basis(Vector3.RIGHT, 0.4) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.5), c + Vector3(-0.12, 1.2, -2.5)))
	add_location("great_library", c, 22.0, c + Vector3(0, 0.12, 6.0))


func _lights() -> void:
	for z in [-12.0, 0.0, 12.0]:
		Kit.mesh_node(self, Kit.prop("Chandelier_02"), null, Kit.xf(Vector3(0, H - 3.4, z), 0.0, Vector3.ONE * 2.2))
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.04, 1.6, 0.04), 0.005), Kit.metal(Color(0.15, 0.12, 0.1), 0.5), Kit.xf(Vector3(0, H - 1.2, z)), false)
		Kit.omni(self, Vector3(0, H - 3.8, z), Color(1.0, 0.75, 0.48), 2.6, 16.0)


func _links() -> void:
	add_gate("academy", Vector3(0, 0.5, L * 0.5 + 0.9), Vector3(0, 0.05, L * 0.5 - 3.5), 0.0, 1.4)
	add_interactable(Interactable.make("rare_book_read", "Read the rare grimoire on the central lectern", "study", "great_library",
		Vector3(0, 0, -1.2), {"knowledge": {"spell:elemental_binding_theory": 1}, "skills": {"arcane_orb": 0.1}}, "look_around", 5.0)).radius = 2.0
	add_interactable(Interactable.make("library_research", "Research at a study table", "study", "great_library",
		Vector3(-4.5, 0, 7.4), {"knowledge": {"lore:academy_archives": 1}}, "", 5.0)).radius = 2.2
	add_interactable(Interactable.make("catalogue_search", "Search the catalogue cabinets", "inspect", "great_library",
		Vector3(-3.5, 0, -L * 0.5 + 2.2), {"knowledge": {"catalogue:great_library": 1}, "discover": ["ancient_vault", "cloud_temple"]}, "look_around", 3.5)).radius = 2.2


func showcase_shots(_loc: String) -> Array:
	return [[Vector3(-7, 2.0, 17), Vector3(2, 4.5, -14), 62.0], [Vector3(8, 1.7, 2), Vector3(-6, 6, -12), 60.0]]
