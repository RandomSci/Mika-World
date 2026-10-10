class_name AreaBase
extends Node3D
## Base for every streamed area (a scene holding one or more registry locations).
## Subclasses override `build_steps()` (small callables executed a few per frame during activation),
## `env_preset()` and the static RESOURCES list (heavy textures/models preloaded on worker threads).

signal navigation_ready


var area_id := ""
var info := {}
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var night := false
var outdoor := true
var points_of_interest := {}   # id -> {position, description, interact_radius, location}
var zones: Array = []          # [{id, location, center, radius}]
var gates := {}                # neighbour_area -> {position, arrive, radius, label, trigger}
var interactables := {}        # id -> Interactable
var visible_landmarks: Array = []  # [{id, position}] actually rendered in this area's vista
var nav_region: NavigationRegion3D
var nav_aabb := AABB(Vector3(-45, -10, -45), Vector3(90, 40, 90))
var nav_agent_climb := 0.25
var magic_receivers: Array = []
var rng := RandomNumberGenerator.new()
var _sky_day: Sky
var _sky_night: Sky
var _preset := {}


func build_steps() -> Array:
	return []


func env_preset() -> Dictionary:
	return {}


# ------------------------------------------------------------------ activation (driven by the streaming manager)
func setup(id: String) -> void:
	area_id = id
	info = WorldState.areas[id]
	outdoor = not info.get("interior", false)
	rng.seed = hash(id)  # deterministic: revisits rebuild exactly the same world


func activate_steps() -> Array:
	var steps: Array = [_build_environment]
	steps.append_array(build_steps())
	if outdoor:
		steps.append(func(): Vista.build(self))
	steps.append(func(): set_night(WorldState.night))
	steps.append(finalize_collisions)
	return steps


## Solid-looking props must block movement and navigation (physics_test audit). Many props were
## placed as visuals only; before the nav bake, give every reachable solid prop a collider:
## Poly Haven furniture/containers/statues get their (cached) convex hull, shrubs and crystal
## clusters a cylinder. Walkable decals, foliage, water, magic and gate/portal visuals are skipped.
const SOLID_PROPS := ["Barrel_01", "wooden_barrels_01", "wooden_crate_01", "planter_box_01", "potted_plant_01", "gothic_statue",
	"treasure_chest", "stone_fire_pit", "GothicCabinet_01", "bench_vice_01", "wooden_bucket_01", "wicker_basket_01", "brass_vase_01",
	"ceramic_vase_01", "large_castle_door", "tree_stump", "dead_tree_trunk", "root_cluster_01"]
const CYLINDER_PROPS := ["shrub_02", "shrub_03"]
static var _solid_shape_cache := {}


