class_name Sanctuary
extends AreaBase
## The Arcane Sanctuary: builds the playable world from imported CC0 assets
## (Poly Haven / ambientCG) + the custom Blender architecture.
## Characters are spawned by main.gd; this node owns terrain, architecture,
## set dressing, light/atmosphere, points of interest and navigation.

const ARCH_PATH := "res://assets/architecture/sanctuary_architecture.glb"
const MODELS := "res://assets/polyhaven/models/"
const DAIS_TOP := 0.6
## Heavy resources preloaded on worker threads by the streaming manager.
const RESOURCES := [
	"res://assets/architecture/sanctuary_architecture.glb",
	"res://assets/trees/broadleaf_tree_near.glb",
	"res://assets/trees/broadleaf_tree_far.glb",
	"res://assets/polyhaven/textures/mossy_rock/mossy_rock_diff_2k.jpg",
	"res://assets/polyhaven/textures/mossy_rock/mossy_rock_nor_gl_2k.jpg",
	"res://assets/polyhaven/textures/monastery_stone_floor/monastery_stone_floor_diff_2k.jpg",
	"res://assets/polyhaven/textures/leafy_grass/leafy_grass_diff_2k.jpg",
	"res://assets/polyhaven/textures/leafy_grass/leafy_grass_nor_gl_2k.jpg",
	"res://assets/polyhaven/models/rock_moss_set_01/rock_moss_set_01_1k.gltf",
	"res://assets/polyhaven/models/rock_moss_set_02/rock_moss_set_02_1k.gltf",
	"res://assets/polyhaven/models/rock_face_01/rock_face_01_1k.gltf",
	"res://assets/polyhaven/models/fern_02/fern_02_1k.gltf",
	"res://assets/polyhaven/models/shrub_02/shrub_02_1k.gltf",
	"res://assets/polyhaven/hdris/nature_reserve_forest/nature_reserve_forest_2k.hdr",
	# sub-area expansion (garden planting, chamber offerings, journal desk)
	"res://assets/polyhaven/models/flower_empodium/flower_empodium_1k.gltf",
	"res://assets/polyhaven/models/flower_gazania/flower_gazania_1k.gltf",
	"res://assets/polyhaven/models/flower_ursinia/flower_ursinia_1k.gltf",
	"res://assets/polyhaven/models/shrub_03/shrub_03_1k.gltf",
	"res://assets/polyhaven/models/brass_vase_01/brass_vase_01_1k.gltf",
	"res://assets/polyhaven/models/ceramic_vase_01/ceramic_vase_01_1k.gltf",
	"res://assets/polyhaven/models/folding_wooden_stool/folding_wooden_stool_1k.gltf",
	"res://assets/wildlife/fox.glb", "res://assets/wildlife/deer.glb", "res://assets/wildlife/stag.glb", "res://assets/wildlife/koi.glb",
]

var mats: SanctuaryMaterials
var terrain: SanctuaryTerrain
var areas := []                # [{id, center(Vector3), radius}]
var fire_lights: Array[OmniLight3D] = []
var _night_nodes: Array[Node3D] = []
var altar_crystal: Node3D
var _scene_cache := {}
var _shape_cache := {}
var _group := "misc"  # perf category for nodes created by the helpers
var altar_books: Array = []
var alchemy: AlchemyTable
var expansion: SanctuaryExpansion   # sub-areas of the mini-region (garden, chamber, watchpoint...)


func build_steps() -> Array:
	# The original build order, split into steps the streaming manager runs within a frame budget.
	if RenderProfile.options.has("no-expansion"):  # A/B measurement of the mini-region expansion only
		return [_step_init, _build_terrain, _build_architecture, _step_rocks, _build_trees, _step_grass, _step_ferns_shrubs,
			_step_deadwood, _step_props, _build_fires_and_lights, _register_points_of_interest, _build_world_links]
	return [_step_init, _build_terrain, _build_architecture, _step_rocks, _build_trees, _step_grass, _step_ferns_shrubs,
		_step_deadwood, _step_props, _build_fires_and_lights, _step_expansion_ritual_gate, _step_expansion_garden,
		_step_expansion_chamber, _step_expansion_watch, _step_expansion_finish, _register_points_of_interest, _build_world_links]


func _step_expansion_ritual_gate() -> void:
	_group = "expansion"
	expansion = SanctuaryExpansion.new(self)
	expansion.build_ritual_and_gate()
	expansion.build_training_targets()


func _step_expansion_garden() -> void:
	expansion.build_garden()


func _step_expansion_chamber() -> void:
	expansion.build_chamber()


func _step_expansion_watch() -> void:
	expansion.build_watchpoint()


func _step_expansion_finish() -> void:
	expansion.build_magic_props()
	expansion.build_alchemy()
	expansion.build_wildlife()
	expansion.finish()
	expansion.set_night(night)


func _step_init() -> void:
	rng.seed = 20261010
	mats = SanctuaryMaterials.new()
	magic_receivers = mats.magic_receivers()
	terrain = SanctuaryTerrain.new()
	nav_aabb = AABB(Vector3(-36, -2, -36), Vector3(90, 12, 82))  # z to +46: includes the Watchpoint


func _step_rocks() -> void:
	_group = "rocks"
	_build_rocks()


func _step_grass() -> void:
	_group = "foliage"
	_build_foliage_part(0)


func _step_ferns_shrubs() -> void:
	_group = "foliage"
	_build_foliage_part(1)


func _step_deadwood() -> void:
	_group = "foliage"
	_build_foliage_part(2)


func _step_props() -> void:
	_group = "props"
	_build_props()


