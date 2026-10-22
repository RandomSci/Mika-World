class_name NatureKit
extends RefCounted
## Stylized vegetation for Milestone K: the Quaternius Stylized Nature MegaKit (CC0) meshes, re-dressed with our own
## shaders (shaders/nature/) so trees, plants, grass and rocks share one painted, art-directed look, and placed
## with chunked MultiMeshes (per-instance colour variation and wind phase in INSTANCE_CUSTOM; chunks so the
## renderer can cull and range-fade them). The pack's materials are never used as-is.

const DIR := "res://assets/nature/snm/"
const CHUNK := 40.0

static var _meshes := {}
static var _tex := {}
static var _aabbs := {}        # mesh key -> {whole, leaf}
static var _lods := {}
static var _shadow_meshes := {}
static var _white: ImageTexture
static var _mushroom_mat: StandardMaterial3D
static var _mushroom_glow_mat: StandardMaterial3D


## Drop cached meshes/materials/textures (called with Kit.release_unused when an area unloads).
static func release() -> int:
	var n := _meshes.size() + _tex.size()
	# the warmed models stay (WARM_LIST, loaded at the stage's start): clearing them on every trip made the next
	# area load each again inside its build (0.1 s per tree model at the Mentor's Tower, 2026-10-22)
	var keep := _warm_set()
	for d in [_meshes, _aabbs]:
		for k in (d as Dictionary).keys():
			if not keep.has("mesh|" + String(k)):
				(d as Dictionary).erase(k)
	for k in _lods.keys():
		if not keep.has("lod|" + String(k).trim_suffix("|lod")):
			_lods.erase(k)
	for k in _shadow_meshes.keys():
		if not keep.has("shadow|" + String(k).trim_suffix("|shadow")):
			_shadow_meshes.erase(k)
	_tex.clear()
	_mushroom_mat = null
	_mushroom_glow_mat = null
	return n - _meshes.size()


static var _warm_cache := {}


static func _warm_set() -> Dictionary:
	if _warm_cache.is_empty() and FileAccess.file_exists(WARM_LIST):
		var j = JSON.parse_string(FileAccess.get_file_as_string(WARM_LIST))
		if j is Array:
			for k in j:
				_warm_cache[String(k)] = true
	return _warm_cache


## Night: only the GROVE's mushrooms (crown "glow") turn bioluminescent — the rest of the forest's fungi stay
## ordinary, so the glow is a place, not a texture.
static func set_night_glow(v: bool) -> void:
	if _mushroom_glow_mat == null:
		return
	_mushroom_glow_mat.emission = Color(0.12, 0.75, 0.7) if v else Color(1, 1, 1)
	_mushroom_glow_mat.emission_energy_multiplier = 0.85 if v else 0.12
	_mushroom_glow_mat.albedo_color = Color(0.55, 0.85, 0.9) if v else Color(0.85, 0.95, 1.0)

## Palette presets an area can pass to mesh(): crown tints per tree family.
const CROWNS := {
	"common": {"top": Color(0.60, 0.84, 0.34), "bottom": Color(0.17, 0.34, 0.19), "trans": Color(0.8, 1.0, 0.4)},
	"twisted": {"top": Color(0.52, 0.80, 0.40), "bottom": Color(0.14, 0.30, 0.21), "trans": Color(0.7, 1.0, 0.5)},
	"pine": {"top": Color(0.36, 0.58, 0.34), "bottom": Color(0.07, 0.19, 0.15), "trans": Color(0.5, 0.8, 0.4)},
	"blossom": {"top": Color(1.0, 0.72, 0.9), "bottom": Color(0.62, 0.36, 0.66), "trans": Color(1.0, 0.7, 0.9)},
	"bush": {"top": Color(0.50, 0.78, 0.30), "bottom": Color(0.12, 0.30, 0.14), "trans": Color(0.7, 1.0, 0.4)},
	"plant": {"top": Color(0.40, 0.66, 0.28), "bottom": Color(0.06, 0.19, 0.11), "trans": Color(0.8, 1.0, 0.45)},
	"dark": {"top": Color(0.30, 0.42, 0.30), "bottom": Color(0.06, 0.12, 0.10), "trans": Color(0.4, 0.6, 0.3)},
}


