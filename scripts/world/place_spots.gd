class_name PlaceSpots
extends RefCounted
## Small named places in every area (Selwyn, 23 Oct checklist: "Detailed 6 regions, more places to explore each
## region"). Until now the whole world had 22 named points of interest and most far areas one to three, so the brain
## fell back on "look at a cluster of rocks" (a viewer: "so many rocks") and the same few places. data/places.json gives
## every area five or six spots, each a real thing built where it stands (a cairn, a wayshrine, a spring, a statue, a
## notice board ...), with what anyone sees (look), what a closer look finds (secret, said once and remembered, it can
## teach a lore line or a clue of the running story chapter) and what is different after dark.
##
## Built as one area build step (AreaBase.activate_steps), placed deterministically on flat open ground off the trails
## and out of the water, a ring of distances from one of the area's locations. Each spot is an Interactable
## ("spot:<id>", verb inspect) and a point of interest, so the camera, the curiosity talk and the brain all see it.
## The brain's "spot" option walks there; visit() does the closer look, the talk between the girls and the memory.

const DATA := "res://data/places.json"
# the spot's gesture word -> a clip both girls have (WorldCharacter.CLIPS)
const GESTURES := {"look_around": "look_around", "crouch_inspect": "kneel_fix", "touch": "pick_chest", "look_up": "look_around",
	"look_far": "pointing", "look_down": "pick_floor", "pray": "kneel_fix", "read_scroll": "pick_chest"}
const MIN_SPACING := 6.0              # metres between two spots of one area
const REVISIT_GAP_S := 5400.0         # a spot she knows is worth another look only after this long

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f else {"spots": {}}
	return _data


static func specs(area_id: String) -> Array:
	return (data().spots as Dictionary).get(area_id, [])


static func spec(spot_id: String) -> Dictionary:
	for a in data().spots:
		for s in data().spots[a]:
			if String(s.id) == spot_id:
				return s
	return {}


static func has_spots(area_id: String) -> bool:
	return not specs(area_id).is_empty()


## A spot of a story chapter stands only once that chapter has begun (its marks were not there before).
static func active(s: Dictionary) -> bool:
	var ch := String(s.get("chapter", ""))
	return ch == "" or WorldState.knowledge.has("chapter_started:" + ch)


# ------------------------------------------------------------------ building
static func build(area: AreaBase) -> void:
	var placed: Array = []
	var built := 0
	var t0 := Time.get_ticks_usec()
	var t_slice := t0
	for s in specs(area.area_id):
		if not active(s):
			continue
		var poi: Dictionary = area.points_of_interest.get(String(s.loc), {})
		if poi.is_empty():
			continue
		var at := _site(area, poi.position, s, placed)
		if at == Vector3.INF:
			print("[spots] %s: no open ground for %s near %s" % [area.area_id, s.id, s.loc])
			continue
		placed.append(at)
		var face := Vector3(poi.position.x - at.x, 0, poi.position.z - at.z)
		var yaw := atan2(face.x, face.z) if face.length() > 0.1 else 0.0
		_prop(area, String(s.prop), at, yaw, String(s.id))
		var it := Interactable.make("spot:" + String(s.id), String(s.name).capitalize(), "inspect", String(s.loc), at,
			{}, String(GESTURES.get(String(s.get("gesture", "look_around")), "look_around")), 2.5)
		it.kind = "inspect"
		it.radius = 1.6
		area.add_interactable(it)
		area.points_of_interest["spot:" + String(s.id)].description = String(s.look)
		built += 1
		# one prop a slice: a few metres of stone and a light each, never a long frame (builds are sliced, 22 Oct)
		if Time.get_ticks_usec() - t_slice > WorldStreamingManager.slice_us():
			await area.get_tree().process_frame
			t_slice = Time.get_ticks_usec()
	if built > 0:
		print("[spots] %s: %d places, %.0f ms" % [area.area_id, built, (Time.get_ticks_usec() - t0) / 1000.0])
		area.navigation_ready.connect(_prune.bind(area), CONNECT_ONE_SHOT)


