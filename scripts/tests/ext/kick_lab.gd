extends RefCounted
## Combat v3 kick lab: Mika throws every kick at Luna (who stands in her guard and takes it), each one twice - once
## filmed from the side, once from the front - then every punch, then an exchange where Luna defends, so every
## guard pose is used too. Marks "[kicklab] <move> <view> from frame A to frame B" for 10 fps strips. The joint
## audit runs on the final pose of both girls on EVERY frame: the test fails if any knee or elbow folds backwards
## (against its own hinge, or a knee pointing behind her pelvis) or a thigh / upper arm has to turn past 120 deg.

const KICKS := ["front_kick", "roundhouse", "crescent_kick", "axe_kick", "hook_kick", "spin_back_kick", "low_sweep"]
const PUNCHES := ["jab", "cross", "hook", "uppercut", "body_hook", "palm_strike"]


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
	d.setup(main, "duel", {"seed": 5, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 5, "length": 9999.0, "demo": true})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	var only := String(RenderProfile.options.get("kick-only", ""))
	var kicks_only := RenderProfile.options.has("kicks-only")
	var moves: Array = KICKS if only == "" else [only]
	sim.S.luna.p.late = 1.0                          # she takes every kick (we film the kicker)
	d.cut(d.ft + 0.001, "fixed", "mika", {"pos": d.center + Vector3(0, 1.1, 3.6), "look": d.center + Vector3(0, 0.95, 0)})
	await t._wait(1.2)                               # (the lens settles before the first kick)
	for name in moves:
		for view in ["side", "front"]:
			await _one(t, d, sim, name, view)
	if only == "" and not kicks_only:
		for name in PUNCHES:
			await _one(t, d, sim, name, "side")
		# Luna defends now: every guard pose gets used (audited too)
		sim.S.luna.p.late = 0.0
		sim.S.luna.p.read = 0.6
		for name in ["jab", "cross", "hook", "uppercut", "body_hook", "front_kick", "roundhouse", "low_sweep", "crescent_kick", "jab", "cross", "hook"]:
			await _one(t, d, sim, name, "guarded")
	var faults: Array = []
	var frames := 0
	for id in sim.F:
		var f: MeleeFighter = sim.F[id]
		frames += f.joint_frames
		for fl in f.joint_faults:
			faults.append("%s %s" % [id, JSON.stringify(fl)])
	var groups := {}
	for id in sim.F:
		for fl in (sim.F[id] as MeleeFighter).joint_faults:
			var key := "%s %s in %s: %s" % [id, fl.limb, fl.pose, String(fl.why).get_slice(" (", 0).get_slice(" turned", 0)]
			if not groups.has(key):
				groups[key] = [0, fl]
			groups[key][0] = int(groups[key][0]) + 1
	for key in groups:
		print("[kicklab] FAULT x%d %s  e.g. %s" % [groups[key][0], key, JSON.stringify(groups[key][1])])
	var hits := 0
	for a in sim.attacks:
		print("[kicklab]   ", JSON.stringify(a))
		if String(a.outcome) in ["hit", "block"]:
			hits += 1
	t._check(frames > 300, "joint audit ran on %d frames (both girls)" % frames)
	t._check(faults.is_empty(), "no knee or elbow ever bends backwards (%d faults)" % faults.size())
	t._check(hits >= moves.size(), "%d strikes connected" % hits)
	sim.teardown()
	d.teardown()


static func _one(t, d: FightDirector, sim: MeleeSim, name: String, view: String) -> void:
	var m: Dictionary = MeleeBook.MOVES[name]
	var gap := float(m.reach) + 0.1
	var c0: Vector3 = d.center
	d.F.mika.pos = c0 - Vector3(gap * 0.5, 0, 0)
	d.F.luna.pos = c0 + Vector3(gap * 0.5, 0, 0)
	sim.S.mika.glide = {}
	sim.S.luna.glide = {}
	sim.S.mika.vel = Vector3.ZERO
	sim.S.luna.vel = Vector3.ZERO
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	for id in sim.F:
		(sim.F[id] as MeleeFighter).replant()
	var gy := FightDirector.ground_y(d.F.mika.c, c0)
	var mid := Vector3(c0.x, gy + 0.95, c0.z)
	var cam := {"pos": mid + Vector3(0, 0.15, 3.6), "look": mid, "fov": 42.0}            # side: across the line
	if view == "guarded":
		cam = {"pos": mid + Vector3(0.8, 0.2, 3.4), "look": mid, "fov": 44.0}
	if view == "front":
		var mk: Vector3 = d.F.mika.pos
		cam = {"pos": Vector3(mk.x + 2.3, gy + 1.1, mk.z + 2.6), "look": Vector3(mk.x + 0.25, gy + 0.95, mk.z), "fov": 44.0}      # three-quarter front of her, Luna clear of the line
	d.cut(d.ft + 0.001, "fixed", "mika", cam)
	await t._wait(0.45)
	var a0 := Engine.get_frames_drawn()
	sim._attack(sim.S.mika, sim.S.luna, name)
	var w0: float = t._game_t
	while String(sim.S.mika.state) == "attack" and t._game_t - w0 < 3.0:
		await t.get_tree().process_frame
	await t._wait(0.35)
	print("[kicklab] %s %s from frame %d to frame %d" % [name, view, a0, Engine.get_frames_drawn()])
	while String(sim.S.luna.state) in ["react", "down", "defend"] and t._game_t - w0 < 5.0:
		await t.get_tree().process_frame
