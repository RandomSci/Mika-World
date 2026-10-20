class_name MagicCaster
extends RefCounted
## Combat v3: runs a SpellBook spell on a fighter of a MeleeSim - every spell with its real gesture (2026-10-20).
##   1. her body performs the spell's gesture clip (Move Library v2 mocap, hands and fingers included; GestureBook has
##      which part plays, how fast, and where her releasing hand points - she turns so it points at the target). A
##      "body" clip owns all of her (the fight rig steps out), an "upper" one her torso, head, arms and hands (the rig
##      keeps her legs in the stance)
##   2. through the clip's gather window the energy gathers AT her hand (SpellVFX.charge follows the hand), inside her
##      sigil, with light drawn in and a real light in her colour on her and the ground; big spells lift her hair and
##      skirt in the gathering wind
##   3. at the clip's release frame the effect leaves the hand (or the conjured weapon swings on the clip's own cuts),
##      the floor floods with her colour, and the shape flies, erupts, falls from the sky or holds (17 shapes, below)
##   4. it lands where it really touches the other girl (a sphere against her hurtbox capsules, BodyAwareness), stopped
##      by her barrier, or missing because she moved; the defender reads it like a strike (MeleeSim._respond)
## A hit or a knockdown during the gesture aborts it: the clip stops, the charge fizzles, the rig takes her back.

var sim: MeleeSim
var svfx: SpellVFX
var afx: ArcaneFX                          # motes, wisps, sigils, billows, volleys, moons, lights
var arts: PetalArts                        # the petal arts: what the spells look like (PETALS)
var cvfx: CombatVFX                        # the sparks of the spells (hidden with the old spell look under PETALS)
var barriers := {}                        # id -> barrier handle while up
var _perf := {}                           # id -> the gesture she is performing {atk, g, charge, motes, until}
var log_casts: Array = []                 # QA: [t, id, spell, clip, gather start, release, end] (fight seconds)


static func make(s: MeleeSim) -> MagicCaster:
	var m := MagicCaster.new()
	m.sim = s
	m.cvfx = s.vfx
	m.arts = PetalArts.make(s)
	if PETALS:
		# (Selwyn 2026-10-20: one look, the petal arts; the old spell shapes keep their timing and hits but are not
		# drawn: their nodes live under hidden parents)
		m.cvfx = CombatVFX.make(s.vfx.get_parent())
		m.cvfx.name = "SpellSparksHidden"
		m.cvfx.visible = false
	m.svfx = SpellVFX.make(s.vfx.get_parent(), m.cvfx)
	m.afx = ArcaneFX.make(s.vfx.get_parent(), m.cvfx, m.svfx)
	if PETALS:
		m.svfx.visible = false
		m.afx.visible = false
	return m


func can_cast(s: Dictionary, name: String, dist: float) -> bool:
	var sp: Dictionary = SpellBook.SPELLS.get(name, {})
	if sp.is_empty() or not (String(sp.who) in [String(s.id), "both"]):
		return false
	if GestureBook.of(String(sp.clip)).is_empty():
		return false                                  # (no spell without its gesture)
	if float(s.get("energy", 100.0)) < float(sp.get("energy", 0.0)):
		return false
	var r: Array = sp.get("range", [0.0, 99.0])
	return dist >= float(r[0]) and dist <= float(r[1])


func performing(id: String) -> bool:
	return _perf.has(id)


# ------------------------------------------------------------------------------------------------ the body
## Her body takes the gesture clip: the clip plays from g.from at g.speed, the rig steps out (body) or keeps only her
## legs (upper), she turns by -aim so the releasing hand points at the target. Returns its length in fight seconds.
## opts (the gesture director): speed (her pace, 0.85 to 1.15), use ("upper" while she walks), fade (blend in).
func _perform(s: Dictionary, g: Dictionary, clip: String, opts := {}) -> float:
	var f: MeleeFighter = sim.F[s.id]
	var spd := float(opts.get("speed", g.speed))
	var L := GestureBook.length(g) * float(g.speed) / spd
	sim.d.anim(s.id, "ml_" + clip, float(g.from), float(g.to), spd, float(opts.get("fade", 0.12)))
	if String(opts.get("use", g.use)) == "body":
		f.rig_w = 0.0
		f.upper_clip = 0.0
	else:
		f.rig_w = 1.0
		f.upper_clip = 1.0
	sim.d.F[s.id].yaw_extra = -deg_to_rad(float(g.get("aim", 0.0)))
	f.play([{"dur": L, "ease": "hold", "pose": {}}])           # (the rig waits, her stance kept for the legs)
	return L


## The gesture is over (or broken off): the rig takes her back, feet planted where the clip left them.
func _release_body(id: String) -> void:
	var f: MeleeFighter = sim.F[id]
	if f.rig_w < 0.5:
		f.replant()
	f.rig_w = 1.0
	f.upper_clip = 0.0
	sim.d.F[id].yaw_extra = 0.0
	sim.d.stance(id, 0.2)
	sim.S[id].weapon_hand = ""
	_perf.erase(id)


## A blow broke her gesture: the energy fizzles, the clip stops, the rig takes her back (the reaction plays on it).
func abort(id: String) -> void:
	if not _perf.has(id):
		return
	var p: Dictionary = _perf[id]
	# a blow in her gather breaks it hard: the reaction is a stagger, never the small flinch (HitReactions)
	var atk0: Dictionary = p.get("atk", {})
	if not atk0.is_empty() and String(atk0.get("phase", "")) == "gather":
		sim.S[id].gather_broken = true
	if p.has("charge") and not (p.charge as Dictionary).is_empty():
		svfx.cancel(p.charge)
	if p.get("motes"):
		afx.stop(p.motes, 0.3)
	var st_a = p.get("storm")
	if st_a and is_instance_valid(st_a):
		var at_a: Vector3 = hand_point(sim.F[id], "Right")
		(st_a as PetalStorm).scatter(func() -> Vector3: return at_a, 0.9, 0.8)
		(st_a as PetalStorm).finish()
	if p.get("weapon"):
		svfx.weapon_vanish(p.weapon)
	var card_a = p.get("card")
	if card_a and is_instance_valid(card_a):
		(card_a as FlipbookFX).stop(0.1)
	_release_body(id)


# ------------------------------------------------------------------------------------------------ her hands
## Where the energy sits on her hand (final pose): the palm's centre a little out from it, or a fingertip.
func hand_point(f: MeleeFighter, side: String, tip := "") -> Vector3:
	var hp: Vector3 = f.trace.get(side + "Hand", f.sk.global_position)
	var mp: Vector3 = f.trace.get(side + "MiddleProximal", hp)
	if tip == "index":
		return f.trace.get(side + "IndexDistal", mp) as Vector3 + (mp - hp).normalized() * 0.02 * f.k
	var out := (mp - hp)
	var palm := hp.lerp(mp, 0.55)
	# a little off the palm, away from her body (the energy sits in front of the hand, not inside it)
	var chest: Vector3 = f.trace.get("UpperChest", hp)
	var off := (palm - chest)
	off.y *= 0.3
	return palm + off.normalized() * 0.05 * f.k + out.normalized() * 0.02 * f.k


