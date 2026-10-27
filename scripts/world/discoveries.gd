class_name Discoveries
extends RefCounted
## Data-driven places to find (data/discoveries.json): each is a real, solid prop set into an area at one of its
## locations (an inscription stone, a cairn, a lantern post, a surveyor's crate, a small shrine) with an
## interactable that teaches what is there - often the clue that starts the next expedition (data/expeditions.json),
## so storylines run across the regions on foot. Placed when an area opens (WorldStreamingManager.before_reveal),
## on walkable ground clear of other things; never in empty air (the prop is what she reads or examines).

static var data := {}
static var last_fail := {}


static func load_data() -> Dictionary:
	if data.is_empty() and FileAccess.file_exists("res://data/discoveries.json"):
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/discoveries.json"))
	return data


static func populate(area: Node) -> int:
	if area == null or area.has_meta("discoveries_done") or not ("interactables" in area):
		return 0
	area.set_meta("discoveries_done", true)
	# the freshly baked navigation mesh reaches the map a few physics frames later (until then every closest-point
	# query answers the origin): wait for it, a second at most
	var map: RID = (area as Node3D).get_world_3d().navigation_map
	var probe: Vector3 = (area as Node3D).to_global(Vector3(3.0, 0.0, 3.0))
	for i in 60:
		if NavigationServer3D.map_get_closest_point(map, probe) != Vector3.ZERO:
			break
		await area.get_tree().physics_frame
	var n := 0
	for d in load_data().get("discoveries", []):
		if String(d.get("area", "")) != String(area.get("area_id")):
			continue
		var pos = _spot(area, d)
		var tries := 0
		while pos == null and int(last_fail.get("blocked", 0)) == 0 and tries < 90:
			# nothing walkable answered yet: the new navigation mesh is still reaching the map
			await area.get_tree().physics_frame
			tries += 1
			pos = _spot(area, d)
		if pos == null:
			push_warning("[discoveries] no clear spot for %s %s" % [d.id, str(last_fail)])
			continue
		var p: Vector3 = pos
		var top := _prop(area, String(d.get("prop", "stele")), p, float(d.get("yaw", 0.0)))
		var it := Interactable.make(String(d.id), String(d.label), String(d.get("verb", "inspect")), String(d.get("location", "")),
			p + Vector3(0, 0.0, 0), d.get("effects", {}), String(d.get("gesture", "")), float(d.get("duration", 5.0)))
		it.repeatable = bool(d.get("repeatable", false))
		it.kind = String(d.get("kind", "explore"))
		it.radius = float(d.get("radius", 1.8))
		it.face_point = top
		if d.has("requires"):
			it.requires = d.requires
		if d.has("book"):
			it.book_id = String(d.book)
		area.add_interactable(it)
		n += 1
	if n > 0:
		print("[discoveries] %s: %d placed" % [area.get("area_id"), n])
		area.set_meta("props_after_bake", true)   # (main re-bakes once every find is in: rebake_after_props)
	return n


## The finds' props are solid but are set in after the bake: the walking map must go round them (27 Oct live: two
## crates on the woods trail, every walk to the wayshrine, the Lamplighter's first clue, stuck against them 14 m
## short, and the story stood still all day). Once per arrival, still behind the travel card.
static func rebake_after_props(area: Node) -> void:
	if area == null or not area.has_meta("props_after_bake") or not area.has_method("bake_navigation"):
		return
	area.remove_meta("props_after_bake")
	await area.bake_navigation()


## Where it stands: the location's point of interest + offset, on walkable ground, clear of anything solid
## (a ring of alternatives if the first spot is taken). null if nothing is clear.
static func _spot(area: Node, d: Dictionary):
	last_fail = {}
	var pois: Dictionary = area.get("points_of_interest")
	var loc := String(d.get("location", ""))
	if not pois.has(loc):
		last_fail = {"no_poi": loc, "area": str(area.get("area_id")), "pois": pois.keys()}
		return null
	var base: Vector3 = (pois[loc] as Dictionary).position
	var off: Array = d.get("offset", [0, 0])
	var map: RID = (area as Node3D).get_world_3d().navigation_map
	var space := (area as Node3D).get_world_3d().direct_space_state
	var why := {"off_nav": 0, "blocked": 0}
	for ring: float in [0.0, 2.0, 3.5, 5.0]:
		for k in (1 if ring == 0.0 else 8):
			var a: float = TAU * k / 8.0
			# POIs are area-local; the navigation map and physics are global (areas stream in at their own offsets)
			var want: Vector3 = (area as Node3D).to_global(base + Vector3(float(off[0]), 0, float(off[1])) + Vector3(cos(a), 0, sin(a)) * ring)
			var p := NavigationServer3D.map_get_closest_point(map, want)
			if p.distance_to(Vector3(want.x, p.y, want.z)) > 1.5:
				why.off_nav += 1
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(1.4, 1.6, 1.4)
			q.shape = sh
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, 0))
			q.collision_mask = 1
			var hits := space.intersect_shape(q, 4)
			if hits.is_empty():
				return (area as Node3D).to_local(p)
			why.blocked += 1
			if not why.has("by"):
				why["by"] = hits.map(func(h): return str(h.collider.name) if h.collider else "?")
	why["base"] = base
	why["nav_iter"] = NavigationServer3D.map_get_iteration_id(map)
	last_fail = why
	return null


