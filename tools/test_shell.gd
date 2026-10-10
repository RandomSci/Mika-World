extends SceneTree
func _init():
	var m := Kit.cave_shell(Vector3(26, 11, 30), 31, 0.22, Callable(), 48, 24)
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var inward := 0
	var outward := 0
	for i in range(0, v.size(), 3):
		var n := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		if n.dot(v[i] + v[i + 1] + v[i + 2]) > 0: outward += 1
		else: inward += 1
	print("tris=", v.size() / 3, " aabb=", m.get_aabb(), " inward=", inward, " outward=", outward, " idx=", a[Mesh.ARRAY_INDEX] != null)
	quit()
