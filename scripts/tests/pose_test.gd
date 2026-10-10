class_name PoseTest
extends Node
## --posetest: sitting quality check. Mika sits on the garden Still Stone and the Watchpoint bench;
## mid-sit the test measures pelvis height vs the seat top, both feet vs the ground, how far the
## pelvis is from the seat centre, and captures close-ups (side, front three-quarter, back three-quarter,
## front). Results → <shots>/posetest/pose_<tag>.json

var main: Node
var results := {}
var dir := ""


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/posetest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _bone(m: WorldCharacter, name: String) -> Vector3:
	var sk := m.skeleton
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(name))).origin


func _shot(tag: String) -> String:
	await get_tree().process_frame
	await get_tree().process_frame
	var path := "%s/%s_%s.png" % [dir, String(RenderProfile.options.get("posetag", "pose")), tag]
	get_viewport().get_texture().get_image().save_png(path)
	return path


func _run() -> void:
	var m: WorldCharacter = main.characters["mika"]
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	await _wait(2.5)
	var rig: ThirdPersonCamera = main.camera_rig
	for id in ["garden_meditate", "watchpoint_rest"]:
		var it: Interactable = main.world.interactables[id]
		m.global_position = it.approach_point() + Vector3(0, 0.1, 0) + (it.approach_point() - it.global_position).normalized() * 0.8
		await _wait(0.5)
		var job := func(): await it.perform(m)
		job.call()
		await _wait(0.6 + 0.35 + 2.6)  # look/settle + into the pose
		var seat_top: float = it.seat_body.global_position.y + (it.seat_body.get_child(0).shape as BoxShape3D).size.y * 0.5
		var hips := _bone(m, "Hips")
		var lf := _bone(m, "LeftFoot")
		var rf := _bone(m, "RightFoot")
		var lt := _bone(m, "LeftToes") if m.skeleton.find_bone("LeftToes") != -1 else lf
		var ground: float = m.global_position.y
		var seat_c: Vector3 = it.seat_body.global_position
		var fwd := -m.global_transform.basis.z
		var rec := {
			"hips_above_seat_m": snappedf(hips.y - seat_top, 0.01),
			"hips_behind_root_m": snappedf(-(hips - m.global_position).dot(fwd), 0.01),
			"hips_to_seat_centre_horizontal_m": snappedf(Vector2(hips.x - seat_c.x, hips.z - seat_c.z).length(), 0.01),
			"left_foot_above_ground_m": snappedf(lf.y - ground, 0.01), "right_foot_above_ground_m": snappedf(rf.y - ground, 0.01),
			"left_toes_above_ground_m": snappedf(lt.y - ground, 0.01),
			"knee_gap_m": snappedf(_bone(m, "LeftLowerLeg").distance_to(_bone(m, "RightLowerLeg")), 0.01),
			"feet_gap_m": snappedf(lf.distance_to(rf), 0.01),
			"knee_gap_after_correction_m": snappedf(m.pose_adjust.last_knee_gap, 0.01),
		}
		var head := _bone(m, "Head")
		var right := Vector3(-fwd.z, 0, fwd.x)
		for v in [["side", right * 2.2 + Vector3(0, -0.35, 0)], ["front34", (fwd * 1.9 + right * 1.1) + Vector3(0, -0.3, 0)],
				["back34", (-fwd * 1.8 + right * 1.2) + Vector3(0, 0.0, 0)], ["front", fwd * 2.0 + Vector3(0, -0.35, 0)]]:
			var look := hips.lerp(head, 0.35)
			rig.set_shot(look + v[1], look, 40.0)
			rec["shot_" + v[0]] = await _shot("%s_%s" % [id, v[0]])
		results[id] = rec
		print("[posetest] ", id, " ", JSON.stringify(rec))
		rig.clear_shot()
		while it.busy:
			await get_tree().process_frame
		await _wait(0.8)
		results[id]["after_stand_overlap"] = _overlaps(m)
	var f := FileAccess.open("%s/pose_%s.json" % [dir, String(RenderProfile.options.get("posetag", "pose"))], FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("[posetest] done")
	get_tree().quit()


func _overlaps(m: WorldCharacter) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.exclude = [m.get_rid()]
	q.transform = Transform3D(Basis.IDENTITY, m.global_position + Vector3(0, 0.85, 0))
	return not m.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
