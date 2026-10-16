class_name StarfallPlace
extends Node3D
## STARFALL HILL in the living world: the env-test scene's pieces (scripts/areas/starfall_hill.gd) placed in the
## sanctuary, a short walk from where Mika and Luna first wake (the developer: "near their first spawn point").
## One great old tree (Poly Haven island_tree_01) on the open grass west of the ruins, dense wind-stirred grass,
## glowing wildflowers and periwinkles round the patch where they lie, scanned grass clumps, ferns at the roots,
## fireflies after dusk, and the ESO Milky Way as the sanctuary's night sky (eso0932a, CC BY 4.0, CREDITS.md).
## It lives on the real clock: by day the grass is green and the flowers only flowers; from dusk the grass turns
## to moonlit blue, the flowers glow, the fireflies come out and the Milky Way rises.
## At night (Levels 1-9) the two walk here together, lie down under the edge of the canopy, watch the sky and talk
## (Companionship._stargaze_together + MageDialogue), then get up and wander the hill (spots()).

const SITE := Vector2(-33.0, 21.0)          # the tree (open within 8 m, a little raised: --mktest=starfall_site)
const TREE_H := 13.5
const BED_DIST := 4.6                       # their bed, from the trunk toward the sanctuary (the open side)
const GRASS_R := 13.0
const SCAN_R := 5.5
const CORE_AZ := 34.0
const CORE_EL := 9.0
const ARCH_AZ := -38.0
const ARCH_EL := 58.0

static var instance: StarfallPlace

var main: Node
var world: Node
var bed := Vector3.ZERO                     # where their heads meet (world)
var tree_base := Vector3.ZERO
var _grass_mat: ShaderMaterial
var _flower_mat: ShaderMaterial
var _plant_mats: Array[ShaderMaterial] = []
var _leaf_mats: Array[ShaderMaterial] = []
var _bark_mats: Array[StandardMaterial3D] = []
var _flies: Array[GPUParticles3D] = []
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _acc := 0.0
var _dl := -1.0


## Built into the sanctuary when it is shown (main: streaming.before_reveal).
static func populate(m: Node, w: Node) -> void:
	if w == null or not w.has_method("ground_at") or String(m.streaming.current_id) != "sanctuary":
		return
	if instance and is_instance_valid(instance) and instance.get_parent() == w:
		return
	var p := StarfallPlace.new()
	p.name = "StarfallHill"
	p.main = m
	p.world = w
	w.add_child(p)
	instance = p
	# the sanctuary's day follows the clock (the real one in live play): sun, dusk, night, dawn
	if WorldState.real_clock or RenderProfile.options.has("day-cycle"):
		SanctuaryDayCycle.attach(m, w)


func h(x: float, z: float) -> float:
	return float(world.ground_at(x, z))


func _ready() -> void:
	_rng.seed = 7741
	_noise.seed = 12
	tree_base = Vector3(SITE.x, h(SITE.x, SITE.y), SITE.y)
	var to_home := (Vector2(0, 1.6) - SITE).normalized()
	var b2 := SITE + to_home * BED_DIST + Vector2(-to_home.y, to_home.x) * 1.2
	bed = Vector3(b2.x, h(b2.x, b2.y), b2.y)
	_tree()
	_grass()
	_wildflowers()
	_scanned_plants()
	_fireflies()
	_night_sky()
	_moonlight()
	_register()
	_update_light(true)
	print("[starfall] Starfall Hill in the sanctuary: tree %s, bed %s" % [tree_base, bed])


## Spots on the hill to wander to: {id: {pos, look, label}} (the tree, the flowers, the view, the bed).
func spots() -> Dictionary:
	var fwd := (bed - tree_base)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	var out := {}
	var add := func(id: String, p: Vector3, look: Vector3, label: String):
		var map: RID = world.get_world_3d().navigation_map
		var np := NavigationServer3D.map_get_closest_point(map, p)
		out[id] = {"pos": np, "look": look, "label": label}
	add.call("tree", tree_base + fwd * 1.7 + side * 0.6, tree_base + Vector3(0, 2.2, 0), "the old tree on Starfall Hill")
	add.call("flowers", bed + side * 2.4 + fwd * 0.8, bed + side * 2.4 + fwd * 0.8 + Vector3(0, -1.0, 0), "the glowing flowers in the grass")
	add.call("view", bed + fwd * 6.5, bed + fwd * 30.0 + Vector3(0, 6.0, 0), "the edge of the hill, looking out over the sanctuary")
	add.call("bed", bed, bed + Vector3(0, 10.0, 0), "the grass where they lie and watch the stars")
	add.call("roots", tree_base - side * 2.4 + fwd * 0.4, tree_base + Vector3(0, 1.0, 0), "the ferns among the roots")
	return out


