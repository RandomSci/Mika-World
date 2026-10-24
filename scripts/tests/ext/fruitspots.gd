extends RefCounted
## --mktest=fruitspots (25 Oct, Selwyn: "magical fruits on trees"): finds where each outdoor area can grow a magic fruit
## tree. Around every point of interest, 4 to 8 m out: level walkable ground the paths reach from the area's first gate,
## nothing solid within 1.6 m, at least 5 m from any gate, place or interactable, at least 14 m from another tree.
## Prints one JSON line per area ("[fruitspots] {...}") for data/gatherables.json "trees". No GPU.

const AREAS := ["sanctuary", "lantern_lake", "mentor_tower", "whispering_woods", "ancient_grove", "river_valley", "village",
	"observatory_hill", "highland_path", "celestial_summit", "academy", "wayside"]
const PER_AREA := 3


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	var found := 0
	var errors := false
	for a in AREAS:
		if not WorldState.areas.has(a):
			print("[fruitspots] %s: no such area" % a)
			continue
		await main.streaming.travel(a, main.characters["mika"])
		await t._wait(1.5)
		var area = main.streaming.current
		var map: RID = main.characters["mika"].get_world_3d().navigation_map
		var space: PhysicsDirectSpaceState3D = main.characters["mika"].get_world_3d().direct_space_state
		var keep: Array = []          # points to stay away from
		for g in area.gates.values():
			for k in [g.position, g.arrive]:
				keep.append(k.origin if k is Transform3D else k)
		for p in area.points_of_interest.values():
			keep.append(p.position)
		for it in area.interactables.values():
			if it is Node3D:
				keep.append((it as Node3D).global_position)
		var ga = area.gates.values()[0].arrive if not area.gates.is_empty() else main.characters["mika"].global_position
		var start: Vector3 = ga.origin if ga is Transform3D else ga
		start = NavigationServer3D.map_get_closest_point(map, start)
		var chosen: Array = []
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(a)
		var pois: Array = area.points_of_interest.values()
		for tries in 400:
			if chosen.size() >= PER_AREA or pois.is_empty():
				break
			var base: Vector3 = pois[rng.randi() % pois.size()].position
			var ang := rng.randf() * TAU
			var r := rng.randf_range(4.0, 8.0)
			var c := base + Vector3(cos(ang) * r, 0, sin(ang) * r)
			var on := NavigationServer3D.map_get_closest_point(map, c + Vector3(0, 2.0, 0))
			if Vector2(on.x - c.x, on.z - c.z).length() > 0.3:
				continue
			c = on
			if keep.any(func(k): return Vector2(k.x - c.x, k.z - c.z).length() < 5.0):
				continue
			if chosen.any(func(k): return k.distance_to(c) < 14.0):
				continue
			var level := true
			for d in [Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, 1.2), Vector3(0, 0, -1.2)]:
				var q := NavigationServer3D.map_get_closest_point(map, c + d + Vector3(0, 1.0, 0))
				if Vector2(q.x - c.x - d.x, q.z - c.z - d.z).length() > 0.3 or absf(q.y - c.y) > 0.35:
					level = false
			if not level:
				continue
			var sq := PhysicsShapeQueryParameters3D.new()
			var s := SphereShape3D.new()
			s.radius = 1.6
			sq.shape = s
			sq.transform = Transform3D(Basis(), c + Vector3(0, 1.8, 0))
			sq.collision_mask = 1 | 4
			if not space.intersect_shape(sq, 1).is_empty():
				continue
			# open sky above (the crown and the fruit need room): nothing in 4 m straight up
			var up := PhysicsRayQueryParameters3D.create(c + Vector3(0, 0.5, 0), c + Vector3(0, 4.5, 0), 1 | 4)
			if not space.intersect_ray(up).is_empty():
				continue
			if NavigationServer3D.map_get_path(map, start, c, true).is_empty():
				continue
			var path := NavigationServer3D.map_get_path(map, start, c, true)
			if path[path.size() - 1].distance_to(c) > 0.6:
				continue
			chosen.append(c)
		found += chosen.size()
		var out := chosen.map(func(c): return [snappedf(c.x, 0.1), snappedf(c.z, 0.1)])
		print("[fruitspots] %s" % JSON.stringify({"area": a, "spots": out}))
	t._check(found >= AREAS.size() * 2 and not errors, "spots found (%d)" % found)
