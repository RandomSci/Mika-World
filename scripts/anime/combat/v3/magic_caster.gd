class_name MagicCaster
extends RefCounted
## Combat v3: runs a SpellBook spell on a fighter of a MeleeSim, with a body.
##   1. the gesture's windup (key poses on the rig: one hand drawn back, or both arms in, a deeper wider stance)
##   2. the energy gathers AT the hand bone (SpellVFX.charge follows the bone) for the spell's gather time; on a big
##      spell the hair and skirt lift in the gathering wind
##   3. the release FROM the hand (the arm thrown at the target - the hand aimed live at her), the shape leaves the hand:
##      a bolt / orb flies at the point she stood at the release, spikes erupt along the ground to her feet, a wave
##      skims the ground, a beam holds; a conjured weapon is drawn from light and swung (or thrown)
##   4. it lands where it really touches her: a sphere against her hurtbox capsules (BodyAwareness), stopped by her
##      barrier, or missing because she stepped out of its way - the defender reads it like a strike (MeleeSim._respond)

var sim: MeleeSim
var svfx: SpellVFX
var afx: ArcaneFX                          # the reference language (Download(9)): motes, wisps, sigils, billows, volleys, moons
var barriers := {}                        # id -> barrier handle while up


static func make(s: MeleeSim) -> MagicCaster:
	var m := MagicCaster.new()
	m.sim = s
	m.svfx = SpellVFX.make(s.vfx.get_parent(), s.vfx)
	m.afx = ArcaneFX.make(s.vfx.get_parent(), s.vfx, m.svfx)
	return m


func can_cast(s: Dictionary, name: String, dist: float) -> bool:
	var sp: Dictionary = SpellBook.SPELLS.get(name, {})
	if sp.is_empty() or not (String(sp.who) in [String(s.id), "both"]):
		return false
	if float(s.get("energy", 100.0)) < float(sp.get("energy", 0.0)):
		return false
	var r: Array = sp.get("range", [0.0, 99.0])
	return dist >= float(r[0]) and dist <= float(r[1])


