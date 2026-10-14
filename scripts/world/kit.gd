class_name Kit
extends RefCounted
## Shared construction kit for all streamed areas: cached CC0 PBR materials, bevelled
## architectural primitives, Poly Haven prop lookup, MultiMesh scatter, terrain and lights.
## Materials/meshes are cached by key and released by `release_unused()` when an area unloads.

const PH_TEX := "res://assets/polyhaven/textures/"
const PH_MOD := "res://assets/polyhaven/models/"
const MOSS := "res://assets/ambientcg/Moss002/Moss002_1K-JPG_"

static var _mats := {}
static var _meshes := {}
static var _props := {}
static var _noise: NoiseTexture2D


# ------------------------------------------------------------------ texture paths (also used as RESOURCES lists)
static func tex_set(name: String, res: String) -> PackedStringArray:
	var b := PH_TEX + name + "/" + name + "_"
	# fall back to whatever resolution was actually downloaded
	if not FileAccess.file_exists(b + "nor_gl_" + res + ".jpg"):
		for r in ["1k", "2k", "4k"]:
			if FileAccess.file_exists(b + "nor_gl_" + r + ".jpg"):
				res = r
				break
	var d := "diff"
	for cand in ["diff", "diffuse", "col_01", "col_1", "color"]:
		if FileAccess.file_exists(b + cand + "_" + res + ".jpg"):
			d = cand
			break
	return PackedStringArray([b + d + "_" + res + ".jpg", b + "nor_gl_" + res + ".jpg", b + "rough_" + res + ".jpg", b + "ao_" + res + ".jpg"])


static func model_path(id: String) -> String:
	return PH_MOD + id + "/" + id + "_1k.gltf"


static func noise() -> NoiseTexture2D:
	if _noise == null:
		_noise = NoiseTexture2D.new()
		_noise.width = 512
		_noise.height = 512
		_noise.seamless = true
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 5
		fn.seed = 1234
		_noise.noise = fn
	return _noise


# ------------------------------------------------------------------ materials
## World-space triplanar PBR (no UVs needed) using the sanctuary's weathering shader.
static func tri(tex: String, res := "1k", tiling := 0.4, moss := 0.0, tint := Color(1, 1, 1), extra := {}) -> ShaderMaterial:
	var key := "tri:%s:%s:%s:%s:%s:%s" % [tex, res, tiling, moss, tint, extra]
	if _mats.has(key):
		return _mats[key]
	var t := tex_set(tex, res)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/stone_triplanar.gdshader")
	m.set_shader_parameter("stone_albedo", load(t[0]))
	m.set_shader_parameter("stone_normal", load(t[1]))
	m.set_shader_parameter("stone_rough", load(t[2]))
	if ResourceLoader.exists(t[3]):
		m.set_shader_parameter("stone_ao", load(t[3]))
	m.set_shader_parameter("moss_albedo", load(MOSS + "Color.jpg"))
	m.set_shader_parameter("moss_normal", load(MOSS + "NormalGL.jpg"))
	m.set_shader_parameter("breakup_noise", noise())
	m.set_shader_parameter("tiling", tiling)
	m.set_shader_parameter("moss_amount", moss)
	m.set_shader_parameter("stone_tint", tint)
	m.set_shader_parameter("tint_variation", 0.08 if moss == 0.0 else 0.18)
	if moss == 0.0:
		m.set_shader_parameter("grime_height", 0.25)
	for k in extra:
		if k != "two_sided":
			m.set_shader_parameter(k, extra[k])
	_mats[key] = m
	return m