## Once the navmesh exists: a place nobody can walk up to (behind a library wall, cut off by a stream) is taken away
## again, so the brain never sets off for it.
static func _prune(area: AreaBase) -> void:
	if not is_instance_valid(area) or area.nav_region == null or area.nav_region.navigation_mesh == null:
		return
	# the area's own baked mesh, read directly (the navigation map may not have synced yet when this runs: the
	# sanctuary's first check found every spot 9 to 21 m from a navmesh that was not there yet)
	var nm: NavigationMesh = area.nav_region.navigation_mesh
	var xf := area.nav_region.global_transform
	var verts := nm.get_vertices()
	var polys := []
	for i in nm.get_polygon_count():
		polys.append(Array(nm.get_polygon(i)).map(func(vi): return xf * verts[vi]))
	for k in area.interactables.keys():
		if not String(k).begins_with("spot:"):
			continue
		var it: Interactable = area.interactables[k]
		var d := _nav_dist(polys, it.global_position)
		if d <= 2.2:
			continue
		print("[spots] %s: %s cannot be walked to (navmesh %.1f m away), taken away" % [area.area_id, k, d])
		var root := area.get_node_or_null("Spot_" + String(k).trim_prefix("spot:"))
		if root:
			root.queue_free()
		area.interactables.erase(k)
		area.points_of_interest.erase(k)
		it.queue_free()


## Flat distance from p to the nearest walkable polygon at about its height (0 inside one).
static func _nav_dist(polys: Array, p: Vector3) -> float:
	var best := INF
	var q := Vector2(p.x, p.z)
	for poly in polys:
		var n: int = poly.size()
		if n < 3:
			continue
		if absf(float(poly[0].y) - p.y) > 2.5:
			continue
		var inside := false
		var j := n - 1
		for i in n:
			var a := Vector2(poly[i].x, poly[i].z)
			var b := Vector2(poly[j].x, poly[j].z)
			if (a.y > q.y) != (b.y > q.y) and q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
			best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
			j = i
		if inside:
			return 0.0
	return best


static func _ground(area: AreaBase, x: float, z: float, near_y: float) -> float:
	if area.has_method("ground_at"):
		return float(area.call("ground_at", x, z))
	var space := area.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, near_y + 6.0, z), Vector3(x, near_y - 8.0, z))
	var hit := space.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else INF


## Flat open ground in the spot's ring round its location: off the trails, out of the water, nothing solid standing
## there, not on top of another spot. Deterministic (seeded by the spot's id), so a revisit finds it where it was.
static func _site(area: AreaBase, c: Vector3, s: Dictionary, placed: Array) -> Vector3:
	var at := _site_pass(area, c, s, placed, 0.4, 0.12, 1.0)
	if at == Vector3.INF:
		# steep country (the highland path: its only flat ground is the trail): a little more slope, a trail's edge
		# but never its middle, a wider ring
		at = _site_pass(area, c, s, placed, 0.75, 0.35, 1.7)
	return at