func _src(f: MeleeFighter, hand: String, tip := "") -> Callable:
	match hand:
		"both":
			return func() -> Vector3:
				return (hand_point(f, "Left") + hand_point(f, "Right")) * 0.5
		"lh":
			return func() -> Vector3: return hand_point(f, "Left", tip)
		"rf", "lf":
			var side := "Right" if hand == "rf" else "Left"
			return func() -> Vector3: return f.trace.get(side + "Foot", f.sk.global_position) as Vector3
	return func() -> Vector3: return hand_point(f, "Right", tip)


# ------------------------------------------------------------------------------------------------ casting
## Start a spell (or a conjured weapon) at the opponent. Returns the attack dict (also s.atk).
## `over` (an ultimate) replaces the SpellBook entry: the same body, gather and release, bigger shapes; its "kinds"
## gives one shape per release frame of the clip (a combo of shapes), "pre" the shape of every release but the last.
## `opts` (from the GestureDirector): her pace, upper body only, the blend in (see _perform); the gesture's times scale
## with her pace.
func cast(s: Dictionary, o: Dictionary, name: String, over := {}, opts := {}) -> Dictionary:
	var sp: Dictionary = over if not over.is_empty() else SpellBook.SPELLS[name]
	var clip := String(sp.clip)
	var g := GestureBook.of(clip)
	if g.is_empty():
		push_error("[magic] %s has no gesture clip" % name)
		return {}
	var f: MeleeFighter = sim.F[s.id]
	var t := sim.t
	s.energy = float(s.get("energy", 100.0)) - float(sp.get("energy", 0.0))
	if _perf.has(s.id):
		abort(s.id)
	var k := float(g.speed) / float(opts.get("speed", g.speed))
	var rels: Array = []
	for r in g.release:
		rels.append(GestureBook.at(g, float(r)) * k)
	var t_g0 := GestureBook.at(g, float(g.gather[0])) * k
	var t_rel: float = rels[0]
	var L := _perform(s, g, clip, opts)
	var who := String(s.id)
	var big := String(sp.kind) in ["beam", "meteor", "sky", "domain", "eclipse", "pillars", "seal", "rows", "orb"]
	var hand := String(g.hand)
	var tip := "index" if clip in ["finger_snap_point", "sky_call_point"] else ""
	var src := _src(f, hand, tip)
	var emit := _src(f, String(g.get("emit", hand)), tip)
	log_casts.append([snappedf(t, 0.01), who, name, clip, snappedf(t + t_g0, 0.01), snappedf(t + t_rel, 0.01), snappedf(t + L, 0.01)])
	sim.events.append([snappedf(t, 0.01), "cast", who, name])
	f.move_tag = "cast:" + name
	_perf[who] = {"g": g, "until": t + L}
	sim.at(L, func():
		if _perf.has(who) and float(_perf[who].until) <= sim.t + 0.01:
			_release_body(who)
		if f.move_tag == "cast:" + name:
			f.move_tag = "")
	if String(sp.kind) == "barrier":
		return _barrier(s, o, sp, t_rel, L, src)
	var m := {"limb": hand if hand in ["lh", "rh"] else "rh", "aim": sp.get("aim", "chest"), "height": sp.get("height", "mid"),
		"weight": sp.get("weight", "medium"), "from": "C", "reach": 0.0, "dmg": sp.dmg, "spell": true, "knock": sp.get("knock", 0.3),
		"launch": sp.get("launch", false), "recover": 0.22}
	var dist0 := sim._flat(sim.d.pos(o.id) - sim.d.pos(s.id)).length()
	var fly := dist0 / float(sp.get("speed", 20.0))
	var atk := {"name": name, "m": m, "by": s.id, "vs": o.id, "t0": t, "t_hit": t + t_rel + fly, "t_release": t + t_rel, "limb": m.limb,
		"surf": "fist", "locked": Vector3.INF, "outcome": "", "contact": Vector3.INF, "dir": Vector3.ZERO, "phase": "wind", "react_delay": -1.0,
		"defence": "", "spell": sp, "zone": "", "part": "", "touch": Vector3.INF, "clip": clip}
	s.state = "attack"
	s.atk = atk
	(s.recent as Array).append(name)
	sim.action_starts.append(t)
	o.threat = atk
	atk.perceive_at = t + sim.rng.randf_range(0.10, 0.20)
	_perf[who].atk = atk
	var alive := func() -> bool: return String(atk.outcome) != "interrupted" and _perf.has(who)
	# --- the gather, at her hand, through the clip's gather window
	var gather_len := maxf(t_rel - t_g0, 0.15)
	sim.at(t_g0, func():
		if not alive.call():
			return
		atk.phase = "gather"
		var size := float(sp.get("size", 1.0))
		var ch := svfx.charge(src, who, gather_len + 0.05, size * (1.4 if big else 0.9))
		_perf[who].charge = ch
		var nrm := func() -> Vector3:
			var p: Vector3 = src.call()
			var c: Vector3 = f.trace.get("UpperChest", p)
			var v := p - c
			return v.normalized() if v.length() > 0.05 else sim.d.fwd(who)
		if PETALS:
			# (Selwyn 2026-10-20: the petal technique; no more circles) the storm gathers into her hand
			var n_g := 3200 if big else 2000
			if PetalArts.carded(who, String(sp.kind)):
				n_g = int(n_g * PetalArts.CARD_EXTRA)          # (the video card is the look; the petals an extra layer)
			var storm := PetalStorm.make(sim.d.main, who, n_g)
			storm.ground(sim.d.pos(who).y)
			storm.gather(src, gather_len)
			_perf[who].storm = storm
			_perf[who].card = arts.gather_card(who, src, gather_len, big)
			arts.aura(f, who, gather_len * 0.8, gather_len * 0.2 + 0.1, big)
		else:
			afx.sigil(src, nrm, who, (0.5 if big else 0.32) * f.k, gather_len + 0.2, 0.12, 6.0 if who == "mika" else 8.0)
			_perf[who].motes = afx.motes(src, who, 110 if big else 50, 0.55, 0.9 if big else 0.45, "gather", 2.0)
		afx.glow(src, who, 4.0 if big else 2.4, 3.5 if big else 2.2, gather_len + 0.25, minf(gather_len * 0.6, 0.5), 0.25)
		if big:
			afx.wisps(func() -> Vector3: return f.sk.global_position + Vector3.UP * 1.0 * f.k, who, 1.0, gather_len + 0.4, 4, 3.0)
			_wind(f.c, Vector3.UP * 0.6 + sim.d.fwd(who) * -0.4, gather_len + 0.3)
		if sp.get("sigil_drawn", false) and not PETALS:
			_drawn_sigil(f, who, g, src)
		if String(sp.kind) == "array":
			var ta := GestureBook.at(g, float(g.extra.array)) * k - t_g0
			sim.at(maxf(ta, 0.0), func():
				if alive.call():
					_array_open(s, o, src))
		if String(sp.kind) == "weapon":
			s.weapon_hand = hand
			_perf[who].weapon = _conjure(s, sp, hand)
			atk.weapon = _perf[who].weapon)
	# --- the release(s), at the clip's frames
	if String(sp.kind) == "weapon":
		_weapon(s, o, atk, sp, rels, alive)
		return atk
	sim.at(t_rel if not sp.has("kinds") and not sp.has("pre") else rels[rels.size() - 1], func():
		if not alive.call():
			return
		atk.phase = "active"
		if _perf[who].get("motes"):
			afx.stop(_perf[who].motes, 0.6)
		var sp_last := sp.duplicate()
		if sp.has("kinds"):
			sp_last.kind = (sp.kinds as Array)[(sp.kinds as Array).size() - 1]
		_release(s, o, atk, sp_last, _perf[who].get("charge", {}), emit))
	if sp.has("kinds") or sp.has("pre"):
		# the clip's earlier release frames: each its own shape (a kick's comet before the landing ring, the palms of a
		# flurry before the last one), lighter, a fresh attack each so every one can land
		for i in rels.size() - 1:
			var kind_i: String = (sp.kinds as Array)[mini(i, (sp.kinds as Array).size() - 1)] if sp.has("kinds") else String(sp.pre)
			sim.at(float(rels[i]), func():
				if not alive.call():
					return
				var sub := atk.duplicate()
				sub.name = name + "_%d" % i
				sub.outcome = ""
				var sp_i := sp.duplicate()
				sp_i.kind = kind_i
				sp_i.size = float(sp.get("size", 1.0)) * 0.6
				sp_i.dmg = float(sp.dmg) * 0.3
				sp_i.n = 3
				_release(s, o, sub, sp_i, {}, emit))
	return atk


