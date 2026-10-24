extends RefCounted
## --mktest=treeprobe: the real tree meshes' surfaces and extents (for hanging fruit in their crowns). No GPU.


static func run(t) -> void:
	for id in ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_5", "DeadTree_1"]:
		var m: ArrayMesh = NatureKit.mesh(id, "common")
		print("[treeprobe] %s aabb %s surfaces %d" % [id, str(m.get_aabb()), m.get_surface_count()])
		for i in m.get_surface_count():
			var a := m.surface_get_arrays(i)
			var mat := m.surface_get_material(i)
			print("[treeprobe]   %d name '%s' verts %d mat %s transp %s" % [i, m.surface_get_name(i), (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), mat.get_class() if mat else "-", str(mat.get("transparency")) if mat else "-"])
	t._check(true, "printed")
