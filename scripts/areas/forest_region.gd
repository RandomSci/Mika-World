class_name ForestRegion
extends WhisperingWoods
## A playable forest area of the ENCHANTED FOREST region built on the Whispering Woods' realistic toolkit (the
## quality bar the developer approved: photographic ground, layered species, undergrowth, grass, light shafts,
## leaf fall), each with its own geography and identity (the world-quality gate: "CHANGE THE WORLD QUALITY, MAKE
## IT CINEMATIC, NOT CARTOONISH"). Subclasses describe the place in data-like overrides:
##   trails            [[points], width, main|narrow|hidden]   (set in _init)
##   clearings         [[Vector2 centre, radius, zone]]         open, level ground (glades, shrine courts)
##   streams           [[points], half_width, depth]           water courses (ribbon water, banks, nav holes)
##   shape(x, z, h)    extra terrain shaping (hills, plateaus, ravines) on top of the rolling ground
##   density(p, f)     how wooded a spot is
##   features()        the place's own build steps (landmarks, ruins, glowcaps ...)
##   links()           locations, gates, interactables
## Light follows the world clock hour by hour (dawn, noon, dusk, night), like the travel stretches.

var clearings: Array = []
var streams: Array = []
var water_tune := {}                 # stylized_water overrides for this place's water (an open valley reflects sky, not canopy)
var _stream_seg: Array = []          # [[a, b, half_width, depth]] flattened for queries


func _init() -> void:
	trails = []


func shape(_x: float, _z: float, h: float) -> float:
	return h


func density(_p: Vector2, f: float) -> float:
	return f


func features() -> Array:
	return []


func links() -> void:
	pass


# ------------------------------------------------------------------ geography
func _segs() -> Array:
	if _stream_seg.is_empty():
		for s in streams:
			var pts: Array = s[0]
			for i in pts.size() - 1:
				_stream_seg.append([pts[i], pts[i + 1], float(s[1]), float(s[2])])
	return _stream_seg


## Distance to the nearest stream centreline and that stream's [half_width, depth].
func stream_info(p: Vector2) -> Array:
	var best := INF
	var hw := 0.0
	var dep := 0.0
	for sg in _segs():
		var d := _seg_dist(p, sg[0], sg[1])
		if d < best:
			best = d
			hw = sg[2]
			dep = sg[3]
	return [best, hw, dep]


func _raw_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var roll := 1.2 * sin(x * 0.041 + 0.6) * cos(z * 0.036) + 0.55 * sin(x * 0.11 + 1.3) * sin(z * 0.09 + 0.4) + 0.25 * sin((x - z) * 0.21)
	var si := stream_info(p)
	# streams run level-ish: the rolling ground calms near the water, and the bed is cut into it
	roll *= smoothstep(float(si[1]), float(si[1]) + 10.0, float(si[0])) * 0.85 + 0.15
	var h := shape(x, z, roll)
	for c in clearings:
		var cf := 1.0 - smoothstep(float(c[1]) - 2.0, float(c[1]) + 5.0, p.distance_to(c[0]))
		# a clearing calms the ground's small rolls; it never undoes the place's big landforms (hills, bowls)
		h = lerpf(h, shape(x, z, roll * 0.12), cf)
	# the water courses are cut last: nothing levels a riverbed back up (a meadow beside a river keeps its river)
	if float(si[1]) > 0.0:
		h -= (1.0 - smoothstep(float(si[1]) * 1.05, float(si[1]) + 4.0, float(si[0]))) * float(si[2])
	# a rim of higher wooded ground round the edges, opened where gates are
	h += smoothstep(108.0, 136.0, maxf(absf(x), absf(z))) * 9.0 * (1.0 - _gate_gap(p))
	return h


func _gate_gap(p: Vector2) -> float:
	var g := 0.0
	for gp in gate_spots():
		g = maxf(g, 1.0 - smoothstep(8.0, 18.0, p.distance_to(gp)))
	return g


## Where the gates are (map edge points): the rim stays open there.
func gate_spots() -> Array:
	return []