## Her body is free again (the spell itself may still be flying: its attack stays open until it lands).
func _done(s: Dictionary, atk: Dictionary) -> void:
	if String(s.state) == "attack" and s.atk == atk:
		s.state = "free"
		s.atk = {}


## The energy leaves her hand at the release frame - the floor floods with her colour, then the shape.
func _release(s: Dictionary, o: Dictionary, atk: Dictionary, sp: Dictionary, ch: Dictionary, src: Callable) -> void:
	var of: MeleeFighter = sim.F[o.id]
	var f: MeleeFighter = sim.F[s.id]
	var from: Vector3 = src.call()
	var card0 = _perf.get(String(s.id), {}).get("card")
	if card0 and is_instance_valid(card0) and not ch.is_empty():
		(card0 as FlipbookFX).stop(0.12)
	if sim.realm:
		var big_r := String(sp.kind) in ["beam", "meteor", "sky", "domain", "eclipse", "pillars", "seal", "rows", "orb", "vortex", "wave"]
		sim.realm.push(String(s.id), 1.0 if sp.get("ultimate", false) else (0.32 if big_r else 0.14))
		sim.realm.pulse(1.0 if sp.get("ultimate", false) else (0.7 if big_r else 0.35))
	var core: MeshInstance3D = svfx.release(ch) if not ch.is_empty() else null
	if core:
		svfx._vanish(core, 0.06)
	var aim := String(atk.m.aim)
	var tgt0: Vector3 = of.target_point(aim, from)
	var gy := sim.d.pos(o.id).y
	var fl := sim._flat(tgt0 - from).normalized()
	var side := fl.cross(Vector3.UP).normalized()
	var who := String(s.id)
	var size := float(sp.get("size", 1.0))
	afx.lens_streak(from, who, 1.6 * size, 0.14)
	afx.flood(Vector3(from.x, gy, from.z), who, 3.0 + size * 1.5, 7.0, 0.6)
	var land := func(p: Vector3, r: float):
		_land(s, o, atk, p, r)
		if String(atk.outcome) != "":
			afx.flood(Vector3(p.x, gy, p.z), who, 4.0 * size, 8.0, 0.8)
	sim.at(0.25, func(): _done(s, atk))
	match String(sp.kind):
		"volley":
			# a half ring of star shards bursts out of a sigil over her pointing hand, hovers, then streams one by one
			var hold_v := 0.3
			var tgt_fn := func() -> Vector3: return (sim.F[o.id] as MeleeFighter).target_point(aim, from)
			var first := {"done": false}
			atk.t_hit = sim.t + hold_v + from.distance_to(tgt0) / 26.0
			afx.volley(func() -> Vector3: return (src.call() as Vector3) + Vector3.UP * 0.3 * f.k,
				func() -> Vector3: return f.sk.global_position, func() -> Vector3: return sim.d.fwd(s.id), who, int(sp.get("n", 12)), hold_v, tgt_fn,
				func(i: int, p: Vector3):
					cvfx.impact(p, fl, who, 0.5, "hit")
					afx.motes(p, who, 24, 0.9, 0.08, "burst", 1.6)
					if not first.done:
						first.done = true
						atk.locked = p
						land.call(p, 0.22), 26.0, 0.05, f.k)
		"orb":
			# a frost star (Mika) or a small full moon with orbit rings (Luna) grown at her hands, flown, bursting
			var mh: Dictionary = afx.moon(src, who, 0.34 * size)
			var to_m := tgt0
			atk.locked = to_m
			var fly_m := from.distance_to(to_m) / float(sp.get("speed", 9.0))
			atk.t_hit = sim.t + 0.3 + fly_m
			afx.glow(func() -> Vector3: return (mh.root as Node3D).global_position if is_instance_valid(mh.root) else Vector3.INF, who, 3.0, 4.0, 0.3 + fly_m + 0.2, 0.1, 0.2)
			sim.at(0.3, func(): afx.moon_fly(mh, to_m, fly_m, func(p: Vector3):
				afx.billow(p, who, 0.9, 0.6, 160)
				afx.shock_ring(p, fl, who, 2.2, 0.35)
				land.call(p, 0.65)))
		"rows":
			# two rows of faceted ice spikes erupt in sequence from her stomp to the target and past it
			var a_r := Vector3(from.x, gy + 0.02, from.z)
			var b_r: Vector3 = of.trace.get("LeftFoot" if aim == "ankle_l" else "RightFoot", of.sk.global_position)
			b_r.y = gy + 0.02
			var dirr := sim._flat(b_r - a_r)
			var dl := dirr.length()
			dirr = dirr.normalized()
			var sd := dirr.cross(Vector3.UP).normalized()
			var n := int(sp.get("n", 9))
			var step := (dl + 1.2) / float(n)
			atk.locked = b_r
			atk.t_hit = sim.t + (dl / step) * 0.055 + 0.05
			var lanes: Array = [-1.0, 1.0] if int(sp.get("lanes", 2)) <= 2 else [-2.0, -1.0, 0.0, 1.0, 2.0]
			for i in n:
				for lane in lanes:
					var p_i: Vector3 = a_r + dirr * step * float(i + 1) + sd * lane * (0.35 + 0.08 * float(i))
					sim.at(0.055 * float(i) + (0.025 if lane > 0 else 0.0), func():
						svfx.crystal_burst(p_i, who, 0.45 + 0.04 * float(i), 6, 0.9 + 0.08 * float(i))
						cvfx.dust(p_i, Vector3.UP, 4, 0.5))
			sim.at((dl / step) * 0.055, func():
				svfx.crystal_burst(b_r, who, 1.1, 16, 1.5)
				afx.motes(b_r + Vector3.UP * 0.4, who, 140, 1.6, 0.5, "burst", 2.5)
				afx.shock_ring(b_r + Vector3.UP * 0.05, Vector3.UP, who, 2.4, 0.4)
				afx.lens_streak(b_r + Vector3.UP * 0.5, who, 3.0, 0.2)
				land.call(b_r + Vector3.UP * 0.4, 0.5))
		"beam":
			var to_b := tgt0
			atk.locked = to_b
			var hold_b := float(sp.get("dur", 0.6))
			afx.sigil(src, func() -> Vector3: return fl, who, 0.55 * f.k, hold_b + 0.3, 0.1, 6.0 if who == "mika" else 8.0)
			svfx.beam(src, func() -> Vector3: return to_b, who, hold_b, 1.8 * size)
			if sp.get("twin", false):
				# two sigils, one at each hand, their beams crossing on her
				var lh := func() -> Vector3: return hand_point(f, "Left") + side * 0.6 + Vector3.UP * 0.3
				var rh := func() -> Vector3: return hand_point(f, "Right") - side * 0.6 + Vector3.UP * 0.3
				svfx.beam(lh, func() -> Vector3: return to_b, who, hold_b, 1.4 * size)
				svfx.beam(rh, func() -> Vector3: return to_b, who, hold_b, 1.4 * size)
				afx.sigil(lh, func() -> Vector3: return fl, who, 0.6, hold_b + 0.3, 0.1, 8.0)
				afx.sigil(rh, func() -> Vector3: return fl, who, 0.6, hold_b + 0.3, 0.1, 8.0)
			afx.glow(src, who, 6.0, 6.0, hold_b + 0.2, 0.05, 0.25)
			afx.wisps(src, who, 0.7, hold_b + 0.3, 3, 5.0)
			sim.d.shake(0.25)
			sim.at(0.1, func():
				afx.billow(to_b, who, 1.0, 0.7, 200)
				if who == "luna":
					svfx.frames(to_b, who, 2, 0.9, 0.45)
				else:
					svfx.crystal_burst(Vector3(to_b.x, gy, to_b.z), who, 1.0, 12, 1.1)
				land.call(to_b, 0.3))
		"meteor":
			# star meteors fall one after another across the target's ground, each a frost crater and a ring
			var c_m: Vector3 = sim.d.pos(o.id)
			var n_m := int(sp.get("n", 7))
			var first_m := {"done": false}
			atk.t_hit = sim.t + 0.55
			for i in n_m:
				var off := Vector3(sim.rng.randf_range(-1.8, 1.8), 0, sim.rng.randf_range(-1.8, 1.8)) if i != 2 else Vector3.ZERO
				var to_g := Vector3(c_m.x, gy, c_m.z) + off
				var sky := to_g + Vector3(sim.rng.randf_range(-1.5, 1.5), 8.0, 0) - fl * 2.5
				sim.at(0.12 * float(i), func():
					var core_m := svfx.body(svfx.crystal(0.9, 0.12, 6, 0.6), who, 3.4)
					svfx.projectile(core_m, sky, func() -> Vector3: return to_g, who, 0.45, 1.6, 0.0, func(p: Vector3):
						svfx.crystal_burst(p, who, 0.9, 10, 1.0)
						afx.shock_ring(p + Vector3.UP * 0.04, Vector3.UP, who, 2.0, 0.35)
						afx.flood(p, who, 3.0, 5.0, 0.4)
						cvfx.dust(p, Vector3.UP, 10, 0.8)
						sim.d.shake(0.15)
						if (p - sim.d.pos(o.id)).length() < 1.2:
							if not first_m.done:
								first_m.done = true
								land.call(p + Vector3.UP * 0.6, 0.7)))
			sim.at(0.12 * float(n_m) + 0.5, func():
				if String(atk.outcome) == "":
					atk.outcome = "miss"
					_log(s, atk, "miss", ""))
		"sky":
			# a pillar of starlight (Mika) or slanting moon rays (Luna) down from the sky onto her, a curtain of light
			var to_s := tgt0
			var top := Vector3(to_s.x, gy + 9.0, to_s.z) - fl * (0.5 if who == "mika" else 3.0)
			atk.locked = to_s
			atk.t_hit = sim.t + 0.12
			for k2 in (1 if who == "mika" else 3):
				var lat := side * (float(k2) - 1.0) * 0.35
				svfx.beam(func() -> Vector3: return top + lat, func() -> Vector3: return to_s + lat, who, 0.55, 2.2 * size)
			afx.glow(to_s + Vector3.UP * 1.5, who, 7.0, 7.0, 0.8, 0.05, 0.5)
			sim.d.shake(0.35)
			sim.at(0.1, func():
				afx.billow(to_s, who, 1.2, 0.8, 220)
				afx.rays(Vector3(to_s.x, gy + 0.2, to_s.z), who, 18, 2.6, 0.35)
				afx.shock_ring(Vector3(to_s.x, gy + 0.05, to_s.z), Vector3.UP, who, 3.0, 0.45)
				if who == "mika":
					svfx.crystal_burst(Vector3(to_s.x, gy, to_s.z), who, 1.3, 16, 1.6)
				else:
					svfx.frames(to_s, who, 3, 1.1, 0.6)
				land.call(to_s, 0.45))
		"arrow":
			# the arrow leaves the bow hand and splits into a fan of star bolts
			var n_a := int(sp.get("n", 5))
			var first_a := {"done": false}
			var dist_a := from.distance_to(tgt0)
			atk.t_hit = sim.t + dist_a / float(sp.get("speed", 24.0))
			for i in n_a:
				var spread := (float(i) - float(n_a - 1) * 0.5) * 0.16
				var to_a := from + (tgt0 - from).rotated(Vector3.UP, spread) if i != n_a / 2 else tgt0
				svfx.streak(from, func() -> Vector3: return to_a, who, dist_a / float(sp.get("speed", 24.0)), 0.8, func(p: Vector3):
					cvfx.impact(p, fl, who, 0.5, "hit")
					svfx.crystal_burst(Vector3(p.x, gy, p.z), who, 0.4, 5, 0.6)
					if not first_a.done and (p - tgt0).length() < 0.6:
						first_a.done = true
						land.call(p, 0.25))
		"vortex":
			# a spinning blizzard travels across the ground at her
			var a_v := Vector3(from.x, gy, from.z)
			var b_v: Vector3 = sim.d.pos(o.id)
			var dur_v := a_v.distance_to(b_v) / float(sp.get("speed", 6.0))
			atk.locked = b_v
			atk.t_hit = sim.t + dur_v
			var t_v := sim.t
			var pos_v := func() -> Vector3: return a_v.lerp(b_v, clampf((sim.t - t_v) / maxf(dur_v, 0.01), 0.0, 1.0)) + Vector3.UP * 0.6
			var mv := afx.motes(pos_v, who, 160, 1.0, 0.9, "swirl", 3.0)
			afx.glow(pos_v, who, 3.0, 4.0, dur_v + 0.3, 0.1, 0.3)
			var steps := int(ceil(dur_v / 0.08))
			for i in steps:
				sim.at(0.08 * float(i), func(): svfx.swirl((pos_v.call() as Vector3) - Vector3.UP * 0.55, who, 0.9 * size, 0.4, 3))
			sim.at(dur_v, func():
				afx.stop(mv, 1.0)
				afx.billow(b_v + Vector3.UP * 0.5, who, 0.8, 0.5, 120)
				land.call(b_v + Vector3.UP * 0.5, 0.6))
		"domain":
			# her ground: rings of crystals (Mika) or light (Luna) run out from her, a dome of light, the field stays
			var c_d := Vector3(from.x, gy, from.z)
			var R := float(sp.get("size", 4.5))
			for i in 4:
				var r_i := R * float(i + 1) / 4.0
				sim.at(0.09 * float(i), func():
					afx.shock_ring(c_d + Vector3.UP * 0.05, Vector3.UP, who, r_i, 0.45)
					svfx.ground_ring(c_d, who, r_i, 0.5)
					for j in 8 + i * 4:
						var a := TAU * float(j) / float(8 + i * 4) + float(i) * 0.3
						var pj := c_d + Vector3(cos(a), 0, sin(a)) * r_i
						if who == "mika":
							svfx.crystal_burst(pj, who, 0.3, 4, 0.6 + 0.15 * float(i))
						else:
							afx.motes(pj + Vector3.UP * 0.3, who, 16, 1.4, 0.2, "swirl", 1.0))
			afx.flood(c_d, who, 7.0, R * 2.5, float(sp.get("linger", 4.0)))
			afx.wisps(c_d + Vector3.UP * 1.0, who, R * 0.6, float(sp.get("linger", 4.0)), 6, 1.5)
			afx.motes(c_d + Vector3.UP * 2.0, who, 260, 3.5, R * 0.8, "drift", 0.4)
			sim.d.shake(0.35)
			var to_d: Vector3 = of.target_point(aim, from)
			atk.locked = to_d
			atk.t_hit = sim.t + 0.25
			if sim._flat(to_d - c_d).length() <= R + 0.4:
				sim.at(0.25, func(): land.call(to_d, 0.5))
			else:
				sim.at(0.3, func():
					if String(atk.outcome) == "":
						atk.outcome = "miss"
						_log(s, atk, "miss", ""))
		"crescent":
			var dist_c := from.distance_to(tgt0)
			var dur_c := dist_c / float(sp.get("speed", 16.0))
			atk.locked = tgt0
			atk.t_hit = sim.t + dur_c
			var nrm := side.rotated(fl, sim.rng.randf_range(-0.5, 0.5))
			svfx.slash_arc(from + fl * 0.3, nrm, Vector3.UP, 1.3 * size, 0.4, 170.0, dur_c + 0.15, who, 3.6, fl * dist_c, 0.7)
			for k3 in int(sp.get("fan", 0)):
				# a fan of crescents round the first (the waltz's ring of moon blades)
				var yaw := (float(k3) - float(int(sp.fan) - 1) * 0.5) * 0.28
				var fl2 := fl.rotated(Vector3.UP, yaw)
				sim.at(0.04 * float(k3), func(): svfx.slash_arc(from + fl2 * 0.3, side.rotated(Vector3.UP, yaw), Vector3.UP, 1.0 * size, 0.35, 160.0,
					dur_c + 0.2, who, 3.2, fl2 * dist_c * 1.1, 0.7))
			afx.wisps(from + fl * dist_c * 0.5, who, 1.2, dur_c + 0.4, 3, 4.0)
			var t_c := sim.t
			afx.glow(func() -> Vector3: return from.lerp(tgt0, clampf((sim.t - t_c) / maxf(dur_c, 0.01), 0.0, 1.0)), who, 3.0, 4.0, dur_c + 0.2, 0.05, 0.2)
			var to_c := tgt0
			sim.at(dur_c, func():
				afx.billow(to_c, who, 0.7, 0.45, 90)
				land.call(to_c, 0.45))
		"array":
			# the array opened under her palm (at the clip's palm-to-ground frame); now the thorns erupt in rings
			var b_t: Vector3 = sim.d.pos(o.id)
			atk.locked = b_t
			atk.t_hit = sim.t + 0.18
			sim.at(0.08, func():
				svfx.tendrils(b_t, sim.d.pos(s.id), who, 7, 1.9)
				for i in int(sp.get("n", 7)):
					var a := TAU * float(i) / float(sp.get("n", 7))
					svfx.tendrils(b_t + Vector3(cos(a), 0, sin(a)) * 1.3, b_t, who, 2, 1.2)
				afx.motes(b_t + Vector3.UP * 0.6, who, 140, 1.5, 0.7, "burst", 2.0)
				afx.shock_ring(b_t + Vector3.UP * 0.04, Vector3.UP, who, 2.4, 0.45)
				sim.at(0.08, func(): land.call(b_t + Vector3.UP * 0.5, 0.55)))
		"pillars":
			# rows of violet light pillars erupt in sequence over her side of the arena, toward and round her
			var c_p: Vector3 = sim.d.pos(o.id)
			var a_p := Vector3(from.x, gy, from.z)
			var dp := sim._flat(c_p - a_p).normalized()
			var sp_p := dp.cross(Vector3.UP).normalized()
			var n_p := int(sp.get("n", 10))
			atk.locked = c_p
			atk.t_hit = sim.t + 0.45
			for i in n_p:
				var row := float(i / 2)
				var lane := -1.0 if i % 2 == 0 else 1.0
				var p_p: Vector3 = c_p - dp * 1.6 + dp * row * 0.75 + sp_p * lane * (0.6 + 0.25 * row)
				p_p.y = gy
				sim.at(0.06 * row, func():
					svfx.tendrils(p_p, p_p + dp, who, 3, 2.2)
					afx.motes(p_p + Vector3.UP * 1.0, who, 30, 1.6, 0.25, "swirl", 1.5)
					afx.flood(p_p, who, 1.5, 3.0, 0.5))
			sim.at(0.45, func():
				svfx.tendrils(c_p, a_p, who, 6, 2.6)
				afx.shock_ring(c_p + Vector3.UP * 0.05, Vector3.UP, who, 2.6, 0.45)
				land.call(c_p + Vector3.UP * 0.6, 0.6))
		"seal":
			# a large crescent seal opens over her, then rings of light whirl round her over a ground glyph
			var c_s: Vector3 = sim.d.pos(o.id)
			atk.locked = c_s
			atk.t_hit = sim.t + 0.4
			afx.sigil(c_s + Vector3.UP * 2.6, Vector3.DOWN, who, 1.4 * size, 1.2, 0.2, 8.0)
			afx.sigil(c_s + Vector3.UP * 0.04, Vector3.UP, who, 1.6 * size, 1.4, 0.15, 8.0)
			afx.glow(c_s + Vector3.UP * 2.0, who, 6.0, 6.0, 1.2, 0.1, 0.5)
			sim.at(0.3, func():
				for i in 3:
					sim.at(0.06 * float(i), func(): svfx.swirl(c_s + Vector3.UP * (0.3 + 0.5 * float(i)), who, 1.1, 0.5, 4))
				svfx.frames(c_s, who, 3, 1.2, 0.6)
				afx.rays(c_s + Vector3.UP * 1.0, who, 16, 2.0, 0.3)
				land.call(c_s + Vector3.UP * 1.0, 0.7))
		"eclipse":
			# a dark violet eclipse sphere with a silver corona hangs over the field, rains tracer lines on her, then
			# drops onto her
			var c_e: Vector3 = sim.d.pos(o.id)
			var hang := c_e.lerp(Vector3(from.x, gy, from.z), 0.35) + Vector3.UP * 3.2
			var eh: Dictionary = afx.moon(func() -> Vector3: return hang, who, 0.6 * size)
			afx.glow(hang, who, 5.0, 8.0, float(sp.get("linger", 4.0)), 0.3, 0.6)
			afx.flood(Vector3(c_e.x, gy, c_e.z), who, 3.0, 10.0, 1.5)
			var n_e := int(sp.get("n", 6))
			var first_e := {"done": false}
			atk.t_hit = sim.t + 0.9
			for i in n_e:
				sim.at(0.5 + 0.16 * float(i), func():
					var to_e: Vector3 = sim.d.pos(o.id) + Vector3(sim.rng.randf_range(-0.6, 0.6), 0.9, sim.rng.randf_range(-0.6, 0.6))
					svfx.streak(hang, func() -> Vector3: return to_e, who, 0.18, 0.7, func(p: Vector3):
						cvfx.impact(p, Vector3.DOWN, who, 0.5, "hit")
						afx.shock_ring(Vector3(p.x, gy + 0.04, p.z), Vector3.UP, who, 1.0, 0.3)
						if not first_e.done:
							first_e.done = true
							land.call(p, 0.35)))
			sim.at(0.5 + 0.16 * float(n_e) + 0.6, func():
				afx.moon_fly(eh, Vector3(c_e.x, gy + 0.3, c_e.z), 0.35, func(p: Vector3):
					afx.billow(p, who, 1.4, 0.9, 260)
					afx.shock_ring(p, Vector3.UP, who, 3.5, 0.5)
					afx.flood(p, who, 6.0, 9.0, 0.9)
					sim.d.shake(0.4)))
		"wave":
			var to_w: Vector3 = sim.d.pos(o.id)
			atk.locked = to_w
			var from_w := Vector3(from.x, gy, from.z)
			var dur_w := from_w.distance_to(to_w) / float(sp.get("speed", 10.0))
			atk.t_hit = sim.t + dur_w
			var t_w := sim.t
			svfx.slash_arc(from_w + Vector3.UP * 0.1, Vector3.UP, -side, 1.4 * size, 0.45, 200.0, dur_w + 0.2, who, 3.4, sim._flat(to_w - from), 0.8)
			var trail_m := afx.motes(func() -> Vector3: return (from_w + Vector3.UP * 0.3).lerp(to_w, clampf((sim.t - t_w) / maxf(dur_w, 0.01), 0.0, 1.0)), who, 90, 1.0, 0.6, "drift")
			sim.at(dur_w, func():
				afx.stop(trail_m, 1.0)
				afx.billow(to_w + Vector3.UP * 0.4, who, 0.6, 0.45, 70)
				land.call(to_w + Vector3.UP * 0.35, 0.55))
		_:
			var to_x := tgt0
			atk.locked = to_x
			svfx.streak(from, func() -> Vector3: return to_x, who, from.distance_to(to_x) / 28.0, 1.0, func(p: Vector3): land.call(p, 0.2))
	if PETALS:
		# the look of it: the storm gathered in her hand leaves it in this spell's shape (the last release takes it)
		var pf: Dictionary = _perf.get(who, {})
		var storm = pf.get("storm") if not ch.is_empty() else null
		if not ch.is_empty():
			pf.erase("storm")
		var locked: Vector3 = atk.get("locked", tgt0)
		arts.release({"who": who, "kind": String(sp.kind), "src": src, "from": from,
			"target": func() -> Vector3: return of.trace.get("Chest", sim.d.chest(String(o.id))),
			"at": locked, "fly": float(atk.get("t_hit", sim.t + 0.5)) - sim.t, "gy": gy, "fl": fl, "side": side, "size": size,
			"n": int(sp.get("n", 0)) if sp.has("n") else 12, "ult": bool(sp.get("ultimate", false)), "ok": of.k, "storm": storm, "sp": sp})


