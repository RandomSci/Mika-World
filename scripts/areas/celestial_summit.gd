extends KitArea
## E3 Celestial Observatory + E4 Cloud Temple (Celestial Highlands).
## A summit plateau floating above the sea of clouds: a brass armillary sphere and stone star dial,
## and a tiered temple with flared roofs, lanterns and a sanctum at the cliff edge.

const OBS := Vector3(-12, 0, 4)
const TEMPLE := Vector3(8, 0, -16)
const SKY := "res://assets/polyhaven/hdris/belfast_sunset_puresky/belfast_sunset_puresky_2k.hdr"

var stone: ShaderMaterial
var roof: StandardMaterial3D
var wood: ShaderMaterial
var rings: Array[Node3D] = []


static func resources() -> Array:
	return textures(["castle_wall_slates", "roof_slates_02", "rocky_terrain_02", "rock_wall_10", "stony_dirt_path", "dark_wooden_planks", "large_grey_tiles"]) + \
		textures(["cliff_side", "monastery_stone_floor"], "2k") + models(["Lantern_01", "namaqualand_boulder_02", "brass_candleholders", "gothic_statue"]) + [SKY]


func env_preset() -> Dictionary:
	return {"sky_day": SKY,
		"day": {"sun_rot": Vector3(-12, -70, 0), "sun_energy": 2.4, "sun_color": Color(1.0, 0.74, 0.5), "fog": 0.0008, "fog_color": Color(0.85, 0.72, 0.62), "vol_fog": 0.0, "exposure": 0.95, "bg_energy": 0.9, "saturation": 1.08},
		"night": {"fog": 0.0015, "ambient": 1.6, "exposure": 1.4, "bg_energy": 1.3},
		"vista": {"mountains": true, "ridge_height": 300.0, "ridge_base": -420.0, "ridge_seed": 44, "snow_line": -120.0, "haze": Color(0.86, 0.74, 0.68), "cloud_sea": -55.0}}


func height(x: float, z: float) -> float:
	var d := Vector2(x / 34.0, (z + 4.0) / 30.0).length()
	return sin(x * 0.17) * 0.3 + cos(z * 0.21) * 0.3 - smoothstep(0.92, 1.15, d) * 50.0


func build_steps() -> Array:
	return [_ground, _cliff_body, _observatory, _temple_base, _temple_hall, _temple_roofs, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-34, -4, -36), Vector3(68, 24, 66))
	stone = Kit.tri("castle_wall_slates", "1k", 0.45, 0.12, Color(0.9, 0.88, 0.84))
	roof = Kit.uvmat("roof_slates_02", "1k", Vector2(4, 3), Color(0.55, 0.6, 0.62))
	wood = Kit.tri("dark_wooden_planks", "1k", 0.7, 0.0, Color(0.5, 0.28, 0.2))
	magic_receivers = [stone]
	var mat := Kit.terrain_mat("rocky_terrain_02", "rock_wall_10", "stony_dirt_path", Color(0.85, 0.88, 0.76), Color(0.6, 0.6, 0.62))
	Kit.terrain(self, 90.0, 1.0, height, func(x, z):
		var path := 1.0 - smoothstep(1.2, 2.5, absf(x * 0.5 + (z - 20.0) * 0.0) if z > -4.0 and z < 30.0 and absf(x) < 3.0 else 9.0)
		return Color(path, smoothstep(0.85, 1.0, Vector2(x / 34.0, (z + 4.0) / 30.0).length()), 0.0), mat)
	boundary_circle(Vector3(0, 0, -4), 29.5)