static func _site_pass(area: AreaBase, c: Vector3, s: Dictionary, placed: Array, max_spread: float, max_trail: float, widen: float) -> Vector3:
	var ring: Array = s.get("ring", [6, 14])
	var r0 := float(ring[0])
	var r1 := float(ring[1]) * widen
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(s.id)) + (0 if widen == 1.0 else 7)
	var space := area.get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_cost := 1e9
	var why := {}
	var rise := 6.0 if widen == 1.0 else 14.0     # (the mountain path climbs 10 m within its own ring)
	for k in 60:
		var a := rng.randf() * TAU
		var d := rng.randf_range(r0, r1)
		var x: float = c.x + cos(a) * d
		var z: float = c.z + sin(a) * d
		if not area.nav_aabb.has_point(Vector3(x, area.nav_aabb.position.y + 1.0, z)):
			why.outside = why.get("outside", 0) + 1
			continue
		var y := _ground(area, x, z, c.y)
		if y == INF or absf(y - c.y) > rise:
			why.height = why.get("height", 0) + 1
			continue
		# something solid underfoot (the lake's bank collider stops at the shore: a stone in the water had none)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, y + 3.0, z), Vector3(x, y - 1.0, z)))
		if hit.is_empty() or absf(float(hit.position.y) - y) > 0.5:
			why.no_floor = why.get("no_floor", 0) + 1
			continue
		var spread := 0.0
		for o in [Vector2(0.9, 0), Vector2(-0.9, 0), Vector2(0, 0.9), Vector2(0, -0.9)]:
			var yo := _ground(area, x + o.x, z + o.y, y)
			spread = maxf(spread, absf(yo - y) if yo != INF else 9.0)
		if spread > max_spread:
			why.slope = why.get("slope", 0) + 1
			continue
		if area.has_method("trail_at") and float(area.call("trail_at", x, z)) > max_trail:
			why.trail = why.get("trail", 0) + 1
			continue                   # never on a path (a cairn in the middle of the trail blocks the walk)
		if area.has_method("site_water_dist") and float(area.call("site_water_dist", Vector2(x, z))) < 2.5:
			why.water = why.get("water", 0) + 1
			continue
		if placed.any(func(p): return Vector2(p.x - x, p.z - z).length() < MIN_SPACING):
			why.spacing = why.get("spacing", 0) + 1
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(2.2, 1.6, 2.2)
		q.shape = sh
		# (lifted by the slope: on a hillside the box's own uphill corner would touch the ground and count as solid)
		q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 1.0 + spread, z))
		if not space.intersect_shape(q, 1).is_empty():
			why.solid = why.get("solid", 0) + 1
			continue
		var cost := spread * 4.0 + absf(d - (r0 + r1) * 0.5) * 0.05
		if cost < best_cost:
			best_cost = cost
			best = Vector3(x, y, z)
	if best == Vector3.INF and widen > 1.0:
		print("[spots] %s: %s rejected %s" % [area.area_id, s.id, str(why)])
	return best


static func _wood() -> Material:
	return Kit.tri("wood_table_001", "1k", 0.9, 0.0, Color(0.6, 0.48, 0.38))


## The places' own stone (23 Oct stills: the areas' stone reads per-vertex colour, which these shapes do not have, so
## props came out flat grey or black): worked stone for benches, tablets, shrines and arches; natural rock for
## cairns, standing stones and outcrops; marble at the academy; dark wet rock under ground.
static func _stone_for(area: AreaBase, worked: bool) -> Material:
	var cave := area is CaveArea
	if area.area_id in ["academy", "great_library"] and worked:
		return Kit.tri("marble_01", "1k", 0.25, 0.0, Color(0.93, 0.92, 0.88))
	if not RealKit.enabled():
		return Kit.tri("mossy_rock", "1k", 0.4, 0.0 if cave else 0.6)
	if cave:
		return RealKit.stone_mat("rock_wall_10", false)
	return RealKit.stone_mat("mossy_stone_wall" if worked else "rock_pitted_mossy", false)


