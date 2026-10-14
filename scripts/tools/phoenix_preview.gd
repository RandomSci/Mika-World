extends Node3D
## Oriel preview: her real rig in a plain lit room, every clip sampled into a contact sheet, measurements
## written to JSON (clip lengths, wingspan spread vs folded, head height). Proof the animation assets exist
## and play in Godot, independent of the world.
##   godot --path . res://scenes/tools/phoenix_preview.tscn -- --out=res://screenshots/phoenix --form=true [--clips=idle,fly]

var rig: PhoenixTrueRig
var cam: Camera3D
var report := {}


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.8, 0.85, 1.0)
	add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.31, 0.34)
	floor_mi.material_override = fm
	add_child(floor_mi)
	rig = PhoenixTrueRig.new()
	add_child(rig)
	rig.build()
	cam = Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	cam.current = true
	_run.call_deferred()


func _frame(view: String) -> void:
	match view:
		"side":
			cam.global_position = Vector3(8.5, 2.1, 0.3)
			cam.look_at(Vector3(0, 1.5, 0.2))
		"front":
			cam.global_position = Vector3(-4.6, 2.6, 7.6)
			cam.look_at(Vector3(0, 1.5, 0.0))
		"back":
			cam.global_position = Vector3(5.0, 3.6, -7.0)
			cam.look_at(Vector3(0, 1.5, 0.0))
		"head":
			cam.global_position = Vector3(1.7, 2.9, 3.4)
			cam.look_at(rig.head_point())
		"wide":
			cam.global_position = Vector3(-7.5, 3.5, 9.0)
			cam.look_at(Vector3(0, 1.6, 0.0))
		"top":
			cam.global_position = Vector3(0.01, 11.0, 0.5)
			cam.look_at(Vector3(0, 1.4, 0.4))
		_:
			cam.global_position = Vector3(-5.4, 2.8, 6.4)
			cam.look_at(Vector3(0, 1.5, 0.0))


func _grab() -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	var im := get_viewport().get_texture().get_image()
	im.convert(Image.FORMAT_RGB8)
	return im


func _run() -> void:
	await get_tree().create_timer(0.8).timeout
	var out: String = RenderProfile.options.get("out", "res://screenshots/phoenix")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var only := String(RenderProfile.options.get("clips", ""))
	var clips: Array = rig.player.get_animation_list() if only == "" else only.split(",")
	report["clips"] = {}
	report["bones"] = rig.skeleton.get_bone_count()
	report["meshes"] = rig.model.find_children("*", "MeshInstance3D", true, false).size()
	# stills of the resting pose
	rig.play_clip("idle", 0.0, 1.0, true)
	rig.player.seek(0.0, true)
	for v in ["front", "side", "back", "head", "top"]:
		_frame(v)
		var im: Image = await _grab()
		im.save_png("%s/still_%s.png" % [out, v])
	rig.player.pause()
	var tips := rig.wingtips()
	report["span_folded_m"] = snappedf((tips[0] - tips[1]).length(), 0.01)
	rig.play_clip("wing_spread", 0.0, 1.0, false)
	rig.player.seek(1.15, true)
	rig.skeleton.force_update_all_bone_transforms()
	tips = rig.wingtips()
	report["span_spread_m"] = snappedf((tips[0] - tips[1]).length(), 0.01)
	report["head_height_m"] = snappedf(rig.head_point().y, 0.01)
	_frame("front")
	var im2: Image = await _grab()
	im2.save_png("%s/still_spread.png" % out)
	var n := 6
	for clip in clips:
		var c := String(clip)
		var anim := rig.player.get_animation(c)
		var view := "front"
		if c in ["fly", "glide", "hover", "takeoff", "land", "bank_left", "bank_right"]:
			view = "wide"
		elif c in ["preen", "look", "call", "stretch"]:
			view = "side"
		var w := 420
		var h := 420
		var sheet := Image.create(w * n, h, false, Image.FORMAT_RGB8)
		rig.play_clip(c, 0.0, 1.0, false)
		for k in n:
			var t := anim.length * k / (n - 1)
			rig.player.seek(t, true)
			rig.skeleton.force_update_all_bone_transforms()
			_frame(view)
			var im: Image = await _grab()
			var side := im.get_height()
			var crop := im.get_region(Rect2i(im.get_width() / 2 - side / 2, 0, side, side))
			crop.resize(w, h, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i(k * w, 0))
		sheet.save_png("%s/clip_%s.png" % [out, c])
		report.clips[c] = {"length_s": snappedf(anim.length, 0.01), "tracks": anim.get_track_count()}
		print("[phoenix] clip ", c, " ", report.clips[c])
	var f := FileAccess.open(out + "/phoenix_preview.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[phoenix] preview done ", JSON.stringify({"bones": report.bones, "meshes": report.meshes, "span_spread_m": report.span_spread_m, "span_folded_m": report.span_folded_m, "head_m": report.head_height_m, "clips": report.clips.size()}))
	get_tree().quit()
