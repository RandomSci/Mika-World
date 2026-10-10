class_name SanctuaryExpansion
extends RefCounted
## The Sanctuary as a connected mini-region: builds the sub-areas around the original circle
## (Meditation Garden, Shrine / Altar Chamber, Scenic Watchpoint, the ruined forest gate details,
## rune targets on the training grounds, the scroll lectern and Mika's journal on the dais) and
## registers their activities. Ids match data/sanctuary.json (lore, trials, brain actions).
## Everything is deterministic (fixed seed) so the streamed layout hash stays stable.

const POND := SanctuaryTerrain.POND
const SEAT_H := 0.44   # top of seats; matches the hips height of the retargeted "Sitting Idle" clip

var s: Sanctuary
var rng := RandomNumberGenerator.new()
var stone: Material
var slab: Material
var wood: Material
var rubble_xf: Array = []
var shafts: Array[ShaderMaterial] = []
var rune_sigils := {}              # target id -> ShaderMaterial
var heartstone: Node3D
var heartstone_light: OmniLight3D
var heartstone_mat: Material
var heartstone_y := 0.0


func _init(owner: Sanctuary) -> void:
	s = owner
	rng.seed = 7_2026
	stone = s.mats.stone
	slab = s.mats.stone_slab
	wood = Kit.uvmat("dark_wooden_planks")


func g(x: float, z: float) -> float:
	return s.terrain.fast_height(x, z)


func blk(size: Vector3, pos: Vector3, yaw := 0.0, mat: Material = null, collide := true, tilt := Vector3.ZERO) -> MeshInstance3D:
	var b := Basis(Vector3.UP, yaw)
	if tilt != Vector3.ZERO:
		b = b * Basis.from_euler(tilt)
	var t := Transform3D(b, pos)
	var mi := Kit.mesh_node(s, Kit.box_mesh(size, 0.04), mat if mat else stone, t)
	mi.add_to_group("cat_expansion")
	if collide:
		Kit.static_box(s, size, t)
	return mi


func rubble(center: Vector2, radius: float, count: int, avoid_paths := 1.4) -> void:
	for i in count:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		if SanctuaryTerrain.dist_to_paths(p) < avoid_paths:
			continue
		var sc := rng.randf_range(0.5, 1.25)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))).scaled(Vector3.ONE * sc)
		rubble_xf.append(Transform3D(b, Vector3(p.x, g(p.x, p.y) + 0.06 * sc, p.y)))


func shaft(pos: Vector3, height: float, width: float, yaw: float, lean: float, intensity := 0.22) -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/light_shaft.gdshader")
	m.set_shader_parameter("intensity", intensity)
	shafts.append(m)
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	for k in 2:  # two crossed cards read as a volume from most angles
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis(Vector3.UP, yaw + k * PI * 0.5) * Basis(Vector3.RIGHT, 0.0) * Basis(Vector3.FORWARD, lean), pos)
		mi.visibility_range_end = 60.0
		s.add_child(mi)


func set_night(n: bool) -> void:
	for m in shafts:
		m.set_shader_parameter("day", 0.0 if n else 1.0)


