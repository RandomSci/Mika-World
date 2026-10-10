extends Node3D
## Animation preview + quality metrics on Mika's real VRM skeleton.
## godot --path . res://scenes/tools/anim_preview.tscn -- --clipdir=res://assets/animations/mixamo_sword --out=res://screenshots/sword
## For every clip: retarget (same path as WorldCharacter), sample 6 poses into a contact sheet, and measure
## root drift, two-hand grip spread, hand-in-torso penetration, joint angular-velocity spikes, foot sliding.

var mika: WorldCharacter
var cam: Camera3D
var report := {}


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.33, 0.36)
	floor.material_override = fm
	add_child(floor)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12, 0.2, 12)
	cs.shape = bs
	cs.position.y = -0.1
	body.add_child(cs)
	add_child(body)
	mika = WorldCharacter.new()
	add_child(mika)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	mika.anim_tree.active = false
	mika.set_physics_process(false)
	if RenderProfile.options.has("swordshots"):
		await _sword_shots()
		return
	if RenderProfile.options.has("gripcal"):
		await _grip_calibration()
		return
	var dir: String = RenderProfile.options.get("clipdir", "res://assets/animations/mixamo_sword")
	var out: String = RenderProfile.options.get("out", "res://screenshots/sword")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var lib := AnimationLibrary.new()
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".fbx"))
	files.sort()
	var skel_path := String(mika.avatar.get_path_to(mika.skeleton))
	for f in files:
		var src: Node = load(dir + "/" + f).instantiate()
		var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
		var name := "mixamo_com" if ap.has_animation("mixamo_com") else ap.get_animation_list()[0]
		var anim: Animation = ap.get_animation(name).duplicate(true)
		src.free()
		var hips_track := anim.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
		var drift := 0.0
		if hips_track >= 0 and anim.track_get_key_count(hips_track) > 1:
			var a: Vector3 = anim.track_get_key_value(hips_track, 0)
			var b: Vector3 = anim.track_get_key_value(hips_track, anim.track_get_key_count(hips_track) - 1)
			drift = Vector2(b.x - a.x, b.z - a.z).length()
		mika._retarget_paths(anim, skel_path, true)
		lib.add_animation(f.get_basename(), anim)
		report[f.get_basename()] = {"length_s": snappedf(anim.length, 0.01), "tracks": anim.get_track_count(), "root_drift_m": snappedf(drift, 0.01)}
	mika.body_player.add_animation_library("prev", lib)
	var sk := mika.skeleton
	var bones := {}
	for b in ["Hips", "LeftHand", "RightHand", "UpperChest", "Spine", "LeftFoot", "RightFoot", "Head"]:
		bones[b] = sk.find_bone(b)
	for clip in report:
		var anim: Animation = lib.get_animation(clip)
		mika.body_player.play("prev/" + clip)
		mika.body_player.pause()
		var n := 48
		var grip := []
		var min_torso := 9.0
		var hip_y := []
		var prev_rot := {}
		var max_ang_vel := 0.0
		var foot_slide := 0.0
		var prev_feet := {}
		var shots := []
		for i in n:
			var t := anim.length * i / (n - 1)
			mika.body_player.seek(t, true)
			sk.force_update_all_bone_transforms()
			var gp := func(b: String) -> Vector3: return sk.get_bone_global_pose(bones[b]).origin
			var lh: Vector3 = gp.call("LeftHand")
			var rh: Vector3 = gp.call("RightHand")
			grip.append(lh.distance_to(rh))
			var chest: Vector3 = gp.call("UpperChest")
			var spine: Vector3 = gp.call("Spine")
			for h in [lh, rh]:
				# distance to the torso segment Spine→UpperChest
				var ab := chest - spine
				var tt := clampf((h - spine).dot(ab) / ab.length_squared(), 0.0, 1.0)
				min_torso = minf(min_torso, h.distance_to(spine + ab * tt))
			hip_y.append(gp.call("Hips").y)
			for b in ["LeftHand", "RightHand", "Head", "Spine"]:
				var q := sk.get_bone_global_pose(bones[b]).basis.get_rotation_quaternion()
				if prev_rot.has(b) and i > 0:
					var ang: float = (prev_rot[b] as Quaternion).angle_to(q) / (anim.length / (n - 1))
					max_ang_vel = maxf(max_ang_vel, ang)
				prev_rot[b] = q
			for ft in ["LeftFoot", "RightFoot"]:
				var p: Vector3 = gp.call(ft)
				if prev_feet.has(ft) and p.y < 0.13 and (prev_feet[ft] as Vector3).y < 0.13:
					foot_slide += Vector2(p.x - prev_feet[ft].x, p.z - prev_feet[ft].z).length()
				prev_feet[ft] = p
		var mean := 0.0
		for g in grip: mean += g
		mean /= grip.size()
		var sd := 0.0
		for g in grip: sd += (g - mean) * (g - mean)
		sd = sqrt(sd / grip.size())
		var r: Dictionary = report[clip]
		r["grip_mean_m"] = snappedf(mean, 0.01)
		r["grip_sd_m"] = snappedf(sd, 0.01)
		r["min_hand_to_torso_m"] = snappedf(min_torso, 0.01)
		r["hip_y_range_m"] = [snappedf(hip_y.min(), 0.01), snappedf(hip_y.max(), 0.01)]
		r["max_angular_velocity_deg_s"] = snappedf(rad_to_deg(max_ang_vel), 1.0)
		r["planted_foot_slide_m"] = snappedf(foot_slide, 0.01)
		var flags := []
		if mean > 0.35 and clip.contains("sword") and not clip.contains("cast") and not clip.contains("kick"):
			flags.append("hands far apart for a two-handed grip")
		if min_torso < 0.09:
			flags.append("hand passes through torso")
		if rad_to_deg(max_ang_vel) > 1400.0:
			flags.append("very fast joint rotation (possible pop)")
		if r.root_drift_m > 0.3:
			flags.append("root motion %.2f m (made in-place)" % r.root_drift_m)
		r["flags"] = flags
		# contact sheet: 6 poses, three-quarter front view
		var imgs := []
		for k in 6:
			mika.body_player.seek(anim.length * k / 5.0, true)
			sk.force_update_all_bone_transforms()
			cam.global_position = Vector3(1.9, 1.35, -2.6)
			cam.look_at(Vector3(0, 0.95, 0))
			await get_tree().process_frame
			await get_tree().process_frame
			imgs.append(get_viewport().get_texture().get_image())
		var w := 360
		var h := 400
		var sheet := Image.create(w * 6, h, false, Image.FORMAT_RGB8)
		for k in 6:
			var im: Image = imgs[k]
			im.convert(Image.FORMAT_RGB8)
			var crop := im.get_region(Rect2i(im.get_width() / 2 - im.get_height() * 9 / 20, 0, im.get_height() * 9 / 10, im.get_height()))
			crop.resize(w, h)
			sheet.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i(k * w, 0))
		sheet.save_png("%s/%s.png" % [out, clip])
		print("[preview] ", clip, " ", JSON.stringify(r))
	var f := FileAccess.open(out + "/sword_clip_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[preview] done ", report.size(), " clips")
	get_tree().quit()


