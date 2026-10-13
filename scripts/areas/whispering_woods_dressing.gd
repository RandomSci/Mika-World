class_name WoodsDressing
extends RefCounted
## Vegetation and atmosphere for the Whispering Woods (Milestone K). Art direction (docs/WHISPERING_WOODS.md):
## the enchanted-forest references read as LAYERS: tall crowns overhead, a mid layer of bushes and saplings,
## oversized leafy plants and ferns at eye level, and moss/grass/flowers on the floor, with the trail kept open and
## framed (big plants lean in at its edges, trees arch over it). Placement is deterministic (seeded) and obeys
## the terrain: nothing on trails, water, cliffs or landmark clearings. Distances from trails come from a raster
## field computed once.

var a: WhisperingWoods
var rng := RandomNumberGenerator.new()
var tdist := PackedFloat32Array()   # metres to the nearest trail (any kind), capped
var n := 0
var stats := {}
const CAP := 30.0


func _init(area: WhisperingWoods) -> void:
	a = area
	rng.seed = 7171


# ------------------------------------------------------------------ fields
func compute_trail_distance() -> void:
	n = a._n
	tdist.resize(n * n)
	tdist.fill(CAP)
	var half: float = a.HALF
	var step: float = a.STEP
	for t in a.trails:
		var pts: Array = t[0]
		var w: float = t[1]
		for i in pts.size() - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var lo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)) - Vector2.ONE * CAP
			var hi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y)) + Vector2.ONE * CAP
			for iz in range(maxi(0, int((lo.y + half) / step)), mini(n, int((hi.y + half) / step) + 1)):
				for ix in range(maxi(0, int((lo.x + half) / step)), mini(n, int((hi.x + half) / step) + 1)):
					var p := Vector2(-half + ix * step, -half + iz * step)
					var d := maxf(a._seg_dist(p, p0, p1) - w * 0.5, 0.0)
					var k := iz * n + ix
					if d < tdist[k]:
						tdist[k] = d


func trail_dist(x: float, z: float) -> float:
	var ix := clampi(int(round((x + a.HALF) / a.STEP)), 0, n - 1)
	var iz := clampi(int(round((z + a.HALF) / a.STEP)), 0, n - 1)
	return tdist[iz * n + ix]


func slope(x: float, z: float) -> float:
	var hx: float = a.height(x + 0.8, z) - a.height(x - 0.8, z)
	var hz: float = a.height(x, z + 0.8) - a.height(x, z - 0.8)
	return Vector2(hx, hz).length() / 1.6


## Distance to open water (river / pond); negative inside.
func water_dist(p: Vector2) -> float:
	var dr := absf(p.x - a.river_x(p.y)) - 5.5
	var dp: float = p.distance_to(a.POND) - (a.POND_R + 1.0)
	var dpool: float = p.distance_to(a.pool_center()) - 9.0
	return minf(dr, minf(dp, dpool))


## Landmark clearings that must stay open (stairs, ruins core, bridge ends, gates, the sparring ground).
func in_clearing(p: Vector2, margin := 0.0) -> bool:
	var clear := [[a.STAIR_BASE + Vector2(0, -6), 8.0], [a.STAIR_LANDING, 7.0], [a.RUIN_GATE, 7.0], [a.INSCRIPTION, 9.0],
		[a.VIEWPOINT, 7.0], [a.BRIDGE, 10.0], [a.CROSS, 7.0], [a.ENTRY, 8.0], [a.ALCOVE, 5.0], [a.DEN, 9.0],
		[a.FRONTIER_END, 10.0], [Vector2(-130, -6), 9.0]]
	for c in clear:
		if p.distance_to(c[0]) < c[1] + margin:
			return true
	# the approach to the den mouth stays open (it must read from the trail)
	if a._seg_dist(p, Vector2(106, -21), a.DEN_MOUTH - a.DEN_FACE * 5.0) < 7.0 + margin:
		return true
	# the viewpoint's sightline to the falls stays open
	if a._seg_dist(p, a.VIEWPOINT, a.FALLS + Vector2(0, 6)) < 5.0 + margin:
		return true
	# the stair ramp corridor up the escarpment
	if absf(p.x - a.STAIR_BASE.x) < 6.5 + margin and p.y < 4.0 and p.y > -30.0:
		return true
	return false