# ------------------------------------------------------------------ build steps
func build_ritual_and_gate() -> void:
	var top := Sanctuary.DAIS_TOP
	# Scroll lectern on the west side of the dais
	var lp := Vector3(-3.3, top, -0.9)
	blk(Vector3(0.22, 1.0, 0.22), lp + Vector3(0, 0.5, 0), 0.0, wood, true)
	blk(Vector3(0.62, 0.05, 0.46), lp + Vector3(0, 1.05, 0), PI * 0.5, wood, false, Vector3(0.0, 0.0, -0.35))
	blk(Vector3(0.5, 0.06, 0.5), lp + Vector3(0, 0.03, 0), 0.0, wood, false)
	var scroll := Kit.mesh_node(s, Kit.lathe([Vector2(0.035, -0.22), Vector2(0.035, 0.22)], 12, true, true),
		Kit.emissive(Color(0.86, 0.78, 0.6), 0.0), Transform3D(Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, 0.1), lp + Vector3(0.02, 1.12, 0)))
	scroll.add_to_group("cat_expansion")
	var paper := Kit.mesh_node(s, Kit.box_mesh(Vector3(0.36, 0.006, 0.42), 0.0), Kit.emissive(Color(0.88, 0.8, 0.62), 0.05),
		Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_euler(Vector3(0, 0, -0.35)), lp + Vector3(0.0, 1.09, 0)), false)
	paper.add_to_group("cat_expansion")
	var it := Interactable.make("scroll_first_circle", "Read the Scroll of the First Circle", "study", "ritual_sanctuary",
		lp, {"skills": {"arcane_orb": 0.05}}, "", 4.0)
	it.kind = "study"
	it.book_id = "scroll_first_circle"
	it.book_xf = Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, 0.35), lp + Vector3(0.02, 1.13, 0))
	it.book_props = [scroll, paper]
	it.radius = 1.3
	it.stand_point = lp + Vector3(0.75, 0, 0.0)
	it.face_point = lp + Vector3(0, 1.0, 0)
	s.add_interactable(it)

	# Mika's journal: a small writing desk + stool on the east side of the dais
	var dp := Vector3(3.4, top, 1.3)
	blk(Vector3(0.9, 0.06, 0.55), dp + Vector3(0, 0.74, 0), -0.5, wood, true)
	for sx in [-0.38, 0.38]:
		for sz in [-0.2, 0.2]:
			blk(Vector3(0.06, 0.72, 0.06), dp + Basis(Vector3.UP, -0.5) * Vector3(sx, 0.36, sz), -0.5, wood, false)
	var book := Kit.mesh_node(s, Kit.prop("book_encyclopedia_set_01", "book_encyclopedia_set_01_book03"), null,
		Transform3D(Basis(Vector3.UP, -0.2) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.3), dp + Vector3(0.05, 0.78, 0.0)), false)
	book.add_to_group("cat_expansion")
	Kit.place_prop(s, "brass_candleholders", Kit.xf(dp + Vector3(-0.3, 0.77, -0.15)), "brass_candleholder_01")
	s._add_flame(dp + Vector3(-0.3, 0.77 + 0.3, -0.15), 0.25, 0.2, true)
	Kit.place_prop(s, "folding_wooden_stool", Kit.xf(dp + Vector3(-0.35, 0, 0.55), 2.6))
	it = Interactable.make("mika_journal", "Write in Mika's training journal", "rest", "ritual_sanctuary",
		dp, {"knowledge": {"journal:entries": 1}}, "", 3.5)
	it.kind = "rest"
	it.radius = 1.3
	it.stand_point = dp + Basis(Vector3.UP, -0.5) * Vector3(0, 0, 0.75)
	it.face_point = dp + Vector3(0, 0.8, 0)
	s.add_interactable(it)

	# Ruined Forest Gate: fallen voussoirs, an inscription stone, rubble and a light shaft through the arch
	for f in [[Vector3(4.6, 0, -19.6), 0.6, Vector3(0.3, 0, 0.5)], [Vector3(5.6, 0, -18.0), 2.1, Vector3(-0.2, 0, 1.2)],
			[Vector3(-3.2, 0, -24.0), 1.2, Vector3(0.9, 0, 0.2)], [Vector3(6.2, 0, -21.4), 0.2, Vector3(0, 0, 0.25)]]:
		var p: Vector3 = f[0]
		blk(Vector3(0.95, 0.62, 0.7), Vector3(p.x, g(p.x, p.z) + 0.22, p.z), f[1], stone, true, f[2])
	var ip := Vector3(3.7, 0, -14.4)
	var gy := g(ip.x, ip.z)
	blk(Vector3(1.3, 1.5, 0.32), Vector3(ip.x, gy + 0.62, ip.z), 0.35, stone, true, Vector3(-0.08, 0, 0))
	var glyph := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(1.0, 0.9)
	glyph.mesh = gq
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/magic/sigil.gdshader")
	gm.set_shader_parameter("sides", 5)
	gm.set_shader_parameter("color", Color(0.5, 0.75, 1.0))
	gm.set_shader_parameter("intensity", 0.35)
	gm.set_shader_parameter("spin", 0.05)
	glyph.material_override = gm
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glyph.transform = Transform3D(Basis(Vector3.UP, 0.35) * Basis(Vector3.RIGHT, -0.08), Vector3(ip.x, gy + 0.75, ip.z) + Basis(Vector3.UP, 0.35) * Vector3(0, 0, 0.17))
	s.add_child(glyph)
	it = Interactable.make("gate_inscription", "Read the inscription on the forest gate", "inspect", "ritual_sanctuary",
		Vector3(ip.x, gy, ip.z), {}, "", 3.5)
	it.kind = "inspect"
	it.book_id = "gate_inscription"
	it.radius = 1.4
	it.stand_point = Vector3(ip.x, gy, ip.z) + Basis(Vector3.UP, 0.35) * Vector3(0, 0, 1.15)
	it.face_point = Vector3(ip.x, gy + 0.9, ip.z)
	s.add_interactable(it)
	rubble(Vector2(4.5, -19.0), 3.0, 14)
	rubble(Vector2(-4.0, -20.5), 2.6, 10)
	shaft(Vector3(0.6, g(0.6, -19.5) + 4.0, -19.5), 9.0, 2.4, 0.4, 0.42, 0.16)


