class_name HouseBuilder
extends RefCounted
## Believable buildings for the Fantasy Village (and anything else that needs houses), on the realistic toolkit
## (world-quality gate: "no clone cities", photographic materials). A house is built, not boxed:
##   ground storey  coursed MASONRY (StoneBuilder: individual stones, chamfered, mortar gaps) with a real doorway
##                  and window openings (sills, stone lintels over them)
##   upper storey   a JETTIED HALF-TIMBER frame (oak posts, rails, braces standing proud of the plaster infill)
##   roof           steep SLATE with thickness and overhang, a ridge beam, plastered or timbered gables
##   chimney        stacked stone with a cap and a wisp of smoke
##   openings       recessed glass that reflects by day and glows warm at night, mullions, open shutters,
##                  a plank door with a frame and a worn step, flower boxes, a lantern by the door
## Every house differs by its seed (size, storeys, door side, window rhythm, colours, details).

var area: Node3D                     # the area (ground_at / height callable, night_only)
var ground: Callable
var mats := {}
var rng := RandomNumberGenerator.new()
var stats := {"houses": 0}
const ROOF_LAYER := 512              # layer 10: roofs, only for "is something overhead" (rain shelter)
var doors: Array = []                # [{pos, yaw}] doorsteps in build order (TownLife home:N anchors)


func _init(a: Node3D, ground_fn: Callable) -> void:
	area = a
	ground = ground_fn
	mats = {
		"stone": RealKit.stone_mat("castle_wall_slates") if RealKit.enabled() else Kit.tri("castle_wall_slates", "1k", 0.5, 0.2),
		"plaster_a": Kit.tri("plastered_wall_02", "1k", 0.35, 0.0, Color(0.96, 0.93, 0.86)),
		"plaster_b": Kit.tri("plastered_wall_02", "1k", 0.35, 0.0, Color(0.93, 0.86, 0.74)),
		"plaster_c": Kit.tri("plastered_wall_02", "1k", 0.35, 0.0, Color(0.86, 0.88, 0.84)),
		"timber": Kit.tri("dark_wooden_planks", "1k", 0.6, 0.0, Color(0.42, 0.32, 0.25)),
		"door": Kit.tri("dark_wooden_planks", "1k", 1.2, 0.0, Color(0.55, 0.38, 0.26)),
		"roof": Kit.uvmat("roof_slates_02", "1k", Vector2(0.9, 0.9)),
		"roof_b": Kit.uvmat("roof_slates_02", "1k", Vector2(0.9, 0.9), Color(0.78, 0.7, 0.66)),
		"glass": _glass(),
		"glow": Kit.emissive(Color(1.0, 0.7, 0.38), 3.2),
	}


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.12, 0.13)
	m.metallic = 0.6
	m.roughness = 0.06
	return m


