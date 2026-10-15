class_name KitArea
extends AreaBase
## AreaBase + higher-level building blocks shared by the hand-authored areas.

const TREE_NEAR := "res://assets/trees/broadleaf_tree_near.glb"
const TREE_FAR := "res://assets/trees/broadleaf_tree_far.glb"

var _tree_lods := {}


## Paths declared for threaded preloading; subclasses return their own list.
static func resources() -> Array:
	return []


static func textures(names: Array, res := "1k") -> Array:
	var out := []
	for n in names:
		out.append_array(Kit.tex_set(n, res))
	return out


static func models(ids: Array) -> Array:
	return ids.map(func(i): return Kit.model_path(i))


# ------------------------------------------------------------------ vegetation
func _tree_meshes(path: String) -> Array:
	if not _tree_lods.has(path):
		var out := []
		var probe: Node3D = load(path).instantiate()
		for n in probe.find_children("*", "MeshInstance3D", true, false):
			out.append([n.mesh, (n as MeshInstance3D).transform])
		probe.free()
		_tree_lods[path] = out
	return _tree_lods[path]


## A tree with near/far LODs; far LOD casts the (cheap) shadow when `shadow` is set.
func tree(pos: Vector3, scale: float, yaw: float, shadow := true, collide := true) -> Node3D:
	var root := Node3D.new()
	root.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	add_child(root)
	var near_end := (13.0 if RenderProfile.tier() == RenderProfile.LIVE_OPTIMIZED else 22.0) * scale
	for tm in _tree_meshes(TREE_NEAR):
		root.add_child(_lod(tm, 0.0, near_end, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
	for tm in _tree_meshes(TREE_FAR):
		root.add_child(_lod(tm, near_end, 400.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
		if shadow:
			root.add_child(_lod(tm, 0.0, 0.0, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY))
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.45 * scale
		c.height = 4.0 * scale
		cs.shape = c
		cs.position.y = 2.0 * scale
		body.add_child(cs)
		root.add_child(body)
	return root


func _lod(tm: Array, b: float, e: float, shadow: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = tm[0]
	mi.transform = tm[1]
	mi.cast_shadow = shadow
	mi.visibility_range_begin = b
	mi.visibility_range_end = e
	if e > 0.0:
		mi.visibility_range_begin_margin = 2.0
		mi.visibility_range_end_margin = 2.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


## Scatter parts of a Poly Haven model with a MultiMesh. accept(Vector2) -> bool filters spots.
func scatter(model: String, part: String, count: int, center: Vector2, rmin: float, rmax: float, smin: float, smax: float,
		height_fn: Callable, accept: Callable = Callable(), vis_end := 60.0) -> MultiMeshInstance3D:
	var xs := []
	var n := int(count * float(RenderProfile.get_setting("foliage_density")))
	for i in n * 3:
		if xs.size() >= n:
			break
		var p := center + Vector2.from_angle(rng.randf() * TAU) * lerpf(rmin, rmax, sqrt(rng.randf()))
		if accept.is_valid() and not accept.call(p):
			continue
		var s := rng.randf_range(smin, smax)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height_fn.call(p.x, p.y) - 0.03, p.y)))
	return Kit.multimesh(self, Kit.prop(model, part), xs, vis_end)


func rocks_ring(center: Vector3, radius: float, count: int, size_min: float, size_max: float, mat: Material, height_fn: Callable, seed_base := 0) -> void:
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.2, 0.2)
		var r := radius + rng.randf_range(-1.5, 1.5)
		var p := Vector3(center.x + cos(a) * r, 0, center.z + sin(a) * r)
		var s := rng.randf_range(size_min, size_max)
		var mi := Kit.mesh_node(self, Kit.rock_mesh(1.0, seed_base + i, 0.38, Vector3(1.0, rng.randf_range(0.6, 1.3), rng.randf_range(0.8, 1.2)), 2), mat,
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height_fn.call(p.x, p.z) - s * 0.25, p.z)))
		Kit.convex_collide(mi)