static func tex(file: String) -> Texture2D:
	if not _tex.has(file):
		_tex[file] = load(DIR + file)
	return _tex[file]


## The model's mesh with our materials. `crown` picks a palette from CROWNS for leaf surfaces.
## Every model an area build asked for, saved (user://nature_warm.json): the next start loads them all up front
## (warm_from_list), so no trip pays a first load - one tree model took 0.4 s in the middle of the tower's build.
const WARM_LIST := "user://nature_warm.json"
static var _warm_keys := {}
static var _warm_dirty := false


static func _note_warm(kind: String, id: String, crown: String) -> void:
	var k := kind + "|" + id + "|" + crown
	if not _warm_keys.has(k):
		_warm_keys[k] = true
		_warm_dirty = true


## Writes the list (called after an area is built).
static func save_warm_list() -> void:
	if not _warm_dirty:
		return
	_warm_dirty = false
	var old := {}
	if FileAccess.file_exists(WARM_LIST):
		var j = JSON.parse_string(FileAccess.get_file_as_string(WARM_LIST))
		if j is Array:
			for k in j:
				old[String(k)] = true
	for k in _warm_keys:
		old[k] = true
	var f := FileAccess.open(WARM_LIST, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(old.keys()))


## Loads every listed model, one per frame (at the stage's start, before anyone watches a trip).
static func warm_from_list(tree: SceneTree) -> int:
	if not FileAccess.file_exists(WARM_LIST):
		return 0
	var j = JSON.parse_string(FileAccess.get_file_as_string(WARM_LIST))
	if not (j is Array):
		return 0
	var n := 0
	for k in j:
		var parts := String(k).split("|")
		if parts.size() < 3:
			continue
		match parts[0]:
			"mesh": mesh(parts[1], parts[2])
			"lod": lod_mesh(parts[1], parts[2])
			"shadow": shadow_mesh(parts[1], parts[2])
		n += 1
		await tree.process_frame
	return n


static func mesh(id: String, crown := "") -> ArrayMesh:
	var key := id + "|" + crown
	_note_warm("mesh", id, crown)
	if _meshes.has(key):
		return _meshes[key]
	var ps: PackedScene = load(DIR + id + ".gltf")
	var root := ps.instantiate()
	var src: MeshInstance3D = _first_mesh(root)
	var m: ArrayMesh = src.mesh.duplicate()
	var xf := _mesh_xform(src)
	root.free()
	if xf != Transform3D.IDENTITY:
		m = _baked(m, xf)
	var whole := m.get_aabb()
	# crown extents (from the leaf surface) drive the gradient, the spherised normals and the trunk sway
	var leaf_aabb := AABB()
	for i in m.get_surface_count():
		var nm := _surf_name(m, i)
		if nm.begins_with("Leaves") or nm == "Grass":
			leaf_aabb = _surface_aabb(m, i)
	for i in m.get_surface_count():
		m.surface_set_material(i, _material(id, _surf_name(m, i), crown, whole, leaf_aabb))
	_aabbs[key] = {"whole": whole, "leaf": leaf_aabb}
	# REALISM PASS: a photoreal substitute at the same placement (RealKit), sized from the kit model
	var real := RealKit.substitute(id, crown, whole.size.y)
	if real:
		_meshes[key] = real
		return real
	_meshes[key] = m
	return m


static func white_tex() -> ImageTexture:
	if _white == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_white = ImageTexture.create_from_image(img)
	return _white