# ------------------------------------------------------------------ environment
func _build_environment() -> void:
	env = Environment.new()
	_sky_day = Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/polyhaven/hdris/nature_reserve_forest/nature_reserve_forest_2k.hdr")
	pano.energy_multiplier = 1.0
	_sky_day.sky_material = pano
	_sky_day.radiance_size = Sky.RADIANCE_SIZE_256
	_sky_night = Sky.new()
	var npano := PanoramaSkyMaterial.new()
	npano.panorama = load("res://assets/polyhaven/hdris/kloppenheim_02/kloppenheim_02_2k.hdr")
	npano.energy_multiplier = 1.0
	_sky_night.sky_material = npano
	_sky_night.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, [0.0, 0.6, 1.0, 1.0, 0.8, 0.5, 0.0][i])
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.25
	env.fog_height = 1.2
	env.adjustment_enabled = true
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.35
	RenderProfile.apply_to_environment(env)
	world_env = WorldEnvironment.new()
	world_env.environment = env
	var cam_attr := CameraAttributesPractical.new()
	world_env.camera_attributes = cam_attr
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if RenderProfile.profile == RenderProfile.ULTRA else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = RenderProfile.get_setting("shadow_distance")
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_volumetric_fog_energy = 1.6
	add_child(sun)


func set_night(v: bool) -> void:
	night = v
	if night:
		env.sky = _sky_night
		env.background_energy_multiplier = 0.9
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 1.6
		env.tonemap_exposure = 1.25
		sun.light_color = Color(0.62, 0.72, 1.0)
		sun.light_energy = 0.32
		sun.rotation_degrees = Vector3(-38, 140, 0)
		env.fog_light_color = Color(0.09, 0.12, 0.2)
		env.fog_density = 0.004
		env.fog_height_density = 0.06
		env.volumetric_fog_albedo = Color(0.55, 0.62, 0.85)
		env.adjustment_saturation = 1.08
		env.adjustment_contrast = 1.06
	else:
		env.sky = _sky_day
		env.background_energy_multiplier = 0.7
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 1.0
		env.tonemap_exposure = 1.0
		# low warm late-afternoon sun from the south-west: long shadows across the dais
		sun.light_color = Color(1.0, 0.84, 0.66)
		sun.light_energy = 2.4
		sun.rotation_degrees = Vector3(-24, -130, 0)
		env.fog_light_color = Color(0.45, 0.55, 0.6)
		env.fog_density = 0.0009
		env.fog_height_density = 0.006
		env.volumetric_fog_albedo = Color(0.85, 0.88, 0.9)
		env.tonemap_exposure = 0.92
		env.adjustment_saturation = 1.06
		env.adjustment_contrast = 1.04
	env.fog_sun_scatter = 0.25
	for l in fire_lights:
		l.light_energy = l.get_meta("base_energy") * (1.7 if night else 1.0)
	for n in _night_nodes:
		n.visible = night
	if expansion:
		expansion.set_night(night)
	RenderProfile.apply_to_environment(env)
	if env.volumetric_fog_enabled and not night:
		env.volumetric_fog_density = 0.0012  # daytime: just enough for sun shafts, no milky wash


# ------------------------------------------------------------------ terrain
func _build_terrain() -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	add_child(body)
	body.add_to_group("cat_terrain")
	var mi := MeshInstance3D.new()
	mi.mesh = terrain.build_mesh()  # also fills terrain.grid
	mi.material_override = mats.terrain
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = terrain.build_collision_shape()
	body.add_child(cs)


# ------------------------------------------------------------------ architecture
func _build_architecture() -> void:
	var arch: Node3D = load(ARCH_PATH).instantiate()
	arch.name = "Architecture"
	add_child(arch)
	arch.add_to_group("cat_architecture")
	for node in arch.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		for s in mi.mesh.get_surface_count():
			var mname := String(mi.mesh.surface_get_material(s).resource_name) if mi.mesh.surface_get_material(s) else ""
			var m: Material = mats.stone
			if mname.begins_with("stone_floor"): m = mats.stone_slab
			elif mname.begins_with("rune_floor"): m = mats.rune_floor
			elif mname.begins_with("gold"): m = mats.gold
			mi.set_surface_override_material(s, m)
		var name_l := String(mi.name).to_lower()
		if name_l.begins_with("ritualdais") or name_l.begins_with("runefloor") or name_l.begins_with("daissteps"):
			continue  # walkable ramp collider below instead of stepped trimesh
		_add_static_collision(mi, mi.mesh.create_trimesh_shape())
	# Walkable dais: a low cone frustum covering the tiers (8° slope), so the
	# character walks up naturally while the visuals keep crisp stepped slabs.
	var ramp := StaticBody3D.new()
	ramp.name = "DaisRamp"
	add_child(ramp)
	var pts := PackedVector3Array()
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(Vector3(cos(a) * 8.6, -0.05, sin(a) * 8.6))
		pts.append(Vector3(cos(a) * 5.0, DAIS_TOP, sin(a) * 5.0))
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = hull
	ramp.add_child(cs)