# ------------------------------------------------------------------ architecture helpers
## Invisible perimeter so characters stay inside the authored playable space.
func boundary_circle(center: Vector3, radius: float, height := 6.0, segments := 32) -> void:
	for i in segments:
		var a := TAU * (i + 0.5) / segments
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		var w := TAU * radius / segments + 0.4
		Kit.static_box(self, Vector3(w, height, 0.6), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p + Vector3(0, height * 0.5 - 1.0, 0)))


func boundary_box(center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	for s: float in [-1.0, 1.0]:
		Kit.static_box(self, Vector3(size.x + 1, size.y, 0.6), Kit.xf(center + Vector3(0, h.y - 1, s * h.z)))
		Kit.static_box(self, Vector3(0.6, size.y, size.z + 1), Kit.xf(center + Vector3(s * h.x, h.y - 1, 0)))


## Straight stair of blocks rising along local -Z from `base`; returns top position.
func stairs(base: Vector3, yaw: float, width: float, steps: int, rise: float, run: float, mat: Material) -> Vector3:
	var b := Basis(Vector3.UP, yaw)
	for k in steps:
		var c := base + b * Vector3(0, rise * (k + 0.5), -run * (k + 0.5))
		Kit.block(self, Vector3(width, rise * (k + 1), run), Transform3D(b, c - b * Vector3(0, rise * k * 0.5, 0)), mat, false, 0.02)
	# Collision is a smooth ramp under the step nosings: CharacterBody3D has no step-up, and a
	# rise/run of 0.2/0.42 (~25°) is well inside floor_max_angle. Visuals keep crisp steps.
	var top := base + b * Vector3(0, rise * steps, -run * steps)
	# ramp plane from the stair foot to exactly the top edge (flush with the landing, no lip),
	# extended 0.5 m below ground at the foot only
	var dir := (top - base).normalized()
	var foot := base - dir * 0.5
	var length := foot.distance_to(top)
	var pitch := atan2(rise * steps, run * steps)
	var thick := 0.4
	var ramp_basis := b * Basis(Vector3.RIGHT, pitch)
	var mid := (foot + top) * 0.5 - ramp_basis * Vector3(0, thick * 0.5, 0)
	Kit.static_box(self, Vector3(width, thick, length), Transform3D(ramp_basis, mid))
	return top


## Semicircular arch of wedge-like blocks in the local XY plane (opening along Z).
func arch(center: Vector3, yaw: float, span: float, thickness: float, depth: float, mat: Material, pieces := 9) -> void:
	var b := Basis(Vector3.UP, yaw)
	var r := span * 0.5 + thickness * 0.5
	for i in pieces:
		var a := PI * (i + 0.5) / pieces
		var p := Vector3(cos(a) * r, sin(a) * r, 0)
		var seg := PI * r / pieces - 0.02
		var basis := b * Basis(Vector3.FORWARD, -(PI * 0.5 - a))
		Kit.block(self, Vector3(seg, thickness, depth), Transform3D(basis, center + b * p), mat, true, 0.03)


## Timber-framed house: stone ground floor, plaster upper floor with dark beams, slate gable roof,
## chimney, warm windows at night. Box collision. Returns the house root.
func house(pos: Vector3, yaw: float, w: float, d: float, mats: Dictionary, seed: int, floors := 2) -> Node3D:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var root := Node3D.new()
	root.transform = Kit.xf(pos, yaw)
	add_child(root)
	var fh := 2.9
	Kit.block(root, Vector3(w, fh, d), Kit.xf(Vector3(0, fh * 0.5, 0)), mats.stone, true, 0.05)
	var top := fh
	if floors > 1:
		Kit.block(root, Vector3(w + 0.3, fh, d + 0.3), Kit.xf(Vector3(0, fh * 1.5, 0)), mats.plaster, true, 0.03)
		top = fh * 2.0
		# timber frame: posts, rails, braces
		for side: float in [-1.0, 1.0]:
			var zf := side * (d * 0.5 + 0.17)
			var nposts := int(w / 1.3) + 1
			for i in nposts:
				var x := -w * 0.5 + w * i / (nposts - 1)
				Kit.mesh_node(root, Kit.box_mesh(Vector3(0.18, fh, 0.08), 0.015), mats.timber, Kit.xf(Vector3(x, fh * 1.5, zf)))
			for y in [fh + 0.08, fh * 2.0 - 0.1, fh * 1.45]:
				Kit.mesh_node(root, Kit.box_mesh(Vector3(w + 0.35, 0.16, 0.09), 0.015), mats.timber, Kit.xf(Vector3(0, y, zf)))
			for i in range(0, nposts - 1, 2):
				var x0 := -w * 0.5 + w * i / (nposts - 1)
				var x1 := -w * 0.5 + w * (i + 1) / (nposts - 1)
				var len := Vector2(x1 - x0, fh * 0.45).length()
				Kit.mesh_node(root, Kit.box_mesh(Vector3(len, 0.14, 0.08), 0.015), mats.timber,
					Transform3D(Basis(Vector3.FORWARD, -atan2(fh * 0.45, x1 - x0)), Vector3((x0 + x1) * 0.5, fh * 1.2, zf)))
		for side: float in [-1.0, 1.0]:
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.09, fh, d + 0.35), 0.015), mats.timber, Kit.xf(Vector3(side * (w * 0.5 + 0.17), fh * 1.5, 0)))
	var rise := d * 0.45
	Kit.mesh_node(root, Kit.gable_end(d + (0.3 if floors > 1 else 0.0), rise, 0.2), mats.plaster, Kit.xf(Vector3(-w * 0.5 - 0.05, top, 0)))
	Kit.mesh_node(root, Kit.gable_end(d + (0.3 if floors > 1 else 0.0), rise, 0.2), mats.plaster, Kit.xf(Vector3(w * 0.5 + 0.05, top, 0)))
	Kit.mesh_node(root, Kit.gable_roof(w, d + 0.3, rise, 0.45, 0.14), mats.roof, Kit.xf(Vector3(0, top, 0)))
	var cx := r.randf_range(-w * 0.3, w * 0.3)
	Kit.block(root, Vector3(0.7, rise + 1.6, 0.7), Kit.xf(Vector3(cx, top + (rise + 1.6) * 0.5, -d * 0.18)), mats.stone, false, 0.03)
	# door + windows (warm glow at night, dark glass by day)
	var door := Kit.block(root, Vector3(1.05, 2.1, 0.08), Kit.xf(Vector3(r.randf_range(-w * 0.25, w * 0.25), 1.05, d * 0.5 + 0.03)), mats.door, false, 0.01)
	var glow: Material = mats.window_glow
	for side: float in [-1.0, 1.0]:
		var nwin := maxi(1, int(w / 2.6))
		for i in nwin:
			var x := -w * 0.5 + w * (i + 0.5) / nwin
			for fl in floors:
				if fl == 0 and side > 0 and absf(x - door.position.x) < 1.0:
					continue
				var y := 1.55 + fl * fh
				var zf := side * (d * 0.5 + (0.19 if fl > 0 else 0.03))
				Kit.mesh_node(root, Kit.box_mesh(Vector3(0.85, 1.05, 0.06), 0.01), mats.window_day, Kit.xf(Vector3(x, y, zf)), false)
				Kit.mesh_node(root, Kit.box_mesh(Vector3(1.05, 0.1, 0.16), 0.01), mats.timber, Kit.xf(Vector3(x, y - 0.6, zf)), false)
				if r.randf() < 0.7:
					night_only(Kit.mesh_node(root, Kit.box_mesh(Vector3(0.8, 1.0, 0.065), 0.01), glow, Kit.xf(Vector3(x, y, zf + side * 0.005)), false))
	if r.randf() < 0.5:
		night_only(Kit.omni(root, Vector3(0, 1.6, d * 0.5 + 1.2), Color(1.0, 0.65, 0.35), 0.8, 5.0))
	return root


