extends ForestRegion
## F1 Academy Courtyard + F3 Advanced Magic Arena + F4 Academy Gardens (Grand Academy) - moved onto the realistic
## toolkit (world-quality gate): photographic ground (lawns, flagstone walks, gravel garden paths), the woods round
## the campus, hour-by-hour light; the great hall's facade in real coursed ashlar, photoscanned stone and marble.
## A monumental paved courtyard framed by the great hall (tall arched windows, a portal, a lantern spire with a
## rose window) and two round towers, wings with archway passages, the arena with tiered seating round a rune
## circle, and formal gardens with hedges, flowerbeds and a fountain.

const COURT := Vector3(0, 0, 0)
const ARENA := Vector3(44, 0, 6)
const GARDEN := Vector3(-42, 0, 6)
const GATE_VILLAGE := Vector2(-12, 132)

var stone: ShaderMaterial
var marble: ShaderMaterial
var roof: StandardMaterial3D
var glass_day: Material
var glass_night: Material


func _init() -> void:
	trails = [
		[[Vector2(-18, 26), Vector2(18, 26)], 1.0, "hidden"],
		[[Vector2(8, 27), Vector2(4, 60), Vector2(-6, 100), GATE_VILLAGE], 4.0, "main"],     # the old academy road (beside the sealed portal, not through it)
	]
	clearings = [[Vector2(0, 4), 74.0, "glade"]]
	streams = []


func gate_spots() -> Array:
	return [GATE_VILLAGE]


func shape(x: float, z: float, h: float) -> float:
	# the campus is level; the land rolls only beyond it
	return h * smoothstep(70.0, 92.0, Vector2(x * 0.85, z).length())


func density(p: Vector2, f: float) -> float:
	return f * smoothstep(74.0, 92.0, Vector2(p.x * 0.85, p.y).length())


func _terrain_mask(x: float, z: float) -> Color:
	var court := float(absf(x) < 22.0 and z > -14.0 and z < 26.0)
	var to_arena := float(x > 20.0 and x < 32.0 and absf(z - 6.0) < 2.5)
	var to_garden := float(x < -20.0 and x > -30.0 and absf(z - 6.0) < 2.5)
	var walk := maxf(maxf(court, to_arena), to_garden)
	var gp := Vector2(x - GARDEN.x, z - GARDEN.z)
	var gravel := float(absf(gp.x) < 1.6 or absf(gp.y) < 1.6) * float(gp.length() < 16.0) + float(absf(gp.length() - 6.5) < 1.2)
	var base := super._terrain_mask(x, z)
	return Color(walk, base.g, clampf(gravel, 0.0, 1.0) * (1.0 - walk), 0.0)


func features() -> Array:
	return [_materials, _great_hall, _towers, _wings, _fountain_court, _arena, _gardens_layout, _gardens_plants, _anchors]


func _materials() -> void:
	stone = (RealKit.stone_mat("castle_wall_slates") if RealKit.enabled() else Kit.tri("castle_wall_slates", "1k", 0.45, 0.1)).duplicate()
	stone.set_shader_parameter("moss_amount", 0.12)
	stone.set_shader_parameter("tint", Color(1.05, 1.03, 0.98))
	marble = Kit.tri("marble_01", "1k", 0.25, 0.0, Color(0.95, 0.94, 0.9))
	roof = Kit.uvmat("roof_slates_02", "1k", Vector2(5, 3), Color(0.5, 0.56, 0.64))
	glass_day = Kit.metal(Color(0.12, 0.16, 0.22), 0.06)
	glass_night = Kit.emissive(Color(1.0, 0.75, 0.45), 2.6)
	magic_receivers = [stone, marble]
	# the walks are flagstones, the garden paths gravel
	var tm: ShaderMaterial = mats.terrain
	tm.set_shader_parameter("path_alb", RealKit.ph_tex("monastery_stone_floor", "diff"))
	tm.set_shader_parameter("path_nrm", RealKit.ph_tex("monastery_stone_floor", "nor_gl"))
	tm.set_shader_parameter("bank_alb", RealKit.ph_tex("stony_dirt_path", "diff"))
	tm.set_shader_parameter("bank_nrm", RealKit.ph_tex("stony_dirt_path", "nor_gl"))


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
	Kit.block(self, Vector3(w - 0.6, h, 11.4), Kit.xf(c + Vector3(0, h * 0.5, -0.2)), stone, true, 0.08)
	var front := c.z + 6.05
	# the facade in real coursed ashlar (StoneBuilder): piers between the tall windows, sills under them, masonry
	# over them and over the portal
	var sb := StoneBuilder.new(height, 211)
	sb.base_y = -1.0
	sb.top_y = h + 1.0
	var fz := front - 0.25
	var opens := [[-3.9, 3.9, 0.0, 9.2]]
	for i in 9:
		var wx := -16.0 + i * 4.0
		if absf(wx) < 3.0:
			continue
		opens.append([wx - 1.05, wx + 1.05, 3.7, 9.3])
	opens.sort_custom(func(a, b): return a[0] < b[0])
	var x := -w * 0.5
	for o in opens:
		if float(o[0]) - x > 0.15:
			sb.wall(Vector3(x, 0, fz), Vector3(float(o[0]), 0, fz), h, 0.7, 0.0, 0.62, 0.0, 0.0)
		if float(o[2]) > 0.2:
			sb.wall(Vector3(float(o[0]), 0, fz), Vector3(float(o[1]), 0, fz), float(o[2]), 0.7, 0.0, 0.62, 0.0, 0.0)
		sb.wall(Vector3(float(o[0]), 0, fz), Vector3(float(o[1]), 0, fz), h, 0.7, 0.0, 0.62, float(o[3]), 0.0)
		x = float(o[1])
	sb.wall(Vector3(x, 0, fz), Vector3(w * 0.5, 0, fz), h, 0.7, 0.0, 0.62, 0.0, 0.0)
	for sx: float in [-1.0, 1.0]:
		sb.wall(Vector3(sx * w * 0.5, 0, fz), Vector3(sx * w * 0.5, 0, c.z - 6.0), h, 0.7, 0.0, 0.62, 0.0, 0.0)
	sb.finish(self, stone, "HallMasonry")
	var root := Node3D.new()
	add_child(root)
	for i in 9:
		var wx := -16.0 + i * 4.0
		if absf(wx) < 3.0:
			continue
		_arched_window(root, Vector3(wx, 6.5, front + 0.02), 2.0, 5.6)
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.8, h, 0.5), 0.03), marble, Kit.xf(Vector3(wx + 2.0, h * 0.5, front + 0.15)))
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