func _add_static_collision(mi: MeshInstance3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	mi.add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


# ------------------------------------------------------------------ asset helpers
func _scene(id: String) -> Node3D:
	if not _scene_cache.has(id):
		_scene_cache[id] = load(MODELS + id + "/" + id + "_1k.gltf")
	return _scene_cache[id].instantiate()


## Mesh (+ its imported PBR materials) of one named part of a Poly Haven asset.
func _part_mesh(id: String, part: String = "") -> Mesh:
	var key := id + ":" + part
	if not _scene_cache.has(key):
		var root := _scene(id)
		var found: MeshInstance3D = null
		for n in root.find_children("*", "MeshInstance3D", true, false):
			if part == "" or String(n.name).begins_with(part):
				found = n
				break
		_scene_cache[key] = found.mesh
		root.free()
	return _scene_cache[key]


func place_mesh(mesh: Mesh, pos: Vector3, yaw: float, scale_v: Vector3, collide := true, sink := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	mi.add_to_group("cat_" + _group)
	var ground := terrain.fast_height(pos.x, pos.z) if pos.y < -50.0 else pos.y
	mi.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(scale_v), Vector3(pos.x, ground - sink, pos.z))
	if collide:
		if not _shape_cache.has(mesh):
			_shape_cache[mesh] = mesh.create_convex_shape(true, false)  # no simplify pass: much faster on scanned rocks
		_add_static_collision(mi, _shape_cache[mesh])
	return mi


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, -100.0, z)  # y < -50 => snap to terrain in place_mesh


# ------------------------------------------------------------------ rocks
func _build_rocks() -> void:
	var r1 := "rock_moss_set_01"
	var r2 := "rock_moss_set_02"
	# North-east outcrop behind the colonnade: big rock face + mossy companions
	place_mesh(_part_mesh("rock_face_01"), _ground(17.5, -15.0), 2.4, Vector3.ONE * 1.5, true, 0.6)
	place_mesh(_part_mesh(r1, "rock_moss_set_01_rock04"), _ground(13.2, -17.5), 0.7, Vector3.ONE * 1.6, true, 0.3)
	place_mesh(_part_mesh(r2, "rock_moss_set_02_rock11"), _ground(20.5, -10.5), 1.9, Vector3.ONE * 1.4, true, 0.15)
	# West outcrop framing the curved ruin wall
	place_mesh(_part_mesh("rock_face_02"), _ground(-20.0, 4.0), -1.2, Vector3.ONE * 1.8, true, 0.5)
	place_mesh(_part_mesh(r1, "rock_moss_set_01_rock01"), _ground(-18.0, -9.5), 0.3, Vector3.ONE * 1.7, true, 0.3)
	place_mesh(_part_mesh(r1, "rock_moss_set_01_rock05"), _ground(-22.5, -2.0), 2.2, Vector3.ONE * 1.5, true, 0.3)
	place_mesh(_part_mesh(r2, "rock_moss_set_02_rock07"), _ground(-16.5, 9.0), 0.9, Vector3.ONE * 1.3, true, 0.1)
	# Gateway boulders
	place_mesh(_part_mesh("boulder_01"), _ground(-9.0, -26.5), 0.4, Vector3.ONE * 1.4, true, 0.25)
	place_mesh(_part_mesh("namaqualand_boulder_02"), _ground(7.8, -20.5), 2.6, Vector3.ONE * 1.2, true, 0.2)
	place_mesh(_part_mesh(r2, "rock_moss_set_02_rock12"), _ground(-4.0, -26.0), 1.1, Vector3.ONE * 1.1, true, 0.1)
	# South path edge
	place_mesh(_part_mesh(r1, "rock_moss_set_01_rock02"), _ground(5.5, 17.0), 1.3, Vector3.ONE * 1.2, true, 0.3)
	place_mesh(_part_mesh(r2, "rock_moss_set_02_rock10"), _ground(-5.0, 21.0), 2.9, Vector3.ONE * 1.2, true, 0.1)
	place_mesh(_part_mesh(r1, "rock_moss_set_01_rock06"), _ground(-6.5, 26.0), 0.2, Vector3.ONE * 1.4, true, 0.2)
	# Training clearing: a ring of seven standing stones (scanned rocks set upright)
	var tc := SanctuaryTerrain.TRAINING_CENTER
	var parts := ["rock_moss_set_01_rock04", "rock_moss_set_01_rock03", "rock_moss_set_01_rock06", "rock_moss_set_02_rock11",
			"rock_moss_set_01_rock04", "rock_moss_set_02_rock13", "rock_moss_set_01_rock03"]
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		var p := tc + Vector2(cos(a), sin(a)) * 7.2
		var m := _part_mesh(r1 if parts[i].begins_with("rock_moss_set_01") else r2, parts[i])
		var mi := place_mesh(m, _ground(p.x, p.y), a + PI * 0.5, Vector3(0.55, 1.9, 0.55), true, 0.2)
	# Scatter of smaller mossy rocks around the clearing edge
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(16.0, 30.0)
		var p := Vector2(cos(a), sin(a)) * d
		if SanctuaryTerrain.dist_to_paths(p) < 2.5 or absf(d - 14.5) < 1.5 or _blocked(p, 1.5):
			continue
		var set_id := r1 if rng.randf() < 0.5 else r2
		var part := "%s_rock%02d" % [set_id, rng.randi_range(1, 6) if set_id == r1 else rng.randi_range(7, 13)]
		place_mesh(_part_mesh(set_id, part), _ground(p.x, p.y), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.4, 0.9), true, 0.08)


