class_name WoodsFeatures
extends RefCounted
## Environmental features of the Whispering Woods (Milestone K environment pass, against the developer's
## references): the things that make a forest read as an ecosystem rather than a scatter of plants —
##   * fallen trees, stumps and exposed roots on the forest floor; drifting leaves under the canopy;
##   * a MUSHROOM GROVE (one place, so its glow after dark stays special) beside the pond path;
##   * riverbanks: sediment, half-submerged stones (the water shader foams around them), reeds;
##   * the HIDDEN POND's identity: weeping willows leaning over the water, a spring fall from the ledge, mist;
##   * the DEN as a root-and-vine hollow: a tree on the outcrop whose roots drape over the mouth, vines across
##     it, a nest and old bones inside, one shaft of light, a dim cool fill so the dark stays readable;
##   * the RUINS overgrown: ivy mats on the walls, vines from the gate and the arches, the engulfing tree's roots.
## Everything is deterministic (seeded) and placed off the trails and the navmesh routes.

var a: WhisperingWoods
var rng := RandomNumberGenerator.new()
var stats := {}

const GROVE := Vector2(-30, 40)
const GROVE_R := 12.0


func _init(area: WhisperingWoods) -> void:
	a = area
	rng.seed = 9191


func _g(x: float, z: float) -> float:
	return a.height(x, z)


func _v(p: Vector2) -> Vector3:
	return Vector3(p.x, a.height(p.x, p.y), p.y)


