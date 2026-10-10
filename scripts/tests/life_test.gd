class_name LifeTest
extends Node
## --lifetest (use with --visitors=fast): wildlife behaviour + reactions to real magic, and the travellers:
## arrival along a route, witnessing Mika's magic, a spoken conversation with knowledge transfer, and a
## check that a traveller who did not witness something cannot talk about it.

var main: Node
var report := {"wildlife": [], "npc": {}}
var dir := ""


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/lifetest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, RenderProfile.profile.to_lower(), tag])


func _animals() -> Array:
	return main.world.find_children("Animal_*", "", true, false)


func _snapshot(label: String) -> void:
	report.wildlife.append({"label": label, "animals": _animals().map(func(a): return a.describe())})


func _run() -> void:
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	var m: WorldCharacter = main.characters["mika"]
	var rig: ThirdPersonCamera = main.camera_rig
	await _wait(4.0)
	# --- wildlife, undisturbed
	m.global_position = Vector3(0, Sanctuary.DAIS_TOP + 0.1, 1.5)
	await _wait(12.0)
	_snapshot("undisturbed 12 s")
	var deer: Node3D = main.world.find_child("Animal_deer_12", true, false)
	rig.set_shot(deer.global_position + Vector3(4.5, 2.0, 5.0), deer.global_position + Vector3(0, 0.7, 0), 45.0)
	await _wait(1.0)
	_shot("deer")
	var fox: Node3D = main.world.find_child("Animal_fox_11", true, false)
	# --- the fox investigates a calm, still Mika
	m.global_position = fox.global_position + Vector3(7.0, 0.3, 2.0)
	m.velocity = Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000 and fox.state != "investigate" and fox.state != "observe":
		await get_tree().process_frame
		rig.set_shot((fox.global_position + m.global_position) * 0.5 + Vector3(0, 2.5, 6.5), (fox.global_position + m.global_position) * 0.5 + Vector3(0, 0.5, 0), 50.0)
	await _wait(4.0)
	_shot("fox_investigates")
	_snapshot("fox near a still Mika")
	# --- magic startles: koi + fox
	WorldState.knowledge["incantation:water_ripple"] = 1
	WorldState.skills["water_ripple"] = 1.0
	m.global_position = Vector3(SanctuaryTerrain.POND.x, 0.3, SanctuaryTerrain.POND.y + 4.6)
	await _wait(1.0)
	var water_y: float = main.world.ground_at(SanctuaryTerrain.POND.x + 3.6, SanctuaryTerrain.POND.y) - 0.14
	rig.set_shot(Vector3(SanctuaryTerrain.POND.x + 3.5, water_y + 3.2, SanctuaryTerrain.POND.y + 4.0), Vector3(SanctuaryTerrain.POND.x, water_y, SanctuaryTerrain.POND.y), 50.0)
	await _wait(0.5)
	_shot("koi_before")
	var r: Dictionary = await main.magic.cast(m, "water_ripple", "pond")
	await _wait(0.6)
	_shot("koi_scatter")
	_snapshot("after water on the pond (%s %s)" % [r.get("effect", ""), r.get("reason", "")])
	report["pond_cast"] = {"outcome": r.get("outcome"), "effect": r.get("effect"), "reason": r.get("reason", "")}
	rig.clear_shot()
	# --- travellers: Ysolde arrives (fast schedule), witnesses an extinguished brazier, then they talk
	var waited := 0.0
	while not main.npcs.present.has("wandering_mage") and waited < 40.0:
		await _wait(0.5)
		waited += 0.5
	var ys: TravelerNPC = main.npcs.present.get("wandering_mage")
	report.npc["arrival"] = {"arrived": ys != null, "after_s": waited}
	if ys:
		var t1 := Time.get_ticks_msec()
		while ys.state == "arriving" and Time.get_ticks_msec() - t1 < 60000:
			await get_tree().process_frame
		rig.set_shot(ys.global_position + Vector3(3.0, 1.8, 3.5), ys.global_position + Vector3(0, 1.0, 0), 45.0)
		await _wait(0.8)
		_shot("ysolde_arrived")
		rig.clear_shot()
		WorldState.knowledge["incantation:wind_gust"] = 1
		WorldState.skills["wind_gust"] = 1.2
		m.global_position = Vector3(0, Sanctuary.DAIS_TOP + 0.1, 3.0)
		await _wait(0.6)
		var rw: Dictionary = await main.magic.cast(m, "wind_gust", "brazier_se")
		report.npc["cast_witnessed"] = {"effect": rw.get("effect"), "ysolde_witnessed": ys.witnessed.map(func(e): return e.effect)}
		await _wait(1.0)
		# Mika walks over and they talk
		m.navigate_to(ys.global_position + (m.global_position - ys.global_position).normalized() * 1.6)
		var t2 := Time.get_ticks_msec()
		while m.current_action == "navigate_to" and Time.get_ticks_msec() - t2 < 20000:
			await get_tree().process_frame
		main.director.enabled = true
		var shot_taken := [false]
		var conv := [null]
		var go := func(): conv[0] = await main.dialogue.converse("wandering_mage", m)
		go.call()
		while conv[0] == null:
			await get_tree().process_frame
			if not shot_taken[0] and main.voice.busy() and main.director.mode == "conversation":
				await _wait(1.2)
				_shot("conversation")
				shot_taken[0] = true
		report.npc["conversation_1"] = conv[0]
		main.director.enabled = false
	# a second traveller: did not witness the brazier, so the extinguish beat is unavailable to her
	var el: TravelerNPC = main.npcs.present.get("travelling_scholar")
	if el == null:
		el = main.npcs.arrive("travelling_scholar")
	if el:
		var beats: Array = main.dialogue.choose_beats("travelling_scholar", el, 6)
		report.npc["scholar_available_beats"] = beats.map(func(b): return b.id)
		report.npc["scholar_witnessed"] = el.witnessed.duplicate()
		report.npc["scholar_context_keys"] = main.dialogue.context_for("travelling_scholar", el).knows.keys()
	report.npc["state"] = WorldState.npc_state.duplicate(true)
	report.npc["manager"] = main.npcs.describe()
	report["llm"] = main.llm.describe()
	var f := FileAccess.open("%s/life_test_%s.json" % [dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[lifetest] done")
	get_tree().quit()
