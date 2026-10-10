extends SceneTree
func _init():
	var ps: PackedScene = load("res://assets/characters/mika/Mika.vrm")
	var root: Node = ps.instantiate()
	_walk(root, 0)
	var sk: Skeleton3D = root.find_child("GeneralSkeleton", true, false)
	if sk:
		print("SKELETON bones=", sk.get_bone_count(), " first:", sk.get_bone_name(0), " profile-like names: ", [sk.find_bone("Hips"), sk.find_bone("LeftHand"), sk.find_bone("RightHand"), sk.find_bone("Head")])
		var hips = sk.find_bone("Hips")
		print("hips rest global y=", sk.get_bone_global_rest(hips).origin, " head=", sk.get_bone_global_rest(sk.find_bone("Head")).origin)
	var ap: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if ap: print("ANIMS ", ap.get_animation_list())
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var mats = []
		for s in m.mesh.get_surface_count():
			var mat = m.get_active_material(s)
			mats.append(mat.get_class() + ":" + (str(mat.shader.resource_path.get_file()) if mat is ShaderMaterial and mat.shader else ""))
		print("MESH ", m.name, " surfaces=", m.mesh.get_surface_count(), " aabb=", m.get_aabb(), " ", mats.slice(0, 6))
	quit()
func _walk(n: Node, d: int):
	if d < 4: print("  ".repeat(d), n.name, " [", n.get_class(), "]", (" script=" + n.get_script().resource_path.get_file()) if n.get_script() else "")
	for c in n.get_children(): _walk(c, d + 1)
