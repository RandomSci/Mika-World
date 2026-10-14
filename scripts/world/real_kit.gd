class_name RealKit
extends RefCounted
## REALISM PASS: photoreal substitutes for the stylized nature kit. NatureKit.mesh()/lod_mesh()/shadow_mesh()
## ask `substitute()` first; every area that scatters the kit (trees, understory, undergrowth, rocks) then gets
## photoreal vegetation and stone at the same placements, normalised to the kit model's height so densities and
## clearances stay as designed. Sources (all CC0): our own trees (tools/models/build_real_trees.py) with
## photoreal leaf twigs (tools/textures/leaf_twigs.py from ambientCG LeafSet009/010) and Poly Haven bark;
## Poly Haven scans: fern_02, nettle_plant, shrub_02, rock_moss_set_01/02.
## `--stylized` turns the whole realism pass off (the previous look).

const TREES := "res://assets/nature/real/real_trees.glb"
const TREE_INFO := "res://assets/nature/real/real_trees.json"
const CONIFERS := "res://assets/nature/real/real_conifers.glb"           # spruces / firs (tools/models/build_real_conifers.py)
const CONIFER_INFO := "res://assets/nature/real/real_conifers.json"
const PH := "res://assets/polyhaven/models/"

static var _cache := {}
static var _src := {}
static var _info := {}
static var _mats := {}


static func enabled() -> bool:
	return not RenderProfile.options.has("stylized")


static func _tex(path: String) -> Texture2D:
	return load(path)


static func ph_tex(name: String, kind: String) -> Texture2D:
	var b := "res://assets/polyhaven/textures/%s/%s_" % [name, name]
	for res in ["2k", "1k"]:
		for k in ([kind] if kind != "diff" else ["diff", "diffuse"]):
			var p: String = b + String(k) + "_" + String(res) + ".jpg"
			if ResourceLoader.exists(p):
				return load(p)
	return null


