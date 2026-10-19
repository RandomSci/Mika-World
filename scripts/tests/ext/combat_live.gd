extends RefCounted
## A live fight (CombatSim) between Mika and Luna at the training clearing, nothing planned. --fight-seed=N picks the
## dice (every seed a different fight), --fight-length=S forces a length, --fight-hour=H the light. Checks that it is
## NOT turn-based: both keep moving (distance travelled, time standing still, time spent near their start spot),
## many different moves, no move spammed, a length between 45 s and 3 min, at least 3 highlights, a finisher.

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
	var seed := int(RenderProfile.options.get("fight-seed", str(Time.get_ticks_usec() % 100000)))
	var hours := [17.4, 18.6, 20.8]
	FightDirector.set_hour(main, float(RenderProfile.options.get("fight-hour", str(hours[seed % 3]))))
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
		main.weather.cloud = 0.0
		main.weather.rain = 0.0
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(2.5)
	if main.get("voice") and main.voice:
		main.voice.stop()
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": seed, "axis_deg": float(seed % 360)})
	var opts := {"seed": seed}
	if RenderProfile.options.has("fight-length"):
		opts["length"] = float(RenderProfile.options.get("fight-length"))
	var sim := CombatSim.make(d, opts)
	var start := {"mika": d.pos("mika"), "luna": d.pos("luna")}
	var watch := {"frames": 0, "travel": {"mika": 0.0, "luna": 0.0}, "near_start": {"mika": 0, "luna": 0}, "still": 0, "airborne": 0, "tpose": 0,
		"cine": 0, "still_why": {}}
	var last := {"mika": d.pos("mika"), "luna": d.pos("luna")}
	var watcher := func():
		while not sim.done:
			await t.get_tree().process_frame
			watch.frames += 1
			var both_still := true
			for id in ["mika", "luna"]:
				var p: Vector3 = d.pos(id)
				var step := Vector2(p.x - last[id].x, p.z - last[id].z).length()
				watch.travel[id] = float(watch.travel[id]) + step
				if step > 0.004:
					both_still = false
				if Vector2(p.x - start[id].x, p.z - start[id].z).length() < 1.0:
					watch.near_start[id] = int(watch.near_start[id]) + 1
				if float(d.F[id].lift) > 0.3:
					watch.airborne = int(watch.airborne) + 1
				last[id] = p
			if Engine.time_scale < 0.9 or sim.climax:
				watch.cine += 1                          # (hit-stop and slow motion: stillness on purpose, not counted)
			elif both_still:
				watch.still += 1
				var why := "%s/%s" % [String(sim.S.mika.state) + ":" + String((sim.S.mika.act as Dictionary).get("name", sim.S.mika.get("loco", ""))),
					String(sim.S.luna.state) + ":" + String((sim.S.luna.act as Dictionary).get("name", sim.S.luna.get("loco", "")))]
				watch.still_why[why] = int(watch.still_why.get(why, 0)) + 1
	watcher.call()
	var r: Dictionary = await sim.run()
	await t._wait(0.5)
	print("[combat] result ", JSON.stringify(r))
	print("[combat] watch ", JSON.stringify(watch))
	t.report["combat"] = r
	t.report["combat_watch"] = watch
	var n := maxf(float(watch.frames) - float(watch.cine), 1.0)
	var moves: Dictionary = r.moves
	var max_share := 0.0
	var total := 0
	for k in moves:
		total += int(moves[k])
	for k in moves:
		max_share = maxf(max_share, float(moves[k]) / maxf(total, 1))
	var hl: Array = r.highlights
	t._check(float(r.length_s) >= 40.0 and float(r.length_s) <= 200.0, "fight length %.0f s (dice %.0f s)" % [float(r.length_s), float(r.dice_length_s)])
	t._check(float(watch.travel.mika) > float(r.length_s) * 1.2 and float(watch.travel.luna) > float(r.length_s) * 1.2,
		"both keep moving: Mika %.0f m, Luna %.0f m travelled" % [float(watch.travel.mika), float(watch.travel.luna)])
	t._check(float(watch.near_start.mika) / n < 0.15 and float(watch.near_start.luna) / n < 0.15,
		"nobody goes back to a start spot (Mika %.0f %%, Luna %.0f %% of the fight within 1 m of it)" % [100.0 * float(watch.near_start.mika) / n, 100.0 * float(watch.near_start.luna) / n])
	t._check(float(watch.still) / n < 0.08, "both stand still only %.1f %% of the time" % [100.0 * float(watch.still) / n])
	t._check(moves.size() >= 10, "%d different moves used" % moves.size())
	t._check(max_share < 0.22, "no move dominates (the most used is %.0f %% of %d)" % [100.0 * max_share, total])
	t._check(hl.size() >= 3, "%d highlights: %s" % [hl.size(), str(hl.map(func(h): return "%s@%s" % [h[1], h[0]]))])
	t._check(hl.any(func(h): return String(h[1]) == "finisher"), "it ends on a finisher (winner %s)" % r.winner)
	t._check(int(watch.airborne) > 30, "they fight in the air too (%d frames airborne)" % int(watch.airborne))
	d.teardown()