## The prop itself (area-local); returns the point she looks at (its face / top).
static func _prop(area: Node, kind: String, p: Vector3, yaw: float) -> Vector3:
	var a := area as Node3D
	var stone: Material = Kit.tri("castle_wall_slates", "1k", 0.6, 0.1, Color(0.78, 0.76, 0.72))
	var b := Basis(Vector3.UP, yaw)
	match kind:
		"cairn":
			var y := 0.0
			for i in 5:
				var s := 0.75 - i * 0.12
				var h := 0.28 - i * 0.02
				Kit.block(a, Vector3(s, h, s * 0.9), Transform3D(b * Basis(Vector3.UP, i * 0.6), p + Vector3(0, y + h * 0.5, 0)), stone, false, 0.05)
				y += h
			Kit.static_box(a, Vector3(0.75, y, 0.7), Transform3D(b, p + Vector3(0, y * 0.5, 0)))
			return p + Vector3(0, y * 0.8, 0)
		"lantern":
			var wood: Material = Kit.tri("dark_wooden_planks", "1k", 0.6, 0.0, Color(0.5, 0.36, 0.26))
			Kit.block(a, Vector3(0.16, 2.1, 0.16), Transform3D(b, p + Vector3(0, 1.05, 0)), wood, true, 0.01)
			Kit.block(a, Vector3(0.55, 0.08, 0.08), Transform3D(b, p + Vector3(0.22, 2.0, 0)), wood, false, 0.01)
			Kit.mesh_node(a, Kit.prop("Lantern_01", "Lantern_01"), null, Transform3D(b.scaled(Vector3.ONE * 1.3), p + b * Vector3(0.42, 1.72, 0)))
			var lamp := Kit.omni(a, p + b * Vector3(0.42, 1.8, 0), Color(1.0, 0.72, 0.42), 0.9, 6.0)
			if a.has_method("night_only"):
				a.night_only(lamp)
			return p + Vector3(0, 1.5, 0)
		"crates":
			Kit.place_prop(a, "wooden_crate_01", Kit.xf(p, yaw), "", true)
			Kit.place_prop(a, "wooden_crate_01", Kit.xf(p + b * Vector3(0.95, 0, 0.25), yaw + 0.5), "", true)
			return p + Vector3(0, 0.7, 0)
		"shrine":
			Kit.block(a, Vector3(0.9, 0.9, 0.6), Transform3D(b, p + Vector3(0, 0.45, 0)), stone, true, 0.04)
			Kit.block(a, Vector3(1.05, 0.12, 0.72), Transform3D(b, p + Vector3(0, 0.96, 0)), stone, false, 0.03)
			var glow := Kit.omni(a, p + Vector3(0, 1.2, 0), Color(1.0, 0.8, 0.5), 0.6, 4.0)
			if a.has_method("night_only"):
				a.night_only(glow)
			return p + Vector3(0, 1.0, 0)
	# "stele": an inscription stone on a low base, its face toward +Z turned by yaw
	Kit.block(a, Vector3(1.1, 0.22, 0.7), Transform3D(b, p + Vector3(0, 0.11, 0)), stone, false, 0.04)
	Kit.block(a, Vector3(0.85, 1.45, 0.24), Transform3D(b * Basis(Vector3.RIGHT, -0.04), p + Vector3(0, 0.95, 0)), stone, false, 0.05)
	Kit.static_box(a, Vector3(1.1, 1.7, 0.7), Transform3D(b, p + Vector3(0, 0.85, 0)))
	return p + Vector3(0, 1.2, 0) + b * Vector3(0, 0, 0.13)
