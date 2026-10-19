extends RefCounted
## Combat v3, deliverable 1: a live close-combat exchange (MeleeSim on the procedural fight rig) between Mika and Luna
## at the training clearing, --fight-seed=N for the dice, --fight-length=S (default 15). Checks the rules: the
## defender never reacts before 0.10 s after the windup starts, fists / feet really touch (contact error at the hit
## frame), exchanges keep flowing (gaps between actions), a mix of hits, blocks, dodges.

static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		if main.performance.busy():
			main.performance.interrupt("fight test")
			var w0: float = t._game_t
			while main.performance.busy() and t._game_t - w0 < 8.0:
				await t.get_tree().process_frame
		main.performance.set_process(false)
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	var seed := int(RenderProfile.options.get("fight-seed", "11"))
	FightDirector.set_hour(main, float(RenderProfile.options.get("fight-hour", "17.6")))
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
		main.weather.cloud = 0.0
		main.weather.rain = 0.0
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(2.0)
	if main.get("voice") and main.voice:
		main.voice.stop()
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": seed, "axis_deg": float(seed * 37 % 360), "bare": true})
	var sim := MeleeSim.make(d, {"seed": seed, "length": float(RenderProfile.options.get("fight-length", "15"))})
	d.cut(0.0, "duo", "mika", {"k": 1.0, "high": 0.35})
	d.set_process(true)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	sim.start()
	await t._wait(0.6)
	# she faces the other girl: skeleton +Z toward her
	var fm: MeleeFighter = sim.F.mika
	var fz := (fm.sk.global_transform.basis * Vector3(0, 0, 1))
	fz.y = 0.0
	var to := d.pos("luna") - d.pos("mika")
	to.y = 0.0
	t._check(fz.normalized().dot(to.normalized()) > 0.9, "skeleton +Z faces the opponent (dot %.2f)" % fz.normalized().dot(to.normalized()))
	print("[melee] fight starts at frame %d" % Engine.get_frames_drawn())
	while not sim.done:
		await t.get_tree().process_frame
	var r: Dictionary = sim.result()
	await t._wait(0.4)
	print("[melee] result ", JSON.stringify({"length": r.length, "outcomes": r.outcomes, "exchanges": r.exchanges, "gaps": r.gaps, "vfx": r.vfx}))
	for a in r.attacks:
		print("[melee]   %s" % JSON.stringify(a))
	for e in r.events:
		print("[melee]   ev %s" % JSON.stringify(e))
	t.report["melee"] = r
	var errs: Array = r.contact_err
	var worst := 0.0
	var mean := 0.0
	for e in errs:
		worst = maxf(worst, float(e))
		mean += float(e)
	mean /= maxf(errs.size(), 1)
	var delays: Array = r.react_delays
	var early := delays.filter(func(x): return float(x) < 0.099)
	var gaps: Array = r.gaps
	var gmax := 0.0
	for g in gaps:
		gmax = maxf(gmax, float(g))
	var n: int = (r.attacks as Array).size()
	t._check(n >= 10, "%d attacks in %.0f s" % [n, float(r.length)])
	t._check(errs.size() >= 3 and mean < 0.05 and worst < 0.09, "contact: fist / foot to the point it lands on, mean %.3f m, worst %.3f m over %d hits and blocks" % [mean, worst, errs.size()])
	t._check(early.is_empty(), "no defender moves before 0.10 s after the windup starts (%d reactions, min %.2f s)" % [delays.size(), delays.min() if not delays.is_empty() else -1.0])
	var oc: Dictionary = r.outcomes
	t._check(oc.size() >= 3, "a mix of outcomes: %s" % str(oc))
	t._check(gmax < 1.3, "actions keep coming: longest gap between any two actions %.2f s" % gmax)
	sim.teardown()
	d.teardown()
