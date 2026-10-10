extends SceneTree
func _init():
	for d in DirAccess.get_directories_at("res://assets/polyhaven/models"):
		var path := "res://assets/polyhaven/models/%s/%s_1k.gltf" % [d, d]
		var ps: PackedScene = load(path)
		if ps == null: print("FAIL ", path); continue
		var root: Node3D = ps.instantiate()
		var out := []
		var tris := 0
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			var a: AABB = m.get_aabb()
			var t := 0
			for s in m.mesh.get_surface_count():
				t += m.mesh.surface_get_array_index_len(s) / 3
			tris += t
			out.append("%s pos=%s size=%s tris=%d" % [m.name, str(m.position.snapped(Vector3.ONE * 0.01)), str(a.size.snapped(Vector3.ONE * 0.01)), t])
		print(d, " total_tris=", tris, " meshes=", out.size())
		for o in out.slice(0, 8): print("    ", o)
		root.free()
	quit()