## Luna's sigil beam: her fingertip draws the circle and its line in the air (the clip's draw window) and the circle
## stays there as a sigil until the beam goes through it.
func _drawn_sigil(f: MeleeFighter, who: String, g: Dictionary, src: Callable) -> void:
	var dr: Array = g.extra.draw
	var t0 := GestureBook.at(g, float(dr[0])) - GestureBook.at(g, float(g.gather[0]))
	var t1 := GestureBook.at(g, float(g.extra.line[1])) - GestureBook.at(g, float(g.gather[0]))
	var tip := func() -> Vector3: return hand_point(f, "Right", "index")
	sim.at(maxf(t0, 0.0), func():
		var tr := sim.vfx.trail(func() -> Array: return [(tip.call() as Vector3) + Vector3.UP * 0.012, (tip.call() as Vector3) - Vector3.UP * 0.012], who, t1 - t0 + 0.9, 3.4, 1.4)
		if tr is Dictionary:
			tr["hist_max"] = 60)


## The array under her palm opens at the clip's palm-to-ground frame, and its twin under the other girl.
func _array_open(s: Dictionary, o: Dictionary, src: Callable) -> void:
	var who := String(s.id)
	var p: Vector3 = src.call()
	var gy := sim.d.pos(s.id).y
	afx.sigil(Vector3(p.x, gy + 0.03, p.z), Vector3.UP, who, 1.1, 1.6, 0.15, 8.0)
	afx.flood(Vector3(p.x, gy, p.z), who, 3.0, 5.0, 1.2)
	var q: Vector3 = sim.d.pos(o.id)
	afx.sigil(Vector3(q.x, gy + 0.03, q.z), Vector3.UP, who, 1.4, 1.6, 0.2, 8.0)


