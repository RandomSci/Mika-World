class_name FightMoves
extends RefCounted
## The beat library (2026-10-19): each exchange the referee decided becomes a staged beat - clips on both fighters,
## where they move, her magic, the impact, and the shots (close-up -> wide -> close-up, cuts on the hits). Times are
## fight time from the beat's start; every beat lasts FightPlan.LEN[move]. Positions are read when each event fires
## (a knock-back moves where the next beat starts). Clip timings (segment starts, release frames) live in CLIP below,
## measured from the clips (scripts/tests/ext/fight_probe.gd).

## clip -> [from s, release s (the strike / the cast leaving her hand), to s]
const CLIP := {
	"cast_quick": [0.0, 0.2, 0.5],
	"magic_attack_1h": [0.4, 0.95, 1.5],
	"magic_attack_2h": [0.4, 1.2, 1.9],
	"power_up": [0.3, 1.8, 2.8],
	"jump_attack": [0.0, 1.22, 2.1],
	"spin": [0.1, 0.9, 1.8],
	"kick": [0.15, 0.55, 1.1],
	"knock": [0.0, 0.0, 1.05],
	"jump_back": [0.0, 0.3, 0.63],
	"block": [0.0, 0.25, 0.5],
	"fall": [0.0, 0.6, 1.3],
	"land": [0.0, 0.0, 1.0],
}
const NAME := {"power_up": "sword:great_sword_power_up", "jump_attack": "sword:great_sword_jump_attack", "spin": "sword:great_sword_high_spin_attack",
	"kick": "sword:great_sword_kick", "hit": "hit_chest", "knock": "sword:great_sword_impact_3", "land": "ual_react:NinjaJump_Land", "jump_back": "sword:great_sword_jump",
	"strafe": "sword:great_sword_strafe", "block": "brace", "fall": "rx_fall_back"}

var d: FightDirector
var _talk_until := -1.0                  # fight time the current line is expected to end (no overlapping lines)


func clipname(k: String) -> String:
	return String(NAME.get(k, k))


## Plays the segment of clip k (CLIP table) over `dur` s (-1 = its own speed); returns the seconds to its release.
func seg(id: String, k: String, dur := -1.0, fade := 0.1, to_override := -1.0) -> float:
	var c: Array = CLIP.get(k, [0.0, 0.0, -1.0])
	var from: float = c[0]
	var to: float = to_override if to_override > 0.0 else float(c[2])
	var speed := 1.0
	if dur > 0.0:
		speed = maxf((to - from) / dur, 0.05)
	d.anim(id, clipname(k), from, to, speed, fade)
	return (float(c[1]) - from) / speed


func say(id: String, text: String, est := 1.8) -> void:
	if d.ft < _talk_until:
		return
	_talk_until = d.ft + est
	d.say(id, text)


func stage(ex: Dictionary, t0: float) -> float:
	var mv := String(ex.move)
	var L := float(FightPlan.LEN.get(mv, 2.0))
	match mv:
		"faceoff": _faceoff(ex, t0)
		"bow": _bow(ex, t0)
		"charge": _charge(ex, t0)
		"volley": _volley(ex, t0)
		"dash_strike": _dash_strike(ex, t0)
		"aerial": _aerial(ex, t0)
		"spin": _spin(ex, t0)
		"counter": _counter(ex, t0)
		"clash": _clash(ex, t0)
		"finisher": _finisher(ex, t0)
		"aftermath": _aftermath(ex, t0)
		"laugh": _laugh(ex, t0)
	return L


# ------------------------------------------------------------------------------------------------ helpers
func _recenter(t0: float) -> void:
	d.at(t0, func():
		for id in ["mika", "luna"]:
			if d._flat(d.pos(id) - d.home(id)).length() > 0.5:
				d.move(id, d.home(id), 0.35, Tween.TRANS_SINE, Tween.EASE_IN_OUT))


func _back(id: String, m: float, dur: float) -> void:
	d.move(id, d.pos(id) - d.fwd(id) * m, dur, Tween.TRANS_EXPO, Tween.EASE_OUT)