## UV-mapped PBR StandardMaterial (roofs, floors with directional patterns, fabric).
static func uvmat(tex: String, res := "1k", uv_scale := Vector2.ONE, tint := Color(1, 1, 1), cull_off := false) -> StandardMaterial3D:
	var key := "uv:%s:%s:%s:%s:%s" % [tex, res, uv_scale, tint, cull_off]
	if _mats.has(key):
		return _mats[key]
	var t := tex_set(tex, res)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(t[0])
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(t[1])
	m.roughness_texture = load(t[2])
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if ResourceLoader.exists(t[3]):
		m.ao_enabled = true
		m.ao_texture = load(t[3])
	m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func emissive(col: Color, energy := 3.0, unshaded := false) -> StandardMaterial3D:
	var key := "em:%s:%s:%s" % [col, energy, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


static func metal(col: Color, rough := 0.35) -> StandardMaterial3D:
	var key := "metal:%s:%s" % [col, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 1.0
	m.roughness = rough
	_mats[key] = m
	return m


static func crystal(col: Color, energy := 2.5) -> ShaderMaterial:
	var key := "crystal:%s:%s" % [col, energy]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/crystal.gdshader")
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("glow", energy)
	_mats[key] = m
	return m


static func shader_mat(path: String, params := {}) -> ShaderMaterial:
	var key := "sh:%s:%s" % [path, params]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	if path.ends_with("water.gdshader") or path.ends_with("vista.gdshader") or path.ends_with("cloud_sea.gdshader"):
		m.set_shader_parameter("noise_tex", noise())
	Gusts.register(m)
	_mats[key] = m
	return m


## Called when an area unloads: drop every cached material/mesh/prop/shape so their textures and
## buffers can be freed (the next area rebuilds what it needs in a few ms). Returns entries dropped.
static func release_unused() -> int:
	AreaBase.clear_collision_cache()
	var n := _mats.size() + _meshes.size() + _props.size() + _convex.size() + NatureKit.release()
	_mats.clear()
	_meshes.clear()
	_props.clear()
	_convex.clear()
	return n


static func cache_sizes() -> Dictionary:
	return {"materials": _mats.size(), "meshes": _meshes.size(), "props": _props.size()}


# ------------------------------------------------------------------ meshes
## Chamfered box (flat-shaded faces + bevel strips), centred at origin.
static func box_mesh(size: Vector3, bevel := 0.03) -> ArrayMesh:
	var key := "box:%s:%s" % [size, bevel]
	if _meshes.has(key):
		return _meshes[key]
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.45)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := []
	var tris := []
	for a in 3:
		for s: float in [-1.0, 1.0]:
			var pts := []
			for c: Array in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var v := Vector3.ZERO
				v[a] = s * h[a]
				v[(a + 1) % 3] = c[0] * (h[(a + 1) % 3] - b)
				v[(a + 2) % 3] = c[1] * (h[(a + 2) % 3] - b)
				pts.append(v)
			quads.append(pts)
	for a in 3:
		var a2 := (a + 1) % 3
		var c := (a + 2) % 3
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var pts := []
				for sc: float in [-1.0, 1.0]:
					var p1 := Vector3.ZERO
					p1[a] = sa * h[a]; p1[a2] = sb * (h[a2] - b); p1[c] = sc * (h[c] - b)
					var p2 := Vector3.ZERO
					p2[a] = sa * (h[a] - b); p2[a2] = sb * h[a2]; p2[c] = sc * (h[c] - b)
					pts.append(p1); pts.append(p2)
				quads.append([pts[0], pts[1], pts[3], pts[2]])
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				tris.append([Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b)), Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b)), Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)])
	for q in quads:
		_emit_poly(st, q)
	for t in tris:
		_emit_poly(st, t)
	var m := st.commit()
	_meshes[key] = m
	return m


static func _emit_poly(st: SurfaceTool, pts: Array) -> void:
	var cen := Vector3.ZERO
	for p in pts: cen += p
	cen /= pts.size()
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if n.dot(cen) < 0.0:
		pts = pts.duplicate()
		pts.reverse()
		n = -n
	for i in range(1, pts.size() - 1):
		for v in [pts[0], pts[i + 1], pts[i]]:
			st.set_normal(n)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)