# ------------------------------------------------------------------ trees
func _build_trees() -> void:
	# Two LODs of the same (thinned + decimated) Poly Haven tree: near (≈150k tris) and far (≈44k).
	# Far LOD doubles as the shadow caster for trees close to the clearing.
	var lods := {"near": _tree_meshes("res://assets/trees/broadleaf_tree_near.glb"), "far": _tree_meshes("res://assets/trees/broadleaf_tree_far.glb")}
	var spots: Array[Vector2] = []
	for p in [Vector2(-12.5, -28.5), Vector2(13.5, -25.0), Vector2(-25.0, 13.0), Vector2(25.0, 20.0),
			Vector2(-28.0, -12.0), Vector2(30.0, -9.0), Vector2(10.0, 29.0), Vector2(-12.0, 32.0)]:
		spots.append(p)
	var count := int(18 * RenderProfile.get_setting("foliage_density"))
	var tries := 0
	while spots.size() < 8 + count and tries < 400:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(31.0, 58.0)
		if SanctuaryTerrain.dist_to_paths(p) < 5.0 or p.distance_to(SanctuaryTerrain.TRAINING_CENTER) < 13.0 or _blocked(p, 4.0):
			continue
		var ok := true
		for q in spots:
			if q.distance_to(p) < 9.0:
				ok = false
				break
		if ok:
			spots.append(p)
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.45
	trunk_shape.height = 4.0
	for i in spots.size():
		var p: Vector2 = spots[i]
		var root := Node3D.new()
		root.name = "Tree%d" % i
		add_child(root)
		root.add_to_group("cat_trees")
		var s := rng.randf_range(0.95, 1.3)
		root.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, terrain.fast_height(p.x, p.y) - 0.15, p.y))
		var casts_shadow := p.length() < (22.0 if RenderProfile.profile == RenderProfile.LIVE_OPTIMIZED else 30.0)
		var near_end := 15.0 if RenderProfile.profile == RenderProfile.LIVE_OPTIMIZED else 24.0
		for tm in lods.near:
			root.add_child(_tree_part(tm, 0.0, near_end, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
		for tm in lods.far:
			root.add_child(_tree_part(tm, near_end, 150.0, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF))
			if casts_shadow:
				root.add_child(_tree_part(tm, 0.0, 0.0, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY))
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position.y = 2.0
		body.add_child(cs)
		root.add_child(body)


func _tree_meshes(path: String) -> Array:
	var out := []
	var probe: Node3D = load(path).instantiate()
	for n in probe.find_children("*", "MeshInstance3D", true, false):
		out.append([n.mesh, (n as MeshInstance3D).transform])
	probe.free()
	return out


func _tree_part(tm: Array, vis_begin: float, vis_end: float, shadow: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = tm[0]
	mi.transform = tm[1]
	mi.cast_shadow = shadow
	mi.visibility_range_begin = vis_begin
	mi.visibility_range_end = vis_end
	if vis_end > 0.0:
		mi.visibility_range_begin_margin = 2.0
		mi.visibility_range_end_margin = 2.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


# ------------------------------------------------------------------ foliage
func _multimesh(mesh: Mesh, xforms: Array[Transform3D], vis_end: float, colors: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.add_to_group("cat_" + _group)
	mmi.visibility_range_end = vis_end
	mmi.visibility_range_end_margin = 4.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return mmi


func _blocked(p: Vector2, margin := 0.0) -> bool:
	var d := p.length()
	if d < 8.4 + margin: return true                                   # dais
	if absf(d - 9.2) < 1.2 + margin and d < 10.6: return true          # colonnade ring footing
	if absf(d - 14.5) < 0.9 + margin and absf(p.x) > 8.0: return true  # ruin walls
	if absf(p.x) < 6.5 and absf(p.y + 17.0) < 1.6 + margin: return true # arch
	if SanctuaryTerrain.dist_to_paths(p) < 1.3 + margin: return true
	if p.distance_to(SanctuaryTerrain.GARDEN) < 7.5 + margin: return true   # garden keeps its own planting
	if p.distance_to(SanctuaryTerrain.CHAMBER) < 6.5 + margin: return true
	if p.distance_to(SanctuaryTerrain.WATCH) < 5.0 + margin: return true
	return false


func _build_foliage_part(part_i: int) -> void:
	var density: float = RenderProfile.get_setting("foliage_density")
	var tc := SanctuaryTerrain.TRAINING_CENTER
	if part_i == 0:
		_foliage_grass(density, tc)
	elif part_i == 1:
		_foliage_ferns_shrubs(density, tc)
	else:
		_foliage_deadwood()


func _foliage_grass(density: float, tc: Vector2) -> void:

	# Grass clumps (geometry blades) across the clearing and training area
	var grass_mesh := _make_grass_clump_mesh()
	grass_mesh.surface_set_material(0, mats.grass)
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	var n := int(11000 * density)
	for i in n:
		var p: Vector2
		if i % 5 == 0:
			p = tc + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 12.0
		else:
			p = Vector2.from_angle(rng.randf() * TAU) * lerpf(8.6, 26.0, sqrt(rng.randf()))
		if _blocked(p, -0.2):
			continue
		var y := terrain.fast_height(p.x, p.y)
		var s := rng.randf_range(0.7, 1.35)
		xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(p.x, y - 0.02, p.y)))
		cols.append(Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.8, 1.0)))
	_group = "grass"
	_multimesh(grass_mesh, xf, 30.0, cols).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _foliage_ferns_shrubs(density: float, tc: Vector2) -> void:

	_group = "foliage"
	# Ferns hugging architecture bases, rocks and the forest edge
	var fern_parts := ["fern_02_a", "fern_02_b", "fern_02_c", "fern_02_d"]
	for part in fern_parts:
		var fx: Array[Transform3D] = []
		for i in int(70 * density):
			var p: Vector2
			match i % 3:
				0: p = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.4, 11.5)   # outside colonnade
				1: p = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(13.0, 16.5)   # along ruin walls
				_: p = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 34.0)   # forest edge
			if _blocked(p):
				continue
			var s := rng.randf_range(0.9, 1.7)
			fx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, terrain.fast_height(p.x, p.y) - 0.03, p.y)))
		_multimesh(_part_mesh("fern_02", part), fx, 60.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Shrubs: denser toward the forest, a few as accents near ruins
	var shrub_parts := [["shrub_02", "shrub_02_a"], ["shrub_02", "shrub_02_b"], ["shrub_02", "shrub_02_c"], ["shrub_02", "shrub_02_d"]]
	for sp in shrub_parts:
		var sx: Array[Transform3D] = []
		for i in int(26 * density):
			var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(16.0, 45.0)
			if _blocked(p, 1.0) or p.distance_to(tc) < 9.0:
				continue
			var s := rng.randf_range(0.8, 1.5)
			sx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, terrain.fast_height(p.x, p.y) - 0.05, p.y)))
		_multimesh(_part_mesh(sp[0], sp[1]), sx, 90.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Small undergrowth flowers/weeds near the dais edge (shrub_03 sprigs)
	for part in ["shrub_03_a", "shrub_03_b", "shrub_03_c", "shrub_03_d"]:
		var wx: Array[Transform3D] = []
		for i in int(90 * density):
			var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8.5, 22.0)
			if _blocked(p):
				continue
			var s := rng.randf_range(1.0, 1.8)
			wx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, terrain.fast_height(p.x, p.y), p.y)))
		_multimesh(_part_mesh("shrub_03", part), wx, 35.0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF



func _foliage_deadwood() -> void:
	# Dead wood, stumps and roots in the forest margin
	place_mesh(_part_mesh("dead_tree_trunk"), _ground(-15.0, 19.0), 0.6, Vector3.ONE * 1.3, true, 0.05)
	place_mesh(_part_mesh("tree_stump_01"), _ground(18.0, 21.0), 1.0, Vector3.ONE * 1.1, true, 0.05)
	place_mesh(_part_mesh("tree_stump_02"), _ground(-24.0, -18.0), 2.0, Vector3.ONE * 1.2, true, 0.05)
	place_mesh(_part_mesh("root_cluster_01"), _ground(23.0, -19.0), 0.8, Vector3.ONE * 1.0, false, 0.05)
	for i in 6:
		var p := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(18.0, 32.0)
		if not _blocked(p, 1.0):
			place_mesh(_part_mesh("dry_branches_medium_01", "dry_branches_medium_01_" + ["a", "b", "c"][i % 3]), _ground(p.x, p.y), rng.randf() * TAU, Vector3.ONE * 1.2, false, 0.02)


## Procedural clump of curved, tapered grass blades (UV.y = 0 root → 1 tip).
func _make_grass_clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var segs := 4
	for b in 7:
		var base := Vector2.from_angle(r.randf() * TAU) * r.randf() * 0.12
		var dir := Vector2.from_angle(r.randf() * TAU)
		var h := r.randf_range(0.22, 0.5)
		var w := r.randf_range(0.018, 0.03)
		var lean := r.randf_range(0.05, 0.22)
		var side := Vector3(-dir.y, 0, dir.x)
		var verts := []
		for s in segs + 1:
			var t := float(s) / segs
			var c := Vector3(base.x + dir.x * lean * t * t, h * t, base.y + dir.y * lean * t * t)
			var ww := w * (1.0 - t * 0.92)
			verts.append([c - side * ww, c + side * ww, t])
		for s in segs:
			var a0: Vector3 = verts[s][0]; var a1: Vector3 = verts[s][1]
			var b0: Vector3 = verts[s + 1][0]; var b1: Vector3 = verts[s + 1][1]
			var n := (b0 - a0).cross(a1 - a0).normalized()
			n = (n + Vector3.UP * 0.6).normalized()
			for v in [[a0, verts[s][2]], [b0, verts[s + 1][2]], [a1, verts[s][2]], [a1, verts[s][2]], [b0, verts[s + 1][2]], [b1, verts[s + 1][2]]]:
				st.set_normal(n)
				st.set_uv(Vector2(0.5, v[1]))
				st.add_vertex(v[0])
	return st.commit()


# ------------------------------------------------------------------ props
func _build_props() -> void:
	var altar_top := DAIS_TOP + 0.44 + 0.74 + 0.19
	var altar := Vector3(0, altar_top, -2.6)
	# Two books on the spell pedestal
	var book := _part_mesh("book_encyclopedia_set_01", "book_encyclopedia_set_01_book03")
	var b1 := MeshInstance3D.new(); b1.mesh = book; add_child(b1)
	b1.transform = Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.4), altar + Vector3(-0.15, 0.03, 0.12))
	var b2 := MeshInstance3D.new(); b2.mesh = _part_mesh("book_encyclopedia_set_01", "book_encyclopedia_set_01_book07"); add_child(b2)
	altar_books = [b1, b2]
	b2.transform = Transform3D(Basis(Vector3.UP, -0.2) * Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3.ONE * 1.4), altar + Vector3(-0.12, 0.08, 0.1))
	# Brass candle holders flanking the altar top
	var holder := _part_mesh("brass_candleholders", "brass_candleholder_01")
	for sx in [-0.42, 0.42]:
		var h := MeshInstance3D.new(); h.mesh = holder; add_child(h)
		h.position = altar + Vector3(sx, 0.0, -0.18)
		_add_flame(h.position + Vector3(0, 0.39, 0), 0.35, 0.35, false)
	# Floating crystal focus above the altar (spell-learning focus)
	altar_crystal = Node3D.new()
	altar_crystal.name = "AltarCrystal"
	add_child(altar_crystal)
	altar_crystal.position = altar + Vector3(0.12, 0.62, -0.05)
	var cm := MeshInstance3D.new()
	cm.mesh = _make_crystal_mesh()
	cm.material_override = mats.crystal
	altar_crystal.add_child(cm)
	var cl := OmniLight3D.new()
	cl.light_color = Color(0.45, 0.65, 1.0)
	cl.light_energy = 0.9
	cl.omni_range = 4.5
	cl.light_volumetric_fog_energy = 0.4
	altar_crystal.add_child(cl)
	# Statue watching over the gateway
	var statue := place_mesh(_part_mesh("gothic_statue"), Vector3(-5.2, 0.0, -15.6), 0.25, Vector3.ONE * 1.25, true)
	statue.position.y = terrain.height(-5.2, -15.6) - 0.05
	# Lanterns on the ruin walls (lit at night)
	var lantern := _part_mesh("Lantern_01", "Lantern_01")
	var glass := _part_mesh("Lantern_01", "Lantern_01_glass")
	for p in [Vector3(-13.9, 0.0, -4.0), Vector3(13.6, 0.0, -7.5), Vector3(-1.9, 0.0, -16.2), Vector3(1.9, 0.0, -16.2)]:
		var lp := Vector3(p.x, terrain.height(p.x, p.z), p.z)
		var l := MeshInstance3D.new(); l.mesh = lantern; add_child(l); l.position = lp; l.scale = Vector3.ONE * 1.4
		var g := MeshInstance3D.new(); g.mesh = glass; add_child(g); g.position = lp; g.scale = Vector3.ONE * 1.4
		_add_flame(lp + Vector3(0, 0.16, 0), 0.6, 0.12, true)


