extends RefCounted
## A 20 s spar of paired exchanges (2026-10-20, Selwyn: the suit mocap is the fight's body; "a 20 second spar built from
## them as paired exchanges rendered next to my Download(7) reference"). PairedPlay on a demo MeleeSim, the fight's
## cinematographer (FightCine) on the contacts. Both girls lead four exchanges each. Options: --weapon-level=20 (the
## Gale Rapier and the Shadow Glaive). Prints "[spar] <beat> at <fight s> frame N" and every contact ("[paired] ...").

## [beat, attacker, attack clip, answers [hit index, answer, clip, meet s, extra]]
const BEATS := [
	["cleave / block", "luna", "sword:great_sword_slash_4", [[1, "block", "ualf:Sword_Block", 0.35]]],
	["combo / guards then a cut", "mika", "ualf:Sword_Regular_Combo", [[0, "block", "sword:great_sword_blocking", 0.25],
		[1, "block", "sword:great_sword_blocking_3", 0.25], [2, "block", "sword:great_sword_blocking", 0.25], [3, "hit", "sword:great_sword_impact", 0.08]]],
	["spin / duck and block", "luna", "sword:great_sword_high_spin_attack", [[1, "dodge", "sword:great_sword_crouching_4", 0.2],
		[2, "block", "ualf:Sword_Block", 0.35]]],
	["dash through / block", "mika", "ualf:Sword_Dash", [[0, "block", "sword:great_sword_blocking_3", 0.25]]],
	["three cuts / block, parry, hit", "luna", "sword:great_sword_slash_2", [[0, "block", "ualf:Sword_Block", 0.35],
		[1, "parry", "ualf:Sword_Regular_B", 0.27], [2, "hit", "ualf:Hit_Chest", 0.05]]],
	["thrust / hit", "mika", "ualf:Sword_Attack", [[0, "hit", "sword:great_sword_impact_2", 0.1]]],
	["leaping cleave / roll under", "luna", "sword:great_sword_jump_attack", [[2, "dodge", "ualf:Roll", 0.35]]],
	["heavy combo / knockdown", "mika", "ualf:Sword_Heavy_Combo", [[0, "block", "sword:great_sword_blocking", 0.25],
		[1, "block", "sword:great_sword_blocking_2", 0.35], [2, "hit", "sword:great_sword_impact_3", 0.1],
		[3, "knock", "ualf:Hit_Knockback", 0.05, "ualf:LayToIdle"]]],
]


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
	FightDirector.set_hour(main, float(RenderProfile.options.get("hour", "18.2")))
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 7, "axis_deg": 20.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 7, "length": 9999.0, "demo": true, "melee": true, "start_gap": 3.0})
	sim.footwork = false
	d.cut(0.0, "duo", "mika", {"k": 1.0, "high": 0.35})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	sim.cine = FightCine.make(sim)
	var pp := PairedPlay.make(sim)
	var tick := func():
		pp.update()
		if sim.cine:
			sim.cine.update()
	var wait := func(s: float) -> void:
		var w0: float = sim.t
		while sim.t < w0 + s:
			tick.call()
			await t.get_tree().process_frame
	await wait.call(0.8)
	print("[spar] start at %.2f frame %d" % [sim.t, Engine.get_frames_drawn()])
	var n_by := {"mika": 0, "luna": 0}
	for bt in BEATS:
		var a := String(bt[1])
		var b := "luna" if a == "mika" else "mika"
		var answers := []
		for an in bt[3]:
			var e := {"hit": int(an[0]), "answer": String(an[1]), "clip": String(an[2]), "meet": float(an[3])}
			if (an as Array).size() > 4:
				e["then"] = String(an[4])
			answers.append(e)
		print("[spar] %s at %.2f frame %d" % [bt[0], sim.t, Engine.get_frames_drawn()])
		n_by[a] = int(n_by[a]) + 1
		var span := pp.exchange({"a": a, "b": b, "atk": String(bt[2]), "answers": answers})
		await wait.call(span + 0.15)
	await wait.call(1.0)
	print("[spar] end at %.2f frame %d" % [sim.t, Engine.get_frames_drawn()])
	var tally := {}
	for r in pp.rows:
		tally[String(r.answer)] = int(tally.get(String(r.answer), 0)) + 1
		print("[spar] row ", JSON.stringify(r))
	t._check(n_by.mika == n_by.luna and pp.rows.size() >= 12, "paired exchanges %s, contacts %s" % [str(n_by), str(tally)])
	for id in ["mika", "luna"]:
		pp.wp.sheathe(id)
	await t._wait(0.5)
	sim.teardown()
	d.teardown()