## A house at `pos` facing `yaw` (its front, with the door, faces local +Z). w x d footprint in metres.
func house(pos: Vector3, yaw: float, w: float, d: float, seed: int, storeys := 2) -> Node3D:
	rng.seed = seed
	var root := Node3D.new()
	root.name = "House_%d" % seed
	root.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	area.add_child(root)
	var xf := root.transform
	var plaster: Material = [mats.plaster_a, mats.plaster_b, mats.plaster_c][seed % 3]
	var roof: Material = mats.roof if seed % 4 != 3 else mats.roof_b
	var fh := 2.9
	var base := pos.y
	var door_x := rng.randf_range(-w * 0.22, w * 0.22)
	# ---- ground storey: masonry with a doorway and windows
	var sb := StoneBuilder.new(ground, seed)
	sb.base_y = base - 1.0
	sb.top_y = base + fh + 1.0
	var hw := w * 0.5
	var hd := d * 0.5
	var c00 := xf * Vector3(-hw, 0, hd)
	var c10 := xf * Vector3(hw, 0, hd)
	var c11 := xf * Vector3(hw, 0, -hd)
	var c01 := xf * Vector3(-hw, 0, -hd)
	var th := 0.5
	# front wall: left of the door, right of the door, masonry over it
	_wall_open(sb, xf, Vector3(-hw, 0, hd), Vector3(hw, 0, hd), fh, th, base, [[door_x - 0.6, door_x + 0.6, 0.0, 2.2]] + _windows(w, door_x, 1.0, 2.0))
	_wall_open(sb, xf, Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), fh, th, base, _windows(w, 99.0, 1.0, 2.0))
	_wall_open(sb, xf, Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), fh, th, base, _windows(d, 99.0, 1.0, 2.0) if rng.randf() < 0.6 else [])
	_wall_open(sb, xf, Vector3(hw, 0, -hd), Vector3(hw, 0, hd), fh, th, base, _windows(d, 99.0, 1.0, 2.0) if rng.randf() < 0.6 else [])
	sb.finish(area, mats.stone, "Masonry_%d" % seed)          # StoneBuilder works in world space
	# a solid body for the house (the walls' colliders are per course; one box keeps walkers out)
	Kit.static_box(root, Vector3(w - 0.1, fh * storeys, d - 0.1), Kit.xf(Vector3(0, fh * storeys * 0.5, 0)))
	# interior darkness behind the glass / doorway (a lit room at night)
	Kit.block(root, Vector3(w - 1.0, fh - 0.2, d - 1.0), Kit.xf(Vector3(0, fh * 0.5, 0)), Kit.emissive(Color(0.02, 0.018, 0.016), 0.0), false, 0.0)
	_door(root, Vector3(door_x, 0, hd))
	for win in _windows(w, door_x, 1.0, 2.0):
		_window(root, Vector3((win[0] + win[1]) * 0.5, 1.5, hd - 0.08), 0.0, plaster, rng.randf() < 0.35)
	var top := fh
	# ---- upper storey: jettied half-timber
	if storeys > 1:
		var jet := 0.3
		var uw := w + jet * 2.0
		var ud := d + jet * 2.0
		Kit.block(root, Vector3(uw - 0.12, fh - 0.1, ud - 0.12), Kit.xf(Vector3(0, fh * 1.5, 0)), plaster, false, 0.02)
		# the jetty's beam ends showing under the overhang
		for i in int(uw / 0.7):
			var x := -uw * 0.5 + 0.35 + i * 0.7
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.16, 0.18, 0.5), 0.01), mats.timber, Kit.xf(Vector3(x, fh - 0.05, ud * 0.5 - 0.2)))
		_timber_frame(root, uw, ud, fh, fh, plaster)
		for win in _windows(uw, 99.0, 1.0, 1.9):
			_window(root, Vector3((win[0] + win[1]) * 0.5, fh + 1.45, ud * 0.5 + 0.02), 0.0, plaster, rng.randf() < 0.3)
			_window(root, Vector3((win[0] + win[1]) * 0.5, fh + 1.45, -ud * 0.5 - 0.02), PI, plaster, false)
		top = fh * 2.0
		w = uw
		d = ud
	# ---- roof
	var rise := d * rng.randf_range(0.5, 0.62)
	Kit.mesh_node(root, Kit.gable_end(d, rise, 0.22), plaster, Kit.xf(Vector3(-w * 0.5 + 0.06, top, 0)))
	Kit.mesh_node(root, Kit.gable_end(d, rise, 0.22), plaster, Kit.xf(Vector3(w * 0.5 - 0.06, top, 0)))
	Kit.mesh_node(root, Kit.gable_roof(w + 0.2, d + 0.2, rise, 0.5, 0.16), roof, Kit.xf(Vector3(0, top, 0)))
	# what the roof covers, eaves included (WeatherSystem: out of the rain under here). Its own layer: no walking on
	# it, no navmesh on it, only the overhead test sees it.
	var cover := StaticBody3D.new()
	cover.name = "RoofCover"
	cover.collision_layer = ROOF_LAYER
	cover.collision_mask = 0
	var ccs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(w + 1.2, 0.2, d + 1.2)
	ccs.shape = cbox
	ccs.position = Vector3(0, top + 0.15, 0)
	cover.add_child(ccs)
	root.add_child(cover)
	Kit.mesh_node(root, Kit.box_mesh(Vector3(w + 1.1, 0.2, 0.26), 0.02), mats.timber, Kit.xf(Vector3(0, top + rise + 0.08, 0)))
	# gable timbers: a king post and two braces
	for sx: float in [-1.0, 1.0]:
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.14, rise * 0.95, 0.16), 0.01), mats.timber, Kit.xf(Vector3(sx * (w * 0.5 - 0.02), top + rise * 0.47, 0)))
	# ---- chimney with smoke
	var cx := rng.randf_range(-w * 0.3, w * 0.3)
	var cz := -d * 0.2
	var csb := StoneBuilder.new(ground, seed + 7)
	var chim_h := top + rise + 1.4
	var cw := xf * Vector3(cx, 0, cz)
	var y := top + rise * 0.4
	while y < chim_h:
		csb.block(Transform3D(Basis(Vector3.UP, yaw), cw + Vector3(0, base + y + 0.18 - pos.y, 0)), Vector3(0.8, 0.36, 0.8), 0.05, 0.03)
		y += 0.38
	csb.block(Transform3D(Basis(Vector3.UP, yaw), cw + Vector3(0, base + chim_h + 0.08 - pos.y, 0)), Vector3(1.0, 0.16, 1.0), 0.0, 0.02)
	csb.finish(area, mats.stone, "Chimney_%d" % seed)
	var smoke := FX.particles(10, 6.0, FX.pm_puff("smoke"), FX.puff_mesh(0.8))
	smoke.position = Vector3(cx, chim_h + 0.4, cz)
	smoke.emitting = true
	root.add_child(smoke)
	# ---- details: lantern by the door (night), a flower box, a barrel or crates
	var lamp := Kit.omni(root, Vector3(door_x + 0.9, 2.3, d * 0.5 + 0.6), Color(1.0, 0.66, 0.36), 0.9, 6.0)
	# the doorstep (TownLife: the resident's way in and out), facing out of the house
	doors.append({"pos": root.transform * Vector3(door_x, 0.0, hd + 0.75), "yaw": root.rotation.y})
	if area.has_method("night_only"):
		area.night_only(lamp)
	if rng.randf() < 0.6:
		Kit.place_prop_all(root, "wooden_barrels_01", Kit.xf(Vector3(hw + 0.8, 0, hd - 0.8), rng.randf() * TAU, Vector3.ONE * 0.8), true)
	stats.houses += 1
	return root


