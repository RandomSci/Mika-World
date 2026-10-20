class_name WeaponPlay
extends RefCounted
## Weapon fighting (2026-10-20, Selwyn: Move Library v4, "strikes keep the procedural IK on the target, the clips give
## timing, footwork and body motion"). One exchange at a time on a MeleeSim:
##   strike(a, b, clip)     her clip plays the whole body (the mocap is hip-centred, so the clip's travel, a dash, a
##                          lunge, a step back, is her glide over the ground, TRAVEL below); from the clip's contact
##                          frame back by `lead` her weapon hand is steered (FightIK) so the blade's TIP lands on the
##                          point she aims at on the other girl (the hand goes to that point less the blade along its
##                          current line); at the contact the blade decides: on the other girl's blade while she
##                          defends = a block (or a parry if her defence is a parry), on her body = a hit, else a miss
##   defend(b, clip, at)    her defence clip starts so its block frame (GUARD) meets a strike's contact at fight time
##                          `at`; her weapon is up across the line through the window
## Times are the catalog's (contact_s from the mocap, eye checked against the sources at 10 fps on 20 October).

## clip -> [contact (s in the clip), weapon hand, aim, weight, dmg, travel kind, travel m]
const STRIKES := {
	"r_lunge_thrust": [1.75, "rh", "chest", "medium", 9.0, "forward", 1.1],
	"r_triple_thrust": [0.8, "rh", "chest", "medium", 8.0, "forward", 0.4],
	"r_backstep_slash": [1.5, "rh", "chest", "light", 6.0, "back", 1.2],
	"r_dash_through": [2.0, "rh", "stomach", "medium", 9.0, "through", 0.0],
	"r_flick_cut": [3.15, "rh", "chest", "light", 6.0, "forward", 0.2],
	"r_parry_riposte": [2.1, "rh", "chest", "medium", 9.0, "forward", 0.5],
	"r_aerial_thrust": [1.8, "rh", "chest", "heavy", 12.0, "forward", 1.6],
	"g_wide_sweep": [2.5, "rh", "stomach", "medium", 9.0, "forward", 0.3],
	"g_overhead_arc": [3.0, "rh", "chest", "heavy", 12.0, "forward", 0.4],
	"g_spin_multi_slash": [1.6, "rh", "stomach", "medium", 8.0, "forward", 0.3],
	"g_long_thrust": [1.45, "rh", "chest", "medium", 10.0, "forward", 0.8],
	"g_plant_burst": [0.87, "rh", "area", "heavy", 13.0, "none", 0.0],
	"s_iaido_draw": [2.0, "rh", "stomach", "heavy", 11.0, "forward", 0.5],
	"s_running_slash": [2.95, "rh", "chest", "medium", 9.0, "forward", 2.6],
}
## defence clip -> [block frame (s), kind (block / parry), travel m back]
const GUARD := {
	"g_shaft_block": [1.0, "block", 0.6],          # (a HIGH block: the shaft overhead)
	"r_parry_riposte": [0.9, "parry", 0.0],          # (the beat parry; the riposte thrust at 2.1)
	"s_blade_clash": [1.0, "block", 0.2],
	"s_weapon_lock": [1.0, "block", 0.0],
}

var sim: MeleeSim
var weapons := {}                          # id -> FightWeapon
var defending := {}                        # id -> {kind, from, to}
var log_rows: Array = []                   # QA: one row per exchange


static func make(s: MeleeSim) -> WeaponPlay:
	var w := WeaponPlay.new()
	w.sim = s
	return w


## Overrides from the catalog (contact_s, lead_limb) when the entry was filled and eye checked.
static func timing(clip: String) -> Array:
	var spec: Array = (STRIKES.get(clip, [1.5, "rh", "chest", "medium", 8.0, "forward", 0.5]) as Array).duplicate()
	var e := ActionPlayer.entry(clip)
	if not e.is_empty() and e.has("contact_s") and String(e.get("eye", "")) == "pass":
		spec[0] = float(e.contact_s)
	return spec


func draw(id: String, hand := "Right") -> FightWeapon:
	if weapons.has(id) and is_instance_valid(weapons[id]):
		return weapons[id]
	var w := FightWeapon.draw(sim, id, hand)
	weapons[id] = w
	return w


func sheathe(id: String) -> void:
	if weapons.has(id) and is_instance_valid(weapons[id]):
		(weapons[id] as FightWeapon).sheathe()
	weapons.erase(id)