func build_garden() -> void:
	var gc := SanctuaryTerrain.GARDEN
	# Pond: the terrain is carved (SanctuaryTerrain.POND); a still water surface sits just below the rim.
	var water_y := g(POND.x + 3.6, POND.y) - 0.14
	var w := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.25
	cyl.bottom_radius = 3.25
	cyl.height = 0.02
	cyl.radial_segments = 40
	cyl.rings = 1
	w.mesh = cyl
	w.material_override = Kit.shader_mat("res://shaders/water.gdshader", {"shallow": Color(0.08, 0.2, 0.19), "deep": Color(0.015, 0.05, 0.055),
		"clarity": 0.22, "flow": Vector2(0.004, 0.006), "wave_scale": 0.05})
	w.position = Vector3(POND.x, water_y, POND.y)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(w)
	var pr := PondReactive.new()
	pr.name = "Reactive_pond"
	s.add_child(pr)
	pr.position = w.position
	pr.setup("pond", "the garden pond", w, 3.25)
	# Invisible pond guard: the navmesh routes around it; too tall to step onto.
	var guard := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gshape := CylinderShape3D.new()
	gshape.radius = 2.7
	gshape.height = 1.2
	gcs.shape = gshape
	guard.add_child(gcs)
	guard.position = Vector3(POND.x, water_y - 0.15, POND.y)
	s.add_child(guard)
	# Rim stones and a few lily-pad-like flat stones
	var r1 := "rock_moss_set_01"
	for i in 13:
		var a := TAU * i / 13.0 + rng.randf_range(-0.12, 0.12)
		var rr := 3.25 + rng.randf_range(-0.1, 0.25)
		var p := POND + Vector2(cos(a), sin(a)) * rr
		var part := "%s_rock%02d" % [r1, 1 + (i % 6)]
		s.place_mesh(s._part_mesh(r1, part), s._ground(p.x, p.y), rng.randf() * TAU, Vector3(0.42, 0.32, 0.42) * rng.randf_range(0.8, 1.2), false, 0.12)
	# Lily pads and reeds
	var pads: Array = []
	for i in 9:
		var p := POND + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.8, 2.5)
		pads.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, 1, 1) * rng.randf_range(0.7, 1.3)), Vector3(p.x, water_y + 0.012, p.y)))
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.22
	pad_mesh.bottom_radius = 0.22
	pad_mesh.height = 0.01
	pad_mesh.radial_segments = 12
	pad_mesh.rings = 1
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.2, 0.36, 0.12)
	pad_mat.roughness = 0.5
	Kit.multimesh(s, pad_mesh, pads, 40.0, false, pad_mat)
	var reeds: Array = []
	for i in 70:
		var a := rng.randf_range(-1.9, 1.1)  # north and east banks, away from the seat
		var p := POND + Vector2(cos(a), sin(a)) * rng.randf_range(2.7, 3.4)
		var hgt := rng.randf_range(0.6, 1.25)
		var bb := Basis.from_euler(Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.18, 0.18))).scaled(Vector3(1, hgt, 1))
		reeds.append(Transform3D(bb, Vector3(p.x, g(p.x, p.y) - 0.05 + hgt * 0.5, p.y)))
	var reed_mesh := CylinderMesh.new()
	reed_mesh.top_radius = 0.004
	reed_mesh.bottom_radius = 0.014
	reed_mesh.height = 1.0
	reed_mesh.radial_segments = 4
	reed_mesh.rings = 1
	var reed_mat := StandardMaterial3D.new()
	reed_mat.albedo_color = Color(0.36, 0.42, 0.18)
	reed_mat.roughness = 0.8
	Kit.multimesh(s, reed_mesh, reeds, 40.0, false, reed_mat).add_to_group("cat_foliage")
	# The Still Stone: a smooth seat facing the pond
	var seat := POND + Vector2(-3.9, 3.4)
	var face := (POND - seat).normalized()
	var yaw := atan2(face.x, face.y)
	var sy := g(seat.x, seat.y)
	var sm := Kit.mesh_node(s, Kit.rock_mesh(0.62, 31, 0.12, Vector3(1.25, 0.6, 0.85)), stone, Transform3D(Basis(Vector3.UP, yaw), Vector3(seat.x, sy + SEAT_H - 0.37, seat.y)))
	sm.add_to_group("cat_expansion")
	var stand := seat + face * 0.42
	var it := Interactable.make("garden_meditate", "Meditate on the Still Stone", "meditate", "ritual_sanctuary",
		Vector3(seat.x, sy, seat.y), {"skills": {"focus": 0.2, "arcane_orb": 0.05}, "knowledge": {"lore:still_stone": 1}}, "sit", 6.0)
	it.kind = "meditate"
	it.lore_id = "garden_stone"
	it.radius = 1.2
	it.stand_point = Vector3(stand.x, sy, stand.y)
	it.face_point = Vector3(POND.x, sy + 1.0, POND.y)
	it.seat_body = Kit.static_box(s, Vector3(1.4, SEAT_H, 0.9), Transform3D(Basis(Vector3.UP, yaw), Vector3(seat.x, sy + SEAT_H * 0.5, seat.y)))
	var sitp := seat + face * 0.12  # pelvis a little forward of the stone's centre (it is deep)
	it.sit_point = Vector3(sitp.x, sy, sitp.y)
	s.add_interactable(it)
	var refl := POND + Vector2(-0.6, -3.9)
	var ry := g(refl.x, refl.y)
	it = Interactable.make("pond_reflect", "Watch the still pond", "rest", "ritual_sanctuary",
		Vector3(POND.x, water_y, POND.y), {"skills": {"focus": 0.08}}, "look_around", 4.5)
	it.kind = "rest"
	it.radius = 3.6
	it.stand_point = Vector3(refl.x, ry, refl.y)
	it.face_point = Vector3(POND.x, water_y, POND.y)
	s.add_interactable(it)
	# Stone lantern beside the seat (warm light, brighter at night)
	var lt := seat + Vector2(-1.2, -1.5)
	var lty := g(lt.x, lt.y)
	var lan := Kit.mesh_node(s, Kit.lathe([Vector2(0.32, 0), Vector2(0.3, 0.12), Vector2(0.12, 0.18), Vector2(0.1, 0.78), Vector2(0.24, 0.84),
		Vector2(0.24, 0.9)], 8, false, true), stone, Kit.xf(Vector3(lt.x, lty, lt.y)))
	lan.add_to_group("cat_expansion")
	blk(Vector3(0.36, 0.3, 0.36), Vector3(lt.x, lty + 1.05, lt.y), 0.3, stone, false)
	blk(Vector3(0.72, 0.1, 0.72), Vector3(lt.x, lty + 1.25, lt.y), 0.3, stone, false)
	blk(Vector3(0.42, 0.12, 0.42), Vector3(lt.x, lty + 1.36, lt.y), 0.3, stone, false)
	Kit.mesh_node(s, Kit.box_mesh(Vector3(0.2, 0.18, 0.2), 0.0), Kit.emissive(Color(1.0, 0.7, 0.35), 1.2), Kit.xf(Vector3(lt.x, lty + 1.05, lt.y), 0.3), false)
	s._add_flame(Vector3(lt.x, lty + 1.05, lt.y), 0.5, 0.35, true)
	Kit.static_box(s, Vector3(0.5, 1.3, 0.5), Kit.xf(Vector3(lt.x, lty + 0.65, lt.y)))
	# Planting: flowers, shrubs and ferns; a few stepping stones
	var flowers := ["flower_empodium", "flower_gazania", "flower_ursinia"]
	var dens: float = RenderProfile.get_setting("foliage_density")
	for k in flowers.size():
		var xs := []
		for i in int(46 * dens):
			var p := gc + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, 7.5)
			if p.distance_to(POND) < 3.7 or SanctuaryTerrain.dist_to_paths(p) < 1.2 or p.distance_to(seat) < 1.3:
				continue
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), Vector3(p.x, g(p.x, p.y) - 0.02, p.y)))
		var mm := Kit.multimesh(s, Kit.prop(flowers[k]), xs, 38.0, false)
		mm.add_to_group("cat_foliage")
	for i in 7:
		var a := rng.randf() * TAU
		var p := gc + Vector2(cos(a), sin(a)) * rng.randf_range(5.5, 7.5)
		if SanctuaryTerrain.dist_to_paths(p) < 1.8:
			continue
		s.place_mesh(s._part_mesh("shrub_03"), s._ground(p.x, p.y), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.2), false)
	for i in 5:
		var p := Vector2(9.0, 12.5).lerp(seat, (i + 1) / 6.0) + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
		var st := Kit.mesh_node(s, Kit.rock_mesh(0.34, 40 + i, 0.08, Vector3(1.0, 0.18, 0.8)), slab, Kit.xf(Vector3(p.x, g(p.x, p.y) - 0.02, p.y), rng.randf() * TAU), false)
		st.add_to_group("cat_expansion")


