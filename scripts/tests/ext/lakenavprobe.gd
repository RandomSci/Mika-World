extends RefCounted
## --mktest=lakenavprobe: where the lake path's navmesh really reaches (the first lake dance run: "unreachable, nearest
## walkable point 9 m from the circle"). Builds the path as LakeWaterDance does, bakes, prints the closest navmesh
## points along it and the colliders under it. No dance.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("lake nav probe")
	await t._hold_all()
	main.travel.cancel("lake nav probe")
	if main.streaming.current_id != "lantern_lake":
		await main.streaming.travel("lantern_lake", main.characters["mika"])
	await t._wait(2.0)
	var lwd: LakeWaterDance = LakeWaterDance.instance
	var lake: Node3D = lwd._lake()
	var area = main.streaming.current
	print("[lakenav] area at %s, lake at %s, nav_aabb %s" % [str(area.global_position), str(lake.global_position), str(area.nav_aabb)])
	var lane: Dictionary = lwd._lane(lake, area)
	print("[lakenav] lane %s" % str(lane))
	for z in range(-12, 16, 2):
		print("[lakenav]   h(-1.5, %d) = %.2f" % [z, float(area.h(-1.5, float(z)))])
	var path := WaterPath.new()
	lake.add_child(path)
	path.build(lane.shore - lane.fwd * 0.4, LakeWaterDance.SPOT, LakeWaterDance.RADIUS)
	path.set_solid(true)
	for c in path.body.get_children():
		print("[lakenav] collider %s at %s (global %s) %s" % [c.name, str(c.position), str((c as Node3D).global_position), str((c as CollisionShape3D).shape)])
	await lwd._rebake(area, true)
	print("[lakenav] baked with path, nav_aabb %s" % str(area.nav_aabb))
	var map: RID = main.characters["mika"].get_world_3d().navigation_map
	for z in range(-12, 16, 1):
		var p := lake.to_global(Vector3(-1.5, 0.06, float(z)))
		var q := NavigationServer3D.map_get_closest_point(map, p)
		print("[lakenav]   z %d: closest %s (%.2f m away)" % [z, str(lake.to_local(q)), q.distance_to(p)])
	var space := lake.get_world_3d().direct_space_state
	for z in [-9, -4, 0, 4, 8]:
		var qr := PhysicsRayQueryParameters3D.create(lake.to_global(Vector3(-1.5, 3.0, float(z))), lake.to_global(Vector3(-1.5, -3.0, float(z))), 1)
		var hit := space.intersect_ray(qr)
		print("[lakenav]   ray down at z %d: %s" % [z, str(hit.get("collider")) + " y " + str(lake.to_local(hit.position).y if not hit.is_empty() else "-")])
	await lwd._rebake(area, false)
	path.queue_free()
	t._check(true, "probe printed")
