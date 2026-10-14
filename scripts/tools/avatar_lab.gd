extends Node3D
## AVATAR LAB (level-based appearances): the characters' appearance stages side by side under the Whispering Woods'
## light, without loading the world. Line-ups (old vs new), face close-ups across expressions, a walk (springs in
## motion), and measurements per avatar (triangles, surfaces/draw calls, MToon materials, expressions bound, spring
## bones, load time). Writes PNGs + avatar_lab.json.
##   godot --path . res://scenes/tools/avatar_lab.tscn -- --save-path=user://test_regress_lab.json --out=res://screenshots/avatar_lab
##     [--lab=lineup|faces|walk|all]

var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var out := "res://screenshots/avatar_lab"
var report := {}
const AVATARS := {
	"mika_old": ["mika", "res://assets/characters/mika/Mika.vrm"],
	"mika_celestial": ["mika", "res://assets/characters/mika/stages/l01_celestial/MikaCelestial_hair2.vrm"],
	"luna_old": ["luna", "res://assets/characters/luna/forms/Luna_Level01.vrm"],
	"luna_oracle": ["luna", "res://assets/characters/luna/stages/l01_oracle/LunaOracle_hair2.vrm"],
}


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = load("res://assets/polyhaven/hdris/nature_reserve_forest/nature_reserve_forest_2k.hdr")
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.88
	env.ssao_enabled = not RenderProfile.options.has("no-ssao")
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 150, 0)
	sun.light_energy = 3.1
	sun.light_color = Color(1, 0.9, 0.74)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	floor_mi.material_override = RealKit.stone_mat("mossy_stone_wall", false)
	add_child(floor_mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	out = String(RenderProfile.options.get("out", out))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Progression.load_data()
	_run.call_deferred()


func _look(pos: Vector3, at: Vector3, fov := 40.0) -> void:
	cam.global_position = pos
	cam.look_at(at)
	cam.fov = fov


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("[avatar_lab] wrote ", name)


func _spawn(key: String, at: Vector3, yaw := 0.0) -> WorldCharacter:
	var spec: Array = AVATARS[key]
	var t0 := Time.get_ticks_msec()
	var c := WorldCharacter.new()
	c.name = key
	c.character_id = spec[0]
	c.display_name = key
	c.avatar_path = spec[1]
	add_child(c)
	c.global_position = at
	c.rotation.y = yaw
	c.apply_light_balance(sun.light_energy, env.ambient_light_energy)
	report[key] = _measure(c)
	report[key]["load_ms"] = Time.get_ticks_msec() - t0
	return c


func _measure(c: WorldCharacter) -> Dictionary:
	var tris := 0
	var surfaces := 0
	var mtoon := 0
	var mats := 0
	var meshes := 0
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		meshes += 1
		for si in m.mesh.get_surface_count():
			surfaces += 1
			var arr := m.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() / 3) if idx else (arr[Mesh.ARRAY_VERTEX].size() / 3)
			var mat := m.get_active_material(si)
			if mat:
				mats += 1
				if mat is ShaderMaterial and String((mat as ShaderMaterial).shader.resource_path).to_lower().contains("mtoon"):
					mtoon += 1
	var springs := 0
	for n in c.avatar.find_children("*", "", true, false):
		if String(n.get_class()).contains("Spring") or String(n.name).to_lower().contains("spring"):
			springs += 1
	var sec = c.avatar.get("vrm_secondary")
	var face_bound: int = c.face.bound_count() if c.face and c.face.has_method("bound_count") else -1
	return {"triangles": tris, "meshes": meshes, "surfaces": surfaces, "materials": mats, "mtoon": mtoon,
		"spring_nodes": springs, "has_secondary": sec != null, "face_controller": c.face != null, "face_components": face_bound,
		"bones": c.skeleton.get_bone_count() if c.skeleton else 0, "height_m": snappedf(_height(c), 0.01)}


func _height(c: WorldCharacter) -> float:
	var top := 0.0
	for mi in c.avatar.find_children("*", "MeshInstance3D", true, false):
		var bb := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		top = maxf(top, bb.end.y - c.global_position.y)
	return top


func _run() -> void:
	var mode := String(RenderProfile.options.get("lab", "all"))
	if mode in ["lineup", "all"]:
		await _lineup()
	if mode in ["faces", "all"]:
		await _faces()
	if mode in ["walk", "all"]:
		await _walk()
	if mode in ["ears", "all"]:
		await _ears()
	if mode in ["sit", "all"]:
		await _sit()
	if mode in ["body", "all"]:
		await _body()
	var f := FileAccess.open(out + "/avatar_lab.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[avatar_lab] report ", JSON.stringify(report))
	get_tree().quit()


func _lineup() -> void:
	var keys := ["mika_old", "mika_celestial", "luna_old", "luna_oracle"]
	var cs := []
	for i in keys.size():
		cs.append(_spawn(keys[i], Vector3((i - 1.5) * 1.25, 0, 0), 0.0))
	await _wait(2.5)
	_look(Vector3(0, 1.0, 5.6), Vector3(0, 0.88, 0), 40.0)
	await _grab("lineup_front")
	_look(Vector3(3.6, 1.2, 4.2), Vector3(0, 0.9, 0), 42.0)
	await _grab("lineup_34")
	_look(Vector3(0, 1.1, -5.6), Vector3(0, 0.88, 0), 40.0)
	await _grab("lineup_back")
	for c in cs:
		(c as Node).queue_free()
	await _wait(0.5)


