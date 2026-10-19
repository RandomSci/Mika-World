extends RefCounted
## Prebake every Move Library clip for every avatar Mika and Luna can wear (data/appearances.json), into
## MocapBake.BAKED_DIR (no first-use bake on stream). Each avatar is instanced off screen, its skeleton baked clip by
## clip; a clip whose cache is already current is skipped. --avatars=a.vrm,b.vrm limits it. Marks "[prebake] ...".

static func run(t) -> void:
	var avatars := {}
	var app = JSON.parse_string(FileAccess.get_file_as_string("res://data/appearances.json"))
	var stack := [app]
	while not stack.is_empty():
		var v = stack.pop_back()
		if v is Dictionary:
			if String(v.get("avatar", "")).ends_with(".vrm"):
				avatars[String(v.avatar)] = true
			for k in v:
				stack.append(v[k])
		elif v is Array:
			stack.append_array(v)
	var only := String(RenderProfile.options.get("avatars", "")).split(",", false)
	var made := 0
	var kept := 0
	var keys := {}
	for path in avatars:
		if not only.is_empty() and not (String(path).get_file() in only):
			continue
		if not ResourceLoader.exists(path):
			print("[prebake] missing avatar %s" % path)
			continue
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		t.add_child(inst)
		inst.visible = false
		var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		var key := MocapBake.rest_key(sk)
		if keys.has(key):
			print("[prebake] %s shares its skeleton with %s" % [String(path).get_file(), keys[key]])
			inst.queue_free()
			continue
		keys[key] = String(path).get_file()
		var t0 := Time.get_ticks_msec()
		for n in MoveCatalog.CLIPS:
			var json: String = WorldCharacter.MOCAP_DIR + String(n) + ".json"
			if not FileAccess.file_exists(json):
				continue
			if MocapBake.cached(sk, json) != null:
				kept += 1
				continue
			if MocapBake.bake_to_cache(sk, json) != null:
				made += 1
			await t.get_tree().process_frame
		print("[prebake] %s (skeleton %s) done in %.1f s" % [String(path).get_file(), key, (Time.get_ticks_msec() - t0) / 1000.0])
		inst.queue_free()
	t._check(made + kept > 0, "%d clips baked, %d already current, %d skeletons" % [made, kept, keys.size()])