## Start a spell (or a conjured weapon) at the opponent. Returns the attack dict (also s.atk).
func cast(s: Dictionary, o: Dictionary, name: String) -> Dictionary:
	var sp: Dictionary = SpellBook.SPELLS[name]
	var f: MeleeFighter = sim.F[s.id]
	var t := sim.t
	s.energy = float(s.get("energy", 100.0)) - float(sp.get("energy", 0.0))
	if String(sp.kind) == "barrier":
		return _barrier(s, o, sp)
	var g: Array = SpellBook.GESTURES[sp.gesture]
	var wind := 0.14
	var gather := float(sp.gather)
	var rel := 0.09
	var dist0 := sim._flat(sim.d.pos(o.id) - sim.d.pos(s.id)).length()
	var fly := 0.3
	if sp.has("speed"):
		fly = dist0 / float(sp.speed)
	var m := {"limb": String(sp.hand) if String(sp.hand) != "both" else "rh", "aim": sp.get("aim", "chest"), "height": sp.get("height", "mid"),
		"weight": sp.get("weight", "medium"), "from": "C", "reach": 0.0, "dmg": sp.dmg, "spell": true, "knock": sp.get("knock", 0.3),
		"launch": sp.get("launch", false), "recover": 0.22}
	var atk := {"name": name, "m": m, "by": s.id, "vs": o.id, "t0": t, "t_hit": t + wind + gather + rel + fly,
		"t_release": t + wind + gather + rel + float(sp.get("hold", 0.0)), "limb": m.limb, "surf": "fist",
		"locked": Vector3.INF, "outcome": "", "contact": Vector3.INF, "dir": Vector3.ZERO, "phase": "wind", "react_delay": -1.0, "defence": "",
		"spell": sp, "zone": "", "part": "", "touch": Vector3.INF}
	s.state = "attack"
	s.atk = atk
	(s.recent as Array).append(name)
	sim.action_starts.append(t)
	o.threat = atk
	atk.perceive_at = t + sim.rng.randf_range(0.10, 0.20)
	f.move_tag = "cast:" + name
	var hand_b := "RightHand" if String(sp.hand) != "lh" else "LeftHand"
	var src := func() -> Vector3:
		if String(sp.hand) == "both":
			var a: Vector3 = f.trace.get("LeftHand", f.sk.global_position)
			var b: Vector3 = f.trace.get("RightHand", a)
			return (a + b) * 0.5 + sim.d.fwd(s.id) * 0.1 * f.k
		var hp: Vector3 = f.trace.get(hand_b, f.sk.global_position)
		var mp: Vector3 = f.trace.get(hand_b.replace("Hand", "MiddleProximal"), hp)
		return hp + (mp - hp).normalized() * 0.09 * f.k + Vector3.UP * 0.03 * f.k
	var aim_fn := func() -> Vector3:                       # the hand thrown at her (release)
		var sh: Vector3 = f.trace.get("RightUpperArm" if String(sp.hand) != "lh" else "LeftUpperArm", f.sk.global_position)
		var tgt: Vector3 = (sim.F[o.id] as MeleeFighter).target_point(String(m.aim), sh)
		return sh + (tgt - sh).normalized() * 0.58 * f.k
	var segs := []
	var charge := {}
	var big := String(sp.gesture) in ["two_hand", "overhead"]
	segs.append({"dur": wind, "ease": "inout", "pose": g[0], "start": func():
		atk.phase = "wind"
		if big:
			_wind(f.c, Vector3.UP * 0.6 + sim.d.fwd(s.id) * -0.4, gather + wind + 0.2)})
	segs.append({"dur": gather, "ease": "hold", "pose": g[0], "start": func():
		charge.h = svfx.charge(src, s.id, gather + 0.05, float(sp.get("size", 1.0)) * (1.4 if big else 0.9))
		# the build (Download(9)): a rune sigil wipes in at her hand, light is drawn in to it from around her, and on a
		# big spell soft wisps wind round her as it gathers
		afx.sigil(src, func() -> Vector3: return sim.d.fwd(s.id), s.id, 0.42 if big else 0.28, gather + 0.15, 0.1, 6.0 if s.id == "mika" else 8.0)
		charge.gm = afx.motes(src, s.id, 90 if big else 40, 0.5, 0.9 if big else 0.45, "gather", 2.0)
		if big:
			afx.wisps(func() -> Vector3: return f.sk.global_position + Vector3.UP * 1.0 * f.k, s.id, 0.95, gather + 0.3, 4, 3.0)})
	var rel_pose: Dictionary = g[1]
	var dyn := {}
	if String(sp.gesture) in ["one_hand", "sweep"]:
		dyn[String(sp.hand)] = aim_fn
		f.palm[String(sp.hand)] = "fwd"
	segs.append({"dur": rel, "ease": "snap", "pose": rel_pose, "dyn": dyn, "start": func():
		atk.phase = "active"
		if charge.has("gm"):
			afx.stop(charge.gm, 0.6)
		_release(s, o, atk, sp, charge.get("h", {}), src)})
	segs.append({"dur": float(m.recover), "ease": "inout", "pose": {}, "start": func():
		atk.phase = "recover"
		f.palm = {"lh": "guard", "rh": "guard"},
		"end": func(): _done(s, atk)})
	f.play(segs)
	sim.events.append([snappedf(t, 0.01), "cast", s.id, name])
	return atk


## Her body is free again (the spell itself may still be flying: its attack stays open until it lands).
func _done(s: Dictionary, atk: Dictionary) -> void:
	var f: MeleeFighter = sim.F[s.id]
	if f.move_tag.begins_with("cast:"):
		f.move_tag = ""
	if String(s.state) == "attack" and s.atk == atk:
		s.state = "free"
		s.atk = {}