## Measure the two-handed grip axis in the RightHand bone frame (blade must pass through both fists).
func _grip_calibration() -> void:
	var sl := SwordLayer.attach(mika)
	await get_tree().process_frame
	var sk := mika.skeleton
	var rh_i := sk.find_bone("RightHand")
	var lh_i := sk.find_bone("LeftHand")
	var rmid := sk.find_bone("RightMiddleProximal")
	var acc_dir := Vector3.ZERO
	var acc_mid := Vector3.ZERO
	var acc_palm := Vector3.ZERO
	var n := 0
	for role in ["idle", "walk", "slash", "attack", "block"]:
		var anim := mika.body_player.get_animation("sw/" + role)
		mika.body_player.play("sw/" + role)
		mika.body_player.pause()
		for i in 12:
			mika.body_player.seek(anim.length * i / 11.0, true)
			sk.force_update_all_bone_transforms()
			var rh := sk.get_bone_global_pose(rh_i)
			var lh := sk.get_bone_global_pose(lh_i)
			if rh.origin.distance_to(lh.origin) > 0.22:
				continue  # not in a two-handed grip at this instant
			var inv := rh.basis.inverse()
			acc_dir += inv * (rh.origin - lh.origin).normalized()
			acc_mid += inv * ((rh.origin + lh.origin) * 0.5 - rh.origin)
			if rmid >= 0:
				acc_palm += inv * ((sk.get_bone_global_pose(rmid).origin + rh.origin) * 0.5 - rh.origin)
			n += 1
	acc_dir = (acc_dir / n).normalized()
	print("[gripcal] samples=", n, " blade_dir_local=", acc_dir, " grip_mid_local=", acc_mid / n, " palm_local=", acc_palm / n)
	get_tree().quit()


func _sword_shots() -> void:
	var sl := SwordLayer.attach(mika)
	await get_tree().process_frame
	sl.blade_root.visible = true
	sl._glow(0.6)
	var out: String = RenderProfile.options.get("out", "res://screenshots/sword")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for role in ["idle", "slash", "attack", "power_up", "block", "slash_heavy"]:
		var anim := mika.body_player.get_animation("sw/" + role)
		mika.body_player.play("sw/" + role)
		mika.body_player.pause()
		var imgs := []
		for k in 5:
			mika.body_player.seek(anim.length * k / 4.0, true)
			mika.skeleton.force_update_all_bone_transforms()
			cam.global_position = Vector3(2.2, 1.4, -2.4)
			cam.look_at(Vector3(0, 1.0, 0))
			await get_tree().process_frame
			await get_tree().process_frame
			imgs.append(get_viewport().get_texture().get_image())
		var w := 380
		var h := 420
		var sheet := Image.create(w * 5, h, false, Image.FORMAT_RGB8)
		for k in 5:
			var im: Image = imgs[k]
			im.convert(Image.FORMAT_RGB8)
			var crop := im.get_region(Rect2i(im.get_width() / 2 - im.get_height() * 9 / 20, 0, im.get_height() * 9 / 10, im.get_height()))
			crop.resize(w, h)
			sheet.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i(k * w, 0))
		sheet.save_png("%s/withsword_%s.png" % [out, role])
	print("[preview] sword shots done")
	get_tree().quit()