## The places of the academy's day (TownLife, data/residents.json): the students' and teachers' quarters (doors in
## the wings), an open-air lesson on the east lawn of the courtyard (the teacher standing, the class sitting on the
## grass facing him - two places left free for visitors), the practice spots round the arena's rune circle, the
## library door, the lawn by the garden fountain where they eat, and the courtyard fountain.
func _anchors() -> void:
	var q := 0
	for sx: float in [-1.0, 1.0]:
		for z in [1.0, 11.0]:
			add_anchor("quarters:%d" % q, Vector3(sx * 22.6, height(sx * 22.6, z), z), -sx * PI * 0.5, true)
			q += 1
	var teacher := Vector3(12.5, 0, 15.0)
	add_anchor("lecture", Vector3(teacher.x, height(teacher.x, teacher.z), teacher.z), -PI * 0.5)
	# the class sits on two benches facing the teacher (three to a bench; the far places free for visitors)
	var bench_wood := Kit.tri("wood_table_001", "1k", 0.9, 0.0, Color(0.6, 0.48, 0.38))
	var n := 0
	for row in 2:
		n = seat_bench(Vector3(teacher.x - 3.6 - row * 1.5, 0, teacher.z), PI * 0.5, 3, "seat", n, bench_wood)
	for i in 4:
		var a := PI + (i - 1.5) * 0.45
		var pp := Vector3(ARENA.x + cos(a) * 6.5, 0, ARENA.z + sin(a) * 6.5)
		pp.y = height(pp.x, pp.z)
		add_anchor("practice:%d" % i, pp, atan2(ARENA.x - pp.x, ARENA.z - pp.z))
	add_anchor("library", Vector3(0, height(0, -14.6), -14.6), PI, true)
	# the garden's marble benches (radius 9, seat 0.45 m): one place on each, facing the fountain
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var face := Vector3(-cos(a), 0, -sin(a))
		var bp := Vector3(GARDEN.x + cos(a) * 9.0, 0, GARDEN.z + sin(a) * 9.0) + face * 0.36
		bp.y = height(bp.x, bp.z)
		add_anchor("bench:%d" % i, bp, atan2(face.x, face.z))
	add_anchor("fountain", Vector3(0, height(0, 11.6), 11.6), 0.0)
	add_anchor("square:0", Vector3(-3.0, height(-3.0, 12.0), 12.0), PI * 0.25)


