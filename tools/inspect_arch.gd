extends SceneTree
func _init():
	var r: Node = load("res://assets/architecture/sanctuary_architecture.glb").instantiate()
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var names := []
		for s in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(s)
			names.append("%s|%s" % [m.resource_name if m else "null", m.get_class() if m else ""])
		print(mi.name, " ", names, " fmt_has_color=", (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0)
	r.free()
	quit()
