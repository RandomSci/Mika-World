class_name EnvPolish
extends RefCounted
## Milestone J targeted environment polish for the Arcane Sanctuary (the stream's home area), applied after
## the area is built so the area scripts stay untouched:
##   * tree canopies: the leaf cards were alpha-BLENDED (no depth writes -> dark, wrongly layered cards with
##     hard dark fringes). They become depth-correct alpha-scissor leaves with wrap lighting and light
##     shining through (backlight), slightly warmer so they sit with the grass.
##   * the open meadow beyond the clearing (26-48 m) gets sparse grass clumps and wildflower patches, so
##     the wide shots stop looking like a flat green carpet.
## Budget: one extra MultiMesh of grass (shared mesh/material) + one of flowers, both distance-culled.

static var _leaf_cache := {}


static func apply(world: Node, area_id: String) -> Dictionary:
	if world == null or area_id != "sanctuary":
		return {}
	var out := {"leaf_materials": _fix_leaves(world)}
	out.merge(_meadow(world))
	print("[env_polish] ", out)
	return out


static func _fix_leaves(world: Node) -> int:
	var fixed := 0
	for mi in world.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_in_group("cat_trees") and not (m.get_parent() and m.get_parent().is_in_group("cat_trees")):
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si) as BaseMaterial3D
			if src == null or src.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var mat: BaseMaterial3D = _leaf_cache.get(src)
			if mat == null:
				mat = src.duplicate()
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.42
				mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
				mat.backlight_enabled = true
				mat.backlight = Color(0.32, 0.38, 0.18)
				mat.albedo_color = src.albedo_color * Color(1.08, 1.1, 0.95)
				mat.roughness = 0.9
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				_leaf_cache[src] = mat
			m.set_surface_override_material(si, mat)
			fixed += 1
	return fixed


static func _meadow(world: Node) -> Dictionary:
	if not world.has_method("_make_grass_clump_mesh") or world.get("mats") == null:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014
	var density: float = RenderProfile.get_setting("foliage_density")
	var grass_mesh: ArrayMesh = world.call("_make_grass_clump_mesh")
	grass_mesh.surface_set_material(0, world.mats.grass)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var flowers: Array[Transform3D] = []
	var fcols: Array[Color] = []
	var palette := [Color(1.0, 0.97, 0.9), Color(1.0, 0.86, 0.35), Color(0.78, 0.66, 1.0), Color(1.0, 0.7, 0.82)]
	# clumped placement: patches of grass and flowers, not an even sprinkle
	var patches := int(70 * density)
	for pi in patches:
		var centre := Vector2.from_angle(rng.randf() * TAU) * lerpf(27.0, 48.0, sqrt(rng.randf()))
		if world.call("_blocked", centre, 1.0):
			continue
		var n := rng.randi_range(18, 40)
		var flower_patch := rng.randf() < 0.45
		var fc: Color = palette[rng.randi() % palette.size()]
		for k in n:
			var p := centre + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * rng.randf_range(1.2, 3.2)
			var y: float = world.ground_at(p.x, p.y)
			if flower_patch and k % 3 == 0:
				var s := rng.randf_range(0.7, 1.2)
				flowers.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, y, p.y)))
				fcols.append(fc.lerp(Color.WHITE, rng.randf() * 0.25))
			else:
				var s2 := rng.randf_range(0.8, 1.5)
				xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s2, s2 * rng.randf_range(0.9, 1.4), s2)), Vector3(p.x, y - 0.02, p.y)))
				cols.append(Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.1), rng.randf_range(0.75, 0.95)))
	var root := Node3D.new()
	root.name = "MeadowPolish"
	world.add_child(root)
	root.add_child(_mm(grass_mesh, xf, cols, 55.0))
	root.add_child(_mm(_flower_mesh(), flowers, fcols, 40.0))
	return {"meadow_grass": xf.size(), "meadow_flowers": flowers.size()}


static func _mm(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color], vis_end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = 5.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mmi


## A small wildflower: a thin stem and a five-petal head, coloured per instance (vertex colour x instance).
static func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.35, 0.55, 0.22)
	var h := 0.28
	for a in [0.0, PI * 0.5]:
		var d := Vector3(cos(a), 0, sin(a)) * 0.008
		for v in [[-d, 0.0], [d, 0.0], [d, h], [-d, 0.0], [d, h], [-d, h]]:
			st.set_color(stem)
			st.set_normal(Vector3.UP)
			st.add_vertex((v[0] as Vector3) + Vector3(0, float(v[1]), 0))
	for k in 5:
		var a0 := TAU * k / 5.0
		var c := Vector3(0, h, 0)
		var p1 := c + Vector3(cos(a0 - 0.35), 0.02, sin(a0 - 0.35)) * 0.055
		var p2 := c + Vector3(cos(a0), 0.035, sin(a0)) * 0.075
		var p3 := c + Vector3(cos(a0 + 0.35), 0.02, sin(a0 + 0.35)) * 0.055
		for v in [c, p1, p2, c, p2, p3]:
			st.set_color(Color.WHITE)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	return mesh
