class_name PairedPlay
extends RefCounted
## Paired exchanges (2026-10-20, Selwyn: "Fight structure like real games. Every exchange is a paired animation. The
## attacker's full body clip plays whole with root motion, the defender's matching reaction clip (block, parry, dodge,
## hit) is synced so both meet at the contact frame. Spacing comes from the weapon reach, rapier about 1.5 m and glaive (since replaced by Luna's longsword, 1.8 m)
## about 2.5 m, never chest to chest. No partial blending inside an attack.")
## On a MeleeSim (demo: no brain, no footwork), with the suit mocap of BodyMoves:
##   exchange(spec)   the attacker steps to the distance her weapon reaches at her first blow (less the clip's own
##                    travel to it), then her clip plays whole; for every blow the defender's answer clip starts so its
##                    meet frame lands on the contact; her own clip's travel moves her too (a knock-back flies 3 m), and
##                    a guard gives ground by as much as the attacker travels between two blows (the distance holds)
##   facing           frozen while a clip plays (a dash through goes on past her, the body never spins round mid move)
##   no layers        the fighter's procedural rig is off (rig_w 0) and nothing steers a hand: the clip is the body
##   contact          blade on blade sparks and a starburst, blade on body the hit stop, the shake, the big hit
##                    burst; every contact is an attack record for the cinematographer (FightCine)
## Prints "[paired] <t> <a> <clip> hit <i> -> <b> <answer> <clip>".

const GAP := {"mika": 1.5, "luna": 1.8}                     # m between their hips at a blade contact (the weapon's reach: rapier, longsword)
const STANCE := {"mika": "ualf:Sword_Idle", "luna": "sword:great_sword_idle"}
const POWER := {"block": 0.45, "parry": 0.6, "hit": 0.75, "knock": 1.0}

var sim: MeleeSim
var d: FightDirector
var wp: WeaponPlay
var rm := {}                                                # id -> the clip moving her {clip, t0, from, speed, base, fwd, left, r0, until}
var rows: Array = []
var busy_until := {}                                        # id -> fight s her current clip ends
var _weather_was := true


## After the fight: the weather runs again.
func release() -> void:
	var w = d.main.get("weather") if is_instance_valid(d) else null
	if w:
		w.enabled = _weather_was


static func make(s: MeleeSim) -> PairedPlay:
	var p := PairedPlay.new()
	p.sim = s
	p.d = s.d
	p.wp = WeaponPlay.make(s)
	s.set_meta("weapon_play", p.wp)
	s.set_meta("paired", true)
	# (Selwyn: no rain during fights) the weather holds clear while they fight; release() gives it back
	var w = s.d.main.get("weather")
	if w:
		p._weather_was = bool(w.enabled)
		w.enabled = false
		w.rain = 0.0
		w.cloud = 0.0
	for id in ["mika", "luna"]:
		(s.F[id] as MeleeFighter).rig_w = 0.0
		p.wp.draw(id)
		p.stance(id, 0.3)
	return p


func stance(id: String, fade := 0.25) -> void:
	rm.erase(id)
	d.anim(id, STANCE[id], randf() * 1.0, -1.0, 1.0, fade, true)
	d.F[id].yaw_k = 1.0


## Her clip from `from` to `to` (-1: its end) at `speed`, moving her by its own travel along `fwd` (her facing).
func drive(id: String, clip: String, from := 0.0, to := -1.0, speed := 1.0, fade := 0.1, fwd := Vector3.ZERO) -> float:
	var c: WorldCharacter = d.F[id].c
	if fwd == Vector3.ZERO:
		fwd = sim._flat(d.pos(String(d.F[id].other)) - d.pos(id)).normalized()
	var L := d.anim(id, clip, from, to, speed, fade)
	if L <= 0.0:
		push_warning("[paired] no clip " + clip)
		return 0.0
	rm[id] = {"clip": clip, "t0": sim.t, "from": from, "speed": speed, "base": d.pos(id), "fwd": fwd,
		"left": Vector3.UP.cross(fwd), "r0": FightDeck.root_at(c, clip, from), "until": sim.t + L}
	d.F[id].yaw_k = 0.0
	busy_until[id] = sim.t + L
	(sim.F[id] as MeleeFighter).rig_w = 0.0
	return L