## A blow landing on `def`: her reaction, the knock-back, the spark and the impact feel.
func _hit(att: String, def: String, power: float, at: Vector3, big := false, kind := "hit") -> void:
	var dir := d.fwd(att)
	d.fx.hit_spark(at, att, dir, power > 0.6)
	d.impact(power, big)
	if kind == "knock" or power > 0.7:
		seg(def, "knock", 0.75, 0.05)
		_back(def, 1.2 + power, 0.55)
	else:
		d.anim(def, "hit_head" if d.rng.randf() < 0.4 else "hit_chest", 0.0, -1.0, 1.25, 0.05)
		_back(def, 0.45, 0.3)
	d.face_fx(def, "surprised", 1.0, 0.6)
	d.sound("impact_heavy" if power > 0.6 else "impact_light", at, -2.0 if power > 0.6 else -4.0)
	d.sound("spell_water_impact" if att == "mika" else "spell_umbral_impact", at, -6.0)
	if d.mode == "training":
		d.F[att].touches = int(d.F[att].touches) + 1
		d.at(d.ft + 0.5, func():
			say(def, ["Hey! No fair!", "Ow, okay, okay!", "Hmph. Lucky shot."][d.rng.randi() % 3], 1.3)
			d.face_fx(att, "laughing", 1.0, 1.2))
	d.at(d.ft + 0.65, func(): d.stance(def))


func _shield_up(def: String, att: String) -> Dictionary:
	seg(def, "block", 0.25, 0.08)
	var h := d.fx.shield(d.F[def].c, def, func() -> Vector3: return d.pos(att))
	d.F[def].shield = h
	d.sound("ward_mirror_up", d.chest(def), -6.0)
	return h


func _shield_down(def: String, dur := 0.25) -> void:
	d.fx.shield_off(d.F[def].shield, dur)
	d.F[def].shield = {}


func _shield_point(def: String, _att: String) -> Vector3:
	return d.pos(def) + d.fwd(def) * 0.62 + Vector3(0, 1.05 + ((d.F[def].c as Node3D).global_position.y - d.pos(def).y), 0)


func _side_dodge(def: String, sgn: float, dist := 1.15, dur := 0.32) -> void:
	var lat := d.fwd(def).cross(Vector3.UP).normalized() * sgn
	d.anim(def, "sword:great_sword_strafe" if sgn > 0.0 else "sword:great_sword_strafe_2", 0.1, 0.8, 1.6, 0.06)
	d.move(def, d.pos(def) + lat * dist - d.fwd(def) * 0.2, dur, Tween.TRANS_EXPO, Tween.EASE_OUT)
	d.fx.afterimages(d.F[def].c, def, 4, 0.045)
	d.fx.puff(d.pos(def), 6, 0.35)
	d.sound("portal_whoosh", d.chest(def), -10.0, 1.4)
	d.at(d.ft + dur + 0.25, func(): d.stance(def))


func _jump_back(def: String, dist := 1.4) -> void:
	seg(def, "jump_back", 0.55, 0.06)
	d.move(def, d.pos(def) - d.fwd(def) * dist, 0.5, Tween.TRANS_QUAD, Tween.EASE_OUT)
	d.hop(def, 0.35, 0.5)
	d.fx.afterimages(d.F[def].c, def, 3, 0.06)
	d.at(d.ft + 0.6, func(): d.stance(def))


func _hand(id: String) -> Vector3:
	return (d.bone(id, "RightHand") + d.bone(id, "LeftHand")) * 0.5


func _shot_index(t: float) -> int:
	for i in d._shots.size():
		if absf(float(d._shots[i][0]) - t) < 0.001:
			return i
	return d._shots.size() - 1


# ------------------------------------------------------------------------------------------------ the opening
func _faceoff(_ex: Dictionary, t0: float) -> void:
	d.cut(0.0, "establish", "mika")
	d.cut(t0 + 0.85, "face", "mika", {"roll": -6.0})
	d.cut(t0 + 1.45, "face", "luna", {"roll": 6.0})
	d.cut(t0 + 2.0, "wide_low", "mika", {"roll": -4.0})
	d.at(t0, func():
		d.face_fx("mika", "determined", 0.9, 3.0)
		d.face_fx("luna", "determined", 0.7, 3.0))
	d.at(t0 + 0.15, func(): say("mika", "Don't hold back, Luna.", 1.3))
	d.at(t0 + 1.5, func():
		say("luna", "I never do.", 1.2)
		d.face_fx("luna", "playful", 0.8, 1.0))
	d.at(t0 + 2.0, func():
		d.sound("spell_wind_activation", d.center, -8.0)
		d.shake(0.25))