# ------------------------------------------------------------------ forest floor
func floor_features() -> void:
	var root := Node3D.new()
	root.name = "ForestFloor"
	a.add_child(root)
	var d: WoodsDressing = a.dress
	var logs := {}
	var log_cols: Array = []
	var stumps := []
	var n_roots := 0
	var half: float = a.HALF
	var z := -half + 6.0
	while z < half - 6.0:
		var x := -half + 6.0
		while x < half - 6.0:
			var p := Vector2(x + rng.randf_range(-4.0, 4.0), z + rng.randf_range(-4.0, 4.0))
			x += 11.0
			if not d.inside(p, 5.0) or d.in_clearing(p, 1.0) or d.slope(p.x, p.y) > 0.5 or d.water_dist(p) < 2.0:
				continue
			var zone := d.zone(p)
			var dens: float = a._forest_density(p)
			var td := d.trail_dist(p.x, p.y)
			var r := rng.randf()
			# a fallen tree lies ALONG the forest, never across a path: skip anything that could reach a trail
			if r < 0.22 * dens and td > 5.5 and zone in ["deep", "wood", "monster", "grove", "streamside", "ancient_path"]:
				var yaw := rng.randf() * TAU
				var fwd := Vector2(-sin(yaw), -cos(yaw))    # where the model's trunk (+y) points once rolled onto its side
				var L := rng.randf_range(5.0, 8.0)
				if d.trail_dist((p + fwd * L).x, (p + fwd * L).y) < 2.5 or d.trail_dist((p - fwd * L * 0.3).x, (p - fwd * L * 0.3).y) < 2.5:
					continue
				var id: String = ["DeadTree_1", "DeadTree_2", "DeadTree_3"][rng.randi() % 3]
				var s := rng.randf_range(0.5, 0.75)
				# lay it down: the trunk axis (model +y) along the ground, slightly rolled, the root end sunk
				var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5 + rng.randf_range(-0.08, 0.08)) * Basis(Vector3.UP, rng.randf() * TAU)
				var base := _v(p) + Vector3(0, 0.25 * s, 0)
				if not logs.has(id):
					logs[id] = []
				logs[id].append(Transform3D(b.scaled(Vector3.ONE * s), base))
				log_cols.append([base, Vector3(fwd.x, 0, fwd.y), L * 0.55, 0.42 * s])
			elif r < 0.34 * dens and td > 2.2 and zone != "pond":
				stumps.append([p, rng.randf_range(0.28, 0.5), rng.randf_range(0.35, 0.8)])
		z += 11.0
	for id in logs:
		NatureKit.scatter(root, NatureKit.mesh(id), logs[id], {"shadow": true, "vis_end": 110.0, "name": "Log" + id})
	# colliders: a box along each trunk (layer 3), and a rectangle carved out of the navmesh under it
	var body := NatureKit.vegetation_body(root, "LogColliders")
	var holes := Node3D.new()
	holes.name = "LogCarves"
	root.add_child(holes)
	for lc in log_cols:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(lc[2]) * 2.0, float(lc[3]) * 2.0, float(lc[3]) * 2.0)
		cs.shape = bs
		var dirv: Vector3 = lc[1]
		var yaw := atan2(-dirv.z, dirv.x)
		var centre: Vector3 = (lc[0] as Vector3) + dirv * float(lc[2]) * 0.7
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), centre + Vector3(0, float(lc[3]) * 0.5, 0))
		body.add_child(cs)
		var ob := NavigationObstacle3D.new()
		ob.avoidance_enabled = false
		ob.affect_navigation_mesh = true
		ob.position = centre - Vector3(0, 0.6, 0)
		ob.height = float(lc[3]) * 2.0 + 0.6
		var hl := float(lc[2])
		var hw := float(lc[3])
		var side := Vector3(-dirv.z, 0, dirv.x)
		ob.vertices = PackedVector3Array([dirv * hl + side * hw, dirv * hl - side * hw, -dirv * hl - side * hw, -dirv * hl + side * hw])
		holes.add_child(ob)
	# stumps: one lathe per size class, instanced
	var by_size := {}
	for s in stumps:
		var key := "%d" % int(float(s[1]) * 10.0)
		if not by_size.has(key):
			by_size[key] = []
		var p2: Vector2 = s[0]
		by_size[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, float(s[2]) / 0.5, 1)), _v(p2) - Vector3(0, 0.08, 0)))
	var stump_body := NatureKit.vegetation_body(root, "StumpColliders")
	var stump_holes := Node3D.new()
	stump_holes.name = "StumpCarves"
	root.add_child(stump_holes)
	for key in by_size:
		var rad := float(key) / 10.0
		NatureKit.scatter(root, stump_mesh_for(rad), by_size[key], {"shadow": true, "vis_end": 70.0, "name": "Stump" + key})
		for t in by_size[key]:
			var cs2 := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = rad * 1.2
			cy.height = 0.5 * (t as Transform3D).basis.get_scale().y
			cs2.shape = cy
			cs2.position = (t as Transform3D).origin + Vector3(0, cy.height * 0.5, 0)
			stump_body.add_child(cs2)
			NatureKit.nav_obstacle(stump_holes, (t as Transform3D).origin, rad * 1.2, cy.height)
	# exposed roots at the biggest trees (the dressing remembers them)
	for t in d.big_trees:
		if rng.randf() > 0.4 or RenderProfile.options.has("ev_noroots"):
			continue
		var tr: Transform3D = t
		var s3 := tr.basis.get_scale().x
		FoliageBuilder.roots(root, tr.origin + Vector3(0, 0.1, 0), 0.5 * s3, rng.randi_range(3, 5), Vector2(1.4, 2.6) * s3, rng, _g, false, "Roots")
		n_roots += 1
	stats.logs = log_cols.size()
	stats.stumps = stumps.size()
	stats.root_clusters = n_roots


static var _stumps := {}
static func stump_mesh_for(radius: float) -> ArrayMesh:
	var key := "%.2f" % radius
	if not _stumps.has(key):
		var m := FoliageBuilder.stump_mesh(radius, 0.5, int(radius * 100.0))
		m.surface_set_material(0, FoliageBuilder.bark_mat(true))
		_stumps[key] = m
	return _stumps[key]


## Drifting leaves where the canopy is dense, along the routes (so the camera sees them).
func leaf_fall() -> void:
	var root := Node3D.new()
	root.name = "LeafFall"
	a.add_child(root)
	var d: WoodsDressing = a.dress
	var n := 0
	for t in a.trails:
		var pts: Array = t[0]
		for i in pts.size() - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var L := p0.distance_to(p1)
			var k := 7.0
			while k < L:
				var q := p0.lerp(p1, k / L)
				k += 14.0
				if a._forest_density(q) < 0.55:
					continue
				var em := FoliageBuilder.leaf_fall(root, Vector3(q.x, _g(q.x, q.y) + 7.0, q.y), 14)
				em.visibility_range_end = 45.0
				n += 1
	stats.leaf_emitters = n


