extends SceneTree
## Render a turntable-style preview of models (front + 3/4) to PNG: godot --path . -s tools/preview_models.gd -- out.png model1.glb ...
func _init():
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var paths := args.slice(1)
	var vp := SubViewport.new()
	vp.size = Vector2i(400 * paths.size(), 520)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var x := 0.0
	var max_h := 0.0
	for p in paths:
		var n: Node3D = (load(p) as PackedScene).instantiate()
		vp.add_child(n)
		await process_frame
		var top := 0.0
		var sk: Skeleton3D = n.find_child("*", true, false) as Skeleton3D
		for skn in n.find_children("*", "Skeleton3D", true, false):
			var skel: Skeleton3D = skn
			for bi in skel.get_bone_count():
				top = maxf(top, (skel.global_transform * skel.get_bone_global_pose(bi)).origin.y)
		var s := 1.0 / maxf(top, 0.01)
		n.scale = Vector3.ONE * s
		n.position = Vector3(x, 0, 0)
		print("MODEL ", p, " height_by_bones=", snappedf(top, 0.001))
		n.rotation.y = 0.5
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
		if ap:
			for a in ap.get_animation_list():
				if a.ends_with("Idle") or a.ends_with("Swimming_Normal") or a.ends_with("Female_Idle"):
					ap.play(a)
					break
		x += 1.2
	cam.size = 1.25
	cam.position = Vector3((x - 1.2) * 0.5, 0.6, 4)
	cam.size = maxf(1.25, x * 0.42)
	for i in 10:
		await process_frame
	vp.get_texture().get_image().save_png(out)
	quit()