func finalize_collisions() -> void:
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 0.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	var added := 0
	for n in find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n
		var mesh: Mesh = null
		var xforms: Array[Transform3D] = []
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
			xforms.append(gi.global_transform)
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			var mm := (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			for i in mm.instance_count:
				xforms.append(gi.global_transform * mm.get_instance_transform(i))
		if mesh == null or not mesh is ArrayMesh:
			continue
		var key := String(mesh.resource_name)
		var mat = gi.material_override
		var crystal := mat is ShaderMaterial and (mat as ShaderMaterial).shader and String((mat as ShaderMaterial).shader.resource_path).ends_with("crystal.gdshader")
		var kind := ""
		for p in SOLID_PROPS:
			if key.begins_with(p):
				kind = "hull"
		for p in CYLINDER_PROPS:
			if key.begins_with(p):
				kind = "cyl"
		if crystal:
			kind = "cyl"
		var stone_shader := mat is ShaderMaterial and (mat as ShaderMaterial).shader and String((mat as ShaderMaterial).shader.resource_path).contains("stone_triplanar")
		if kind == "" and stone_shader and gi is MeshInstance3D:
			kind = "box"  # free-standing stone posts / plinths / blocks
		if kind == "":
			continue
		var maabb := mesh.get_aabb()
		for xf in xforms:
			var aabb: AABB = xf * maabb
			if aabb.size.y < 0.45 or maxf(aabb.size.x, aabb.size.z) > 6.0:
				continue
			q.transform = Transform3D(Basis.IDENTITY, aabb.get_center())
			if not space.intersect_shape(q, 1).is_empty():
				continue  # already solid (placed with collision)
			if _near_gate(aabb.get_center()):
				continue  # doors/portals at routes are travel triggers, walked into on purpose
			if kind == "box":
				if maxf(aabb.size.x, aabb.size.z) > 2.6 or aabb.size.y > 4.0:
					continue  # big architecture is authored with its own collision (arches must stay open)
				var gq := PhysicsRayQueryParameters3D.create(aabb.get_center() + Vector3(0, 0.1, 0), aabb.get_center() - Vector3(0, 30, 0))
				var gh := space.intersect_ray(gq)
				if gh.is_empty() or aabb.position.y > (gh.position as Vector3).y + 0.35:
					continue  # not standing on the ground (wall-mounted, roof ornaments)
			var body := StaticBody3D.new()
			body.name = "AutoCollider"
			var cs := CollisionShape3D.new()
			if kind == "box":
				var bs := BoxShape3D.new()
				bs.size = maabb.size
				cs.shape = bs
				body.transform = xf * Transform3D(Basis.IDENTITY, maabb.get_center())
			elif kind == "hull":
				if not _solid_shape_cache.has(mesh):
					_solid_shape_cache[mesh] = mesh.create_convex_shape(true, true)
				cs.shape = _solid_shape_cache[mesh]
				body.transform = xf
			else:
				var cyl := CylinderShape3D.new()
				cyl.radius = clampf(minf(aabb.size.x, aabb.size.z) * 0.32, 0.12, 0.7)
				cyl.height = minf(aabb.size.y, 2.0)
				cs.shape = cyl
				body.position = Vector3(aabb.get_center().x, aabb.position.y + cyl.height * 0.5, aabb.get_center().z)
			body.add_child(cs)
			add_child(body)
			added += 1
	if added > 0:
		print("[area] %s: finalize_collisions added %d colliders to solid props" % [area_id, added])


func _near_gate(p: Vector3) -> bool:
	for g in gates.values():
		if Vector2(p.x - g.position.x, p.z - g.position.z).length() < g.radius + 1.5:
			return true
	return false


static func clear_collision_cache() -> void:
	_solid_shape_cache.clear()


func bake_navigation() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = nav_agent_climb
	nm.agent_max_slope = 30.0  # keep nav well inside the controller's 46° floor limit (rounded rock flanks)
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.filter_baking_aabb = nav_aabb
	add_child(nav_region)
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	var done := [false]
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func(): done[0] = true)
	while not done[0]:
		await get_tree().process_frame
	nav_region.navigation_mesh = nm
	# let the navigation map sync before anyone queries it
	await get_tree().physics_frame
	await get_tree().physics_frame
	navigation_ready.emit()


