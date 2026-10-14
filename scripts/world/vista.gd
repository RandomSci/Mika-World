class_name Vista
extends Node3D
## Cinematic distant scenery for outdoor areas, built cheaply and honestly:
##  * a ring of mountain ridges (≈1.5k tris) with aerial-perspective shading,
##  * landmark impostors placed in their TRUE world-map direction from this area
##    (distance compressed into the camera range with angular size preserved),
##  * optional sea of clouds.
## Impostors have no collision and no gameplay; the registry says whether each is a
## real destination, purely scenic, or unfinished.

const RING_RADIUS := 1700.0
const MAX_PLACE := 2600.0
const MIN_PLACE := 380.0


static func build(area: AreaBase) -> Vista:
	var v := Vista.new()
	v.name = "Vista"
	area.add_child(v)
	var opts: Dictionary = area.env_preset().get("vista", {})
	var haze: Color = opts.get("haze", Color(0.62, 0.7, 0.8))
	var mat := Kit.shader_mat("res://shaders/vista.gdshader", {"haze": haze, "snow_line": opts.get("snow_line", 380.0),
		"rock_tex": load("res://assets/polyhaven/textures/cliff_side/cliff_side_diff_2k.jpg"),
		"green_col": opts.get("green", Color(0.18, 0.26, 0.15)), "max_haze": opts.get("max_haze", 0.42)})
	if opts.get("mountains", false):
		# Distant ranges = the scanned CC0 "mountainside" (10 m photogrammetry rock) scaled to km size:
		# real rock forms read as mountains through the area's fog; auto mesh-LODs keep it cheap.
		var mesh: Mesh = Kit.prop("mountainside") if ResourceLoader.exists(Kit.model_path("mountainside")) else null
		var r := RandomNumberGenerator.new()
		r.seed = int(opts.get("ridge_seed", 7))
		var count: int = opts.get("mountain_count", 11)
		var height_scale: float = opts.get("ridge_height", 300.0) / 300.0
		for i in count:
			var a := TAU * (i + r.randf_range(-0.3, 0.3)) / count
			var dist := r.randf_range(1500.0, 2500.0)
			var s := r.randf_range(140.0, 230.0)
			var pos := Vector3(cos(a) * dist, opts.get("ridge_base", -40.0) - s * 0.05, sin(a) * dist)
			if mesh:
				var mi := Kit.mesh_node(v, mesh, null, Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.12, 0.22) * height_scale, s)), pos), false)
				mi.name = "Mountain%d" % i
				mi.lod_bias = 0.6
			else:
				Kit.mesh_node(v, _ridge_ring(opts.get("ridge_height", 260.0), opts.get("ridge_seed", 7)), mat, Transform3D(Basis.IDENTITY, Vector3(0, opts.get("ridge_base", -40.0), 0)), false)
				break
	if opts.get("ridge", false) and not opts.get("mountains", false):
		# painterly procedural ridges (no scanned rock): the forest's horizon
		Kit.mesh_node(v, _ridge_ring(opts.get("ridge_height", 260.0), opts.get("ridge_seed", 7)), mat, Transform3D(Basis.IDENTITY, Vector3(0, opts.get("ridge_base", -40.0), 0)), false)
	if opts.has("cloud_sea"):
		var cs := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(7000, 7000)
		cs.mesh = pm
		cs.material_override = Kit.shader_mat("res://shaders/cloud_sea.gdshader", {"radius": 3400.0})
		cs.position.y = opts.cloud_sea
		cs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(cs)
	var here: Array = area.info.global_pos
	if opts.get("no_impostors", false):
		return v   # a painted backdrop carries the horizon here (WoodsHero); the primitive impostors stay hidden
	for lid in WorldState.landmarks:
		var lm: Dictionary = WorldState.landmarks[lid]
		if lm.get("location", "") != "" and WorldState.areas.has(WorldState.locations[lm.location].area) and WorldState.locations[lm.location].area == area.area_id:
			continue  # you're standing in it
		var d := Vector3(lm.global_pos[0] - here[0], lm.global_pos[1] - here[1], lm.global_pos[2] - here[2])
		var flat := Vector2(d.x, d.z).length()
		if flat < 150.0:
			continue
		var placed := clampf(flat, MIN_PLACE, MAX_PLACE)
		var s := placed / flat
		var pos := Vector3(d.x * s, d.y * s, d.z * s)
		var node := _impostor(lm.impostor, mat, s, area)
		node.name = "Landmark_" + lid
		node.position = pos
		node.rotation.y = atan2(d.x, d.z)
		v.add_child(node)
		area.visible_landmarks.append({"id": lid, "position": pos, "true_distance_m": snappedf(Vector3(d).length(), 1.0)})
	return v