## Moves her (and the clip moving her) by v over the next dur seconds (a guard giving ground).
func give(id: String, v: Vector3, dur: float) -> void:
	var steps := maxi(int(dur / 0.05), 1)
	for k in steps:
		sim.at(dur * float(k) / float(steps), func():
			if rm.has(id):
				rm[id].base = (rm[id].base as Vector3) + v / float(steps)
			else:
				d.F[id].pos = d.clamp_arena((d.F[id].pos as Vector3) + v / float(steps)))


## Every frame (fight time): each clip's own travel on her mark.
func update() -> void:
	for id in rm.keys():
		var e: Dictionary = rm[id]
		var c: WorldCharacter = d.F[id].c
		var tt := float(e.from) + (sim.t - float(e.t0)) * float(e.speed)
		var r := FightDeck.root_at(c, String(e.clip), tt) - (e.r0 as Vector2)
		d.F[id].pos = d.clamp_arena((e.base as Vector3) + (e.fwd as Vector3) * r.y + (e.left as Vector3) * r.x)
		if sim.t >= float(e.until) + 0.05:
			rm.erase(id)


## One paired exchange. spec: {a, b, atk, from (clip s, default 0), to (-1), speed (1),
##   answers: [{hit (index of the attacker's blow), answer (block / parry / hit / knock / dodge), clip, meet (s into the
##   answer clip where it meets the blow), from (s, default 0), to (-1), then (a clip after it, e.g. the get up)}]}
## Returns the seconds until both are back in stance.
func exchange(spec: Dictionary) -> float:
	var a := String(spec.a)
	var b := String(spec.b)
	var atk := String(spec.atk)
	var from := float(spec.get("from", 0.0))
	var speed := float(spec.get("speed", 1.0))
	var ca: WorldCharacter = d.F[a].c
	var answers: Array = spec.get("answers", [])
	var dirv := sim._flat(d.pos(b) - d.pos(a)).normalized()
	# the spacing: her weapon's reach at the first blow, less the clip's own travel up to it
	var h0 := BodyMoves.hit_t(atk, int((answers[0] as Dictionary).get("hit", 0)) if not answers.is_empty() else 0)
	if h0 < 0.0:
		h0 = from + 0.4
	var travel0 := (FightDeck.root_at(ca, atk, h0) - FightDeck.root_at(ca, atk, from)).y
	var want: Vector3 = d.clamp_arena(d.pos(b) - dirv * (float(GAP[a]) + travel0))
	var prep := 0.0
	if sim._flat(want - d.pos(a)).length() > 0.08:
		prep = 0.35
		(sim.S[a] as Dictionary).glide = {"from": d.pos(a), "to": want, "t": 0.0, "dur": prep, "ease": "inout"}
	# the attacker starts late enough that every answer clip can start at or after now
	var lead := 0.0
	for an in answers:
		var ht := BodyMoves.hit_t(atk, int(an.get("hit", 0)))
		lead = maxf(lead, float(an.get("meet", 0.0)) - (ht - from) / speed - prep)
	var t_a := prep + lead
	var L_a := FightDeck.clip_length(ca, atk)
	var end_a := (L_a if float(spec.get("to", -1.0)) < 0.0 else float(spec.to)) - from
	var span := t_a + end_a / speed
	sim.at(t_a, func():
		dirv = sim._flat(d.pos(b) - d.pos(a)).normalized()
		drive(a, atk, from, float(spec.get("to", -1.0)), speed, 0.12, dirv)
		sim.events.append([snappedf(sim.t, 0.01), "attack", a, atk]))
	sim.at(span, func():
		if float(busy_until.get(a, 0.0)) <= sim.t + 0.02:
			stance(a))
	for i in answers.size():
		var an: Dictionary = answers[i]
		var ht := BodyMoves.hit_t(atk, int(an.get("hit", 0)))
		var contact := t_a + (ht - from) / speed
		var start := contact - float(an.get("meet", 0.0))
		var clip := String(an.get("clip", ""))
		if clip != "":
			sim.at(maxf(start, 0.0), func():
				drive(b, clip, float(an.get("from", 0.0)) + maxf(-start, 0.0), float(an.get("to", -1.0)), 1.0, 0.08, sim._flat(d.pos(a) - d.pos(b)).normalized())
				if String(an.answer) == "dodge":
					sim.events.append([snappedf(sim.t, 0.01), "evade", b, clip]))
		# the weapon's trail through the blow
		sim.at(maxf(contact - 0.3, 0.0), func(): _trail(a, true))
		sim.at(contact + 0.22, func(): _trail(a, false))
		sim.at(contact, func(): _contact(a, b, atk, i, String(an.answer)))
		# a guard gives ground by the attacker's travel to her next blow (the distance holds through a combo)
		if String(an.answer) != "dodge" and i + 1 < answers.size():
			var hn := BodyMoves.hit_t(atk, int((answers[i + 1] as Dictionary).get("hit", 0)))
			var dv := (FightDeck.root_at(ca, atk, hn) - FightDeck.root_at(ca, atk, ht)).y
			if dv > 0.05:
				sim.at(contact, func(): give(b, dirv * dv, (hn - ht) / speed))
		# after her last answer: a follow on clip (the get up) or back to her stance
		if i == answers.size() - 1 and clip != "":
			var L_b := FightDeck.clip_length(d.F[b].c, clip)
			var end_b := start + ((L_b if float(an.get("to", -1.0)) < 0.0 else float(an.to)) - float(an.get("from", 0.0)))
			span = maxf(span, end_b)
			var then := String(an.get("then", ""))
			sim.at(maxf(end_b, 0.0), func():
				if then != "":
					drive(b, then, 0.0, -1.0, 1.0, 0.15)
				elif float(busy_until.get(b, 0.0)) <= sim.t + 0.02:
					stance(b))
			if then != "":
				var L_t := FightDeck.clip_length(d.F[b].c, then)
				sim.at(end_b + L_t, func(): stance(b))
				span = maxf(span, end_b + L_t)
	return span