func build_chamber() -> void:
	var c := SanctuaryTerrain.CHAMBER
	var cy := g(c.x, c.y)
	var x0 := c.x - 4.0
	var x1 := c.x + 4.0
	var z0 := c.y - 4.0
	var z1 := c.y + 4.0
	var th := 0.6
	# Floor
	blk(Vector3(8.0, 0.12, 8.0), Vector3(c.x, cy + 0.03, c.y), 0.0, slab, true)
	# Broken masonry walls: [side, from, to, [heights along the run]]; the south and east walls are
	# low ruins so the interior (altar, tablet, light shaft) reads from the approach path.
	var walls := [
		["n", -4.0, 4.0, [3.6, 3.2, 2.2, 1.0, 1.8, 2.8, 2.4]],
		["w", -4.0, 4.0, [3.6, 4.0, 3.8, 3.4, 2.6, 2.0]],
		["s", -4.0, 4.0, [2.0, 1.4, 0.5, 0.8, 1.2, 0.4, 0.9]],
		["e", -4.0, -1.3, [1.8, 1.3, 2.2]],
		["e", 1.3, 4.0, [1.6, 0.9, 1.0]],
	]
	var course := 0.42
	var wall_xf: Array = []
	for wseg in walls:
		var a: float = wseg[1]
		var b: float = wseg[2]
		var hs: Array = wseg[3]
		var side: String = wseg[0]
		var along_axis := Vector3(1, 0, 0) if side == "n" or side == "s" else Vector3(0, 0, 1)
		var base: Vector3 = {"n": Vector3(c.x, 0, z0), "s": Vector3(c.x, 0, z1), "w": Vector3(x0, 0, c.y), "e": Vector3(x1, 0, c.y)}[side]
		var rows := 10
		for row in rows:
			var u := a + (rng.randf_range(0.0, 0.45) if row % 2 == 1 else 0.0)
			while u < b - 0.05:
				var blen := minf(rng.randf_range(0.55, 1.05), b - u)
				var mid_u := u + blen * 0.5
				var tt := (mid_u - a) / (b - a) * (hs.size() - 1)
				var i0 := clampi(int(tt), 0, hs.size() - 2)
				var hloc := lerpf(hs[i0], hs[i0 + 1], tt - i0) + rng.randf_range(-0.25, 0.2)
				var y := (row + 0.5) * course
				if y < hloc:
					var p := base + along_axis * mid_u + Vector3(0, cy - 0.06 + y, 0)
					var inset := Vector3(along_axis.z, 0, along_axis.x) * rng.randf_range(-0.04, 0.04)
					var yaw := (0.0 if side == "n" or side == "s" else PI * 0.5) + rng.randf_range(-0.025, 0.025)
					var b3 := Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(rng.randf_range(-0.02, 0.02), 0, rng.randf_range(-0.03, 0.03)))
					wall_xf.append(Transform3D(b3.scaled(Vector3(blen - 0.03, course - 0.03, th * rng.randf_range(0.92, 1.0))), p + inset))
				u += blen
		# collision: one box per ~1 m of wall at the local height
		var n := int(ceil((b - a) / 1.0))
		for k in n:
			var ua := a + (b - a) * k / n
			var ub := a + (b - a) * (k + 1) / n
			var tm := ((ua + ub) * 0.5 - a) / (b - a) * (hs.size() - 1)
			var j0 := clampi(int(tm), 0, hs.size() - 2)
			var hh := maxf(lerpf(hs[j0], hs[j0 + 1], tm - j0) - 0.15, 0.3)
			var size := Vector3(ub - ua, hh, th) if side == "n" or side == "s" else Vector3(th, hh, ub - ua)
			Kit.static_box(s, size, Kit.xf(base + along_axis * (ua + ub) * 0.5 + Vector3(0, cy + hh * 0.5 - 0.06, 0)))
	var wmm := Kit.multimesh(s, Kit.box_mesh(Vector3.ONE, 0.05), wall_xf, 90.0, true, stone)
	wmm.add_to_group("cat_expansion")
	wmm.name = "ChamberMasonry"
	# fallen blocks from the breaches, outside the low south wall
	for k in 9:
		var p := Vector2(c.x + rng.randf_range(-3.5, 3.5), z1 + rng.randf_range(0.6, 2.4))
		var sc := Vector3(rng.randf_range(0.5, 0.95), course - 0.03, th * 0.95)
		var bb := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))).scaled(sc)
		rubble_xf.append(Transform3D(bb, Vector3(p.x, g(p.x, p.y) + 0.12, p.y)))
	# Doorway pilasters + a fallen lintel outside
	for sz in [-1.45, 1.45]:
		blk(Vector3(0.75, 2.9 if sz < 0 else 2.2, 0.75), Vector3(x1 + 0.05, cy + (1.35 if sz < 0 else 1.0), c.y + sz), 0.0, stone, true)
	blk(Vector3(3.6, 0.55, 0.7), Vector3(x1 + 2.2, g(x1 + 2.2, c.y + 2.6) + 0.2, c.y + 2.9), 0.5, stone, true, Vector3(0.1, 0, 0.12))
	# Broken column stumps flanking the approach
	var col := Kit.lathe([Vector2(0.36, 0), Vector2(0.3, 0.25), Vector2(0.26, 0.3), Vector2(0.26, 1.0)], 16, true, true)
	for p in [Vector2(x1 + 1.6, c.y - 2.6), Vector2(x1 + 1.6, c.y + 2.6)]:
		var h := 1.2 if p.y < c.y else 2.3
		var mi := Kit.mesh_node(s, col, stone, Transform3D(Basis().scaled(Vector3(1, h, 1)), Vector3(p.x, g(p.x, p.y), p.y)))
		mi.add_to_group("cat_expansion")
		Kit.static_box(s, Vector3(0.6, h, 0.6), Kit.xf(Vector3(p.x, g(p.x, p.y) + h * 0.5, p.y)))
	# Altar with the Heartstone (west wall)
	var ap := Vector3(x0 + 1.4, cy, c.y)
	blk(Vector3(1.3, 0.95, 1.9), ap + Vector3(0, 0.55, 0), 0.0, stone, true)
	blk(Vector3(1.55, 0.14, 2.15), ap + Vector3(0, 1.08, 0), 0.0, slab, false)
	heartstone = Node3D.new()
	heartstone.name = "AnimatedHeartstone"
	heartstone.position = ap + Vector3(0, 1.75, 0)
	s.add_child(heartstone)
	heartstone_y = heartstone.position.y
	heartstone_mat = Kit.crystal(Color(0.55, 0.4, 1.0), 1.4)
	var hm := MeshInstance3D.new()
	hm.mesh = Kit.crystal_mesh(0.7, 0.17, 5)
	hm.material_override = heartstone_mat
	hm.position.y = -0.3
	heartstone.add_child(hm)
	heartstone_light = OmniLight3D.new()
	heartstone_light.light_color = Color(0.72, 0.64, 1.0)
	heartstone_light.light_energy = 0.6
	heartstone_light.omni_range = 3.6
	heartstone_light.light_volumetric_fog_energy = 0.5
	heartstone.add_child(heartstone_light)
	var hr := HeartstoneReactive.new()
	hr.name = "Reactive_heartstone"
	s.add_child(hr)
	hr.position = heartstone.position
	hr.setup("heartstone", "the Heartstone relic", heartstone_light)
	# Offering bowls + candles on the altar
	Kit.place_prop(s, "brass_vase_01", Kit.xf(ap + Vector3(0.1, 1.15, -0.75), 0.0, Vector3.ONE * 0.6))
	Kit.place_prop(s, "ceramic_vase_01", Kit.xf(ap + Vector3(0.15, 1.15, 0.78), 1.0, Vector3.ONE * 0.55))
	for sz in [-0.45, 0.45]:
		Kit.place_prop(s, "brass_candleholders", Kit.xf(ap + Vector3(0.45, 1.15, sz)), "brass_candleholder_01")
	s._add_flame(ap + Vector3(0.45, 1.15 + 0.39, -0.45), 0.35, 0.25, true)
	var it := Interactable.make("heartstone_attune", "Attune to the Heartstone relic", "practice", "ritual_sanctuary",
		ap + Vector3(0, 1.1, 0), {"skills": {"arcane_orb": 0.2, "focus": 0.1}, "knowledge": {"attuned:heartstone": 1}}, "spell_casting", 4.5)
	it.kind = "practice"
	it.lore_id = "chamber_tablet"
	it.radius = 1.6
	it.stand_point = ap + Vector3(1.9, 0.0, 0.0)
	it.face_point = ap + Vector3(0, 1.6, 0)
	it.on_begin = func(): _heartstone_pulse()
	s.add_interactable(it)
	# Lore tablet set into the north wall
	var tp := Vector3(c.x + 0.6, cy, z0 + 0.36)
	blk(Vector3(1.5, 1.05, 0.14), tp + Vector3(0, 1.45, 0), 0.0, slab, false)
	var tg := MeshInstance3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(1.05, 0.75)
	tg.mesh = tq
	var tgm := ShaderMaterial.new()
	tgm.shader = load("res://shaders/magic/sigil.gdshader")
	tgm.set_shader_parameter("sides", 8)
	tgm.set_shader_parameter("color", Color(0.65, 0.5, 1.0))
	tgm.set_shader_parameter("intensity", 0.3)
	tgm.set_shader_parameter("spin", 0.02)
	tg.material_override = tgm
	tg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tg.position = tp + Vector3(0, 1.45, 0.08)
	s.add_child(tg)
	it = Interactable.make("chamber_tablet", "Read the Tablet of the Heartstone", "study", "ritual_sanctuary",
		tp + Vector3(0, 1.2, 0), {}, "", 4.0)
	it.kind = "study"
	it.book_id = "chamber_tablet"
	it.radius = 1.4
	it.stand_point = tp + Vector3(0, 0, 1.25)
	it.face_point = tp + Vector3(0, 1.45, 0)
	s.add_interactable(it)
	# Stone reading ledge with the Keeper's Daybook (south-east corner of the chamber, reader faces south)
	var lg := Vector3(c.x + 2.2, cy, c.y + 2.3)
	blk(Vector3(0.75, 0.95, 0.55), lg + Vector3(0, 0.5, 0), 0.0, stone, true)
	blk(Vector3(0.85, 0.1, 0.62), lg + Vector3(0, 1.0, 0), 0.0, slab, false, Vector3(-0.3, 0, 0))
	var closed := Kit.mesh_node(s, Kit.prop("book_encyclopedia_set_01", "book_encyclopedia_set_01_book05"), null,
		Transform3D(Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.3), lg + Vector3(-0.05, 1.07, 0.0)), false)
	it = Interactable.make("keepers_daybook", "Read the Keeper's Daybook", "study", "ritual_sanctuary", lg + Vector3(0, 1.0, 0), {}, "", 4.0)
	it.kind = "study"
	it.book_id = "keepers_daybook"
	it.radius = 1.4
	it.book_xf = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, 0.3), lg + Vector3(0, 1.07, -0.02))
	it.book_props = [closed]
	it.stand_point = lg + Vector3(0, 0, -0.85)
	it.face_point = lg + Vector3(0, 1.0, 0)
	s.add_interactable(it)
	# Fallen roof stones inside, rubble outside, a sun shaft through the open roof, drifting dust
	blk(Vector3(1.0, 0.5, 0.7), Vector3(c.x + 2.2, cy + 0.32, c.y - 2.6), 0.7, stone, true, Vector3(0.2, 0, 0.15))
	blk(Vector3(0.7, 0.4, 0.6), Vector3(c.x + 2.9, cy + 0.26, c.y + 2.8), 1.9, stone, true, Vector3(0, 0, 0.3))
	rubble(Vector2(c.x, c.y), 6.5, 30, 1.2)
	shaft(Vector3(c.x - 1.2, cy + 4.0, c.y), 7.5, 2.6, 0.2, 0.35, 0.26)
	var dust := GPUParticles3D.new()
	dust.amount = 40
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.position = Vector3(c.x - 1.0, cy + 1.8, c.y)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.6, 1.6, 2.6)
	pm.gravity = Vector3(0, 0.01, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.spread = 180.0
	pm.scale_min = 0.25
	pm.scale_max = 0.6
	pm.color = Color(1.0, 0.9, 0.72, 0.35)
	dust.process_material = pm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.03, 0.03)
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/magic/energy_mote.gdshader")
	dm.set_shader_parameter("hdr_boost", 0.9)
	dq.material = dm
	dust.draw_pass_1 = dq
	dust.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 4, 6))
	dust.name = "AnimatedDust"
	s.add_child(dust)


