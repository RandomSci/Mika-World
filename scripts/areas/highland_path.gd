extends KitArea
## E1 Mountain Path + E2 Cliff Overlook (Celestial Highlands).
## A switchback trail climbs ~18 m up a rocky mountainside past cairns; at the east edge a railed
## stone overlook hangs above a sea of clouds with snow-capped ranges beyond.

const OVERLOOK := Vector3(26, 0, -6)
const SKY := "res://assets/polyhaven/hdris/alps_field/alps_field_2k.hdr"
const TRAIL := [Vector2(0, 42), Vector2(-14, 26), Vector2(10, 12), Vector2(-10, -4), Vector2(12, -18), Vector2(0, -36), Vector2(0, -44)]

var stone: ShaderMaterial
var rock: ShaderMaterial


static func resources() -> Array:
	return textures(["rock_wall_10", "stony_dirt_path", "castle_wall_slates", "snow_02"]) + textures(["leafy_grass"], "2k") + textures(["cliff_side"], "2k") + \
		models(["mountainside", "namaqualand_boulder_02", "rock_moss_set_02", "boulder_01"]) + [SKY]


func env_preset() -> Dictionary:
	return {"sky_day": SKY,
		"day": {"sun_rot": Vector3(-26, -140, 0), "sun_energy": 2.5, "sun_color": Color(1.0, 0.9, 0.78), "fog": 0.0005, "fog_color": Color(0.7, 0.76, 0.84), "vol_fog": 0.0, "exposure": 0.9, "bg_energy": 0.85},
		"night": {"fog": 0.002, "ambient": 1.5, "exposure": 1.35},
		"vista": {"mountains": false, "ridge_height": 420.0, "mountain_count": 8, "ridge_base": -240.0, "ridge_seed": 33, "snow_line": 40.0, "haze": Color(0.68, 0.74, 0.84), "cloud_sea": -70.0, "green": Color(0.3, 0.32, 0.28)}}


var _seg_len := []
var _seg_total := 0.0
var _overlook_y := 0.0


func trail_t(p: Vector2) -> Vector2:
	# returns (distance to trail, trail height at nearest point)
	if _seg_len.is_empty():
		for i in TRAIL.size() - 1:
			_seg_len.append((TRAIL[i + 1] - TRAIL[i]).length())
			_seg_total += _seg_len[i]
	var best := 1e9
	var hy := 0.0
	var acc := 0.0
	for i in TRAIL.size() - 1:
		var a: Vector2 = TRAIL[i]
		var b: Vector2 = TRAIL[i + 1]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + (b - a) * t)
		if d < best:
			best = d
			hy = (acc + t * _seg_len[i]) / _seg_total * 18.0
		acc += _seg_len[i]
	return Vector2(best, hy)


func height(x: float, z: float) -> float:
	var tr := trail_t(Vector2(x, z))
	var slope := clampf((42.0 - z) / 86.0, 0.0, 1.0) * 18.0
	var rough := sin(x * 0.23) * 1.2 + cos(z * 0.19 + x * 0.05) * 1.0 + sin((x - z) * 0.5) * 0.3
	var mountain := slope + rough + smoothstep(18.0, 34.0, -x) * 9.0
	var bench := lerpf(tr.y, mountain, smoothstep(2.0, 5.0, tr.x))
	var ov := 1.0 - smoothstep(6.0, 10.0, Vector2(x - OVERLOOK.x, z - OVERLOOK.z).length())
	if ov > 0.0:
		if _overlook_y == 0.0:
			_overlook_y = trail_t(Vector2(OVERLOOK.x - 8, OVERLOOK.z)).y + 0.2
		bench = lerpf(bench, _overlook_y, ov)
	var drop := smoothstep(32.0, 40.0, x) * 60.0
	return bench - drop


func build_steps() -> Array:
	return [_ground, _outcrops, _cairns, _overlook, _links]


func _ground() -> void:
	nav_aabb = AABB(Vector3(-36, -6, -48), Vector3(72, 36, 96))
	stone = Kit.tri("castle_wall_slates", "1k", 0.5, 0.15, Color(0.85, 0.85, 0.85))
	rock = Kit.tri("cliff_side", "2k", 0.1, 0.0)
	magic_receivers = [stone, rock]
	var mat := Kit.terrain_mat("leafy_grass", "rock_wall_10", "stony_dirt_path", Color(0.78, 0.84, 0.6), Color(0.62, 0.64, 0.66), "2k")
	mat.set_shader_parameter("grass2_albedo", load("res://assets/polyhaven/textures/snow_02/snow_02_diff_1k.jpg"))
	Kit.terrain(self, 100.0, 1.0, height, func(x, z):
		var tr := trail_t(Vector2(x, z))
		var steep := smoothstep(12.0, 28.0, -x) + smoothstep(30.0, 36.0, x)
		return Color(1.0 - smoothstep(1.2, 2.4, tr.x), clampf(steep, 0.0, 1.0), 0.0), mat)
	boundary_box(Vector3(0, 0, 0), Vector3(68, 60, 92))


func _outcrops() -> void:
	for spec in [[Vector3(-24, 0, 20), 2.2, 0.4], [Vector3(-26, 0, -14), 2.6, 1.6], [Vector3(-20, 0, -34), 2.0, 2.8], [Vector3(20, 0, 30), 1.6, 3.6], [Vector3(24, 0, -30), 1.8, 0.9]]:
		var p: Vector3 = spec[0]
		Kit.place_prop(self, "mountainside", Kit.xf(Vector3(p.x, height(p.x, p.z) - 2.5, p.z), spec[2], Vector3.ONE * spec[1]), "", true)
	for i in 14:
		var p := Vector2(rng.randf_range(-30, 30), rng.randf_range(-40, 40))
		if trail_t(p).x < 3.5 or p.distance_to(Vector2(OVERLOOK.x, OVERLOOK.z)) < 9.0 or p.x > 31.0:
			continue
		Kit.place_prop(self, ["namaqualand_boulder_02", "boulder_01"][i % 2], Kit.xf(Vector3(p.x, height(p.x, p.y) - 0.3, p.y), rng.randf() * TAU, Vector3.ONE * rng.randf_range(1.2, 2.6)), "", true)