func _make_crystal_mesh() -> ArrayMesh:
	# elongated, slightly irregular hexagonal bipyramid
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 0.34, 0)
	var bot := Vector3(0, -0.22, 0)
	var ring := []
	for i in 6:
		var a := TAU * i / 6.0
		ring.append(Vector3(cos(a) * (0.085 + 0.015 * (i % 2)), 0.02 * (i % 3), sin(a) * (0.085 + 0.015 * (i % 2))))
	for i in 6:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 6]
		for tri in [[top, b, a], [bot, a, b]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()


func _add_flame(pos: Vector3, energy: float, rng_m: float, night_boost: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.32)
	l.light_energy = energy
	l.set_meta("base_energy", energy)
	l.omni_range = 2.5 + rng_m * 6.0
	l.omni_attenuation = 1.4
	l.position = pos
	l.light_volumetric_fog_energy = 0.6
	add_child(l)
	fire_lights.append(l)
	var flame := MeshInstance3D.new()
	var q := SphereMesh.new()
	q.radius = 0.012
	q.height = 0.045
	flame.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.7, 0.35)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.6, 0.25)
	fm.emission_energy_multiplier = 8.0
	flame.material_override = fm
	flame.position = pos
	add_child(flame)


# ------------------------------------------------------------------ braziers + magic lights
func _build_fires_and_lights() -> void:
	var names := ["brazier_ne", "brazier_nw", "brazier_sw", "brazier_se"]
	var labels := ["north-east brazier", "north-west brazier", "south-west brazier", "south-east brazier"]
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		# Blender (x, y) -> Godot (x, -z)
		var pos := Vector3(6.35 * cos(a), 0.4 + 0.82, -6.35 * sin(a))
		# each brazier is a ReactiveElement: its fire answers wind / water / fire / arcane magic
		var br := Brazier.new()
		br.name = names[k]
		br.position = pos
		add_child(br)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.26)
		l.light_energy = 1.6
		l.omni_range = 7.0
		l.shadow_enabled = false  # omni cube shadows re-render the scene 6x per light; too costly on the iGPU
		l.position = Vector3(0, 0.35, 0)
		l.light_volumetric_fog_energy = 1.0
		br.add_child(l)
		var fp := _make_fire_particles(Vector3.ZERO)
		br.add_child(fp)
		br.setup(names[k], "the " + labels[k], fp, l)