static func _prop(area: AreaBase, kind: String, at: Vector3, yaw: float, sid: String) -> void:
	var worked: bool = kind in ["stone_bench", "ruin_arch", "well", "statue", "tablet", "shrine", "chimes"]
	var stone := _stone_for(area, worked)
	var b := Basis(Vector3.UP, yaw)
	var seed := hash(sid) % 1000
	var root := Node3D.new()
	root.name = "Spot_" + sid
	area.add_child(root)
	match kind:
		"cairn":
			var y := 0.0
			for i in 5:
				var r := 0.42 - i * 0.07
				Kit.mesh_node(root, Kit.rock_mesh(r, seed + i, 0.25, Vector3(1.0, 0.45, 0.9)), stone, Transform3D(Basis(Vector3.UP, i * 1.3), at + Vector3(0, y + r * 0.42, 0)))
				y += r * 0.8
			Kit.static_box(root, Vector3(0.8, y, 0.8), Kit.xf(at + Vector3(0, y * 0.5, 0)))
		"standing_stone":
			Kit.mesh_node(root, Kit.rock_mesh(0.5, seed, 0.18, Vector3(0.75, 2.6, 0.5)), stone, Transform3D(b * Basis(Vector3.FORWARD, 0.06), at + Vector3(0, 1.15, 0)))
			Kit.static_box(root, Vector3(0.8, 2.4, 0.6), Transform3D(b, at + Vector3(0, 1.2, 0)))
		"stone_bench":
			Kit.block(root, Vector3(1.6, 0.12, 0.48), Transform3D(b, at + Vector3(0, 0.44, 0)), stone, false, 0.03)
			for sx: float in [-0.6, 0.6]:
				Kit.block(root, Vector3(0.22, 0.4, 0.42), Transform3D(b, at + b * Vector3(sx, 0.2, 0)), stone, false, 0.02)
			Kit.static_box(root, Vector3(1.6, 0.5, 0.48), Transform3D(b, at + Vector3(0, 0.25, 0)))
		"ruin_arch":
			for sx: float in [-1.0, 1.0]:
				Kit.block(root, Vector3(0.5, 2.2 if sx < 0 else 1.5, 0.5), Transform3D(b, at + b * Vector3(sx, 1.1 if sx < 0 else 0.75, 0)), stone, false, 0.04)
			Kit.block(root, Vector3(2.4, 0.42, 0.5), Transform3D(b * Basis(Vector3.FORWARD, 0.28), at + b * Vector3(-0.1, 1.95, 0)), stone, false, 0.04)
			Kit.static_box(root, Vector3(0.5, 2.2, 0.5), Transform3D(b, at + b * Vector3(-1, 1.1, 0)))
			Kit.static_box(root, Vector3(0.5, 1.5, 0.5), Transform3D(b, at + b * Vector3(1, 0.75, 0)))
		"well":
			Kit.mesh_node(root, Kit.lathe([Vector2(0.7, 0), Vector2(0.95, 0), Vector2(0.95, 0.75), Vector2(0.7, 0.75), Vector2(0.7, 0)], 18, false, false), stone, Kit.xf(at))
			var water := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.7
			disc.bottom_radius = 0.7
			disc.height = 0.02
			water.mesh = disc
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.03, 0.05, 0.07)
			wm.roughness = 0.05
			water.material_override = wm
			water.position = at + Vector3(0, 0.35, 0)
			root.add_child(water)
			Kit.static_box(root, Vector3(1.9, 0.8, 1.9), Kit.xf(at + Vector3(0, 0.4, 0)))
		"spring":
			for i in 7:
				var a := i * TAU / 7.0
				Kit.mesh_node(root, Kit.rock_mesh(0.22, seed + i, 0.3, Vector3(1, 0.6, 1)), stone, Kit.xf(at + Vector3(cos(a) * 0.85, 0.08, sin(a) * 0.85), a))
			var pool := MeshInstance3D.new()
			var pd := CylinderMesh.new()
			pd.top_radius = 0.75
			pd.bottom_radius = 0.75
			pd.height = 0.02
			pool.mesh = pd
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.05, 0.11, 0.12, 0.82)
			pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pm.roughness = 0.03
			pm.metallic = 0.55
			pm.metallic_specular = 0.8
			pool.material_override = pm
			pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pool.position = at + Vector3(0, 0.05, 0)
			root.add_child(pool)
			area.night_only(Kit.omni(root, at + Vector3(0, 0.4, 0), Color(0.55, 0.85, 1.0), 0.5, 2.5))
		"statue":
			Kit.block(root, Vector3(0.9, 0.6, 0.9), Transform3D(b, at + Vector3(0, 0.3, 0)), stone, false, 0.04)
			# a hooded figure: robe, shoulders, a hood, one arm raised with a lamp
			Kit.mesh_node(root, Kit.lathe([Vector2(0.0, 0), Vector2(0.4, 0), Vector2(0.36, 0.55), Vector2(0.27, 1.05), Vector2(0.3, 1.22),
				Vector2(0.17, 1.32), Vector2(0.0, 1.34)], 16, true, true), stone, Transform3D(b, at + Vector3(0, 0.6, 0)))
			Kit.mesh_node(root, Kit.lathe([Vector2(0.0, 0), Vector2(0.15, 0.02), Vector2(0.17, 0.18), Vector2(0.13, 0.32), Vector2(0.0, 0.36)], 12, true, true),
				stone, Transform3D(b, at + Vector3(0, 1.92, 0)))
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.12, 0.62, 0.12), 0.03), stone, Transform3D(b * Basis(Vector3.FORWARD, -0.35), at + Vector3(0, 2.0, 0) + b * Vector3(0.36, 0, 0)))
			Kit.mesh_node(root, Kit.lathe([Vector2(0.0, 0), Vector2(0.1, 0.02), Vector2(0.1, 0.16), Vector2(0.0, 0.2)], 8, true, true), stone,
				Transform3D(b, at + Vector3(0, 2.3, 0) + b * Vector3(0.48, 0, 0)))
			Kit.static_box(root, Vector3(0.9, 2.4, 0.9), Transform3D(b, at + Vector3(0, 1.2, 0)))
		"tablet":
			Kit.block(root, Vector3(0.95, 1.25, 0.16), Transform3D(b * Basis(Vector3.RIGHT, -0.1), at + Vector3(0, 0.62, 0)), stone, false, 0.03)
			var sig := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.7, 0.9)
			sig.mesh = q
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/magic/sigil.gdshader")
			m.set_shader_parameter("sides", 4 + seed % 5)
			m.set_shader_parameter("color", Color(0.85, 0.8, 0.6))
			m.set_shader_parameter("intensity", 0.12)
			m.set_shader_parameter("spin", 0.0)
			m.set_shader_parameter("seed", float(seed % 97))
			sig.material_override = m
			sig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sig.transform = Transform3D(b * Basis(Vector3.RIGHT, -0.1), at + Vector3(0, 0.64, 0) + b * Vector3(0, 0.06, 0.09))
			root.add_child(sig)
			Kit.static_box(root, Vector3(1.0, 1.3, 0.3), Transform3D(b, at + Vector3(0, 0.65, 0)))
		"crystal_cluster":
			var col := Color(0.55, 0.8, 1.0)
			for i in 6:
				var a := i * 1.7
				var l := 0.5 + (seed + i * 37) % 7 * 0.12
				Kit.mesh_node(root, Kit.crystal_mesh(l, 0.1 + i % 3 * 0.03, seed + i), Kit.crystal(col, 1.4),
					Transform3D(Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.35 if i > 0 else 0.0), at + Vector3(cos(a) * 0.25, l * 0.4, sin(a) * 0.25)), false)
			Kit.omni(root, at + Vector3(0, 0.7, 0), col, 0.6, 3.0)
			Kit.static_box(root, Vector3(0.9, 1.1, 0.9), Kit.xf(at + Vector3(0, 0.55, 0)))
		"mushroom_ring":
			var cap := StandardMaterial3D.new()
			cap.albedo_color = Color(0.86, 0.84, 0.78)
			cap.emission_enabled = true
			cap.emission = Color(0.4, 0.75, 1.0)
			cap.emission_energy_multiplier = 0.0
			var stem := StandardMaterial3D.new()
			stem.albedo_color = Color(0.9, 0.88, 0.82)
			var capm := Kit.lathe([Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.075, 0.035), Vector2(0.0, 0.055)], 10, true, true)
			var stemm := Kit.lathe([Vector2(0.018, 0.0), Vector2(0.015, 0.09)], 6, true, true)
			for i in 14:
				var a := i * TAU / 14.0 + sin(i * 2.1) * 0.12
				var p := at + Vector3(cos(a) * 1.05, 0, sin(a) * 1.05)
				var s := 0.8 + (i * 31 % 5) * 0.12
				Kit.mesh_node(root, stemm, stem, Transform3D(Basis().scaled(Vector3.ONE * s), p), false)
				Kit.mesh_node(root, capm, cap, Transform3D(Basis().scaled(Vector3.ONE * s), p + Vector3(0, 0.085 * s, 0)), false)
			root.set_meta("night_glow", cap)
			area.night_only(Kit.omni(root, at + Vector3(0, 0.3, 0), Color(0.45, 0.75, 1.0), 0.45, 2.5))
		"log":
			# triplanar bark (the lathe's own UVs stretched the bark into streaks along the log, 23 Oct stills)
			var bark: Material = Kit.tri("bark_brown_02", "1k", 0.8, 0.35, Color(0.85, 0.8, 0.75))
			Kit.mesh_node(root, Kit.lathe([Vector2(0.0, 0.0), Vector2(0.38, 0.0), Vector2(0.42, 0.4), Vector2(0.4, 2.6), Vector2(0.34, 3.0), Vector2(0.0, 3.0)], 12, true, true), bark,
				Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0, 0.36, 0) + b * Vector3(0, 0, -1.5)))
			Kit.static_box(root, Vector3(0.8, 0.75, 3.0), Transform3D(b, at + Vector3(0, 0.37, 0)))
		"lantern_post":
			var w := _wood()
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.14, 2.1, 0.14), 0.02), w, Transform3D(b, at + Vector3(0, 1.05, 0)))
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.5, 0.08, 0.08), 0.01), w, Transform3D(b, at + Vector3(0, 2.0, 0) + b * Vector3(0.2, 0, 0)))
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.22, 0.3, 0.22), 0.02), Kit.metal(Color(0.15, 0.14, 0.13)), Transform3D(b, at + Vector3(0, 1.75, 0) + b * Vector3(0.38, 0, 0)))
			Kit.static_box(root, Vector3(0.3, 2.1, 0.3), Kit.xf(at + Vector3(0, 1.05, 0)))
		"shrine":
			Kit.block(root, Vector3(0.7, 0.45, 0.55), Transform3D(b, at + Vector3(0, 0.22, 0)), stone, false, 0.03)
			Kit.block(root, Vector3(0.6, 0.05, 0.45), Transform3D(b, at + Vector3(0, 0.47, 0)), stone, false, 0.01)
			for sx: float in [-0.26, 0.26]:
				Kit.block(root, Vector3(0.08, 0.42, 0.4), Transform3D(b, at + b * Vector3(sx, 0.7, 0)), stone, false, 0.01)
			Kit.block(root, Vector3(0.6, 0.42, 0.06), Transform3D(b, at + b * Vector3(0, 0.7, -0.18)), stone, false, 0.01)
			Kit.block(root, Vector3(0.82, 0.08, 0.6), Transform3D(b, at + Vector3(0, 0.95, 0)), stone, false, 0.02)
			Kit.static_box(root, Vector3(0.82, 1.0, 0.6), Transform3D(b, at + Vector3(0, 0.5, 0)))
		"lookout":
			Kit.mesh_node(root, Kit.rock_mesh(0.95, seed, 0.28, Vector3(1.25, 0.6, 0.95)), stone, Transform3D(b, at + Vector3(0, 0.08, 0)))
			Kit.mesh_node(root, Kit.rock_mesh(0.45, seed + 3, 0.3, Vector3(1.0, 0.7, 0.9)), stone, Transform3D(b, at + b * Vector3(0.9, 0.05, 0.5)))
			Kit.static_box(root, Vector3(2.4, 0.5, 1.8), Transform3D(b, at + Vector3(0, 0.12, 0)))
		"chimes":
			var w := _wood()
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.12, 2.2, 0.12), 0.02), w, Transform3D(b, at + Vector3(0, 1.1, 0)))
			Kit.mesh_node(root, Kit.box_mesh(Vector3(0.9, 0.07, 0.07), 0.01), w, Transform3D(b, at + Vector3(0, 2.05, 0)))
			var ch := Kit.lathe([Vector2(0.025, 0.0), Vector2(0.025, 0.3)], 6, true, true)
			for i in 5:
				Kit.mesh_node(root, ch, stone, Transform3D(b, at + Vector3(0, 1.62 + (i % 2) * 0.08, 0) + b * Vector3(-0.36 + i * 0.18, 0, 0)), false)
			Kit.static_box(root, Vector3(0.3, 2.2, 0.3), Kit.xf(at + Vector3(0, 1.1, 0)))
		"book_stack":
			var cols := [Color(0.42, 0.14, 0.12), Color(0.16, 0.24, 0.36), Color(0.25, 0.3, 0.16), Color(0.4, 0.32, 0.18), Color(0.3, 0.16, 0.3)]
			var y := 0.0
			for i in 7:
				var bm := StandardMaterial3D.new()
				bm.albedo_color = cols[(seed + i) % cols.size()]
				bm.roughness = 0.8
				var h := 0.06 + (i * 13 % 4) * 0.015
				Kit.mesh_node(root, Kit.box_mesh(Vector3(0.34 - i % 3 * 0.03, h, 0.26), 0.008), bm, Transform3D(Basis(Vector3.UP, yaw + sin(i * 1.9) * 0.4), at + Vector3(0, y + h * 0.5, 0)), false)
				y += h
			Kit.static_box(root, Vector3(0.45, y, 0.4), Kit.xf(at + Vector3(0, y * 0.5, 0)))
		"ash_mark":
			var ash := StandardMaterial3D.new()
			ash.albedo_color = Color(0.2, 0.2, 0.21)
			ash.roughness = 1.0
			var scorch := MeshInstance3D.new()
			var sd := CylinderMesh.new()
			sd.top_radius = 1.0
			sd.bottom_radius = 1.0
			sd.height = 0.015
			scorch.mesh = sd
			scorch.material_override = ash
			scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			scorch.position = at + Vector3(0, 0.02, 0)
			root.add_child(scorch)
			Kit.mesh_node(root, Kit.rock_mesh(0.3, seed, 0.25, Vector3(1, 0.7, 1)), stone, Kit.xf(at + Vector3(0, 0.15, 0)))
			var mark := MeshInstance3D.new()
			var mq := QuadMesh.new()
			mq.size = Vector2(0.5, 0.5)
			mark.mesh = mq
			var mm := ShaderMaterial.new()
			mm.shader = load("res://shaders/magic/sigil.gdshader")
			mm.set_shader_parameter("sides", 3)
			mm.set_shader_parameter("color", Color(0.35, 0.35, 0.38))
			mm.set_shader_parameter("intensity", 0.05)
			mm.set_shader_parameter("spin", 0.0)
			mm.set_shader_parameter("seed", 13.0)
			mark.material_override = mm
			mark.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at + Vector3(0, 0.035, 0.6))
			root.add_child(mark)
		_:
			Kit.mesh_node(root, Kit.rock_mesh(0.5, seed), stone, Kit.xf(at + Vector3(0, 0.3, 0)))