func _cliff_body() -> void:
	# the plateau's rocky underside, seen from the edges above the clouds
	var mi := Kit.mesh_node(self, Kit.rock_mesh(1.0, 1300, 0.35, Vector3(36, 46, 32), 3), Kit.tri("cliff_side", "2k", 0.06, 0.0), Kit.xf(Vector3(0, -46, -4)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		var p := Vector3(cos(a) * 30.0, 0, -4.0 + sin(a) * 26.0)
		Kit.place_prop(self, "namaqualand_boulder_02", Kit.xf(Vector3(p.x, height(p.x, p.z) - 0.3, p.z), a, Vector3.ONE * rng.randf_range(2.0, 3.5)), "", true)


func _observatory() -> void:
	var c := Vector3(OBS.x, height(OBS.x, OBS.z), OBS.z)
	rune_disc(c, 4.3, Color(0.9, 0.75, 0.45), Color(0.7, 0.55, 1.0), 33.0)
	var brass := Kit.metal(Color(0.8, 0.6, 0.32), 0.25)
	Kit.mesh_node(self, Kit.lathe([Vector2(0.6, 0.1), Vector2(0.55, 0.3), Vector2(0.25, 0.45), Vector2(0.2, 1.4), Vector2(0.35, 1.5)], 12, false), stone, Kit.xf(c))
	Kit.static_box(self, Vector3(0.9, 1.5, 0.9), Kit.xf(c + Vector3(0, 0.75, 0)))
	var sphere_root := Node3D.new()
	sphere_root.position = c + Vector3(0, 2.6, 0)
	add_child(sphere_root)
	for i in 3:
		var t := TorusMesh.new()
		t.inner_radius = 0.95 - i * 0.15
		t.outer_radius = 1.02 - i * 0.15
		t.rings = 48
		t.ring_segments = 6
		var ring := Node3D.new()
		ring.rotation = Vector3(PI * 0.5 * (i % 2), i * 0.6, 0.41 * i)
		sphere_root.add_child(ring)
		Kit.mesh_node(ring, t, brass, Transform3D.IDENTITY)
		rings.append(ring)
	Kit.mesh_node(sphere_root, SphereMesh.new(), Kit.emissive(Color(0.7, 0.8, 1.0), 4.0, true), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.18), Vector3.ZERO), false)
	Kit.mesh_node(sphere_root, Kit.lathe([Vector2(0.03, -1.1), Vector2(0.03, 1.1)], 6), brass, Transform3D(Basis(Vector3.FORWARD, 0.41), Vector3.ZERO))
	Kit.omni(self, c + Vector3(0, 2.6, 0), Color(0.75, 0.82, 1.0), 1.2, 7.0)
	# star dial: stone disc with a gnomon
	var dial := c + Vector3(6.5, 0, 2.0)
	Kit.mesh_node(self, Kit.lathe([Vector2(1.3, 0), Vector2(1.3, 0.7), Vector2(1.45, 0.78), Vector2(1.45, 0.86), Vector2(0, 0.86)], 32), stone, Kit.xf(Vector3(dial.x, height(dial.x, dial.z), dial.z)))
	Kit.static_box(self, Vector3(2.4, 0.9, 2.4), Kit.xf(Vector3(dial.x, height(dial.x, dial.z) + 0.45, dial.z)))
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.06, 0.7, 1.0), 0.01), brass, Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(dial.x, height(dial.x, dial.z) + 1.1, dial.z)))
	add_location("celestial_observatory", OBS, 10.0, c + Vector3(0, 0.12, 5.2))


func _process(delta: float) -> void:
	for i in rings.size():
		rings[i].rotate_object_local(Vector3.UP, delta * (0.15 + i * 0.07))


func _temple_base() -> void:
	var y0 := height(TEMPLE.x, TEMPLE.z)
	for tier in 3:
		var w := 20.0 - tier * 2.4
		var d := 15.0 - tier * 2.0
		Kit.block(self, Vector3(w, 0.5 + (2 - tier) * 0.0, d), Kit.xf(Vector3(TEMPLE.x, y0 + 0.25 + tier * 0.5, TEMPLE.z - tier * 0.4)), stone, false, 0.05)
	Kit.block(self, Vector3(20, 0.5, 15), Kit.xf(Vector3(TEMPLE.x, y0 - 0.25, TEMPLE.z)), stone, false, 0.05)  # skirt into the ground
	Kit.static_box(self, Vector3(15.2, 1.5, 11.0), Kit.xf(Vector3(TEMPLE.x, y0 + 0.75, TEMPLE.z - 0.8)))  # walkable podium top = y0 + 1.5
	stairs(Vector3(TEMPLE.x, y0, TEMPLE.z + 4.7 + 8 * 0.45), 0.0, 5.0, 8, 0.1875, 0.45, stone)


