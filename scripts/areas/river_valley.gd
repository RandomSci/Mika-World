extends KitArea
## B2 Luminous River + B3 Waterfall Crossing (Enchanted Forest).
## A green valley under a cliff: twin waterfalls fall ~20 m into a misty pool, a river meanders
## south past glowing reeds and stepping stones, and an arched stone bridge carries the road east.

const BRIDGE_Z := -5.0
const FALLS_Z := -26.0

var stone: ShaderMaterial
var rock: ShaderMaterial


static func resources() -> Array:
	return textures(["forrest_ground_01", "rock_wall_10", "cliff_side", "castle_wall_slates"]) + textures(["leafy_grass", "cliff_side"], "2k") + \
		models(["fern_02", "shrub_02", "rock_moss_set_01", "rock_moss_set_02", "namaqualand_cliff_01", "boulder_01"]) + [TREE_NEAR, TREE_FAR]


func env_preset() -> Dictionary:
	return {
		"day": {"sun_rot": Vector3(-34, 150, 0), "sun_energy": 2.2, "fog": 0.003, "fog_color": Color(0.55, 0.65, 0.7), "vol_fog": 0.006, "exposure": 0.95, "bg_energy": 0.7, "saturation": 1.08},
		"night": {"fog": 0.006, "fog_color": Color(0.05, 0.08, 0.13), "vol_fog": 0.01, "ambient": 1.5, "exposure": 1.35},
		"vista": {"mountains": true, "ridge_height": 320.0, "green": Color(0.16, 0.25, 0.14), "haze": Color(0.56, 0.66, 0.74), "snow_line": 300.0},
	}


func river_x(z: float) -> float:
	return sin(z * 0.07) * 4.5 + sin(z * 0.19) * 1.2


func height(x: float, z: float) -> float:
	var dr := absf(x - river_x(z))
	var bed := -1.6 * (1.0 - smoothstep(2.0, 8.0, dr))  # banks ≈22°: inside the 30° nav slope limit
	var cliff := smoothstep(-16.0, -24.0, z) * 21.0
	var sides := smoothstep(26.0, 46.0, absf(x)) * 7.0 * (1.0 - smoothstep(-4.0, 4.0, absf(z - BRIDGE_Z) - 3.0) * 0.0)
	var road := 1.0 - smoothstep(2.5, 6.0, absf(z - BRIDGE_Z))
	sides *= 1.0 - road * 0.85
	var bumps := sin(x * 0.21) * cos(z * 0.17) * 0.35
	var pool := (1.0 - smoothstep(5.0, 10.0, Vector2(x, z - FALLS_Z - 5.0).length())) * -1.4
	return minf(bed + pool, 0.0) * (1.0 - smoothstep(-15.0, -20.0, z) * 0.0) + cliff + sides + bumps * (1.0 - road)


func build_steps() -> Array:
	return [_terrain, _water, _cliffs, _falls, _bridge, _river_life, _trees, _links]


func _terrain() -> void:
	nav_aabb = AABB(Vector3(-48, -4, -24), Vector3(96, 16, 70))
	stone = Kit.tri("castle_wall_slates", "1k", 0.45, 0.6, Color(0.92, 0.9, 0.86))
	rock = Kit.tri("cliff_side", "2k", 0.12, 0.35)
	magic_receivers = [stone, rock]
	var mat := Kit.terrain_mat("leafy_grass", "forrest_ground_01", "rock_wall_10", Color(0.78, 0.9, 0.66), Color(0.5, 0.56, 0.42), "2k")
	Kit.terrain(self, 120.0, 1.0, height, func(x, z):
		var dr := absf(x - river_x(z))
		var bank := 1.0 - smoothstep(3.5, 6.0, dr)
		var steep := smoothstep(-15.0, -19.0, z)
		var road := (1.0 - smoothstep(1.5, 3.2, absf(z - BRIDGE_Z))) * smoothstep(6.0, 9.0, absf(x))
		return Color(maxf(bank, steep), maxf(road, smoothstep(30.0, 45.0, absf(x)) * 0.8), 0.0), mat)
	boundary_box(Vector3(0, 0, 8), Vector3(96, 12, 72))


func _water() -> void:
	var wm := Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.12, 0.3, 0.28), "deep": Color(0.02, 0.07, 0.08), "clarity": 1.2,
		"flow": Vector2(0.0, 0.12), "glow_color": Color(0.2, 0.7, 0.6), "glow": 0.15})
	for seg in 12:
		var z0 := -22.0 + seg * 6.0
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(11.0, 6.4)
		w.mesh = pm
		w.material_override = wm
		w.position = Vector3(river_x(z0 + 3.0), -0.75, z0 + 3.0)
		w.rotation.y = -atan(cos((z0 + 3.0) * 0.07) * 0.07 * 4.5)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
	var pool := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 9.5
	cm.bottom_radius = 9.5
	cm.height = 0.02
	cm.radial_segments = 48
	pool.mesh = cm
	pool.material_override = wm
	pool.position = Vector3(0, -0.74, FALLS_Z + 5.0)
	add_child(pool)