## After dark the mushroom caps glow (the area's set_night calls this through its spots' metadata).
static func set_night(area: AreaBase, v: bool) -> void:
	for n in area.get_children():
		if n is Node3D and String(n.name).begins_with("Spot_") and n.has_meta("night_glow"):
			(n.get_meta("night_glow") as StandardMaterial3D).emission_energy_multiplier = 1.4 if v else 0.0


# ------------------------------------------------------------------ the brain's side
## The spots of the area she is in that are worth walking to now: one never seen (curiosity), one a story clue may be
## at, or a known one after a long while (a different look, at night perhaps).
static func options(brain) -> Array:
	var out := []
	var area = brain.main.world
	if area == null or not area is AreaBase:
		return out
	var now := Time.get_unix_time_from_system()
	var lead_spots := {}
	if brain.main.get("story"):
		for l in brain.main.story.next_leads():
			if String(l.get("activity", "")) == "spot" and (not bool(l.get("night", false)) or WorldState.night):
				lead_spots[String(l.spot)] = String(l.lead)
	for s in specs(String(brain.main.streaming.current_id)):
		var key := "spot:" + String(s.id)
		if not area.interactables.has(key):
			continue
		var seen := float(brain.mind.knowledge.get("spot_seen:" + String(s.id), 0.0))
		var lead := String(lead_spots.get(String(s.id), ""))
		if seen > 0.0 and now - seen < REVISIT_GAP_S and lead == "":
			continue
		out.append({"kind": "spot", "key": key, "interactable": key, "spot": String(s.id), "first": seen == 0.0,
			"clue": String(s.get("clue", "")), "lead": lead, "label": lead if lead != "" else ("look at %s" if seen == 0.0 else "go back to %s") % String(s.name)})
	return out


