extends RefCounted
## The realm by eye (FightRealm): the two girls at range in the duel, Mika's realm grown in three pushes (the frozen
## starfield), held, then Luna's pushes take the world back into her eclipse. A slow orbiting wide camera. Marks
## "[realm] <state> at frame N".

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
	FightDirector.set_hour(main, float(RenderProfile.options.get("hour", "17.0")))
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.0)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 4, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 4, "length": 9999.0, "demo": true})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	var r := FightRealm.make(d)
	sim.realm = r
	var c0: Vector3 = d.center
	d.F.mika.pos = c0 + Vector3(-3.2, 0, 0)
	d.F.luna.pos = c0 + Vector3(3.2, 0, 0)
	await t._wait(0.8)
	d.cut(d.ft + 0.001, "orbit", "mika", {"from": 10.0, "to": 130.0, "r": 9.5})
	print("[realm] start at frame %d" % Engine.get_frames_drawn())
	for i in 3:
		r.push("mika", 0.34)
		r.pulse(0.8)
		await t._wait(2.0)
		print("[realm] mika k %.2f at frame %d" % [r.k, Engine.get_frames_drawn()])
	d.cut(d.ft + 0.001, "wide_low", "luna", {})
	await t._wait(2.0)
	print("[realm] mika full at frame %d" % Engine.get_frames_drawn())
	d.cut(d.ft + 0.001, "orbit", "luna", {"from": 160.0, "to": 260.0, "r": 9.5})
	for i in 5:
		r.push("luna", 0.4)
		r.pulse(0.8)
		await t._wait(2.0)
		print("[realm] %s k %.2f eclipse %.2f at frame %d" % [r.who, r.k, r.eclipse, Engine.get_frames_drawn()])
	d.cut(d.ft + 0.001, "hero_low", "luna", {})
	await t._wait(2.5)
	print("[realm] luna full at frame %d" % Engine.get_frames_drawn())
	t._check(r.who == "luna" and r.k > 0.9, "the realm grew, held and changed hands (%s %.2f)" % [r.who, r.k])
	r.teardown()
	sim.realm = null
	sim.teardown()
	d.teardown()