# ------------------------------------------------------------------ mushroom grove
func mushroom_grove() -> void:
	var root := Node3D.new()
	root.name = "MushroomGrove"
	a.add_child(root)
	var d: WoodsDressing = a.dress
	var sets := {}
	for i in 90:
		var ang := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * GROVE_R
		var p := GROVE + Vector2(cos(ang), sin(ang)) * rr
		if d.trail_dist(p.x, p.y) < 0.9 or d.slope(p.x, p.y) > 0.6:
			continue
		var big := rng.randf() < 0.3
		var id := "Mushroom_Laetiporus" if (big and rng.randf() < 0.5) else "Mushroom_Common"
		var s := rng.randf_range(1.6, 3.2) if big else rng.randf_range(0.8, 1.5)
		var key := id + "|" + ("glow" if (big or rng.randf() < 0.35) else "")
		if not sets.has(key):
			sets[key] = []
		sets[key].append(d.xf_at(p, s, 0.03, 0.12))
	for key in sets:
		var parts: PackedStringArray = key.split("|")
		NatureKit.scatter(root, NatureKit.mesh(parts[0], parts[1]), sets[key], {"shadow": parts[1] == "glow", "vis_end": 70.0, "name": "Grove" + parts[0]})
	# a soft teal light in the grove after dark + fireflies
	var l := Kit.omni(root, Vector3(GROVE.x, _g(GROVE.x, GROVE.y) + 2.2, GROVE.y), Color(0.3, 0.9, 0.8), 1.1, 16.0)
	a.night_only(l)
	var ff: GPUParticles3D = d._particles(true, 1.6)
	ff.position = Vector3(GROVE.x, _g(GROVE.x, GROVE.y) + 1.5, GROVE.y)
	root.add_child(ff)
	a.night_only(ff)
	stats.grove_mushrooms = sets.values().reduce(func(acc, arr): return acc + arr.size(), 0)


# ------------------------------------------------------------------ riverbanks
func banks() -> void:
	var root := Node3D.new()
	root.name = "Banks"
	a.add_child(root)
	var d: WoodsDressing = a.dress
	var stones := {}
	var reeds := []
	var pebbles := {}
	var z := -a.HALF + 8.0
	while z < a.HALF - 8.0:
		var rx: float = a.river_x(z)
		for side: float in [-1.0, 1.0]:
			# half-submerged stones along the waterline (the shader foams around them), gravel above it
			for k in 2:
				var off := rng.randf_range(4.2, 7.2)
				var p := Vector2(rx + side * off, z + rng.randf_range(-2.5, 2.5))
				if absf(p.y - a.FALLS.y) < 16.0 or absf(p.y - a.BRIDGE.y) < 7.0 or d.trail_dist(p.x, p.y) < 1.6 or rng.randf() > 0.55:
					continue
				var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
				var s := rng.randf_range(0.35, 0.8)
				if not stones.has(id):
					stones[id] = []
				stones[id].append(d.xf_at(p, s, 0.45, 0.5))
			for k2 in 4:
				var p2 := Vector2(rx + side * rng.randf_range(6.0, 9.5), z + rng.randf_range(-2.5, 2.5))
				if absf(p2.y - a.FALLS.y) < 14.0 or d.trail_dist(p2.x, p2.y) < 0.8 or rng.randf() > 0.6:
					continue
				var id2: String = ("Pebble_Round_%d" % (1 + rng.randi() % 5)) if rng.randf() < 0.6 else ("Pebble_Square_%d" % (1 + rng.randi() % 6))
				if not pebbles.has(id2):
					pebbles[id2] = []
				pebbles[id2].append(d.xf_at(p2, rng.randf_range(0.8, 1.8), 0.02))
			if rng.randf() < 0.7:
				var p3 := Vector2(rx + side * rng.randf_range(6.2, 8.8), z + rng.randf_range(-2.0, 2.0))
				if absf(p3.y - a.FALLS.y) > 14.0 and d.trail_dist(p3.x, p3.y) > 1.2:
					reeds.append(d.xf_at(p3, rng.randf_range(0.9, 1.4), 0.05))
		z += 5.0
	for id in stones:
		NatureKit.scatter(root, NatureKit.mesh(id, "wet"), stones[id], {"shadow": true, "vis_end": 120.0, "name": "Bank" + id})
	for id in pebbles:
		NatureKit.scatter(root, NatureKit.mesh(id), pebbles[id], {"vis_end": 45.0, "chunk": 24.0, "name": "Bank" + id})
	NatureKit.scatter(root, NatureKit.mesh("Grass_Wispy_Tall"), reeds, {"vis_end": 60.0, "name": "BankReeds"})
	stats.bank_stones = stones.values().reduce(func(acc, arr): return acc + arr.size(), 0)
	stats.bank_reeds = reeds.size()