func village_mats() -> Dictionary:
	return {
		"stone": Kit.tri("castle_wall_slates", "1k", 0.5, 0.2),
		"plaster": Kit.tri("plastered_wall_02", "1k", 0.35, 0.0, Color(0.95, 0.92, 0.86)),
		"timber": Kit.tri("dark_wooden_planks", "1k", 0.6, 0.0, Color(0.55, 0.45, 0.38)),
		"roof": Kit.uvmat("roof_slates_02", "1k", Vector2(0.9, 0.9)),
		"door": Kit.tri("dark_wooden_planks", "1k", 1.2, 0.0, Color(0.6, 0.45, 0.32)),
		"window_day": Kit.metal(Color(0.08, 0.1, 0.12), 0.12),
		"window_glow": Kit.emissive(Color(1.0, 0.7, 0.38), 3.2),
	}


func lantern_post(pos: Vector3, mats: Dictionary, energy := 1.2) -> void:
	Kit.block(self, Vector3(0.14, 2.6, 0.14), Kit.xf(pos + Vector3(0, 1.3, 0)), mats.timber, true, 0.02)
	Kit.mesh_node(self, Kit.box_mesh(Vector3(0.7, 0.1, 0.1), 0.01), mats.timber, Kit.xf(pos + Vector3(0.3, 2.55, 0)))
	Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01"), null, Kit.xf(pos + Vector3(0.58, 2.2, 0), 0.0, Vector3.ONE * 1.3))
	Kit.mesh_node(self, Kit.prop("Lantern_01", "Lantern_01_glass"), null, Kit.xf(pos + Vector3(0.58, 2.2, 0), 0.0, Vector3.ONE * 1.3))
	Kit.mesh_node(self, SphereMesh.new(), Kit.emissive(Color(1.0, 0.68, 0.35), 7.0, true), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.05), pos + Vector3(0.58, 2.42, 0)), false)
	night_only(Kit.omni(self, pos + Vector3(0.58, 2.35, 0), Color(1.0, 0.66, 0.36), energy, 7.0))