func inside(p: Vector2, border := 4.0) -> bool:
	return absf(p.x) < a.HALF - border and absf(p.y) < a.HALF - border


func xf_at(p: Vector2, s: float, sink := 0.15, tilt := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	if tilt > 0.0:
		b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, tilt)) * b
	b = b.scaled(Vector3.ONE * s)
	return Transform3D(b, Vector3(p.x, a.height(p.x, p.y) - sink * s, p.y))


# ------------------------------------------------------------------ trees
## Tree families per region. Returns "" where no tree should stand.
func _family(p: Vector2) -> String:
	if p.x > 82.0:
		return "dead" if rng.randf() < 0.45 else "dark"
	if p.y < -60.0 and p.x < 10.0:
		return "pine" if rng.randf() < 0.7 else "common"
	if absf(p.x) > a.HALF - 22.0 or absf(p.y) > a.HALF - 22.0:
		return "pine" if rng.randf() < 0.6 else "common"
	if p.distance_to(a.POND) < 40.0:
		return "twisted" if rng.randf() < 0.55 else "common"
	return "twisted" if rng.randf() < 0.3 else "common"


func trees() -> void:
	var placed := {"common": [], "twisted": [], "pine": [], "dead": [], "dark": []}
	var models := {"common": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"],
		"twisted": ["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"],
		"pine": ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
		"dead": ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"],
		"dark": ["TwistedTree_2", "TwistedTree_4", "CommonTree_3"]}
	var per_model := {}
	var trunks := {}   # radius -> xforms
	var taken: Array[Vector2] = []
	var spacing := 6.5
	var half: float = a.HALF
	var z := -half + 3.0
	while z < half - 3.0:
		var x := -half + 3.0
		while x < half - 3.0:
			var p := Vector2(x + rng.randf_range(-2.4, 2.4), z + rng.randf_range(-2.4, 2.4))
			x += spacing
			if not inside(p, 3.0):
				continue
			var dens: float = a._forest_density(p)
			var td := trail_dist(p.x, p.y)
			# trees frame trails: never on them, a little sparser right beside them, then dense
			if td < 2.6 or water_dist(p) < 1.5 or in_clearing(p, 2.0) or slope(p.x, p.y) > 0.75:
				continue
			var keep := dens * dens * 1.25 + (0.18 if td < 9.0 else 0.0)
			if rng.randf() > keep:
				continue
			var ok := true
			for q in taken:
				if q.distance_squared_to(p) < 16.0:
					ok = false
					break
			if not ok:
				continue
			var fam := _family(p)
			var list: Array = models[fam]
			var id: String = list[rng.randi() % list.size()]
			var s := rng.randf_range(0.85, 1.3)
			if fam == "twisted":
				s = rng.randf_range(0.7, 1.05) if td > 6.0 else rng.randf_range(0.55, 0.8)
			elif fam == "common":
				s = rng.randf_range(1.0, 1.55)
			elif fam == "pine":
				s = rng.randf_range(1.1, 1.8)
			var crown := "dark" if fam == "dark" else ""
			var key := id + "|" + crown
			if not per_model.has(key):
				per_model[key] = []
			per_model[key].append(xf_at(p, s, 0.25))
			taken.append(p)
			var r := 0.5 if fam == "twisted" else (0.45 if fam == "dead" else 0.32)
			if fam == "dark" and id.begins_with("Twisted"):
				r = 0.5
			if not trunks.has(r):
				trunks[r] = []
			trunks[r].append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(p.x, a.height(p.x, p.y), p.y)))
		z += spacing
	var root := Node3D.new()
	root.name = "Trees"
	a.add_child(root)
	var total := 0
	for key in per_model:
		var parts: PackedStringArray = key.split("|")
		NatureKit.scatter(root, NatureKit.mesh(parts[0], parts[1]), per_model[key], {"vis_end": 170.0, "shadow": true, "name": parts[0]})
		total += per_model[key].size()
	for r in trunks:
		NatureKit.trunk_colliders(root, trunks[r], r)
	stats.trees = total