## The petal arts (Selwyn 2026-10-20, his Bankai reference): every spell is drawn as her petal storm taking the
## spell's shape (PetalArts); the old spell shapes keep their timing and hits, hidden.
const PETALS := true


## Her wall (barrier_raise): it forms at her palms at the clip's release frame and widens as her arms spread, held
## until the clip ends.
func _barrier(s: Dictionary, o: Dictionary, sp: Dictionary, t_rel: float, L: float, src: Callable) -> Dictionary:
	var f: MeleeFighter = sim.F[s.id]
	var who := String(s.id)
	f.move_tag = "guard:barrier"
	var g := GestureBook.of(String(sp.clip))
	var t_w := GestureBook.at(g, float(g.extra.widen))
	var toward := func() -> Vector3: return (sim.F[o.id] as MeleeFighter).trace.get("Chest", sim.d.pos(o.id))
	var center := func() -> Vector3: return (src.call() as Vector3) + sim.d.fwd(who) * 0.15 * f.k
	afx.glow(src, who, 2.5, 2.5, t_rel + 0.1, t_rel * 0.7, 0.1)
	if PETALS:
		var ws := PetalStorm.make(sim.d.main, who, 2200)
		var body := func() -> Vector3: return f.trace.get("Chest", sim.d.chest(who))
		ws.gather(src, maxf(t_rel, 0.3)).shield(body, 0.8 * f.k, maxf(L - t_rel, 0.6) + 0.4).scatter(body, 1.3, 1.0)
		ws.finish()
	sim.at(t_rel, func():
		if not _perf.has(who):
			return
		barriers[who] = svfx.barrier(center, toward, who, 0.75 * f.k)
		afx.glow(center, who, 3.5, 4.0, L - t_rel, 0.05, 0.3)
		afx.flood(sim.d.pos(who), who, 2.5, 5.0, 0.5))
	sim.at(t_w, func():
		if barriers.has(who):
			var mi = barriers[who].get("core")
			if mi and is_instance_valid(mi):
				var tw := (mi as Node3D).create_tween()
				tw.tween_property(mi, "scale", (mi as Node3D).scale * 1.5, 0.25).set_ease(Tween.EASE_OUT))
	sim.at(L - 0.05, func():
		if barriers.has(who):
			svfx.barrier_off(barriers[who])
			barriers.erase(who)
		if f.move_tag == "guard:barrier":
			f.move_tag = "")
	s.state = "defend"
	s.until = sim.t + L
	sim.events.append([snappedf(sim.t, 0.01), "barrier", who, String(sp.clip)])
	return {}


