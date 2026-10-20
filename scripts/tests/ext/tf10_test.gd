extends RefCounted
## The Level 10 transformation (Tf10, Transformation_Kit_v1) for one girl at night in the clearing, the other girl
## watching: --girl=mika|luna. Marks "[tf10] ..." (its beats) and "[tf10test] rolling at frame N" (the first frame of
## the sequence: everything before it is the setup, cut from the review).

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	var who := String(RenderProfile.options.get("girl", "mika"))
	var other := "luna" if who == "mika" else "mika"
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		main.performance.set_process(false)
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, Tf10.NIGHT)
	var wth = main.get("weather")
	if wth:
		wth.set_weather("clear", 48.0)
		wth.enabled = false
		wth.rain = 0.0
		wth.cloud = 0.0
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 5, "axis_deg": float(RenderProfile.options.get("axis", "25")), "bare": true})
	d.set_process(true)
	d.anim(who, "ualf:Idle", 0.0, -1.0, 1.0, 0.2, true)
	d.anim(other, "ualf:Idle", 0.7, -1.0, 1.0, 0.2, true)
	# (the opening shot already on her before the sequence rolls: no setup frames, no other girl's opening)
	d.cut(d.ft + 0.001, "eyes", who, {"k": 1.0, "fov": 22.0})
	await t._wait(1.2)
	var tf := Tf10.make(d, who)
	print("[tf10test] rolling at frame %d" % Engine.get_frames_drawn())
	tf.start()
	while not tf.done:
		await t.get_tree().process_frame
	await t._wait(0.4)
	print("[tf10test] ended at frame %d" % Engine.get_frames_drawn())
	t._check(tf.log.size() >= 15 and (d.F[who].c as WorldCharacter).avatar_path == Tf10.NEW_FORM[who], "%s transformed (%d beats)" % [who, tf.log.size()])
	if wth:
		wth.enabled = true
	d.teardown()