func _heartstone_pulse() -> void:
	var tw := s.create_tween()
	tw.tween_property(heartstone_light, "light_energy", 1.5, 1.4)
	tw.tween_property(heartstone_light, "light_energy", 0.9, 2.0)  # attuned: stays brighter than before


func build_watchpoint() -> void:
	var w := SanctuaryTerrain.WATCH
	var wy := g(w.x, w.y)
	var top := wy + 2.0
	var half := 3.2
	# Raised platform with a ragged edge course
	blk(Vector3(half * 2.0, 2.2, half * 2.0), Vector3(w.x, top - 1.1, w.y), 0.0, stone, true)
	blk(Vector3(half * 2.0 - 0.3, 0.1, half * 2.0 - 0.3), Vector3(w.x, top + 0.02, w.y), 0.0, slab, false)
	# Parapet: north and west edges with gaps; the east edge is where the stairs arrive
	for seg in [[Vector3(w.x - 1.6, 0, w.y - half + 0.18), Vector3(3.0, 0.9, 0.36)], [Vector3(w.x + 2.1, 0, w.y - half + 0.18), Vector3(2.0, 0.6, 0.36)],
			[Vector3(w.x - half + 0.18, 0, w.y + 0.9), Vector3(0.36, 0.9, 4.0)], [Vector3(w.x - 0.8, 0, w.y + half - 0.18), Vector3(4.0, 0.75, 0.36)]]:
		var p: Vector3 = seg[0]
		var sz: Vector3 = seg[1]
		blk(sz, Vector3(p.x, top + sz.y * 0.5, p.z), 0.0, stone, true)
	# Broken tower stump in the north-west corner
	var tpos := Vector3(w.x - 2.0, top, w.y - 2.0)
	var tower := Kit.mesh_node(s, Kit.lathe([Vector2(1.05, 0), Vector2(1.0, 2.6), Vector2(0.0, 2.6)], 14, false, true), stone, Kit.xf(tpos))
	tower.add_to_group("cat_expansion")
	var tb := StaticBody3D.new()
	var tcs := CollisionShape3D.new()
	var tsh := CylinderShape3D.new()
	tsh.radius = 1.05
	tsh.height = 2.6
	tcs.shape = tsh
	tb.add_child(tcs)
	tb.position = tpos + Vector3(0, 1.3, 0)
	s.add_child(tb)
	for k in 4:
		var a := k * 0.9 + 0.3
		blk(Vector3(0.55, 0.45 + 0.35 * (k % 2), 0.4), tpos + Vector3(cos(a) * 0.82, 2.75 + 0.15 * (k % 2), sin(a) * 0.82), a, stone, false)
	# Stairs up from the east (ramp collider flush with the ground, crisp visual steps)
	var foot_x := w.x + half + 6.0
	var gf := g(foot_x, w.y)
	var steps := 11
	var run := 6.0 / steps
	var rise := (top - gf) / steps
	for i in steps:
		var x := w.x + half + 6.0 - (i + 0.5) * run
		var t_top := gf + (i + 1) * rise
		var base := g(x, w.y) - 0.3
		blk(Vector3(run + 0.02, t_top - base, 3.0), Vector3(x, (t_top + base) * 0.5, w.y), 0.0, stone, false)
	var dir := Vector2(-6.0, top - gf)
	var length := dir.length() + 1.0
	var ang := atan2(-(top - gf), 6.0)
	var ramp_b := Basis(Vector3(0, 0, 1), ang)
	var mid := Vector3(w.x + half + 3.0, (top + gf) * 0.5, w.y)
	Kit.static_box(s, Vector3(length, 0.3, 3.0), Transform3D(ramp_b, mid - ramp_b.y * 0.15))
	# low cheek walls along the stair: they read as masonry and keep the path off the ramp's raw edge
	for sz in [-1.7, 1.7]:
		var cheek := Basis(Vector3(0, 0, 1), ang)
		blk(Vector3(length - 0.6, 0.5, 0.35), mid + cheek.y * 0.12 + Vector3(0.3, 0.1, sz), 0.0, stone, true, Vector3(0, 0, ang))
	# Bench facing the sanctuary (north-east) + plaque on the north parapet
	var bench := Vector2(w.x - 0.6, w.y + 1.7)
	var look := (Vector2.ZERO - bench).normalized()
	var byaw := atan2(look.x, look.y)
	var bb := Basis(Vector3.UP, byaw)
	blk(Vector3(1.6, 0.1, 0.45), Vector3(bench.x, top + SEAT_H - 0.05, bench.y), byaw, slab, false)
	for sx in [-0.6, 0.6]:
		blk(Vector3(0.18, SEAT_H - 0.1, 0.36), Vector3(bench.x, top + (SEAT_H - 0.1) * 0.5, bench.y) + bb * Vector3(sx, 0, 0), byaw, stone, false)
	var stand := Vector3(bench.x, top, bench.y) + bb * Vector3(0, 0, 0.42)
	var it := Interactable.make("watchpoint_rest", "Sit and rest on the watchpoint bench", "rest", "ritual_sanctuary",
		Vector3(bench.x, top, bench.y), {"skills": {"focus": 0.08}}, "sit", 6.0)
	it.kind = "rest"
	it.radius = 1.2
	it.stand_point = stand
	it.face_point = stand + bb * Vector3(0, 1.2, 3.0)
	it.seat_body = Kit.static_box(s, Vector3(1.6, SEAT_H, 0.45), Transform3D(bb, Vector3(bench.x, top + SEAT_H * 0.5, bench.y)))
	it.sit_point = Vector3(bench.x, top, bench.y) + bb * Vector3(0, 0, 0.02)
	s.add_interactable(it)
	var pl := Vector3(w.x + 2.1, top, w.y - half + 0.4)
	blk(Vector3(0.9, 0.55, 0.08), pl + Vector3(0, 0.75, 0), 0.0, Kit.metal(Color(0.55, 0.45, 0.3), 0.5), false, Vector3(-0.5, 0, 0))
	it = Interactable.make("watchpoint_survey", "Survey the realm from the Watchpoint", "explore", "ritual_sanctuary",
		pl, {"knowledge": {"survey:realm": 1}, "discover": ["village_square", "academy_courtyard", "cloud_temple"]}, "look_around", 5.0)
	it.kind = "explore"
	it.lore_id = "watchpoint_plaque"
	it.radius = 1.5
	it.stand_point = pl + Vector3(0, 0, 1.0)
	it.face_point = Vector3(10.0, top + 1.5, -60.0)
	s.add_interactable(it)
	# A lantern for the night and rubble at the foot of the platform
	s._add_flame(Vector3(w.x + half - 0.4, top + 1.0, w.y + half - 0.4), 0.45, 0.4, true)
	Kit.place_prop(s, "Lantern_01", Kit.xf(Vector3(w.x + half - 0.4, top + 0.84, w.y + half - 0.4), 0.0, Vector3.ONE * 1.4), "Lantern_01")
	Kit.place_prop(s, "Lantern_01", Kit.xf(Vector3(w.x + half - 0.4, top + 0.84, w.y + half - 0.4), 0.0, Vector3.ONE * 1.4), "Lantern_01_glass")
	blk(Vector3(0.3, 0.84, 0.3), Vector3(w.x + half - 0.4, top + 0.42, w.y + half - 0.4), 0.0, stone, true)
	rubble(Vector2(w.x, w.y), 5.5, 20, 1.6)