func _terrain_mask(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var ix := clampi(int(round((x + HALF) / STEP)), 0, _n - 1)
	var iz := clampi(int(round((z + HALF) / STEP)), 0, _n - 1)
	var tr := _trail_mask[iz * _n + ix]
	var hid := _hidden_mask[iz * _n + ix] * 0.45
	var si := stream_info(p)
	var bank := (1.0 - smoothstep(float(si[1]) + 1.0, float(si[1]) + 5.5, float(si[0]))) if float(si[1]) > 0.0 else 0.0
	return Color(maxf(tr, hid), _forest_density(p) * 0.85, clampf(bank, 0.0, 1.0), 0.0)


func _forest_density(p: Vector2) -> float:
	var f := 0.6 + 0.25 * sin(p.x * 0.033 + 1.1) * cos(p.y * 0.029 + 0.4)
	for c in clearings:
		f -= 0.75 * (1.0 - smoothstep(float(c[1]), float(c[1]) + 10.0, p.distance_to(c[0])))
	return clampf(density(p, f), 0.0, 1.0)


func site_zone(p: Vector2) -> String:
	for c in clearings:
		if p.distance_to(c[0]) < float(c[1]) + 6.0:
			return String(c[2])
	var si := stream_info(p)
	if float(si[1]) > 0.0 and float(si[0]) < float(si[1]) + 7.0:
		return "streamside"
	return "deep" if _forest_density(p) > 0.72 else "wood"


func site_water_dist(p: Vector2) -> float:
	var si := stream_info(p)
	return (float(si[0]) - float(si[1])) if float(si[1]) > 0.0 else 999.0


func site_clearing(p: Vector2, margin := 0.0) -> bool:
	for c in clearings:
		if p.distance_to(c[0]) < float(c[1]) + margin:
			return true
	for gp in gate_spots():
		if p.distance_to(gp) < 10.0 + margin:
			return true
	return false


# ------------------------------------------------------------------ build
func build_steps() -> Array:
	dress = WoodsDressing.new(self)
	dress.rng.seed = hash(area_id) ^ 7171
	feats = WoodsFeatures.new(self)
	feats.rng.seed = hash(area_id) ^ 9191
	marks = null
	var steps: Array = [_precompute, _painted_sky, _terrain, _streams, dress.compute_trail_distance, dress.trees, dress.understory,
		dress.undergrowth, dress.grass, dress.rocks, _steep_rocks, dress.atmosphere, feats.leaf_fall]
	steps.append_array(features())
	steps.append(_links)
	return steps


func _streams() -> void:
	if streams.is_empty():
		return
	var wm := RiverRibbon.forest_water()
	for k in water_tune:
		wm.set_shader_parameter(k, water_tune[k])
	mats.water = wm
	for s in streams:
		var pts: Array = s[0]
		var hw := float(s[1])
		var centre: Array = []
		var widths: Array = []
		# resample every 2 m; the water sits a fixed depth below the bank along the bed
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 2.0))
			for k in n:
				var q := a.lerp(b, float(k) / n)
				centre.append(Vector3(q.x, height(q.x, q.y) + float(s[2]) * 0.38, q.y))
				widths.append(hw * 2.0)
		var last: Vector2 = pts[pts.size() - 1]
		centre.append(Vector3(last.x, height(last.x, last.y) + float(s[2]) * 0.38, last.y))
		widths.append(hw * 2.0)
		# the surface follows the bed, smoothed along the course (no steps, no sudden dips into a bowl)
		var ys: Array[float] = []
		for c in centre:
			ys.append((c as Vector3).y)
		for pass_i in 3:
			var sm: Array[float] = ys.duplicate()
			for i in range(1, ys.size() - 1):
				sm[i] = (ys[i - 1] + ys[i] * 2.0 + ys[i + 1]) * 0.25
			ys = sm
		for i in centre.size():
			var c1: Vector3 = centre[i]
			centre[i] = Vector3(c1.x, ys[i], c1.z)
		add_child(RiverRibbon.build(centre, widths, wm))
		# the water is not walkable (fords and bridges are added by the place)
		for i in centre.size() - 1:
			var c0: Vector3 = centre[i]
			var c1: Vector3 = centre[i + 1]
			var dir := Vector2(c1.x - c0.x, c1.z - c0.z).normalized()
			var nrm := Vector2(-dir.y, dir.x) * (hw * 0.8)
			if _ford_at(Vector2(c0.x, c0.z)):
				continue
			_nav_hole([Vector2(c0.x, c0.z) - nrm, Vector2(c0.x, c0.z) + nrm, Vector2(c1.x, c1.z) + nrm, Vector2(c1.x, c1.z) - nrm], c0.y - 4.0, 4.6)