static func leaf_mat() -> ShaderMaterial:
	if not _mats.has("leaf"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/real/real_leaf.gdshader")
		m.set_shader_parameter("albedo_tex", _tex("res://assets/nature/real/twigs_albedo.png"))
		m.set_shader_parameter("normal_tex", _tex("res://assets/nature/real/twigs_normal.png"))
		Gusts.register(m)
		_mats["leaf"] = m
	return _mats.leaf


## Needle sprays (conifers): the same leaf shader with the needle atlas.
static func needle_mat() -> ShaderMaterial:
	if not _mats.has("needles"):
		var m := (leaf_mat().duplicate() as ShaderMaterial)
		m.set_shader_parameter("albedo_tex", _tex("res://assets/nature/real/needles_albedo.png"))
		m.set_shader_parameter("normal_tex", _tex("res://assets/nature/real/needles_normal.png"))
		Gusts.register(m)
		_mats["needles"] = m
	return _mats.needles


static func bark_mat(kind := "tree_bark_03") -> ShaderMaterial:
	var key := "bark:" + kind
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/real/real_bark.gdshader")
		m.set_shader_parameter("bark_albedo", ph_tex(kind, "diff"))
		m.set_shader_parameter("bark_normal", ph_tex(kind, "nor_gl"))
		m.set_shader_parameter("bark_rough", ph_tex(kind, "rough"))
		m.set_shader_parameter("moss_albedo", load("res://assets/ambientcg/Moss002/Moss002_1K-JPG_Color.jpg"))
		m.set_shader_parameter("moss_normal", load("res://assets/ambientcg/Moss002/Moss002_1K-JPG_NormalGL.jpg"))
		m.set_shader_parameter("noise_tex", Kit.noise())
		Gusts.register(m)
		_mats[key] = m
	return _mats[key]


## A scanned plant's imported material as real_plant.gdshader: the same maps, plus sway and gusts.
static func plant_mat(src: Material, plant_h: float) -> Material:
	if not (src is BaseMaterial3D):
		return src
	var key := "plant:%s:%s" % [src.get_instance_id(), snappedf(plant_h, 0.05)]
	if _mats.has(key):
		return _mats[key]
	var b := src as BaseMaterial3D
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/real/real_plant.gdshader")
	m.set_shader_parameter("albedo_tex", b.albedo_texture)
	m.set_shader_parameter("albedo_color", b.albedo_color)
	m.set_shader_parameter("use_normal", 1.0 if (b.normal_enabled and b.normal_texture != null) else 0.0)
	if b.normal_texture:
		m.set_shader_parameter("normal_tex", b.normal_texture)
	var orm: Texture2D = b.roughness_texture if b.roughness_texture else b.ao_texture
	m.set_shader_parameter("use_orm", 1.0 if orm != null else 0.0)
	if orm:
		m.set_shader_parameter("orm_tex", orm)
	m.set_shader_parameter("alpha_cut", b.alpha_scissor_threshold if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
	m.set_shader_parameter("plant_height", plant_h)
	Gusts.register(m)
	_mats[key] = m
	return m


static func stone_mat(kind := "rock_pitted_mossy", vertex_color := true) -> ShaderMaterial:
	var key := "stone:%s:%s" % [kind, vertex_color]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/real/real_stone.gdshader")
		m.set_shader_parameter("stone_alb", ph_tex(kind, "diff"))
		m.set_shader_parameter("stone_nrm", ph_tex(kind, "nor_gl"))
		m.set_shader_parameter("moss_alb", load("res://assets/ambientcg/Moss002/Moss002_1K-JPG_Color.jpg"))
		m.set_shader_parameter("moss_nrm", load("res://assets/ambientcg/Moss002/Moss002_1K-JPG_NormalGL.jpg"))
		m.set_shader_parameter("noise_tex", Kit.noise())
		m.set_shader_parameter("use_vertex_color", vertex_color)
		_mats[key] = m
	return _mats[key]


static func terrain_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/real/real_terrain.gdshader")
	for pair in [["litter", "forest_leaves_02"], ["floor", "forest_floor"], ["path", "mud_forest"], ["rock", "rock_pitted_mossy"], ["bank", "stony_dirt_path"]]:
		m.set_shader_parameter(pair[0] + "_alb", ph_tex(pair[1], "diff"))
		m.set_shader_parameter(pair[0] + "_nrm", ph_tex(pair[1], "nor_gl"))
	m.set_shader_parameter("moss_alb", load("res://assets/ambientcg/Moss002/Moss002_1K-JPG_Color.jpg"))
	m.set_shader_parameter("moss_nrm", load("res://assets/ambientcg/Moss002/Moss002_1K-JPG_NormalGL.jpg"))
	m.set_shader_parameter("noise_tex", Kit.noise())
	return m


static func _load_trees() -> void:
	if not _src.is_empty():
		return
	var scene: Node = (load(TREES) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		_src[String(mi.name)] = (mi as MeshInstance3D).mesh
	scene.free()
	_info = JSON.parse_string(FileAccess.get_file_as_string(TREE_INFO))
	if ResourceLoader.exists(CONIFERS):
		var cs: Node = (load(CONIFERS) as PackedScene).instantiate()
		for mi in cs.find_children("*", "MeshInstance3D", true, false):
			_src[String(mi.name)] = (mi as MeshInstance3D).mesh
		cs.free()
		var ci: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONIFER_INFO))
		_info.merge(ci)


## Two-surface tree (bark + leaves), scaled by s.
static func _tree(variant: String, far: bool, s: float, bark_kind: String) -> ArrayMesh:
	_load_trees()
	var out := ArrayMesh.new()
	var bark: Mesh = _src[variant + ("_FarBark" if far else "_Bark")]
	var leaves: Mesh = _src[variant + ("_FarLeaves" if far else "_Leaves")]
	_append(out, bark, bark_mat(bark_kind), s)
	var conifer := variant.begins_with("RealSpruce") or variant.begins_with("RealFir") or variant.begins_with("RealPine")
	var lm := (needle_mat() if conifer else leaf_mat()).duplicate() as ShaderMaterial
	lm.set_shader_parameter("crown_height", float(_info[variant].height) * s)
	Gusts.register(lm)
	_append(out, leaves, lm, s)
	return out


static func _append(out: ArrayMesh, src: Mesh, mat: Material, s: float) -> void:
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		if s != 1.0:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] *= s
			arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mat)