func _windows(w: float, door_x: float, wid: float, _h: float) -> Array:
	var out := []
	var n := maxi(1, int(w / 2.6))
	for i in n:
		var x := -w * 0.5 + w * (i + 0.5) / n
		if absf(x - door_x) < 1.4:
			continue
		out.append([x - wid * 0.5, x + wid * 0.5, 0.9, 2.1])
	return out


## A masonry wall from local a to b with openings [t0, t1, y0, y1] along it (t in local metres along the wall
## measured on its main axis, from the wall's middle): full-height piers between openings, a sill under each
## window, masonry above each opening on a stone lintel.
func _wall_open(sb: StoneBuilder, xf: Transform3D, a: Vector3, b: Vector3, h: float, th: float, base: float, openings: Array) -> void:
	var along := (b - a)
	var L := along.length()
	var dir := along / L
	var cuts := []
	for o in openings:
		# o's x range is relative to the wall's centre along its axis
		var t0: float = float(o[0]) + L * 0.5
		var t1: float = float(o[1]) + L * 0.5
		if t1 <= 0.3 or t0 >= L - 0.3:
			continue
		cuts.append([clampf(t0, 0.3, L - 0.3), clampf(t1, 0.3, L - 0.3), float(o[2]), float(o[3])])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var t := 0.0
	for ct in cuts:
		if ct[0] - t > 0.2:
			sb.wall(xf * (a + dir * t), xf * (a + dir * ct[0]), h, th, 0.0, 0.48, 0.0, base)
		if float(ct[2]) > 0.2:
			sb.wall(xf * (a + dir * ct[0]), xf * (a + dir * ct[1]), float(ct[2]), th, 0.0, 0.45, 0.0, base)
		# lintel and masonry above
		var lp := xf * (a + dir * ((float(ct[0]) + float(ct[1])) * 0.5))
		var wd := xf.basis * dir
		sb.block(Transform3D(Basis(Vector3.UP, atan2(-wd.z, wd.x)), Vector3(lp.x, base + float(ct[3]) + 0.13, lp.z)), Vector3(float(ct[1]) - float(ct[0]) + 0.5, 0.26, th + 0.04), 0.0, 0.03)
		if h - float(ct[3]) > 0.5:
			sb.wall(xf * (a + dir * ct[0]), xf * (a + dir * ct[1]), h, th, 0.0, 0.48, float(ct[3]) + 0.26, base)
		t = ct[1]
	if L - t > 0.2:
		sb.wall(xf * (a + dir * t), xf * (a + dir * L), h, th, 0.0, 0.48, 0.0, base)