## Steep ground (escarpments, valley sides) carries bedded boulders and rock outcrops, like real hillsides: big
## mossy rocks set into the slope, more where it is steeper - never a smooth earth wall.
func _steep_rocks() -> void:
	var sets := {}
	var z := -HALF + 4.0
	var n := 0
	while z < HALF - 4.0:
		var x := -HALF + 4.0
		while x < HALF - 4.0:
			var p := Vector2(x + rng.randf_range(-1.2, 1.2), z + rng.randf_range(-1.2, 1.2))
			x += 3.2
			var sl := dress.slope(p.x, p.y)
			if sl < 0.6 or trail_at(p.x, p.y) > 0.15 or site_water_dist(p) < 2.0 or site_clearing(p, 1.0):
				continue
			if rng.randf() > clampf((sl - 0.6) * 1.4, 0.15, 0.85):
				continue
			var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
			var s := rng.randf_range(1.3, 2.6) * clampf(sl, 0.8, 1.6)
			(sets.get_or_add(id, []) as Array).append(dress.xf_at(p, s, 0.45, 0.4))
			n += 1
		z += 3.2
	# solid: characters stop at them and the camera never ends up inside one (layer 3; no navmesh caps - the steep
	# ground is unwalkable anyway)
	var rock_body := NatureKit.vegetation_body(self, "SteepRockColliders")
	for id in sets:
		NatureKit.scatter(self, NatureKit.mesh(String(id)), sets[id], {"vis_end": 240.0, "shadow": true, "name": "SteepRocks_" + String(id)})
		var aabb := NatureKit.mesh(String(id)).get_aabb()
		for t in sets[id]:
			var xf := t as Transform3D
			var sc := xf.basis.get_scale()
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = maxf(aabb.size.x * sc.x, aabb.size.z * sc.z) * 0.42
			cs.shape = sp
			cs.position = xf * aabb.get_center()
			rock_body.add_child(cs)
	dress.stats["steep_rocks"] = n


## A clearing's own ground cover (the forest undergrowth pass leaves clearings bare): a dense rim of ferns and
## leafy plants where the wood begins, clover, flowers and mushrooms sprinkled inside, fallen branches, a few mossy
## stones - a lived-in forest floor, not a lawn. keep_clear: [[Vector2, r]] spots that must stay open (steps, altars).
func dress_clearing(c: Vector2, r: float, sunny := true, keep_clear := []) -> void:
	var root := Node3D.new()
	root.name = "ClearingCover"
	add_child(root)
	var sets := {}
	var put := func(id: String, p: Vector2, s: float) -> void:
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height(p.x, p.y) - 0.02, p.y))
		(sets.get_or_add(id, []) as Array).append(t)
	var n := int(r * r * 1.4 * float(RenderProfile.get_setting("foliage_density")))
	for i in n:
		var d := sqrt(rng.randf()) * (r + 4.0)
		var p := c + Vector2.from_angle(rng.randf() * TAU) * d
		if trail_at(p.x, p.y) > 0.25 or site_water_dist(p) < 0.6:
			continue
		var blocked := false
		for kc in keep_clear:
			if p.distance_to(kc[0]) < float(kc[1]):
				blocked = true
		if blocked:
			continue
		var rim := smoothstep(r - 5.0, r + 1.0, d)
		var rr := rng.randf()
		if rr < rim * 0.55:
			put.call(["Fern_1", "Fern_1", "Plant_1", "Plant_7_Big", "Bush_Common"][rng.randi() % 5], p, rng.randf_range(0.9, 1.5))
		elif rr < 0.62:
			put.call(["Clover_1", "Clover_2", "Plant_7"][rng.randi() % 3], p, rng.randf_range(0.7, 1.2))
		elif rr < 0.74 and sunny:
			put.call(["Flower_3_Group", "Flower_4_Group", "Flower_3_Single", "Flower_4_Single"][rng.randi() % 4], p, rng.randf_range(0.5, 0.8))
		elif rr < 0.8:
			put.call("Mushroom_Common", p, rng.randf_range(0.4, 0.8))
	for id in sets:
		NatureKit.scatter(root, NatureKit.mesh(String(id)), sets[id], {"vis_end": 60.0, "shadow": String(id) == "Bush_Common", "chunk": 24.0, "name": "Clearing_" + String(id)})
	# fallen branches and a few mossy stones
	for i in int(r * 0.5):
		var p2 := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(r * 0.4, r + 2.0)
		if trail_at(p2.x, p2.y) > 0.25:
			continue
		Kit.place_prop(root, "dry_branches_medium_01", Kit.xf(Vector3(p2.x, height(p2.x, p2.y), p2.y), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.6, 1.0)), "", false)