## A Poly Haven scan's meshes (all MeshInstances flattened, their own materials kept), scaled to height h.
static func _scan(id: String, h: float, pick := -1, sway := false) -> ArrayMesh:
	# the real-time version (tools/models/decimate_scans.py) when it exists
	var path := "res://assets/nature/real/" + id + "_low.glb"
	if not ResourceLoader.exists(path):
		path = PH + id + "/" + id + "_1k.gltf"
	if not ResourceLoader.exists(path):
		path = PH + id + "/" + id + "_2k.gltf"
	var scene: Node = (load(path) as PackedScene).instantiate()
	var mis := scene.find_children("*", "MeshInstance3D", true, false)
	var out := ArrayMesh.new()
	var aabb := AABB()
	var parts := []
	for k in mis.size():
		if pick >= 0 and k != pick % mis.size():
			continue
		var mi := mis[k] as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		if pick >= 0:
			xf.origin = Vector3.ZERO     # a single rock from a set: centred
		parts.append([mi.mesh, xf])
		var ab := xf * mi.mesh.get_aabb()
		aabb = ab if aabb.size == Vector3.ZERO else aabb.merge(ab)
	var s := h / maxf(aabb.size.y, 0.01)
	var lift := -aabb.position.y * s
	for pr in parts:
		var m: Mesh = pr[0]
		var xf: Transform3D = pr[1]
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in v.size():
				v[i] = (xf * v[i]) * s + Vector3(0, lift, 0)
				if i < n.size():
					n[i] = (xf.basis * n[i]).normalized()
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_NORMAL] = n
			arr[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var sm := m.surface_get_material(si)
			out.surface_set_material(out.get_surface_count() - 1, plant_mat(sm, h) if sway else sm)
	scene.free()
	return out


static func _empty() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, -5, 0), Vector3(0.001, -5, 0), Vector3(0, -5, 0.001)]:
		st.add_vertex(v)
	return st.commit()


## kit id -> substitute (null = keep the kit model). kit_h: the kit model's own height (metres, before scatter
## scaling) so the substitute stands as tall as the design expected (trees a little taller: real woods are tall).
static func substitute(id: String, crown: String, kit_h: float, far := false) -> ArrayMesh:
	if not enabled():
		return null
	var key := "%s|%s|%s" % [id, crown, far]
	if _cache.has(key):
		return _cache[key]
	var out: ArrayMesh = null
	var tree_map := {"CommonTree_1": "RealBeech_A", "CommonTree_2": "RealBeech_B", "CommonTree_3": "RealMaple", "CommonTree_4": "RealBeech_A", "CommonTree_5": "RealOak",
		"TwistedTree_1": "RealOak", "TwistedTree_2": "RealMaple", "TwistedTree_3": "RealOak", "TwistedTree_4": "RealBeech_B", "TwistedTree_5": "RealOak",
		"Pine_1": "RealSpruce_A", "Pine_2": "RealSpruce_B", "Pine_3": "RealFir", "Pine_4": "RealSpruce_A", "Pine_5": "RealPineYoung",
		"DeadTree_1": "RealYoung", "DeadTree_2": "RealYoung", "DeadTree_3": "RealYoung", "DeadTree_4": "RealYoung", "DeadTree_5": "RealYoung"}
	if tree_map.has(id):
		_load_trees()
		var v: String = tree_map[id]
		var target := clampf(kit_h * 1.45, 6.0, 26.0)
		if v.begins_with("RealSpruce") or v.begins_with("RealFir"):
			target = clampf(kit_h * 1.3, 9.0, 24.0)
		var s := clampf(target / float(_info[v].height), 0.3, 1.25)
		out = _tree(v, far, s, "bark_brown_02" if v in ["RealOak", "RealMaple", "RealSpruce_A", "RealSpruce_B", "RealFir", "RealPineYoung"] else "tree_bark_03")
	elif id.begins_with("Bush_"):
		out = _scan("shrub_02", clampf(kit_h, 0.8, 2.2), -1, true)
	elif id.begins_with("Clover"):
		out = _empty()      # moss in the floor texture stands in for clover carpets
	elif id.begins_with("Fern") or id.begins_with("Plant_"):
		out = _scan("fern_02", clampf(kit_h * (1.0 if id.begins_with("Fern") else 0.8), 0.35, 1.3), -1, true)
	elif id.begins_with("Flower") or id.begins_with("Mushroom") or id.begins_with("Petal") or id.begins_with("Grass"):
		out = _scan("nettle_plant", clampf(kit_h * 0.9, 0.3, 0.9), -1, true) if id.begins_with("Flower") else _empty()
	elif id.begins_with("Rock_Medium"):
		out = _scan("rock_moss_set_01", maxf(kit_h, 0.5), int(id.right(1)))
	elif id.begins_with("Pebble") or id.begins_with("RockPath"):
		out = _scan("rock_moss_set_02", maxf(kit_h, 0.12), id.hash())
	_cache[key] = out
	return out
