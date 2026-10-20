class_name FightCine
extends RefCounted
## The live fight's cinematographer (2026-10-20, Selwyn: "the camera angles like close timings are so critical like in
## those videos especially during fights", his references Download 3, 4, 5, 7). It replaces the old follow shot
## (one two-shot every 2.6 to 4.2 s) with cuts timed to what happens, from the director's shot library:
##   a strike's windup       a side profile of both, or over the attacker's shoulder, or the defender's face
##   the blow lands          a close up on the contact point (hit_close), held through the hit stop
##   the recoil              a low wide shot as she is driven back, or a crane on a launch / knockdown
##   a dash or a rush        tracking alongside her
##   a spell's gather        the low hero angle on the caster
##   the release             behind the caster along the spell's path, then the impact
##   between exchanges       a wide or a slow orbit, held at most 1.2 s
## Rules from the references: a cut every 0.3 to 1.2 s in an exchange, never two of the same kind in a row, a close up
## only at a hit, the 180 degree line kept (the director's side), and an ultimate's own cinematic is never interrupted
## (UltimateCast holds the camera through sim.cine_hold).
## Every choice is logged to `log` [t, kind, who, why] for the review sheets.

const MIN_SHOT := 0.3                     # fight seconds
const NEUTRAL_MAX := 1.2
const HIT_HOLD := 0.42

var sim: MeleeSim
var cur := ""
var since := 0.0
var until := 0.0                          # the current shot is kept at least until then
var _ev_i := 0
var _atk_i := 0
var _last_kinds: Array = []
var log: Array = []


static func make(s: MeleeSim) -> FightCine:
	var c := FightCine.new()
	c.sim = s
	return c


func _cut(kind: String, who: String, opts: Dictionary, hold: float, why: String) -> void:
	var t := sim.t
	sim.d.cut(sim.d.ft + 0.001, kind, who, opts)
	cur = kind
	since = t
	until = t + hold
	_last_kinds.append(kind)
	if _last_kinds.size() > 3:
		_last_kinds.pop_front()
	log.append([snappedf(t, 0.01), kind, who, why])
	sim._next_cam = t + 99.0                       # (the old follow camera stays off)


func _fresh(kinds: Array) -> String:
	for k in kinds:
		if _last_kinds.is_empty() or String(_last_kinds[_last_kinds.size() - 1]) != String(k):
			return String(k)
	return String(kinds[0])


func _can_cut(urgent := false) -> bool:
	if sim.t < float(sim.get("cine_hold")):
		return false
	return sim.t - since >= (0.22 if urgent else MIN_SHOT)


var _pc := 0                               # paired contacts so far (close-ups alternate)
var _wc := 0                               # paired windups so far
var _quiet_since := -99.0                 # the last blade contact (a new exchange after a pause resets with a wide)


## A weapon windup (Download(7)): a new exchange after a pause opens wide to set the space; a dash, lunge or run is
## on her feet then alongside her; anything else from the side or over her shoulder.
func _weapon_windup(who: String, clip: String) -> void:
	var spec: Array = WeaponPlay.STRIKES.get(clip, [])
	var travel := String(spec[5]) if spec.size() > 5 else ""
	var far := travel == "through" or (travel == "forward" and spec.size() > 6 and float(spec[6]) >= 0.8)
	if BodyMoves.has(clip):
		far = absf(float(BodyMoves.entry(clip).get("travel", 0.0))) >= 1.5      # (the suit mocap's own travel: a dash, a long combo)
	var lead := 0.0
	if sim.t - _quiet_since > 2.5 and (not sim.has_meta("paired") or sim._flat(sim.d.pos("mika") - sim.d.pos("luna")).length() > 4.5):
		_cut("wide_low", who, {}, 0.55, "reset " + clip)
		lead = 0.55
	var go := func():
		if sim.t < float(sim.get("cine_hold")):
			return
		if sim.has_meta("paired"):
			# (paired, Download(7): her face as she commits every third windup, else both bodies; a long travel from the
			# side, it crosses the frame)
			_wc += 1
			var k3 := "profile" if far else _fresh(["duo", "profile", "orbit", "wide_low"])
			var o3 := {"k": 1.0, "high": 0.25}
			if k3 == "orbit":
				o3 = {"from": sim.rng.randf_range(-20.0, 20.0), "to": sim.rng.randf_range(40.0, 70.0), "r": 4.2}
			_cut(k3, who, o3, 0.55, "windup " + clip)
			return
		if far:
			_cut("feet", who, {}, 0.5, "dash " + clip)
			sim.at(0.5, func():
				if sim.t >= float(sim.get("cine_hold")) and cur == "feet":
					_cut("track", who, {}, 0.7, "dash " + clip))
		else:
			_cut(_fresh(["profile", "track", "duo"]), who, {}, 0.7, "windup " + clip)
	if lead > 0.0:
		sim.at(lead, go)
	else:
		go.call()