func near(p: Vector3, r := 18.0) -> bool:
	return Vector2(p.x - bed.x, p.z - bed.z).length() < r or Vector2(p.x - tree_base.x, p.z - tree_base.z).length() < r


# ------------------------------------------------------------------ the place in the world's registry
func _register() -> void:
	var a: Dictionary = WorldState.areas.get("sanctuary", {})
	a["stargaze_spot"] = [bed.x, bed.z]
	a["stargaze_place"] = "Starfall Hill, under the old tree"
	if world.get("points_of_interest") is Dictionary:
		for id in spots():
			var s: Dictionary = spots()[id]
			world.points_of_interest["starfall_" + id] = {"position": world.to_local(s.pos), "description": s.label, "interact_radius": 2.0}


# ------------------------------------------------------------------ the tree
func _tree() -> void:
	var scene: PackedScene = load("res://assets/polyhaven/models/island_tree_01/island_tree_01_2k.gltf")
	if scene == null:
		push_warning("[starfall] island_tree_01 missing")
		return
	var t: Node3D = scene.instantiate()
	t.name = "HeroTree"
	add_child(t)
	var aabb := AABB()
	var first := true
	var tinv := t.global_transform.affine_inverse()
	for mi in t.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var bb := (tinv * m.global_transform) * m.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	var k := TREE_H / maxf(aabb.size.y, 0.1)
	t.scale = Vector3.ONE * k
	t.rotation.y = deg_to_rad(200.0)
	t.global_position = tree_base + Vector3(0, -aabb.position.y * k - 0.25, 0)
	var wind := load("res://shaders/starfall/foliage_wind.gdshader")
	for mi in t.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si) as StandardMaterial3D
			if src == null:
				continue
			var nm := String(src.resource_name)
			if nm.ends_with("_leaves") or nm.ends_with("_branches"):
				var sm := ShaderMaterial.new()
				sm.shader = wind
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("normal_tex", src.normal_texture)
				sm.set_shader_parameter("arm_tex", src.roughness_texture if src.roughness_texture else src.ao_texture)
				sm.set_shader_parameter("base_world", tree_base)
				sm.set_shader_parameter("calm_height", 4.0)
				sm.set_shader_parameter("amp", 0.03 if nm.ends_with("_leaves") else 0.02)
				m.set_surface_override_material(si, sm)
				_leaf_mats.append(sm)
			else:
				var bark := src.duplicate() as StandardMaterial3D
				m.set_surface_override_material(si, bark)
				_bark_mats.append(bark)
	var body := StaticBody3D.new()
	body.name = "TreeTrunk"
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.85
	cyl.height = 4.0
	cs.shape = cyl
	body.add_child(cs)
	add_child(body)
	body.global_position = tree_base + Vector3(0, 2.0, 0)


# ------------------------------------------------------------------ grass, flowers, plants
func _body_dist(x: float, z: float) -> float:
	# the patch where they lie is pressed flat (two bodies side by side, heads at the bed)
	var fwd := Vector2(bed.x - tree_base.x, bed.z - tree_base.z).normalized()
	var p := Vector2(x, z) - Vector2(bed.x, bed.z)
	var along := p.dot(fwd)
	var across := absf(p.dot(Vector2(-fwd.y, fwd.x)))
	if along < -0.4 or along > 2.0:
		return 9.0
	return maxf(0.0, across - 0.75)