func _faces() -> void:
	for key in ["mika_celestial", "luna_oracle"]:
		var c := _spawn(key, Vector3.ZERO, 0.0)
		await _wait(2.0)
		var head := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Head")).origin
		var fwd := -c.global_transform.basis.z
		for e in ["neutral", "happy", "surprised", "sad", "frustrated", "shy"]:
			if c.face:
				for other in ["happy", "surprised", "sad", "frustrated", "shy"]:
					c.face.set_hold(other, 0.0)
				if e != "neutral":
					c.face.set_hold(e, 1.0)
			await _wait(0.8)
			_look(head + fwd * 0.62 + Vector3(0.12, 0.04, 0), head + Vector3(0, 0.02, 0), 32.0)
			await _grab("face_%s_%s" % [key, e])
		_look(head + fwd * 0.55 + c.global_transform.basis.x * 0.42 + Vector3(0, 0.05, 0), head, 34.0)
		await _grab("face_%s_34" % key)
		c.queue_free()
		await _wait(0.4)


func _walk() -> void:
	var m := _spawn("mika_celestial", Vector3(-1.0, 0, 3.0), PI)
	var l := _spawn("luna_oracle", Vector3(1.0, 0, 3.0), PI)
	await _wait(1.5)
	for c in [m, l]:
		(c as WorldCharacter).set_move_input(Vector3(0, 0, -1), false)
	for k in 6:
		await _wait(0.55)
		var mid := (m.global_position + l.global_position) * 0.5
		_look(mid + Vector3(3.4, 1.3, -1.6), mid + Vector3(0, 0.9, 0), 42.0)
		await _grab("walk_%02d" % k)
	for c in [m, l]:
		(c as WorldCharacter).set_move_input(Vector3.ZERO, false)
	await _wait(1.0)
	# turning, then a run
	for c in [m, l]:
		(c as WorldCharacter).set_move_input(Vector3(1, 0, 0), true)
	for k in 3:
		await _wait(0.45)
		var mid := (m.global_position + l.global_position) * 0.5
		_look(mid + Vector3(0, 1.2, 4.2), mid + Vector3(0, 0.9, 0), 46.0)
		await _grab("run_%02d" % k)
	for c in [m, l]:
		(c as WorldCharacter).set_move_input(Vector3.ZERO, false)


func _ears() -> void:
	var c := _spawn("mika_celestial", Vector3.ZERO, 0.0)
	await _wait(2.0)
	report["ears"] = c.ears != null
	for e in ["neutral", "surprised", "sad", "frustrated", "curious", "happy"]:
		if c.face:
			for o in ["surprised", "sad", "frustrated", "curious", "happy"]:
				c.face.set_hold(o, 0.0)
			if e != "neutral":
				c.face.set_hold(e, 1.0)
		await _wait(1.2)
		var head := c.skeleton.global_transform * c.skeleton.get_bone_global_pose(c.skeleton.find_bone("Head")).origin
		var fwd := -c.global_transform.basis.z
		_look(head + fwd * 0.95 + c.global_transform.basis.x * 0.35 + Vector3(0, 0.12, 0), head + Vector3(0, 0.12, 0), 34.0)
		await _grab("ears_%s" % e)
	c.queue_free()


func _sit() -> void:
	var m := _spawn("mika_celestial", Vector3(-0.9, 0, 0), 0.0)
	var l := _spawn("luna_oracle", Vector3(0.9, 0, 0), 0.0)
	await _wait(1.5)
	for c in [m, l]:
		(c as WorldCharacter).play_gesture("sit_ground_enter", 0.3, 0.3)
		(c as WorldCharacter).set_ground_pose("sit", (c as WorldCharacter).animation_length("sit_ground_enter") * 0.9)
	await _wait(2.2)
	for c in [m, l]:
		(c as WorldCharacter).play_gesture("sit_ground_loop", 0.3, 0.6)
	await _wait(1.5)
	_look(Vector3(0, 0.9, -3.4), Vector3(0, 0.45, 0), 42.0)
	await _grab("sit_front")
	_look(Vector3(3.2, 1.0, -1.4), Vector3(0, 0.45, 0), 42.0)
	await _grab("sit_34")
	for c in [m, l]:
		(c as Node).queue_free()


## Full-body language: each state on both mages, front and three-quarter (BodyLanguage).
func _body() -> void:
	var m := _spawn("mika_celestial", Vector3(-0.8, 0, 0), 0.0)
	var l := _spawn("luna_oracle", Vector3(0.8, 0, 0), 0.0)
	await _wait(1.5)
	report["body_language"] = {}
	var states := ["neutral", "hurt", "tired", "happy", "sad", "shy", "frustrated", "talking"]
	for st in states:
		for c in [m, l]:
			var ch := c as WorldCharacter
			if ch.face:
				for e in ["hurt", "tired", "happy", "sad", "shy", "frustrated"]:
					ch.face.set_hold(e, 0.0)
				if st in ["hurt", "tired", "happy", "sad", "shy", "frustrated"]:
					ch.face.set_hold(st, 0.9)
			var bl := ch.body_language
			if bl:
				bl.injury = 0.85 if st == "hurt" else 0.0
				bl.injury_side = 1.0
				bl.exertion = 0.6 if st in ["hurt", "tired"] else 0.0
				bl.speaking = st == "talking"
		await _wait(2.2)
		_look(Vector3(0, 1.1, -4.6), Vector3(0, 0.95, 0), 40.0)
		await _grab("body_%s_front" % st)
		_look(Vector3(3.0, 1.2, -3.2), Vector3(0, 0.95, 0), 42.0)
		await _grab("body_%s_34" % st)
		report["body_language"][st] = {"mika": m.body_language.status() if m.body_language else {}, "luna": l.body_language.status() if l.body_language else {}}
	for c in [m, l]:
		(c as Node).queue_free()