func _make_fire_particles(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.9
	p.position = pos
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.16
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3)); c.add_point(Vector2(0.25, 1.0)); c.add_point(Vector2(1, 0.0))
	curve.curve = c
	pm.scale_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.4)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/magic/energy_mote.gdshader")
	sm.set_shader_parameter("hdr_boost", 4.0)
	quad.material = sm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
	return p


# ------------------------------------------------------------------ semantics for the AI bridge
func _register_points_of_interest() -> void:
	var tc := SanctuaryTerrain.TRAINING_CENTER
	var poi := {
		"ritual_circle": [Vector3(0, DAIS_TOP, 0), "Engraved arcane circle at the centre of the dais", 2.5],
		"spell_altar": [Vector3(0, DAIS_TOP, -1.35), "Octagonal spell-learning pedestal with books and a floating crystal", 1.0],
		"north_arch": [Vector3(0, 0, -14.5), "Ancient voussoir arch gateway to the northern forest", 2.0],
		"west_ruins": [Vector3(-11.5, 0, -1.0), "Curved ruined wall with a mossy rock outcrop", 2.0],
		"east_ruins": [Vector3(11.5, 0, -5.0), "Ruined wall and the north-east rock face", 2.0],
		"south_path": [Vector3(0.8, 0, 14.0), "Stone-lined path leading south into the forest", 2.0],
		"training_clearing": [Vector3(tc.x, 0, tc.y), "Ring of standing stones reserved for training with a mentor", 3.0],
		"brazier_ne": [Vector3(4.2, DAIS_TOP, -4.2), "Burning stone brazier", 1.2],
		"gothic_statue": [Vector3(-4.5, 0, -14.2), "Weathered statue guarding the gateway", 1.5],
	}
	for id in poi:
		var p: Vector3 = poi[id][0]
		if p.y == 0.0:
			p.y = terrain.height(p.x, p.z)
		points_of_interest[id] = {"position": p, "description": poi[id][1], "interact_radius": poi[id][2]}
	areas = [
		{"id": "spell_altar", "center": Vector3(0, 0, -2.6), "radius": 1.9},
		{"id": "ritual_platform", "center": Vector3.ZERO, "radius": 7.8},
		{"id": "colonnade", "center": Vector3.ZERO, "radius": 11.0},
		{"id": "north_arch", "center": Vector3(0, 0, -17), "radius": 5.0},
		{"id": "training_clearing", "center": Vector3(tc.x, 0, tc.y), "radius": 10.0},
		{"id": "sanctuary_clearing", "center": Vector3.ZERO, "radius": 26.0},
	]


