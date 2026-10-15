extends ForestRegion
## C4 Village Observatory (Fantasy Village) - moved onto the realistic toolkit (world-quality gate): a wooded hill
## above the village (photographic ground, the forest round it, hour-by-hour light - the night sky is why it is here);
## on its top a paved circular terrace with a balustrade, a brass telescope on a stone pier, a star-chart table and
## benches; behind it, north, the OBSERVATORY itself: a round stone drum with a cornice, lancet windows that glow at
## night, an arched door onto the terrace, and a verdigris copper dome ribbed in brass, its shutter open and the
## great telescope's barrel pointing out at the sky. The path winds down the hill's south-east flank toward the
## village stair.

const TERRACE := Vector3(0, 0, 0)
const GATE := Vector2(52, 52)
const DOME := Vector3(0, 0, -15.5)
const DR := 4.3

var stone: ShaderMaterial


func _init() -> void:
	trails = [[[Vector2(8, 8), Vector2(18, 20), Vector2(30, 26), Vector2(40, 40), GATE], 2.2, "main"]]
	clearings = [[Vector2(0, 0), 11.0, "clearing"], [Vector2(0, -15.5), 8.5, "clearing"]]
	streams = []


func shape(x: float, z: float, h: float) -> float:
	var d := Vector2(x, z).length()
	return -smoothstep(11.0, 70.0, d) * 16.0 + h * smoothstep(11.0, 22.0, d)


func gate_spots() -> Array:
	return [GATE]


func features() -> Array:
	return [_terrace, _telescope, _furniture, _observatory, func(): dress_clearing(Vector2(0, 0), 10.0, true, [[Vector2(0, 0), 9.8], [Vector2(DOME.x, DOME.z), DR + 1.5]])]


func _terrace() -> void:
	stone = RealKit.stone_mat("castle_wall_slates") if RealKit.enabled() else Kit.tri("castle_wall_slates", "1k", 0.45, 0.35)
	magic_receivers = [stone]
	var tiles := Kit.tri("monastery_stone_floor", "2k", 0.3, 0.1, Color(0.85, 0.83, 0.8))
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


