extends RefCounted
## Combat v3 reaction lab: Mika lands every kind of reaction on Luna, in a fixed order, each filmed from the side -
## head flinch (jab), head stagger (hook), side stagger (body hook), stomach knock-back (front kick), launch
## (launcher) then a juggle (jab in the air), knockdown (low sweep), block-stun (cross into a cover), guard pushed open
## (roundhouse into a mid block), guard break (front kick into a mid block on a tired guard). Marks "[reactlab]
## <name> from frame A to frame B" for 10 fps strips; the joint audit and the reaction names are checked. --no-physics
## runs the same without partial physics (for comparison).

const PLAN := [["head_flinch", "jab", ""], ["head_stagger", "hook", ""], ["side_stagger", "body_hook", ""],
	["stomach_knockback", "front_kick", ""], ["launch", "launcher", ""], ["juggle", "jab", "air"],
	["knockdown", "low_sweep", ""], ["blockstun", "cross", "cover"], ["guard_open", "roundhouse", "block_mid"],
	["guard_break", "front_kick", "block_mid!"]]


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
	FightDirector.set_hour(main, 15.5)
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 9, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 9, "length": 9999.0, "demo": true})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	sim.S.luna.p.late = 1.0
	sim.S.luna.p.read = 0.0
	var got := {}
	for step in PLAN:
		var name: String = step[0]
		var move: String = step[1]
		var how: String = step[2]
		if how != "air":
			await _place(t, d, sim, move)
		var a0 := Engine.get_frames_drawn()
		if how.begins_with("cover") or how.begins_with("block_mid"):
			if how.ends_with("!"):
				sim.S.luna.block_load = 1.8                # (a tired guard: this one breaks it)
			sim._attack(sim.S.mika, sim.S.luna, move)
			await t._wait(0.06)
			sim._defend(sim.S.luna, sim.S.mika, how.trim_suffix("!"), sim.S.mika.atk)
		elif how == "air":
			sim._attack(sim.S.mika, sim.S.luna, move)
		else:
			sim._attack(sim.S.mika, sim.S.luna, move)
		var w0: float = t._game_t
		while String(sim.S.mika.state) == "attack" and t._game_t - w0 < 2.5:
			await t.get_tree().process_frame
		var last: Dictionary = sim.attacks[-1] if not sim.attacks.is_empty() else {}
		got[name] = [String(last.get("outcome", "")), String(last.get("reaction", "")), String(last.get("zone", ""))]
		if name == "launch":
			await t._wait(0.05)                          # (the juggle follows while she is still in the air)
		else:
			await t._wait(1.1 if name != "knockdown" else 2.2)
		print("[reactlab] %s from frame %d to frame %d  %s" % [name, a0, Engine.get_frames_drawn(), JSON.stringify(got[name])])
	var faults := 0
	for id in sim.F:
		faults += (sim.F[id] as MeleeFighter).joint_faults.size()
		for fl in (sim.F[id] as MeleeFighter).joint_faults.slice(0, 6):
			print("[reactlab] FAULT %s %s" % [id, JSON.stringify(fl)])
	var want := {"head_flinch": "flinch", "head_stagger": "stagger", "side_stagger": "stagger", "stomach_knockback": "knockback",
		"launch": "launch", "juggle": "juggle", "knockdown": "knockdown", "blockstun": "blockstun", "guard_open": "guard_open", "guard_break": "guard_break"}
	var ok := 0
	for n in want:
		if got.has(n) and String(got[n][1]) == String(want[n]):
			ok += 1
		else:
			print("[reactlab] MISMATCH %s wanted %s got %s" % [n, want[n], JSON.stringify(got.get(n, []))])
	t._check(ok == want.size(), "%d of %d reactions as planned" % [ok, want.size()])
	t._check(faults == 0, "joint audit through every reaction: %d faults" % faults)
	sim.teardown()
	d.teardown()


static func _place(t, d: FightDirector, sim: MeleeSim, move: String) -> void:
	var m: Dictionary = MeleeBook.MOVES[move]
	var gap := float(m.reach) + 0.1
	var c0: Vector3 = d.center
	for id in sim.F:
		(sim.F[id] as MeleeFighter).audit_hold = 4
	d.F.mika.pos = c0 - Vector3(gap * 0.5, 0, 0)
	d.F.luna.pos = c0 + Vector3(gap * 0.5, 0, 0)
	for id in sim.S:
		sim.S[id].glide = {}
		sim.S[id].vel = Vector3.ZERO
		sim.S[id].state = "free"
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	for id in sim.F:
		(sim.F[id] as MeleeFighter).replant()
	var gy := FightDirector.ground_y(d.F.mika.c, c0)
	var mid := Vector3(c0.x, gy + 0.95, c0.z)
	d.cut(d.ft + 0.001, "fixed", "mika", {"pos": mid + Vector3(0.5, 0.25, 3.9), "look": mid + Vector3(0.4, 0, 0), "fov": 44.0})
	await t._wait(0.5)