func _cliffs() -> void:
	for i in 9:
		var x := -40.0 + i * 10.0 + rng.randf_range(-2, 2)
		if absf(x) < 7.0:
			continue
		var s := rng.randf_range(2.6, 3.6)
		Kit.place_prop(self, "namaqualand_cliff_01", Kit.xf(Vector3(x, height(x, -19.0) - 2.0, -19.5 + rng.randf_range(-1, 1)), rng.randf_range(-0.3, 0.3) + (PI if i % 2 else 0.0), Vector3(s, s * 1.4, s)), "", true)
	for p in [Vector3(-7.5, 0, -22), Vector3(7.5, 0, -22), Vector3(-12, 0, -14), Vector3(13, 0, -12)]:
		Kit.place_prop(self, "boulder_01", Kit.xf(Vector3(p.x, height(p.x, p.z) - 0.4, p.z), rng.randf() * TAU, Vector3.ONE * rng.randf_range(1.6, 2.4)), "", true)


func _falls() -> void:
	var fm := Kit.shader_mat("res://shaders/waterfall.gdshader", {"speed": 1.2})
	for spec in [[-3.2, 5.5, 20.5], [3.6, 3.8, 18.0]]:
		var w := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(spec[1], spec[2])
		w.mesh = qm
		w.material_override = fm
		w.position = Vector3(spec[0], -0.7 + spec[2] * 0.5, FALLS_Z + 0.6)
		w.rotation.x = -0.05
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
		# spray / mist at the base
		var p := GPUParticles3D.new()
		p.amount = 60
		p.lifetime = 2.2
		p.position = Vector3(spec[0], -0.3, FALLS_Z + 1.5)
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(spec[1] * 0.4, 0.2, 0.6)
		pm.direction = Vector3(0, 1, 0.6)
		pm.spread = 35.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 1.6
		pm.gravity = Vector3(0, -0.15, 0)
		pm.scale_min = 2.0
		pm.scale_max = 4.0
		var grad := Gradient.new()
		grad.set_color(0, Color(0.85, 0.9, 0.95, 0.35))
		grad.set_color(1, Color(0.85, 0.9, 0.95, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		pm.color_ramp = gt
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/magic/energy_mote.gdshader")
		sm.set_shader_parameter("hdr_boost", 0.35)
		q.material = sm
		p.draw_pass_1 = q
		p.visibility_aabb = AABB(Vector3(-6, -1, -3), Vector3(12, 8, 8))
		add_child(p)
	# lip of the cliff above the falls
	Kit.mesh_node(self, Kit.rock_mesh(1.0, 77, 0.3, Vector3(9, 2.2, 3.5)), rock, Kit.xf(Vector3(0, 19.8, FALLS_Z - 0.8)))
	add_location("waterfall_crossing", Vector3(0, 0, BRIDGE_Z - 6.0), 16.0, Vector3(-15.5, height(-15.5, BRIDGE_Z - 3.5), BRIDGE_Z - 3.5))
	add_poi("bridge_crown", Vector3(0, 2.75, BRIDGE_Z), "Top of the stone bridge, facing the twin waterfalls", "waterfall_crossing")


func _bridge() -> void:
	var z := BRIDGE_Z
	var deck_y := 2.4
	arch(Vector3(0, deck_y - 0.5 - 4.5 - 0.9, z), 0.0, 9.0, 0.9, 3.4, stone, 11)  # crown sits just under the deck
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(1.6, 4.0, 3.6), Kit.xf(Vector3(sx * 5.4, 0.2, z)), stone, true, 0.06)  # abutments
	Kit.block(self, Vector3(13.0, 0.5, 3.6), Kit.xf(Vector3(0, deck_y - 0.25, z)), stone, true, 0.05)
	for sz: float in [-1.0, 1.0]:
		for i in 7:
			Kit.block(self, Vector3(1.75, 0.75, 0.32), Kit.xf(Vector3(-5.4 + i * 1.8, deck_y + 0.37, z + sz * 1.62)), stone, true, 0.04)
	# ramps down to both banks (smooth collision, stepped-looking slabs)
	for sx: float in [-1.0, 1.0]:
		var top := Vector3(sx * 6.5, deck_y, z)
		var bottom_x := sx * 13.0
		var bottom := Vector3(bottom_x, height(bottom_x, z), z)
		var len := Vector2(bottom.x - top.x, bottom.y - top.y).length()
		var ang := atan2(top.y - bottom.y, absf(top.x - bottom.x))
		var mid := (top + bottom) * 0.5
		var b := Basis(Vector3.FORWARD, -ang * sx)
		Kit.block(self, Vector3(len + 0.4, 0.4, 3.4), Transform3D(b, mid - b * Vector3(0, 0.2, 0)), stone, true, 0.04)
		for k in 4:
			Kit.block(self, Vector3(0.3, 0.7, 0.3), Kit.xf(bottom.lerp(top, 0.2 + k * 0.2) + Vector3(0, 0.35, 1.6)), stone, true, 0.03)
			Kit.block(self, Vector3(0.3, 0.7, 0.3), Kit.xf(bottom.lerp(top, 0.2 + k * 0.2) + Vector3(0, 0.35, -1.6)), stone, true, 0.03)
	# lanterns on the bridge crown
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(Vector3(sx * 5.4, deck_y + 0.75, z + 1.62), 0.0, Vector3.ONE * 1.6))
		night_only(Kit.omni(self, Vector3(sx * 5.4, deck_y + 1.1, z + 1.62), Color(1.0, 0.68, 0.36), 1.0, 6.0))