func _temple_hall() -> void:
	var y := height(TEMPLE.x, TEMPLE.z) + 1.5
	for ix in 4:
		for iz in 3:
			if iz == 1 and (ix == 1 or ix == 2):
				continue
			var p := TEMPLE + Vector3(-5.4 + ix * 3.6, 0, 3.0 - iz * 3.4)
			Kit.mesh_node(self, Kit.lathe([Vector2(0.38, 0), Vector2(0.32, 0.25), Vector2(0.3, 4.3), Vector2(0.42, 4.5)], 12), wood, Kit.xf(Vector3(p.x, y, p.z)))
			Kit.static_box(self, Vector3(0.7, 4.5, 0.7), Kit.xf(Vector3(p.x, y + 2.25, p.z)))
	Kit.block(self, Vector3(11.8, 4.5, 0.4), Kit.xf(TEMPLE + Vector3(0, y - TEMPLE.y + 2.25, -4.0)), stone, true, 0.03)
	Kit.block(self, Vector3(12.6, 0.5, 8.6), Kit.xf(TEMPLE + Vector3(0, y - TEMPLE.y + 4.7, -0.4)), wood, false, 0.04)
	# sanctum altar with incense candles
	Kit.block(self, Vector3(2.2, 1.0, 1.0), Kit.xf(TEMPLE + Vector3(0, y - TEMPLE.y + 0.5, -2.8)), stone, true, 0.04)
	Kit.place_prop(self, "brass_candleholders", Kit.xf(TEMPLE + Vector3(-0.6, y - TEMPLE.y + 1.0, -2.8)), "brass_candleholder_03")
	Kit.omni(self, TEMPLE + Vector3(0, y - TEMPLE.y + 2.2, -2.0), Color(1.0, 0.68, 0.4), 1.6, 8.0)
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(TEMPLE + Vector3(sx * 6.2, y - TEMPLE.y + 3.6, 3.6), 0.0, Vector3.ONE * 2.0))
		night_only(Kit.omni(self, TEMPLE + Vector3(sx * 6.2, y - TEMPLE.y + 3.9, 3.6), Color(1.0, 0.62, 0.32), 1.4, 8.0))
	add_location("cloud_temple", TEMPLE, 13.0, TEMPLE + Vector3(0, y - TEMPLE.y + 0.05, 1.5))


func _temple_roofs() -> void:
	var y := height(TEMPLE.x, TEMPLE.z) + 1.5 + 4.95
	# two flared, square pagoda roofs (4-sided lathes) stacked, with an upper drum
	Kit.mesh_node(self, Kit.lathe([Vector2(10.6, 0.0), Vector2(9.6, 0.5), Vector2(6.0, 2.4), Vector2(4.6, 2.9)], 4, false), roof, Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.0, 1.0, 0.72)), TEMPLE + Vector3(0, y - TEMPLE.y, -0.4)))
	Kit.block(self, Vector3(6.0, 2.0, 4.6), Kit.xf(TEMPLE + Vector3(0, y - TEMPLE.y + 3.8, -0.4)), wood, false, 0.03)
	Kit.mesh_node(self, Kit.lathe([Vector2(6.4, 0.0), Vector2(5.8, 0.4), Vector2(2.4, 2.4), Vector2(0.3, 3.2)], 4, false), roof, Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(1.0, 1.0, 0.75)), TEMPLE + Vector3(0, y - TEMPLE.y + 4.7, -0.4)))
	Kit.mesh_node(self, Kit.lathe([Vector2(0.15, 0), Vector2(0.1, 1.6), Vector2(0.0, 1.9)], 6), Kit.metal(Color(0.8, 0.6, 0.3), 0.3), Kit.xf(TEMPLE + Vector3(0, y - TEMPLE.y + 7.8, -0.4)))
	night_only(Kit.mesh_node(self, Kit.box_mesh(Vector3(5.6, 1.0, 4.65), 0.02), Kit.emissive(Color(1.0, 0.65, 0.35), 2.0), Kit.xf(TEMPLE + Vector3(0, y - TEMPLE.y + 3.8, -0.4)), false))


func _links() -> void:
	add_gate("highland_path", Vector3(0.0, height(0, 25.5), 25.5), Vector3(0.0, height(0, 20) + 0.05, 20.0), 0.0, 2.4)
	add_interactable(Interactable.make("temple_pray", "Offer a quiet prayer in the Cloud Temple", "pray", "cloud_temple",
		TEMPLE + Vector3(0, height(TEMPLE.x, TEMPLE.z) + 1.5 - TEMPLE.y, -1.4), {"skills": {"arcane_orb": 0.15}, "knowledge": {"blessing:cloud_temple": 1}}, "spell_casting", 4.2)).radius = 2.6
	add_interactable(Interactable.make("armillary_align", "Align the armillary sphere to the stars", "study", "celestial_observatory",
		Vector3(OBS.x, height(OBS.x, OBS.z), OBS.z + 1.3), {"knowledge": {"astronomy:armillary": 1}}, "look_around", 4.0)).radius = 2.2
	add_interactable(Interactable.make("star_dial_read", "Read the time on the star dial", "read", "celestial_observatory",
		Vector3(OBS.x + 6.5, height(OBS.x + 6.5, OBS.z + 3.6), OBS.z + 3.6), {"knowledge": {"astronomy:star_dial": 1}}, "", 3.0)).radius = 2.0


func showcase_shots(loc: String) -> Array:
	if loc == "cloud_temple":
		return [[TEMPLE + Vector3(-14, 4.0, 18), TEMPLE + Vector3(0, 5, 0), 55.0]]
	return [[OBS + Vector3(6, 2.2, 8), OBS + Vector3(0, 2.4, 0), 50.0], [Vector3(-20, 3.0, -20), Vector3(400, -60, -600), 55.0]]
