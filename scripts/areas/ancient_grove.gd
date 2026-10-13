extends KitArea
## B1 Ancient Grove + B4 Forgotten Forest Shrine (Enchanted Forest).
## Immense trees around a mossy clearing, a fallen giant, a brook, glowing glowcaps;
## to the north a raised runic shrine with guardian statues and glyph stones.

const SHRINE := Vector3(0, 0, -34)
const CLEARING := Vector3(0, 0, 6)

var stone: ShaderMaterial
var glyph_mats: Array = []


static func resources() -> Array:
	return textures(["forrest_ground_01", "stony_dirt_path", "bark_brown_02"]) + textures(["leafy_grass"], "2k") + textures(["mossy_rock"], "2k") + \
		models(["dead_tree_trunk_02", "root_cluster_01", "fern_02", "shrub_02", "rock_moss_set_01", "rock_moss_set_02", "gothic_statue", "tree_stump_02"]) + \
		[TREE_NEAR, TREE_FAR]


func env_preset() -> Dictionary:
	return {
		"day": {"sun_rot": Vector3(-38, -150, 0), "sun_energy": 2.0, "sun_color": Color(1.0, 0.9, 0.72), "fog": 0.006, "fog_color": Color(0.36, 0.46, 0.4),
			"vol_fog": 0.012, "vol_albedo": Color(0.9, 0.95, 0.85), "ambient": 0.8, "exposure": 0.95, "bg_energy": 0.6, "saturation": 1.1},
		"night": {"fog": 0.01, "fog_color": Color(0.04, 0.07, 0.1), "vol_fog": 0.015, "ambient": 1.4, "exposure": 1.3},
		"vista": {"ridge_height": 180.0, "green": Color(0.15, 0.24, 0.13), "haze": Color(0.5, 0.6, 0.62)},
	}


func height(x: float, z: float) -> float:
	var n := sin(x * 0.07) * 0.9 + cos(z * 0.09 + x * 0.03) * 0.8 + sin((x + z) * 0.17) * 0.25
	var flat := 1.0 - smoothstep(10.0, 18.0, Vector2(x - CLEARING.x, z - CLEARING.z).length())
	flat = maxf(flat, 1.0 - smoothstep(9.0, 15.0, Vector2(x - SHRINE.x, z - SHRINE.z).length()))
	flat = maxf(flat, 1.0 - smoothstep(1.5, 4.0, _path_dist(Vector2(x, z))))
	var brook := 1.0 - smoothstep(0.8, 3.0, absf(z - (-14.0 + sin(x * 0.12) * 3.0)))
	var rim := smoothstep(42.0, 58.0, Vector2(x, z).length()) * 5.0
	return n * (1.0 - flat) * 0.9 + rim - brook * 0.55


func _path_dist(p: Vector2) -> float:
	var segs := [[Vector2(0, 50), Vector2(1, 20)], [Vector2(1, 20), Vector2(0, -24)], [Vector2(4, 4), Vector2(48, -10)]]
	var best := 1e9
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return best


func build_steps() -> Array:
	return [_terrain, _brook, _giant_trees, _fallen_giant, _shrine, _glyph_stones, _undergrowth, _glowcaps, _links]


func _terrain() -> void:
	nav_aabb = AABB(Vector3(-50, -6, -50), Vector3(100, 20, 102))
	stone = Kit.tri("mossy_rock", "2k", 0.4, 0.95)
	magic_receivers = [stone]
	var mat := Kit.terrain_mat("leafy_grass", "forrest_ground_01", "stony_dirt_path", Color(0.7, 0.85, 0.62), Color(0.45, 0.52, 0.36), "2k")
	Kit.terrain(self, 130.0, 1.0, height, func(x, z):
		var p := Vector2(x, z)
		var path := 1.0 - smoothstep(0.8, 2.2, _path_dist(p))
		var forest := smoothstep(8.0, 16.0, p.distance_to(Vector2(CLEARING.x, CLEARING.z))) * 0.85
		return Color(path, forest, 0.0), mat)
	boundary_circle(Vector3.ZERO, 54.0)