func _river_life() -> void:
	# luminous reeds: thin stalks with glowing seed heads along both banks
	var reed := Kit.lathe([Vector2(0.012, 0), Vector2(0.008, 1.1), Vector2(0.03, 1.15), Vector2(0.025, 1.32), Vector2(0.0, 1.38)], 5)
	var xs := []
	for i in int(380 * float(RenderProfile.get_setting("foliage_density"))):
		var z := rng.randf_range(-14.0, 38.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := river_x(z) + side * rng.randf_range(3.6, 5.6)
		if absf(z - BRIDGE_Z) < 3.0:
			continue
		var s := rng.randf_range(0.6, 1.2)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.15, 0.15)).scaled(Vector3.ONE * s), Vector3(x, height(x, z) - 0.05, z)))
	Kit.multimesh(self, reed, xs, 45.0, false, Kit.emissive(Color(0.35, 0.95, 0.75), 1.6))
	# stepping stones crossing the river downstream
	for i in 6:
		var z := 20.0 + (i % 2) * 0.7
		var x := river_x(z) - 4.0 + i * 1.5
		var mi := Kit.mesh_node(self, Kit.rock_mesh(0.55, 500 + i, 0.25, Vector3(1.2, 0.6, 1.0)), stone, Kit.xf(Vector3(x, -0.55, z), i))
		Kit.convex_collide(mi)
	add_location("luminous_river", Vector3(river_x(20.0), 0, 20.0), 18.0, Vector3(river_x(20.0) - 7.0, height(river_x(20.0) - 7.0, 20.0), 20.0))
	add_poi("stepping_stones", Vector3(river_x(20.0) - 4.0, 0.0, 20.0), "Stepping stones across the river", "luminous_river")


func _trees() -> void:
	for p in [Vector2(-20, 12), Vector2(18, 16), Vector2(-24, -8), Vector2(24, -10), Vector2(-14, 30), Vector2(16, 34), Vector2(-34, 22), Vector2(34, 26)]:
		tree(Vector3(p.x, height(p.x, p.y) - 0.2, p.y), rng.randf_range(1.1, 1.6), rng.randf() * TAU, true)
	var h := height
	var ok := func(p: Vector2) -> bool: return absf(p.x - river_x(p.y)) > 5.5 and absf(p.y - BRIDGE_Z) > 4.0 and p.y > -15.0
	for part in ["fern_02_a", "fern_02_b", "fern_02_c"]:
		scatter("fern_02", part, 70, Vector2(0, 10), 6.0, 40.0, 1.0, 1.9, h, ok, 45.0)
	for part in ["shrub_02_a", "shrub_02_c"]:
		scatter("shrub_02", part, 18, Vector2(0, 10), 12.0, 42.0, 0.9, 1.5, h, ok, 70.0)


func _links() -> void:
	add_gate("ancient_grove", Vector3(-45.0, height(-45, BRIDGE_Z), BRIDGE_Z), Vector3(-39.0, height(-39, BRIDGE_Z) + 0.05, BRIDGE_Z), -PI * 0.5, 2.6)
	add_gate("village", Vector3(45.0, height(45, BRIDGE_Z), BRIDGE_Z), Vector3(39.0, height(39, BRIDGE_Z) + 0.05, BRIDGE_Z), PI * 0.5, 2.6)
	add_interactable(Interactable.make("collect_river_water", "Fill a flask with luminous river water", "collect", "luminous_river",
		Vector3(river_x(16.0) - 4.6, height(river_x(16.0) - 4.6, 16.0), 16.0), {"items": {"luminous_water": 1}}, "", 2.5)).radius = 2.4
	add_interactable(Interactable.make("reeds_study", "Study the glowing reeds", "study", "luminous_river",
		Vector3(river_x(26.0) + 5.0, height(river_x(26.0) + 5.0, 26.0), 26.0), {"knowledge": {"lore:luminous_reeds": 1}}, "look_around", 3.5)).radius = 2.4
	add_interactable(Interactable.make("falls_meditate", "Meditate on the bridge before the falls", "meditate", "waterfall_crossing",
		Vector3(0, 2.4, BRIDGE_Z), {"skills": {"arcane_orb": 0.1}, "knowledge": {"calm:waterfall": 1}}, "", 4.0)).radius = 2.2


func showcase_shots(loc: String) -> Array:
	if loc == "waterfall_crossing":
		return [[Vector3(-16, 4.5, 14), Vector3(0, 6, FALLS_Z), 55.0], [Vector3(10, 2.2, 6), Vector3(-2, 4, BRIDGE_Z - 4), 55.0]]
	return [[Vector3(river_x(30.0) + 9, 2.4, 34), Vector3(river_x(14.0), 0.5, 12), 55.0]]