## A weapon drawn from light into her hand through the gather (the clip's hand grips it).
func _conjure(s: Dictionary, sp: Dictionary, hand: String) -> Dictionary:
	var f: MeleeFighter = sim.F[s.id]
	var side := "Left" if hand == "lh" else "Right"
	var hb := f.sk.find_bone(side + "Hand")
	var xf := func() -> Transform3D:
		var gt := f.sk.global_transform * f.sk.get_bone_global_pose(hb)
		# the grip: the weapon's length runs along her fist's knuckle line, up out of the hand
		var mp: Vector3 = f.trace.get(side + "MiddleProximal", gt.origin)
		var along := (mp - gt.origin).normalized()
		var palm := gt.basis.z.normalized()
		var y := palm.cross(along).normalized()
		var z := along
		var x := y.cross(z).normalized()
		var b := Basis(x, y, z)
		if sp.get("greatsword", false):
			b = b.scaled(Vector3(2.4, 2.4, 2.4))
		return Transform3D(b, gt.origin.lerp(mp, 0.6))
	var w := svfx.weapon(String(sp.weapon), xf, s.id)
	if PETALS:
		(w.root as Node).reparent(svfx.get_parent())          # (the conjured weapon stays drawn: it is in her hand)
	afx.sigil(func() -> Vector3: return f.trace.get(side + "Hand", f.sk.global_position), func() -> Vector3: return sim.d.fwd(s.id), s.id, 0.3, 0.45, 0.08)
	afx.motes(func() -> Vector3: return svfx.weapon_tip(w), s.id, 50, 0.7, 0.2, "burst", 1.2)
	afx.glow(func() -> Vector3: return svfx.weapon_tip(w), s.id, 2.5, 2.5, 1.5, 0.2, 0.4)
	return w