## Plays a weapon clip with no target (a draw, a salute, a twirl, a finisher pose); returns its length.
func pose(id: String, clip: String, speed := 1.0) -> float:
	var f: MeleeFighter = sim.F[id]
	if not f.c.has_clip("ml_" + clip):
		push_warning("[weapon] no clip ml_%s" % clip)
		return 0.0
	var L := FightDeck.clip_length(f.c, "ml_" + clip)
	sim.d.anim(id, "ml_" + clip, 0.0, L, speed, 0.12)
	f.rig_w = 0.0
	f.play([{"dur": L / speed, "ease": "hold", "pose": {}}])
	sim.at(L / speed, func():
		if String(sim.S[id].state) != "down":
			f.replant()
			f.rig_w = 1.0)
	return L / speed


## Her defence clip timed so its block frame lands at fight time `at` (sim.t).
func defend(id: String, clip: String, at: float) -> void:
	var g: Array = GUARD.get(clip, [1.3, "block", 0.0])
	var f: MeleeFighter = sim.F[id]
	if not f.c.has_clip("ml_" + clip):
		return
	var L := FightDeck.clip_length(f.c, "ml_" + clip)
	var start := at - float(g[0])
	var s: Dictionary = sim.S[id]
	sim.at(maxf(start - sim.t, 0.0), func():
		var from := maxf(sim.t - start, 0.0)
		sim.d.anim(id, "ml_" + clip, from, L, 1.0, 0.1)
		f.rig_w = 0.0
		f.play([{"dur": L - from, "ease": "hold", "pose": {}}])
		s.state = "defend"
		s.until = sim.t + L - from
		defending[id] = {"kind": String(g[1]), "from": at - 0.35, "to": at + 0.25}
		if float(g[2]) > 0.0:
			var away := sim._flat(sim.d.pos(id) - sim.d.pos(String(sim.d.F[id].other))).normalized()
			s.glide = {"from": sim.d.pos(id), "to": sim.d.clamp_arena(sim.d.pos(id) + away * float(g[2])), "t": 0.0, "dur": 0.45, "ease": "out"}
		sim.at(L - from, func():
			defending.erase(id)
			if String(s.state) == "defend":
				s.state = "free"
			f.replant()
			f.rig_w = 1.0))


## A weapon strike by a on b. Returns the attack record (its outcome is filled at the contact).
func strike(a: String, b: String, clip: String, speed := 1.0) -> Dictionary:
	var f: MeleeFighter = sim.F[a]
	var of: MeleeFighter = sim.F[b]
	var s: Dictionary = sim.S[a]
	var o: Dictionary = sim.S[b]
	if not f.c.has_clip("ml_" + clip):
		push_warning("[weapon] no clip ml_%s" % clip)
		return {}
	var spec := timing(clip)
	var c_t := float(spec[0])
	var limb := String(spec[1])
	var L := FightDeck.clip_length(f.c, "ml_" + clip)
	var wind := c_t / speed
	var total := L / speed
	var w: FightWeapon = draw(a, "Right" if limb == "rh" else "Left")
	var m := {"weight": String(spec[3]), "dmg": float(spec[4]), "aim": String(spec[2]) if String(spec[2]) != "area" else "chest",
		"height": "mid", "recover": 0.4, "knock": 0.6 if String(spec[3]) == "heavy" else 0.3}
	var atk := {"name": clip, "m": m, "by": a, "vs": b, "t0": sim.t, "t_hit": sim.t + wind, "limb": limb, "outcome": "",
		"weapon": w, "clip": clip, "phase": "wind", "defence": "", "locked": Vector3.INF, "contact": Vector3.INF, "dir": Vector3.ZERO,
		"react_delay": -1.0, "touch": Vector3.INF, "vs_id": b}
	s.state = "attack"
	s.atk = atk
	f.move_tag = "weapon:" + clip
	sim.d.anim(a, "ml_" + clip, 0.0, L, speed, 0.1)
	f.rig_w = 0.0
	f.upper_clip = 0.0
	f.play([{"dur": total, "ease": "hold", "pose": {}}])
	sim.events.append([snappedf(sim.t, 0.01), "attack", a, clip])
	# the clip's travel: her glide over the ground through the windup
	var dirv := sim._flat(sim.d.pos(b) - sim.d.pos(a)).normalized()
	var side := dirv.cross(Vector3.UP)
	var reach := f.limb_len(limb) * 0.8 + (float(FightWeapon.SPAN[a][1]) * f.k * 0.85 if FightWeapon.SPAN.has(a) else 0.8)
	var to: Vector3 = sim.d.pos(a)
	match String(spec[5]):
		"forward":
			to = sim.d.pos(b) - dirv * reach
		"back":
			to = sim.d.pos(a) - dirv * float(spec[6])
		"through":
			# alongside her on her right at the contact (the cut lands as she goes by), then on past her
			to = sim.d.pos(b) + side * 0.75
	if String(spec[5]) != "none":
		s.glide = {"from": sim.d.pos(a), "to": sim.d.clamp_arena(to), "t": 0.0, "dur": wind * (1.15 if String(spec[5]) == "through" else 0.9), "ease": "inout"}
	# the blade's tip on her: the hand steered to the aim point less the blade along its line
	var tgt := func() -> Vector3:
		var p: Vector3 = of.target_point(String(m.aim), f.trace.get("Chest", sim.d.chest(a)))
		if String(spec[2]) == "area":
			p = Vector3(sim.d.pos(b).x, sim.d.pos(a).y + 0.05, sim.d.pos(b).z).lerp(sim.d.pos(a), 0.45)
		var blade := (w.tip_point(1.0) - w.global_position) if is_instance_valid(w) else Vector3.ZERO
		return p - blade * 0.92
	f.steer_limb(limb, tgt, sim.d.ft + wind - 0.32, sim.d.ft + wind - 0.03, sim.d.ft + wind + 0.15)
	if String(spec[5]) == "through":
		var past: Vector3 = sim.d.pos(b) + dirv * 1.8 + side * 0.75
		sim.at(wind, func(): s.glide = {"from": sim.d.pos(a), "to": sim.d.clamp_arena(past), "t": 0.0, "dur": 0.45, "ease": "out"})
	w.trail_on = false
	sim.at(maxf(wind - 0.3, 0.0), func():
		atk.phase = "active"
		if is_instance_valid(w):
			w.trail_on = true
			w.strike = true)
	sim.at(wind, func(): _resolve(a, b, atk))
	sim.at(wind + 0.22, func():
		if is_instance_valid(w):
			w.trail_on = false
			w.strike = false)
	sim.at(total, func():
		f.steer_limb("", Callable(), 0.0, 0.0, 0.0)
		if f.move_tag == "weapon:" + clip:
			f.move_tag = ""
		if s.atk == atk:
			s.state = "free"
			s.atk = {}
		if String(s.state) != "down":
			f.replant()
			f.rig_w = 1.0)
	return atk