func _grass_mesh(blades: int, width: float, spread: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = blades * 977 + int(width * 10000)
	var base_i := 0
	for k in blades:
		var ang := r.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * spread
		var hh := r.randf_range(0.65, 1.0)
		var lean := dir * r.randf_range(0.08, 0.32)
		var w := width * r.randf_range(0.75, 1.25)
		var n := (dir * -0.35 + Vector3.UP).normalized()
		var id := r.randf()
		for s in 4:
			var t := s / 3.0
			var c := root + Vector3(0, hh * t, 0) + lean * t * t
			var ww := w * (1.0 - t * 0.92)
			for e in [-1.0, 1.0]:
				st.set_normal(n)
				st.set_uv(Vector2(id, t))
				st.add_vertex(c + side * ww * e)
		for s in 3:
			var q := base_i + s * 2
			for i in [q, q + 1, q + 3, q, q + 3, q + 2]:
				st.add_index(i)
		base_i += 8
	return st.commit()


func _multimesh(nm: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D], customs: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_custom_data(k, customs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _glow_tex() -> ImageTexture:
	# where the grass tips glow (near the flowers round the bed), in world metres round the bed
	var res := 64
	var ext := 16.0
	var img := Image.create(res, res, false, Image.FORMAT_RF)
	for j in res:
		for i in res:
			var x := bed.x - ext + (i + 0.5) * 2.0 * ext / res
			var z := bed.z - ext + (j + 0.5) * 2.0 * ext / res
			var d := Vector2(x, z).distance_to(Vector2(bed.x, bed.z))
			img.set_pixel(i, j, Color((1.0 - smoothstep(1.2, 5.5, d)) * 0.45, 0, 0))
	return ImageTexture.create_from_image(img)


func _grass() -> void:
	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = load("res://shaders/moonbloom/grass.gdshader")
	_grass_mat.set_shader_parameter("glow_map", _glow_tex())
	_grass_mat.set_shader_parameter("glow_extent", 16.0)
	_grass_mat.set_shader_parameter("wind_strength", 0.12)
	_grass_mat.set_shader_parameter("fade_start", 30.0)
	_grass_mat.set_shader_parameter("fade_end", 60.0)
	var fd := float(RenderProfile.get_setting("foliage_density"))
	var rings := [["GrassNear", 0.0, 7.0, int(14000 * fd), 6, 0.006, 0.07], ["GrassMid", 6.5, GRASS_R, int(12000 * fd), 6, 0.011, 0.1]]
	var c := Vector2(bed.x, bed.z).lerp(SITE, 0.35)
	for ring in rings:
		var xforms: Array[Transform3D] = []
		var customs: Array[Color] = []
		var tries := 0
		while xforms.size() < int(ring[3]) and tries < int(ring[3]) * 4:
			tries += 1
			var rr := sqrt(lerpf(float(ring[1]) ** 2, float(ring[2]) ** 2, _rng.randf()))
			var a := _rng.randf() * TAU
			var x := c.x + cos(a) * rr
			var z := c.y + sin(a) * rr
			if Vector2(x, z).distance_to(SITE) < 1.1:
				continue
			var sy := _rng.randf_range(0.28, 0.55) * (1.0 + 0.3 * _noise.get_noise_2d(x * 9.0, z * 9.0))
			sy *= lerpf(1.0, 0.45, 1.0 - smoothstep(GRASS_R - 3.0, GRASS_R, rr))   # thins out at the edge
			if rr < 7.0:
				sy *= lerpf(0.18, 1.0, smoothstep(0.35, 0.95, _body_dist(x, z)))
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.0, sy, 1.0))
			xforms.append(Transform3D(b, Vector3(x, h(x, z) - 0.02, z)))
			customs.append(Color(_rng.randf(), 0, 0, 0))
		_multimesh(String(ring[0]), _grass_mesh(int(ring[4]), float(ring[5]), float(ring[6])), _grass_mat, xforms, customs)


func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H := 0.22
	for rot in [0.0, PI * 0.5]:
		var side := Vector3(cos(rot), 0, sin(rot)) * 0.0025
		for s in 4:
			var t0 := s / 4.0
			var t1 := (s + 1) / 4.0
			var c0 := Vector3(0.01 * t0 * t0, H * t0, 0)
			var c1 := Vector3(0.01 * t1 * t1, H * t1, 0)
			for pv in [[c0 - side, t0], [c0 + side, t0], [c1 + side, t1], [c0 - side, t0], [c1 + side, t1], [c1 - side, t1]]:
				st.set_normal(Vector3(0, 0, 1))
				st.set_uv(Vector2(0.0, pv[1]))
				st.set_color(Color(0, 0, 0))
				st.add_vertex(pv[0])
	var top := Vector3(0.01, H, 0)
	for k in 6:
		var ang := k * TAU / 6.0
		var out := Vector3(cos(ang), 0, sin(ang))
		var perp := Vector3(-out.z, 0, out.x)
		var mid := top + out * 0.022 + Vector3(0, 0.004, 0)
		var tip := top + out * 0.04 + Vector3(0, 0.012, 0)
		for pv in [[top, 0.0], [mid - perp * 0.013, 0.6], [tip, 1.0], [top, 0.0], [tip, 1.0], [mid + perp * 0.013, 0.6]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(1.0, 1.0))
			st.set_color(Color(0, pv[1], 0))
			st.add_vertex(pv[0])
	for k in 5:
		var a0 := k * TAU / 5.0
		var a1 := (k + 1) * TAU / 5.0
		for p in [top + Vector3(0, 0.007, 0), top + Vector3(cos(a0), 0.002, sin(a0)) * 0.008, top + Vector3(cos(a1), 0.002, sin(a1)) * 0.008]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5, 1.0))
			st.set_color(Color(0, 1, 0))
			st.add_vertex(p)
	return st.commit()