## The energy leaves her hand - each spell in the reference's language (see ArcaneFX).
func _release(s: Dictionary, o: Dictionary, atk: Dictionary, sp: Dictionary, ch: Dictionary, src: Callable) -> void:
	var of: MeleeFighter = sim.F[o.id]
	var f: MeleeFighter = sim.F[s.id]
	var from: Vector3 = src.call()
	var core: MeshInstance3D = svfx.release(ch) if not ch.is_empty() else null
	if core:
		svfx._vanish(core, 0.06)
	var aim := String(atk.m.aim)
	var tgt0: Vector3 = of.target_point(aim, from)
	var gy := sim.d.pos(o.id).y
	var fl := sim._flat(tgt0 - from).normalized()
	var side := fl.cross(Vector3.UP).normalized()
	var who := String(s.id)
	afx.lens_streak(from, who, 1.6, 0.14)
	var land := func(p: Vector3, r: float): _land(s, o, atk, p, r)
	match String(atk.name):
		"star_bolt":
			# star daggers: a fan bursts out of a sigil over her hand, hovers behind her, then streams at Luna
			var hold_v := float(sp.get("hold", 0.3))
			var tgt_fn := func() -> Vector3: return (sim.F[o.id] as MeleeFighter).target_point(aim, from)
			var first := {"done": false}
			atk.t_hit = sim.t + hold_v + from.distance_to(tgt0) / 26.0
			afx.volley(func() -> Vector3: return (f.trace.get("RightHand", from) as Vector3) + Vector3.UP * 0.25 * f.k,
				func() -> Vector3: return f.sk.global_position, func() -> Vector3: return sim.d.fwd(s.id), who, 9, hold_v, tgt_fn,
				func(i: int, p: Vector3):
					sim.vfx.impact(p, fl, who, 0.5, "hit")
					afx.motes(p, who, 24, 0.9, 0.08, "burst", 1.6)
					if not first.done:
						first.done = true
						atk.locked = p
						land.call(p, 0.22), 26.0, 0.04, f.k)
		"frost_orb", "violet_orb":
			# a frost star (Mika) / the full moon (Luna) grown at her hand, haloed and wreathed, flown at her, bursting
			var mh: Dictionary = afx.moon(src, who, 0.32 if who == "mika" else 0.42)
			var to_m := tgt0
			atk.locked = to_m
			var fly_m := from.distance_to(to_m) / 9.0
			atk.t_hit = sim.t + 0.35 + fly_m
			sim.at(0.35, func(): afx.moon_fly(mh, to_m, fly_m, func(p: Vector3): land.call(p, 0.65)))
		"ice_spikes":
			var a_s := Vector3(from.x, gy + 0.03, from.z)
			var b_s: Vector3 = of.trace.get("LeftFoot" if aim == "ankle_l" else "RightFoot", of.sk.global_position)
			b_s.y = gy + 0.03
			atk.locked = b_s
			var dur_s := a_s.distance_to(b_s) / 22.0
			atk.t_hit = sim.t + dur_s + 0.05
			svfx.streak(a_s, func() -> Vector3: return b_s, who, dur_s, 0.8, func(p: Vector3):
				svfx.crystal_burst(p, who, 1.0, 16, 1.3)
				afx.motes(p + Vector3.UP * 0.4, who, 140, 1.6, 0.5, "burst", 2.5)
				afx.shock_ring(p + Vector3.UP * 0.05, Vector3.UP, who, 2.2, 0.4)
				afx.lens_streak(p + Vector3.UP * 0.5, who, 3.0, 0.2)
				land.call(p + Vector3.UP * 0.4, 0.45))
		"moon_crescent":
			var dist_c := from.distance_to(tgt0)
			var dur_c := dist_c / 18.0
			atk.locked = tgt0
			atk.t_hit = sim.t + dur_c
			var nrm := side.rotated(fl, sim.rng.randf_range(-0.5, 0.5))
			svfx.slash_arc(from + fl * 0.3, nrm, Vector3.UP, 1.1, 0.35, 170.0, dur_c + 0.15, who, 3.4, fl * dist_c, 0.7)
			afx.wisps(from + fl * dist_c * 0.5, who, 1.2, dur_c + 0.4, 3, 4.0)
			var to_c := tgt0
			sim.at(dur_c, func():
				afx.billow(to_c, who, 0.6, 0.45, 80)
				land.call(to_c, 0.45))
		"moon_thorns":
			var b_t: Vector3 = sim.d.pos(o.id)
			atk.locked = b_t
			atk.t_hit = sim.t + 0.18
			sim.at(0.1, func():
				svfx.tendrils(b_t, sim.d.pos(s.id), who, 6, 1.7)
				afx.motes(b_t + Vector3.UP * 0.6, who, 120, 1.5, 0.6, "burst", 2.0)
				afx.shock_ring(b_t + Vector3.UP * 0.04, Vector3.UP, who, 2.0, 0.4)
				sim.at(0.08, func(): land.call(b_t + Vector3.UP * 0.5, 0.5)))
		"violet_wave":
			var to_w: Vector3 = sim.d.pos(o.id)
			atk.locked = to_w
			var from_w := Vector3(from.x, gy, from.z)
			var dur_w := from_w.distance_to(to_w) / 14.0
			atk.t_hit = sim.t + dur_w
			var t_w := sim.t
			svfx.slash_arc(from_w + Vector3.UP * 0.08, Vector3.UP, -side, 1.2, 0.4, 200.0, dur_w + 0.2, who, 3.2, sim._flat(to_w - from), 0.8)
			var trail_m := afx.motes(func() -> Vector3: return (from_w + Vector3.UP * 0.3).lerp(to_w, clampf((sim.t - t_w) / maxf(dur_w, 0.01), 0.0, 1.0)), who, 80, 1.0, 0.5, "drift")
			sim.at(dur_w, func():
				afx.stop(trail_m, 1.0)
				afx.billow(to_w + Vector3.UP * 0.4, who, 0.55, 0.4, 60)
				land.call(to_w + Vector3.UP * 0.35, 0.5))
		"star_beam", "lunar_beam":
			var to_b := tgt0
			atk.locked = to_b
			var hold_b := float(sp.dur)
			svfx.beam(src, func() -> Vector3: return to_b, who, hold_b, 1.6)
			afx.wisps(src, who, 0.7, hold_b + 0.3, 3, 5.0)
			afx.stop(afx.motes(src, who, 120, 0.8, 0.3, "swirl"), 0.8)
			sim.d.shake(0.25)
			sim.at(0.1, func():
				afx.billow(to_b, who, 0.9, 0.7, 180)
				if who == "luna":
					svfx.frames(to_b, who, 2, 0.8, 0.45)
				else:
					svfx.crystal_burst(Vector3(to_b.x, gy, to_b.z), who, 0.9, 10, 1.0)
				land.call(to_b, 0.3))
		_:
			if String(sp.kind) == "weapon":
				afx.sigil(src, func() -> Vector3: return sim.d.fwd(s.id), who, 0.3, 0.45, 0.08)
				afx.motes(src, who, 50, 0.7, 0.2, "burst", 1.2)
				_weapon(s, o, atk, sp)
			else:
				var to_x := tgt0
				atk.locked = to_x
				svfx.streak(from, func() -> Vector3: return to_x, who, from.distance_to(to_x) / 28.0, 1.0, func(p: Vector3): land.call(p, 0.2))