func rune_disc(center: Vector3, radius: float, col_outer: Color, col_inner: Color, seed := 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rune_floor.gdshader")
	var f := "res://assets/polyhaven/textures/monastery_stone_floor/monastery_stone_floor_"
	m.set_shader_parameter("floor_albedo", load(f + "diff_2k.jpg"))
	m.set_shader_parameter("floor_normal", load(f + "nor_gl_2k.jpg"))
	m.set_shader_parameter("floor_rough", load(f + "rough_2k.jpg"))
	m.set_shader_parameter("floor_ao", load(f + "ao_2k.jpg"))
	m.set_shader_parameter("moss_albedo", load(Kit.MOSS + "Color.jpg"))
	m.set_shader_parameter("breakup_noise", Kit.noise())
	m.set_shader_parameter("rune_color", col_outer)
	m.set_shader_parameter("rune_color_inner", col_inner)
	m.set_shader_parameter("glyph_seed", seed)
	m.set_shader_parameter("radius_m", radius)
	m.set_shader_parameter("idle_glow", 0.35)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius + 0.05
	cyl.height = 0.12
	cyl.radial_segments = 64
	disc.mesh = cyl
	disc.material_override = m
	disc.position = center + Vector3(0, 0.06, 0)
	add_child(disc)
	Kit.static_box(self, Vector3(radius * 1.4, 0.12, radius * 1.4), Kit.xf(center + Vector3(0, 0.06, 0)))
	return m
