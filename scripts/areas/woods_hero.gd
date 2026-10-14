class_name WoodsHero
extends RefCounted
## Visual-quality pass for the Woods' viewpoint (where Oriel meets Mika) - the benchmark scene:
##   * hero trees (tools/models/build_hero_trees.py): real branching trunks with buttress roots and leaf-clump
##     crowns instead of the kit's rounded blob crowns, in a ring around the terrace, with leafy shrubs;
##   * a painted 360-degree mountain backdrop (tools/textures/paint_backdrop.py) instead of the flat ridge ring.
## The kit trees and round bushes are kept out of HERO_RADIUS (WoodsDressing asks `excludes()`).

const HERO_RADIUS := 60.0
const FAR_RADIUS := 88.0     # beyond the hero ring: fewer hero trees (no shadows) so the mid-distance is not kit blobs
const GLB := "res://assets/nature/hero/hero_trees.glb"
const INFO := "res://assets/nature/hero/hero_trees.json"
const CLUMPS := "res://assets/nature/hero/leaf_clumps.png"
const BACKDROP := "res://assets/nature/hero/backdrop.png"

static var _meshes := {}
static var _info := {}


static func off() -> bool:
	return RenderProfile.options.has("ev_nohero") or RealKit.enabled()   # the stylised hero pass yields to the realism pass


static func excludes(a: Node, p: Vector2) -> bool:
	if RealKit.enabled():
		var vp: Vector2 = a.VIEWPOINT
		# the terrace stands in a clearing (light reaches it); the benchmark cameras' own spots stay clear
		return p.distance_to(vp) < 15.5 or p.distance_to(vp + Vector2(-17.0, 7.0)) < 3.5 or p.distance_to(vp + Vector2(-13.0, -2.0)) < 3.0
	return p.distance_to(a.VIEWPOINT) < HERO_RADIUS and not off()


static func _load() -> void:
	if not _meshes.is_empty():
		return
	var scene: Node = (load(GLB) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(mi.name)] = (mi as MeshInstance3D).mesh
	scene.free()
	_info = JSON.parse_string(FileAccess.get_file_as_string(INFO))


static func _leaf_mat(v: String, palette: int) -> ShaderMaterial:
	var inf: Dictionary = _info[v]
	var cc: Array = inf.canopy_center
	var tops := [Color(0.72, 0.9, 0.42), Color(0.62, 0.86, 0.38), Color(0.82, 0.88, 0.42), Color(0.58, 0.82, 0.46)]
	var bots := [Color(0.12, 0.3, 0.2), Color(0.1, 0.26, 0.18), Color(0.16, 0.3, 0.16), Color(0.1, 0.28, 0.22)]
	return Kit.shader_mat("res://shaders/nature/stylized_foliage.gdshader", {"albedo_tex": load(CLUMPS),
		"tint_top": tops[palette % 4], "tint_bottom": bots[palette % 4], "translucency_color": Color(0.9, 1.0, 0.5),
		"canopy_center": Vector3(cc[0], cc[1], cc[2]), "canopy_radius": float(inf.canopy_radius), "canopy_bottom": float(inf.canopy_bottom),
		"canopy_top": float(inf.canopy_top), "spherize": 0.55, "translucency": 1.0, "tint_texture_mix": Vector4(0.62, 0, 0, 0),
		"wind_strength": 0.1, "flutter": 0.02, "alpha_cut": 0.4, "variation_strength": 0.14, "two_sided": 0.0})


static func _bark_mat() -> ShaderMaterial:
	return Kit.shader_mat("res://shaders/nature/stylized_bark.gdshader", {"albedo_tex": NatureKit.tex("Bark_NormalTree.png"),
		"normal_tex": NatureKit.tex("Bark_NormalTree_Normal.png"), "tint": Color(0.86, 0.8, 0.74), "canopy_bottom": 4.0, "canopy_top": 14.0,
		"wind_strength": 0.0, "moss_amount": 0.75})


## Trees and shrubs in a ring round the terrace, never on the paths, the water or the terrace itself.
static func place_trees(a: Node) -> int:
	if off():
		return 0
	_load()
	var root := Node3D.new()
	root.name = "HeroTrees"
	a.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bark := _bark_mat()
	var variants := ["HeroOak_A", "HeroOak_B", "HeroBeech", "HeroWillow"]
	var mats := {}
	var placed: Array[Vector2] = []
	var count := 0
	var dress = a.dress
	var c: Vector2 = a.VIEWPOINT
	var tries := 0
	while count < 78 and tries < 5000:
		tries += 1
		var ang := rng.randf() * TAU
		var r := rng.randf_range(9.5, FAR_RADIUS) if count >= 40 else rng.randf_range(9.5, HERO_RADIUS + 6.0)
		var p := c + Vector2(cos(ang), sin(ang)) * r
		if not dress.inside(p, 4.0) or dress.trail_dist(p.x, p.y) < 3.2 or dress.water_dist(p) < 2.0 or dress.slope(p.x, p.y) > 0.8:
			continue
		if placed.any(func(q): return q.distance_to(p) < 7.0):
			continue
		var v: String = variants[rng.randi() % variants.size()]
		var s := rng.randf_range(0.85, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, a.height(p.x, p.y) - 0.15, p.y))
		var key := v + str(count % 2)
		if not mats.has(key):
			mats[key] = _leaf_mat(v, count % 4)
		var near := p.distance_to(c) < HERO_RADIUS + 6.0
		_add(root, _meshes[v + "_Bark"], bark, xf, near)
		_add(root, _meshes[v + "_Leaves"], mats[key], xf, near)
		placed.append(p)
		count += 1
	# leafy shrubs at the terrace's edge and along the trail
	var shrubs := 0
	tries = 0
	while shrubs < 46 and tries < 2400:
		tries += 1
		var ang := rng.randf() * TAU
		var r := rng.randf_range(7.5, HERO_RADIUS)
		var p := c + Vector2(cos(ang), sin(ang)) * r
		if not dress.inside(p, 3.0) or dress.trail_dist(p.x, p.y) < 1.6 or dress.water_dist(p) < 1.2:
			continue
		if placed.any(func(q): return q.distance_to(p) < 2.2):
			continue
		var v := "HeroShrub_A" if rng.randf() < 0.5 else "HeroShrub_B"
		var s := rng.randf_range(0.8, 1.35)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.1), s)), Vector3(p.x, a.height(p.x, p.y) - 0.05, p.y))
		if not mats.has(v):
			mats[v] = _leaf_mat(v, 1 + shrubs % 2)
		_add(root, _meshes[v + "_Leaves"], mats[v], xf, false)
		_add(root, _meshes[v + "_Bark"], bark, xf, false)
		placed.append(p)
		shrubs += 1
	var cover := ground_cover(a, root, rng)
	print("[woods] hero trees %d, shrubs %d, ground cover %s" % [count, shrubs, cover])
	return count


