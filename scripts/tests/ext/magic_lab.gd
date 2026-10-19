extends RefCounted
## Combat v3 magic lab: every spell with a body - the gesture, the energy gathering at her hand, the release from the
## hand, the shape flying / erupting / holding, and where it lands on the other girl. Mika casts her set at Luna, Luna
## hers at Mika (no defence), then a defended round: the other girl reads each one and sidesteps, jumps or raises a
## barrier. Filmed from the side. Marks "[magiclab] <spell> <round> from frame A to frame B". Checks: each spell
## resolves (hit / block / miss), the defended round avoids or blocks most, the joint audit stays at 0.

const MIKA := ["star_bolt", "frost_orb", "ice_spikes", "star_beam", "ice_blade", "star_spear"]
const LUNA := ["moon_crescent", "violet_orb", "moon_thorns", "violet_wave", "lunar_beam", "violet_scythe", "moon_whip"]


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
	FightDirector.set_hour(main, 19.6)
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
	if main.get("subtitle") and main.subtitle:
		main.subtitle.visible = false
	await t._wait(1.5)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "duel", {"seed": 11, "axis_deg": 0.0, "bare": true})
	var sim := MeleeSim.make(d, {"seed": 11, "length": 9999.0, "demo": true})
	d.set_process(true)
	await t.get_tree().process_frame
	sim.start()
	var only := String(RenderProfile.options.get("spell", ""))
	var results := []
	for rnd in ["open", "defended"]:
		for who in ["mika", "luna"]:
			var other := "luna" if who == "mika" else "mika"
			sim.S[other].p.late = 1.0 if rnd == "open" else 0.0
			sim.S[other].p.magic = 1.0
			for spell in (MIKA if who == "mika" else LUNA):
				if only != "" and spell != only:
					continue
				var sp: Dictionary = SpellBook.SPELLS[spell]
				var r: Array = sp.range
				var gap := clampf((float(r[0]) + float(r[1])) * 0.5, float(r[0]) + 0.1, 5.5)
				await _place(t, d, sim, who, gap)
				for id in sim.S:
					sim.S[id].energy = 100.0
				var a0 := Engine.get_frames_drawn()
				var n0 := sim.attacks.size()
				sim.magic.cast(sim.S[who], sim.S[other], spell)
				var w0: float = t._game_t
				while (String(sim.S[who].state) == "attack" or sim.attacks.size() == n0) and t._game_t - w0 < 4.0:
					await t.get_tree().process_frame
				await t._wait(0.9)
				var outs := []
				for a in sim.attacks.slice(n0):
					outs.append(String(a.outcome))
				results.append([rnd, who, spell, outs])
				print("[magiclab] %s %s from frame %d to frame %d  %s" % [spell, rnd, a0, Engine.get_frames_drawn(), JSON.stringify(outs)])
	var open_res := 0
	var open_n := 0
	var def_ok := 0
	var def_n := 0
	for r in results:
		var outs: Array = r[3]
		if r[0] == "open":
			open_n += 1
			if not outs.is_empty():
				open_res += 1
		else:
			def_n += 1
			if "miss" in outs or "block" in outs:
				def_ok += 1
	var faults := 0
	for id in sim.F:
		faults += (sim.F[id] as MeleeFighter).joint_faults.size()
		for fl in (sim.F[id] as MeleeFighter).joint_faults.slice(0, 6):
			print("[magiclab] FAULT %s %s" % [id, JSON.stringify(fl)])
	t._check(open_n > 0 and open_res == open_n, "every spell resolves on its target (%d of %d)" % [open_res, open_n])
	t._check(def_n == 0 or def_ok * 2 >= def_n, "the defended round dodges or blocks most (%d of %d)" % [def_ok, def_n])
	t._check(faults == 0, "joint audit through every gesture: %d faults" % faults)
	print("[magiclab] vfx ", JSON.stringify(sim.magic.svfx.stats))
	sim.teardown()
	d.teardown()


static func _place(t, d: FightDirector, sim: MeleeSim, who: String, gap: float) -> void:
	var c0: Vector3 = d.center
	for id in sim.F:
		(sim.F[id] as MeleeFighter).audit_hold = 4
	var sgn := -1.0 if who == "mika" else 1.0
	d.F[who].pos = c0 + Vector3(gap * 0.5 * sgn, 0, 0)
	d.F["luna" if who == "mika" else "mika"].pos = c0 - Vector3(gap * 0.5 * sgn, 0, 0)
	for id in sim.S:
		sim.S[id].glide = {}
		sim.S[id].vel = Vector3.ZERO
		sim.S[id].state = "free"
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	for id in sim.F:
		(sim.F[id] as MeleeFighter).replant()
	var gy := FightDirector.ground_y(d.F.mika.c, c0)
	var mid := Vector3(c0.x, gy + 1.0, c0.z)
	# three-quarter from behind the caster's side (Download(9) films its mage this way): the spell grows in front of her, not hidden by her
	var caster: Vector3 = d.F[who].pos
	var tgt_p: Vector3 = d.F["luna" if who == "mika" else "mika"].pos
	var fw := Vector3(tgt_p.x - caster.x, 0, tgt_p.z - caster.z).normalized()
	var sd := fw.cross(Vector3.UP).normalized()
	d.cut(d.ft + 0.001, "fixed", "mika", {"pos": Vector3(caster.x, gy + 1.6, caster.z) - fw * 1.0 + sd * 4.6, "look": Vector3(caster.x, gy, caster.z).lerp(Vector3(tgt_p.x, gy, tgt_p.z), 0.4) + Vector3.UP * 1.1, "fov": 50.0})
	await t._wait(0.45)
