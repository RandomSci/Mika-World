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
static var _mushroom_mat: StandardMaterial3D


## Drop cached meshes/materials/textures (called with Kit.release_unused when an area unloads).
static func release() -> int:
	var n := _meshes.size() + _tex.size()
	_meshes.clear()
	_tex.clear()
	_mushroom_mat = null
	return n


## Night: the forest's mushrooms glow (bioluminescent teal) — day: barely.
static func set_night_glow(v: bool) -> void:
	if _mushroom_mat == null:
		return
	_mushroom_mat.emission = Color(0.15, 0.85, 0.75) if v else Color(1, 1, 1)
	_mushroom_mat.emission_energy_multiplier = 1.1 if v else 0.15

## Palette presets an area can pass to mesh(): crown tints per tree family.
const CROWNS := {
	"common": {"top": Color(0.60, 0.84, 0.34), "bottom": Color(0.13, 0.30, 0.17), "trans": Color(0.8, 1.0, 0.4)},
	"twisted": {"top": Color(0.52, 0.80, 0.40), "bottom": Color(0.10, 0.26, 0.19), "trans": Color(0.7, 1.0, 0.5)},
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
static func mesh(id: String, crown := "") -> ArrayMesh:
	var key := id + "|" + crown
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
	_meshes[key] = m
	return m


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
		return Kit.shader_mat("res://shaders/nature/stylized_rock.gdshader", {"albedo_tex": tex("Rocks_Diffuse.png" if surf == "Rocks" else "PathRocks_Diffuse.png"),
			"noise_tex": noise, "moss_amount": 0.7 if surf == "Rocks" else 0.2, "tint": Color(1.0, 0.96, 0.9)})
	if surf == "Mushrooms":
		if _mushroom_mat == null:
			_mushroom_mat = StandardMaterial3D.new()
			_mushroom_mat.albedo_texture = tex("Mushrooms.png")
			_mushroom_mat.roughness = 0.7
			_mushroom_mat.emission_enabled = true
			_mushroom_mat.emission_texture = tex("Mushrooms.png")
			_mushroom_mat.emission = Color(1, 1, 1)
			_mushroom_mat.emission_energy_multiplier = 0.15
		return _mushroom_mat
	var fb := StandardMaterial3D.new()
	fb.albedo_color = Color(0.5, 0.6, 0.4)
	return fb


# ------------------------------------------------------------------ placement
## Places `xforms` of one mesh as chunked MultiMeshes. opts: vis_end (m), shadow (bool), colors (Array[Color]),
## chunk (m), name. Each instance gets INSTANCE_CUSTOM = (variation -1..1, wind phase 0..1).
static func scatter(parent: Node3D, m: Mesh, xforms: Array, opts := {}) -> Array:
	var chunk: float = opts.get("chunk", CHUNK)
	var cols: Array = opts.get("colors", [])
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
		var idx: Array = buckets[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = not cols.is_empty()
		mm.mesh = m
		mm.instance_count = idx.size()
		for j in idx.size():
			var t2: Transform3D = xforms[idx[j]]
			mm.set_instance_transform(j, t2)
			mm.set_instance_custom_data(j, Color(rng.randf_range(-1.0, 1.0), rng.randf(), 0, 0))
			if mm.use_colors:
				mm.set_instance_color(j, cols[idx[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [opts.get("name", "scatter"), k.x, k.y]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opts.get("shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ve: float = opts.get("vis_end", 0.0)
		if ve > 0.0:
			mmi.visibility_range_end = ve
			mmi.visibility_range_end_margin = minf(8.0, ve * 0.15)
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
		out.append(mmi)
	return out


## Trunk colliders (one static body, cylinders) so trees block walking and carve the navmesh.
static func trunk_colliders(parent: Node3D, xforms: Array, radius: float, height := 3.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TreeTrunks"
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
	parent.add_child(body)
	return body