## The far version of mesh(id, crown): a soft lumpy crown and a trunk, opaque, about 1/20 of the triangles.
## Same palettes and shaders, so a tree keeps its colour when it swaps at distance (the foliage shader already
## shades crowns as volumes, which is why a blob reads right at 60 m+).
static func lod_mesh(id: String, crown := "") -> ArrayMesh:
	var key := id + "|" + crown + "|lod"
	_note_warm("lod", id, crown)
	if _lods.has(key):
		return _lods[key]
	var full := mesh(id, crown)
	if RealKit.enabled() and _aabbs.has(id + "|" + crown):
		var real_far := RealKit.substitute(id, crown, (_aabbs[id + "|" + crown].whole as AABB).size.y, true)
		if real_far:
			_lods[key] = real_far
			return real_far
	var ab: Dictionary = _aabbs[id + "|" + crown]
	var whole: AABB = ab.whole
	var leaf: AABB = ab.leaf
	var out := ArrayMesh.new()
	var has_crown := leaf.size != Vector3.ZERO
	if has_crown:
		var sm := SphereMesh.new()
		sm.radial_segments = 12
		sm.rings = 7
		sm.radius = 0.5
		sm.height = 1.0
		var st := SurfaceTool.new()
		st.create_from(sm, 0)
		var arr := st.commit_to_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var c := leaf.get_center()
		var half := leaf.size * 0.5
		for i in v.size():
			var d := v[i] * 2.0
			var bump := 1.0 + 0.12 * sin(d.x * 7.1 + d.y * 3.3) * cos(d.z * 5.7 + d.x * 2.1)
			v[i] = c + Vector3(d.x * half.x, d.y * half.y, d.z * half.z) * bump
			n[i] = d.normalized()
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var leaf_mat: ShaderMaterial = null
		for si in full.get_surface_count():
			var m := full.surface_get_material(si)
			if m is ShaderMaterial and String((m as ShaderMaterial).shader.resource_path).ends_with("stylized_foliage.gdshader"):
				leaf_mat = m
		var lm := leaf_mat.duplicate() as ShaderMaterial
		lm.set_shader_parameter("albedo_tex", white_tex())
		lm.set_shader_parameter("tint_texture_mix", Vector4(0.0, 0, 0, 0))
		lm.set_shader_parameter("flutter", 0.0)
		lm.set_shader_parameter("spherize", 1.0)
		lm.set_shader_parameter("alpha_cut", 0.0)
		out.surface_set_material(out.get_surface_count() - 1, lm)
	if not id.begins_with("Bush"):
		var top_y := leaf.get_center().y if has_crown else whole.end.y
		var r := maxf(whole.size.x, whole.size.z) * (0.06 if has_crown else 0.05)
		var cyl := Kit.lathe([Vector2(r * 1.3, whole.position.y), Vector2(r, whole.position.y + 0.6), Vector2(r * 0.75, top_y)], 7, true, false)
		var st2 := SurfaceTool.new()
		st2.create_from(cyl, 0)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st2.commit_to_arrays())
		var bark: Material = null
		for si in full.get_surface_count():
			var m2 := full.surface_get_material(si)
			if m2 is ShaderMaterial and String((m2 as ShaderMaterial).shader.resource_path).ends_with("stylized_bark.gdshader"):
				bark = m2
		out.surface_set_material(out.get_surface_count() - 1, bark if bark else StandardMaterial3D.new())
	_lods[key] = out
	return out


## The shadow-only version of a plant: the LOD crown blob with a dappled (noise-holed) shadow material, plus the
## trunk. Cast from this instead of the leaf cards (see shaders/nature/canopy_shadow.gdshader).
static func shadow_mesh(id: String, crown := "") -> ArrayMesh:
	var key := id + "|" + crown + "|shadow"
	_note_warm("shadow", id, crown)
	if _shadow_meshes.has(key):
		return _shadow_meshes[key]
	var lod := lod_mesh(id, crown)
	if RealKit.enabled() and RealKit.substitute(id, crown, 1.0) != null:
		_shadow_meshes[key] = lod     # the real far canopy casts real dappled shadows
		return lod
	var out := ArrayMesh.new()
	var dapple := Kit.shader_mat("res://shaders/nature/canopy_shadow.gdshader", {"noise_tex": Kit.noise()})
	for si in lod.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lod.surface_get_arrays(si))
		var m := lod.surface_get_material(si)
		var is_crown := m is ShaderMaterial and String((m as ShaderMaterial).shader.resource_path).ends_with("stylized_foliage.gdshader")
		out.surface_set_material(si, dapple if is_crown else m)
	_shadow_meshes[key] = out
	return out


