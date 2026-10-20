extends RefCounted
## Their duel with weapons (WeaponDuel), 45 s on the fight's cinematographer, both ultimates mid fight.
## Options: --fight-length=45, --ult-at=mika=14,luna=30, --ult-pick=mika=ult_x,luna=ult_y, --weapon-level=20.
## Marks "[duel] ..." for every exchange, cast and ultimate.

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		main.performance.set_process(false)
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, float(RenderProfile.options.get("fight-hour", "16.6")))
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 9, "axis_deg": 30.0, "bare": true})
	var length := float(RenderProfile.options.get("fight-length", "45"))
	var sim := MeleeSim.make(d, {"seed": 9, "length": 9999.0, "demo": true, "melee": true, "start_gap": 3.4})
	sim.footwork = true
	d.cut(0.0, "duo", "mika", {"k": 1.0, "high": 0.35})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	sim.cine = FightCine.make(sim)
	var ua := {}
	for kv in String(RenderProfile.options.get("ult-at", "mika=14,luna=30")).split(",", false):
		ua[kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
	var up := {"mika": "ult_starfall_conductor", "luna": "ult_sky_rending_slash"}
	for kv in String(RenderProfile.options.get("ult-pick", "")).split(",", false):
		up[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
	var t0: float = sim.t
	var ua_abs := {}
	for k in ua:
		ua_abs[k] = t0 + float(ua[k])
	var duel := WeaponDuel.make(sim, {"ult_at": ua_abs, "ult_pick": up})
	print("[duel] start at frame %d" % Engine.get_frames_drawn())
	while sim.t < t0 + length:
		duel.update()
		if sim.cine:
			sim.cine.update()
		await t.get_tree().process_frame
	var hits := 0
	for a in sim.attacks:
		if String(a.get("outcome", "")) == "hit":
			hits += 1
	print("[duel] end at frame %d, %d exchanges, %d hits" % [Engine.get_frames_drawn(), duel.rows.size(), hits])
	t._check(duel.rows.size() >= int(length / 4.5), "they fought (%d exchanges in %.0f s)" % [duel.rows.size(), length])
	for id in ["mika", "luna"]:
		duel.wp.sheathe(id)
	await t._wait(0.5)
	sim.teardown()
	d.teardown()