## Which Sanctuary sub-area (data/sanctuary.json) contains p — nearest centre within its radius, else "".
func sub_area_at(p: Vector3) -> String:
	var best := ""
	var best_d := 1e9
	var subs: Dictionary = WorldState.sanctuary.get("sub_areas", {})
	for id in subs:
		var c: Array = subs[id].center
		var d := Vector2(p.x - c[0], p.z - c[2]).length()
		if d <= float(subs[id].radius) and d / float(subs[id].radius) < best_d:
			best_d = d / float(subs[id].radius)
			best = id
	return best


func ground_at(x: float, z: float) -> float:
	return terrain.fast_height(x, z)


func area_at(p: Vector3) -> String:
	for a in areas:
		if Vector2(p.x, p.z).distance_to(Vector2(a.center.x, a.center.z)) <= a.radius:
			return a.id
	return "forest"


func spawn_point(id: String) -> Transform3D:
	match id:
		"companion":
			var tc := SanctuaryTerrain.TRAINING_CENTER
			return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(tc.x - 2.0, terrain.height(tc.x - 2.0, tc.y), tc.y))
		_:
			if gates.has(id):
				return gates[id].arrive
			return Transform3D(Basis.IDENTITY, Vector3(0, DAIS_TOP + 0.05, 1.6))  # facing north, toward the altar


func set_magic_bounce(pos: Vector3, strength: float, color: Color) -> void:
	for m in mats.magic_receivers():
		m.set_shader_parameter("magic_pos", pos)
		m.set_shader_parameter("magic_strength", strength)
		m.set_shader_parameter("magic_color", color)


func set_rune_charge(charge: float, reveal: float) -> void:
	mats.rune_floor.set_shader_parameter("charge", charge)
	mats.rune_floor.set_shader_parameter("reveal", reveal)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in fire_lights.size():
		var l := fire_lights[i]
		var base: float = l.get_meta("base_energy") * (1.7 if night else 1.0)
		l.light_energy = base * (0.86 + 0.1 * sin(t * 11.0 + i * 1.7) + 0.06 * sin(t * 23.0 + i))
	if expansion:
		expansion.process(t)
	if altar_crystal:
		altar_crystal.rotation.y = t * 0.4
		altar_crystal.position.y = DAIS_TOP + 0.44 + 0.74 + 0.19 + 0.62 + sin(t * 1.3) * 0.04