## The conjured weapon on the clip's own cuts: at each release frame the blade's crescent smear in its plane, the
## blade's capsule (hand -> tip) against her body; a thrown spear leaves the hand at the throw frame; a draw cut (iaido,
## the greatsword) also sends a crescent wave along the ground. Then it dissolves.
func _weapon(s: Dictionary, o: Dictionary, atk: Dictionary, sp: Dictionary, rels: Array, alive: Callable) -> void:
	var f: MeleeFighter = sim.F[s.id]
	var of: MeleeFighter = sim.F[o.id]
	var who := String(s.id)
	atk.t_hit = sim.t + float(rels[0])
	if sp.get("throw", false):
		sim.at(float(rels[0]), func():
			if not alive.call() or not _perf[who].get("weapon"):
				return
			var w: Dictionary = _perf[who].weapon
			atk.phase = "active"
			svfx.weapon_vanish(w)
			var from: Vector3 = svfx.weapon_tip(w)
			var to_p: Vector3 = of.target_point(String(atk.m.aim), from)
			atk.locked = to_p
			var dur := from.distance_to(to_p) / float(sp.speed)
			atk.t_hit = sim.t + dur
			if PETALS:
				# the spear flies as one heavy petal comet, the burst at her hand as it leaves
				var card_t = _perf[who].get("card")
				if card_t and is_instance_valid(card_t):
					(card_t as FlipbookFX).stop(0.12)
				if who == "mika":
					FlipbookFX.play(sim.d.main, "mika_petal_burst", func() -> Vector3: return from, {"size": 2.0, "f0": 11.0, "dur": 1.3, "fade_in": 0.05,
						"fade_out": 0.5, "intensity": 1.7, "light": 3.0, "black_cut": 0.16})
				var st_t = _perf[who].get("storm")
				_perf[who].erase("storm")
				if st_t == null or not is_instance_valid(st_t):
					st_t = PetalStorm.make(sim.d.main, who, 2000)
				(st_t as PetalStorm).ground(sim.d.pos(o.id).y)
				(st_t as PetalStorm).comets(func() -> Vector3: return from, func() -> Array: return [Vector4(to_p.x, to_p.y, to_p.z, 0.0)], dur + 0.05, dur, 0.16, 0.15, 0.1)
				(st_t as PetalStorm).scatter(func() -> Vector3: return to_p, 1.2, 1.0)
				(st_t as PetalStorm).finish()
			var core := svfx.body(svfx.crystal(1.4, 0.05, 6, 0.75), who, 3.4)
			afx.flood(sim.d.pos(who), who, 3.0, 6.0, 0.5)
			afx.lens_streak(from, who, 2.0, 0.15)
			svfx.projectile(core, from, func() -> Vector3: return to_p, who, dur, 1.2, 0.04, func(p: Vector3):
				svfx.crystal_burst(Vector3(p.x, sim.d.pos(o.id).y, p.z), who, 1.0, 12, 1.2)
				afx.shock_ring(p, Vector3.UP, who, 2.2, 0.35)
				_land(s, o, atk, p, 0.25))
			sim.at(0.3, func(): _done(s, atk)))
		return
	if PETALS:
		# the petals wind round the conjured blade while she fights with it, and fall away when it vanishes
		var span := float(rels[rels.size() - 1]) - float(rels[0]) + 0.35
		sim.at(float(rels[0]) - 0.1, func():
			var st_w = _perf.get(who, {}).get("storm")
			if st_w == null or not is_instance_valid(st_w):
				return
			_perf[who].erase("storm")
			var side := "Left" if String(s.get("weapon_hand", "rh")) == "lh" else "Right"
			var w: Dictionary = _perf[who].get("weapon", {})
			var hand := func() -> Vector3: return f.trace.get(side + "Hand", f.sk.global_position)
			var tip := func() -> Vector3: return svfx.weapon_tip(w) if not w.is_empty() else (hand.call() as Vector3)
			(st_w as PetalStorm).stream(hand, tip, span, 0.09, 0.08)
			(st_w as PetalStorm).scatter(tip, 0.9, 0.9)
			(st_w as PetalStorm).finish())
	for i in rels.size():
		var tr := float(rels[i])
		sim.at(tr, func():
			if not alive.call() or not _perf[who].get("weapon"):
				return
			var w: Dictionary = _perf[who].weapon
			atk.phase = "active"
			var sh: Vector3 = f.trace.get("RightUpperArm", f.sk.global_position)
			var tip0 := svfx.weapon_tip(w)
			var fwd := sim.d.fwd(who)
			var nrm := (tip0 - sh).cross(fwd).normalized()
			if nrm.length() < 0.1:
				nrm = Vector3.UP
			var big: bool = i == rels.size() - 1 or bool(sp.get("wave", false))
			var r := sh.distance_to(tip0) + 0.15
			svfx.slash_arc(sh, nrm if i % 2 == 0 else -nrm, tip0 - sh, r * (1.6 if big else 1.0) * float(sp.get("size", 1.0)) * (0.6 if sp.get("greatsword", false) else 1.0),
				0.6 if big else 0.45, 200.0 if big else 170.0, 0.25, who, 3.8 if big else 3.2)
			afx.flood(sim.d.pos(who), who, 2.5 if big else 1.5, 5.0, 0.4)
			afx.stop(afx.motes(func() -> Vector3: return svfx.weapon_tip(w), who, 30, 0.6, 0.05, "drift"), 0.6)
			sim.vfx.trail(func() -> Array: return [(f.trace.get("RightHand", Vector3.ZERO) as Vector3).lerp(svfx.weapon_tip(w), 0.4), svfx.weapon_tip(w)], who, 0.14, 2.8, 1.0)
			_blade_touch(s, o, atk, w, i)
			if PETALS:
				arts.swing_card(who, tip0.lerp(sh, 0.3), fwd.rotated(Vector3.UP, 0.0).cross(nrm) * (1.0 if i % 2 == 0 else -1.0), big)
				if i == 0 and who == "mika":
					var card_w = _perf[who].get("card")
					if card_w and is_instance_valid(card_w):
						(card_w as FlipbookFX).stop(0.12)
					FlipbookFX.play(sim.d.main, "mika_petal_burst", func() -> Vector3: return svfx.weapon_tip(w), {"size": 2.0, "f0": 11.0, "dur": 1.3,
						"fade_in": 0.05, "fade_out": 0.5, "intensity": 1.7, "light": 3.0, "black_cut": 0.16})
			if sp.get("wave", false):
				# the draw cut leaves the blade as a crescent wave along the ground at her
				var gy := sim.d.pos(o.id).y
				var a0 := Vector3(sh.x, gy + 0.15, sh.z)
				var to_w: Vector3 = sim.d.pos(o.id)
				var dur_w := a0.distance_to(to_w) / 14.0
				var side := sim._flat(to_w - a0).normalized().cross(Vector3.UP)
				svfx.slash_arc(a0 + Vector3.UP * 0.4, side, Vector3.UP, 1.4 * float(sp.get("size", 1.0)), 0.5, 160.0, dur_w + 0.2, who, 3.6,
					sim._flat(to_w - a0), 0.7)
				afx.glow(a0 + Vector3.UP, who, 3.0, 4.0, 0.4, 0.05, 0.3)
				sim.at(dur_w, func():
					if String(atk.outcome) in ["", "miss"]:
						atk.outcome = ""
						_land(s, o, atk, to_w + Vector3.UP * 0.8, 0.6)))
	sim.at(float(rels[rels.size() - 1]) + 0.3, func():
		if _perf.has(who) and _perf[who].get("weapon"):
			svfx.weapon_vanish(_perf[who].weapon)
			_perf[who].erase("weapon")
		atk.outcome = "done" if String(atk.outcome) == "" else atk.outcome
		_done(s, atk))


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
		if PETALS:
			arts.impact(p, sim.d.pos(o.id).y, String(s.id), 0.5)
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
		if PETALS:
			arts.impact(p, sim.d.pos(o.id).y, String(s.id), 0.35)
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
	if PETALS:
		arts.impact(best.point, sim.d.pos(o.id).y, String(s.id), power)
	sim.d.face_fx(o.id, "hurt", 1.0, 0.5)
	sim._interrupt(o)
	atk.reaction = HitReactions.hit(sim, o, String(best.zone), dir, power, atk.m)
	s.energy = minf(float(s.get("energy", 0.0)) + 6.0, 100.0)
	o.energy = minf(float(o.get("energy", 0.0)) + 4.0, 100.0)
	_log(s, atk, "hit", String(best.zone))


func _log(s: Dictionary, atk: Dictionary, outcome: String, zone: String) -> void:
	sim.attacks.append({"touch": atk.get("touch", Vector3.INF), "vs": atk.get("vs", ""), "t": snappedf(float(atk.t0), 0.01), "by": s.id, "move": atk.name, "outcome": outcome, "defence": atk.defence,
		"zone": zone, "reaction": String(atk.get("reaction", "")), "frame": Engine.get_frames_drawn(), "err": -1.0, "spell": true,
		"react_delay": float(atk.get("react_delay", -1.0)), "part": String(atk.get("part", ""))})
	print("[melee] %s %s by %s at %.2f s at frame %d (defence %s)" % [outcome.to_upper(), atk.name, s.id, sim.t, Engine.get_frames_drawn(), atk.defence])


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