func build_training_targets() -> void:
	var tc := SanctuaryTerrain.TRAINING_CENTER
	var angles := [-45.0, 15.0, -100.0, -150.0]
	for k in 4:
		var a := deg_to_rad(angles[k])
		var p := tc + Vector2(cos(a), sin(a)) * 5.0
		var gy := g(p.x, p.y)
		var to_c := (tc - p).normalized()
		var yaw := atan2(to_c.x, to_c.y)
		var b := Basis(Vector3.UP, yaw)
		var base := Vector3(p.x, gy, p.y)
		blk(Vector3(0.16, 1.7, 0.16), base + Vector3(0, 0.85, 0), yaw, wood, true)
		blk(Vector3(1.0, 0.12, 0.12), base + Vector3(0, 1.25, 0), yaw, wood, false)
		var disc := Kit.mesh_node(s, Kit.lathe([Vector2(0.48, 0), Vector2(0.5, 0.06), Vector2(0.48, 0.12)], 24, true, true), stone,
			Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), base + Vector3(0, 1.35, 0) + b * Vector3(0, 0, 0.1)))
		disc.add_to_group("cat_expansion")
		var disc_body := Kit.static_box(s, Vector3(1.0, 1.0, 0.16), Transform3D(b, base + Vector3(0, 1.35, 0) + b * Vector3(0, 0, 0.1)))
		var sig := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.92, 0.92)
		sig.mesh = q
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/magic/sigil.gdshader")
		m.set_shader_parameter("sides", 3 + k)
		m.set_shader_parameter("color", Color(0.45, 0.7, 1.0))
		m.set_shader_parameter("intensity", 0.3)
		m.set_shader_parameter("spin", 0.2)
		m.set_shader_parameter("seed", float(k) + 1.0)
		sig.material_override = m
		sig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sig.transform = Transform3D(b, base + Vector3(0, 1.35, 0) + b * Vector3(0, 0, 0.24))
		s.add_child(sig)
		var id := "rune_target_%d" % (k + 1)
		rune_sigils[id] = m
		var rr := RuneReactive.new()
		rr.name = "Reactive_" + id
		s.add_child(rr)
		rr.global_transform = Transform3D(b, base + Vector3(0, 1.35, 0) + b * Vector3(0, 0, 0.2))
		rr.setup(id, "rune target %d" % (k + 1), m, disc, [disc, sig])
		rr.bodies.append(disc_body)
		var it := Interactable.make(id, "Strike rune target %d" % (k + 1), "practice", "mage_training_grounds",
			base + Vector3(0, 1.35, 0), {"skills": {"arcane_orb": 0.08}}, "magic_attack_1h", 2.4)
		it.kind = "practice"
		it.lore_id = "training_ledger"
		it.radius = 3.6
		var sp := p + to_c * 3.0
		it.stand_point = Vector3(sp.x, g(sp.x, sp.y), sp.y)
		it.face_point = base + Vector3(0, 1.35, 0)
		it.on_begin = func(): _flash_target(id)
		s.add_interactable(it)