## Surface of revolution around Y. profile = [Vector2(r, y), ...] bottom→top. `sides` < 8 gives faceted prisms.
static func lathe(profile: Array, sides := 32, smooth := true, caps := true) -> ArrayMesh:
	var key := "lathe:%s:%s:%s:%s" % [profile, sides, smooth, caps]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if not smooth:
		st.set_smooth_group(-1)
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			for v in [v00, v10, v01, v01, v10, v11]:
				st.set_uv(Vector2(float(s) / sides * 4.0, v.y))
				st.add_vertex(v)
	if caps:
		for end in [0, profile.size() - 1]:
			var p: Vector2 = profile[end]
			if p.x < 0.001:
				continue
			for s in sides:
				var a0 := TAU * s / sides
				var a1 := TAU * (s + 1) / sides
				var c := Vector3(0, p.y, 0)
				var v0 := Vector3(cos(a0) * p.x, p.y, sin(a0) * p.x)
				var v1 := Vector3(cos(a1) * p.x, p.y, sin(a1) * p.x)
				var tri := [c, v0, v1] if end == 0 else [c, v1, v0]
				for v in tri:
					st.set_uv(Vector2(v.x, v.z))
					st.add_vertex(v)
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m


## Gable roof with UVs (u along the ridge, v down the slope), thickness and overhang.
static func gable_roof(width: float, depth: float, rise: float, overhang := 0.35, thick := 0.12) -> ArrayMesh:
	var key := "roof:%s:%s:%s:%s" % [width, depth, rise, overhang]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := width * 0.5 + overhang
	var hz := depth * 0.5 + overhang
	var drop := rise * overhang / (depth * 0.5)
	for side: float in [-1.0, 1.0]:
		var ridge := Vector3(0, rise, 0)
		var eave_z := side * hz
		var e_y := -drop
		var slope_len := Vector2(hz, rise + drop).length()
		var quads := [
			[Vector3(-hx, rise, 0), Vector3(hx, rise, 0), Vector3(hx, e_y, eave_z), Vector3(-hx, e_y, eave_z)],
			[Vector3(-hx, rise - thick, 0), Vector3(-hx, e_y - thick, eave_z), Vector3(hx, e_y - thick, eave_z), Vector3(hx, rise - thick, 0)],
			[Vector3(-hx, e_y, eave_z), Vector3(hx, e_y, eave_z), Vector3(hx, e_y - thick, eave_z), Vector3(-hx, e_y - thick, eave_z)],
		]
		for qi in quads.size():
			var q: Array = quads[qi]
			var n: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
			var want := Vector3(0, 1, side * 0.6) if qi == 0 else (Vector3(0, -1, 0) if qi == 1 else Vector3(0, 0, side))
			if n.dot(want) < 0:
				q = [q[0], q[3], q[2], q[1]]
				n = -n
			var uvs := [Vector2(0, 0), Vector2(width + 2 * overhang, 0), Vector2(width + 2 * overhang, slope_len), Vector2(0, slope_len)]
			if q[1].x < q[0].x:
				uvs = [Vector2(width + 2 * overhang, 0), Vector2(0, 0), Vector2(0, slope_len), Vector2(width + 2 * overhang, slope_len)]
			# Godot's front faces wind clockwise seen from outside (n = (q1-q0)x(q3-q0) is CCW): emit 0,2,1 / 0,3,2,
			# or the top is culled and the underside (normal down, unlit) shows through black from above
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(n)
				st.set_uv(uvs[idx] * 0.5)
				st.add_vertex(q[idx])
	st.generate_tangents()
	var m := st.commit()
	_meshes[key] = m
	return m


## Triangular gable-end wall (fills under a gable roof), local origin at the eave line centre.
static func gable_end(width: float, rise: float, thick := 0.25) -> ArrayMesh:
	var key := "gable:%s:%s:%s" % [width, rise, thick]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var ht := thick * 0.5
	for s: float in [-1.0, 1.0]:
		var pts := [Vector3(s * ht, 0, -hw), Vector3(s * ht, 0, hw), Vector3(s * ht, rise, 0)]
		_emit_poly(st, pts)
	for e in [[Vector3(0, 0, -hw), Vector3(0, rise, 0)], [Vector3(0, rise, 0), Vector3(0, 0, hw)]]:
		var a: Vector3 = e[0]
		var b2: Vector3 = e[1]
		_emit_poly(st, [a + Vector3(-ht, 0, 0), b2 + Vector3(-ht, 0, 0), b2 + Vector3(ht, 0, 0), a + Vector3(ht, 0, 0)])
	var m := st.commit()
	_meshes[key] = m
	return m