# ------------------------------------------------------------------ undergrowth
func undergrowth() -> void:
	var root := Node3D.new()
	root.name = "Undergrowth"
	a.add_child(root)
	var sets := {}
	var add := func(id: String, t: Transform3D, crown := "") -> void:
		var k := id + "|" + crown
		if not sets.has(k):
			sets[k] = []
		sets[k].append(t)
	var half: float = a.HALF
	var step := 2.2
	var z := -half + 2.0
	while z < half - 2.0:
		var x := -half + 2.0
		while x < half - 2.0:
			var p := Vector2(x + rng.randf_range(-1.0, 1.0), z + rng.randf_range(-1.0, 1.0))
			x += step
			if not inside(p, 2.0):
				continue
			var td := trail_dist(p.x, p.y)
			var wd := water_dist(p)
			if td < 0.5 or wd < 0.3 or in_clearing(p, -1.0) or slope(p.x, p.y) > 0.8:
				continue
			var dens: float = a._forest_density(p)
			var r := rng.randf()
			var dead := p.x > 82.0
			# trail edge (0.5..4 m): giant leaves lean in, ferns, flowers in the light
			if td < 4.0:
				if r < 0.16 and dens > 0.35 and not dead:
					add.call("Plant_1_Big", xf_at(p, rng.randf_range(1.1, 2.0), 0.05, 0.25))
				elif r < 0.36:
					add.call("Fern_1", xf_at(p, rng.randf_range(0.8, 1.3), 0.02, 0.15))
				elif r < 0.46 and dens < 0.6 and not dead:
					add.call(["Flower_3_Group", "Flower_4_Group", "Flower_3_Single", "Flower_4_Single"][rng.randi() % 4], xf_at(p, rng.randf_range(0.5, 0.75), 0.02))
				elif r < 0.56:
					add.call("Plant_7_Big", xf_at(p, rng.randf_range(0.9, 1.4), 0.0))
				continue
			# forest interior: layered
			if rng.randf() > 0.35 + dens * 0.6:
				continue
			if r < 0.13 * dens and not dead:
				add.call("Plant_1_Big", xf_at(p, rng.randf_range(1.3, 2.4), 0.05, 0.2))
			elif r < 0.35:
				add.call("Fern_1", xf_at(p, rng.randf_range(0.9, 1.6), 0.02, 0.15), "dark" if dead else "")
			elif r < 0.47:
				add.call("Bush_Common", xf_at(p, rng.randf_range(0.9, 1.7), 0.1), "dark" if dead else "")
			elif r < 0.52 and dens < 0.55 and not dead:
				add.call("Bush_Common_Flowers", xf_at(p, rng.randf_range(0.8, 1.3), 0.1))
			elif r < 0.62:
				add.call(["Plant_7", "Plant_7_Big", "Clover_1", "Clover_2"][rng.randi() % 4], xf_at(p, rng.randf_range(0.8, 1.3), 0.0))
			elif r < 0.66 and dens > 0.5:
				add.call(["Mushroom_Common", "Mushroom_Laetiporus"][rng.randi() % 2], xf_at(p, rng.randf_range(0.6, 1.1), 0.02))
			elif r < 0.72 and dens < 0.5 and not dead:
				add.call(["Flower_3_Group", "Flower_4_Group"][rng.randi() % 2], xf_at(p, rng.randf_range(0.55, 0.8), 0.02))
		z += step
	var total := 0
	for k in sets:
		var parts: PackedStringArray = k.split("|")
		var big := parts[0] in ["Plant_1_Big", "Bush_Common", "Bush_Common_Flowers"]
		NatureKit.scatter(root, NatureKit.mesh(parts[0], parts[1]), sets[k], {"vis_end": 90.0 if big else 55.0, "shadow": big, "chunk": 32.0, "name": parts[0]})
		total += sets[k].size()
	stats.undergrowth = total