## Called by the sim every frame (fight time).
func update() -> void:
	if sim.t < float(sim.get("cine_hold")):
		_ev_i = sim.events.size()
		_atk_i = sim.attacks.size()
		return
	var rng := sim.rng
	# 1 a blow landed: close on the contact, then the recoil
	while _atk_i < sim.attacks.size():
		var a: Dictionary = sim.attacks[_atk_i]
		_atk_i += 1
		var oc := String(a.get("outcome", ""))
		var p: Vector3 = a.get("touch", Vector3.INF)
		if oc in ["hit", "block", "parry"] and p != Vector3.INF and _can_cut(true):
			var by := String(a.by)
			# (a spell landing is a burst of light: a lens 1 m from it is a white screen, so it is framed from 4.6 m)
			if bool(a.get("paired", false)):
				# a paired exchange (Download(7)): every other blade contact a close-up on the clash itself, else both
				# bodies round it; a hit then cuts to the struck girl's face
				_pc += 1
				var vs2 := String(a.get("vs", ""))
				var mid: Vector3 = (sim.d.chest(by) + sim.d.chest(vs2)) * 0.5
				var gapc := sim._flat(sim.d.pos(vs2) - sim.d.pos(by)).length()
				var flip := 1.0 if rng.randf() < 0.5 else -1.0
				var trav := absf(float(BodyMoves.entry(String(a.move)).get("travel", 0.0)))
				# (whole bodies only, 2026-10-20: both of them at the contact from the side or low, the struck girl's
				# recoil from the side)
				_cut("duo" if _pc % 2 == 0 else "profile", by, {"k": 1.0, "high": 0.2} if _pc % 2 == 0 else {}, 0.5, "%s %s" % [oc, a.move])
				if oc == "hit" and vs2 != "":
					sim.at(0.4, func():
						if sim.t >= float(sim.get("cine_hold")):
							_cut("profile", vs2, {}, 0.6, "reaction"))
				_quiet_since = sim.t
				return
			if bool(a.get("weapon", false)):
				# blade contact: close on the clash or the cut, then the struck girl's face (Download(7))
				_cut("duo", by, {"k": 1.0, "high": 0.2}, 0.5, "%s %s" % [oc, a.move])
				var vs := String(a.get("vs", ""))
				if oc == "hit" and vs != "":
					sim.at(0.45, func():
						if sim.t >= float(sim.get("cine_hold")):
							_cut("track", vs, {}, 0.6, "reaction"))      # (her recoil alongside her: the face close-up landed behind her hair)
				_quiet_since = sim.t
				return
			if bool(a.get("spell", false)):
				_cut("impact", by, {"at": p}, HIT_HOLD, "%s %s" % [oc, a.move])
				return
			_cut("hit_close", by, {"at": p, "flip": 1.0 if rng.randf() < 0.5 else -1.0}, HIT_HOLD, "%s %s" % [oc, a.move])
			return
	# 2 the events: windups, casts, dashes, falls
	while _ev_i < sim.events.size():
		var e: Array = sim.events[_ev_i]
		_ev_i += 1
		var kind := String(e[1])
		var who := String(e[2])
		match kind:
			"attack":
				if _can_cut():
					var k := _fresh(["profile", "ots", "face_ots"] if rng.randf() < 0.6 else ["ots", "profile", "wide_low"])
					# (a weapon windup: the side that shows both bodies and the blade's line; over the shoulder put the
					# other girl's hair over half the frame for a second, Selwyn's spar, 20 October)
					if String(MoveCatalog.CLIPS.get(String(e[3]), {}).get("cat", "")) == "weapon" or BodyMoves.has(String(e[3])):
						_weapon_windup(who, String(e[3]))
						continue
					var target_who := who if k != "face_ots" else String(sim.d.F[who].other)
					_cut(k, target_who, {}, 0.32, "windup " + String(e[3]))
			"spell", "cast":
				if _can_cut():
					_cut("hero_low", who, {}, 0.6, "gather " + String(e[3]))
					var caster := who
					# (the big forms, spires, a funnel from the sky, a tide, are framed wide at the release to show
					# their scale; the rest over her shoulder down the line of the spell)
					var sk := String(SpellBook.SPELLS.get(String(e[3]), {}).get("kind", ""))
					var wide := sk in ["pillars", "rows", "array", "sky", "seal", "meteor", "eclipse", "domain", "vortex", "wave"]
					sim.at(0.65, func():
						if sim.t >= float(sim.get("cine_hold")) and cur == "hero_low":
							if wide:
								_cut("wide_low", caster, {"k": 1.25, "high": 0.5, "min": 5.0}, 1.0, "release wide")
							elif sim.has_meta("weapon_play"):
								_cut("duo", caster, {"k": 1.1}, 0.7, "release")    # (both in frame: behind her looked at the back of a head)
							else:
								_cut("behind", caster, {}, 0.7, "release"))
			"rush":
				if _can_cut():
					_cut("track", who, {}, 0.6, "rush")
			"evade":
				if _can_cut(true):
					_cut("profile" if sim.has_meta("paired") else _fresh(["track", "wide_low"]), who, {}, 0.55, "evade " + String(e[3]))
			"travel":
				if _can_cut(true):
					_cut("crane", who, {}, 1.1, "travel " + String(e[3]))
			"knockdown":
				if _can_cut(true):
					_cut("crane", who, {}, 1.0, "knockdown")
			"defend":
				pass
	# 3 between exchanges: a wide that does not sit still for long
	var nmax := 1.0 if sim.has_meta("paired") else NEUTRAL_MAX
	if sim.t >= until and sim.t - since >= nmax:
		var k2 := _fresh(["duo", "wide_low", "orbit"])
		if sim.has_meta("weapon_play"):
			k2 = _fresh(["orbit", "profile", "orbit", "track"])      # (a weapon fight: both in frame, the lens always moving)
			if sim.has_meta("paired"):
				# (wide only to reset space: when they are far apart)
				var gap_n := sim._flat(sim.d.pos("mika") - sim.d.pos("luna")).length()
				k2 = "wide_low" if gap_n > 4.5 else _fresh(["two_mid", "orbit", "profile"])
		var o2 := {"k": rng.randf_range(0.9, 1.05), "high": rng.randf_range(0.0, 0.4), "min": 3.2}
		if k2 == "orbit":
			o2 = {"from": rng.randf_range(10.0, 40.0), "to": rng.randf_range(60.0, 100.0), "r": 4.6}
		_cut(k2, String(sim.S.keys()[rng.randi() % sim.S.size()]), o2, NEUTRAL_MAX, "neutral")