## The contact's flash (Selwyn: "white burst at most 2 frames and small"): a starburst for two frames.
func _burst(at: Vector3, size: float) -> void:
	FlipbookFX.play(d.main, "fx_impact_starburst", func() -> Vector3: return at, {"size": size, "f0": 20.0, "f1": 40.0, "dur": 2.0 / 30.0,
		"fade_in": 0.0, "fade_out": 0.02, "intensity": 0.9, "light": 1.2, "black_cut": 0.2, "near": 1.6})


func _trail(id: String, on: bool) -> void:
	var w = wp.weapons.get(id)
	if w and is_instance_valid(w):
		(w as FightWeapon).trail_on = on
		(w as FightWeapon).strike = on


func _contact(a: String, b: String, atk: String, i: int, answer: String) -> void:
	var dirv := sim._flat(d.pos(b) - d.pos(a)).normalized()
	var w = wp.weapons.get(a)
	var tip: Vector3 = (w as FightWeapon).tip_point(1.0) if w and is_instance_valid(w) else d.chest(b)
	var chest: Vector3 = (sim.F[b] as MeleeFighter).trace.get("Chest", d.chest(b))
	var power: float = POWER.get(answer, 0.6)
	var at := tip
	match answer:
		"block", "parry":
			var bw = wp.weapons.get(b)
			if bw and is_instance_valid(bw):
				var cp: Array = BodyAwareness.closest((w as FightWeapon).tip_point(0.3), tip, (bw as FightWeapon).butt_point(), (bw as FightWeapon).tip_point(1.0))
				at = ((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5
			# (sparks and a small quick starburst only: the block's full impact burst read as a white ball over her)
			d.impact(power, false)
			d.shake(0.3)
			_burst(at, 0.35)
		"hit", "knock":
			at = tip.lerp(chest, 0.6)
			(sim.S[b] as Dictionary).hp = float(sim.S[b].hp) - 8.0 * power
			d.impact(power, false)
			d.shake(0.35 + power * 0.5)
			sim.vfx.impact(at, dirv, a, power * 0.5, "hit")
			_burst(at, 0.45)
	if answer != "dodge":
		sim.attacks.append({"t": snappedf(sim.t, 0.01), "by": a, "move": atk, "outcome": "hit" if answer == "knock" else answer,
			"defence": answer if answer in ["block", "parry"] else "", "touch": at, "vs": b, "limb": "rh", "weapon": true,
			"frame": Engine.get_frames_drawn(), "err": -1.0, "react_delay": -1.0, "paired": true})
	rows.append({"t": snappedf(sim.t, 0.01), "a": a, "atk": atk, "hit": i, "b": b, "answer": answer,
		"gap": snappedf(sim._flat(d.pos(b) - d.pos(a)).length(), 0.01)})
	print("[paired] %.2f %s %s answer %d -> %s %s gap %.2f m (frame %d)" % [sim.t, a, atk, i, b, answer,
		sim._flat(d.pos(b) - d.pos(a)).length(), Engine.get_frames_drawn()])