# ------------------------------------------------------------------ grass
func grass() -> void:
	var root := Node3D.new()
	root.name = "Grass"
	a.add_child(root)
	var ids := ["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall"]
	var sets := {}
	var cols := {}
	for id in ids:
		sets[id] = []
		cols[id] = []
	var half: float = a.HALF
	var step := 0.95
	var z := -half + 2.0
	while z < half - 2.0:
		var x := -half + 2.0
		while x < half - 2.0:
			var p := Vector2(x + rng.randf_range(-0.55, 0.55), z + rng.randf_range(-0.55, 0.55))
			x += step
			var td := trail_dist(p.x, p.y)
			if td < 0.15 or water_dist(p) < 0.2 or slope(p.x, p.y) > 0.65 or not inside(p, 2.0):
				continue
			var dens: float = a._forest_density(p)
			# meadows full, forest floor patchy, trail shoulders sparse
			var keep := lerpf(0.85, 0.22, dens) * (0.45 if td < 1.2 else 1.0)
			if in_clearing(p) :
				keep *= 0.6
			if rng.randf() > keep:
				continue
			# mostly soft wispy tufts (read as a carpet); taller common blades only in open meadow
			var id: String = ids[[2, 2, 3, 0][rng.randi() % 4]] if dens < 0.45 else ids[[2, 2, 0][rng.randi() % 3]]
			var s := rng.randf_range(0.32, 0.6) * (0.8 if dens > 0.6 else 1.0) * (0.75 if td < 2.0 else 1.0)
			sets[id].append(xf_at(p, s, 0.03))
			# patch colour: warm meadow, cooler and darker in the forest, tired in monster territory
			var c := Color(1, 1, 1).lerp(Color(0.72, 0.8, 0.78), dens)
			if p.x > 82.0:
				c = Color(0.78, 0.74, 0.6)
			cols[id].append(c)
		z += step
	var total := 0
	for id in ids:
		NatureKit.scatter(root, NatureKit.mesh(id), sets[id], {"vis_end": 36.0, "chunk": 16.0, "colors": cols[id], "name": id})
		total += sets[id].size()
	stats.grass = total


# ------------------------------------------------------------------ rocks
func rocks() -> void:
	var root := Node3D.new()
	root.name = "Rocks"
	a.add_child(root)
	var big := {}
	var small := {}
	var half: float = a.HALF
	var step := 5.0
	var z := -half + 3.0
	while z < half - 3.0:
		var x := -half + 3.0
		while x < half - 3.0:
			var p := Vector2(x + rng.randf_range(-2.0, 2.0), z + rng.randf_range(-2.0, 2.0))
			x += step
			if not inside(p, 2.0) or in_clearing(p, 1.0):
				continue
			var td := trail_dist(p.x, p.y)
			var sl := slope(p.x, p.y)
			var wd := water_dist(p)
			var r := rng.randf()
			# boulders at cliff feet and on slopes, along the banks, sometimes beside the trail
			var want := 0.04 + (0.35 if sl > 0.5 else 0.0) + (0.3 if wd > -1.0 and wd < 3.0 else 0.0) + (0.06 if td > 2.0 and td < 5.0 else 0.0)
			if td < 1.6 or r > want:
				continue
			var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
			var s := rng.randf_range(0.5, 1.4) * (1.6 if sl > 0.5 else 1.0)
			if s >= 0.7 and (td < 1.25 * s + 0.8 or p.distance_to(a.VIEWPOINT) < 16.0):
				s = rng.randf_range(0.45, 0.65)   # near a path: only small (non-blocking) stones
			if not big.has(id):
				big[id] = []
			big[id].append(xf_at(p, s, 0.3, 0.3))
		z += step
	# pebbles scattered on and beside trails
	for t in a.trails:
		var pts: Array = t[0]
		for i in pts.size() - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var L := p0.distance_to(p1)
			var cnt := int(L / 2.5)
			for j in cnt:
				var q := p0.lerp(p1, rng.randf())
				var side := (p1 - p0).normalized().orthogonal() * rng.randf_range(-1.0, 1.0) * (float(t[1]) * 0.5 + 1.0)
				q += side
				if water_dist(q) < 0.5:
					continue
				var id2: String = ("Pebble_Round_%d" % (1 + rng.randi() % 5)) if rng.randf() < 0.6 else ("Pebble_Square_%d" % (1 + rng.randi() % 6))
				if not small.has(id2):
					small[id2] = []
				small[id2].append(xf_at(q, rng.randf_range(0.6, 1.5), 0.02))
	var total := 0
	var big_xf := []
	for id in big:
		NatureKit.scatter(root, NatureKit.mesh(id), big[id], {"vis_end": 160.0, "shadow": true, "name": id})
		total += big[id].size()
		big_xf.append_array(big[id])
	for id in small:
		NatureKit.scatter(root, NatureKit.mesh(id), small[id], {"vis_end": 40.0, "chunk": 24.0, "name": id})
		total += small[id].size()
	# boulders are solid (approximate spheres), large ones only
	var body := StaticBody3D.new()
	body.name = "BoulderColliders"
	for t2 in big_xf:
		var tr: Transform3D = t2
		var s2 := tr.basis.get_scale().x
		if s2 < 0.7:
			continue
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 1.25 * s2
		cs.shape = sp
		cs.position = tr.origin + Vector3(0, 0.35 * s2, 0)
		body.add_child(cs)
	root.add_child(body)
	stats.rocks = total