func links() -> void:
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
	edge_gate("village", GATE_VILLAGE)
	# the free places at the open-air lesson (the back bench): a visitor sits in when a lesson is being taught
	for i in [3, 4, 5]:
		var a: Dictionary = anchors.get("seat:%d" % i, {})
		if a.is_empty():
			continue
		var fwd := Vector3(sin(float(a.yaw)), 0, cos(float(a.yaw)))
		var it := Interactable.make("lesson_seat_%d" % i, "Sit in on the lesson on the east lawn", "study", "academy_courtyard",
			a.pos, {}, "sit", 60.0)
		it.stand_point = a.pos
		it.sit_point = (a.pos as Vector3) - fwd * 0.36
		it.face_point = (a.pos as Vector3) + fwd * 4.0 + Vector3(0, 1.0, 0)
		it.seat_body = seat_bodies.get("seat:%d" % i)
		it.kind = "study"
		it.radius = 1.0
		it.custom_activity = _lesson.bind(it)
		add_interactable(it)
	add_interactable(Interactable.make("statue_plaque", "Read the founder's plaque on the fountain statue", "read", "academy_courtyard",
		Vector3(0, 0, 11.0), {"knowledge": {"lore:academy_founding": 1}}, "look_around", 3.0)).radius = 2.4
	interactables["statue_plaque"].book_id = "founders_plaque"   # a real text: read page by page (data/books.json)
	add_interactable(Interactable.make("arena_drill", "Run a casting drill in the arena", "practice", "advanced_magic_arena",
		Vector3(ARENA.x - 3.0, 0.15, ARENA.z), {"skills": {"arcane_orb": 0.35}}, "magic_attack_2h", 2.8)).radius = 3.0
	add_interactable(Interactable.make("garden_herbs", "Gather medicinal herbs in the gardens", "collect", "academy_gardens",
		Vector3(GARDEN.x + 6.0, 0, GARDEN.z + 6.0), {"items": {"herbs": 1}, "knowledge": {"botany:academy_gardens": 1}}, "", 3.0)).radius = 3.0
	add_interactable(Interactable.make("garden_fountain_rest", "Rest by the garden fountain", "rest", "academy_gardens",
		Vector3(GARDEN.x + 3.0, 0, GARDEN.z), {"knowledge": {"calm:academy_gardens": 1}}, "", 3.5)).radius = 2.4


## Sitting in on a lesson (V3: magic learned from mentors). She listens while the teacher - a resident living
## his own day (TownLife) - talks and demonstrates; what she takes away is the next of his lessons she has not
## heard yet (data/residents.json "lessons"), remembered as her own knowledge.
func _lesson(c: WorldCharacter, it: Interactable) -> Dictionary:
	var teacher: Resident = null
	for r in get_tree().get_nodes_in_group("residents"):
		if is_instance_valid(r) and (r as Resident).activity == "teach" and (r as Resident).visible:
			teacher = r
	if teacher == null:
		it.effects = {}
		return {"ok": false, "detail": "no lesson is being taught right now"}
	var who := c.character_id
	var mind := WorldState.mind(who)
	var lessons: Array = teacher.data.get("lessons", [])
	var next := {}
	for l in lessons:
		if not mind.knowledge.has("lesson:%s:%s" % [teacher.id, String(l.id)]):
			next = l
			break
	if next.is_empty() and not lessons.is_empty():
		next = lessons[randi() % lessons.size()]
	c.look_head_at(teacher.global_position + Vector3(0, 1.6, 0))
	var t := 0.0
	var said := 0
	var lines: Array = next.get("lines", []) + teacher.data.get("lines", {}).get("teach", [])
	while t < 55.0 and teacher.activity == "teach":
		# the teacher speaks to the class and now and then shows it (a small spell at his hands)
		if int(t / 14.0) >= said and said < lines.size():
			if VoiceService.instance:
				VoiceService.instance.say(String(teacher.data.get("voice", teacher.id)), String(lines[said]), {"max_wait": 3.0})
			if said % 2 == 1:
				teacher.play("cast", 0.2)
				teacher.town.spell_spark(teacher)
			said += 1
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	c.look_head_at(null)
	var know: Dictionary = (next.get("knowledge", {}) as Dictionary).duplicate()
	know["lesson:%s:%s" % [teacher.id, String(next.get("id", "general"))]] = 1
	know["mentor:" + teacher.id] = 1
	know["lesson_last_min"] = str(WorldState.world_min)
	it.effects = {"knowledge": know, "skills": next.get("skills", {"spell_theory": 0.1})}
	return {"ok": true, "detail": "listened to %s's lesson: %s" % [String(teacher.data.get("name", teacher.id)), String(next.get("topic", "the elemental arts"))],
		"teacher": teacher.id, "topic": String(next.get("topic", "")), "lines_heard": said}


func showcase_shots(loc: String) -> Array:
	match loc:
		"advanced_magic_arena":
			return [[ARENA + Vector3(-9.5, 2.6, 6.5), ARENA + Vector3(2, 1.2, -2), 62.0]]
		"academy_gardens":
			return [[GARDEN + Vector3(13, 2.6, -11), GARDEN + Vector3(0, 0.6, 1), 58.0]]
	return [[Vector3(-10, 2.2, 26), Vector3(0, 9, -22), 62.0], [Vector3(14, 1.8, 18), Vector3(-6, 6, -16), 60.0]]