func _wildflowers() -> void:
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var tries := 0
	while xforms.size() < 320 and tries < 40000:
		tries += 1
		var rr := sqrt(_rng.randf()) * (6.0 if xforms.size() < 240 else 14.0)
		var a := _rng.randf() * TAU
		var x := bed.x + cos(a) * rr
		var z := bed.z + sin(a) * rr
		var d := (1.0 - smoothstep(1.2, 5.5, rr)) * 0.9 if xforms.size() < 240 else 0.15
		if _rng.randf() > d * smoothstep(0.55, 0.9, _body_dist(x, z)) or Vector2(x, z).distance_to(SITE) < 1.3:
			continue
		var s := _rng.randf_range(0.8, 1.35)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		b = Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.25)) * b
		xforms.append(Transform3D(b, Vector3(x, h(x, z) - 0.01, z)))
		customs.append(Color(_rng.randf(), _rng.randf_range(0.5, 1.1), _rng.randf(), 0))
	_flower_mat = ShaderMaterial.new()
	_flower_mat.shader = load("res://shaders/moonbloom/flower.gdshader")
	_flower_mat.set_shader_parameter("petal_color", Color(0.85, 0.9, 1.0))
	_flower_mat.set_shader_parameter("glow_a", Color(0.55, 0.68, 1.0))
	_flower_mat.set_shader_parameter("glow_b", Color(0.78, 0.72, 1.0))
	_flower_mat.set_shader_parameter("glow_c", Color(0.95, 0.97, 1.0))
	_flower_mat.set_shader_parameter("stem_color", Color(0.05, 0.12, 0.05))
	_flower_mat.set_shader_parameter("wind_strength", 0.03)
	_multimesh("Wildflowers", _flower_mesh(), _flower_mat, xforms, customs)


func _scan_variants(path: String, petal_glow := 0.0, amp := 0.12, tint := Color(1, 1, 1)) -> Array:
	var ps := load(path) as PackedScene
	if ps == null:
		return []
	var root: Node3D = ps.instantiate()
	var out := []
	var shader := load("res://shaders/starfall/plant_wind.gdshader")
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var src := m.get_active_material(0) as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = shader
		if src:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			sm.set_shader_parameter("normal_tex", src.normal_texture)
			sm.set_shader_parameter("arm_tex", src.roughness_texture if src.roughness_texture else src.ao_texture)
			sm.set_shader_parameter("alpha_cut", src.alpha_scissor_threshold if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.4)
		var aabb := m.mesh.get_aabb()
		sm.set_shader_parameter("root_y", aabb.position.y)
		sm.set_shader_parameter("amp", amp)
		sm.set_shader_parameter("petal_glow", petal_glow)
		sm.set_shader_parameter("tint", tint)
		sm.set_meta("night_glow", petal_glow)
		_plant_mats.append(sm)
		out.append({"mesh": m.mesh, "mat": sm, "aabb": aabb})
	root.free()
	return out


func _scatter(nm: String, variants: Array, spots: Array) -> int:
	if variants.is_empty():
		return 0
	var per := {}
	for i in spots.size():
		var v: int = _rng.randi() % variants.size()
		per.get_or_add(v, []).append(spots[i])
	var n := 0
	for v in per:
		var var_d: Dictionary = variants[v]
		var aabb: AABB = var_d.aabb
		var centre := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
		var xforms: Array[Transform3D] = []
		var customs: Array[Color] = []
		for sp in per[v]:
			var b := Basis(Vector3.UP, float(sp[1])).scaled(Vector3.ONE * float(sp[2]))
			xforms.append(Transform3D(b, sp[0]) * Transform3D(Basis.IDENTITY, -centre))
			customs.append(Color(0, 0, 0, 0))
		_multimesh("%s_%d" % [nm, v], var_d.mesh, var_d.mat, xforms, customs)
		n += xforms.size()
	return n


