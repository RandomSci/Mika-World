extends RefCounted
## --mktest=npcprobe (23 Oct, Selwyn: "around 20 should be fine?"): how many people the stream can carry. In the village
## square, a fixed whole-crowd shot, then N full characters (WorldCharacter with a VRM: spring bones, MToon, the full
## animation tree, as Mika and Luna) and then N light townsfolk (the CC0 resident models with one looping clip), 12 s
## each after a settle, frame times measured in real time (no movie writer). Marks "[npcprobe] ...".

const FULL := [0, 5, 10, 20]
const LIGHT := [20, 40]


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("npc probe")
	await t._hold_all()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	var mc: WorldCharacter = main.characters["mika"]
	if main.streaming.current_id != "village":
		await main.streaming.travel("village", mc, false)
	await t._wait(4.0)
	var area = main.streaming.current
	RenderingServer.viewport_set_measure_render_time(t.get_viewport().get_viewport_rid(), true)
	var centre: Vector3 = area.points_of_interest["village_square"].position
	var map := mc.get_world_3d().navigation_map
	var spots := []
	for i in 60:
		var a := i * 2.399963
		var r := 2.5 + sqrt(float(i)) * 1.6
		spots.append(NavigationServer3D.map_get_closest_point(map, centre + Vector3(cos(a) * r, 0, sin(a) * r)))
	main.director.begin_scene(func(_d): return {"pos": centre + Vector3(0, 6.0, 17.0), "look": centre + Vector3(0, 0.8, 0), "fov": 60.0, "rate": 30.0})
	var holder := Node3D.new()
	holder.name = "NpcProbe"
	area.add_child(holder)
	var results := []
	var full_nodes := []
	for n in FULL:
		while full_nodes.size() < n:
			var c := WorldCharacter.new()
			c.name = "probe_full_%d" % full_nodes.size()
			c.character_id = "probe_%d" % full_nodes.size()
			c.display_name = c.name
			c.avatar_path = "res://assets/characters/mika/Mika.vrm"
			holder.add_child(c)
			c.global_position = spots[full_nodes.size()]
			c.look_at_point(centre)
			full_nodes.append(c)
			await t.get_tree().process_frame
		results.append(await _measure(t, "full %d" % n))
	for c in full_nodes:
		c.queue_free()
	full_nodes.clear()
	await t._wait(2.0)
	var models := ["res://assets/npc/residents/guard_m.glb", "res://assets/npc/woman.glb", "res://assets/npc/worker.glb", "res://assets/npc/adventurer.glb"]
	var light_nodes := []
	for n in LIGHT:
		while light_nodes.size() < n:
			var ps: PackedScene = load(models[light_nodes.size() % models.size()])
			var m: Node3D = ps.instantiate()
			holder.add_child(m)
			m.global_position = spots[light_nodes.size()]
			m.look_at(Vector3(centre.x, m.global_position.y, centre.z), Vector3.UP, true)
			var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
			if ap and not ap.get_animation_list().is_empty():
				var names := ap.get_animation_list()
				var pick := names[0]
				for nm in names:
					if String(nm).to_lower().contains("idle"):
						pick = nm
						break
				ap.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
				ap.play(pick)
			light_nodes.append(m)
		results.append(await _measure(t, "light %d" % n))
	main.director.end_scene()
	holder.queue_free()
	print("[npcprobe] RESULTS %s" % JSON.stringify(results))
	t._check(true, "measured %d crowds" % results.size())


static func _measure(t, label: String) -> Dictionary:
	await t._wait(5.0)          # load and settle
	var frames: Array = []
	var last := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await t.get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	frames.sort()
	var avg: float = frames.reduce(func(a, b): return a + b, 0.0) / maxf(frames.size(), 1)
	var r := {"crowd": label, "fps": snappedf(1000.0 / avg, 0.1), "avg_ms": snappedf(avg, 0.1), "p95_ms": snappedf(frames[int(frames.size() * 0.95)], 0.1),
		"max_ms": snappedf(frames.back(), 0.1), "over_100": frames.filter(func(f): return f > 100.0).size(),
		"gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(t.get_viewport().get_viewport_rid()), 0.1)}
	print("[npcprobe] %s" % JSON.stringify(r))
	return r