func _brook() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(110, 7)
	pm.subdivide_width = 40
	w.mesh = pm
	w.material_override = Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.12, 0.22, 0.18), "deep": Color(0.02, 0.05, 0.05), "clarity": 0.8, "flow": Vector2(0.08, 0.01)})
	w.position = Vector3(0, -0.42, -14.0)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)
	# stepping stones where the path crosses
	for i in 4:
		var p := Vector3(0.6 + (i % 2) * 0.5, 0, -16.0 + i * 1.3)
		var mi := Kit.mesh_node(self, Kit.rock_mesh(0.45, 300 + i, 0.25, Vector3(1.2, 0.45, 1.0)), stone, Kit.xf(Vector3(p.x, height(p.x, p.z) + 0.1, p.z), i))
		Kit.convex_collide(mi)


func _giant_trees() -> void:
	var spots := [Vector2(-13, 2), Vector2(14, 9), Vector2(-9, 19), Vector2(12, -6), Vector2(-17, -9), Vector2(20, 22), Vector2(-24, 28),
		Vector2(26, -22), Vector2(-28, -24), Vector2(8, -46), Vector2(-14, -45), Vector2(32, 6), Vector2(-34, 6), Vector2(18, 36), Vector2(-6, 38)]
	var budget := 1.0 if RenderProfile.profile != RenderProfile.LIVE_OPTIMIZED else 0.75
	for i in int(spots.size() * budget):
		var p: Vector2 = spots[i]
		var s := rng.randf_range(2.0, 2.8) if i < 6 else rng.randf_range(1.4, 2.1)
		tree(Vector3(p.x, height(p.x, p.y) - 0.3, p.y), s, rng.randf() * TAU, i < 8)
		# moss-wrapped root flare around the biggest trunks
		if i < 6:
			var root := Kit.place_prop(self, "root_cluster_01", Kit.xf(Vector3(p.x, height(p.x, p.y) - 0.15, p.y), rng.randf() * TAU, Vector3.ONE * 0.9))
			root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_location("ancient_grove", CLEARING, 22.0, Vector3(CLEARING.x + 2.0, height(2.0, 6.0), CLEARING.z))


func _fallen_giant() -> void:
	var log := Kit.place_prop(self, "dead_tree_trunk_02", Kit.xf(Vector3(-11, height(-11, 13) - 0.2, 13), 0.5, Vector3.ONE * 2.6), "", true)
	Kit.place_prop(self, "tree_stump_02", Kit.xf(Vector3(9.5, height(9.5, 15), 15), 1.2, Vector3.ONE * 1.8), "", true)
	var r1 := "rock_moss_set_01"
	for spec in [[Vector3(-7, 0, -3), "rock_moss_set_01_rock02", 1.6], [Vector3(16, 0, 0), "rock_moss_set_01_rock05", 1.9], [Vector3(-20, 0, 16), "rock_moss_set_01_rock04", 1.7],
			[Vector3(6, 0, 22), "rock_moss_set_01_rock06", 1.4], [Vector3(24, 0, -14), "rock_moss_set_01_rock01", 2.1]]:
		var p: Vector3 = spec[0]
		Kit.place_prop(self, r1, Kit.xf(Vector3(p.x, height(p.x, p.z) - 0.3, p.z), rng.randf() * TAU, Vector3.ONE * spec[2]), spec[1], true)


