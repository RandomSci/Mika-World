class_name FaceTest
extends Node
## --facetest: close-up face verification in the current area (use --start=<location>).
## Frames the face from front / three-quarter / side, measures mean face luminance around the
## projected head bone, saves PNGs; repeats at night and mid-cast. Results → <shots>/facetest_<tag>.json

var main: Node
var results := []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RenderProfile.shots_dir))
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _face_point(m: WorldCharacter) -> Vector3:
	var sk := m.skeleton
	var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))
	var fwd := -m.global_transform.basis.z
	return head.origin + Vector3(0, 0.07, 0) + fwd * 0.07


func _measure_and_shoot(tag: String, m: WorldCharacter) -> Dictionary:
	var cam: Camera3D = main.camera_rig.camera
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var fp := _face_point(m)
	var sp := cam.unproject_position(fp)
	var r := int(clampf(1800.0 * 0.05 / cam.global_position.distance_to(fp), 6, 120))
	var sum := 0.0
	var n := 0
	for y in range(int(sp.y) - r, int(sp.y) + r, 2):
		for x in range(int(sp.x) - r, int(sp.x) + r, 2):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				var c := img.get_pixel(x, y)
				sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				n += 1
	var name := "%s_%s_%s" % [RenderProfile.options.get("facetag", "face"), WorldState.current_location, tag]
	var path := "%s/%s.png" % [RenderProfile.shots_dir, name]
	img.save_png(path)
	var res := {"shot": name, "face_luminance": snappedf(sum / maxi(n, 1), 0.001), "sample_px": n, "night": WorldState.night}
	results.append(res)
	print("[facetest] ", JSON.stringify(res))
	return res


func _frame(m: WorldCharacter, angle_deg: float, dist := 0.85) -> void:
	var fp := _face_point(m)
	var fwd := -m.global_transform.basis.z
	var dir := fwd.rotated(Vector3.UP, deg_to_rad(angle_deg))
	main.camera_rig.set_shot(fp + dir * dist + Vector3(0, 0.03, 0), fp, 35.0)


func _run() -> void:
	var m: WorldCharacter = main.characters["mika"]
	main.player.enabled = false
	await _wait(3.0)
	for night in [false, true]:
		WorldState.night = night
		main.world.set_night(night)
		await _wait(0.6)
		for a in [0.0, 40.0, 85.0]:
			_frame(m, a)
			await _wait(0.5)
			await _measure_and_shoot("%s_%d" % ["night" if night else "day", int(a)], m)
	WorldState.night = false
	main.world.set_night(false)
	# during casting: face framed from the front three-quarter while the orb lights her
	var spell = m.cast_spell(ArcaneOrbSpell, "prepare_and_cast")
	if spell:
		for f in [0.45, 0.62]:
			while is_instance_valid(spell) and spell.t < spell.duration * f:
				_frame(m, 30.0, 1.0)
				await get_tree().process_frame
			await _measure_and_shoot("cast_%d" % int(f * 100), m)
		while is_instance_valid(spell):
			await get_tree().process_frame
	var f := FileAccess.open("%s/facetest_%s_%s.json" % [RenderProfile.shots_dir, RenderProfile.options.get("facetag", "face"), WorldState.current_location], FileAccess.WRITE)
	f.store_string(JSON.stringify({"profile": RenderProfile.profile, "legacy_mtoon": RenderProfile.options.has("mtoon-legacy"), "results": results}, "  "))
	print("[facetest] done")
	get_tree().quit()