# ------------------------------------------------------------------ world links (streaming): locations, routes, activities
func _build_world_links() -> void:
	var tc := SanctuaryTerrain.TRAINING_CENTER
	var h := func(x: float, z: float) -> float: return terrain.height(x, z)
	add_location("ritual_sanctuary", Vector3(0, 0, -2), 17.0, Vector3(0, DAIS_TOP, 0.0))
	add_location("mage_training_grounds", Vector3(tc.x, 0, tc.y), 12.0, Vector3(tc.x, h.call(tc.x, tc.y), tc.y))
	var stone := mats.stone

	# North: the forest path continues beyond the arch into the Whispering Woods (Milestone K).
	add_gate("whispering_woods", Vector3(1.0, h.call(1.0, -33.0), -33.0), Vector3(0.8, h.call(0.8, -27.0) + 0.05, -27.0), PI, 2.6)
	var post := Kit.block(self, Vector3(0.18, 1.7, 0.18), Kit.xf(Vector3(3.2, h.call(3.2, -31.0) + 0.85, -31.0)), Kit.uvmat("dark_wooden_planks"), true, 0.02)
	Kit.block(self, Vector3(1.1, 0.28, 0.06), Kit.xf(Vector3(3.2, h.call(3.2, -31.0) + 1.45, -31.0), -0.3), Kit.uvmat("dark_wooden_planks"), false, 0.01)

	# South-west: a stone crypt over the stairway down to the Ancient Spell Library.
	var cx := -10.5
	var cz := 12.5
	var gy: float = h.call(cx, cz)
	Kit.block(self, Vector3(3.6, 0.3, 4.2), Kit.xf(Vector3(cx, gy + 0.05, cz)), stone)
	for sx in [-1.0, 1.0]:
		Kit.block(self, Vector3(0.5, 2.6, 4.0), Kit.xf(Vector3(cx + sx * 1.5, gy + 1.45, cz)), stone)
	Kit.block(self, Vector3(3.6, 0.5, 0.5), Kit.xf(Vector3(cx, gy + 2.9, cz + 1.75)), stone)
	Kit.block(self, Vector3(3.6, 2.6, 0.5), Kit.xf(Vector3(cx, gy + 1.45, cz - 1.75)), stone)
	var roof := Kit.mesh_node(self, Kit.gable_roof(3.6, 4.2, 1.1, 0.25, 0.18), Kit.uvmat("castle_wall_slates", "1k", Vector2(0.8, 0.8)), Kit.xf(Vector3(cx, gy + 3.15, cz), PI * 0.5))
	Kit.mesh_node(self, Kit.box_mesh(Vector3(2.4, 2.4, 3.0), 0.01), Kit.emissive(Color(0.01, 0.012, 0.02), 0.0), Kit.xf(Vector3(cx, gy + 1.3, cz - 0.2)), false)
	for k in 5:  # visible steps descending into the dark
		Kit.mesh_node(self, Kit.box_mesh(Vector3(2.2, 0.18, 0.5), 0.02), stone, Kit.xf(Vector3(cx, gy + 0.18 - k * 0.2, cz + 1.2 - k * 0.45)), false)
	Kit.omni(self, Vector3(cx, gy + 2.2, cz + 2.2), Color(0.5, 0.6, 1.0), 0.6, 4.0)
	add_gate("arcane_library", Vector3(cx, gy, cz + 0.6), Vector3(cx + 0.2, gy + 0.05, cz + 4.2), PI, 1.3)

	# East: the trail past the training stones to the Mentor's Tower.
	add_gate("mentor_tower", Vector3(45.0, h.call(45.0, 18.8), 18.8), Vector3(39.0, h.call(39.0, 16.2) + 0.05, 16.2), atan2(13.0, 12.0), 2.4)
	Kit.block(self, Vector3(0.18, 1.7, 0.18), Kit.xf(Vector3(41.0, h.call(41.0, 15.2) + 0.85, 15.2)), Kit.uvmat("dark_wooden_planks"), true, 0.02)
	Kit.block(self, Vector3(1.1, 0.28, 0.06), Kit.xf(Vector3(41.0, h.call(41.0, 15.2) + 1.45, 15.2), 0.4), Kit.uvmat("dark_wooden_planks"), false, 0.01)

	# South-west meadow: a ley-line portal (the only magical route, linking the two schools of magic).
	var px := -12.0
	var pz := 23.0
	var py: float = h.call(px, pz)
	for sx in [-1.0, 1.0]:
		Kit.block(self, Vector3(0.7, 3.6, 0.7), Kit.xf(Vector3(px + sx * 1.6, py + 1.75, pz), 0.0), stone)
	Kit.block(self, Vector3(4.2, 0.6, 0.8), Kit.xf(Vector3(px, py + 3.8, pz)), stone)
	var portal := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 3.4)
	portal.mesh = q
	var pm := ShaderMaterial.new()
	pm.shader = load("res://shaders/magic/sigil.gdshader")
	pm.set_shader_parameter("sides", 7)
	pm.set_shader_parameter("color", Color(0.55, 0.45, 1.0))
	pm.set_shader_parameter("intensity", 1.3)
	pm.set_shader_parameter("spin", 0.25)
	portal.material_override = pm
	portal.position = Vector3(px, py + 1.75, pz)
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(portal)
	Kit.omni(self, Vector3(px, py + 1.8, pz + 0.8), Color(0.6, 0.5, 1.0), 1.0, 5.0)
	add_gate("academy", Vector3(px, py, pz), Vector3(px, py + 0.05, pz - 3.0), 0.0, 1.2)

	# Activities
	var tome := add_interactable(Interactable.make("altar_spellbook", "Study the spellbook on the altar", "study", "ritual_sanctuary",
		Vector3(0, DAIS_TOP, -1.9), {"knowledge": {"lore:arcane_orb_theory": 1}, "skills": {"arcane_orb": 0.1}}, "", 4.0))
	tome.radius = 1.6
	tome.kind = "study"
	tome.book_id = "liber_orbis"
	tome.effects = {"skills": {"arcane_orb": 0.05}}
	var altar_top := DAIS_TOP + 0.44 + 0.74 + 0.19
	tome.book_xf = Transform3D(Basis.IDENTITY, Vector3(0, altar_top + 0.03, -2.45))
	tome.book_props = altar_books
	tome.stand_point = Vector3(0, DAIS_TOP, -1.45)
	tome.face_point = Vector3(0, altar_top, -2.45)
	add_interactable(Interactable.make("ritual_circle_attune", "Attune to the ritual circle", "meditate", "ritual_sanctuary",
		Vector3(0, DAIS_TOP, 0.5), {"skills": {"arcane_orb": 0.15}, "knowledge": {"attuned:ritual_circle": 1}}, "spell_casting", 4.2)).radius = 2.6
	interactables.ritual_circle_attune.kind = "practice"
	interactables.ritual_circle_attune.lore_id = "scroll_first_circle"
	add_interactable(Interactable.make("training_stones_practice", "Practice strikes at the standing stones", "practice", "mage_training_grounds",
		Vector3(tc.x, h.call(tc.x, tc.y), tc.y), {"skills": {"arcane_orb": 0.25}}, "magic_attack_1h", 2.3)).radius = 3.5
	interactables.training_stones_practice.kind = "practice"
	interactables.training_stones_practice.lore_id = "training_ledger"
	add_interactable(Interactable.make("statue_inspect", "Inspect the weathered gate statue", "inspect", "ritual_sanctuary",
		Vector3(-4.4, h.call(-4.4, -14.0), -14.0), {"knowledge": {"lore:gate_guardian": 1}}, "look_around", 3.0)).radius = 2.0
	interactables.statue_inspect.kind = "inspect"