# ------------------------------------------------------------------ environment presets
func _build_environment() -> void:
	_preset = env_preset()
	env = Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, [0.0, 0.6, 1.0, 1.0, 0.8, 0.5, 0.0][i])
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.adjustment_enabled = true
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 64.0
	env.volumetric_fog_ambient_inject = 0.3
	if outdoor:
		_sky_day = _sky(_preset.get("sky_day", "res://assets/polyhaven/hdris/nature_reserve_forest/nature_reserve_forest_2k.hdr"))
		_sky_night = _sky(_preset.get("sky_night", "res://assets/polyhaven/hdris/kloppenheim_02/kloppenheim_02_2k.hdr"))
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = _preset.get("bg", Color(0.01, 0.012, 0.018))
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = _preset.get("sun_shadows", true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = RenderProfile.get_setting("shadow_distance")
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func _sky(path: String) -> Sky:
	var s := Sky.new()
	var p := PanoramaSkyMaterial.new()
	p.panorama = load(path)
	s.sky_material = p
	s.radiance_size = Sky.RADIANCE_SIZE_128
	return s


func set_night(v: bool) -> void:
	night = v
	var key := "night" if v else "day"
	var p: Dictionary = _preset.get(key, {})
	if outdoor:
		env.sky = _sky_night if v else _sky_day
		env.background_energy_multiplier = p.get("bg_energy", 0.9 if v else 0.75)
		env.ambient_light_energy = p.get("ambient", 1.6 if v else 1.0)
	else:
		env.ambient_light_color = p.get("ambient_color", Color(0.25, 0.3, 0.4))
		env.ambient_light_energy = p.get("ambient", 0.6)
	env.tonemap_exposure = p.get("exposure", 1.2 if v else 0.95)
	sun.light_color = p.get("sun_color", Color(0.62, 0.72, 1.0) if v else Color(1.0, 0.86, 0.68))
	sun.light_energy = p.get("sun_energy", 0.3 if v else 2.3)
	sun.rotation_degrees = p.get("sun_rot", Vector3(-38, 140, 0) if v else Vector3(-30, -130, 0))
	sun.visible = sun.light_energy > 0.0
	env.fog_light_color = p.get("fog_color", Color(0.09, 0.12, 0.2) if v else Color(0.5, 0.58, 0.66))
	env.fog_density = p.get("fog", 0.004 if v else 0.0012)
	env.fog_height_density = p.get("fog_height", 0.0)
	env.fog_sky_affect = p.get("fog_sky", 0.15)
	env.adjustment_saturation = p.get("saturation", 1.06)
	env.adjustment_contrast = p.get("contrast", 1.04)
	env.volumetric_fog_albedo = p.get("vol_albedo", Color(0.85, 0.88, 0.92))
	RenderProfile.apply_to_environment(env)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = p.get("vol_fog", 0.002)
	for n in get_tree().get_nodes_in_group("night_lights_" + str(get_instance_id())):
		n.visible = v
	for n in get_tree().get_nodes_in_group("day_only_" + str(get_instance_id())):
		n.visible = not v


## Nodes visible only at night (window glows, lanterns) — tracked per area instance.
func night_only(n: Node3D) -> Node3D:
	n.add_to_group("night_lights_" + str(get_instance_id()))
	n.visible = night
	return n


# ------------------------------------------------------------------ semantics
func add_location(location_id: String, center: Vector3, radius: float, poi: Vector3, desc := "") -> void:
	zones.append({"id": location_id, "location": location_id, "center": center, "radius": radius})
	points_of_interest[location_id] = {"position": poi, "description": desc if desc != "" else WorldState.locations[location_id].description,
		"interact_radius": 2.5, "location": location_id}


func add_poi(id: String, pos: Vector3, desc: String, location_id: String, radius := 1.5) -> void:
	points_of_interest[id] = {"position": pos, "description": desc, "interact_radius": radius, "location": location_id}


## A physical route to a neighbouring area: walking into `pos` (radius) starts travel;
## arrivals from that neighbour appear at `arrive` facing `arrive_yaw` (away from the gate).
func add_gate(neighbour: String, pos: Vector3, arrive: Vector3, arrive_yaw: float, radius := 2.2) -> void:
	var route: String = WorldState.adjacency.get(area_id, {}).get(neighbour, "route")
	var trig := Area3D.new()
	trig.name = "Gate_" + neighbour
	trig.position = pos
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	cs.shape = sp
	trig.add_child(cs)
	trig.monitorable = false
	add_child(trig)
	gates[neighbour] = {"position": pos, "arrive": Transform3D(Basis(Vector3.UP, arrive_yaw), arrive), "radius": radius, "label": route, "trigger": trig}
	add_poi("gate:" + neighbour, pos, "Route to %s: %s" % [WorldState.areas[neighbour].region.replace("_", " "), route], location_at(pos), radius)


func add_interactable(it: Interactable) -> Interactable:
	add_child(it)
	interactables[it.id] = it
	add_poi(it.id, it.global_position if it.is_inside_tree() else it.position, it.label, it.location_id, it.radius)
	return it


func location_at(p: Vector3) -> String:
	var best := ""
	var best_d := 1e9
	for z in zones:
		var d: float = Vector2(p.x - z.center.x, p.z - z.center.z).length()
		if d <= z.radius and d < best_d:
			best = z.location
			best_d = d
	if best == "" and not zones.is_empty():
		# outside every zone: nearest location of this area (still truthful about the area)
		for z in zones:
			var d: float = Vector2(p.x - z.center.x, p.z - z.center.z).length() - z.radius
			if d < best_d:
				best_d = d
				best = z.location
	return best


## Legacy name used by the original bridge/tour: returns the location id.
func area_at(p: Vector3) -> String:
	return location_at(p)


func spawn_point(from_area: String) -> Transform3D:
	if gates.has(from_area):
		return gates[from_area].arrive
	return _default_spawn()


func _default_spawn() -> Transform3D:
	if not zones.is_empty():
		var poi: Vector3 = points_of_interest[zones[0].location].position
		return Transform3D(Basis.IDENTITY, poi + Vector3(0, 0.05, 2.0))
	return Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0))


func ground_height(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -200, z))
	var hit := space.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else 0.0


func set_magic_bounce(pos: Vector3, strength: float, color: Color) -> void:
	for m in magic_receivers:
		m.set_shader_parameter("magic_pos", pos)
		m.set_shader_parameter("magic_strength", strength)
		m.set_shader_parameter("magic_color", color)


func set_rune_charge(_charge: float, _reveal: float) -> void:
	pass


## Free physical space around p (for casting): radius of clear ground.
func has_space_for_magic(p: Vector3, radius := 1.0) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.45, 0))
	q.collision_mask = 1
	for hit in space.intersect_shape(q, 8):
		if hit.collider is StaticBody3D:
			return false
	return true