## Irregular rock/crystal-friendly blob: noise-displaced sphere.
static func rock_mesh(radius: float, seed := 1, roughness := 0.35, squash := Vector3.ONE, detail := 2) -> ArrayMesh:
	var key := "rock:%s:%s:%s:%s:%s" % [radius, seed, roughness, squash, detail]
	if _meshes.has(key):
		return _meshes[key]
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12 * detail
	sm.rings = 6 * detail
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = 1.3
	fn.fractal_octaves = 3
	for i in verts.size():
		var v := verts[i]
		var d := 1.0 + fn.get_noise_3dv(v * 1.0) * roughness
		verts[i] = v * d * squash * radius
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(am, 0)
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m


## Elongated faceted crystal (hexagonal prism + pointed tip).
static func crystal_mesh(length: float, radius: float, seed := 0) -> ArrayMesh:
	var key := "crys:%s:%s:%s" % [length, radius, seed]
	if _meshes.has(key):
		return _meshes[key]
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var prof := [Vector2(radius * 0.7, 0), Vector2(radius, length * 0.15), Vector2(radius * r.randf_range(0.85, 1.0), length * 0.72), Vector2(0.0, length)]
	var m := lathe(prof, 6, false, true)
	_meshes[key] = m
	return m


# ------------------------------------------------------------------ props (Poly Haven)
## Mesh of a named part of a Poly Haven model (first mesh if part == "").
static func prop(id: String, part := "") -> Mesh:
	var key := id + ":" + part
	if _props.has(key):
		return _props[key]
	var ps: PackedScene = load(model_path(id))
	var root: Node = ps.instantiate()
	var found: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if part == "" or String(n.name).begins_with(part):
			found = n
			break
	var mesh: Mesh = found.mesh if found else null
	root.free()
	_props[key] = mesh
	return mesh


## All meshes of a Poly Haven model with their relative transforms (multi-part props like barrels sets).
static func prop_parts(id: String) -> Array:
	var key := id + ":*"
	if _props.has(key):
		return _props[key]
	var root: Node3D = (load(model_path(id)) as PackedScene).instantiate()
	var out := []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var cur: Node = n
		while cur != root and cur is Node3D:
			t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		out.append([n.mesh, t])
	root.free()
	_props[key] = out
	return out