func _observatory() -> void:
	var y0 := height(DOME.x, DOME.z) - 0.5
	var base := DOME + Vector3(0, y0, 0)
	# the drum: plinth, battered wall, a string course, the cornice the dome sits on
	var prof := [Vector2(DR + 0.45, 0.0), Vector2(DR + 0.45, 1.0), Vector2(DR + 0.1, 1.15), Vector2(DR, 3.6), Vector2(DR + 0.14, 3.65),
		Vector2(DR + 0.14, 3.85), Vector2(DR, 3.9), Vector2(DR, 6.4), Vector2(DR + 0.3, 6.5), Vector2(DR + 0.45, 6.8), Vector2(DR + 0.45, 7.0), Vector2(DR + 0.1, 7.05)]
	Kit.mesh_node(self, Kit.lathe(prof, 48, true, true), stone, Kit.xf(base))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = DR + 0.2
	cyl.height = 7.0
	cs.shape = cyl
	cs.position = base + Vector3(0, 3.5, 0)
	body.add_child(cs)
	add_child(body)
	# the dome: verdigris copper, twelve brass ribs, the open shutter (a dark slot) facing south-east
	var verd := StandardMaterial3D.new()
	verd.albedo_color = Color(0.36, 0.55, 0.49)
	verd.roughness = 0.55
	verd.metallic = 0.35
	var dome_prof := []
	for i in 13:
		var t := PI * 0.5 * i / 12.0
		dome_prof.append(Vector2(cos(t) * (DR + 0.25) + 0.01, sin(t) * (DR + 0.25)))
	Kit.mesh_node(self, Kit.lathe(dome_prof, 48, true, false), verd, Kit.xf(base + Vector3(0, 7.0, 0)))
	var brass := Kit.metal(Color(0.72, 0.55, 0.3), 0.32)
	var dark := Kit.metal(Color(0.03, 0.03, 0.035), 0.6)
	var slot_yaw := PI * 0.75                     # the shutter faces south-east, over the terrace
	for k in 12:
		var yaw := TAU * k / 12.0
		for i in 11:
			var t := PI * 0.5 * (i + 0.5) / 11.0
			var r := DR + 0.29
			var p := Vector3(cos(t) * r, sin(t) * r, 0)
			var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, t)
			Kit.mesh_node(self, Kit.box_mesh(Vector3(0.07, PI * 0.5 * r / 11.0 + 0.03, 0.12), 0.01), brass, Transform3D(b, base + Vector3(0, 7.0, 0) + Basis(Vector3.UP, yaw) * p), false)
	for i in 10:
		var t := PI * 0.5 * (i + 0.5) / 10.0
		var r := DR + 0.3
		var p := Vector3(cos(t) * r, sin(t) * r, 0)
		var b := Basis(Vector3.UP, slot_yaw) * Basis(Vector3.BACK, t)
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.05, PI * 0.5 * r / 10.0 + 0.04, 1.3), 0.01), dark, Transform3D(b, base + Vector3(0, 7.0, 0) + Basis(Vector3.UP, slot_yaw) * p), false)
	# the great telescope's barrel, out through the shutter at ~38 degrees
	var dirv := Basis(Vector3.UP, slot_yaw) * Vector3(cos(deg_to_rad(38.0)), sin(deg_to_rad(38.0)), 0)
	var tube_base := base + Vector3(0, 7.6, 0)
	var tb := Basis.looking_at(dirv, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)
	Kit.mesh_node(self, Kit.lathe([Vector2(0.26, 0.0), Vector2(0.3, 2.2), Vector2(0.36, 2.3), Vector2(0.36, 2.6), Vector2(0.33, 4.9), Vector2(0.4, 5.0), Vector2(0.4, 5.35)], 20), brass, Transform3D(tb, tube_base))
	# finial
	Kit.mesh_node(self, Kit.lathe([Vector2(0.18, 0), Vector2(0.2, 0.15), Vector2(0.05, 0.3), Vector2(0.11, 0.45), Vector2(0.0, 1.1)], 12), brass, Kit.xf(base + Vector3(0, 7.0 + DR + 0.25, 0)))
	# lancet windows (stone surrounds, glazing that glows at night) and the arched door onto the terrace
	var glass := Kit.metal(Color(0.05, 0.06, 0.08), 0.12)
	for k in 6:
		var a := TAU * k / 6.0 + PI / 6.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.4:
			continue
		var n := Vector3(cos(a), 0, sin(a))
		var bw := Basis(Vector3.UP, -a + PI * 0.5)
		var wp := base + n * (DR + 0.02) + Vector3(0, 4.9, 0)
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.62, 1.7, 0.12), 0.01), glass, Transform3D(bw, wp), false)
		night_only(Kit.mesh_node(self, Kit.box_mesh(Vector3(0.56, 1.62, 0.14), 0.01), Kit.emissive(Color(1.0, 0.74, 0.42), 2.6), Transform3D(bw, wp), false))
		for sx: float in [-1.0, 1.0]:
			Kit.block(self, Vector3(0.22, 1.9, 0.3), Transform3D(bw, wp + bw * Vector3(sx * 0.42, 0, 0.05)), stone, false, 0.02)
		Kit.block(self, Vector3(1.1, 0.18, 0.4), Transform3D(bw, wp + bw * Vector3(0, -0.95, 0.08)), stone, false, 0.02)
		Kit.block(self, Vector3(1.0, 0.3, 0.32), Transform3D(bw, wp + bw * Vector3(0, 1.0, 0.05)), stone, false, 0.02)
	var door_at := base + Vector3(0, 1.0, DR + 0.15)
	for p in Kit.prop_parts("large_castle_door"):
		Kit.mesh_node(self, p[0], null, Transform3D(Basis.IDENTITY.scaled(Vector3(1.25, 1.25, 1.2)), door_at + Vector3(0, -0.15, 0)) * p[1])
	Kit.mesh_node(self, Kit.lathe([Vector2(1.3, 0.0), Vector2(1.3, 0.35), Vector2(0.0, 0.35)], 24, false), stone, Kit.xf(base + Vector3(0, 0.5, DR + 0.9)))
	var lamp_glow := Kit.omni(self, door_at + Vector3(0, 2.4, 0.9), Color(1.0, 0.7, 0.4), 1.4, 7.0)
	night_only(lamp_glow)
	add_poi("observatory_dome", base + Vector3(0, 0.6, DR + 2.2), "The observatory's copper dome, its shutter open on the sky", "village_observatory", 2.5)


func links() -> void:
	add_gate("village", Vector3(GATE.x, height(GATE.x, GATE.y), GATE.y), Vector3(GATE.x - 6.0, height(GATE.x - 6.0, GATE.y - 6.0) + 0.05, GATE.y - 6.0), PI * 0.25 + PI, 2.4)
	add_interactable(Interactable.make("telescope_observe", "Observe the sky through the brass telescope", "observe", "village_observatory",
		Vector3(-2, 0.15, -2), {"knowledge": {"astronomy:constellations": 1}, "discover": ["celestial_observatory"]}, "look_around", 5.0)).radius = 2.0
	add_interactable(Interactable.make("star_chart_study", "Study the star chart", "study", "village_observatory",
		Vector3(3.2, 0.15, -3.2), {"knowledge": {"astronomy:star_chart": 1}}, "", 4.0)).radius = 2.0
	interactables["star_chart_study"].book_id = "atlas_of_the_ten_rings"   # a real text: read page by page (data/books.json)
	# what she looks at: the eyepiece on its mount, the chart on the table top (not the foot of the pier / table)
	interactables["telescope_observe"].face_point = Vector3(-2, 1.55, -2)
	interactables["star_chart_study"].face_point = Vector3(3.2, 1.0, -3.2)


func showcase_shots(_loc: String) -> Array:
	return [[Vector3(7, 1.8, 7), Vector3(-2, 1.6, -2), 55.0], [Vector3(-4, 2.0, -6), Vector3(600, -40, 700), 50.0]]
