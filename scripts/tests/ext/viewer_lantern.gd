extends RefCounted
## --mktest=viewer_lantern (2026-10-19): the deliverable clip - a new subscriber ("Aiko", a fake live event through the
## live link) while Mika and Luna are out in the boat on Lantern Lake at night: a lantern with her name rises beside
## them, they look up at it and thank her by name. Everything here is the living world's own code (LakeRitual: the
## queue, the lantern, the reaction, the lens); this only sets the scene (the boat out on the water) and fires the
## event. GPU run with --write-movie (30 fps) and --keep-overlay; prints the clip window's frames; stills at 3 moments.


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	main.spawner.enabled = false
	if main.performance and main.performance.busy():
		main.performance.interrupt("viewer lantern scene")
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 12.0)
	var lr: LakeRitual = LakeRitual.instance
	var luna: WorldCharacter = main.characters["luna"]
	var mika: WorldCharacter = main.characters["mika"]
	await main.streaming.travel("lantern_lake", luna, false)
	t._check(main.streaming.current_id == "lantern_lake", "at Lantern Lake")
	main.day_night.set_override(true)
	await t._wait(3.0)
	var boat: MoonBoat = lr._ensure_boat()
	t._check(boat != null, "the boat is moored at the pier")
	if boat == null:
		return
	# the two of them on the pier beside the boat, into it, out onto the clear water (LakeRitual's own steps)
	for pair in [[luna, "bow"], [mika, "stern"]]:
		var c: WorldCharacter = pair[0]
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.visible = true
		c.set_physics_process(true)
		c.global_position = lr._deck_spot(String(pair[1])) + Vector3(0, 0.05, 0)
		c.set_hair_frame("")
	await t._wait(1.0)
	lr.night_ritual = true
	lr.participants = ["mika", "luna"]
	lr.running = "boarding"
	main.director.enabled = true
	main.director.set_subject(mika)
	lr._cam_take("ritual")
	lr._set_shot("row")
	await lr._step_in(luna, "bow")
	await lr._step_in(mika, "stern")
	lr.running = "out"
	await lr._push_off()
	if RenderProfile.options.has("vl-row"):
		await lr._row_path(LakeRitual.OUT, 1.8, null, 50.0)
	await lr._glide_spot()                               # (before the clip window: the row out is the ritual test's)
	lr.running = "lanterns"
	boat.day_night = null
	await boat.light_lantern("stern", "bow", "Right")
	lr._set_shot("two")
	await t._wait(5.0)                                   # (the drapes settle; a calm two-shot)
	# the clip: 2 s before the event, the lantern and their thanks, 2 s after
	var f0: int = Engine.get_frames_drawn()
	print("[viewerlantern] clip start frame %d" % f0)
	await t._wait(2.0)
	var link = main.get("live_link")
	t._check(link != null, "the live link (dummy server)")
	link._on_message({"type": "youtube-live-subscriber", "author": "Aiko"})
	var te: float = t._game_t
	var shots := {2.6: "rise", 5.2: "thanks", 8.0: "high"}
	var taken := {}
	while t._game_t - te < LakeRitual.REACT_S + 1.0 or lr._busy_event:
		await t.get_tree().process_frame
		for k in shots:
			if not taken.has(k) and t._game_t - te >= float(k):
				taken[k] = true
				t._shot(String(shots[k]))
				print("[viewerlantern] still %s at frame %d" % [shots[k], Engine.get_frames_drawn()])
		if t._game_t - te > 40.0:
			break
	await t._wait(1.5)
	print("[viewerlantern] clip end frame %d" % Engine.get_frames_drawn())
	print("[viewerlantern] log %s" % JSON.stringify(lr.log))
	var e: Dictionary = lr.log[-1] if not lr.log.is_empty() else {}
	t._check(String(e.get("name", "")) == "Aiko" and String(e.get("where", "")) == "boat", "Aiko's lantern rose beside the boat", e)
	t._check((e.get("lines", []) as Array).size() >= 2 and (e.lines as Array).all(func(l): return String(l).contains("Aiko")), "Mika and Luna thanked Aiko by name", e.get("lines", []))
	var spoken: Array = (main.voice.log as Array).slice(-4).map(func(r): return "%s audio=%s %s" % [r.get("speaker", ""), str(r.get("audio", false)), String(r.get("text", "")).left(60)])
	print("[viewerlantern] voice %s" % str(spoken))
	t.report["viewer_lantern"] = {"log": lr.log, "voice": spoken, "clip_frames": [f0, Engine.get_frames_drawn()]}
	lr.running = ""
	lr._cam_release("ritual")