## A sphere (r) arriving at p: against her barrier, then her hurtboxes.
func _land(s: Dictionary, o: Dictionary, atk: Dictionary, p: Vector3, r: float) -> void:
	if String(atk.outcome) != "":
		return
	var of: MeleeFighter = sim.F[o.id]
	var dir := (p - (sim.F[s.id] as MeleeFighter).sk.global_position)
	dir.y *= 0.2
	dir = dir.normalized()
	atk.dir = dir
	if barriers.has(o.id) and bool(barriers[o.id].on):
		atk.outcome = "block"
		atk.touch = p
		svfx.barrier_hit(barriers[o.id], p, s.id)
		sim.d.impact(0.3, false)
		_log(s, atk, "block", "barrier")
		return
	var best := {}
	var hurt := BodyAwareness.hurtboxes(of)
	for n in hurt:
		var c: Array = hurt[n]
		var cp: Array = BodyAwareness.closest(p, p, c[0], c[1])
		var dd := (cp[0] as Vector3).distance_to(cp[1]) - float(c[2]) - r
		if dd < 0.0 and (best.is_empty() or dd < float(best.d)):
			best = {"part": n, "zone": BodyAwareness.HURT[n][3], "d": dd, "point": cp[1]}
	if best.is_empty():
		atk.outcome = "miss"
		svfx.burst_at(p, dir, s.id, 0.4)
		_log(s, atk, "miss", "")
		return
	atk.outcome = "hit"
	atk.zone = best.zone
	atk.touch = best.point
	var power: float = {"light": 0.5, "medium": 0.72, "heavy": 1.0}.get(String(atk.m.weight), 0.6)
	o.hp = float(o.hp) - float(atk.m.dmg)
	of.vibrate = true
	sim.d.impact(power, false)
	sim.d.shake(0.3 + power * 0.5)
	svfx.burst_at(best.point, dir, s.id, power)
	sim.d.face_fx(o.id, "hurt", 1.0, 0.5)
	sim._interrupt(o)
	atk.reaction = HitReactions.hit(sim, o, String(best.zone), dir, power, atk.m)
	s.energy = minf(float(s.get("energy", 0.0)) + 6.0, 100.0)
	o.energy = minf(float(o.get("energy", 0.0)) + 4.0, 100.0)
	_log(s, atk, "hit", String(best.zone))