## Ferns, flowering plants, clover, grass clumps, mushrooms and pebbles in drifts round the terrace (the kit's
## CC0 meshes with their existing materials) - the ground reads as a forest floor, not a flat green surface.
static func ground_cover(a: Node, root: Node3D, rng: RandomNumberGenerator) -> Dictionary:
	var dress = a.dress
	var c: Vector2 = a.VIEWPOINT
	var sets := {"Fern_1": [], "Plant_7": [], "Clover_1": [], "Clover_2": [], "Flower_3_Single": [], "Flower_4_Single": [], "Flower_3_Group": [],
		"Grass_Common_Tall": [], "Grass_Wispy_Tall": [], "Grass_Common_Short": [], "Mushroom_Common": [], "Pebble_Round_2": [], "Pebble_Square_3": []}
	# drift centres: plants grow in patches
	var drifts := []
	for i in 70:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(5.5, HERO_RADIUS)
		drifts.append(c + Vector2(cos(ang), sin(ang)) * r)
	for d in drifts:
		var kind := rng.randi() % 6
		var ids: Array = [["Fern_1", "Fern_1", "Grass_Wispy_Tall"], ["Fern_1", "Plant_7", "Grass_Common_Short"], ["Clover_1", "Clover_2", "Flower_3_Single"],
			["Grass_Common_Tall", "Grass_Wispy_Tall", "Flower_4_Single"], ["Fern_1", "Mushroom_Common", "Clover_2"], ["Pebble_Round_2", "Grass_Common_Short", "Clover_1"]][kind]
		var n := rng.randi_range(8, 16)
		for k in n:
			var p: Vector2 = d + Vector2(rng.randf_range(-2.6, 2.6), rng.randf_range(-2.6, 2.6))
			if not dress.inside(p, 2.0) or dress.trail_dist(p.x, p.y) < 1.1 or dress.water_dist(p) < 0.6 or p.distance_to(c) < 6.4:
				continue
			var id: String = ids[rng.randi() % ids.size()]
			var s := rng.randf_range(0.7, 1.25) * (0.6 if id.begins_with("Pebble") else (0.55 if id.begins_with("Flower") else 1.0))
			(sets[id] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, a.height(p.x, p.y) - 0.04, p.y)))
	var out := {}
	for id in sets:
		if (sets[id] as Array).is_empty():
			continue
		NatureKit.scatter(root, NatureKit.mesh(id), sets[id], {"vis_end": 70.0, "shadow": false, "name": "Hero_" + id, "chunk": 32.0})
		out[id] = (sets[id] as Array).size()
	return out


static func _add(root: Node3D, mesh: Mesh, mat: Material, xf: Transform3D, shadow: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 220.0
	root.add_child(mi)


## The painted mountains: a cylinder 1500 m out, unshaded, behind everything, fading into the horizon haze.
static func backdrop(a: Node) -> void:
	if off() or RenderProfile.options.has("ev_nobackdrop") or not ResourceLoader.exists(BACKDROP):
		return
	var R := 1500.0
	var y0 := -90.0
	var y1 := 430.0
	var n := 96
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for k in 2:
			pass
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p00 := Vector3(cos(a0) * R, y0, sin(a0) * R)
		var p10 := Vector3(cos(a1) * R, y0, sin(a1) * R)
		var p01 := Vector3(cos(a0) * R, y1, sin(a0) * R)
		var p11 := Vector3(cos(a1) * R, y1, sin(a1) * R)
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		for t in [[p00, Vector2(u0, 1)], [p11, Vector2(u1, 0)], [p10, Vector2(u1, 1)], [p00, Vector2(u0, 1)], [p01, Vector2(u0, 0)], [p11, Vector2(u1, 0)]]:
			st.set_uv(t[1])
			st.add_vertex(t[0])
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = st.commit()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/nature/backdrop.gdshader")
	sm.set_shader_parameter("tex", load(BACKDROP))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	a.add_child(mi)
	var v = a.find_child("Vista", false, false)
	if v:
		for ch in v.get_children():
			if String(ch.name).begins_with("Ridge") or (ch is MeshInstance3D and not String(ch.name).begins_with("Landmark")):
				ch.visible = false