func _timber_frame(root: Node3D, w: float, d: float, y0: float, fh: float, _plaster: Material) -> void:
	var tm: Material = mats.timber
	for face in 4:
		var long := face < 2
		var span := w if long else d
		var off := (d * 0.5 if long else w * 0.5) + 0.03
		var sgn := 1.0 if face % 2 == 0 else -1.0
		var basis := Basis(Vector3.UP, 0.0 if long else PI * 0.5)
		var place := func(local: Vector3, size: Vector3, roll := 0.0) -> void:
			var p := local
			var b := basis * Basis(Vector3.FORWARD, roll)
			var at := Vector3(p.x, p.y, sgn * off) if long else Vector3(sgn * off, p.y, p.x)
			Kit.mesh_node(root, Kit.box_mesh(size, 0.012), tm, Transform3D(b, at))
		var nposts := int(span / 1.25) + 1
		for i in nposts:
			var x := -span * 0.5 + span * i / maxf(nposts - 1, 1)
			place.call(Vector3(x, y0 + fh * 0.5, 0), Vector3(0.18, fh, 0.12))
		for yy in [y0 + 0.1, y0 + fh - 0.08, y0 + fh * 0.42]:
			place.call(Vector3(0, yy, 0), Vector3(span + 0.1, 0.16, 0.12))
		for i in range(0, nposts - 1, 2):
			var x0 := -span * 0.5 + span * i / maxf(nposts - 1, 1)
			var x1 := -span * 0.5 + span * (i + 1) / maxf(nposts - 1, 1)
			var ln := Vector2(x1 - x0, fh * 0.42).length()
			place.call(Vector3((x0 + x1) * 0.5, y0 + fh * 0.21, 0), Vector3(ln, 0.13, 0.11), atan2(fh * 0.42, x1 - x0) * (1.0 if int(i / 2.0) % 2 == 0 else -1.0))


func _window(root: Node3D, at: Vector3, yaw: float, _plaster: Material, shutters: bool) -> void:
	var b := Basis(Vector3.UP, yaw)
	Kit.mesh_node(root, Kit.box_mesh(Vector3(0.95, 1.1, 0.05), 0.005), mats.glass, Transform3D(b, at), false)
	var glow := Kit.mesh_node(root, Kit.box_mesh(Vector3(0.9, 1.05, 0.04), 0.005), mats.glow, Transform3D(b, at + b * Vector3(0, 0, -0.02)), false)
	if area.has_method("night_only") and rng.randf() < 0.75:
		area.night_only(glow)
	else:
		glow.queue_free()
	# frame and mullions
	for k in [[Vector3(0, 0.6, 0.04), Vector3(1.15, 0.12, 0.12)], [Vector3(0, -0.6, 0.06), Vector3(1.25, 0.12, 0.2)], [Vector3(0.53, 0, 0.04), Vector3(0.1, 1.2, 0.12)],
			[Vector3(-0.53, 0, 0.04), Vector3(0.1, 1.2, 0.12)], [Vector3(0, 0, 0.03), Vector3(0.05, 1.1, 0.06)], [Vector3(0, 0.05, 0.03), Vector3(0.95, 0.05, 0.06)]]:
		Kit.mesh_node(root, Kit.box_mesh(k[1], 0.008), mats.timber, Transform3D(b, at + b * (k[0] as Vector3)), false)
	if shutters:
		for sx: float in [-1.0, 1.0]:
			var sb := b * Basis(Vector3.UP, sx * 1.9)
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.5, 1.15, 0.05), 0.008), mats.door, Transform3D(sb, at + b * Vector3(sx * 0.82, 0, 0.12)), false)
	if rng.randf() < 0.4:
		# a flower box under the sill
		Kit.mesh_node(root, Kit.box_mesh(Vector3(1.0, 0.22, 0.3), 0.01), mats.timber, Transform3D(b, at + b * Vector3(0, -0.78, 0.2)))
		var fl := NatureKit.mesh(["Flower_3_Group", "Flower_4_Group"][rng.randi() % 2])
		NatureKit.scatter(root, fl, [Transform3D(b.scaled(Vector3.ONE * 0.45), at + b * Vector3(-0.25, -0.67, 0.2)), Transform3D(b.scaled(Vector3.ONE * 0.4), at + b * Vector3(0.25, -0.67, 0.2))], {"vis_end": 60.0, "name": "WindowFlowers"})