func _bow(_ex: Dictionary, t0: float) -> void:
	d.cut(0.0, "two_mid", "mika")
	d.cut(t0 + 1.0, "face", "mika")
	d.cut(t0 + 1.7, "face", "luna")
	d.at(t0 + 0.1, func():
		for id in ["mika", "luna"]:
			d.anim(id, "victory_nod", 0.0, -1.0, 1.0, 0.25)
		d.face_fx("mika", "playful", 0.9, 2.0)
		d.face_fx("luna", "happy", 0.7, 2.0))
	d.at(t0 + 0.2, func(): say("mika", "Ready to lose again?", 1.6))
	d.at(t0 + 1.9, func(): say("luna", "Ha! You wish.", 1.2))
	d.at(t0 + 1.4, func():
		for id in ["mika", "luna"]:
			d.stance(id, 0.3))


func _charge(ex: Dictionary, t0: float) -> void:
	var first := String(ex.att)
	d.cut(t0, "orbit", "mika", {"from": 5.0, "to": 70.0, "r": 4.6})
	d.cut(t0 + 0.95, "hero_low", first, {"roll": -8.0})
	d.at(t0, func():
		for id in ["mika", "luna"]:
			seg(id, "power_up", 1.4, 0.2)
			d.F[id].aura = d.fx.aura(d.F[id].c, id, 1.0)
		d.sound("spell_arcane_charge", d.center, -4.0)
		d.shake(0.3))
	d.at(t0 + 1.45, func():
		for id in ["mika", "luna"]:
			d.fx.aura_off(d.F[id].aura)
			d.stance(id, 0.2))