## A place where people cross the water on foot (stepping stones / bridge): not cut out of the navmesh.
func _ford_at(_p: Vector2) -> bool:
	return false


func _links() -> void:
	links()
	boundary_box(Vector3(0, 0, 0), Vector3(SIZE - 6, 40, SIZE - 6))
	print("[forest_region] %s dressing %s features %s" % [area_id, dress.stats, feats.stats])


## A gate at the map edge: the trigger at `at`, arrivals placed `inward` metres toward the centre.
func edge_gate(neighbour: String, at: Vector2, inward := 9.0) -> void:
	if not WorldState.areas.has(neighbour):
		return
	var to_c := (-at).normalized()
	var arr := at + to_c * inward
	add_gate(neighbour, Vector3(at.x, height(at.x, at.y), at.y), Vector3(arr.x, height(arr.x, arr.y) + 0.05, arr.y), atan2(-to_c.x, -to_c.y), 3.0)


# ------------------------------------------------------------------ time of day (hour by hour, like the travel stretches)
var hour_shown := -1.0
var _tod_t := 0.0
var _shafts: Array = []


func set_night(v: bool) -> void:
	super.set_night(v)
	set_time_of_day(WorldState.hour_f())


func set_time_of_day(h: float) -> void:
	if env == null or sun == null:
		return
	hour_shown = h
	var L: Array = Wayside.LIGHT
	var i := 0
	while i < L.size() - 2 and h >= float(L[i + 1][0]):
		i += 1
	var a: Array = L[i]
	var b: Array = L[i + 1]
	var k := clampf((h - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var night_now := h < 5.1 or h > 20.0
	night = night_now
	sun.light_energy = lerpf(a[1], b[1], k)
	sun.light_color = (a[2] as Color).lerp(b[2], k)
	env.ambient_light_energy = lerpf(a[3], b[3], k)
	env.tonemap_exposure = lerpf(a[4], b[4], k)
	env.background_energy_multiplier = lerpf(a[5], b[5], k)
	env.fog_light_color = (a[6] as Color).lerp(b[6], k)
	env.fog_density = lerpf(a[7], b[7], k)
	env.sky = _sky_night if night_now else _sky_day
	env.ambient_light_sky_contribution = 0.55 if night_now else 0.5
	env.ambient_light_color = Color(0.2, 0.26, 0.42) if night_now else Color(0.6, 0.66, 0.52)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_albedo = Color(0.35, 0.42, 0.6) if night_now else Color(0.9, 0.93, 0.86)
	if night_now:
		sun.rotation_degrees = Vector3(-48, 120, 0)
	else:
		var t := clampf((h - 5.0) / 15.0, 0.0, 1.0)
		sun.rotation_degrees = Vector3(-4.0 - sin(t * PI) * 52.0, lerpf(70.0, 250.0, t), 0)
	for n in get_tree().get_nodes_in_group("night_lights_" + str(get_instance_id())):
		n.visible = night_now
	if _shafts.is_empty():
		for n in find_children("*", "MeshInstance3D", true, false):
			var mo := (n as MeshInstance3D).material_override as ShaderMaterial
			if mo and mo.shader and mo.shader.resource_path.contains("light_shaft"):
				_shafts.append(n)
	for n in _shafts:
		if is_instance_valid(n):
			(n as Node3D).visible = h > 8.0 and h < 17.0


func _process(delta: float) -> void:
	_tod_t -= delta
	if _tod_t <= 0.0:
		_tod_t = 0.25
		if absf(WorldState.hour_f() - hour_shown) > 0.02:
			set_time_of_day(WorldState.hour_f())

# ------------------------------------------------------------------ shared landmark builders (from the Woods' own)
## A waterfall: falling sheets from a lip (each [x offset, width, start below lip, reach, speed]), churning foam where
## it lands, rising mist, mossy boulders framing it. The water falls toward +z_dir.
func waterfall(lip: Vector3, foot_y: float, sheets: Array, dir := Vector3(0, 0, 1)) -> Node3D:
	var root := Node3D.new()
	root.name = "Waterfall"
	add_child(root)
	root.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), lip)
	var noise := Kit.noise()
	var drop := lip.y - foot_y
	for sh in sheets:
		var m := _sheet(Vector3(float(sh[0]), -float(sh[2]), 0.0), float(sh[1]), drop - float(sh[2]) + 0.2, float(sh[3]))
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = Kit.shader_mat("res://shaders/nature/stylized_waterfall.gdshader", {"noise_tex": noise, "width_m": float(sh[1]), "speed": float(sh[4])})
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var foam := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(14.0, 10.0)
	q.orientation = PlaneMesh.FACE_Y
	foam.mesh = q
	foam.material_override = Kit.shader_mat("res://shaders/nature/foam_patch.gdshader", {"noise_tex": noise})
	foam.position = Vector3(0, -drop + 0.05, 7.5)
	foam.rotation.y = PI
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(foam)
	var mist := GPUParticles3D.new()
	mist.amount = 34
	mist.lifetime = 5.0
	mist.preprocess = 5.0
	mist.position = Vector3(0, -drop + 0.6, 3.5)
	mist.visibility_aabb = AABB(Vector3(-10, -2, -8), Vector3(20, 16, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(6.0, 0.3, 1.2)
	pm.direction = Vector3(0, 1, 0.6)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.15, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	mist.process_material = pm
	var mq := QuadMesh.new()
	mq.size = Vector2(3.4, 3.4)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_color = Color(0.93, 0.97, 1.0)
	mm.albedo_texture = WoodsDressing._dot_tex()
	mm.proximity_fade_enabled = true
	mm.proximity_fade_distance = 1.0
	mq.material = mm
	mist.draw_pass_1 = mq
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mist)
	return root


static func _sheet(lip: Vector3, width: float, drop: float, reach: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 34
	var cols := 6
	var pts := []
	for i in rows + 1:
		var t := float(i) / rows
		var y := lip.y - drop * t * t
		var zz := lip.z + reach * t
		var w := width * (1.0 + 0.12 * t)
		var row := []
		for j in cols + 1:
			var u := float(j) / cols
			row.append([Vector3(lip.x + (u - 0.5) * w, y, zz), Vector2(u, t)])
		pts.append(row)
	for i in rows:
		for j in cols:
			var quad := [pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(0, 0.3, 1).normalized())
				st.set_uv(quad[k][1])
				st.add_vertex(quad[k][0])
	return st.commit()


## An old arched stone bridge across water running north-south: deck from x0 to x1 at z, arch rings over the
## channel, piers with cutwaters, abutments, a humped walkable deck with curbs, posts and rails (StoneBuilder).
func stone_bridge(z: float, x0: float, x1: float, mat: Material, seed := 61) -> Node3D:
	var root := Node3D.new()
	root.name = "StoneBridge"
	add_child(root)
	var base := maxf(height(x0 - 6.0, z), height(x1 + 6.0, z))
	var sb := StoneBuilder.new(height, seed)
	sb.base_y = base - 3.5
	sb.top_y = base + 4.0
	var depth := 3.6
	var span := x1 - x0
	var n_arch := 3 if span > 14.0 else 1
	var arches := []
	if n_arch == 3:
		var side_r := span * 0.136
		var mid_r := span * 0.1725
		arches = [[x0 + side_r, side_r, base - 1.0], [(x0 + x1) * 0.5, mid_r, base - 1.5], [x1 - side_r, side_r, base - 1.0]]
	else:
		arches = [[(x0 + x1) * 0.5, span * 0.42, base - 1.0]]
	var thick := 0.6
	for ar in arches:
		sb.ring(Vector3(ar[0], ar[2], z), 0.0, ar[1], thick, depth, 11 if float(ar[1]) < 3.0 else 13)
	var piers := []
	if n_arch == 3:
		piers = [x0 + span * 0.2, x1 - span * 0.2]
	for px in piers:
		var bed := height(px, z) - 0.6
		var y := bed
		while y < base - 1.0:
			var ch := minf(0.55, base - 1.0 - y)
			sb.block(Transform3D(sb._jit(0.6), Vector3(px, y + ch * 0.5, z)), Vector3(1.1, ch, depth), 0.1)
			sb.block(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(px, y + ch * 0.5, z - depth * 0.5)), Vector3(0.78, ch, 0.78), 0.1)
			y += ch + 0.01
		sb.collider(Transform3D(Basis.IDENTITY, Vector3(px, (bed + base - 1.0) * 0.5, z)), Vector3(1.1, base - 1.0 - bed, depth))
	var deck_y := func(x: float) -> float:
		var top := base + 1.9
		if x < x0:
			return lerpf(height(x0 - 6.0, z) - 0.05, top, clampf((x - (x0 - 6.0)) / 6.0, 0.0, 1.0))
		if x > x1:
			return lerpf(top, height(x1 + 6.0, z) - 0.05, clampf((x - x1) / 6.0, 0.0, 1.0))
		return top + 1.4 * sin(PI * (x - x0) / span)
	for ab in [x0 - 0.75, x1 + 0.75]:
		var gy := height(ab, z) - 0.4
		var top2: float = deck_y.call(ab) - 0.3
		var y2 := gy
		while y2 < top2 - 0.05:
			var ch2 := minf(0.5, top2 - y2)
			sb.block(Transform3D(sb._jit(0.6), Vector3(ab, y2 + ch2 * 0.5, z)), Vector3(1.5, ch2, depth + 0.2), 0.15)
			y2 += ch2 + 0.01
	var x := x0
	while x < x1 - 0.01:
		var xm := x + 0.45
		var yt := -INF
		for ar in arches:
			var dx: float = xm - float(ar[0])
			var ro: float = float(ar[1]) + thick
			if absf(dx) < ro:
				yt = maxf(yt, float(ar[2]) + sqrt(ro * ro - dx * dx) - 0.15)
		for px2 in piers:
			if absf(xm - float(px2)) < 0.6:
				yt = maxf(yt, base - 1.0)
		var dtop: float = deck_y.call(xm) - 0.32
		if yt > -INF and dtop - yt > 0.12:
			for side: float in [-1.0, 1.0]:
				sb.block(Transform3D(sb._jit(0.5), Vector3(xm, (yt + dtop) * 0.5, z + side * (depth * 0.5 - 0.3))), Vector3(0.88, dtop - yt, 0.6), 0.05)
		x += 0.9
	x = x0 - 6.0
	var slice_i := 0
	while x < x1 + 6.0 - 0.01:
		var xa := x
		var xb := x + 0.95
		var ya: float = deck_y.call(xa)
		var yb: float = deck_y.call(xb)
		var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5, z)
		var bb := Basis(Vector3.BACK, atan2(yb - ya, xb - xa))
		for j in 3:
			sb.block(Transform3D(bb * sb._jit(0.4), mid + Vector3(0, -0.2, -1.2 + j * 1.2)), Vector3(0.93, 0.4, 1.16), sb.rng.randf() * 0.3, 0.04)
		if xa > x0 - 3.5 and xb < x1 + 3.5:
			for side2: float in [-1.0, 1.0]:
				var edge := mid + Vector3(0, 0, side2 * (depth * 0.5 + 0.05))
				sb.block(Transform3D(bb * sb._jit(0.5), edge + Vector3(0, 0.11, 0)), Vector3(0.93, 0.22, 0.42), 0.45)
				if slice_i % 2 == 0 and sb.rng.randf() > 0.08:
					sb.block(Transform3D(bb * sb._jit(0.8), edge + Vector3(0, 0.62, 0)), Vector3(0.3, 0.8, 0.3), 0.3)
					sb.block(Transform3D(bb, edge + Vector3(0, 1.06, 0)), Vector3(0.38, 0.08, 0.38), 0.6)
				sb.block(Transform3D(bb * sb._jit(0.3), edge + Vector3(0, 0.94, 0)), Vector3(0.95, 0.14, 0.18), 0.5)
				sb.collider(Transform3D(bb, edge + Vector3(0, 0.55, 0)), Vector3(1.0, 1.1, 0.42))
		sb.collider(Transform3D(bb, mid - Vector3(0, 0.2, 0)), Vector3(Vector2(xb - xa, yb - ya).length() + 0.04, 0.4, depth))
		x = xb
		slice_i += 1
	sb.finish(root, mat, "BridgeStone")
	return root