## A second blow inside a clip that is already playing (the riposte of r_parry_riposte): no new clip, her hand steered
## onto the other girl and the contact resolved `delay` seconds from now.
func followup(a: String, b: String, clip: String, delay: float) -> Dictionary:
	var f: MeleeFighter = sim.F[a]
	var of: MeleeFighter = sim.F[b]
	var spec := timing(clip)
	var limb := String(spec[1])
	var w: FightWeapon = draw(a, "Right" if limb == "rh" else "Left")
	var m := {"weight": String(spec[3]), "dmg": float(spec[4]), "aim": String(spec[2]), "height": "mid", "recover": 0.4, "knock": 0.3}
	var atk := {"name": clip, "m": m, "by": a, "vs": b, "t0": sim.t, "t_hit": sim.t + delay, "limb": limb, "outcome": "", "weapon": w,
		"clip": clip, "phase": "active", "defence": "", "touch": Vector3.INF}
	var tgt := func() -> Vector3:
		var p: Vector3 = of.target_point(String(m.aim), f.trace.get("Chest", sim.d.chest(a)))
		var blade := (w.tip_point(1.0) - w.global_position) if is_instance_valid(w) else Vector3.ZERO
		return p - blade * 0.92
	f.steer_limb(limb, tgt, sim.d.ft + maxf(delay - 0.3, 0.0), sim.d.ft + delay - 0.03, sim.d.ft + delay + 0.15)
	# she closes into her reach for it (the riposte's step in)
	var dirv := sim._flat(sim.d.pos(b) - sim.d.pos(a)).normalized()
	var reach := f.limb_len(limb) * 0.8 + float(FightWeapon.SPAN[a][1]) * f.k * 0.85
	(sim.S[a] as Dictionary).glide = {"from": sim.d.pos(a), "to": sim.d.clamp_arena(sim.d.pos(b) - dirv * reach), "t": 0.0,
		"dur": maxf(delay * 0.85, 0.2), "ease": "inout"}
	sim.at(maxf(delay - 0.3, 0.0), func():
		if is_instance_valid(w):
			w.trail_on = true
			w.strike = true)
	sim.at(delay, func(): _resolve(a, b, atk))
	sim.at(delay + 0.22, func():
		if is_instance_valid(w):
			w.trail_on = false
			w.strike = false)
	return atk