# ------------------------------------------------------------------ node helpers
static func mesh_node(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat:
		mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func static_box(parent: Node3D, size: Vector3, xf: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.transform = xf
	parent.add_child(body)
	return body


## Bevelled block with matching box collision.
static func block(parent: Node3D, size: Vector3, xf: Transform3D, mat: Material, collide := true, bevel := 0.03) -> MeshInstance3D:
	var mi := mesh_node(parent, box_mesh(size, bevel), mat, xf)
	if collide:
		static_box(parent, size, xf)
	return mi


static func trimesh_collide(mi: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	mi.add_child(body)


static var _convex := {}


static func convex_collide(mi: MeshInstance3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	if not _convex.has(mi.mesh):
		_convex[mi.mesh] = mi.mesh.create_convex_shape(true, true)  # hull is expensive on scanned meshes; reuse per mesh
	cs.shape = _convex[mi.mesh]
	body.add_child(cs)
	mi.add_child(body)


static func place_prop(parent: Node3D, id: String, xf: Transform3D, part := "", collide := false) -> MeshInstance3D:
	var mi := mesh_node(parent, prop(id, part), null, xf)
	if collide:
		convex_collide(mi)
	return mi


static func place_prop_all(parent: Node3D, id: String, xf: Transform3D, collide := false) -> Node3D:
	var root := Node3D.new()
	root.transform = xf
	parent.add_child(root)
	for p in prop_parts(id):
		var mi := mesh_node(root, p[0], null, p[1])
		if collide:
			convex_collide(mi)
	return root


static func multimesh(parent: Node3D, mesh: Mesh, xforms: Array, vis_end := 0.0, shadow := false, mat: Material = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = 3.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi


static func omni(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = shadow
	l.light_volumetric_fog_energy = 0.8
	parent.add_child(l)
	return l


static func xf(pos: Vector3, yaw := 0.0, scale := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos)


# ------------------------------------------------------------------ terrain
## Heightfield terrain: mesh (vertex colours carry blend masks) + HeightMapShape3D collision.
## height_fn(x, z) -> float; mask_fn(x, z) -> Color(path, forest, rock).
static func terrain(parent: Node3D, size: float, step: float, height_fn: Callable, mask_fn: Callable, mat: Material) -> StaticBody3D:
	var n := int(size / step) + 1
	var half := size * 0.5
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for iz in n:
		for ix in n:
			hs[iz * n + ix] = height_fn.call(-half + ix * step, -half + iz * step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var x := -half + ix * step
			var z := -half + iz * step
			var hl := hs[iz * n + maxi(ix - 1, 0)]
			var hr := hs[iz * n + mini(ix + 1, n - 1)]
			var hd := hs[maxi(iz - 1, 0) * n + ix]
			var hu := hs[mini(iz + 1, n - 1) * n + ix]
			st.set_normal(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
			st.set_color(mask_fn.call(x, z))
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, hs[iz * n + ix], z))
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + n)
			st.add_index(i + 1); st.add_index(i + n + 1); st.add_index(i + n)
	st.generate_tangents()
	var body := StaticBody3D.new()
	body.name = "Terrain"
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	body.add_child(mi)
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = hs
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(step, 1, step)
	body.add_child(cs)
	return body


## Terrain blend material with any three Poly Haven ground layers (+ optional tints).
static func terrain_mat(grass: String, forest: String, path: String, grass_tint := Color(0.92, 0.98, 0.86), forest_tint := Color(0.5, 0.56, 0.4), res_g := "1k") -> ShaderMaterial:
	var key := "terrain:%s:%s:%s:%s:%s" % [grass, forest, path, grass_tint, forest_tint]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain_blend.gdshader")
	var g := tex_set(grass, res_g)
	var f := tex_set(forest, "1k")
	var p := tex_set(path, "1k")
	m.set_shader_parameter("grass_albedo", load(g[0]))
	m.set_shader_parameter("grass_normal", load(g[1]))
	m.set_shader_parameter("grass_rough", load(g[2]))
	m.set_shader_parameter("grass2_albedo", load(g[0]))
	m.set_shader_parameter("leaves_albedo", load(f[0]))
	m.set_shader_parameter("leaves_normal", load(f[1]))
	m.set_shader_parameter("leaves_rough", load(f[2]))
	m.set_shader_parameter("path_albedo", load(p[0]))
	m.set_shader_parameter("path_normal", load(p[1]))
	m.set_shader_parameter("path_rough", load(p[2]))
	m.set_shader_parameter("breakup_noise", noise())
	m.set_shader_parameter("grass_tint", grass_tint)
	m.set_shader_parameter("leaves_tint", forest_tint)
	_mats[key] = m
	return m


## Enclosing cave shell: an inward-facing, noise-displaced ellipsoid. `keep(dir)` can reject
## faces (e.g. to cut a cave mouth); dir is the unit direction from the centre.
static func cave_shell(radii: Vector3, seed: int, roughness := 0.22, keep: Callable = Callable(), segs := 40, rings := 22) -> ArrayMesh:
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = 1.6
	fn.fractal_octaves = 4
	var grid := []
	for r in rings + 1:
		var phi := PI * r / rings
		var row := []
		for s in segs + 1:
			var th := TAU * s / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var n := fn.get_noise_3dv(d * 2.0)
			row.append([d, d * radii * (1.0 + n * roughness)])
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		for s in segs:
			var a: Array = grid[r][s]
			var b: Array = grid[r][s + 1]
			var c: Array = grid[r + 1][s]
			var d: Array = grid[r + 1][s + 1]
			var dir: Vector3 = ((a[0] + b[0] + c[0] + d[0]) * 0.25).normalized()
			if keep.is_valid() and not keep.call(dir):
				continue
			# inward-facing winding (verified per triangle against the outward direction)
			for tri in [[a[1], b[1], c[1]], [c[1], b[1], d[1]]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				# Godot front faces are clockwise as seen by the viewer; for a viewer at the centre that
				# means the right-hand cross product must point OUTWARD.
				if (p1 - p0).cross(p2 - p0).dot(p0 + p1 + p2) < 0.0:
					tri = [p0, p2, p1]
				for v in tri:
					st.add_vertex(v)
	st.generate_normals()
	return st.commit()
