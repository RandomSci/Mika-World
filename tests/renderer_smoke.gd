extends SceneTree
# Minimal Forward+ smoke test: lit PBR sphere, shadows, SSAO, glow. Prints adapter info and FPS, saves a screenshot.
var frames := 0
var t0 := 0
func _init():
	var root3d := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.4, 0.5)
	env.ssao_enabled = true
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new(); we.environment = env; root3d.add_child(we)
	var sun := DirectionalLight3D.new(); sun.shadow_enabled = true; sun.rotation_degrees = Vector3(-45, 30, 0); root3d.add_child(sun)
	var mi := MeshInstance3D.new(); mi.mesh = SphereMesh.new(); root3d.add_child(mi)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10, 10); floor.mesh = pm; floor.position.y = -1; root3d.add_child(floor)
	var cam := Camera3D.new(); cam.position = Vector3(0, 1, 4); root3d.add_child(cam); 
	root.add_child(root3d)
	cam.look_at(Vector3.ZERO)
	print("RENDERER ", RenderingServer.get_current_rendering_driver_name(), " / ", RenderingServer.get_current_rendering_method())
	print("ADAPTER ", RenderingServer.get_video_adapter_name(), " | ", RenderingServer.get_video_adapter_vendor(), " | API ", RenderingServer.get_video_adapter_api_version())
func _process(_d):
	frames += 1
	if frames == 30: t0 = Time.get_ticks_msec()
	if frames == 330:
		var dt := (Time.get_ticks_msec() - t0) / 300.0
		print("SMOKE frame_ms=%.2f fps=%.1f" % [dt, 1000.0 / dt])
		root.get_texture().get_image().save_png("res://screenshots/smoke_forward_plus.png")
		quit()
	return false
