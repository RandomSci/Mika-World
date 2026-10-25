extends RefCounted
## --mktest=villageblock (25 Oct live: Mika stuck 43 times at (-10.6, 0, 4.4) in the village square; stuckprobe: the walk
## east is blocked by an unnamed StaticBody3D at (-10, 0.2, 4.5)). What that body is. Marks "[villageblock] ...".

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	if main.streaming.current_id != "village":
		await main.streaming.travel("village", main.characters["mika"])
	await t._wait(2.0)
	var area: Node3D = main.streaming.current
	for b in area.find_children("*", "StaticBody3D", true, false):
		var sb := b as StaticBody3D
		if sb.global_position.distance_to(Vector3(-10.0, 0.2, 4.5)) > 1.5:
			continue
		print("[villageblock] %s layer %d at %s rot %s, parent %s, meta %s" % [sb.name, sb.collision_layer, str(sb.global_position), str(sb.global_rotation_degrees.snapped(Vector3.ONE)), sb.get_parent().name, str(sb.get_meta_list())])
		for s in sb.get_children():
			if s is CollisionShape3D:
				var sh = (s as CollisionShape3D).shape
				var info := sh.get_class()
				if sh is BoxShape3D: info += " size %s" % str(sh.size)
				elif sh is CylinderShape3D: info += " r %.2f h %.2f" % [sh.radius, sh.height]
				elif sh is CapsuleShape3D: info += " r %.2f h %.2f" % [sh.radius, sh.height]
				elif sh is SphereShape3D: info += " r %.2f" % sh.radius
				elif sh is ConvexPolygonShape3D or sh is ConcavePolygonShape3D: info += " aabb %s" % str((s as CollisionShape3D).get_debug_mesh().get_aabb() if (s as CollisionShape3D).has_method("get_debug_mesh") else "-")
				print("[villageblock]   shape %s at %s" % [info, str((s as CollisionShape3D).global_position)])
	for m in area.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var bb := mi.global_transform * mi.get_aabb()
		if bb.grow(0.3).has_point(Vector3(-10.0, 0.3, 4.5)):
			print("[villageblock] mesh %s (%s) aabb %s" % [mi.name, mi.get_parent().name, str(bb)])
	for m in area.find_children("*", "MultiMeshInstance3D", true, false):
		print("[villageblock] multimesh %s parent %s" % [m.name, m.get_parent().name]) if (m as Node3D).global_position.distance_to(Vector3(-10, 0, 4.5)) < 30 else null
	t._check(true, "listed")