# ------------------------------------------------------------------ the hidden pond
func pond_identity() -> void:
	var root := Node3D.new()
	root.name = "PondIdentity"
	a.add_child(root)
	var wy: float = a.height(a.POND.x, a.POND.y) + 1.55
	# three weeping willows around the shore, leaning over the water
	var spots := [[0.35 * TAU, "TwistedTree_2"], [0.62 * TAU, "TwistedTree_5"], [0.86 * TAU, "TwistedTree_3"]]
	var trunks := []
	for sp in spots:
		var ang: float = sp[0]
		var dirv := Vector2(cos(ang), sin(ang))
		var p: Vector2 = a.POND + dirv * (a.POND_R + 2.6)
		var s := rng.randf_range(0.7, 0.85)
		var lean := -Vector3(dirv.x, 0, dirv.y)   # toward the water
		var b := Basis(lean.cross(Vector3.UP).normalized(), -0.16) * Basis(Vector3.UP, rng.randf() * TAU)
		var xf := Transform3D(b.scaled(Vector3.ONE * s), _v(p) - Vector3(0, 0.2, 0))
		NatureKit.scatter(root, NatureKit.mesh(String(sp[1])), [xf], {"shadow": true, "vis_end": 200.0, "name": "WillowTrunk"})
		trunks.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), _v(p)))
		# the curtain hangs from the crown (model crown ~ y 6..17 at scale 1), longest on the water side
		var crown := _v(p) + lean * 2.2 * s + Vector3(0, 11.5 * s, 0)
		FoliageBuilder.willow_curtain(root, crown, 4.6 * s, 54, Vector2(3.0, 7.5), lean, rng, "WillowCurtain")
	NatureKit.trunk_colliders(root, trunks, 0.55)
	# the spring: a narrow fall from the ledge into the pond, foam where it lands, mist
	var ledge: Vector2 = a.POND + Vector2(-2, -19)
	var dir2 := (a.POND - ledge).normalized()
	var lip: Vector2 = ledge + dir2 * 6.5
	var lip_y := _g(lip.x, lip.y) + 0.35
	var foot: Vector2 = ledge + dir2 * 11.5
	var drop := lip_y - wy
	var m := a.marks._sheet(Vector3(lip.x, lip_y, lip.y), 1.9, drop + 0.3, 2.6)
	# the sheet is built along +z; rotate it to run from the ledge toward the pond
	var mi := MeshInstance3D.new()
	mi.name = "SpringFall"
	mi.mesh = m
	mi.material_override = Kit.shader_mat("res://shaders/nature/stylized_waterfall.gdshader", {"noise_tex": Kit.noise(), "width_m": 1.9, "speed": 1.1})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var yaw := atan2(dir2.x, dir2.y)   # +z -> dir2
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	# the sheet mesh was generated at the lip's world position; rotate about the lip instead of the origin
	var lip3 := Vector3(lip.x, lip_y, lip.y)
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), lip3 - Basis(Vector3.UP, yaw) * lip3)
	root.add_child(mi)
	var foam := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 3.5)
	q.orientation = PlaneMesh.FACE_Y
	foam.mesh = q
	foam.material_override = Kit.shader_mat("res://shaders/nature/foam_patch.gdshader", {"noise_tex": Kit.noise(), "opacity": 0.7})
	foam.position = Vector3(foot.x, wy + 0.03, foot.y) + Vector3(dir2.x, 0, dir2.y) * 1.2
	foam.rotation.y = yaw + PI
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(foam)
	# wet stones at the lip and the foot
	var wet := []
	for i in 7:
		var t := float(i) / 6.0
		var p4 := lip.lerp(foot, t) + dir2.orthogonal() * (1.6 + rng.randf_range(-0.3, 0.6)) * (1.0 if i % 2 == 0 else -1.0)
		var y4 := lerpf(lip_y, wy, t)
		wet.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))).scaled(Vector3.ONE * rng.randf_range(0.55, 0.95)), Vector3(p4.x, maxf(y4, _g(p4.x, p4.y)) - 0.25, p4.y)))
	NatureKit.scatter(root, NatureKit.mesh("Rock_Medium_2", "wet"), wet, {"shadow": true, "vis_end": 120.0, "name": "SpringRocks"})
	_mist(root, Vector3(foot.x, wy + 0.3, foot.y), 14, 2.0)
	# pond mist drifting over the water after dark, and a quiet mist by day at the far shore
	var pm := _mist(root, Vector3(a.POND.x, wy + 0.2, a.POND.y), 22, 4.5)
	pm.visibility_range_end = 90.0
	a.night_only(pm)
	# the pond's ambience source position for the audio director (the fall), and a cool fill under the willows at night
	var l := Kit.omni(root, Vector3(a.POND.x, wy + 2.5, a.POND.y), Color(0.3, 0.6, 0.9), 0.6, 22.0)
	a.night_only(l)
	stats.willows = spots.size()
	stats.spring_fall = true