# ------------------------------------------------------------------ cliffs
## The escarpment face: big mossy boulders bedded into the slope in two staggered rows, so the 9 m step reads as
## a rocky, overgrown cliff instead of a smeared ramp (the stair corridor, the river and the falls stay clear).
func cliffs() -> void:
	var root := Node3D.new()
	root.name = "Cliffs"
	a.add_child(root)
	var sets := {}
	var cols: Array[Transform3D] = []
	var x := -a.HALF + 6.0
	while x < 128.0:
		x += rng.randf_range(2.6, 3.8)
		if absf(x - a.STAIR_BASE.x) < 8.0:
			continue
		var esc_z := -24.0 + 3.0 * sin(x * 0.05) - smoothstep(20.0, 60.0, x) * 16.0
		for row in 2:
			var z := esc_z + (1.0 if row == 0 else -2.6) + rng.randf_range(-0.8, 0.8)
			var p := Vector2(x + rng.randf_range(-1.0, 1.0), z)
			if water_dist(p) < 3.0 or p.distance_to(a.FALLS + Vector2(0, 3)) < 12.0 or p.distance_to(a.ALCOVE) < 9.0 or not inside(p, 4.0):
				continue
			if slope(p.x, p.y) < 0.35 or in_clearing(p, 2.0) or p.distance_to(a.VIEWPOINT) < 14.0:
				continue
			var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
			# foot row: big boulders; rim row: bedded deep so only a rocky lip shows (keeps views off the plateau)
			var s := rng.randf_range(2.0, 3.4) if row == 0 else rng.randf_range(1.4, 2.2)
			var t := xf_at(p, s, 0.35 if row == 0 else 0.62, 0.35)
			if not sets.has(id):
				sets[id] = []
			sets[id].append(t)
			cols.append(t)
	var total := 0
	for id in sets:
		NatureKit.scatter(root, NatureKit.mesh(id), sets[id], {"vis_end": 220.0, "shadow": true, "name": "Cliff" + id})
		total += sets[id].size()
	stats.cliff_rocks = total


# ------------------------------------------------------------------ atmosphere
func _sun_dir() -> Vector3:
	var rot: Vector3 = a.env_preset().day.sun_rot
	return Basis.from_euler(rot * PI / 180.0) * Vector3(0, 0, -1)   # direction the light travels