func _scanned_plants() -> void:
	var grass := _scan_variants("res://assets/polyhaven/models/grass_medium_02/grass_medium_02_1k.gltf", 0.0, 0.14)
	var gs := []
	var tries := 0
	var want := int(1100 * float(RenderProfile.get_setting("foliage_density")))
	while gs.size() < want and tries < want * 20:
		tries += 1
		var rr := sqrt(_rng.randf()) * SCAN_R
		var a := _rng.randf() * TAU
		var x := bed.x + cos(a) * rr
		var z := bed.z + sin(a) * rr
		if _body_dist(x, z) < 0.5 or Vector2(x, z).distance_to(SITE) < 1.2:
			continue
		gs.append([Vector3(x, h(x, z) - 0.02, z), _rng.randf() * TAU, _rng.randf_range(1.3, 2.1)])
	_scatter("ScanGrass", grass, gs)
	var peri := _scan_variants("res://assets/polyhaven/models/periwinkle_plant/periwinkle_plant_1k.gltf", 1.4, 0.05)
	var ps := []
	tries = 0
	while ps.size() < 120 and tries < 20000:
		tries += 1
		var rr := lerpf(0.9, 5.5, pow(_rng.randf(), 0.8))
		var a := _rng.randf() * TAU
		var x := bed.x + cos(a) * rr
		var z := bed.z + sin(a) * rr
		if _body_dist(x, z) < 0.55 or Vector2(x, z).distance_to(SITE) < 1.3:
			continue
		ps.append([Vector3(x, h(x, z) - 0.01, z), _rng.randf() * TAU, _rng.randf_range(0.6, 1.0)])
	_scatter("Periwinkles", peri, ps)
	var fern := _scan_variants("res://assets/polyhaven/models/fern_02/fern_02_1k.gltf", 0.0, 0.06)
	var fs := []
	for k in 11:
		var a := deg_to_rad(110.0 + k * 22.0 + _rng.randf_range(-8, 8))
		var rr := _rng.randf_range(1.5, 3.4)
		var x := SITE.x + cos(a) * rr
		var z := SITE.y + sin(a) * rr
		if Vector2(x, z).distance_to(Vector2(bed.x, bed.z)) < 2.4:
			continue
		fs.append([Vector3(x, h(x, z) - 0.03, z), _rng.randf() * TAU, _rng.randf_range(0.8, 1.25)])
	_scatter("Ferns", fern, fs)


# ------------------------------------------------------------------ fireflies (after dusk)
func _emitter(nm: String, at: Vector3, amount: int, life: float, box: Vector3, quad: Vector2, turb: float) -> void:
	var gp := GPUParticles3D.new()
	gp.name = nm
	gp.amount = maxi(1, int(amount * float(RenderProfile.get_setting("particle_scale"))))
	gp.lifetime = life
	gp.preprocess = life
	gp.visibility_aabb = AABB(-box - Vector3(10, 10, 10), (box + Vector3(10, 10, 10)) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.gravity = Vector3(0, 0.02, 0)
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.18
	pm.direction = Vector3(0.3, 0.4, 0.2)
	pm.spread = 150.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = turb
	pm.turbulence_noise_scale = 5.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.09
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.15, Color(1, 1, 1, 1))
	ramp.add_point(0.85, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = quad
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/moonbloom/firefly.gdshader")
	sm.set_shader_parameter("color", Color(0.95, 0.92, 0.5))
	sm.set_shader_parameter("energy", 5.0)
	q.material = sm
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gp)
	gp.global_position = at
	_flies.append(gp)


func _fireflies() -> void:
	_emitter("FirefliesNear", bed + Vector3(0, 0.7, 0), 50, 9.0, Vector3(4.0, 0.6, 4.0), Vector2(0.045, 0.045), 1.0)
	_emitter("FirefliesTree", tree_base + Vector3(0, 2.2, 0), 90, 10.0, Vector3(10, 2.0, 10), Vector2(0.08, 0.08), 1.3)


# ------------------------------------------------------------------ the Milky Way night sky
func _sky_dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