func _mist(parent: Node3D, pos: Vector3, amount: int, size: float) -> GPUParticles3D:
	var mist := GPUParticles3D.new()
	mist.amount = amount
	mist.lifetime = 6.0
	mist.preprocess = 6.0
	mist.position = pos
	mist.visibility_aabb = AABB(Vector3(-12, -3, -12), Vector3(24, 10, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(size * 1.5, 0.3, size * 1.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, 0.05, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	mist.process_material = pm
	var mq := QuadMesh.new()
	mq.size = Vector2(size, size)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_color = Color(0.9, 0.96, 1.0)
	mm.albedo_texture = WoodsDressing._dot_tex()
	mm.proximity_fade_enabled = true
	mm.proximity_fade_distance = 1.5
	mq.material = mm
	mist.draw_pass_1 = mq
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mist)
	return mist


# ------------------------------------------------------------------ the den as a hollow
func den_hollow() -> void:
	var root := Node3D.new()
	root.name = "DenHollow"
	a.add_child(root)
	var mouth: Vector3 = a.marks.den_mouth()
	var face := Vector3(a.DEN_FACE.x, 0, a.DEN_FACE.y)
	var right := Vector3(-face.z, 0, face.x)
	var centre := mouth - face * 5.0 + Vector3(0, -1.2, 0)
	# a great twisted tree on the outcrop, its roots draping down the front over the mouth
	var top := centre + Vector3(0, 6.1, 0) - face * 1.5
	var s := 1.05
	var txf := Transform3D(Basis(Vector3.UP, 1.3).scaled(Vector3.ONE * s), top - Vector3(0, 0.3, 0))
	NatureKit.scatter(root, NatureKit.mesh("TwistedTree_4", "dark"), [txf], {"shadow": true, "vis_end": 220.0, "name": "DenTree"})
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# roots: tapered tubes from the trunk base, over the dome's front, down past the lip on both sides of the mouth
	var w: float = 2.5
	for i in 7:
		var t := -1.0 + 2.0 * i / 6.0
		var lx := t * (w + 1.6)
		var L := 7.0 + rng.randf_range(-0.6, 1.2)
		var pts: Array[Vector3] = []
		for k in 9:
			var u := float(k) / 8.0
			# arc: from the trunk base forward and down along the dome surface, then over the lintel
			var fy := 6.0 - 6.4 * u * u
			var fz := 1.0 + 6.2 * sin(u * PI * 0.5)
			var x := lerpf(lx * 0.25, lx, u)
			var jitter := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.1, 0.1), 0)
			var p := centre + right * x + Vector3(0, fy, 0) + face * fz + jitter
			# never through the opening: push roots outward from the mouth below the crown
			if fy < 4.6 and absf(x) < w + 0.4:
				p += right * signf(x if x != 0.0 else 1.0) * (w + 0.5 - absf(x))
			pts.append(p)
		_tube(st, pts, lerpf(0.34, 0.05, 0.0), 0.05, 7)
	var roots := MeshInstance3D.new()
	roots.name = "DenRoots"
	roots.mesh = st.commit()
	roots.material_override = FoliageBuilder.bark_mat(false)
	roots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(roots)
	# vines across the top of the mouth
	var anchors := []
	for i in 9:
		var t2 := -1.0 + 2.0 * i / 8.0
		anchors.append(centre + face * 6.8 + right * t2 * (w + 0.6) + Vector3(0, 4.3 + 0.7 * sqrt(maxf(0.0, 1.0 - t2 * t2)), 0))
	FoliageBuilder.vine_curtain(root, anchors, Vector2(0.9, 2.6), face, rng, "dark", "DenVines")
	# inside: a nest of dry grass at the back, a few old bones, one shaft of light through a crack, a dim fill
	var nest_c := centre - face * 1.8 + Vector3(0, 0.0, 0)
	var nest := []
	var nest_cols := []
	for i in 46:
		var ang := rng.randf() * TAU
		var rr := rng.randf_range(0.9, 2.4)
		var p2 := nest_c + Vector3(cos(ang) * rr, 0, sin(ang) * rr)
		nest.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, 0.5, 1) * rng.randf_range(0.7, 1.1)), Vector3(p2.x, _g(p2.x, p2.z) - 0.02, p2.z)))
		nest_cols.append(Color(0.72, 0.6, 0.36))
	NatureKit.scatter(root, NatureKit.mesh("Grass_Wispy_Tall"), nest, {"colors": nest_cols, "vis_end": 40.0, "name": "DenNest"})
	var bone_mat := StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.86, 0.82, 0.72)
	bone_mat.roughness = 0.8
	for i in 6:
		var p3 := nest_c + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-2.5, 2.5)) + right * rng.randf_range(-1.0, 1.0)
		var L2 := rng.randf_range(0.5, 1.1)
		var bone := Kit.mesh_node(root, Kit.lathe([Vector2(0.06, 0), Vector2(0.035, L2 * 0.15), Vector2(0.03, L2 * 0.85), Vector2(0.06, L2)], 8, true, true), bone_mat,
			Transform3D(Basis.from_euler(Vector3(PI * 0.5 + rng.randf_range(-0.15, 0.15), rng.randf() * TAU, 0)), Vector3(p3.x, _g(p3.x, p3.z) + 0.04, p3.z)), false)
		bone.name = "Bone%d" % i
	var shaft_mat := Kit.shader_mat("res://shaders/nature/light_shaft.gdshader", {"noise_tex": Kit.noise(), "strength": 0.3})
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 7.0)
	var shaft := MeshInstance3D.new()
	shaft.mesh = quad
	shaft.material_override = shaft_mat
	var sdir := Vector3(0.25, -1.0, 0.1).normalized()
	var sside := sdir.cross(Vector3.UP).normalized()
	shaft.transform = Transform3D(Basis(sside, -sdir, sside.cross(-sdir).normalized()), centre + right * 1.2 - face * 0.5 + Vector3(0, 2.2, 0))
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shaft)
	shaft.add_to_group("day_only_" + str(a.get_instance_id()))
	var fill := Kit.omni(root, centre + Vector3(0, 2.4, 0), Color(0.45, 0.55, 0.7), 0.45, 9.0)
	fill.name = "DenFill"
	stats.den_hollow = true


