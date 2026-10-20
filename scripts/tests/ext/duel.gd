extends RefCounted
## The duel as an anime MV (2026-10-19): Mika and Luna at the sanctuary's training clearing; the referee (FightPlan)
## decides the bout, FightDirector stages it (FightDeck clips + softness pass, FightFX magic, hit-stop, flashes, speed
## lines on big hits, slow motion on the finisher, a Phantom Camera shot list cut on the hits), it ends with a winner,
## then the aftermath (a hand up, a high five) and the XP. Record with --write-movie (30 fps).
## NOTE: --mktest=duel is the built-in Milestone K sparring test; this one runs as --mktest=duelmv (ext/duelmv.gd).
## Options: --fight-seed=N, --fight-hour=H (clock hour, default 17.6: low golden sun), --fight-mode=duel|training.
## Checks: a winner (duel) / a score (training); both landed or blocked something; XP for both; every shot <= 6 s and
## cuts on the action; no shot < 0.2 s; they never overlap or leave the clearing; no T-pose; effects really spawned.

static func run(t, fight_mode := "") -> void:
	var main = t.main
	var mode := fight_mode if fight_mode != "" else String(RenderProfile.options.get("fight-mode", "duel"))
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
			await t._wait(1.5)                    # (its "interrupted" outro line is said now, not in the fight)
		main.performance.set_process(false)
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, float(RenderProfile.options.get("fight-hour", "17.6")))
	if main.get("weather") and main.weather:
		main.weather.set_weather(String(RenderProfile.options.get("fight-weather", "clear")), 48.0)
		if String(RenderProfile.options.get("fight-weather", "clear")) == "clear":
			main.weather.cloud = 0.0             # (now, not over the ~20 s the sky normally takes)
			main.weather.rain = 0.0
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(2.5)
	if main.get("voice") and main.voice:
		main.voice.stop()                 # (lines queued before the fight - an interrupted dance's outro - never play in it)
	await t._wait(0.3)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, mode, {"seed": int(RenderProfile.options.get("fight-seed", "1907"))})
	var watch := {"frames": 0, "overlap": 0, "min_gap": 99.0, "tpose": 0, "out": 0, "fx_peak": 0, "max_lift": 0.0}
	var stills: Array = String(RenderProfile.options.get("fight-stills", "")).split(",", false)
	var watcher := func():
		while not d.done:
			await t.get_tree().process_frame
			watch.frames += 1
			var gap := d._flat(d.chest("mika") - d.chest("luna")).length()
			watch.min_gap = minf(float(watch.min_gap), gap)
			if gap < 0.42:
				watch.overlap += 1
			for id in ["mika", "luna"]:
				if d._flat(d.pos(id) - d.center).length() > FightDirector.ARENA_R + 0.05:
					watch.out += 1
				if _tpose(d, id):
					watch.tpose += 1
			watch.fx_peak = maxi(int(watch.fx_peak), d.fx.get_child_count())
			for s in stills:
				if absf(d.real_t - float(s)) < 0.017:
					t._shot("%s_%s" % [mode, String(s).replace(".", "_")])
	watcher.call()
	var r: Dictionary = await d.run()
	t.report["fight"] = r
	t.report["plan"] = d.plan
	t.report["cuts"] = d.cam_log
	t.report["hits"] = d.hit_log
	t.report["watch"] = watch
	print("[fight] result ", JSON.stringify(r))
	print("[fight] watch ", JSON.stringify(watch))
	if main.get("voice") and main.voice:
		var vl: Array = main.voice.log
		for e in vl.slice(maxi(vl.size() - 12, 0)):
			print("[fight] voice ", JSON.stringify(e).left(220))
	# shot lengths in real time (frames / 30)
	var longest := 0.0
	var shortest := 99.0
	for i in d.cam_log.size():
		var t0: float = d.cam_log[i][0]
		var t1: float = d.cam_log[i + 1][0] if i + 1 < d.cam_log.size() else d.real_t
		longest = maxf(longest, t1 - t0)
		if i + 1 < d.cam_log.size():
			shortest = minf(shortest, t1 - t0)
	t._check(d.cam_log.size() >= (16 if mode == "duel" else 10), "a cut shot list (%d cuts)" % d.cam_log.size())
	t._check(longest <= 6.0, "no shot longer than 6 s (longest %.2f s)" % longest)
	t._check(shortest >= 0.2, "no flicker cuts (shortest %.2f s)" % shortest)
	t._check(int(r.hits.mika) + int(r.hits.luna) >= 2, "blows landed on both sides of the exchanges", r.hits)
	t._check(int(r.blocks.mika) + int(r.blocks.luna) + int(r.dodges.mika) + int(r.dodges.luna) >= 1, "someone blocked or dodged", [r.blocks, r.dodges])
	if mode == "duel":
		t._check(String(r.get("winner", "")) in ["mika", "luna"], "the duel has a winner (%s)" % r.get("winner", ""))
	t._check(float(r.award.mika) > 0.0 and float(r.award.luna) > 0.0, "both earned XP", r.award)
	t._check(int(watch.overlap) == 0, "their bodies never overlap (closest %.2f m)" % float(watch.min_gap))
	t._check(int(watch.out) == 0, "they stayed inside the clearing")
	t._check(int(watch.tpose) == 0, "no T-pose frames (%d)" % int(watch.tpose))
	t._check(int(watch.fx_peak) >= 12, "the magic really spawned (peak %d effect nodes)" % int(watch.fx_peak))
	t._check(d.hit_log.size() >= 3, "impacts with hit-stop (%d)" % d.hit_log.size())


## A T-pose (or A-pose): both upper arms near horizontal-out with straight elbows while the clip should be moving.
static func _tpose(d: FightDirector, id: String) -> bool:
	var n := 0
	for s in ["Left", "Right"]:
		var u := d.bone(id, s + "UpperArm")
		var l := d.bone(id, s + "LowerArm")
		var h := d.bone(id, s + "Hand")
		var a := (l - u).normalized()
		var b := (h - l).normalized()
		if absf(a.y) < 0.2 and a.dot(b) > 0.97:
			n += 1
	return n == 2