## The contact: blade on blade (a block or a parry), blade on body (a hit), or nothing (a miss).
func _resolve(a: String, b: String, atk: Dictionary) -> void:
	if String(atk.outcome) != "":
		return
	var w: FightWeapon = atk.weapon
	if not is_instance_valid(w):
		return
	var s: Dictionary = sim.S[a]
	var o: Dictionary = sim.S[b]
	var of: MeleeFighter = sim.F[b]
	var p0 := w.tip_point(0.25)
	var p1 := w.tip_point(1.0)
	var power: float = {"light": 0.5, "medium": 0.72, "heavy": 1.0}.get(String(atk.m.weight), 0.6)
	var dir := (p1 - p0).normalized()
	var dv: Dictionary = defending.get(b, {})
	var bw: FightWeapon = weapons.get(b)
	var outcome := "miss"
	var at := p1
	if not dv.is_empty() and sim.t >= float(dv.from) and sim.t <= float(dv.to) and is_instance_valid(bw):
		# her guard: the strike meets her weapon, wherever her clip holds it (the clash point is the closest pair)
		var cp: Array = BodyAwareness.closest(p0, p1, bw.butt_point(), bw.tip_point(1.0))
		at = ((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5
		outcome = "parry" if String(dv.kind) == "parry" else "block"
	elif String((STRIKES.get(String(atk.clip), [0, 0, ""]) as Array)[2]) == "area":
		# the plant and burst: the ground bursts out from the planted glaive toward her, anyone within 2 m of the burst's
		# heart (a quarter of the way back from her) is hit
		var gp: Vector3 = sim.d.pos(b).lerp(sim.d.pos(a), 0.3)
		gp.y = sim.d.pos(a).y + 0.05
		if sim._flat(sim.d.pos(b) - gp).length() < 2.0:
			outcome = "hit"
			at = of.trace.get("Chest", sim.d.chest(b))
		FlipbookFX.play(sim.d.main, "luna_moon_pillar" if a == "luna" else "mika_petal_burst", func() -> Vector3: return gp, {"size": 3.6,
			"upright": a == "luna", "f0": 0.0 if a == "luna" else 11.0, "f1": 63.0, "dur": 1.8, "intensity": 1.3, "light": 4.0, "black_cut": 0.18,
			"top_fade": 0.35 if a == "luna" else 0.0})
		sim.magic.arts.impact(gp + Vector3.UP * 0.2, sim.d.pos(a).y, a, 1.0)
	else:
		var best := {}
		var hurt := BodyAwareness.hurtboxes(of)
		for n in hurt:
			var c: Array = hurt[n]
			var cp2: Array = BodyAwareness.closest(p0, p1, c[0], c[1])
			var dd := (cp2[0] as Vector3).distance_to(cp2[1]) - float(c[2]) - FightWeapon.RADIUS
			if dd < 0.04 and (best.is_empty() or dd < float(best.d)):
				best = {"part": n, "zone": BodyAwareness.HURT[n][3], "d": dd, "point": cp2[1]}
		if not best.is_empty():
			outcome = "hit"
			at = best.point
			atk.zone = best.zone
	atk.outcome = outcome
	atk.touch = at
	atk.dir = dir
	match outcome:
		"hit":
			o.hp = float(o.hp) - float(atk.m.dmg)
			of.vibrate = true
			sim.d.impact(power, false)
			sim.d.shake(0.35 + power * 0.5)
			sim.vfx.impact(at, dir, a, power, "hit")
			sim.big_hit_fx(at, power)
			sim._interrupt(o)
			atk.reaction = HitReactions.hit(sim, o, String(atk.get("zone", "chest")) if String(atk.get("zone", "")) != "" else "chest", sim._flat(dir).normalized(), power, atk.m)
		"block", "parry":
			# blade on blade: sparks at the clash, both lenses jolt, a short freeze; a parry throws her blade wide
			sim.d.impact(0.45 if outcome == "block" else 0.6, false)
			sim.d.shake(0.3)
			sim.vfx.impact(at, -dir, b, 0.7, "block")
			FlipbookFX.play(sim.d.main, "fx_impact_starburst", func() -> Vector3: return at, {"size": 1.0, "f0": 4.0, "f1": 63.0, "dur": 0.45,
				"fade_in": 0.02, "fade_out": 0.2, "intensity": 1.3, "light": 2.5, "black_cut": 0.16})
			if outcome == "parry":
				sim.d.F[a].yaw_extra = 0.35
				sim.at(0.3, func(): sim.d.F[a].yaw_extra = 0.0)
	sim.attacks.append({"t": snappedf(float(atk.t0), 0.01), "by": a, "move": String(atk.clip), "outcome": outcome, "defence": String(defending.get(b, {}).get("kind", "")),
		"part": String(atk.get("part", "")), "zone": String(atk.get("zone", "")), "reaction": String(atk.get("reaction", "")), "touch": at, "vs": b,
		"limb": String(atk.limb), "weapon": true, "frame": Engine.get_frames_drawn(), "err": -1.0, "react_delay": -1.0})
	log_rows.append({"t": snappedf(sim.t, 0.01), "by": a, "clip": String(atk.clip), "outcome": outcome, "deflect_deg": snappedf(w.deflect_deg, 0.1),
		"contact_other": w.contact_other})
	print("[weapon] %s %s by %s at %.2f s (frame %d)" % [outcome.to_upper(), String(atk.clip), a, sim.t, Engine.get_frames_drawn()])