## A tube along a polyline (tapering), appended to `st`.
func _tube(st: SurfaceTool, pts: Array[Vector3], r0: float, r1: float, sides: int) -> void:
	var prev: Array = []
	for i in pts.size():
		var p := pts[i]
		var dirv: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := dirv.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(dirv).normalized()
		var r := lerpf(r0, r1, float(i) / (pts.size() - 1))
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			ring.append(p + (side * cos(ang) + up * sin(ang)) * r)
		if not prev.is_empty():
			for k in sides:
				var a0: Vector3 = prev[k]
				var a1: Vector3 = prev[(k + 1) % sides]
				var b0: Vector3 = ring[k]
				var b1: Vector3 = ring[(k + 1) % sides]
				var cen := (a0 + a1 + b0 + b1) * 0.25
				var nrm := (cen - p).normalized()
				for v in [a0, b0, b1, a0, b1, a1]:
					st.set_normal(nrm)
					st.set_uv(Vector2(v.x + v.z, v.y) * 0.5)
					st.add_vertex(v)
		prev = ring


# ------------------------------------------------------------------ the ruins overgrown
func ruin_growth() -> void:
	var root := Node3D.new()
	root.name = "RuinGrowth"
	a.add_child(root)
	var n_ivy := 0
	# ivy mats on the standing walls (one face each, the shaded north side more often)
	for seg in a.marks.walls:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var h: float = seg[2]
		var thick: float = seg[3]
		if h < 1.0:
			continue
		var along := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
		var L := along.length()
		along /= L
		var nrm := along.cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			if rng.randf() > (0.9 if side < 0.0 else 0.7):
				continue
			var w := rng.randf_range(minf(L, 2.0), L)
			var start := rng.randf_range(0.0, L - w)
			var origin := p0 + along * start + nrm * side * (thick * 0.5)
			origin.y = minf(_g(origin.x, origin.z), _g((origin + along * w).x, (origin + along * w).z)) - 0.1
			var r := along if side > 0.0 else -along
			var o2 := origin if side > 0.0 else origin + along * w
			FoliageBuilder.ivy_sheet(root, o2, r, Vector3.UP, w, h * rng.randf_range(0.55, 0.95), rng, 0.7, "Ivy")
			n_ivy += 1
	# ivy climbing the arch piers (the gate's and the stairway's)
	for arc in a.marks.arches:
		var c0: Vector3 = arc[0]
		var span0: float = arc[1]
		var yaw0: float = arc[3]
		var right0 := Basis(Vector3.UP, yaw0) * Vector3.RIGHT
		var fwd0 := Basis(Vector3.UP, yaw0) * Vector3.BACK
		for side0: float in [-1.0, 1.0]:
			if rng.randf() > 0.8:
				continue
			var pier := c0 + right0 * side0 * (span0 * 0.5 + 0.6)
			var ground_y := _g(pier.x, pier.z)
			var h0 := c0.y - ground_y
			for face: float in [-1.0, 1.0]:
				if rng.randf() > 0.7:
					continue
				var o := pier + fwd0 * face * 0.62 - right0 * 0.55
				o.y = ground_y - 0.1
				FoliageBuilder.ivy_sheet(root, o, right0 * (1.0 if face > 0.0 else 1.0), Vector3.UP, 1.1, h0 * rng.randf_range(0.5, 0.9), rng, 0.8, "PierIvy")
				n_ivy += 1
	# vines from the gate arch and the three stairway arches
	for arc in a.marks.arches:
		var c: Vector3 = arc[0]
		var span: float = arc[1]
		var top_y: float = arc[2]
		var yaw: float = arc[3]
		var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		var fwd := Basis(Vector3.UP, yaw) * Vector3.BACK
		for side: float in [-1.0, 1.0]:
			var anchors := []
			for i in 7:
				var t := -1.0 + 2.0 * i / 6.0
				var x := t * span * 0.5
				var y := top_y - (span * 0.5) * (1.0 - sqrt(maxf(0.0, 1.0 - t * t))) * 0.9
				anchors.append(c + right * x + Vector3(0, y - c.y, 0) + fwd * side * 0.65)
			FoliageBuilder.vine_curtain(root, anchors, Vector2(0.5, 1.8), fwd * side, rng, "plant", "ArchVines")
	# the engulfing tree's roots over the wall it grew through
	if a.marks.ruin_tree != Transform3D.IDENTITY:
		var tr: Transform3D = a.marks.ruin_tree
		FoliageBuilder.roots(root, tr.origin + Vector3(0, 0.15, 0), 0.75 * tr.basis.get_scale().x, 6, Vector2(2.2, 4.0), rng, _g, false, "RuinTreeRoots")
	stats.ivy_mats = n_ivy