func _flash_target(id: String) -> void:
	var m: ShaderMaterial = rune_sigils[id]
	var tw := s.create_tween()
	tw.tween_interval(0.85)  # the strike lands
	tw.tween_method(func(v: float): m.set_shader_parameter("intensity", v), 0.3, 4.0, 0.12)
	tw.tween_method(func(v: float): m.set_shader_parameter("intensity", v), 4.0, 0.9, 1.2)  # stays lit once struck


## Practice props for elemental experiments + the marked stone at the forest gate (story clue).
func build_magic_props() -> void:
	var tc := SanctuaryTerrain.TRAINING_CENTER
	# practice crystal on a stone stand
	var cp := tc + Vector2(cos(deg_to_rad(75.0)), sin(deg_to_rad(75.0))) * 5.0
	var cy := g(cp.x, cp.y)
	var stand := Kit.mesh_node(s, Kit.lathe([Vector2(0.32, 0), Vector2(0.28, 0.1), Vector2(0.14, 0.18), Vector2(0.12, 0.9), Vector2(0.24, 0.98), Vector2(0.24, 1.05)], 12, false, true), stone, Kit.xf(Vector3(cp.x, cy, cp.y)))
	stand.add_to_group("cat_expansion")
	var stand_body := Kit.static_box(s, Vector3(0.5, 1.05, 0.5), Kit.xf(Vector3(cp.x, cy + 0.52, cp.y)))
	var pc := PracticeCrystal.new()
	pc.name = "Reactive_practice_crystal"
	s.add_child(pc)
	pc.position = Vector3(cp.x, cy, cp.y)
	var cm := MeshInstance3D.new()
	cm.mesh = Kit.crystal_mesh(0.5, 0.13, 17)
	cm.material_override = Kit.crystal(Color(0.5, 0.8, 1.0), 1.6)
	cm.position.y = 1.45
	pc.add_child(cm)
	var cl := FX.light(Color(0.55, 0.8, 1.0), 0.8, 3.0)
	cl.position.y = 1.5
	pc.add_child(cl)
	pc.setup("practice_crystal", "the practice crystal", cm, cl)
	pc.bodies.append(stand_body)
	# straw practice dummy
	var dp := tc + Vector2(cos(deg_to_rad(120.0)), sin(deg_to_rad(120.0))) * 5.2
	var dy := g(dp.x, dp.y)
	var dummy := PracticeDummy.new()
	dummy.name = "Reactive_practice_dummy"
	s.add_child(dummy)
	dummy.position = Vector3(dp.x, dy, dp.y)
	var face := (tc - dp).normalized()
	dummy.rotation.y = atan2(face.x, face.y)
	var body := Node3D.new()
	dummy.add_child(body)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.72, 0.6, 0.38)
	straw.roughness = 0.95
	Kit.mesh_node(body, Kit.box_mesh(Vector3(0.1, 1.9, 0.1), 0.01), wood, Kit.xf(Vector3(0, 0.95, 0)))
	Kit.mesh_node(body, Kit.box_mesh(Vector3(0.9, 0.08, 0.08), 0.01), wood, Kit.xf(Vector3(0, 1.42, 0)))
	var sack := CapsuleMesh.new()
	sack.radius = 0.2
	sack.height = 0.75
	Kit.mesh_node(body, sack, straw, Kit.xf(Vector3(0, 1.22, 0)))
	var head := SphereMesh.new()
	head.radius = 0.14
	head.height = 0.28
	Kit.mesh_node(body, head, straw, Kit.xf(Vector3(0, 1.72, 0)))
	var dbody := Kit.static_box(s, Vector3(0.45, 1.8, 0.45), Kit.xf(Vector3(dp.x, dy + 0.9, dp.y)))
	dummy.setup("practice_dummy", "the straw practice dummy", body, straw)
	dummy.bodies.append(dbody)
	# the marked stone near the forest gate: a carving too faint to read until a rune is woken in it
	var mp := Vector2(-6.4, -17.6)
	var my := g(mp.x, mp.y)
	var to_path := Vector2(-6.4, -20.8) - mp
	var myaw := atan2(to_path.x, to_path.y)
	blk(Vector3(0.75, 1.35, 0.42), Vector3(mp.x, my + 0.6, mp.y), myaw, stone, true, Vector3(0.04, 0, -0.05))
	var glyph := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(0.6, 0.6)
	glyph.mesh = gq
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/magic/sigil.gdshader")
	gm.set_shader_parameter("sides", 7)
	gm.set_shader_parameter("color", Color(1.0, 0.82, 0.45))
	gm.set_shader_parameter("spin", 0.0)
	gm.set_shader_parameter("seed", 31.0)
	glyph.material_override = gm
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mb := Basis(Vector3.UP, myaw)
	glyph.transform = Transform3D(mb, Vector3(mp.x, my + 0.78, mp.y) + mb * Vector3(0, 0, 0.23))
	s.add_child(glyph)
	var ms := MarkedStone.new()
	ms.name = "Reactive_marked_stone"
	s.add_child(ms)
	ms.position = Vector3(mp.x, my + 0.78, mp.y) + mb * Vector3(0, 0, 0.2)
	ms.setup("marked_stone", "the weathered marked stone by the gate", gm, "clue:gate_mark")


