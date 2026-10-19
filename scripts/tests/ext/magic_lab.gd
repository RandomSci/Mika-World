extends RefCounted
## Combat v3 magic lab: every spell with a body - the gesture, the energy gathering at her hand, the release from the
## hand, the shape flying / erupting / holding, and where it lands on the other girl. Mika casts her set at Luna, Luna
## hers at Mika (no defence), then a defended round: the other girl reads each one and sidesteps, jumps or raises a
## barrier. Filmed from the side. Marks "[magiclab] <spell> <round> from frame A to frame B". Checks: each spell
## resolves (hit / block / miss), the defended round avoids or blocks most, the joint audit stays at 0.

## (2026-10-20) Every spell is cast with its gesture clip (SpellBook clip, GestureBook timing). Options --spell=name
## (one), --spells=a,b,c (several), --who=mika|luna, --rounds=open|open,defended, --view=front (a front three-quarter
## view of the caster, to lay beside the source clip). Marks "[magiclab] cast <spell> clip <clip> frame A gather G
## release R end E" (frames drawn) for the contact sheets.


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
	var some := String(RenderProfile.options.get("spells", "")).split(",", false)
	var whos := String(RenderProfile.options.get("who", "mika,luna")).split(",", false)
	var rounds := String(RenderProfile.options.get("rounds", "open,defended")).split(",", false)
	var front := String(RenderProfile.options.get("view", "")) == "front"
	var results := []
	var ults := String(RenderProfile.options.get("ult", "")).split(",", false)
	if not ults.is_empty():
		# the ultimates, with their cinematics (UltimateCast): each from a fresh placement, the caster's camera off
		for u in ults:
			var owner := String(MoveCatalog.ULTIMATES.get(u, {}).get("owner", "mika"))
			var who_u := "luna" if owner == "luna" else "mika"
			var other_u := "luna" if who_u == "mika" else "mika"
			await _place(t, d, sim, who_u, 4.5, true)
			for id in sim.S:
				sim.S[id].energy = 100.0
			var a0 := Engine.get_frames_drawn()
			var n0 := sim.attacks.size()
			var L := UltimateCast.perform(sim, who_u, other_u, u)
			var g := GestureBook.of(u)
			var rel: float = GestureBook.at(g, float((g.release as Array)[(g.release as Array).size() - 1]))
			print("[magiclab] ult %s frame %d gather %d release %d end %d" % [u, a0, a0 + int(round(GestureBook.at(g, float(g.gather[0])) * 30.0)),
				a0 + int(round(rel * 30.0)), a0 + int(round(L * 30.0))])
			var w0: float = t._game_t
			while sim.magic.performing(who_u) and t._game_t - w0 < 12.0:
				await t.get_tree().process_frame
			await t._wait(2.6)
			var outs := []
			for a in sim.attacks.slice(n0):
				outs.append(String(a.outcome))
			print("[magiclab] ult %s outcomes %s" % [u, JSON.stringify(outs)])
		sim.teardown()
		d.teardown()
		return
	for rnd in rounds:
		for who in whos:
			var other := "luna" if who == "mika" else "mika"
			sim.S[other].p.late = 1.0 if rnd == "open" else 0.0
			sim.S[other].p.magic = 1.0
			for spell in SpellBook.spells_of(who):
				if only != "" and spell != only:
					continue
				if not some.is_empty() and not (spell in some):
					continue
				var sp: Dictionary = SpellBook.SPELLS[spell]
				var r: Array = sp.range
				var gap := clampf((float(r[0]) + float(r[1])) * 0.5, float(r[0]) + 0.1, 5.5)
				await _place(t, d, sim, who, gap, front)
				for id in sim.S:
					sim.S[id].energy = 100.0
				var a0 := Engine.get_frames_drawn()
				var n0 := sim.attacks.size()
				var nc: int = sim.magic.log_casts.size()
				sim.magic.cast(sim.S[who], sim.S[other], spell)
				if sim.magic.log_casts.size() > nc:
					var lc: Array = sim.magic.log_casts[nc]
					var t0: float = lc[0]
					print("[magiclab] cast %s clip %s frame %d gather %d release %d end %d" % [spell, lc[3], a0, a0 + int(round((float(lc[4]) - t0) * 30.0)),
						a0 + int(round((float(lc[5]) - t0) * 30.0)), a0 + int(round((float(lc[6]) - t0) * 30.0))])
				var w0: float = t._game_t
				while (sim.magic.performing(who) or String(sim.S[who].state) == "attack" or sim.attacks.size() == n0) and t._game_t - w0 < 7.0:
					await t.get_tree().process_frame
				await t._wait(1.0)
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


static func _place(t, d: FightDirector, sim: MeleeSim, who: String, gap: float, front := false) -> void:
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
	if front:
		# her front three-quarter (as the source clips film the actor), the spell leaving toward the frame's side
		d.cut(d.ft + 0.001, "fixed", "mika", {"pos": Vector3(caster.x, gy + 1.35, caster.z) + fw * 2.6 + sd * 3.4, "look": Vector3(caster.x, gy, caster.z).lerp(Vector3(tgt_p.x, gy, tgt_p.z), 0.3) + Vector3.UP * 1.1, "fov": 52.0})
	else:
		d.cut(d.ft + 0.001, "fixed", "mika", {"pos": Vector3(caster.x, gy + 1.6, caster.z) - fw * 1.0 + sd * 4.6, "look": Vector3(caster.x, gy, caster.z).lerp(Vector3(tgt_p.x, gy, tgt_p.z), 0.4) + Vector3.UP * 1.1, "fov": 50.0})
	await t._wait(0.45)