## Shafts of sun through the canopy beside the trails, pollen motes in the light by day, fireflies by night.
func atmosphere() -> void:
	var root := Node3D.new()
	root.name = "Atmosphere"
	a.add_child(root)
	var shaft_mat := Kit.shader_mat("res://shaders/nature/light_shaft.gdshader", {"noise_tex": Kit.noise(), "strength": 0.2})
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 22.0)
	var up := -_sun_dir()
	var shafts := 0
	var spots: Array[Vector2] = []
	for t in a.trails:
		if t[2] == "hidden":
			continue
		var pts: Array = t[0]
		for i in pts.size() - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var L := p0.distance_to(p1)
			var k := 0.0
			while k < L:
				k += rng.randf_range(12.0, 20.0)
				var q := p0.lerp(p1, clampf(k / L, 0.0, 1.0)) + (p1 - p0).normalized().orthogonal() * rng.randf_range(-7.0, 7.0)
				spots.append(q)
				if a._forest_density(q) < 0.35 or rng.randf() < 0.35:
					continue
				var base := Vector3(q.x, a.height(q.x, q.y), q.y)
				var centre := base + up * 9.0
				var w := rng.randf_range(0.7, 1.4)
				for j in 2:
					var side := up.cross(Vector3.UP).normalized().rotated(up, j * PI * 0.5 + rng.randf() * 0.5)
					var b := Basis(side * w, up, side.cross(up).normalized())
					var mi := MeshInstance3D.new()
					mi.mesh = quad
					mi.material_override = shaft_mat
					mi.transform = Transform3D(b, centre)
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.visibility_range_end = 90.0
					root.add_child(mi)
					mi.add_to_group("day_only_" + str(a.get_instance_id()))
				shafts += 1
	stats.light_shafts = shafts
	# motes and fireflies: a handful of local emitters along the routes (cheap GPU particles)
	var motes := 0
	var flies := 0
	for i in spots.size():
		if i % 3 != 0:
			continue
		var q2: Vector2 = spots[i]
		var pos := Vector3(q2.x, a.height(q2.x, q2.y) + 1.6, q2.y)
		var day := _particles(false)
		day.position = pos
		root.add_child(day)
		day.add_to_group("day_only_" + str(a.get_instance_id()))
		motes += 1
		var night := _particles(true)
		night.position = pos
		root.add_child(night)
		a.night_only(night)
		flies += 1
	# the hidden pond: a cloud of fireflies over the water
	for j in 4:
		var pp: Vector2 = a.POND + Vector2.from_angle(j * TAU / 4.0) * 7.0
		var ff := _particles(true, 2.2)
		ff.position = Vector3(pp.x, a.height(a.POND.x, a.POND.y) + 2.4, pp.y)
		root.add_child(ff)
		a.night_only(ff)
		flies += 1
	stats.motes = motes
	stats.fireflies = flies


func _particles(fireflies: bool, density := 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = int((26 if fireflies else 40) * density)
	p.lifetime = 9.0 if fireflies else 12.0
	p.preprocess = 10.0
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 8, 20))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9, 1.6 if fireflies else 2.4, 9)
	pm.gravity = Vector3(0, 0.02 if fireflies else -0.01, 0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25 if fireflies else 0.12
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6 if fireflies else 0.3
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	var ramp := Gradient.new()
	if fireflies:
		# slow blink: dark -> glow -> dark -> glow -> out
		ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0])
		ramp.colors = PackedColorArray([Color(0, 0, 0, 0), Color(1, 1, 1, 1), Color(0.2, 0.2, 0.2, 0.2), Color(1, 1, 1, 1), Color(0.3, 0.3, 0.3, 0.3), Color(1, 1, 1, 1), Color(0, 0, 0, 0)])
	else:
		ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * (0.09 if fireflies else 0.045)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.75, 1.0, 0.45) * 3.0 if fireflies else Color(1.0, 0.92, 0.7) * 1.2
	m.albedo_texture = _dot_tex()
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	return p


static var _dot: GradientTexture2D
static func _dot_tex() -> GradientTexture2D:
	if _dot == null:
		_dot = GradientTexture2D.new()
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_dot.gradient = g
		_dot.width = 32
		_dot.height = 32
	return _dot