func _shrine() -> void:
	var c := SHRINE
	var y0 := height(c.x, c.z)
	var plat_h := 2.2
	# raised terrace with front stairs
	Kit.block(self, Vector3(16, plat_h, 10), Kit.xf(Vector3(c.x, y0 + plat_h * 0.5 - 0.3, c.z - 2)), stone, true, 0.08)
	stairs(Vector3(c.x, y0 - 0.3, c.z + 3.0 + 11 * 0.42), 0.0, 5.0, 11, 0.2, 0.42, stone)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(1.2, 1.4, 4.8), Kit.xf(Vector3(c.x + sx * 3.1, y0 + 0.3, c.z + 5.3)), stone, true, 0.06)
	var top := y0 + plat_h - 0.3
	# facade: wall with arched doorway and niches
	Kit.block(self, Vector3(14, 6.5, 1.6), Kit.xf(Vector3(c.x, top + 3.25, c.z - 6.2)), stone, true, 0.08)
	Kit.mesh_node(self, Kit.box_mesh(Vector3(2.6, 3.4, 0.3), 0.01), Kit.emissive(Color(0.01, 0.012, 0.018), 0.0), Kit.xf(Vector3(c.x, top + 1.7, c.z - 5.35)), false)
	arch(Vector3(c.x, top + 3.4, c.z - 5.3), 0.0, 2.6, 0.55, 0.9, stone, 9)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(0.6, 3.4, 0.9), Kit.xf(Vector3(c.x + sx * 1.6, top + 1.7, c.z - 5.3)), stone, true, 0.05)
		# guardian statues in niches flanking the door
		Kit.block(self, Vector3(2.2, 0.5, 1.6), Kit.xf(Vector3(c.x + sx * 4.6, top + 0.25, c.z - 4.6)), stone, true, 0.05)
		Kit.place_prop(self, "gothic_statue", Kit.xf(Vector3(c.x + sx * 4.6, top + 0.5, c.z - 4.6), PI + sx * 0.25, Vector3.ONE * 1.35), "", false)
		# broken pillars
		var ph := 3.5 + sx * 1.2
		Kit.mesh_node(self, Kit.lathe([Vector2(0.45, 0), Vector2(0.42, ph), Vector2(0.3, ph + 0.25)], 14, true), stone, Kit.xf(Vector3(c.x + sx * 6.3, top, c.z - 3.0)))
		Kit.static_box(self, Vector3(0.8, ph, 0.8), Kit.xf(Vector3(c.x + sx * 6.3, top + ph * 0.5, c.z - 3.0)))
	# cornice with missing blocks
	for i in 9:
		if i == 2 or i == 6:
			continue
		Kit.block(self, Vector3(1.5, 0.6, 1.9), Kit.xf(Vector3(c.x - 6.0 + i * 1.5, top + 6.8, c.z - 6.2)), stone, false, 0.05)
	# altar stone in front of the door with a glowing rune plate
	Kit.block(self, Vector3(1.6, 0.9, 0.9), Kit.xf(Vector3(c.x, top + 0.45, c.z - 2.4)), stone, true, 0.05)
	var g := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	g.mesh = q
	g.material_override = _glyph_mat(Color(0.35, 0.9, 0.75), 6)
	g.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(c.x, top + 0.91, c.z - 2.4))
	add_child(g)
	Kit.omni(self, Vector3(c.x, top + 1.6, c.z - 2.2), Color(0.4, 1.0, 0.8), 0.9, 6.0)
	add_location("forgotten_forest_shrine", Vector3(c.x, 0, c.z), 14.0, Vector3(c.x, top, c.z - 0.8))
	add_poi("shrine_stairs", Vector3(c.x, y0, c.z + 11.5), "Foot of the shrine stairs", "forgotten_forest_shrine")


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
	for i in 5:
		var a := -PI * 0.5 + (i - 2) * 0.42
		var p := SHRINE + Vector3(cos(a) * 11.0, 0, -sin(a) * 11.0 + 9.0)
		var y := height(p.x, p.z)
		var yaw := atan2(SHRINE.x - p.x, SHRINE.z + 9.0 - p.z)
		var sb := Kit.block(self, Vector3(1.1, 2.6, 0.5), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, rng.randf_range(-0.06, 0.06)), Vector3(p.x, y + 1.1, p.z)), stone, true, 0.08)
		var g := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.75, 0.75)
		g.mesh = q
		g.material_override = _glyph_mat(Color(0.3, 0.85, 0.7), 3 + i)
		g.transform = Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(p.x, y + 1.5, p.z) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.27))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)


