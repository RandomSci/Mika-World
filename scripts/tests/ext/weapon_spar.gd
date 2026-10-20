extends RefCounted
## A 20 s weapon sparring exchange (2026-10-20, Selwyn: "both girls fight with their weapons (dash through, parry and
## riposte, shaft block, plant and burst)"), on the fight's cinematographer (FightCine), through WeaponPlay: Mika's
## rapier, Luna's glaive (conjured light blades below Level 20; --weapon-level=20 shows the Gale Rapier and the Shadow
## Glaive). Prints "[spar] <beat> at <fight s> frame N" and every exchange's outcome ("[weapon] ...").

const BEATS := [
	# [fight s, beat, attacker, attack clip, defender, defence clip (or "")] (eye checked 20 October: the shaft block is a
	# HIGH block, it meets the downward aerial thrust; the blade clash is the mid block)
	[0.4, "draw", "mika", "r_salute_draw", "luna", "g_two_hand_spin"],
	[3.4, "dash through", "mika", "r_dash_through", "luna", ""],
	[6.4, "thrust / parry and riposte", "luna", "g_long_thrust", "mika", "r_parry_riposte"],
	[9.6, "aerial thrust / shaft block", "mika", "r_aerial_thrust", "luna", "g_shaft_block"],
	[12.2, "sweep / backstep counter", "luna", "g_wide_sweep", "mika", ""],
	[15.0, "plant and burst", "luna", "g_plant_burst", "mika", ""],
	[17.4, "lunge / blade clash", "mika", "r_lunge_thrust", "luna", "s_blade_clash"],
	[20.0, "finishers", "mika", "r_sheathe_finish", "luna", "g_finish_pose"],
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
	var sim := MeleeSim.make(d, {"seed": 7, "length": 9999.0, "demo": true, "melee": true, "start_gap": 3.2})
	sim.footwork = true
	d.cut(0.0, "duo", "mika", {"k": 1.0, "high": 0.35})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	sim.cine = FightCine.make(sim)
	var wp := WeaponPlay.make(sim)
	sim.set_meta("weapon_play", wp)
	for id in ["mika", "luna"]:
		print("[spar] %s weapon level %d (%s)" % [id, FightWeapon.level_of(id), "real" if FightWeapon.level_of(id) >= 20 else "conjured"])
	var t0: float = sim.t
	var cine_tick := func():
		if sim.cine:
			sim.cine.update()
	sim.set_meta("cine_tick", cine_tick)
	for bt in BEATS:
		var at := t0 + float(bt[0])
		while sim.t < at:
			cine_tick.call()
			await t.get_tree().process_frame
		var a := String(bt[2])
		var b := String(bt[4])
		print("[spar] %s at %.2f frame %d" % [bt[1], sim.t, Engine.get_frames_drawn()])
		# a fresh line for every exchange: apart (4 m), the axis turned 40 deg from the last, so each strike crosses
		# ground and the cinematographer finds a new side
		if String(bt[1]) != "draw" and String(bt[1]) != "finishers":
			var ang := deg_to_rad(20.0 + 40.0 * float(BEATS.find(bt)))
			var ax := Vector3(cos(ang), 0, sin(ang))
			var c0 := (sim.d.pos("mika") + sim.d.pos("luna")) * 0.5
			c0 = c0.lerp(d.center, 0.5)
			var gap := 4.2 if String(bt[1]) != "dash through" else 5.0
			var pa: Vector3 = c0 - ax * gap * 0.5
			var pb: Vector3 = c0 + ax * gap * 0.5
			for pr in [[a, pa], [b, pb]]:
				var st: Dictionary = sim.S[String(pr[0])]
				st.glide = {"from": sim.d.pos(String(pr[0])), "to": d.clamp_arena(pr[1]), "t": 0.0, "dur": 0.5, "ease": "inout"}
			var w0: float = sim.t
			while sim.t < w0 + 0.55:
				cine_tick.call()
				await t.get_tree().process_frame
		match String(bt[1]):
			"draw":
				wp.draw("mika")
				wp.draw("luna")
				wp.pose(a, String(bt[3]))
				wp.pose(b, String(bt[5]))
			"finishers":
				wp.pose(a, String(bt[3]))
				wp.pose(b, String(bt[5]))
				# (the finisher's ghost slash and blade ring, FX_Cinematic_v1)
				sim.at(1.4, func():
					var gp: Vector3 = sim.d.pos("luna") + sim.d.fwd("luna") * 1.8 + Vector3.UP * 1.6
					FlipbookFX.play(sim.d.main, "fx_ghost_slash", func() -> Vector3: return gp, {"size": 7.0, "dur": 1.4, "fade_out": 0.4,
						"intensity": 1.5, "light": 4.0, "black_cut": 0.16}))
				sim.at(1.6, func():
					var rp: Vector3 = (sim.F["luna"] as MeleeFighter).trace.get("Chest", sim.d.chest("luna"))
					FlipbookFX.play(sim.d.main, "fx_blade_ring", func() -> Vector3: return rp, {"size": 3.6, "f1": 50.0, "dur": 1.0, "fade_out": 0.3,
						"intensity": 1.4, "light": 3.0, "black_cut": 0.16}))
			_:
				var atk := wp.strike(a, b, String(bt[3]))
				if String(bt[5]) != "" and not atk.is_empty():
					wp.defend(b, String(bt[5]), float(atk.t_hit))
					if String(bt[5]) == "r_parry_riposte":
						# the riposte inside her parry clip: its thrust 0.75 s after the parry frame
						var g: Array = WeaponPlay.GUARD["r_parry_riposte"]
						var rip := float(WeaponPlay.STRIKES["r_parry_riposte"][0]) - float(g[0])
						sim.at(maxf(float(atk.t_hit) - sim.t, 0.0), func(): wp.followup(b, a, "r_parry_riposte", rip))
				elif String(bt[1]).begins_with("sweep"):
					# Mika jumps back out of the sweep (her backstep's jump spans the sweep's contact) and cuts as she lands
					var tb := float(atk.t_hit) - 1.4
					sim.at(maxf(tb - sim.t, 0.0), func(): wp.strike("mika", "luna", "r_backstep_slash"))
	var end := t0 + 24.0
	while sim.t < end:
		cine_tick.call()
		await t.get_tree().process_frame
	var hits := 0
	var guards := 0
	for r in wp.log_rows:
		print("[spar] row ", JSON.stringify(r))
		if String(r.outcome) == "hit":
			hits += 1
		elif String(r.outcome) in ["block", "parry"]:
			guards += 1
	var deep := 0
	for id in wp.weapons:
		var w: FightWeapon = wp.weapons[id]
		if is_instance_valid(w) and w.deflect_deg >= FightWeapon.MAX_DEFLECT - 0.1:
			deep += 1
	t._check(hits >= 2 and guards >= 2, "the spar lands hits (%d) and guards (%d)" % [hits, guards])
	for id in ["mika", "luna"]:
		wp.sheathe(id)
	await t._wait(0.6)
	sim.teardown()
	d.teardown()
