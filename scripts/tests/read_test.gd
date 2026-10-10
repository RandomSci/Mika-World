class_name ReadTest
extends Node
## --readtest: real reading in the Sanctuary and the library. Mika walks to each reading spot, opens the
## book, reads page by page (Latin aloud), turns pages, closes it. Captures the director's book close-up
## and the overlay mid-page, records pages read, knowledge learned, lines spoken (audio or fallback).

var main: Node
var report := {"reads": []}
var dir := ""


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/readtest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> String:
	var path := "%s/%s_%s.png" % [dir, RenderProfile.profile.to_lower(), tag]
	get_viewport().get_texture().get_image().save_png(path)
	return path


func _read(id: String, time_scale := 0.6) -> void:
	var m: WorldCharacter = main.characters["mika"]
	var it: Interactable = main.world.interactables[id]
	m.global_position = it.approach_point() + Vector3(0, 0.1, 0) + (it.approach_point() - it.global_position).normalized() * 0.6
	await _wait(0.4)
	var shots := []
	var cb := func(book_id, page, _d):
		if shots.size() < 3:
			await _wait(2.2)
			shots.append(_shot("%s_p%d" % [book_id, page + 1]))
	main.book_reader.page_shown.connect(cb)
	var r: Dictionary = await it.perform(m)
	main.book_reader.page_shown.disconnect(cb)
	r["shots"] = shots
	report.reads.append(r)
	print("[readtest] %s -> ok=%s pages=%s learned=%s spoken=%s" % [id, r.ok, r.get("reading", {}).get("pages_read", []).size(),
		r.get("reading", {}).get("learned", []), r.get("reading", {}).get("spoken", []).map(func(x): return [x.latin, x.audio])])


func _run() -> void:
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	main.director.enabled = true
	await _wait(4.0)
	report["voice_at_start"] = main.voice.describe()
	await _read("altar_spellbook")
	await _read("keepers_daybook")
	await _read("gate_inscription")
	var mika: WorldCharacter = main.characters["mika"]
	await main.streaming.travel("arcane_library", mika)
	await _wait(2.0)
	await _read("lectern_warding_glyph")
	report["knowledge"] = WorldState.knowledge.keys().filter(func(k): return k.begins_with("incantation:") or k.begins_with("clue:") or k.begins_with("read:"))
	report["castable_now"] = main.magic.known_spells().filter(func(x): return x.castable).map(func(x): return x.id)
	report["voice_log"] = main.voice.log.duplicate()
	report["trials"] = WorldState.mission_state()
	var f := FileAccess.open("%s/read_test_%s.json" % [dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[readtest] done")
	get_tree().quit()