static func _surf_name(m: ArrayMesh, i: int) -> String:
	var mat := m.surface_get_material(i)
	return mat.resource_name if mat else ""


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r:
			return r
	return null


static func _mesh_xform(n: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	var p: Node = n
	while p is Node3D:
		x = (p as Node3D).transform * x
		p = p.get_parent()
	return x


static func _baked(m: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in m.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(m, i)
		var mat := m.surface_get_material(i)
		st.set_material(mat)
		var arr := st.commit_to_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for k in v.size():
			v[k] = xf * v[k]
			if k < nrm.size():
				nrm[k] = (xf.basis * nrm[k]).normalized()
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(i, mat)
	return out


static func _surface_aabb(m: ArrayMesh, i: int) -> AABB:
	var v: PackedVector3Array = m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
	var a := AABB(v[0], Vector3.ZERO)
	for p in v:
		a = a.expand(p)
	return a


static func _material(id: String, surf: String, crown: String, whole: AABB, leaf: AABB) -> Material:
	var noise := Kit.noise()
	if surf.begins_with("Leaves") and (id.contains("Tree") or id.begins_with("Pine") or id.begins_with("Bush")):
		var fam := crown
		if fam == "":
			fam = "pine" if id.begins_with("Pine") else ("twisted" if id.begins_with("Twisted") else ("bush" if id.begins_with("Bush") else "common"))
		var pal: Dictionary = CROWNS[fam]
		var file: String = {"Leaves_NormalTree": "Leaves_NormalTree_C.png", "Leaves_TwistedTree": "Leaves_TwistedTree_C.png", "Leaves_Pine": "Leaf_Pine_C.png"}.get(surf, "Leaves_NormalTree_C.png")
		var is_pine := id.begins_with("Pine")
		return Kit.shader_mat("res://shaders/nature/stylized_foliage.gdshader", {"albedo_tex": tex(file),
			"tint_top": pal.top, "tint_bottom": pal.bottom, "translucency_color": pal.trans,
			"canopy_center": leaf.get_center() + Vector3(0, leaf.size.y * 0.08, 0), "canopy_radius": maxf(leaf.size.x, leaf.size.z) * 0.5,
			"canopy_bottom": leaf.position.y, "canopy_top": leaf.end.y,
			"spherize": 0.55 if is_pine else 0.8, "translucency": 0.55, "tint_texture_mix": Vector4(0.35, 0, 0, 0),
			"wind_strength": 0.03 * whole.size.y if not id.begins_with("Bush") else 0.06, "flutter": 0.02, "alpha_cut": 0.4})
	if surf == "Leaves":
		# undergrowth: giant leaves, ferns, clover, flower stems
		var pal2: Dictionary = CROWNS["plant" if crown == "" else crown]
		return Kit.shader_mat("res://shaders/nature/stylized_foliage.gdshader", {"albedo_tex": tex("Leaves.png"),
			"tint_top": pal2.top, "tint_bottom": pal2.bottom, "translucency_color": pal2.trans,
			"canopy_center": Vector3(whole.get_center().x, whole.position.y - whole.size.y * 0.4, whole.get_center().z),
			"canopy_bottom": whole.position.y, "canopy_top": whole.end.y, "spherize": 0.3, "translucency": 0.8,
			"tint_texture_mix": Vector4(0.6, 0, 0, 0), "wind_strength": 0.05, "flutter": 0.012, "alpha_cut": 0.4})
	if surf == "Flowers":
		return Kit.shader_mat("res://shaders/nature/stylized_foliage.gdshader", {"albedo_tex": tex("Flowers.png"),
			"tint_top": Color(0.68, 0.68, 0.68), "tint_bottom": Color(0.6, 0.6, 0.62), "translucency_color": Color(1.0, 0.85, 0.9),
			"canopy_center": whole.get_center() - Vector3(0, whole.size.y, 0), "canopy_bottom": whole.position.y, "canopy_top": whole.end.y,
			"spherize": 0.3, "translucency": 0.5, "tint_texture_mix": Vector4(1.0, 0, 0, 0), "wind_strength": 0.05, "flutter": 0.01, "variation_strength": 0.08})
	if surf == "Grass":
		return Kit.shader_mat("res://shaders/nature/stylized_grass.gdshader", {"albedo_tex": tex("Grass.png"), "tuft_height": whole.end.y,
			"root_color": Color(0.40, 0.60, 0.22), "tip_color": Color(0.62, 0.80, 0.34), "translucency": 0.3})
	if surf.begins_with("Bark"):
		var bf := surf.trim_prefix("Bark_")
		return Kit.shader_mat("res://shaders/nature/stylized_bark.gdshader", {"albedo_tex": tex("Bark_%s.png" % bf),
			"normal_tex": tex("Bark_%s_Normal.png" % bf),
			"tint": (Color(0.62, 0.56, 0.54) if bf == "NormalTree" else Color(0.8, 0.76, 0.74)) if bf != "DeadTree" else Color(0.7, 0.68, 0.72),
			"canopy_bottom": leaf.position.y if leaf.size != Vector3.ZERO else whole.size.y * 0.3,
			"canopy_top": leaf.end.y if leaf.size != Vector3.ZERO else whole.end.y,
			"wind_strength": 0.03 * whole.size.y if bf != "DeadTree" else 0.01, "moss_amount": 0.5})
	if surf == "Rocks" or surf == "PathRocks":
		if crown == "wet":   # stones in and beside water: darker, little moss
			return Kit.shader_mat("res://shaders/nature/stylized_rock.gdshader", {"albedo_tex": tex("Rocks_Diffuse.png" if surf == "Rocks" else "PathRocks_Diffuse.png"),
				"noise_tex": noise, "moss_amount": 0.25, "tint": Color(0.5, 0.56, 0.6)})
		return Kit.shader_mat("res://shaders/nature/stylized_rock.gdshader", {"albedo_tex": tex("Rocks_Diffuse.png" if surf == "Rocks" else "PathRocks_Diffuse.png"),
			"noise_tex": noise, "moss_amount": 0.7 if surf == "Rocks" else 0.2, "tint": Color(1.0, 0.96, 0.9)})
	if surf == "Mushrooms":
		if crown == "glow":
			if _mushroom_glow_mat == null:
				_mushroom_glow_mat = StandardMaterial3D.new()
				_mushroom_glow_mat.albedo_texture = tex("Mushrooms.png")
				_mushroom_glow_mat.albedo_color = Color(0.85, 0.95, 1.0)
				_mushroom_glow_mat.roughness = 0.6
				_mushroom_glow_mat.emission_enabled = true
				_mushroom_glow_mat.emission_texture = tex("Mushrooms.png")
				_mushroom_glow_mat.emission = Color(1, 1, 1)
				_mushroom_glow_mat.emission_energy_multiplier = 0.12
			return _mushroom_glow_mat
		if _mushroom_mat == null:
			_mushroom_mat = StandardMaterial3D.new()
			_mushroom_mat.albedo_texture = tex("Mushrooms.png")
			_mushroom_mat.roughness = 0.7
			_mushroom_mat.emission_enabled = false
		return _mushroom_mat
	var fb := StandardMaterial3D.new()
	fb.albedo_color = Color(0.5, 0.6, 0.4)
	return fb


# ------------------------------------------------------------------ placement
## Places `xforms` of one mesh as chunked MultiMeshes. opts: vis_end (m), shadow (bool), colors (Array[Color]),
## chunk (m), name, lod {"mesh": far mesh, "detail_end": m} (the detailed mesh fades out at detail_end and the
## far mesh fades in, up to vis_end), shadow_mesh (a cheap shadow-only caster used instead of the detailed mesh).
## Each instance gets INSTANCE_CUSTOM = (variation -1..1, wind phase 0..1).
static func scatter(parent: Node3D, m: Mesh, xforms: Array, opts := {}) -> Array:
	var chunk: float = opts.get("chunk", CHUNK)
	var cols: Array = opts.get("colors", [])
	var lod: Dictionary = opts.get("lod", {})
	var buckets := {}
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		var k := Vector2i(floori(t.origin.x / chunk), floori(t.origin.z / chunk))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(i)
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(m.get_rid()) + str(xforms.size()))
	for k in buckets:
		_scatter_chunk(parent, m, xforms, buckets[k], k, rng, cols, lod, opts, out)
	return out


## The same, handing the frame back between chunks once `slice_us` is spent (the area builder awaits it): a whole
## model's batches in one go held frames 0.3 to 0.9 s while the Mentor's Tower woods were laid out (2026-10-22).
static func scatter_sliced(parent: Node3D, m: Mesh, xforms: Array, opts := {}, slice_us := -1) -> Array:
	if slice_us < 0:
		slice_us = WorldStreamingManager.slice_us()
	var chunk: float = opts.get("chunk", CHUNK)
	var cols: Array = opts.get("colors", [])
	var lod: Dictionary = opts.get("lod", {})
	var buckets := {}
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		var k := Vector2i(floori(t.origin.x / chunk), floori(t.origin.z / chunk))
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(i)
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(m.get_rid()) + str(xforms.size()))
	var t0 := Time.get_ticks_usec()
	for k in buckets:
		_scatter_chunk(parent, m, xforms, buckets[k], k, rng, cols, lod, opts, out)
		if Time.get_ticks_usec() - t0 > slice_us and parent.is_inside_tree():
			await parent.get_tree().process_frame
			t0 = Time.get_ticks_usec()
	return out


