extends SceneTree
func _init():
	for f in DirAccess.get_files_at("res://assets/animations/mixamo"):
		if not f.ends_with(".fbx"): continue
		var root: Node = load("res://assets/animations/mixamo/" + f).instantiate()
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		var meshes = root.find_children("*", "MeshInstance3D", true, false).size()
		var line = "%s skel=%s bones=%d meshes=%d" % [f, root.get_path_to(sk), sk.get_bone_count(), meshes]
		for a in ap.get_animation_list():
			var an: Animation = ap.get_animation(a)
			line += " | anim '%s' len=%.2f tracks=%d t0=%s" % [a, an.length, an.get_track_count(), an.track_get_path(0) if an.get_track_count() else ""]
		print(line)
		if f == "walking.fbx": print("  bones: ", range(min(8, sk.get_bone_count())).map(func(i): return sk.get_bone_name(i)))
		root.free()
	quit()