func _log(s: Dictionary, atk: Dictionary, outcome: String, zone: String) -> void:
	sim.attacks.append({"t": snappedf(float(atk.t0), 0.01), "by": s.id, "move": atk.name, "outcome": outcome, "defence": atk.defence,
		"zone": zone, "reaction": String(atk.get("reaction", "")), "frame": Engine.get_frames_drawn(), "err": -1.0, "spell": true})
	print("[melee] %s %s by %s at %.2f s at frame %d (defence %s)" % [outcome.to_upper(), atk.name, s.id, sim.t, Engine.get_frames_drawn(), atk.defence])


## A curved barrier conjured from both hands toward the threat for ~0.7 s.
func _barrier(s: Dictionary, o: Dictionary, sp: Dictionary) -> Dictionary:
	var f: MeleeFighter = sim.F[s.id]
	var g: Array = SpellBook.GESTURES.two_hand_block
	f.move_tag = "guard:barrier"
	var center := func() -> Vector3:
		var a: Vector3 = f.trace.get("LeftHand", f.sk.global_position)
		var b: Vector3 = f.trace.get("RightHand", a)
		return (a + b) * 0.5 + sim.d.fwd(s.id) * 0.12 * f.k
	var toward := func() -> Vector3: return (sim.F[o.id] as MeleeFighter).trace.get("Chest", sim.d.pos(o.id))
	f.play([{"dur": 0.1, "ease": "snap", "pose": g[0], "start": func(): barriers[s.id] = svfx.barrier(center, toward, s.id, 0.8 * f.k)},
		{"dur": 0.6, "ease": "hold", "pose": g[1]},
		{"dur": 0.2, "ease": "inout", "pose": {}, "start": func():
			if barriers.has(s.id):
				svfx.barrier_off(barriers[s.id])
				barriers.erase(s.id)
			if f.move_tag == "guard:barrier":
				f.move_tag = ""}])
	s.state = "defend"
	s.until = sim.t + 0.75
	sim.events.append([snappedf(sim.t, 0.01), "barrier", s.id, ""])
	return {}


## A conjured weapon: drawn from light in her hand, then swung (each swing a strike that lands where the blade really
## touches her - the weapon's own capsule) or thrown (the star spear), then it dissolves.
func _weapon(s: Dictionary, o: Dictionary, atk: Dictionary, sp: Dictionary) -> void:
	var f: MeleeFighter = sim.F[s.id]
	var of: MeleeFighter = sim.F[o.id]
	var hand := f.sk.find_bone("RightHand")
	var xf := func() -> Transform3D:
		var g := f.sk.global_transform * f.sk.get_bone_global_pose(hand)
		# the grip: the weapon's length runs along her fist's knuckle line, up out of the hand
		var mp: Vector3 = f.trace.get("RightMiddleProximal", g.origin)
		var along := (mp - g.origin).normalized()                       # wrist -> knuckles
		var palm := g.basis.z.normalized()                             # palm normal
		var y := palm.cross(along).normalized()                        # across the fist, out of the thumb side
		var z := along
		var x := y.cross(z).normalized()
		return Transform3D(Basis(x, y, z), g.origin.lerp(mp, 0.6))
	var w := svfx.weapon(String(sp.weapon), xf, s.id)
	atk.weapon = w
	if sp.get("throw", false):
		# the star spear: drawn, raised, thrown
		sim.at(0.28, func():
			svfx.weapon_vanish(w)
			var from: Vector3 = svfx.weapon_tip(w)
			var to_p: Vector3 = of.target_point(String(atk.m.aim), from)
			atk.locked = to_p
			var dur := from.distance_to(to_p) / float(sp.speed)
			atk.t_hit = sim.t + dur
			var core := svfx.body(svfx.crystal(1.2, 0.05, 6, 0.75), s.id, 3.2)
			svfx.projectile(core, from, func() -> Vector3: return to_p, s.id, dur, 1.0, 0.04, func(p: Vector3): _land(s, o, atk, p, 0.2)))
		return
	# swings: the blade's own capsule (hand -> tip) against her body, each swing a fresh strike
	var n := int(sp.get("slashes", 2))
	var swing_poses := [
		{"hip_rot": Vector3(4, -40, 0), "spine": Vector3(4, 30, 0), "rh": Vector3(-0.42, 1.42, 0.12)},
		{"hip_rot": Vector3(6, 22, 0), "spine": Vector3(8, -30, 0), "rh": Vector3(0.32, 0.92, 0.46)},
		{"hip_rot": Vector3(2, -30, 0), "spine": Vector3(4, 24, 0), "rh": Vector3(-0.34, 1.0, 0.42)},
		{"hip_rot": Vector3(8, 18, 0), "spine": Vector3(10, -22, 0), "rh": Vector3(0.26, 1.46, 0.36)},
	]
	var segs := []
	for i in n:
		var a_pose: Dictionary = swing_poses[(i * 2) % swing_poses.size()]
		var b_pose: Dictionary = swing_poses[(i * 2 + 1) % swing_poses.size()]
		segs.append({"dur": 0.1, "ease": "inout", "pose": a_pose})
		segs.append({"dur": 0.09, "ease": "snap", "pose": b_pose, "start": func():
			# the blade's swing leaves a great crescent smear in its own plane (the reference's white slash arcs)
			var sh: Vector3 = f.trace.get("RightUpperArm", f.sk.global_position)
			var tip0 := svfx.weapon_tip(w)
			var fwd := sim.d.fwd(s.id)
			var nrm := (tip0 - sh).cross(fwd).normalized()
			if nrm.length() < 0.1:
				nrm = Vector3.UP
			svfx.slash_arc(sh, nrm if i % 2 == 0 else -nrm, tip0 - sh, sh.distance_to(tip0) + 0.15, 0.5, 170.0, 0.2, s.id, 3.4)
			afx.stop(afx.motes(func() -> Vector3: return svfx.weapon_tip(w), s.id, 30, 0.6, 0.05, "drift"), 0.6)
			var tr := sim.vfx.trail(func() -> Array: return [(f.trace.get("RightHand", Vector3.ZERO) as Vector3).lerp(svfx.weapon_tip(w), 0.4), svfx.weapon_tip(w)], s.id, 0.12, 2.8, 1.0),
			"end": func(): _blade_touch(s, o, atk, w, i)})
	segs.append({"dur": 0.22, "ease": "inout", "pose": {}, "start": func(): svfx.weapon_vanish(w), "end": func():
		atk.outcome = "done" if String(atk.outcome) == "" else atk.outcome
		_done(s, atk)})
	f.play(segs)