# ------------------------------------------------------------------------------------------------ exchanges
## Three quick bolts; the defender side-steps them, takes them on a shield (it cracks), or the last one lands.
func _volley(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var oc := String(ex.outcome)
	_recenter(t0)
	d.cut(t0, "ots", a, {"roll": -5.0})
	d.cut(t0 + 0.8, "wide", a, {"dist": 6.2})
	d.cut(t0 + 1.62, "crash" if oc == "hit" else "face_ots", b, {"fov_to": 30.0})
	if oc == "block":
		d.at(t0 + 0.25, func(): _shield_up(b, a))
	for i in 3:
		var tr := t0 + 0.2 + i * 0.48
		d.at(tr, func():
			var lead := seg(a, "cast_quick", 0.42, 0.06)
			d.fx.hand_charge(d.F[a].c, a, "RightHand", lead + 0.05, 0.4)
			d.at(d.ft + lead, func(): _bolt(a, b, i, oc)))
	d.at(t0 + 1.75, func():
		d.stance(a)
		_shield_down(b, 0.4))
	if oc == "dodge":
		d.at(t0 + 0.5, func(): _side_dodge(b, 1.0))
		d.at(t0 + 1.25, func(): _side_dodge(b, -1.0, 1.0))


func _bolt(a: String, b: String, i: int, oc: String) -> void:
	var from := d.bone(a, "RightHand") + d.fwd(a) * 0.15
	var flight := 0.3
	d.sound("spell_water_release" if a == "mika" else "spell_umbral_release", from, -8.0, 1.2 + i * 0.1)
	if oc == "block":
		var tgt := func() -> Vector3: return _shield_point(b, a)
		var on_block := func(p: Vector3):
			d.fx.shield_hit(d.F[b].shield, p, 0.3 if i < 2 else 0.5)
			d.fx.sparks(p, -d.fwd(b), a, 20, 4.0)
			d.impact(0.3 + 0.1 * i)
			d.sound("ward_mirror_absorb", p, -5.0)
			if i == 2:
				_back(b, 0.35, 0.25)
		d.fx.projectile(from, tgt, a, flight, 0.5, 0.15 * (i - 1), on_block, (i - 1) * 0.25)
	elif oc == "hit" and i == 2:
		var tgt2 := func() -> Vector3: return d.chest(b)
		var on_hit := func(p: Vector3): _hit(a, b, 0.55, p, false)
		d.fx.projectile(from, tgt2, a, flight, 0.55, 0.1, on_hit)
	else:
		# a miss: it flies past where she was and bursts on the ground behind her
		var miss := d.pos(b) + d.fwd(a) * 1.4 + Vector3(0, 0.02, 0)
		var to_miss := func() -> Vector3: return miss
		var on_miss := func(p: Vector3):
			d.fx.ground_ring(p, a, 1.6, 1, 0.5)
			d.fx.sparks(p, Vector3.UP, a, 16, 3.5)
			d.sound("impact_light", p, -10.0)
		d.fx.projectile(from, to_miss, a, flight + 0.08, 0.5, 0.35, on_miss, (i - 1) * 0.3)
		if oc == "hit" and i < 2:
			d.at(d.ft + 0.02, func(): _side_dodge(b, 1.0 if i == 0 else -1.0, 0.8, 0.26))


## She dashes in (afterimages, dust) and blasts point-blank; the defender is knocked back, blocks, or jumps clear.
func _dash_strike(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var oc := String(ex.outcome)
	_recenter(t0)
	d.cut(t0, "behind", a)
	d.cut(t0 + 0.32, "track", a, {"tween": 0.1})
	d.cut(t0 + 0.78, "profile" if oc != "hit" else "crash", b if oc == "hit" else a, {"fov_to": 34.0, "roll": 8.0})
	d.cut(t0 + 1.3, "wide", a, {"dist": 6.8})
	d.at(t0 + 0.2, func():
		var to := d.pos(b) - d.fwd(a) * 1.25
		d.anim(a, "dodge_dash", 0.0, -1.0, 1.6, 0.06, true)
		d.move(a, to, 0.36, Tween.TRANS_QUAD, Tween.EASE_IN)
		d.fx.afterimages(d.F[a].c, a, 5, 0.06)
		d.fx.puff(d.pos(a), 8, 0.4)
		d.sound("portal_whoosh", d.chest(a), -6.0, 1.2))
	d.at(t0 + 0.5, func():
		var lead := seg(a, "magic_attack_1h", 0.3, 0.06)
		d.fx.hand_charge(d.F[a].c, a, "RightHand", lead, 0.6)
		if oc == "block":
			_shield_up(b, a)
		elif oc == "dodge":
			d.at(d.ft + lead * 0.4, func(): _jump_back(b, 1.5)))
	d.at(t0 + 0.82, func():
		var at := d.bone(a, "RightHand") + d.fwd(a) * 0.35
		d.sound("spell_water_release" if a == "mika" else "spell_umbral_release", at, -4.0)
		if oc == "hit":
			_hit(a, b, 0.8, d.chest(b), false, "knock")
			d.fx.explosion(d.pos(b) + d.fwd(a) * 0.2, a, 0.55)
		elif oc == "block":
			d.fx.shield_hit(d.F[b].shield, _shield_point(b, a), 0.55)
			d.fx.hit_spark(_shield_point(b, a), a, -d.fwd(b), true)
			d.impact(0.55)
			_back(a, 0.5, 0.3)
			_back(b, 0.7, 0.35)
			d.sound("ward_mirror_absorb", at, -3.0)
		else:
			var gnd := at + d.fwd(a) * 2.6
			gnd.y = d.pos(a).y + 0.05
			var to_gnd := func() -> Vector3: return gnd
			var on_gnd := func(p: Vector3):
				d.fx.ground_ring(p, a, 2.4, 2, 0.6)
				d.fx.debris(p, 10, 0.7)
				d.shake(0.5)
			d.fx.projectile(at, to_gnd, a, 0.22, 0.7, 0.0, on_gnd))
	d.at(t0 + 1.35, func():
		_shield_down(b)
		d.stance(a)
		d.move(a, d.home(a), 0.55, Tween.TRANS_SINE, Tween.EASE_IN_OUT))


## She leaps and comes down on the defender's spot: an explosion of her magic; a side dash clear, a shield, or a hit.
func _aerial(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var oc := String(ex.outcome)
	var c: Array = CLIP.jump_attack
	var land_lead := float(c[1]) - float(c[0])
	_recenter(t0)
	d.cut(t0, "crane", a, {"roll": -10.0})
	d.cut(t0 + land_lead - 0.12, "impact", b, {"at": Vector3.ZERO})
	d.cut(t0 + land_lead + 0.75, "face_ots" if oc != "hit" else "hero_low", a)
	d.at(t0 + 0.05, func():
		seg(a, "jump_attack", -1.0, 0.08)
		var to := d.pos(b) - d.fwd(a) * 0.95
		d.at(d.ft + land_lead * 0.25, func(): d.move(a, to, land_lead * 0.7, Tween.TRANS_SINE, Tween.EASE_IN_OUT))
		d.at(d.ft + land_lead * 0.2, func(): d.hop(a, 0.9, land_lead * 0.75))
		d.sound("phoenix_wing_gust", d.chest(a), -8.0, 1.3)
		d._shots[_shot_index(t0 + land_lead - 0.12)][3]["at"] = d.pos(b))
	if oc == "block":
		d.at(t0 + land_lead - 0.45, func(): _shield_up(b, a))
	elif oc == "dodge":
		d.at(t0 + land_lead - 0.3, func(): _side_dodge(b, -1.0, 1.4, 0.3))
	d.at(t0 + land_lead, func():
		var at := d.pos(a) + d.fwd(a) * 0.6
		d.fx.explosion(at, a, 1.0 if oc == "hit" else 0.8)
		d.sound("rift_erupt", at, -2.0)
		if oc == "hit":
			_hit(a, b, 0.9, d.chest(b), true, "knock")
		elif oc == "block":
			d.fx.shield_hit(d.F[b].shield, _shield_point(b, a), 0.7)
			d.impact(0.65)
			_back(b, 0.8, 0.35)
		else:
			d.impact(0.5))
	d.at(t0 + land_lead + 0.7, func():
		_shield_down(b)
		d.stance(a))


## A spinning strike up close, crescent slashes of light round her.
func _spin(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var oc := String(ex.outcome)
	var c: Array = CLIP.spin
	var lead := float(c[1]) - float(c[0])
	_recenter(t0)
	d.cut(t0, "orbit", a, {"from": -30.0, "to": 40.0, "r": 3.8, "roll": 6.0})
	d.cut(t0 + lead - 0.05, "profile", a)
	d.cut(t0 + lead + 0.6, "face", b if oc == "hit" else a, {"roll": -6.0})
	d.at(t0 + 0.02, func():
		d.move(a, d.pos(b) - d.fwd(a) * 1.25, 0.3, Tween.TRANS_QUAD, Tween.EASE_OUT)
		d.fx.afterimages(d.F[a].c, a, 3, 0.05)
		seg(a, "spin", -1.0, 0.08))
	if oc == "block":
		d.at(t0 + lead - 0.3, func(): _shield_up(b, a))
	elif oc == "dodge":
		d.at(t0 + lead - 0.25, func(): _jump_back(b, 1.3))
	for k in 2:
		d.at(t0 + lead - 0.25 + k * 0.18, func():
			var cc := d.chest(a) - Vector3(0, 0.15 + k * 0.2, 0)
			d.fx.crescent(cc, Vector3.UP.rotated(d.fwd(a), 0.25 * (1 - 2 * k)), d.fwd(a), 1.05 + k * 0.2, -160.0 + k * 40.0, 160.0 + k * 40.0, a, 0.2, 0.09)
			d.sound("spell_wind_release", cc, -9.0, 1.3 + k * 0.2))
	d.at(t0 + lead, func():
		if oc == "hit":
			_hit(a, b, 0.7, d.chest(b), false)
		elif oc == "block":
			d.fx.shield_hit(d.F[b].shield, _shield_point(b, a), 0.5)
			d.impact(0.45)
			_back(b, 0.5, 0.3)
		else:
			d.fx.ground_ring(d.pos(a), a, 2.6, 1, 0.5))
	d.at(t0 + lead + 0.55, func():
		_shield_down(b)
		d.stance(a)
		d.move(a, d.home(a), 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT))


## The attacker's bolt is side-stepped and the defender answers at once: in close with a kick of light.
func _counter(ex: Dictionary, t0: float) -> void:
	var a := String(ex.att)
	var b := String(ex.def)
	var oc := String(ex.outcome)
	_recenter(t0)
	d.cut(t0, "ots", a, {"roll": 5.0})
	d.cut(t0 + 0.55, "orbit", b, {"from": 60.0, "to": 20.0, "r": 4.0, "tween": 0.12})
	d.cut(t0 + 1.15, "crash", a if oc == "hit" else b, {"fov_to": 32.0, "roll": -8.0})
	d.cut(t0 + 1.6, "overhead", a)
	d.at(t0 + 0.1, func():
		var lead := seg(a, "magic_attack_1h", 0.35, 0.08)
		d.fx.hand_charge(d.F[a].c, a, "RightHand", lead, 0.5)
		d.at(d.ft + lead, func():
			var from := d.bone(a, "RightHand")
			var miss := d.pos(b) + d.fwd(a) * 1.8 + Vector3(0, 0.6, 0)
			var to_miss := func() -> Vector3: return miss
			var on_miss := func(p: Vector3): d.fx.ground_ring(Vector3(p.x, d.pos(b).y, p.z), a, 1.6, 1, 0.5)
			d.fx.projectile(from, to_miss, a, 0.32, 0.6, 0.1, on_miss)
			d.sound("spell_water_release" if a == "mika" else "spell_umbral_release", from, -6.0)))
	d.at(t0 + 0.38, func(): _side_dodge(b, 1.0, 0.9, 0.24))
	d.at(t0 + 0.75, func():
		d.anim(b, "dodge_dash", 0.0, -1.0, 1.6, 0.06, true)
		d.move(b, d.pos(a) - d.fwd(b) * 1.35, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN)
		d.fx.afterimages(d.F[b].c, b, 4, 0.05))
	d.at(t0 + 1.0, func():
		var lead := seg(b, "kick", 0.32, 0.06)
		if oc == "block":
			_shield_up(a, b)
		d.at(d.ft + lead, func():
			var at := d.chest(a) - Vector3(0, 0.25, 0)
			d.fx.crescent(at + d.fwd(b) * -0.2, d.fwd(b).cross(Vector3.UP), d.fwd(b), 0.7, -60.0, 80.0, b, 0.14, 0.08)
			if oc == "hit":
				_hit(b, a, 0.75, at, false, "knock")
			else:
				d.fx.shield_hit(d.F[a].shield, _shield_point(a, b), 0.5)
				d.impact(0.5)
				_back(a, 0.6, 0.3)
				_back(b, 0.4, 0.3)))
	d.at(t0 + 1.75, func():
		_shield_down(a)
		d.stance(b)
		d.move(b, d.home(b), 0.4, Tween.TRANS_SINE, Tween.EASE_IN_OUT))


## Both beams at once; the clash orb rocks between them; the stronger push wins and blows the other back.
func _clash(ex: Dictionary, t0: float) -> void:
	var w := String(ex.att)
	var l := String(ex.def)
	var st := {"k": 0.5, "beams": [], "clash": {}}
	d.at(t0, func():
		for id in ["mika", "luna"]:
			d.move(id, d.home(id), 0.3, Tween.TRANS_SINE, Tween.EASE_OUT))
	d.cut(t0, "wide_low", "mika", {"roll": 6.0})
	d.cut(t0 + 0.9, "profile", "mika")
	d.cut(t0 + 1.55, "face", "mika", {"roll": -8.0, "side": 1.0})
	d.cut(t0 + 2.0, "face", "luna", {"roll": 8.0, "side": 1.0})
	d.cut(t0 + 2.45, "overhead", "mika")
	d.cut(t0 + 3.05, "wide", w, {"dist": 7.2, "roll": -6.0})
	d.at(t0 + 0.25, func():
		for id in ["mika", "luna"]:
			seg(id, "magic_attack_2h", 0.55, 0.12)
		d.sound("spell_arcane_charge", d.center, -6.0))
	var clash_at := func() -> Vector3:
		var pm := _hand("mika") + d.fwd("mika") * 0.25
		var pl := _hand("luna") + d.fwd("luna") * 0.25
		return pm.lerp(pl, float(st.k))
	d.at(t0 + 0.8, func():
		# hold the release pose, trembling a little (a short loop round the release frame)
		for id in ["mika", "luna"]:
			var c: Array = CLIP.magic_attack_2h
			d.anim(id, clipname("magic_attack_2h"), float(c[1]) - 0.08, float(c[1]) + 0.08, 0.5, 0.1, true)
			var hid: String = id
			var bm := d.fx.beam(func() -> Vector3: return _hand(hid) + d.fwd(hid) * 0.25, clash_at, id, 0.3)
			(st.beams as Array).append(bm)
		st.clash = d.fx.clash(clash_at)
		d.sound("spell_arcane_gather_loop", d.center, -6.0)
		d.sound("thunder_far_1", d.center, -10.0)
		d.face_fx("mika", "determined", 1.0, 2.5)
		d.face_fx("luna", "determined", 1.0, 2.5)
		var tw := d.create_tween()
		var lose_k := 0.68 if l == "luna" else 0.32
		var win_k := 0.32 if l == "luna" else 0.68
		var setk := func(v: float): st.k = v
		tw.tween_method(setk, 0.5, win_k, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_method(setk, win_k, lose_k, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_method(setk, lose_k, 0.5, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_method(setk, 0.5, 0.97 if l == "luna" else 0.03, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN))
	for k in 6:
		d.at(t0 + 0.9 + k * 0.33, func():
			var p: Vector3 = clash_at.call()
			d.fx.ground_ring(Vector3(p.x, d.center.y, p.z), "mika" if k % 2 == 0 else "luna", 2.2, 1, 0.45)
			d.shake(0.35))
	d.at(t0 + 1.3, func(): say(w, "Not this time!" if w == "mika" else "Give up!", 1.4))
	d.at(t0 + 3.1, func():
		for bm in st.beams:
			d.fx.beam_off(bm)
		d.fx.clash_off(st.clash)
		var at := d.chest(l)
		d.fx.explosion(d.pos(l) + d.fwd(w) * -0.2, w, 1.2)
		_hit(w, l, 1.0, at, true, "knock")
		d.sound("thunder_near_1", at, -4.0)
		d.stance(w))
	d.at(t0 + 3.5, func(): d.stance(l))


# ------------------------------------------------------------------------------------------------ the end
## The finisher: her power rises (aura, a pillar of light), slow motion as the great star / moon leaves her hands,
## the shield shatters, the explosion; she goes down.
func _finisher(ex: Dictionary, t0: float) -> void:
	var w := String(ex.att)
	var l := String(ex.def)
	var st := {"aura": {}}
	_recenter(t0)
	d.cut(t0, "hero_low", w, {"roll": -10.0})
	d.cut(t0 + 0.75, "face", w, {"roll": 5.0})
	d.cut(t0 + 1.3, "behind", w, {"roll": -4.0})
	d.cut(t0 + 1.62, "impact", l, {"at": Vector3.ZERO, "roll": 8.0})
	d.cut(t0 + 2.55, "wide", w, {"dist": 7.0})
	d.at(t0, func():
		seg(w, "power_up", 1.2, 0.15)
		st.aura = d.fx.aura(d.F[w].c, w, 1.4)
		d.fx.pillar(d.pos(w) - d.fwd(w) * 1.1, w, 8.0, 1.4)
		d.sound("phoenix_nova_charge", d.chest(w), -4.0)
		d.shake(0.4)
		d.face_fx(w, "determined", 1.0, 2.0)
		d._shots[_shot_index(t0 + 1.62)][3]["at"] = d.pos(l)
		_shield_up(l, w))
	d.at(t0 + 0.85, func(): say(w, "Starfall!" if w == "mika" else "Moonfall!", 1.0))
	d.at(t0 + 1.25, func():
		d.fx.aura_off(st.aura)
		var lead := seg(w, "magic_attack_2h", 0.32, 0.08)
		d.at(d.ft + lead, func():
			var from := _hand(w) + d.fwd(w) * 0.3 + Vector3(0, 0.1, 0)
			d.slowmo(0.3, 0.42)
			d.sound("phoenix_nova_release", from, -2.0)
			var to_sh := func() -> Vector3: return _shield_point(l, w)
			var on_fin := func(p: Vector3):
				d.fx.shield_shatter(d.F[l].shield, d.fwd(w))
				d.F[l].shield = {}
				d.fx.explosion(d.pos(l), w, 1.5)
				d.sound("phoenix_nova_impact", p, 0.0)
				d.sound("crystal_shatter", p, -3.0)
				d.sfx.zoom_blur(0.8, 0.5)
				d.sfx.wash((FightFX.pal(w).glow as Color), 0.35, 0.05, 0.25, 0.5)
				d.impact(1.0, true)
				d.slowmo(0.35, 0.5)
				d.fx.hit_spark(d.chest(l), w, d.fwd(w), true)
				seg(l, "fall", 0.9, 0.05)
				d.move(l, d.pos(l) - d.fwd(l) * 1.5, 0.7, Tween.TRANS_EXPO, Tween.EASE_OUT)
				d.F[l].yaw_k = 0.0
				d.face_fx(l, "surprised", 1.0, 1.0)
			d.fx.projectile(from, to_sh, w, 0.36, 1.6, 0.25, on_fin)))
	d.at(t0 + 2.6, func():
		d.anim(l, "rx_down_back", 0.0, -1.0, 1.0, 0.35, true)
		d.anim(w, "combat_idle", 0.0, -1.0, 0.8, 0.4, true))


## After the duel: the winner goes to her, offers a hand, pulls her up; a high five.
func _aftermath(ex: Dictionary, t0: float) -> void:
	var w := String(ex.att)
	var l := String(ex.def)
	d.cut(t0, "wide", w, {"dist": 6.0, "drift": 0.5})
	d.cut(t0 + 1.6, "two_mid", w, {"lean": 1.0})
	d.cut(t0 + 3.2, "two_mid", w, {"lean": -1.0})
	d.at(t0, func():
		d.face_fx(w, "relieved", 0.9, 2.0)
		d.anim(w, "walk", 0.0, -1.0, 1.0, 0.3, true)
		var to := d.pos(l) + d.fwd(l) * 0.95
		d.move(w, to, 1.25, Tween.TRANS_SINE, Tween.EASE_IN_OUT))
	d.at(t0 + 0.4, func(): say(w, "Are you okay?" if w == "mika" else "Still in one piece?", 1.4))
	d.at(t0 + 1.3, func():
		d.anim(w, "rx_reach_help", 0.0, -1.0, 1.0, 0.3)
		d.F[w].reach.reach("Right", d.bone(l, "RightHand").lerp(d.chest(w), 0.5) + Vector3(0, 0.15, 0), 0.8)
		d.anim(l, "rx_sit_up", 0.0, -1.0, 1.0, 0.3)
		d.face_fx(l, "relieved", 0.9, 2.0))
	d.at(t0 + 2.0, func():
		d.anim(l, "rx_stand_from_sit", 0.0, -1.0, 1.25, 0.25)
		d.F[w].reach.release("Right"))
	d.at(t0 + 2.75, func():
		d.F[l].yaw_k = 1.0
		d.move(l, d.pos(l) + d.fwd(l) * 0.15, 0.4)
		d.anim(w, "idle", 0.0, -1.0, 1.0, 0.5, true)
		say(l, "Next time I'm winning.", 1.6))
	d.at(t0 + 3.2, func(): d.anim(l, "idle", 0.0, -1.0, 1.0, 0.5, true))
	_high_five(t0 + 3.75, w, l)


func _high_five(t: float, a: String, b: String) -> void:
	d.at(t - 0.55, func():
		var mid := (d.chest(a) + d.chest(b)) * 0.5 + Vector3(0, 0.55, 0)
		d.F[a].reach.reach("Right", mid + d.fwd(a) * -0.04, 1.0)
		d.F[b].reach.reach("Right", mid + d.fwd(b) * -0.04, 1.0)
		d.face_fx(a, "happy", 1.0, 2.0)
		d.face_fx(b, "happy", 1.0, 2.0))
	d.at(t, func():
		var mid := (d.bone(a, "RightHand") + d.bone(b, "RightHand")) * 0.5
		d.fx.pop(mid, a, 1.2, 0.3, 5.0, "star_07_a.png", 1.6)
		d.fx.pop(mid, b, 0.9, 0.3, 4.0, "magic_03_a.png", 1.6)
		d.fx.sparks(mid, Vector3.UP, a, 14, 2.5)
		d.fx.sparks(mid, Vector3.UP, b, 14, 2.5)
		d.sound("impact_light", mid, -6.0, 1.3)
		d.face_fx(a, "laughing", 0.9, 1.5)
		d.face_fx(b, "laughing", 0.9, 1.5))
	d.at(t + 0.6, func():
		d.F[a].reach.release("Right")
		d.F[b].reach.release("Right"))


## The end of a training bout: they laugh about it and high-five (no winner made much of).
func _laugh(ex: Dictionary, t0: float) -> void:
	var tm: Dictionary = ex.get("touches", {"mika": 0, "luna": 0})
	var lead := "mika" if int(tm.mika) > int(tm.luna) else ("luna" if int(tm.luna) > int(tm.mika) else "")
	_recenter(t0)
	d.cut(t0, "two_mid", "mika", {"lean": 1.0})
	d.cut(t0 + 1.6, "face", "luna" if lead == "mika" else "mika")
	d.cut(t0 + 2.3, "two_mid", "mika", {"lean": -1.0})
	d.at(t0 + 0.1, func():
		for id in ["mika", "luna"]:
			d.anim(id, "idle", 0.0, -1.0, 1.0, 0.4, true)
			d.face_fx(id, "laughing", 1.0, 2.5)
			d.move(id, d.center + (d.home(id) - d.center) * 0.2, 1.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT))
	var words := ["zero", "one", "two", "three", "four", "five"]
	var top := maxi(int(tm.mika), int(tm.luna))
	var score := "%s to %s" % [words[mini(top, 5)], words[mini(mini(int(tm.mika), int(tm.luna)), 5)]]
	score = score.left(1).to_upper() + score.substr(1)
	d.at(t0 + 0.3, func():
		_talk_until = -1.0                         # (the last word of a bout is always said)
		if lead == "mika":
			say("mika", "Haha! %s. Pay up!" % score, 1.8)
		elif lead == "luna":
			say("luna", "Hehe. %s, Mika." % score, 1.6)
		else:
			say("mika", "Haha, a draw again!", 1.4))
	d.at(t0 + 2.0, func():
		_talk_until = -1.0
		if lead == "mika":
			say("luna", "Ugh, rematch tomorrow!", 1.4)
		else:
			say("mika", "Okay, okay, you got me!", 1.4))
	_high_five(t0 + 3.3, "mika", "luna")