## The alchemy table west of the dais (between the colonnade and the ruin wall).
func build_alchemy() -> void:
	var tp := Vector3(-9.6, 0, 5.5)
	tp.y = g(tp.x, tp.z)
	var table := AlchemyTable.new()
	table.name = "AlchemyTable"
	table.build(s, tp, 0.0)
	table.remember_homes()
	s.alchemy = table
	var it := Interactable.make("alchemy_table", "Experiment at the alchemy table", "craft", "ritual_sanctuary", tp + Vector3(0, 0.85, 0), {}, "", 3.0)
	it.kind = "craft"
	it.radius = 1.4
	it.stand_point = Vector3(tp.x + 0.6, tp.y, tp.z - 0.05)
	it.face_point = tp + Vector3(0, 0.85, 0)
	it.custom_activity = func(c): return await table.experiment(c)
	s.add_interactable(it)


## Wild residents: a fox by the west ruins, a doe and a stag in the east meadow, koi in the pond.
func build_wildlife() -> void:
	var wl := Node3D.new()
	wl.name = "AnimatedWildlife"
	s.add_child(wl)
	var specs := [["fox", "res://assets/wildlife/fox.glb", Vector3(-16.0, 0, 9.0), 0.24, 11, 9.0],
		["deer", "res://assets/wildlife/deer.glb", Vector3(36.0, 0, 21.0), 0.34, 12, 12.0],
		["stag", "res://assets/wildlife/stag.glb", Vector3(38.5, 0, 17.0), 0.42, 13, 12.0]]
	for sp in specs:
		var a := Animal.new()
		wl.add_child(a)
		var h: Vector3 = sp[2]
		h.y = g(h.x, h.z)
		a.global_position = h
		a.setup(sp[0], sp[1], s, h, sp[3], sp[4])
		a.home_radius = sp[5]
	var water_y := g(POND.x + 3.6, POND.y) - 0.14
	for k in 5:
		var f := PondFish.new()
		wl.add_child(f)
		f.setup("res://assets/wildlife/koi.glb", Vector3(POND.x, water_y, POND.y), 0.9 + k * 0.38, 40 + k)


func finish() -> void:
	# All loose rubble as one MultiMesh (one draw call), shadows only nearby
	var mm := Kit.multimesh(s, Kit.box_mesh(Vector3(0.42, 0.26, 0.34), 0.05), rubble_xf, 55.0, true, stone)
	mm.add_to_group("cat_expansion")
	s.add_child(AmbientLife.new(s))


func process(t: float) -> void:
	if heartstone:
		heartstone.position.y = heartstone_y + sin(t * 1.1) * 0.05
		heartstone.rotation.y = t * 0.25
