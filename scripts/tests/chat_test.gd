class_name ChatTest
extends Node
## --chattest: mock viewer comments -> routing -> Mika's reply -> TTS -> audio -> subtitle -> optional action.
## Never connects to a real stream. Also captures viewer-mode vs developer-mode screenshots.

var main: Node
var report := {"receive": [], "replies": []}
var dir := ""


func _ready() -> void:
	dir = RenderProfile.shots_dir + "/chattest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [dir, RenderProfile.profile.to_lower(), tag])


func _run() -> void:
	await _wait(4.0)
	var w := 0
	while not main.voice.available and w < 60:
		await _wait(0.5)
		w += 1
	WorldState.knowledge["incantation:wind_gust"] = 1
	main.set_brain(true)
	await _wait(3.0)
	var comments := [
		{"message_id": "m1", "author_id": "UC_alex", "author": "Alex", "text": "hi Mika!"},
		{"message_id": "m1", "author_id": "UC_alex", "author": "Alex", "text": "hi Mika!"},
		{"message_id": "m2", "author_id": "UC_sam", "author": "Sam", "text": "lol same"},
		{"message_id": "m3", "author_id": "UC_rin", "author": "Rin", "text": "What are you doing right now, Mika?"},
		{"message_id": "m4", "author_id": "UC_kai", "author": "Kai", "text": "Mika you should practise the Wind Gust at the brazier!"},
		{"message_id": "m5", "author_id": "UC_rin", "author": "Rin", "text": "And which spells do you know?"},
		{"message_id": "m6", "author_id": "UC_bob", "author": "Bob", "text": "@lena nice one"},
	]
	for c in comments:
		var r: Dictionary = main.chat.receive(c)
		report.receive.append({"id": c.message_id, "author": c.author, "text": c.text, "result": r})
	main.set_viewer_mode(true)
	var t0 := Time.get_ticks_msec()
	var shot := false
	while Time.get_ticks_msec() - t0 < 150000 and main.chat.log.size() < 4:
		await get_tree().process_frame
		if not shot and main.voice.busy() and main.chat.log.size() >= 1:
			await _wait(1.0)
			_shot("viewer_mode_reply")
			shot = true
	report.replies = main.chat.log.duplicate()
	report["queue_left"] = main.chat.queue.map(func(e): return {"author": e.author, "text": e.text, "score": e.score})
	report["brain_after"] = main.brain.status()
	report["bonus_now"] = main.brain.curiosity_bonus.duplicate()
	main.set_viewer_mode(false)
	main.hud.visible = true
	await _wait(1.0)
	_shot("developer_mode")
	main.set_brain(false)
	var f := FileAccess.open("%s/chat_test_%s.json" % [dir, RenderProfile.profile.to_lower()], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[chattest] done")
	get_tree().quit()
