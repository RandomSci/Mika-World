class_name SpellBeats
extends RefCounted
## The spell duel (Selwyn, 22 Oct): Mika and Luna settle an argument the mages' way, 45 to 60 s, and nobody is ever
## hurt. Only magic and fast movement: bolts taken on shields, sidesteps and dashes with afterimages, blinks (gone in
## a puff, back at her flank), leaps on rising air, counter spells that meet mid-air, a beam clash that ends in a
## draw. No close combat, no swords (only casting, dodge and jump clips), no blow ever lands. They talk: before the
## first spell (the reason), after a block or a sidestep, before a big cast, and at the end. Every shot shows them
## head to feet (FightDirector.cut maps any closer kind to a whole-body one in this mode).
## Beats are staged on the FightDirector `d` with the shared helpers of FightMoves `m` (shield, bolt, say).

const LEN := {"s_faceoff": 6.0, "s_volley": 2.7, "s_blink": 2.9, "s_counter": 2.7, "s_aerial": 3.1, "s_barrage": 3.1,
	"s_dash": 2.5, "s_clash": 4.4, "s_truce": 6.0}

## Short lines for the moments of the duel, in each one's own voice (Mika playful and stubborn, Luna dry and proud).
## LineMemory picks one never said before; none left: she says nothing.
const LINES := {
	"mika": {
		"after_block": ["Ha! Not even close.", "My shield's tougher than it looks!", "You'll have to do better than that.", "Is that all the moon has?",
			"Blocked! Write that down.", "Nope, not today.", "Ooh, that one tickled.", "Try again, Luna!"],
		"after_dodge": ["Missed me!", "Too slow!", "Over here!", "Catch me if you can!", "Whoa, close one!", "You're aiming at where I was!"],
		"cast": ["Starfall, now!", "Here comes the big one!", "Stars, answer me!", "Frost and starlight!", "Let's see you block this!", "Ready? Here I come!"],
		"clash": ["I'm not backing down!", "Push, push!", "Hold it, hold it!"],
	},
	"luna": {
		"after_block": ["Cute.", "Was that meant to hurt?", "My ward barely noticed.", "Predictable.", "You telegraph everything, Mika.",
			"Try aiming next time.", "Mm. No.", "Again? Fine."],
		"after_dodge": ["Too obvious.", "I saw that coming a mile away.", "Missed.", "Over here, starlight.", "You'll need to be faster.", "Hm. Sloppy."],
		"cast": ["Moon, take her shadow.", "Let's end this.", "Umbra, rise.", "Watch closely.", "My turn.", "Hold still."],
		"clash": ["You're stubborn!", "Give it up!", "Not a chance!"],
	},
}

var d: FightDirector
var m: FightMoves


func line(id: String, kind: String) -> String:
	return LineMemory.fresh(id, LINES[id].get(kind, []), d.rng)


func quip(id: String, kind: String, est := 1.4) -> void:
	var t := line(id, kind)
	if t != "":
		m.say(id, t, est)


func stage(ex: Dictionary, t0: float) -> float:
	var mv := String(ex.move)
	match mv:
		"s_faceoff": _faceoff(ex, t0)
		"s_volley": _volley(ex, t0)
		"s_blink": _blink(ex, t0)
		"s_counter": _counter(ex, t0)
		"s_aerial": _aerial(ex, t0)
		"s_barrage": _barrage(ex, t0)
		"s_dash": _dash(ex, t0)
		"s_clash": _clash(ex, t0)
		"s_truce": _truce(ex, t0)
	return float(LEN.get(mv, 2.5))


# ------------------------------------------------------------------------------------------------ helpers
func _circle(id: String, dur: float) -> void:
	var h := d.fx.circle(d.pos(id) + Vector3(0, 0.03, 0), id, 2.2)
	d.at(d.ft + dur, func(): d.fx.circle_off(h))


func _dash_to(id: String, to: Vector3, dur := 0.3) -> void:
	d.anim(id, "dodge_dash", 0.0, -1.0, 1.7, 0.06)
	d.move(id, to, dur, Tween.TRANS_EXPO, Tween.EASE_OUT)
	d.fx.afterimages(d.F[id].c, id, 5, 0.04)
	d.fx.puff(d.pos(id), 8, 0.4)
	d.sound("portal_whoosh", d.chest(id), -9.0, 1.3)
	d.at(d.ft + dur + 0.2, func(): d.stance(id))