func _door(root: Node3D, at: Vector3) -> void:
	Kit.mesh_node(root, Kit.box_mesh(Vector3(1.12, 2.15, 0.08), 0.01), mats.door, Kit.xf(at + Vector3(0, 1.07, -0.12)), false)
	for k in [[Vector3(-0.62, 1.1, -0.06), Vector3(0.14, 2.3, 0.2)], [Vector3(0.62, 1.1, -0.06), Vector3(0.14, 2.3, 0.2)]]:
		Kit.mesh_node(root, Kit.box_mesh(k[1], 0.01), mats.timber, Kit.xf(at + (k[0] as Vector3)), false)
	# the worn door step
	Kit.block(root, Vector3(1.5, 0.18, 0.7), Kit.xf(at + Vector3(0, 0.05, 0.3)), mats.stone, false, 0.03)
	# a slated door hood on two timber brackets: someone at the door stands out of the rain
	var hood_w := 2.0
	var proj := 1.3
	var tilt := 0.2
	var hb := Basis(Vector3.RIGHT, tilt)
	Kit.mesh_node(root, Kit.box_mesh(Vector3(hood_w, 0.07, proj + 0.1), 0.01), mats.roof, Transform3D(hb, at + Vector3(0, 2.62 - sin(tilt) * proj * 0.5, proj * 0.5)))
	Kit.mesh_node(root, Kit.box_mesh(Vector3(hood_w + 0.06, 0.12, 0.12), 0.01), mats.timber, Kit.xf(at + Vector3(0, 2.66, 0.04)))
	for sx: float in [-1.0, 1.0]:
		# the bracket: a rail under the hood and a strut back down to the wall
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.1, 0.1, proj), 0.01), mats.timber, Transform3D(hb, at + Vector3(sx * (hood_w * 0.5 - 0.15), 2.54 - sin(tilt) * proj * 0.5, proj * 0.5)))
		Kit.mesh_node(root, Kit.box_mesh(Vector3(0.09, 0.09, 1.25), 0.01), mats.timber, Transform3D(Basis(Vector3.RIGHT, -0.75), at + Vector3(sx * (hood_w * 0.5 - 0.15), 2.15, 0.42)))
	var hood := StaticBody3D.new()
	hood.name = "DoorHoodCover"
	hood.collision_layer = ROOF_LAYER
	hood.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(hood_w, 0.1, proj)
	hcs.shape = hbox
	hcs.position = at + Vector3(0, 2.5, proj * 0.5)
	hood.add_child(hcs)
	root.add_child(hood)
	# iron ring handle (a small torus)
	var t := TorusMesh.new()
	t.inner_radius = 0.04
	t.outer_radius = 0.06
	Kit.mesh_node(root, t, Kit.metal(Color(0.2, 0.18, 0.16), 0.5), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0.3, 1.0, -0.06)), false)