static func _ridge_ring(height: float, seed: int) -> ArrayMesh:
	var key := "ridge:%s:%s" % [height, seed]
	if Kit._meshes.has(key):
		return Kit._meshes[key]
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = 2.2
	fn.fractal_octaves = 4
	var segs := 160
	var rows := [[0.0, 0.0], [0.12, 0.55], [0.3, 1.0], [0.6, 0.75], [1.0, 0.4]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid := []
	for r in rows:
		var row := []
		for s in segs + 1:
			var a := TAU * s / segs
			var dir := Vector2(cos(a), sin(a))
			var n := fn.get_noise_2d(dir.x, dir.y) * 0.5 + 0.5
			var n2 := fn.get_noise_2d(dir.x * 3.1 + 7.0, dir.y * 3.1) * 0.5 + 0.5
			var h: float = r[1] * height * (0.35 + n * 1.1 + n2 * 0.4)
			var rad: float = RING_RADIUS + r[0] * 1100.0
			row.append(Vector3(dir.x * rad, h, dir.y * rad))
		grid.append(row)
	for ri in rows.size() - 1:
		for s in segs:
			var a: Vector3 = grid[ri][s]
			var b: Vector3 = grid[ri][s + 1]
			var c: Vector3 = grid[ri + 1][s]
			var d: Vector3 = grid[ri + 1][s + 1]
			for v in [a, c, b, b, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var m := st.commit()
	Kit._meshes[key] = m
	return m


## Simple, readable silhouettes. Detail is irrelevant at 1–3 km; shape language and haze matter.
static func _impostor(kind: String, mat: Material, s: float, area: AreaBase) -> Node3D:
	var root := Node3D.new()
	var k := 1.0 / maxf(s, 0.05)  # build in metres at true scale, then shrink by s
	root.scale = Vector3.ONE * s
	var stone := mat
	var glow := Kit.emissive(Color(1.0, 0.72, 0.4), 6.0, true)
	match kind:
		"temple_peak":
			Kit.mesh_node(root, Kit.rock_mesh(260.0, 11, 0.45, Vector3(0.9, 2.3, 0.9), 3), stone, Transform3D(Basis.IDENTITY, Vector3(0, -420, 0)), false)
			for i in 4:
				var w := 70.0 - i * 15.0
				Kit.mesh_node(root, Kit.box_mesh(Vector3(w, 9, w), 1.0), stone, Transform3D(Basis.IDENTITY, Vector3(0, 150 + i * 16, 0)), false)
				Kit.mesh_node(root, Kit.lathe([Vector2(w * 0.85, 0), Vector2(w * 0.25, 7)], 4, false), stone, Transform3D(Basis(Vector3.UP, PI / 4), Vector3(0, 155 + i * 16, 0)), false)
			area.night_only(Kit.mesh_node(root, Kit.box_mesh(Vector3(40, 3, 40), 0.5), glow, Transform3D(Basis.IDENTITY, Vector3(0, 158, 0)), false))
		"spires":
			Kit.mesh_node(root, Kit.box_mesh(Vector3(160, 50, 70), 2.0), stone, Transform3D(Basis.IDENTITY, Vector3(0, 25, 0)), false)
			for i in 5:
				var h := 90.0 + (i % 3) * 35.0
				var x := -70.0 + i * 35.0
				Kit.mesh_node(root, Kit.lathe([Vector2(9, 0), Vector2(8, h), Vector2(11, h + 2), Vector2(0, h + 38)], 8, false), stone, Transform3D(Basis.IDENTITY, Vector3(x, 0, 25 * ((i % 2) * 2 - 1))), false)
				area.night_only(Kit.mesh_node(root, Kit.box_mesh(Vector3(4, 6, 19), 0.2), glow, Transform3D(Basis.IDENTITY, Vector3(x, h * 0.7, 25 * ((i % 2) * 2 - 1))), false))
		"tower":
			Kit.mesh_node(root, Kit.lathe([Vector2(7, 0), Vector2(6, 38), Vector2(7.5, 39), Vector2(0, 52)], 12, false), stone, Transform3D.IDENTITY, false)
			area.night_only(Kit.mesh_node(root, Kit.box_mesh(Vector3(2, 3, 12.5), 0.1), glow, Transform3D(Basis.IDENTITY, Vector3(0, 32, 0)), false))
		"village":
			var r := RandomNumberGenerator.new()
			r.seed = 77
			for i in 14:
				var p := Vector3(r.randf_range(-90, 90), 0, r.randf_range(-60, 60))
				var w := r.randf_range(8, 14)
				Kit.mesh_node(root, Kit.box_mesh(Vector3(w, 7, 9), 0.3), stone, Transform3D(Basis(Vector3.UP, r.randf() * PI), p + Vector3(0, 3.5, 0)), false)
				Kit.mesh_node(root, Kit.gable_roof(w, 9, 5, 0.6, 0.4), stone, Transform3D(Basis(Vector3.UP, r.randf() * PI), p + Vector3(0, 7, 0)), false)
				area.night_only(Kit.mesh_node(root, Kit.box_mesh(Vector3(w * 0.6, 1.2, 9.3), 0.1), glow, Transform3D(Basis.IDENTITY, p + Vector3(0, 4, 0)), false))
		"dome":
			Kit.mesh_node(root, Kit.lathe([Vector2(12, 0), Vector2(12, 10), Vector2(11, 14), Vector2(6, 20), Vector2(0, 22)], 16), stone, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), false)
		"range":
			for i in 5:
				Kit.mesh_node(root, Kit.rock_mesh(190.0 + i * 25.0, 30 + i, 0.5, Vector3(1.6, 1.15 + (i % 2) * 0.35, 1.0), 3), stone, Transform3D(Basis.IDENTITY, Vector3(-700 + i * 350, -120, (i % 2) * 160)), false)
		"floating_rock":
			Kit.mesh_node(root, Kit.rock_mesh(70.0, 21, 0.4, Vector3(1.2, 0.7, 1.0), 3), stone, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0, 0)), false)
			Kit.mesh_node(root, Kit.lathe([Vector2(8, 0), Vector2(7, 60), Vector2(0, 85)], 8, false), stone, Transform3D(Basis.IDENTITY, Vector3(20, 60, 0)), false)
		"crystal_valley":
			# a valley floor of pale rock with a forest of giant crystal spires, violet, softly luminous
			var r2 := RandomNumberGenerator.new()
			r2.seed = 505
			Kit.mesh_node(root, Kit.rock_mesh(240.0, 17, 0.35, Vector3(1.8, 0.35, 1.2), 3), stone, Transform3D(Basis.IDENTITY, Vector3(0, -60, 0)), false)
			var cmat := Kit.crystal(Color(0.72, 0.5, 1.0), 2.4)
			for i in 26:
				var px := r2.randf_range(-260.0, 260.0)
				var pz := r2.randf_range(-120.0, 120.0)
				var L := r2.randf_range(90.0, 300.0) * (1.4 if absf(px) < 80.0 else 1.0)
				var rad := L * r2.randf_range(0.09, 0.16)
				var tilt := Basis(Vector3(r2.randf_range(-1, 1), 0, r2.randf_range(-1, 1)).normalized(), r2.randf_range(0.0, 0.3)) * Basis(Vector3.UP, r2.randf() * TAU)
				Kit.mesh_node(root, Kit.crystal_mesh(L, rad, 600 + i), cmat, Transform3D(tilt, Vector3(px, -20.0, pz)), false)
		"ruin_silhouette":
			for i in 4:
				var h := 25.0 + i * 12.0
				Kit.mesh_node(root, Kit.lathe([Vector2(6, 0), Vector2(5, h), Vector2(0, h + 4)], 8, false), stone, Transform3D(Basis.IDENTITY, Vector3(-60 + i * 40, 0, 0)), false)
			Kit.mesh_node(root, Kit.box_mesh(Vector3(140, 14, 6), 1.0), stone, Transform3D(Basis.IDENTITY, Vector3(0, 7, 0)), false)
	return root