static func score(o: Dictionary, needs: Dictionary) -> Dictionary:
	var u := 0.2 + float(needs.get("curiosity", 0.5)) * 0.45
	var why := []
	if o.first:
		u += 0.35
		why.append("never looked at it +0.35")
	else:
		u -= 0.25
	if String(o.get("lead", "")) != "":
		u += 0.8
		why.append("the trail leads here +0.80")
	elif String(o.clue) != "" and not WorldState.knowledge.has(String(o.clue)):
		u += 0.45
		why.append("it may have to do with the case +0.45")
	return {"u": u, "why": why}


## Walk over, take the closer look (the gesture, the knowledge it teaches), the girls talk about what they found, and
## both remember it (said once: a revisit is told what they found last time and must notice something else).
static func visit(brain, o: Dictionary) -> Dictionary:
	var s := spec(String(o.spot))
	if s.is_empty():
		return {"ok": false, "detail": "no such place"}
	var res: Dictionary = await brain._use(String(o.interactable))
	if not res.get("ok", false):
		return res
	var who: String = brain.agent_id
	var mind = brain.mind
	var first: bool = not mind.knowledge.has("spot:" + String(s.id))
	var night: bool = WorldState.night and String(s.get("night", "")) != ""
	var effects := {"knowledge": {"spot:" + String(s.id): 1}}
	if first:
		for k in s.get("knowledge", {}):
			effects.knowledge[k] = 1
	# the running chapter's ending at this spot (the lake's wish stone: a light sent north, on a night)
	var fin: Dictionary = brain.main.story.data.get("finale", {}) if brain.main.get("story") else {}
	var finale: bool = not fin.is_empty() and String(fin.spot) == String(s.id) and WorldState.knowledge.has(String(fin.requires)) \
		and (not bool(fin.get("night", false)) or WorldState.night) and not (fin.knowledge as Dictionary).keys().all(func(k): return WorldState.knowledge.has(k))
	WorldState.record_activity({"id": "spot:" + String(s.id), "verb": "inspect", "label": String(s.name)}, effects, who)
	# a clue and an ending are the story's, which is Mika's (story knowledge lives in her mind)
	var story_k := {}
	if String(s.get("clue", "")) != "" and not WorldState.knowledge.has(String(s.clue)):
		story_k[String(s.clue)] = 1
	if finale:
		story_k.merge(fin.knowledge)
	if not story_k.is_empty():
		WorldState.record_activity({"id": "clue:" + String(s.id), "verb": "discover", "label": String(s.name)}, {"knowledge": story_k}, "mika")
	mind.knowledge["spot_seen:" + String(s.id)] = Time.get_unix_time_from_system()
	var other := ""
	for w in brain.main.characters:
		if String(w) != who and (brain.main.characters[w] as Node3D).visible:
			other = String(w)
	var text := ""
	if finale:
		text = String(fin.text)
	elif first:
		text = "you walked over to %s: %s. Looking closer you find that %s." % [String(s.name), String(s.look), String(s.secret)]
		if night:
			text += " It is night, and %s." % String(s.night)
		if String(s.get("clue", "")) != "":
			text += " This could be part of the mystery you are following (%s). Think out loud about what it might mean and who did it: each of you makes your own guess, and you may disagree." % brain.main.story.objective()
			var past: Array = (WorldState.mind(who).knowledge.get("theories", []) as Array).slice(-2).map(func(x): return String(x.get("said", "")))
			if not past.is_empty():
				text += " Earlier you guessed: %s. Say whether this fits your guess or changes your mind." % " / ".join(past)
		else:
			text += " Say what you notice, wonder about it, and answer each other."
	else:
		text = "you are back at %s (%s). Last time you found that %s." % [String(s.name), String(s.look), String(s.secret)]
		text += (" Now it is night, and %s." % String(s.night)) if night else " Notice something you missed before, or say what you think about it now that you know more."
	var talk := {}
	if other != "" and brain.main.mage_talk and brain.main.mage_talk.dialogue:
		talk = await brain.main.mage_talk.dialogue.converse(who, other, {"mode": "event", "topic": {"text": text, "key": "spot:" + String(s.id)}})
	# each girl keeps her own guesses about the case (said in this talk), to bring up and test later
	if first and String(s.get("clue", "")) != "" and talk.has("lines"):
		for g in [who, other]:
			if g == "":
				continue
			var mine: Array = (talk.lines as Array).filter(func(l): return String(l.who) == g).map(func(l): return String(l.text))
			if mine.is_empty():
				continue
			var th: Array = WorldState.mind(g).knowledge.get("theories", [])
			th.append({"clue": String(s.clue), "said": " ".join(mine).left(220), "unix": int(Time.get_unix_time_from_system())})
			WorldState.mind(g).knowledge["theories"] = th.slice(-8)
	if first and brain.main.get("story"):
		brain.main.story.evaluate()
	Highlights.moment(brain.main, "discovery", "%s looks closer at %s" % [MagicSystem.display_name(who), String(s.name)])
	return {"ok": true, "detail": "%s %s" % ["found out about" if first else "went back to", String(s.name)], "first": first,
		"talk": talk.get("ok", false)}