## World -> the panorama's galactic frame: the core low in the north-north-east, the band arching up through the
## north-west (env-test's _sky_rotation, unchanged).
func _sky_rotation() -> Basis:
	var core := _sky_dir(CORE_AZ, CORE_EL)
	var arch := _sky_dir(ARCH_AZ, ARCH_EL)
	var n := core.cross(arch).normalized()
	var zg := -core
	var yg := (n - zg * n.dot(zg)).normalized()
	var xg := yg.cross(zg)
	return Basis(xg, yg, zg).transposed()


func _night_sky() -> void:
	var pano_path := "res://assets/sky/eso_milky_way/eso0932a_6000x3000.jpg"
	if not ResourceLoader.exists(pano_path) or world.get("_sky_night") == null:
		push_warning("[starfall] no Milky Way panorama: the sanctuary keeps its own night sky")
		return
	var skm := ShaderMaterial.new()
	skm.shader = load("res://shaders/starfall/milky_sky.gdshader")
	skm.set_shader_parameter("pano", load(pano_path))
	skm.set_shader_parameter("sky_rot", _sky_rotation())
	skm.set_shader_parameter("meteor_heading", deg_to_rad(5.0))
	skm.set_shader_parameter("pano_energy", 2.0)
	(world._sky_night as Sky).sky_material = skm
	(world._sky_night as Sky).process_mode = Sky.PROCESS_MODE_INCREMENTAL


# ------------------------------------------------------------------ moonlight on the glade (night only)
var _moon: SpotLight3D


## A soft, cool key from high above the bed: at night the two of them, the grass and the flowers round them read on
## a stream (the sanctuary's own moonlight is far too dim under the canopy). No shadows; off by day.
func _moonlight() -> void:
	_moon = SpotLight3D.new()
	_moon.name = "GladeMoonlight"
	_moon.light_color = Color(0.72, 0.8, 1.0)
	_moon.light_energy = 0.0
	_moon.spot_range = 22.0
	_moon.spot_angle = 32.0
	_moon.spot_attenuation = 0.6
	_moon.shadow_enabled = false
	add_child(_moon)
	var fwd := (bed - tree_base)
	fwd.y = 0.0
	_moon.global_position = bed + fwd.normalized() * 5.0 + Vector3(0, 12.0, 0)
	_moon.look_at(bed + Vector3(0, 0.3, 0), Vector3.FORWARD)


# ------------------------------------------------------------------ the real clock: day green, night blue + glow
func _process(delta: float) -> void:
	_acc += delta
	if _acc < 0.5:
		return
	_acc = 0.0
	_update_light(false)


func _update_light(force: bool) -> void:
	var dl := WorldState.daylight()
	if not force and absf(dl - _dl) < 0.01:
		return
	_dl = dl
	var n := 1.0 - dl                         # 0 by day, 1 at night
	if _grass_mat:
		_grass_mat.set_shader_parameter("base_color", Color(0.05, 0.1, 0.03).lerp(Color(0.015, 0.03, 0.05), n))
		_grass_mat.set_shader_parameter("tip_color", Color(0.3, 0.42, 0.14).lerp(Color(0.07, 0.11, 0.2), n))
		_grass_mat.set_shader_parameter("tip_light", Color(0.55, 0.6, 0.3).lerp(Color(0.22, 0.26, 0.62), n))
		_grass_mat.set_shader_parameter("glow_color", Color(0.45, 0.5, 1.0) * n)
	if _flower_mat:
		_flower_mat.set_shader_parameter("glow_energy", 1.7 * n)
		_flower_mat.set_shader_parameter("petal_color", Color(1.0, 0.98, 0.92).lerp(Color(0.85, 0.9, 1.0), n))
	for sm in _plant_mats:
		sm.set_shader_parameter("petal_glow", float(sm.get_meta("night_glow", 0.0)) * n)
		sm.set_shader_parameter("tint", Color(1, 1, 1).lerp(Color(0.78, 0.86, 0.95), n))
	for sm in _leaf_mats:
		sm.set_shader_parameter("tint", Color(0.9, 0.95, 0.85).lerp(Color(0.55, 0.62, 0.8), n))
	for b in _bark_mats:
		b.albedo_color = Color(0.9, 0.88, 0.86).lerp(Color(0.6, 0.62, 0.75), n)
	for f in _flies:
		f.emitting = n > 0.65
	if _moon:
		_moon.light_energy = 2.4 * smoothstep(0.6, 1.0, n)
		_moon.visible = n > 0.6