func _undergrowth() -> void:
	var h := height
	var not_path := func(p: Vector2) -> bool: return _path_dist(p) > 2.0 and p.distance_to(Vector2(SHRINE.x, SHRINE.z)) > 10.0
	for part in ["fern_02_a", "fern_02_b", "fern_02_c", "fern_02_d"]:
		scatter("fern_02", part, 90, Vector2.ZERO, 8.0, 50.0, 1.0, 2.2, h, not_path, 45.0)
	for part in ["shrub_02_a", "shrub_02_b", "shrub_02_c"]:
		scatter("shrub_02", part, 22, Vector2.ZERO, 18.0, 52.0, 0.9, 1.6, h, not_path, 70.0)


func _glowcaps() -> void:
	# small bioluminescent mushrooms around roots and the brook (original, built from lathes)
	var cap := Kit.lathe([Vector2(0.0, 0.0), Vector2(0.025, 0.0), Vector2(0.022, 0.09), Vector2(0.09, 0.1), Vector2(0.075, 0.14), Vector2(0.0, 0.16)], 10)
	var xs := []
	for i in int(260 * float(RenderProfile.get_setting("foliage_density"))):
		var base: Vector2 = [Vector2(-13, 2), Vector2(14, 9), Vector2(-9, 19), Vector2(-11, 13), Vector2(0, -14), Vector2(12, -6)][i % 6]
		var p: Vector2 = base + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 4.5)
		var s := rng.randf_range(0.6, 1.8)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height(p.x, p.y) - 0.02, p.y)))
	Kit.multimesh(self, cap, xs, 40.0, false, Kit.emissive(Color(0.35, 0.75, 1.0), 2.2))
	add_poi("glowcap_patch", Vector3(-12, height(-12, 4), 4), "Patch of glowing mushrooms at the giant tree roots", "ancient_grove")


func _links() -> void:
	add_gate("whispering_woods", Vector3(0.0, height(0, 50), 50.0), Vector3(0.6, height(0.6, 43) + 0.05, 43.0), 0.0, 2.6)
	add_gate("river_valley", Vector3(48.0, height(48, -10), -10.0), Vector3(42.0, height(42, -8.6) + 0.05, -8.6), atan2(42.0, -8.6), 2.6)
	add_interactable(Interactable.make("giant_tree_listen", "Rest a hand on the eldest tree and listen", "meditate", "ancient_grove",
		Vector3(-11.6, height(-11.6, 3.0), 3.0), {"knowledge": {"lore:grove_whispers": 1}}, "look_around", 4.0)).radius = 2.4
	add_interactable(Interactable.make("collect_glowcap", "Gather a glowcap mushroom", "collect", "ancient_grove",
		Vector3(-12, height(-12, 4.5), 4.5), {"items": {"glowcap": 1}}, "", 2.0)).radius = 2.6
	var top := height(SHRINE.x, SHRINE.z) + 1.9
	add_interactable(Interactable.make("shrine_glyphs_read", "Read the runic glyphs on the shrine stones", "study", "forgotten_forest_shrine",
		Vector3(SHRINE.x, top, SHRINE.z - 1.6), {"knowledge": {"lore:runic_script": 1}}, "look_around", 4.0)).radius = 2.4
	var offer := Interactable.make("shrine_offering", "Leave a glowcap as an offering at the shrine altar", "pray", "forgotten_forest_shrine",
		Vector3(SHRINE.x, top, SHRINE.z - 1.6), {"skills": {"arcane_orb": 0.2}, "knowledge": {"blessing:forest_shrine": 1}}, "spell_casting", 4.2)
	offer.requires = {"items": {"glowcap": 1}}
	offer.radius = 2.4
	offer.on_done = func():
		for m in glyph_mats:
			m.set_shader_parameter("intensity", 2.2)
	add_interactable(offer)