## Gone in a puff of her colour, back a moment later at her flank (a blink: fold-step magic).
func _blink(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var sgn := 1.0 if d.rng.randf() < 0.5 else -1.0
	d.cut(t0, "wide", a, {"dist": 7.4})
	d.cut(t0 + 0.95, "orbit", a, {"from": 30.0 * sgn, "to": 75.0 * sgn, "r": 6.0})
	d.cut(t0 + 2.0, "wide_low", b)
	d.at(t0 + 0.15, func():
		var c: WorldCharacter = d.F[a].c
		d.fx.puff(d.chest(a), 14, 0.6)
		d.fx.ground_ring(d.pos(a), a, 1.8, 1, 0.4)
		d.sound("portal_whoosh", d.chest(a), -6.0, 0.9)
		c.visible = false
		# her new mark: a quarter turn round the other, at the same distance
		var around := d._flat(d.pos(a) - d.pos(b))
		var to := d.pos(b) + around.rotated(Vector3.UP, sgn * PI * 0.5)
		d.F[a].pos = d.clamp_arena(to)
		d.at(d.ft + 0.22, func():
			c.visible = true
			d.fx.puff(d.chest(a), 14, 0.6)
			d.fx.ground_ring(d.pos(a), a, 1.8, 1, 0.4)
			d.sound("portal_whoosh", d.chest(a), -6.0, 1.2)))
	d.at(t0 + 0.55, func():
		_circle(a, 1.2)
		var lead := m.seg(a, "magic_attack_1h", 0.5, 0.08)
		d.fx.hand_charge(d.F[a].c, a, "RightHand", lead, 0.55)
		m._shield_up(b, a)
		d.at(d.ft + lead, func():
			var from := d.bone(a, "RightHand") + d.fwd(a) * 0.15
			var tgt := func() -> Vector3: return m._shield_point(b, a)
			var on_block := func(p: Vector3):
				d.fx.shield_hit(d.F[b].shield, p, 0.45)
				d.fx.sparks(p, -d.fwd(b), a, 26, 5.0)
				d.impact(0.45)
				d.sound("ward_mirror_absorb", p, -4.0)
				m._back(b, 0.4, 0.25)
			d.fx.projectile(from, tgt, a, 0.3, 0.65, 0.12, on_block)
			d.sound("spell_water_release" if a == "mika" else "spell_umbral_release", from, -5.0)))
	d.at(t0 + 1.9, func():
		m._shield_down(b, 0.35)
		d.stance(a)
		quip(b, "after_block"))


# ------------------------------------------------------------------------------------------------ the opening
func _faceoff(ex: Dictionary, t0: float) -> void:
	var lines: Array = ex.get("lines", [])
	d.cut(0.0, "establish", "mika")
	d.cut(t0 + 2.2, "two_mid", "mika")
	d.cut(t0 + 4.4, "wide", "luna", {"dist": 7.0})
	d.at(t0, func():
		d.face_fx("mika", "determined", 0.9, 4.0)
		d.face_fx("luna", "determined", 0.7, 4.0))
	var tt := t0 + 0.2
	for l in lines.slice(0, 3):
		var who := String(l[0])
		var text := String(l[1])
		d.at(tt, func(): m.say(who, text, 1.7))
		tt += 1.9
	d.at(t0 + 5.0, func():
		for id in ["mika", "luna"]:
			d.F[id].aura = d.fx.aura(d.F[id].c, id, 1.0)
			_circle(id, 0.9)
		d.sound("spell_arcane_charge", d.center, -4.0)
		d.shake(0.3))
	d.at(t0 + 5.8, func():
		for id in ["mika", "luna"]:
			d.fx.aura_off(d.F[id].aura)
			d.stance(id, 0.2))


# ------------------------------------------------------------------------------------------------ exchanges
## Three quick bolts: taken on her shield, or she dashes clear of them; then she answers it in words.
func _volley(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var oc := String(ex.outcome)
	d.cut(t0, "wide", a, {"dist": 6.8})
	d.cut(t0 + 1.0, "profile", a)
	d.cut(t0 + 1.9, "wide_low", b)
	d.at(t0, func(): _circle(a, 1.8))
	if oc == "block":
		d.at(t0 + 0.2, func(): m._shield_up(b, a))
	for i in 3:
		var tr := t0 + 0.25 + i * 0.45
		d.at(tr, func():
			var lead := m.seg(a, "cast_quick", 0.4, 0.06)
			d.fx.hand_charge(d.F[a].c, a, "RightHand", lead + 0.05, 0.4)
			d.at(d.ft + lead, func(): m._bolt(a, b, i, "block" if oc == "block" else "dodge")))
	if oc == "dodge":
		d.at(t0 + 0.55, func():
			var lat := d.fwd(b).cross(Vector3.UP).normalized()
			_dash_to(b, d.pos(b) + lat * 1.6, 0.28))
		d.at(t0 + 1.3, func():
			var lat2 := d.fwd(b).cross(Vector3.UP).normalized()
			_dash_to(b, d.pos(b) - lat2 * 1.8, 0.28))
	d.at(t0 + 1.8, func():
		d.stance(a)
		m._shield_down(b, 0.4))
	d.at(t0 + 2.0, func(): quip(b, "after_block" if oc == "block" else "after_dodge"))


## Her spell and the other's counter spell meet in the middle and burst; both are pushed back a step.
func _counter(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	d.cut(t0, "wide", a, {"dist": 7.2})
	d.cut(t0 + 0.75, "wide_low", a)
	d.cut(t0 + 1.7, "orbit", a, {"from": -20.0, "to": 25.0, "r": 6.2})
	var meet := {"p": Vector3.ZERO}
	d.at(t0 + 0.1, func():
		meet.p = (d.pos(a) + d.pos(b)) * 0.5 + Vector3(0, 1.2, 0)
		var lead := m.seg(a, "magic_attack_1h", 0.45, 0.08)
		d.fx.hand_charge(d.F[a].c, a, "RightHand", lead, 0.55)
		d.at(d.ft + lead, func():
			var to := func() -> Vector3: return meet.p
			d.fx.projectile(d.bone(a, "RightHand"), to, a, 0.32, 0.7, 0.05, Callable())
			d.sound("spell_water_release" if a == "mika" else "spell_umbral_release", d.chest(a), -5.0)))
	d.at(t0 + 0.22, func():
		var lead2 := m.seg(b, "cast_quick", 0.36, 0.06)
		d.fx.hand_charge(d.F[b].c, b, "RightHand", lead2, 0.5)
		d.at(d.ft + lead2, func():
			var to2 := func() -> Vector3: return meet.p
			var on_meet := func(p: Vector3):
				d.fx.explosion(p, a, 0.9)
				d.fx.sparks(p, Vector3.UP, b, 40, 6.0)
				d.fx.ground_ring(Vector3(p.x, d.center.y, p.z), a, 2.6, 2, 0.6)
				d.impact(0.6)
				d.sound("rift_erupt", p, -4.0)
				for id in [a, b]:
					m._back(id, 0.5, 0.3)
					d.anim(id, "brace", 0.0, -1.0, 1.4, 0.06)
			d.fx.projectile(d.bone(b, "RightHand"), to2, b, 0.3, 0.7, 0.05, on_meet)))
	d.at(t0 + 1.4, func():
		for id in [a, b]:
			d.stance(id))
	d.at(t0 + 1.6, func(): quip(a if d.rng.randf() < 0.5 else b, "after_block"))


## She leaps on rising air and casts down at the other; the other dashes clear and the ground erupts where she stood.
func _aerial(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var oc := String(ex.outcome)
	d.cut(t0, "wide_low", a)
	d.cut(t0 + 1.1, "wide", a, {"dist": 7.6, "fov": 48.0})
	d.cut(t0 + 2.1, "wide", b, {"dist": 7.4})
	d.at(t0 + 0.1, func():
		d.anim(a, "lift_off", 0.0, -1.0, 1.3, 0.08)
		d.fx.ground_ring(d.pos(a), a, 2.4, 2, 0.6)
		d.fx.puff(d.pos(a), 12, 0.6)
		d.sound("phoenix_wing_gust", d.chest(a), -6.0, 1.2)
		var tw := d.create_tween()
		tw.tween_method(func(v: float): d.F[a].lift = v, 0.0, 1.6, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	d.at(t0 + 0.65, func(): quip(a, "cast", 1.2))
	var land := {"p": Vector3.ZERO}
	d.at(t0 + 0.8, func():
		land.p = d.pos(b)
		var lead := m.seg(a, "magic_attack_2h", 0.6, 0.1)
		d.fx.hand_charge(d.F[a].c, a, "RightHand", lead, 0.7)
		d.at(d.ft + lead, func():
			var to := func() -> Vector3: return land.p + Vector3(0, 0.1, 0)
			var on_land := func(p: Vector3):
				d.fx.explosion(p, a, 1.1)
				d.fx.ground_ring(p, a, 3.2, 2, 0.7)
				d.fx.debris(p, 22, 1.0)
				d.impact(0.7)
				d.sound("rift_erupt", p, -2.0)
				if oc == "block":
					d.fx.shield_hit(d.F[b].shield, m._shield_point(b, a), 0.6)
					m._back(b, 0.6, 0.3)
			d.fx.projectile(d.bone(a, "RightHand"), to, a, 0.35, 0.8, -0.2, on_land)))
	if oc == "block":
		d.at(t0 + 0.9, func(): m._shield_up(b, a))
	else:
		d.at(t0 + 1.25, func():
			var away := d.fwd(b) * -1.0
			_dash_to(b, d.pos(b) + away * 1.4 + d.fwd(b).cross(Vector3.UP) * 1.2, 0.3))
	d.at(t0 + 1.8, func():
		var tw2 := d.create_tween()
		tw2.tween_method(func(v: float): d.F[a].lift = v, 1.6, 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		d.at(d.ft + 0.4, func():
			d.anim(a, "land_soft", 0.0, -1.0, 1.2, 0.06)
			d.fx.puff(d.pos(a), 10, 0.5)))
	d.at(t0 + 2.4, func():
		m._shield_down(b, 0.35)
		d.stance(a)
		d.stance(b)
		quip(b, "after_block" if oc == "block" else "after_dodge"))


## Arms wide, a ring of orbs over her head, then all of them at once onto the other's ward.
func _barrage(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	d.cut(t0, "wide", a, {"dist": 7.0})
	d.cut(t0 + 1.15, "overhead", a)
	d.cut(t0 + 1.9, "wide", b, {"dist": 7.4})
	d.at(t0 + 0.05, func():
		d.anim(a, "wide_arm_spell", 0.0, -1.0, 1.2, 0.1)
		d.F[a].aura = d.fx.aura(d.F[a].c, a, 1.2)
		_circle(a, 1.8)
		quip(a, "cast", 1.2))
	d.at(t0 + 0.6, func(): m._shield_up(b, a))
	for i in 6:
		d.at(t0 + 1.05 + i * 0.1, func():
			var from := d.chest(a) + Vector3(0, 1.1, 0) + d.fwd(a).cross(Vector3.UP) * (i - 2.5) * 0.35
			var tgt := func() -> Vector3: return m._shield_point(b, a) + Vector3(0, (i % 3 - 1) * 0.25, 0)
			var on_block := func(p: Vector3):
				d.fx.shield_hit(d.F[b].shield, p, 0.12)
				d.fx.sparks(p, -d.fwd(b), a, 14, 4.0)
				d.impact(0.25)
			d.fx.projectile(from, tgt, a, 0.38, 0.4, 0.4 * ((i % 2) * 2 - 1), on_block, (i - 2.5) * 0.15))
	d.at(t0 + 1.9, func():
		d.fx.aura_off(d.F[a].aura)
		d.stance(a)
		m._back(b, 0.5, 0.3))
	d.at(t0 + 2.2, func():
		m._shield_down(b, 0.35)
		quip(b, "after_block"))


## Fast movement: she dashes round the other in two bursts, casting from the second; the other turns and wards.
func _dash(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var sgn := 1.0 if d.rng.randf() < 0.5 else -1.0
	d.cut(t0, "track", a)
	d.cut(t0 + 1.2, "wide", b, {"dist": 7.0})
	for k in 2:
		d.at(t0 + 0.1 + k * 0.45, func():
			var around := d._flat(d.pos(a) - d.pos(b))
			_dash_to(a, d.pos(b) + around.rotated(Vector3.UP, sgn * 0.6), 0.25))
	d.at(t0 + 1.05, func():
		var lead := m.seg(a, "cast_quick", 0.35, 0.06)
		m._shield_up(b, a)
		d.at(d.ft + lead, func(): m._bolt(a, b, 2, "block")))
	d.at(t0 + 1.9, func():
		m._shield_down(b, 0.35)
		d.stance(a)
		quip(b, "after_block"))


## Both beams at once, the meeting point rocks between them, and it bursts in the middle: a draw.
func _clash(ex: Dictionary, t0: float) -> void:
	var st := {"k": 0.5, "beams": [], "clash": {}}
	d.at(t0, func():
		for id in ["mika", "luna"]:
			d.move(id, d.home(id), 0.3, Tween.TRANS_SINE, Tween.EASE_OUT))
	d.cut(t0, "wide_low", "mika")
	d.cut(t0 + 1.0, "profile", "mika")
	d.cut(t0 + 2.0, "orbit", "mika", {"from": 10.0, "to": 70.0, "r": 6.0})
	d.cut(t0 + 3.2, "wide", "mika", {"dist": 8.0})
	d.at(t0 + 0.25, func():
		for id in ["mika", "luna"]:
			m.seg(id, "magic_attack_2h", 0.55, 0.12)
			_circle(id, 3.2)
		d.sound("spell_arcane_charge", d.center, -5.0))
	var clash_at := func() -> Vector3:
		var pm := m._hand("mika") + d.fwd("mika") * 0.25
		var pl := m._hand("luna") + d.fwd("luna") * 0.25
		return pm.lerp(pl, float(st.k))
	d.at(t0 + 0.8, func():
		for id in ["mika", "luna"]:
			var c: Array = FightMoves.CLIP.magic_attack_2h
			d.anim(id, m.clipname("magic_attack_2h"), float(c[1]) - 0.08, float(c[1]) + 0.08, 0.5, 0.1, true)
			var hid: String = id
			(st.beams as Array).append(d.fx.beam(func() -> Vector3: return m._hand(hid) + d.fwd(hid) * 0.25, clash_at, id, 0.32))
		st.clash = d.fx.clash(clash_at)
		d.sound("spell_arcane_gather_loop", d.center, -6.0)
		var tw := d.create_tween()
		var setk := func(v: float): st.k = v
		tw.tween_method(setk, 0.5, 0.36, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_method(setk, 0.36, 0.64, 0.8).set_trans(Tween.TRANS_SINE)
		tw.tween_method(setk, 0.64, 0.5, 0.6).set_trans(Tween.TRANS_SINE))
	for k in 6:
		d.at(t0 + 0.9 + k * 0.35, func():
			var p: Vector3 = clash_at.call()
			d.fx.ground_ring(Vector3(p.x, d.center.y, p.z), "mika" if k % 2 == 0 else "luna", 2.4, 1, 0.45)
			d.shake(0.3))
	d.at(t0 + 1.2, func(): quip("mika", "clash", 1.2))
	d.at(t0 + 2.1, func(): quip("luna", "clash", 1.2))
	d.at(t0 + 3.0, func():
		for bm in st.beams:
			d.fx.beam_off(bm)
		d.fx.clash_off(st.clash)
		var at: Vector3 = clash_at.call()
		d.fx.explosion(at, "mika", 1.3)
		d.fx.explosion(at + Vector3(0, 0.2, 0), "luna", 1.1)
		d.fx.pillar(Vector3(at.x, d.center.y, at.z), "mika", 6.0, 1.2)
		d.impact(0.9, true)
		d.sound("thunder_near_1", at, -4.0)
		for id in ["mika", "luna"]:
			m._back(id, 1.0, 0.45)
			d.anim(id, "brace", 0.0, -1.0, 1.0, 0.06))
	d.at(t0 + 3.6, func():
		for id in ["mika", "luna"]:
			d.stance(id))


# ------------------------------------------------------------------------------------------------ the end
func _truce(ex: Dictionary, t0: float) -> void:
	var lines: Array = ex.get("lines", [])
	d.cut(t0, "two_mid", "mika")
	d.cut(t0 + 2.6, "wide", "mika", {"dist": 6.0})
	d.at(t0 + 0.1, func():
		for id in ["mika", "luna"]:
			d.anim(id, "idle_talk", 0.0, -1.0, 1.0, 0.3, true)
		d.face_fx("mika", "happy", 0.8, 3.0)
		d.face_fx("luna", "playful", 0.7, 3.0))
	var tt := t0 + 0.3
	for l in lines.slice(0, 3):
		var who := String(l[0])
		var text := String(l[1])
		d.at(tt, func(): m.say(who, text, 1.7))
		tt += 1.75
	d.at(t0 + 5.2, func():
		for id in ["mika", "luna"]:
			d.anim(id, "victory_nod", 0.0, -1.0, 1.0, 0.25))
