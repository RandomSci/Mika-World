class_name AudioTest
extends Node
## --audiotest: event-driven sound + speech verification. Records Godot's Master bus (AudioEffectRecord)
## for the whole run, triggers real events (footsteps on grass and stone, a wind cast at a brazier, a water
## cast at the pond, reading Liber Orbis with Latin read aloud, an alchemy pour, a spoken line) and logs
## every sound the AudioDirector played with the event that caused it. Writes the recording + JSON.

var main: Node
var report := {}
var dir := ""
var rec: AudioEffectRecord
var t0 := 0.0
var marks := []
var phases := []


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/audiotest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	MagicEvents.spell_phase.connect(func(_c, sid, ph, el, _p): phases.append({"t": _now(), "spell": sid, "phase": ph, "element": el}))
	_run.call_deferred()


func _now() -> float:
	return snappedf(Time.get_ticks_msec() / 1000.0 - t0, 0.001)


func _mark(label: String) -> void:
	marks.append({"t": _now(), "label": label})
	print("[audiotest] %.2f %s" % [_now(), label])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _walk(dir_v: Vector3, seconds: float) -> void:
	var m: WorldCharacter = main.characters["mika"]
	var e := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < e:
		m.set_move_input(dir_v, false)
		await get_tree().physics_frame
	m.set_move_input(Vector3.ZERO, false)


func _run() -> void:
	main.player.enabled = false
	var m: WorldCharacter = main.characters["mika"]
	await _wait(3.0)
	# wait for the speech service (it starts with the game)
	var w := 0
	while not main.voice.available and w < 60:
		await _wait(0.5)
		w += 1
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	t0 = Time.get_ticks_msec() / 1000.0
	main.audio.log.clear()
	_mark("start")
	m.global_position = Vector3(0, 0.2, 14.0)
	await _wait(0.5)
	_mark("walk grass")
	await _walk(Vector3(1, 0, 0), 3.0)
	m.global_position = Vector3(0, Sanctuary.DAIS_TOP + 0.1, 2.5)
	await _wait(0.5)
	_mark("walk stone dais")
	await _walk(Vector3(0, 0, -1), 2.0)
	WorldState.knowledge["incantation:wind_gust"] = 1
	WorldState.knowledge["incantation:water_ripple"] = 1
	WorldState.skills["wind_gust"] = 1.2
	m.global_position = Vector3(0, Sanctuary.DAIS_TOP + 0.1, 3.0)
	await _wait(0.5)
	_mark("cast wind at brazier_se")
	var r1: Dictionary = await main.magic.cast(m, "wind_gust", "brazier_se")
	report["cast_wind"] = {"outcome": r1.get("outcome"), "effect": r1.get("effect")}
	await _wait(1.0)
	m.global_position = Vector3(11.5, 0.2, 19.5)
	await _wait(0.5)
	_mark("cast water at pond")
	var r2: Dictionary = await main.magic.cast(m, "water_ripple", "pond")
	report["cast_water"] = {"outcome": r2.get("outcome"), "effect": r2.get("effect")}
	await _wait(1.0)
	var tome: Interactable = main.world.interactables["altar_spellbook"]
	m.global_position = tome.approach_point() + Vector3(0, 0.1, 0.4)
	await _wait(0.5)
	_mark("read Liber Orbis")
	var rr: Dictionary = await tome.perform(m)
	report["reading_spoken"] = rr.get("reading", {}).get("spoken", [])
	var al: Interactable = main.world.interactables["alchemy_table"]
	m.global_position = al.approach_point() + Vector3(0, 0.1, 0)
	await _wait(0.5)
	_mark("alchemy")
	var t: AlchemyTable = main.world.alchemy
	al.custom_activity = func(c): return await t.experiment(c, ["moonwater"], false)
	var ar: Dictionary = await al.perform(m)
	report["alchemy"] = ar.get("activity", {}).get("outcome", "")
	_mark("speech line")
	var sp: Dictionary = await main.voice.say("mika", "The flame leaned away, then steadied. I think my wind needs more practice.")
	report["speech"] = sp
	await _wait(1.0)
	_mark("end")
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	var path := ProjectSettings.globalize_path("%s/godot_master_%s.wav" % [dir, RenderProfile.profile.to_lower()])
	if wav:
		wav.save_to_wav(path)
	report["recording"] = path
	report["marks"] = marks
	report["phases"] = phases
	report["sounds"] = main.audio.log.map(func(e): return {"t": snappedf(e.t - t0, 0.001), "sound": e.sound, "bus": e.bus, "event": e.event})
	report["voice"] = main.voice.describe()
	report["buses"] = AudioBuses.describe()
	var f := FileAccess.open("%s/audio_test_%s.json" % [dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[audiotest] done")
	get_tree().quit()