func _blade_touch(s: Dictionary, o: Dictionary, atk: Dictionary, w: Dictionary, i: int) -> void:
	var f: MeleeFighter = sim.F[s.id]
	var of: MeleeFighter = sim.F[o.id]
	var a: Vector3 = f.trace.get("RightHand", Vector3.ZERO)
	var b: Vector3 = svfx.weapon_tip(w)
	var best := {}
	var hurt := BodyAwareness.hurtboxes(of)
	for n in hurt:
		var c: Array = hurt[n]
		var cp: Array = BodyAwareness.closest(a, b, c[0], c[1])
		var dd := (cp[0] as Vector3).distance_to(cp[1]) - float(c[2]) - 0.05
		if dd < 0.0 and (best.is_empty() or dd < float(best.d)):
			best = {"part": n, "zone": BodyAwareness.HURT[n][3], "d": dd, "point": cp[1]}
	var sub := atk.duplicate()
	sub.name = String(atk.name) + "_%d" % i
	if best.is_empty():
		_log(s, sub, "miss", "")
		return
	var dir := (b - a).cross(Vector3.UP).normalized()
	var df: Dictionary = o.def if String(o.state) == "defend" else {}
	if String(best.part).begins_with("forearm") and not df.is_empty():
		sim.vfx.impact(best.point, dir, s.id, 0.7, "block")
		HitReactions.block(sim, o, dir, 0.7, atk.m, String(df.get("arm", "both")))
		sim.d.impact(0.3, false)
		_log(s, sub, "block", String(best.zone))
		return
	var power := 0.75
	o.hp = float(o.hp) - float(atk.m.dmg) * 0.6
	sim.vfx.impact(best.point, dir, s.id, power, "hit")
	sim.d.impact(power, false)
	sim.d.shake(0.4)
	sim._interrupt(o)
	sub.reaction = HitReactions.hit(sim, o, String(best.zone), dir, power, {"weight": "medium", "knock": 0.35})
	_log(s, sub, "hit", String(best.zone))


## The gathering wind of a big spell: hair and skirt lifted toward `dir` for `dur` s (the VRM springs' add-force).
func _wind(c: WorldCharacter, dir: Vector3, dur: float) -> void:
	for n in c.find_children("*", "Node3D", true, false):
		if n.get("springbone_add_force") != null:
			n.set("springbone_add_force", dir.normalized() * 0.08)
			var tw := n.create_tween()
			tw.tween_interval(dur)
			tw.tween_callback(func(): if is_instance_valid(n): n.set("springbone_add_force", Vector3.ZERO))