func _cairns() -> void:
	for i in range(1, TRAIL.size() - 1):
		var a: Vector2 = TRAIL[i]
		var p := a + Vector2(2.6, 1.2)
		var y := height(p.x, p.y)
		var hh := 0.0
		for k in 5:
			var s := 0.42 - k * 0.06
			Kit.mesh_node(self, Kit.rock_mesh(s, 1100 + i * 10 + k, 0.2, Vector3(1.2, 0.55, 1.0)), stone, Kit.xf(Vector3(p.x, y + hh + s * 0.4, p.y), k * 0.9))
			hh += s * 0.75
		Kit.static_box(self, Vector3(0.9, hh, 0.9), Kit.xf(Vector3(p.x, y + hh * 0.5, p.y)))
	add_location("mountain_path", Vector3(0, 0, 10), 30.0, Vector3(TRAIL[2].x, trail_t(TRAIL[2]).y, TRAIL[2].y))
	add_poi("trail_cairn", Vector3(TRAIL[3].x + 2.6, height(TRAIL[3].x + 2.6, TRAIL[3].y + 1.2), TRAIL[3].y + 1.2), "Stone cairn marking the switchbacks", "mountain_path", 2.0)


func _overlook() -> void:
	var y := height(OVERLOOK.x, OVERLOOK.z)
	var root := Node3D.new()
	root.transform = Kit.xf(Vector3(OVERLOOK.x, y, OVERLOOK.z), -PI * 0.5)
	add_child(root)
	Kit.block(root, Vector3(9, 0.5, 7), Kit.xf(Vector3(0, -0.2, -2.0)), stone, true, 0.05)
	Kit.mesh_node(root, Kit.rock_mesh(1.0, 1200, 0.3, Vector3(5.5, 4.0, 4.5), 2), rock, Kit.xf(Vector3(0, -4.0, -3.5)))
	for i in 9:
		var x := -4.0 + i
		Kit.mesh_node(root, Kit.lathe([Vector2(0.12, 0), Vector2(0.16, 0.15), Vector2(0.08, 0.5), Vector2(0.13, 0.9)], 8), stone, Kit.xf(Vector3(x, 0.05, -5.3)))
	Kit.block(root, Vector3(9.2, 0.14, 0.38), Kit.xf(Vector3(0, 1.0, -5.3)), stone, true, 0.02)
	for sx: float in [-1.0, 1.0]:
		Kit.block(root, Vector3(0.38, 1.1, 6.5), Kit.xf(Vector3(sx * 4.4, 0.55, -2.0)), stone, true, 0.02)
	Kit.block(root, Vector3(1.8, 0.45, 0.55), Kit.xf(Vector3(0, 0.25, 0.5)), stone, true, 0.03)
	add_location("cliff_overlook", OVERLOOK, 9.0, Vector3(OVERLOOK.x + 1.0, y + 0.1, OVERLOOK.z))


func _links() -> void:
	add_gate("village", Vector3(0.0, height(0, 45.5), 45.5), Vector3(0.0, height(0, 40) + 0.05, 40.0), 0.0, 2.6)
	# Milestone K: the frontier road from the Whispering Woods arrives over the western shoulder
	add_gate("whispering_woods", Vector3(-15.5, height(-15.5, 26.0), 26.0), Vector3(-11.0, height(-11.0, 25.0) + 0.05, 25.0), PI * 0.5, 2.4)
	var top := Vector2(0, -44)
	add_gate("celestial_summit", Vector3(top.x, height(top.x, top.y), top.y), Vector3(0.0, height(0, -38.5) + 0.05, -38.5), PI, 2.4)
	for sx: float in [-1.0, 1.0]:
		Kit.block(self, Vector3(0.8, 3.2, 0.8), Kit.xf(Vector3(sx * 2.2, height(sx * 2.2, -43.5) + 1.5, -43.5)), stone, true, 0.05)
	Kit.block(self, Vector3(5.4, 0.6, 1.0), Kit.xf(Vector3(0, height(0, -43.5) + 3.3, -43.5)), stone, false, 0.05)
	add_interactable(Interactable.make("cairn_add_stone", "Add a stone to the trail cairn", "offer", "mountain_path",
		points_of_interest["trail_cairn"].position, {"knowledge": {"custom:cairn_stone": 1}}, "", 2.5)).radius = 2.4
	add_interactable(Interactable.make("overlook_observe", "Take in the view over the sea of clouds", "observe", "cliff_overlook",
		Vector3(OVERLOOK.x + 1.0, height(OVERLOOK.x, OVERLOOK.z) + 0.1, OVERLOOK.z), {"knowledge": {"geography:cloud_sea": 1}, "discover": ["cloud_temple", "celestial_observatory"]}, "look_around", 4.0)).radius = 2.6


func showcase_shots(loc: String) -> Array:
	if loc == "cliff_overlook":
		return [[OVERLOOK + Vector3(-6.5, height(OVERLOOK.x - 6.5, OVERLOOK.z + 3) + 2.2, 3.0), OVERLOOK + Vector3(400, -40, -150), 62.0]]
	return [[Vector3(-12, height(-12, 34) + 3.0, 34), Vector3(4, height(4, 0) + 2.0, 0), 60.0]]