static func _scatter_chunk(parent: Node3D, m: Mesh, xforms: Array, idx: Array, k: Vector2i, rng: RandomNumberGenerator, cols: Array, lod: Dictionary, opts: Dictionary, out: Array) -> void:
	var customs := []
	for j in idx.size():
		customs.append(Color(rng.randf_range(-1.0, 1.0), rng.randf(), 0, 0))
	var fill := func(mesh: Mesh) -> MultiMesh:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = not cols.is_empty()
		mm.mesh = mesh
		mm.instance_count = idx.size()
		for j in idx.size():
			mm.set_instance_transform(j, xforms[idx[j]])
			mm.set_instance_custom_data(j, customs[j])
			if mm.use_colors:
				mm.set_instance_color(j, cols[idx[j]])
		return mm
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_%d_%d" % [opts.get("name", "scatter"), k.x, k.y]
	mmi.multimesh = fill.call(m)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opts.get("shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ve: float = opts.get("vis_end", 0.0)
	if opts.get("shadow", false) and opts.has("shadow_mesh"):
		# the detailed mesh does not cast; a cheap shadow-only stand-in does, over the detailed range
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var caster := MultiMeshInstance3D.new()
		caster.name = mmi.name + "_shadow"
		caster.multimesh = fill.call(opts.shadow_mesh)
		caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var ce: float = lod.detail_end if not lod.is_empty() else ve
		if ce > 0.0:
			caster.visibility_range_end = ce
			caster.visibility_range_end_margin = 6.0
		parent.add_child(caster)
		out.append(caster)
	if not lod.is_empty():
		var de: float = lod.detail_end
		mmi.visibility_range_end = de
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var far := MultiMeshInstance3D.new()
		far.name = mmi.name + "_far"
		far.multimesh = fill.call(lod.mesh)
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.visibility_range_begin = de
		far.visibility_range_begin_margin = 6.0
		if ve > 0.0:
			far.visibility_range_end = ve
			far.visibility_range_end_margin = minf(8.0, ve * 0.15)
		far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(far)
		out.append(far)
	elif ve > 0.0:
		mmi.visibility_range_end = ve
		mmi.visibility_range_end_margin = minf(8.0, ve * 0.15)
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	out.append(mmi)


## Vegetation and boulders are solid for the characters but are NOT parsed into the navmesh as geometry: a
## thousand cylinder caps would be a thousand tiny walkable polygons, which overflow the navmesh edge-merge
## rasterizer and silently disconnect routes elsewhere (Milestone K, the frontier trail). Instead their colliders
## live on physics layer 3 (characters collide with it) and each one carves the navmesh through a
## NavigationObstacle3D prism — no caps, no slivers.
const VEG_LAYER := 4   # layer 3

static func vegetation_body(parent: Node3D, name := "Vegetation") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = VEG_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	return body


## A navmesh carve: a hexagonal prism of `radius` and `height` at `pos` (marks the area unwalkable in the bake;
## eroded by the agent radius like any obstacle).
static func nav_obstacle(parent: Node3D, pos: Vector3, radius: float, height := 2.5) -> NavigationObstacle3D:
	var ob := NavigationObstacle3D.new()
	ob.avoidance_enabled = false
	ob.affect_navigation_mesh = true
	ob.carve_navigation_mesh = false
	ob.position = pos - Vector3(0, 0.6, 0)
	ob.height = height + 0.6
	var v := PackedVector3Array()
	for i in 6:
		var a := TAU * i / 6.0
		v.append(Vector3(cos(a) * radius, 0, sin(a) * radius))
	ob.vertices = v
	parent.add_child(ob)
	return ob


## Trunk colliders (layer 3 cylinders + navmesh carves) so trees block walking and routes go round them.
## trunk_colliders, handing the frame back every `slice_us` (1,537 trunks took 0.45 s in one frame at the tower).
static func trunk_colliders_sliced(parent: Node3D, xforms: Array, radius: float, height := 3.0, slice_us := -1) -> StaticBody3D:
	if slice_us < 0:
		slice_us = WorldStreamingManager.slice_us()
	var body := vegetation_body(parent, "TreeTrunks")
	var holes := Node3D.new()
	holes.name = "TreeTrunkCarves"
	parent.add_child(holes)
	var t0 := Time.get_ticks_usec()
	for t in xforms:
		var tr: Transform3D = t
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		var s := tr.basis.get_scale().x
		cy.radius = radius * s
		cy.height = height
		cs.shape = cy
		cs.position = tr.origin + Vector3(0, height * 0.5 - 0.2, 0)
		body.add_child(cs)
		nav_obstacle(holes, tr.origin, radius * s, height)
		if Time.get_ticks_usec() - t0 > slice_us:
			await parent.get_tree().process_frame
			t0 = Time.get_ticks_usec()
	return body


static func trunk_colliders(parent: Node3D, xforms: Array, radius: float, height := 3.0) -> StaticBody3D:
	var body := vegetation_body(parent, "TreeTrunks")
	var holes := Node3D.new()
	holes.name = "TreeTrunkCarves"
	parent.add_child(holes)
	for t in xforms:
		var tr: Transform3D = t
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		var s := tr.basis.get_scale().x
		cy.radius = radius * s
		cy.height = height
		cs.shape = cy
		cs.position = tr.origin + Vector3(0, height * 0.5 - 0.2, 0)
		body.add_child(cs)
		nav_obstacle(holes, tr.origin, radius * s, height)
	return body
