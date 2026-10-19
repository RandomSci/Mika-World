extends RefCounted
## Combat v3 stance lab: every pose of the fight rig that is not a strike, on both girls - the fighting stance, every
## guard (cover, block high both sides, block mid, duck, slip, shin check, back step, jump and its landing), footwork
## (circling, stepping in and out), the dash - filmed from the side across the line. The joint audit runs on both
## girls every frame: locked or backwards knees, shins angled behind the knee, foot targets out of reach, thighs /
## upper arms twisted past a human hip / shoulder, stance knees more than 8 deg off front 20 / rear 27.5. Marks "[stancelab] <what> <who>
## from frame A to frame B" for stills and 10 fps strips.

const GUARDS := [["cover", "jab"], ["block_high", "hook"], ["block_high", "crescent_kick"], ["block_mid", "body_hook"], ["duck", "hook"],
	["slip", "cross"], ["check", "low_sweep"], ["backstep", "front_kick"], ["jump", "low_sweep"]]


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
	FightDirector.set_hour(main, 16.5)
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 7, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 7, "length": 9999.0, "demo": true, "start_gap": 1.4})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	var c0: Vector3 = d.center
	var gy := FightDirector.ground_y(d.F.mika.c, c0)
	var mid := Vector3(c0.x, gy + 0.9, c0.z)
	d.cut(d.ft + 0.001, "fixed", "mika", {"pos": mid + Vector3(0, 0.1, 3.9), "look": mid, "fov": 40.0})
	await t._wait(1.2)
	# 1. the stance, both girls, still and from the side
	var a0 := Engine.get_frames_drawn()
	var fm: MeleeFighter = sim.F.mika
	for i in 60:
		await t.get_tree().process_frame
		if i % 3 == 0:
			var st := []
			for side in ["lf", "rf"]:
				var ft: Dictionary = fm.feet[side]
				st.append("%s b%.0f r%.3f %s%s" % [side, fm.bend_of(side), float(fm.reach_ratio[side]), "S" if not (ft.step as Dictionary).is_empty() else "-", "A" if ft.air else "-"])
			print("[stancelab] ts %.2f corr %.3f shift %.3f vel %.2f root %s | %s | tag '%s'" % [fm.life_t, fm.stance_corr, fm.stance_shift, fm._root_vel.length(), str((fm.sk.global_transform.origin).snappedf(0.001)), " ".join(st), fm.move_tag])
	var knees := {}
	for id in ["mika", "luna"]:
		var f: MeleeFighter = sim.F[id]
		knees[id] = [snappedf(f.bend_of("lf"), 0.1), snappedf(f.bend_of("rf"), 0.1), snappedf(float(f.reach_ratio.lf), 0.001), snappedf(float(f.reach_ratio.rf), 0.001)]
	print("[stancelab] stance both from frame %d to frame %d" % [a0, Engine.get_frames_drawn()])
	print("[stancelab] stance knees (front, rear deg; foot reach front, rear in leg lengths): ", JSON.stringify(knees))
	for id in knees:
		t._check(absf(float(knees[id][0]) - MeleeFighter.STANCE_FRONT) <= 3.0 and absf(float(knees[id][1]) - MeleeFighter.STANCE_REAR) <= 3.0,
			"%s's stance knees bend %.0f / %.0f deg (front 17 - 23 / rear 24.5 - 30.5)" % [id, float(knees[id][0]), float(knees[id][1])])
	# 2. every guard, Luna then Mika
	for who in ["luna", "mika"]:
		var other := "mika" if who == "luna" else "luna"
		for g in GUARDS:
			await _reset(t, d, sim)
			await t._wait(0.35)
			var m: Dictionary = MeleeBook.MOVES[g[1]]
			var atk := {"name": "lab", "m": m, "by": other, "vs": who, "t0": sim.t, "t_hit": sim.t + 0.7, "limb": m.limb, "surf": "fist",
				"locked": Vector3.INF, "outcome": "", "contact": Vector3.INF, "dir": Vector3.ZERO, "phase": "wind", "react_delay": -1.0, "defence": ""}
			var b0 := Engine.get_frames_drawn()
			sim._defend(sim.S[who], sim.S[other], String(g[0]), atk)
			var w0: float = t._game_t
			while String(sim.S[who].state) == "defend" and t._game_t - w0 < 2.0:
				await t.get_tree().process_frame
			await t._wait(0.3)
			print("[stancelab] %s_vs_%s %s from frame %d to frame %d" % [g[0], g[1], who, b0, Engine.get_frames_drawn()])
	# 3. footwork: circling, stepping in and out
	await _reset(t, d, sim)
	sim.footwork = true
	var f0 := Engine.get_frames_drawn()
	d.cut(d.ft + 0.001, "duo", "mika", {"k": 1.0, "high": 0.2, "min": 3.4})
	await t._wait(4.0)
	print("[stancelab] footwork both from frame %d to frame %d" % [f0, Engine.get_frames_drawn()])
	sim.footwork = false
	# 4. the dash in (a rush) and her landing after a jump
	await _reset(t, d, sim)
	for id in sim.F:
		(sim.F[id] as MeleeFighter).audit_hold = 4
	d.F.mika.pos = c0 - Vector3(2.6, 0, 0)
	d.F.luna.pos = c0 + Vector3(2.6, 0, 0)
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	for id in sim.F:
		(sim.F[id] as MeleeFighter).replant()
	await t._wait(0.5)
	sim.S.luna.p.late = 1.0
	var r0 := Engine.get_frames_drawn()
	sim._rush(sim.S.mika, sim.S.luna)
	await t._wait(1.4)
	print("[stancelab] dash mika from frame %d to frame %d" % [r0, Engine.get_frames_drawn()])
	# the audit
	var groups := {}
	var frames := 0
	var total := 0
	for id in sim.F:
		var f: MeleeFighter = sim.F[id]
		frames += f.joint_frames
		for fl in f.joint_faults:
			total += 1
			var key := "%s %s in %s: %s" % [id, fl.limb, fl.pose, String(fl.why).get_slice(" (", 0).get_slice(" turned", 0).get_slice(" %", 0)]
			if not groups.has(key):
				groups[key] = [0, fl]
			groups[key][0] = int(groups[key][0]) + 1
	for key in groups:
		print("[stancelab] FAULT x%d %s  e.g. %s" % [groups[key][0], key, JSON.stringify(groups[key][1])])
	for id in sim.F:
		print("[stancelab] audited frames by pose, %s: %s" % [id, JSON.stringify((sim.F[id] as MeleeFighter).frames_by_pose)])
	t._check(frames > 300, "joint audit ran on %d frames (both girls)" % frames)
	t._check(total == 0, "every pose: no locked or backwards knee, no shin behind a knee, no foot out of reach, no impossible twist (%d faults)" % total)
	sim.teardown()
	d.teardown()


static func _reset(t, d: FightDirector, sim: MeleeSim) -> void:
	for id in sim.F:
		(sim.F[id] as MeleeFighter).audit_hold = 4          # (the lab places them by hand: no audit until replanted)
	var c0: Vector3 = d.center
	d.F.mika.pos = c0 - Vector3(0.7, 0, 0)
	d.F.luna.pos = c0 + Vector3(0.7, 0, 0)
	for id in sim.S:
		sim.S[id].glide = {}
		sim.S[id].vel = Vector3.ZERO
		sim.S[id].state = "free"
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	for id in sim.F:
		(sim.F[id] as MeleeFighter).replant()
