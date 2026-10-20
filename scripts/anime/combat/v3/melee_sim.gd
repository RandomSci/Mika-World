class_name MeleeSim
extends Node
## Combat v3: a live close-combat fight between fighters on the procedural fight rig (MeleeFighter). Nothing is
## planned: every frame each fighter looks at the distance, what the other is doing, her stamina, the exchange so far,
## and picks an action. The rules (Sakurai / fighting-game frame data):
##   - an attack has a windup (0.06 - 0.15 s), an active part (the hit) and a recovery; the fist or foot is driven by
##     IK onto the other's real bone - or onto her forearm if she blocks - so contact is exact
##   - the defender reacts only after SEEING the windup, 0.10 - 0.20 s later, with an answer that matches the attack
##     (high: block on that side / cover / slip / duck / parry; low: jump or shin check; heavy: get out of the way);
##     sometimes she is late and eats it, sometimes she reads it and counters - that mix is the fight
##   - a hit freezes both of them 4 - 6 frames (the one hit shakes), a block 3; the camera kicks
##   - exchanges of 3 - 6 blows back and forth, a heavy kick or a knock-back separates them, they circle at range for
##     a moment, then one blinks back in (a 4 - 6 m dash in ~0.2 s with afterimages) straight into a strike
## Any number of fighters (teams): each picks the nearest opponent; the brain never names Mika or Luna.

const GRAVITY := 9.8

var d: FightDirector
var vfx: CombatVFX
var magic: MagicCaster                    # spells and conjured weapons (gesture -> gather at the hand -> release)
var ult_at := {}                          # id -> fight second her ultimate comes (opts "ult_at")
var ult_pick := {}                        # id -> which ultimate (opts "ult_pick"; else one of hers at random)
var rng := RandomNumberGenerator.new()
var F := {}                              # id -> MeleeFighter
var S := {}                              # id -> live state
var t := 0.0
var length := 15.0
var done := false
var mode := "close"
var mode_until := 0.0
var events: Array = []                   # [t, kind, who, detail]
var attacks: Array = []                  # every attack with its outcome, reaction delay and contact error (QA)
var action_starts: Array = []            # fight times any fighter began something (gaps between exchanges)
var exchanges := 0
var _blows := 0
var _target_blows := 4
var _sched: Array = []
var _checks: Array = []
var _next_cam := 0.0
var demo := false                        # a lab: no brain picks attacks, no footwork, no camera (the test drives it)
var footwork := false                    # (lab) footwork on even in demo

const PERSONA := {
	"mika": {"aggr": 0.62, "speed": 1.08, "kick": 0.8, "read": 0.22, "late": 0.12, "pref": 0.95},
	"luna": {"aggr": 0.5, "speed": 1.0, "kick": 1.25, "read": 0.32, "late": 0.1, "pref": 1.02},
}


static func make(director: FightDirector, opts := {}) -> MeleeSim:
	var s := MeleeSim.new()
	s.name = "MeleeSim"
	s.process_priority = -60                    # before the director places the bodies
	director.add_child(s)
	s._setup(director, opts)
	return s


func _setup(director: FightDirector, opts: Dictionary) -> void:
	d = director
	d.no_comic = true
	d.ARENA_R = 9.0
	rng.seed = int(opts.get("seed", 1))
	length = float(opts.get("length", 15.0))
	demo = bool(opts.get("demo", false))
	vfx = CombatVFX.make(d.main.world if d.main.get("world") else d.main)
	magic = MagicCaster.make(self)
	ult_at = opts.get("ult_at", {})
	ult_pick = opts.get("ult_pick", {})
	var teams: Dictionary = opts.get("teams", {"mika": 0, "luna": 1})
	var ids: Array = teams.keys()
	# (Selwyn 2026-10-20: a long range duel; --duel-melee keeps the old close start for the melee labs)
	var ranged: bool = not RenderProfile.options.has("duel-melee") and not opts.get("melee", false) and not opts.get("demo", false)
	var gap := float(opts.get("start_gap", 7.0 if ranged else 1.2))
	if ranged:
		mode = "range"
		mode_until = 0.6
	for i in ids.size():
		var id: String = ids[i]
		var sgn := -1.0 if i == 0 else 1.0
		d.F[id].pos = d.center + d.axis * gap * 0.5 * sgn
		d.F[id].yaw_k = 1.6
	set_process(false)
	for id in ids:
		var pz: Dictionary = PERSONA.get(id, PERSONA.mika)
		S[id] = {"id": id, "team": teams[id], "state": "free", "until": 0.0, "atk": {}, "def": {}, "threat": {}, "next_at": rng.randf_range(0.3, 0.8),
			"recent": [], "last_def": "", "hp": 100.0, "stam": 100.0, "glide": {}, "vel": Vector3.ZERO, "circ": 1.0 if rng.randf() < 0.5 else -1.0,
			"circ_until": 0.0, "pref": float(pz.pref), "p": pz.duplicate(), "counter": false, "air": false, "energy": 100.0}


var _hidden: Array = []

## The rune target boards of the training ground (their posts, discs and sigils) stand in every wide shot: hidden
## while they fight, shown again in teardown().
func _hide_props() -> void:
	var runes: Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if n is RuneReactive:
			runes.append((n as Node3D).global_position)
	if runes.is_empty():
		return
	for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.visible or not gi.is_inside_tree():
			continue
		var c := gi.global_transform * gi.get_aabb().get_center()
		for r in runes:
			if Vector2(c.x - r.x, c.z - r.z).length() < 0.75 and c.y < r.y + 0.8 and c.y > r.y - 1.6:
				gi.visible = false
				_hidden.append(gi)
				break


func start() -> void:
	SpellVFX.fight_glow(d.main, true)                # (only magic blooms while they fight)
	_hide_props()
	if not demo and RenderProfile.options.has("realm"):                # (opt in: Selwyn wants the surroundings left alone)
		realm = FightRealm.make(d)
	for id in S:
		F[id] = MeleeFighter.make(d, id)
	set_process(true)


func run() -> Dictionary:
	start()
	while not done:
		await get_tree().process_frame
	return result()


## The gesture director (LimboAI, one tree per girl): every spell and ultimate gesture goes through it.
var gestures: GestureDirector
## The cinematographer (FightCine): cuts timed to the fight; --old-fight-camera keeps the old follow shot.
var cine: FightCine
var cine_hold := 0.0
var ult_kit = null                        # the UltimateKit running now (its first hit gets the impact frames)
var _big_cine_t := -99.0                  # when a big spell last ran the kit's short form
## The duel's realm (FightRealm): the world turns into the realm of whoever pushes the fight with big magic.
var realm: FightRealm                      # fight time until which an ultimate's own cinematic owns the camera


func at(dt: float, fn: Callable) -> void:
	_sched.append([t + dt, fn])


# ------------------------------------------------------------------------------------------------ the frame
func _process(delta: float) -> void:
	var dt := delta
	t += dt
	var due: Array = []
	var keep: Array = []
	for e in _sched:
		if float(e[0]) <= t:
			due.append(e)
		else:
			keep.append(e)
	_sched = keep
	for e in due:
		(e[1] as Callable).call()
	for ch in _checks:
		(ch as Callable).call()
	_checks.clear()
	if gestures == null and magic and not S.is_empty() and not RenderProfile.options.has("no-gesture-director"):
		gestures = GestureDirector.make(self)
	if gestures:
		gestures.update(dt)
	for id in S:
		_track_limbs(id, dt)
		_tick(S[id], dt)
	for id in S:
		var f: MeleeFighter = F[id]
		var o := _target(S[id])
		if not o.is_empty():
			f.look_at = (F[o.id] as MeleeFighter).trace.get("Head", d.bone(o.id, "Head"))
		f.update(dt)
	if not demo:
		if cine == null and not RenderProfile.options.has("old-fight-camera"):
			cine = FightCine.make(self)
		if cine:
			cine.update()
		else:
			_camera()
	if t >= length and _quiet():
		done = true


## Each hand's / foot's velocity on her final pose (what a defender can read during a windup), smoothed.
var limb_vel := {}                        # "<id>:<limb>" -> Vector3 m/s
var _limb_last := {}


func _track_limbs(id: String, dt: float) -> void:
	if dt <= 0.0005:
		return
	var f: MeleeFighter = F[id]
	for limb in ["lh", "rh", "lf", "rf"]:
		var b := ("Left" if limb in ["lh", "lf"] else "Right") + ("Hand" if limb in ["lh", "rh"] else "Foot")
		var p: Vector3 = f.trace.get(b, Vector3.INF)
		if p == Vector3.INF:
			continue
		var key: String = id + ":" + String(limb)
		if _limb_last.has(key):
			limb_vel[key] = (limb_vel.get(key, Vector3.ZERO) as Vector3).lerp((p - (_limb_last[key] as Vector3)) / dt, 0.5)
		_limb_last[key] = p


func _quiet() -> bool:
	for id in S:
		if String(S[id].state) in ["attack", "dash"]:
			return false
	return true


func _target(s: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	for id in S:
		if S[id].team == s.team:
			continue
		var dd := _flat(d.pos(id) - d.pos(s.id)).length()
		if dd < bd:
			bd = dd
			best = S[id]
	return best


func _tick(s: Dictionary, dt: float) -> void:
	var o := _target(s)
	if o.is_empty():
		return
	var to_o := _flat(d.pos(o.id) - d.pos(s.id))
	var dist := to_o.length()
	var fwd := to_o / maxf(dist, 0.001)
	var side := fwd.cross(Vector3.UP)
	s.stam = minf(float(s.stam) + dt * 9.0, 100.0)
	# (her magic comes back: at range fast enough for a big spell every 2 to 3 s; up close slowly)
	s.energy = minf(float(s.get("energy", 100.0)) + dt * (8.0 if mode == "range" else 3.0), 100.0)
	# she sees a windup (only after it started, 0.10 - 0.20 s later)
	var th: Dictionary = s.threat
	if not th.is_empty() and not th.get("seen", false) and t >= float(th.perceive_at) and String(th.outcome) == "":
		if String(s.state) == "react" and float(s.until) - t < float(th.t_hit) - t - 0.06:
			s.state = "free"                         # she shakes off the stagger to answer what she sees coming
		if String(s.state) != "react":
			th.seen = true
			_respond(s, o, th)
	# a strike that falls short of her opponent carries her in (a lunge): the fist always arrives
	if String(s.state) == "attack" and String((s.atk as Dictionary).get("phase", "")) in ["wind", "active"]:
		_lunge(s, o, dt)
	match String(s.state):
		"free":
			if (demo and not footwork) or (magic and magic.performing(String(s.id))) or (gestures and gestures.busy(String(s.id))):
				pass                                      # (a gesture clip owns her body: no stepping under it)
			else:
				_footwork(s, o, dist, fwd, side, dt)
			if not demo and magic and magic.performing(String(s.id)):
				pass
			elif not demo and _ult_due(s, o):
				pass
			elif not demo and t >= float(s.next_at) and (String(o.state) != "down" or t >= float(o.until) - 0.45):   # (she may set off as the other rises)
				if mode == "close":
					if magic and rng.randf() < 0.12 * float(s.p.get("magic", 1.0)) and _cast_any(s, o, dist, true):
						pass
					else:
						_choose_attack(s, o, dist)
				elif mode == "range" and t >= mode_until:
					# (Selwyn 2026-10-20: the duel is mostly long range, powerful spells and creative escapes; close
					# exchanges are rare bursts, and the fight travels across the area)
					if _relocate_due():
						_relocate()
					elif magic and rng.randf() < 0.93 * float(s.p.get("magic", 1.0)) and _cast_any(s, o, dist, false):
						pass
					elif float(s.p.aggr) + rng.randf() * 0.4 > 0.85:
						_rush(s, o)
		"defend":
			if t >= float(s.until):
				s.state = "free"
				s.def = {}
		"react":
			if t >= float(s.until):
				s.state = "free"
				var rf: MeleeFighter = F[s.id]
				rf.vibrate = false
				if rf.move_tag.begins_with("react:"):
					rf.move_tag = ""
		"down":
			if t >= float(s.until):
				s.state = "free"
				var df_: MeleeFighter = F[s.id]
				df_.rig_w = 1.0
				if df_.move_tag.begins_with("react:"):
					df_.move_tag = ""
				d.anim(s.id, "combat_idle", 0.0, -1.0, 1.0, 0.2, true)
	# root motion: an eased glide (lunges, steps, dashes) plus a sliding velocity (knock-backs)
	var g: Dictionary = s.glide
	var wa: Dictionary = (s.atk as Dictionary).get("warp", {}) if s.atk is Dictionary else {}
	if not wa.is_empty() and t < float(s.atk.t_hit) and not o.is_empty():
		var dv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
		var want_w: Vector3 = d.clamp_arena(d.pos(o.id) - dv * float(wa.reach))
		if g.is_empty():
			if _flat(want_w - d.pos(s.id)).length() > 0.03:
				s.glide = {"from": d.pos(s.id), "to": want_w, "t": 0.0, "dur": maxf(float(s.atk.t_hit) - t, 0.05), "ease": "out"}
				g = s.glide
		else:
			g.to = want_w
	if not g.is_empty():
		g.t = float(g.t) + dt
		var u := clampf(float(g.t) / float(g.dur), 0.0, 1.0)
		var e := MeleeFighter.ease_k(u, String(g.ease))
		d.F[s.id].pos = (g.from as Vector3).lerp(g.to, e)
		if u >= 1.0:
			s.glide = {}
	var v: Vector3 = s.vel
	if v.length() > 0.001:
		d.F[s.id].pos = d.clamp_arena((d.F[s.id].pos as Vector3) + v * dt)
		s.vel = v.move_toward(Vector3.ZERO, 7.5 * dt)
	_separate()


func _separate() -> void:
	var ids := S.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = d.F[ids[i]]
			var b: Dictionary = d.F[ids[j]]
			var v := _flat((b.pos as Vector3) - (a.pos as Vector3))
			var l := v.length()
			var mind := 0.62
			# (a strike landing: close enough for the arm or leg to reach her, as fighters step in to hit)
			for x in [S[ids[i]], S[ids[j]]]:
				if String(x.state) == "attack" and (x.atk as Dictionary).has("warp"):
					mind = 0.4
			if l < mind and l > 0.0001:
				var push := v / l * (mind - l) * 0.5
				a.pos = (a.pos as Vector3) - push
				b.pos = (b.pos as Vector3) + push


## Never standing still: she holds her distance with small steps and circles, the direction changing now and then.
func _footwork(s: Dictionary, o: Dictionary, dist: float, fwd: Vector3, side: Vector3, dt: float) -> void:
	if not (s.glide as Dictionary).is_empty():
		return
	if t >= float(s.circ_until):
		s.circ = -float(s.circ) if rng.randf() < 0.6 else float(s.circ)
		s.circ_until = t + rng.randf_range(0.5, 1.3)
	var want: float = s.pref if mode == "close" else s.get("range_d", 5.5)
	var radial := clampf((dist - want) * 4.0, -1.4, 1.4) if mode == "close" else clampf((dist - want) * 4.0, -2.4, 2.4)
	var lat := float(s.circ) * (0.45 if mode == "close" else 1.8)
	var p: Vector3 = d.F[s.id].pos
	d.F[s.id].pos = d.clamp_arena(p + (fwd * radial + side * lat) * dt)


# ------------------------------------------------------------------------------------------------ attacking
func _choose_attack(s: Dictionary, o: Dictionary, dist: float) -> void:
	var names: Array = []
	var weights: Array = []
	var sep_due := _blows >= _target_blows
	var base := {"jab": 1.0, "cross": 0.9, "hook": 0.75, "uppercut": 0.45, "body_hook": 0.6, "front_kick": 0.35, "roundhouse": 0.32, "low_sweep": 0.22}
	for n in base:
		var m: Dictionary = MeleeBook.MOVES[n]
		var w := float(base[n])
		if m.limb in ["lf", "rf"]:
			if not RenderProfile.options.has("duel-kicks"):
				continue                             # (Selwyn 2026-10-20: no kicks in the duel)
			w *= float(s.p.kick)
		if m.get("separator", false):
			w *= 4.0 if sep_due else 0.5
		elif sep_due:
			w *= 0.5
		if String(o.last_def) == "duck" and n in ["uppercut", "body_hook"]:
			w *= 2.5
		if String(o.last_def) in ["cover", "block_high"] and n in ["body_hook", "low_sweep"]:
			w *= 2.0
		if String(o.last_def) == "jump" and n == "low_sweep":
			w *= 0.3
		if bool(s.counter) and n in ["cross", "hook", "uppercut", "body_hook"]:
			w *= 1.8
		var rec: Array = s.recent
		if rec.size() > 0 and rec[-1] == n:
			w *= 0.2
		if rec.size() > 1 and rec[-2] == n:
			w *= 0.55
		var r: Array = m.range
		if dist < float(r[0]) - 0.1 or dist > float(r[1]) + 0.35:
			w *= 0.05
		if float(s.stam) < 25.0 and m.weight == "heavy":
			w *= 0.2
		# motion matching: a move that starts from the pose she is in flows on, one that needs a reset is less likely
		w *= lerpf(0.35, 1.0, MotionMatch.weight(MotionMatch.move_cost(F[s.id], m)))
		names.append(n)
		weights.append(w)
	s.counter = false
	var pick := _weighted(names, weights)
	if pick != "":
		_act_strike(s, o, pick)


## A strike through her action player (one player for every mode: the catalog entry is its timing source, the
## procedural strike lands it). A move with no catalog entry strikes directly.
func _act_strike(s: Dictionary, o: Dictionary, pick: String) -> void:
	var e := String(ActionPlayer.FIGHT_MOVES.get(pick, ""))
	if e == "" or ActionPlayer.entry(e).is_empty() or RenderProfile.options.has("no-action-player"):
		_attack(s, o, pick)
		return
	ActionPlayer.of((F[s.id] as MeleeFighter).c).play(e, {"sim": self, "s": s, "o": o, "move": pick})


## Magic from where she stands (a stand-in until the fight brain, step e): one of her spells that fits the distance
## and her energy, not the one she just used; close in only her conjured blades. Then the range mode resumes after it.
func _cast_any(s: Dictionary, o: Dictionary, dist: float, close: bool) -> bool:
	var names: Array = []
	var ws: Array = []
	for n in SpellBook.spells_of(String(s.id)):
		var sp: Dictionary = SpellBook.SPELLS[n]
		if String(sp.kind) == "barrier" or not magic.can_cast(s, n, dist):
			continue
		if gestures and not gestures.hand_free(s, String(sp.clip)):
			continue                            # (her free hand casts while the other holds a weapon)
		if close != (String(sp.kind) == "weapon" and not sp.get("throw", false)):
			continue
		var w := gestures.taste(String(s.id), String(sp.clip)) if gestures else 1.0
		var rec: Array = s.recent
		if n in rec.slice(maxi(rec.size() - 4, 0)):
			w *= 0.1
		names.append(n)
		ws.append(w)
	var pick := _weighted(names, ws)
	if pick == "":
		return false
	if gestures:
		if gestures.busy(String(s.id)):
			return false
		var clip_id := String(SpellBook.SPELLS[pick].clip)
		if RenderProfile.options.has("no-action-player") or ActionPlayer.entry(clip_id).is_empty():
			if not gestures.request(s, o, pick):
				return false
		else:
			# through her action player: a blocked gesture clip is refused (its body scan failed), another is picked
			if not ActionPlayer.allowed(clip_id):
				return false
			ActionPlayer.of((F[s.id] as MeleeFighter).c).play(clip_id, {"sim": self, "s": s, "o": o, "spell": pick})
	else:
		magic.cast(s, o, pick)
	var g := GestureBook.of(String(SpellBook.SPELLS[pick].clip))
	s.next_at = t + GestureBook.length(g) + rng.randf_range(0.2, 0.6)
	for x in S.values():
		if x != s:
			x.next_at = maxf(float(x.next_at), t + rng.randf_range(0.6, 1.4))
	events.append([snappedf(t, 0.01), "spell", s.id, pick])
	return true


## Her ultimate (once a fight): when the fight's clock reaches her moment (opts "ult_at" {id: s}) or the other is low.
func _ult_due(s: Dictionary, o: Dictionary) -> bool:
	if bool(s.get("ult_done", false)) or String(o.state) == "down" or String(s.state) != "free":
		return false
	var due: float = float(ult_at.get(s.id, 9999.0))
	if t < due and float(o.hp) > 30.0:
		return false
	var mine := MoveCatalog.ultimates_of(String(s.id)).filter(func(u): return String(MoveCatalog.ULTIMATES[u].owner) == String(s.id))
	var u := String(ult_pick.get(s.id, mine[rng.randi() % mine.size()]))
	s.ult_done = true
	var L := UltimateCast.perform(self, String(s.id), String(o.id), u)
	s.next_at = t + L + 0.6
	for x in S.values():
		x.next_at = maxf(float(x.next_at), t + L + 0.4)
	events.append([snappedf(t, 0.01), "ultimate", s.id, u])
	return true


func _weighted(names: Array, weights: Array) -> String:
	var tot := 0.0
	for w in weights:
		tot += float(w)
	if tot <= 0.0:
		return ""
	var r := rng.randf() * tot
	for i in names.size():
		r -= float(weights[i])
		if r <= 0.0:
			return names[i]
	return names[-1]


## Mocap strikes (2026-10-20, Selwyn: the actions are "not smooth at all", the goal Download(7)): each MeleeBook move
## plays a real Move Library strike clip around one of its hits: [clip, contact time in the clip (s), the limb that lands
## there in the mocap, windup lead (s)]. Times are the action catalog's, checked by eye at 10 fps; the landing limb is
## read off the mocap (the fastest hand or foot at that hit). A blocked clip (failed body scan) or --procedural-strikes
## falls back to the key pose strike.
const STRIKE_CLIPS := {
	"jab": ["combo_jab_cross_hook", 0.68, "rh", 0.42], "cross": ["three_hit_combo", 1.12, "rh", 0.45],
	"hook": ["combo_jab_cross_hook", 1.62, "lh", 0.5], "body_hook": ["three_hit_combo", 1.85, "rh", 0.5],
	"uppercut": ["uppercut_launcher", 1.15, "lh", 0.5], "launcher": ["uppercut_launcher", 1.15, "lh", 0.55],
	"front_kick": ["front_kick", 1.33, "rf", 0.6], "roundhouse": ["jump_spin_kick", 1.5, "rf", 0.7],
	"low_sweep": ["low_sweep", 1.7, "rf", 0.65], "crescent_kick": ["crescent_kick", 1.5, "rf", 0.7],
	"axe_kick": ["axe_kick", 1.55, "rf", 0.7], "hook_kick": ["hook_kick", 1.9, "rf", 0.65],
	"spin_back_kick": ["spin_back_kick", 1.5, "rf", 0.7], "palm_strike": ["dash_palm_strike", 1.45, "lh", 0.6],
}
const STRIKE_AFTER := 0.5                 # s of the clip played after the contact (the follow through)


## One strike: key poses on her rig, the limb on a live contact point, the defender warned of the windup.
func _attack(s: Dictionary, o: Dictionary, name: String, pre := []) -> void:
	if pre.is_empty() and _mocap_strike(s, o, name):
		return
	var m: Dictionary = MeleeBook.MOVES[name]
	var f: MeleeFighter = F[s.id]
	f.move_tag = name
	(F[o.id] as MeleeFighter).move_tag = "facing:" + name
	var sp := float(s.p.speed) * rng.randf_range(0.92, 1.1)
	var wind := float(m.wind) / sp
	var act := float(m.active) / sp
	var rec := float(m.recover) / sp
	var pre_t := 0.0
	for sg in pre:
		pre_t += float(sg.dur)
	var limb: String = m.limb
	var surf := "fist"
	if m.has("surf"):
		surf = String(m.surf)
	elif limb in ["lf", "rf"]:
		surf = "ball" if name == "front_kick" else "shin"
	elif m.get("open", false):
		surf = "palm"
	var atk := {"name": name, "m": m, "by": s.id, "vs": o.id, "t0": t, "t_hit": t + pre_t + wind + act, "limb": limb, "surf": surf,
		"locked": Vector3.INF, "outcome": "", "contact": Vector3.INF, "dir": Vector3.ZERO, "phase": "wind", "react_delay": -1.0, "defence": ""}
	s.state = "attack"
	s.atk = atk
	s.stam = float(s.stam) - (14.0 if m.weight == "heavy" else 7.0)
	(s.recent as Array).append(name)
	if (s.recent as Array).size() > 4:
		(s.recent as Array).pop_front()
	_blows += 1
	action_starts.append(t)
	# the defender sees it 0.10 - 0.20 s after the windup starts
	o.threat = atk
	atk.perceive_at = t + rng.randf_range(0.10, 0.20)
	# she closes to the move's distance by the hit (a step in on the windup)
	var ko: float = (F[o.id] as MeleeFighter).k
	var dirv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	if pre.is_empty():
		var want: Vector3 = d.pos(o.id) - dirv * float(m.reach) * (f.k + ko) * 0.5
		if _flat(want - d.pos(s.id)).length() > 0.02:
			s.glide = {"from": d.pos(s.id), "to": d.clamp_arena(want), "t": 0.0, "dur": wind + act * 0.8, "ease": "inout"}
	f.palm[limb] = String(m.get("palm", "down")) if limb in ["lh", "rh"] else f.palm.get(limb, "guard")
	var fn := func() -> Vector3: return _limb_target(s, o, atk)
	var segs: Array = pre.duplicate()
	segs.append({"dur": wind, "ease": "inout", "pose": m.keys[0], "arc": m.get("wind_arc", {}), "start": func():
		atk.phase = "wind"
		if limb in ["lf", "rf"]:
			f.kick_support = "rf" if limb == "lf" else "lf"
			f._lift_hold = f.life_t + minf(0.1, wind * 0.5)})
	segs.append({"dur": act, "ease": "snap", "pose": m.keys[1], "dyn": {limb: fn}, "arc": m.get("arc", {}),
		"start": func(): _active(s, o, atk), "end": func(): _impact(s, o, atk)})
	segs.append({"dur": 0.04 / sp, "ease": "hold", "pose": m.keys[1], "dyn": {limb: fn}})
	segs.append({"dur": rec, "ease": "inout", "pose": m.get("recover_pose", {}), "arc": m.get("recover_arc", {}), "start": func():
		atk.phase = "recover"
		f.strike_limb = ""
		f.kick_support = ""
		f.palm[limb] = "guard",
		"end": func(): _attack_done(s, o, atk)})
	f.play(segs)
	events.append([snappedf(t, 0.01), "attack", s.id, name])


## The mocap version of a strike (STRIKE_CLIPS): the clip plays full body from its windup through the follow through,
## she closes the distance over the windup, and over the last 0.18 s before the contact the landing limb is steered by
## its IK onto the live point on the other girl, then released. The contact is judged on her real pose as always.
func _mocap_strike(s: Dictionary, o: Dictionary, name: String) -> bool:
	if RenderProfile.options.has("procedural-strikes") or not STRIKE_CLIPS.has(name):
		return false
	var spec: Array = STRIKE_CLIPS[name]
	var clip := String(spec[0])
	var f: MeleeFighter = F[s.id]
	var e := ActionPlayer.entry(clip)
	if not e.is_empty() and not ActionPlayer.allowed(clip):
		return false
	if not f.c.has_clip("ml_" + clip):
		return false
	var m: Dictionary = (MeleeBook.MOVES[name] as Dictionary).duplicate()
	var limb := String(spec[2])
	m.limb = limb
	var c_t := float(spec[1])
	var from := maxf(c_t - float(spec[3]), float(e.get("start_s", 0.0)) if not e.is_empty() else 0.0)
	var L_clip := FightDeck.clip_length(f.c, "ml_" + clip)
	var to := minf(c_t + STRIKE_AFTER, L_clip)
	var spd := clampf(float(s.p.speed), 0.9, 1.12) * rng.randf_range(0.96, 1.04)
	var wind := (c_t - from) / spd
	var total := (to - from) / spd
	f.move_tag = name
	(F[o.id] as MeleeFighter).move_tag = "facing:" + name
	var surf := "ball" if name == "front_kick" else ("shin" if limb in ["lf", "rf"] else ("palm" if m.get("open", false) or name == "palm_strike" else "fist"))
	var atk := {"name": name, "m": m, "by": s.id, "vs": o.id, "t0": t, "t_hit": t + wind, "limb": limb, "surf": surf,
		"locked": Vector3.INF, "outcome": "", "contact": Vector3.INF, "dir": Vector3.ZERO, "phase": "wind", "react_delay": -1.0, "defence": "",
		"clip": clip}
	s.state = "attack"
	s.atk = atk
	s.stam = float(s.stam) - (14.0 if m.weight == "heavy" else 7.0)
	(s.recent as Array).append(name)
	if (s.recent as Array).size() > 4:
		(s.recent as Array).pop_front()
	_blows += 1
	action_starts.append(t)
	o.threat = atk
	atk.perceive_at = t + rng.randf_range(0.10, 0.20)
	# she closes to where the mocap body's own fist / foot reaches at the contact (measured on the clip itself, her
	# skeleton): the procedural reach left the target 20 to 40 cm out of the arm's reach
	var dirv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	var cr := _clip_reach(f, clip, c_t, limb)
	# the source actor is rarely square to the camera: she turns so the clip's own strike line points at the other girl
	# (the strike's end at the contact lies at this angle to her left of her facing), then closes to its full reach
	var aim := atan2(float(cr.y), float(cr.x))
	d.F[s.id].yaw_extra = -aim
	var want: Vector3 = d.pos(o.id) - dirv * (maxf(cr.length(), 0.25) + 0.06)
	if _flat(want - d.pos(s.id)).length() > 0.02:
		s.glide = {"from": d.pos(s.id), "to": d.clamp_arena(want), "t": 0.0, "dur": wind * 0.9, "ease": "inout"}
	# motion warping: until the contact, her glide's end and her aim follow where the other girl really is now
	# (a punch filmed facing the camera loses its depth in the mocap: the arm barely reaches forward, so the arm IK
	# throws it; her body stands where the arm, extended, lands on her)
	var arm_strike := limb in ["lh", "rh"]
	var reach_w := maxf(cr.length(), 0.25) + 0.06
	if arm_strike:
		reach_w = maxf(reach_w, f.limb_len(limb) * 0.72 + 0.1 * f.k)
	atk.warp = {"reach": reach_w, "aim": aim}
	# the body: the clip, the rig steps back (her feet planted where the clip leaves them at the end)
	d.anim(s.id, "ml_" + clip, from, to, spd, 0.1)
	f.rig_w = 0.0
	f.upper_clip = 0.0
	f.play([{"dur": total, "ease": "hold", "pose": {}}])
	if limb in ["lh", "rh"]:
		f.palm[limb] = String(m.get("palm", "down"))
	var lead := 0.3 if arm_strike else 0.18
	f.steer_limb(limb, func() -> Vector3: return _limb_target(s, o, atk), d.ft + wind - lead, d.ft + wind - 0.03, d.ft + wind + 0.12)
	at(maxf(wind - 0.14, 0.0), func():
		if String(atk.outcome) == "" and s.atk == atk:
			_limb_target(s, o, atk)
			_active(s, o, atk))
	at(wind, func():
		if s.atk == atk:
			_impact(s, o, atk))
	at(total, func():
		f.steer_limb("", Callable(), 0.0, 0.0, 0.0)
		d.F[s.id].yaw_extra = 0.0
		if f.move_tag == name:
			f.move_tag = ""
		f.strike_limb = ""
		if f.rig_w < 0.5 and String(s.state) != "down":
			f.replant()
			f.rig_w = 1.0
			d.stance(s.id, 0.2)
		_attack_done(s, o, atk))
	events.append([snappedf(t, 0.01), "attack", s.id, name])
	return true


## How far in front of her root (forward, metres) and to her left the landing limb's end is at clip time t, on her own
## skeleton (the deck freezes the clip's hips over the ground at its first frame, so the hips' own travel counts).
var _reach_cache := {}


func _clip_reach(f: MeleeFighter, clip: String, t_c: float, limb: String) -> Vector2:
	var key := "%s|%s|%.2f|%s" % [f.id, clip, t_c, limb]
	if _reach_cache.has(key):
		return _reach_cache[key]
	var a := FightDeck.anim_for(f.c, "ml_" + clip)
	var out := Vector2(0.55 * f.k, 0.0)
	if a:
		var ps := PoseSkel.from(f.sk)
		JointAudit.pose_at(ps, a, 0.0)
		var h0: Vector3 = ps.get_bone_global_pose(ps.find_bone("Hips")).origin
		JointAudit.pose_at(ps, a, t_c)
		var ht: Vector3 = ps.get_bone_global_pose(ps.find_bone("Hips")).origin
		var end_b := ("Left" if limb in ["lh", "lf"] else "Right") + ("Hand" if limb in ["lh", "rh"] else "Foot")
		var e: Vector3 = ps.get_bone_global_pose(ps.find_bone(end_b)).origin - Vector3(ht.x - h0.x, 0.0, ht.z - h0.z)
		var sc := f.sk.global_transform.basis.get_scale().x
		out = Vector2(e.z * sc, e.x * sc)                 # (skeleton +Z faces the other girl, +X her left)
	_reach_cache[key] = out
	print("[strike] %s %s at %.2f: %s reaches %.2f m ahead, %.2f m to the side" % [f.id, clip, t_c, limb, out.x, out.y])
	return out


## A kick's aim one step lower down her body (when the higher point is out of the leg's reach).
const AIM_DOWN := {"crown": "face", "face": "chin", "temple_l": "chin", "temple_r": "chin", "chin": "chest", "chest": "stomach"}


## Where her wrist / ankle goes during the strike (world): the live point on the other girl, her forearm if she is
## blocking, or - once she got out of the way - the empty air where she was.
func _limb_target(s: Dictionary, o: Dictionary, atk: Dictionary) -> Vector3:
	var f: MeleeFighter = F[s.id]
	var of: MeleeFighter = F[o.id]
	var limb: String = atk.limb
	var src_b := "LeftUpperArm" if limb == "lh" else ("RightUpperArm" if limb == "rh" else ("LeftUpperLeg" if limb == "lf" else "RightUpperLeg"))
	var src: Vector3 = f.trace.get(src_b, d.bone(s.id, src_b))
	var contact: Vector3
	var df: Dictionary = o.def
	var m: Dictionary = atk.m
	if atk.locked != Vector3.INF:
		contact = atk.locked
	elif not df.is_empty() and df.get("atk") == atk and bool(df.get("read_ok", true)) and String(df.get("arm", "")) != "" and String(m.height) in (MeleeBook.GUARDS[df.kind].vs as Array):
		contact = of.forearm_point(String(df.arm), src)
	elif not df.is_empty() and df.get("atk") == atk and String(df.kind) == "check" and String(m.height) == "low":
		contact = of.surface("lf", "shin")
	else:
		contact = of.target_point(String(m.aim), src)
		# a kick lands on what her leg can reach from where she stands: a head too high for this range takes the
		# heel / ball on the face, the jaw, the chest instead (up on her toes she gains 7 cm)
		if limb in ["lf", "rf"] and atk.locked == Vector3.INF:
			var lmax := f.limb_len(limb) * 0.99 + (0.1 * f.k if String(atk.surf) == "ball" else 0.03 * f.k)
			var hjr: Vector3 = src + Vector3(0, 0.07 * f.k, 0)
			var aim := String(m.aim)
			var tries := 0
			while hjr.distance_to(contact) > lmax and AIM_DOWN.has(aim) and aim != "chest" and tries < 3:
				aim = AIM_DOWN[aim]
				contact = of.target_point(aim, src)
				tries += 1
	atk.contact = contact
	f.land_at[limb] = contact
	var dir := (contact - src).normalized()
	atk.dir = dir
	var L := 0.0
	match String(atk.surf):
		"fist":
			L = 0.095 * f.k
		"palm":
			L = 0.06 * f.k
		"ball":
			L = 0.12 * f.k
		"shin", "heel":
			L = 0.0
	# the striking surface sits where the final pose really puts it from the wrist / ankle (measured last frame),
	# so the knuckles - not the wrist - end on the contact point
	var end_b := ("Left" if limb in ["lh", "lf"] else "Right") + ("Hand" if limb in ["lh", "rh"] else "Foot")
	var end_now: Vector3 = f.trace.get(end_b, Vector3.ZERO)
	var surf_now := f.surface(limb, String(atk.surf))
	var off := surf_now - end_now
	if String(atk.phase) != "wind" and end_now != Vector3.ZERO and off.length() < 0.25 * f.k and off.length() > 0.001:
		if limb in ["lh", "rh"]:
			# the knuckles / palm turn with the forearm: last frame's offset from the wrist, turned from where the
			# forearm pointed then (elbow -> wrist) to where it will point now (elbow -> contact; the elbow moves
			# little from one frame to the next) - however the arm folds to get there
			var elbow: Vector3 = f.trace.get(("Left" if limb == "lh" else "Right") + "LowerArm", Vector3.ZERO)
			if elbow != Vector3.ZERO and elbow.distance_to(contact) > off.length() * 1.5 and elbow.distance_to(end_now) > 0.05:
				var fa0 := (end_now - elbow).normalized()
				var fa1 := (contact - elbow).normalized()
				var off1 := off
				if fa0.dot(fa1) < 0.9999:
					off1 = Quaternion(fa0, fa1) * off
				return contact - off1
		return contact - off                         # (the knuckles / palm / shin / heel / ball land, wherever they sit off the wrist or ankle)
	return contact - dir * L


## Every big hit (Selwyn 2026-10-20, FX_Cinematic_v1): the impact starburst at the contact, 1 to 1.5 m, played fast.
func big_hit_fx(at: Vector3, power: float) -> void:
	FlipbookFX.play(d.main, "fx_impact_starburst", func() -> Vector3: return at, {"size": lerpf(1.0, 1.5, clampf(power, 0.0, 1.0)), "f0": 4.0,
		"f1": 63.0, "dur": 0.6, "fade_in": 0.02, "fade_out": 0.25, "intensity": 1.5, "light": 3.0, "black_cut": 0.16})


func _lunge(s: Dictionary, o: Dictionary, dt: float) -> void:
	var atk: Dictionary = s.atk
	if atk.contact == Vector3.INF or atk.locked != Vector3.INF:
		return
	var f: MeleeFighter = F[s.id]
	var limb: String = atk.limb
	var root_b := "LeftUpperArm" if limb == "lh" else ("RightUpperArm" if limb == "rh" else ("LeftUpperLeg" if limb == "lf" else "RightUpperLeg"))
	var root: Vector3 = f.trace.get(root_b, d.pos(s.id))
	var L: float = float({"fist": 0.095, "palm": 0.06, "ball": 0.12, "shin": 0.0, "heel": 0.0}.get(String(atk.surf), 0.0)) * f.k
	var short := root.distance_to(atk.contact) - (f.limb_len(limb) * 0.96 + float(L))
	var cramped := root.distance_to(atk.contact) - (f.limb_len(limb) * 0.6 + float(L))
	if cramped < 0.0:
		# too close to throw it: she gives a little ground on the windup
		var back := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
		d.F[s.id].pos = (d.F[s.id].pos as Vector3) - back * minf(-cramped, 3.0 * dt)
	elif short > 0.0:
		var dirv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
		var step := minf(short, 4.5 * dt)
		d.F[s.id].pos = (d.F[s.id].pos as Vector3) + dirv * step
		if step > 2.5 * dt:
			f.skim(0.12)                             # (a fast lunge: the feet skim in with her)
		if not (s.glide as Dictionary).is_empty():
			s.glide.to = (s.glide.to as Vector3) + dirv * step


func _active(s: Dictionary, o: Dictionary, atk: Dictionary) -> void:
	atk.phase = "active"
	var f: MeleeFighter = F[s.id]
	f.strike_limb = atk.limb
	var limb: String = atk.limb
	var side := "Left" if limb in ["lh", "lf"] else "Right"
	var arm := limb in ["lh", "rh"]
	var a_b := side + ("LowerArm" if arm else "LowerLeg")
	var b_b := ("fist_" + side) if arm else (side + "Foot")
	var src := func() -> Array:
		var a: Vector3 = f.trace.get(a_b, Vector3.ZERO)
		var b: Vector3 = f.trace.get(b_b, a)
		return [a, b]
	var heavy: bool = atk.m.weight == "heavy"
	vfx.trail(src, s.id, (float(atk.t_hit) - t) + 0.05, 1.5 if heavy else 1.1, 0.6 if arm else 0.4)


## The moment of contact: was it blocked, dodged, parried - or did it land?
func _impact(s: Dictionary, o: Dictionary, atk: Dictionary) -> void:
	if String(atk.outcome) != "":
		return
	var m: Dictionary = atk.m
	var df: Dictionary = o.def if (String(o.state) == "defend" and o.def.get("atk") == atk) else {}
	# what the striking limb really touches (capsules on the final pose): her guard's forearm is a block, any other
	# part of her a hit (its zone picks the reaction), nothing at all a miss (she got out of the way, or it fell short)
	var ct := BodyAwareness.contact(F[s.id], String(atk.limb), F[o.id])
	var outcome := "hit"
	if not df.is_empty() and MeleeBook.GUARDS[df.kind].get("parry", false) and t >= float(df.ready) - 0.02:
		outcome = "parry"
	elif ct.is_empty():
		outcome = "miss"
	elif String(ct.part).begins_with("forearm") and not df.is_empty() and not MeleeBook.GUARDS[df.kind].get("evade", false):
		outcome = "block"
	atk.outcome = outcome
	atk.zone = String(ct.get("zone", ""))
	atk.part = String(ct.get("part", ""))
	atk.touch = ct.get("point", atk.contact)              # (where the capsules met: the sparks go there)
	o.threat = {}
	var power: float = {"light": 0.5, "medium": 0.72, "heavy": 1.0}.get(String(m.weight), 0.6)
	var dir: Vector3 = atk.dir if atk.dir != Vector3.ZERO else _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	var flat_dir := _flat(dir).normalized()
	var of: MeleeFighter = F[o.id]
	var contact: Vector3 = atk.touch
	match outcome:
		"hit":
			o.hp = float(o.hp) - float(m.dmg)
			of.vibrate = true
			d.impact(power, false)
			d.shake(0.35 + power * 0.55)
			vfx.impact(contact, dir, s.id, power, "hit")
			if power >= 0.9 or atk.has("weapon"):
				big_hit_fx(contact, power)
			d.face_fx(o.id, "hurt", 1.0, 0.5)
			_interrupt(o)
			# the receiver sells it: zone x strength (HitReactions), partial physics on the struck part, hair whip
			atk.reaction = HitReactions.hit(self, o, String(atk.zone) if String(atk.zone) != "" else "chest", dir, power, m)
			s.counter = false
			s.next_at = t + float(atk.m.recover) * 0.6 + (rng.randf_range(0.0, 0.08) if rng.randf() < 0.55 else rng.randf_range(0.2, 0.35))
		"block":
			d.impact(0.28 if power < 0.9 else 0.5, false)
			d.shake(0.22 + power * 0.3)
			vfx.impact(contact, dir, s.id, power, "block")
			atk.reaction = HitReactions.block(self, o, dir, power, m, String(df.get("arm", "both")))
			if String(atk.reaction) != "guard_break":
				o.until = t + 0.12 + power * 0.08
			o.last_def = df.kind
			if rng.randf() < 0.55:
				o.counter = true
				o.next_at = float(o.until) + rng.randf_range(0.02, 0.1)
			s.next_at = t + float(atk.m.recover) + rng.randf_range(0.05, 0.2)
		"miss":
			o.last_def = String(df.get("kind", ""))
			if rng.randf() < 0.65:
				o.counter = true
				o.next_at = t + rng.randf_range(0.02, 0.1)
			s.next_at = t + float(atk.m.recover) + rng.randf_range(0.1, 0.25)
		"parry":
			var wrist: Vector3 = (F[s.id] as MeleeFighter).trace.get(("Left" if atk.limb == "lh" else "Right") + "Hand", contact)
			vfx.impact(wrist, dir, o.id, 0.7, "parry")
			d.impact(0.5, false)
			d.shake(0.4)
			(F[s.id] as MeleeFighter).react(-dir.cross(Vector3.UP), "high", 0.45)
			o.last_def = "parry"
			o.counter = true
			o.next_at = t + 0.05
			at(0.0, func():
				s.state = "react"
				s.until = t + 0.32
				(F[s.id] as MeleeFighter).play([{"dur": 0.3, "ease": "out", "pose": {"hip_rot": Vector3(-2, 10, 0), "spine": Vector3(-6, 40, 0)}}, {"dur": 0.16, "ease": "inout", "pose": {}}]))
	attacks.append({"t": snappedf(float(atk.t0), 0.01), "by": s.id, "move": atk.name, "outcome": outcome, "defence": atk.defence, "part": atk.part, "zone": atk.zone, "reaction": String(atk.get("reaction", "")),
		"react_delay": snappedf(float(atk.react_delay), 0.001), "frame": Engine.get_frames_drawn(), "err": -1.0,
		"touch": atk.get("touch", Vector3.INF), "vs": atk.get("vs", ""), "limb": atk.get("limb", "")})
	var rec_i := attacks.size() - 1
	print("[melee] %s %s by %s at %.2f s at frame %d (defence %s, seen after %.2f s)" % [outcome.to_upper(), atk.name, s.id, t, Engine.get_frames_drawn(), atk.defence, float(atk.react_delay)])
	if outcome in ["hit", "block"]:
		# how far the fist / foot really is from the point it landed on (the final pose, next frame)
		_checks.append(func():
			var af: MeleeFighter = F[s.id]
			var surf: Vector3 = af.surface(atk.limb, atk.surf)
			# (a strike locked on the air she left measures nothing: where it touched her is the capsules' business)
			attacks[rec_i].err = snappedf(surf.distance_to(atk.contact), 0.001) if atk.locked == Vector3.INF and atk.contact != Vector3.INF else -1.0
			if float(attacks[rec_i].err) > 0.09:
				var sd0 := "Left" if atk.limb in ["lh", "lf"] else "Right"
				print("[melee] DBG miss %s: surf %s contact %s wrist %s ik %s phase %s" % [atk.name, str(surf.snappedf(0.001)), str((atk.contact as Vector3).snappedf(0.001)),
					str((af.trace.get(sd0 + ("Hand" if atk.limb in ["lh", "rh"] else "Foot"), Vector3.ZERO) as Vector3).snappedf(0.001)), str(af.ik_target(atk.limb).snappedf(0.001)), atk.phase])
			var sd := "Left" if atk.limb in ["lh", "lf"] else "Right"
			var arm: bool = atk.limb in ["lh", "rh"]
			var root_b := sd + ("UpperArm" if arm else "UpperLeg")
			var end_b := sd + ("Hand" if arm else "Foot")
			var tgt: Vector3 = af.ik_target(atk.limb)
			var rootp: Vector3 = af.trace.get(root_b, Vector3.ZERO)
			attacks[rec_i]["diag"] = {"end_to_ik": snappedf((af.trace.get(end_b, Vector3.ZERO) as Vector3).distance_to(tgt), 0.001),
				"root_to_ik": snappedf(rootp.distance_to(tgt), 0.001), "limb_len": snappedf(af.limb_len(atk.limb), 0.001),
				"ik_to_contact": snappedf(tgt.distance_to(atk.contact), 0.001), "dist": snappedf(_flat(d.pos(o.id) - d.pos(s.id)).length(), 0.01)})
	if m.get("separator", false) and outcome in ["hit", "block"] and not demo:
		_separation(s, o)


func _attack_done(s: Dictionary, o: Dictionary, atk: Dictionary) -> void:
	if String(s.state) == "attack" and s.atk == atk:
		s.state = "free"
		s.atk = {}
	if String(atk.outcome) == "":
		atk.outcome = "cancelled"


## Her attack is broken off (she was hit first).
func _interrupt(s: Dictionary) -> void:
	if magic and magic.performing(String(s.id)):
		magic.abort(String(s.id))                 # (a blow breaks her gesture: the clip stops, the charge fizzles)
	var fi: MeleeFighter = F[s.id]
	if fi.steering():
		fi.steer_limb("", Callable(), 0.0, 0.0, 0.0)  # (a mocap strike broken off: the rig takes her back for the reaction)
		d.F[s.id].yaw_extra = 0.0
		fi.replant()
		fi.rig_w = 1.0
	if String(s.state) == "attack":
		var atk: Dictionary = s.atk
		atk.outcome = "interrupted"
		var o := _target(s)
		if not o.is_empty() and o.threat == atk:
			o.threat = {}
		s.atk = {}
	s.def = {}
	(F[s.id] as MeleeFighter).strike_limb = ""
	(F[s.id] as MeleeFighter).kick_support = ""
	(F[s.id] as MeleeFighter).palm = {"lh": "guard", "rh": "guard"}
	(F[s.id] as MeleeFighter).play([{"dur": 0.12, "ease": "out", "pose": {"hip": Vector3(0, -0.12, -0.06), "spine": Vector3(-8, 10, 0)}}, {"dur": 0.2, "ease": "inout", "pose": {}}])


func _knockdown(o: Dictionary, dir: Vector3) -> void:
	o.state = "down"
	var f: MeleeFighter = F[o.id]
	f.rig_w = 0.0
	f.move_tag = "react:knockdown"
	var c: WorldCharacter = f.c
	var L := FightDeck.clip_length(c, "ml_knockdown_getup")
	var dur := d.anim(o.id, "ml_knockdown_getup", 0.08 * L, 0.92 * L, 2.3, 0.05)
	o.until = t + dur
	# the rig takes her back while she is still rising, knees bent (the clip ends standing straight-legged):
	# feet planted under her where she is now, her guard up as she comes up
	at(maxf(dur - 0.3, 0.1), func():
		if String(o.state) == "down":
			f.replant()
			f.rig_w = 1.0)
	# while she is down the other gives ground and comes back in as she rises (a rush), never stands over her
	mode = "range"
	mode_until = t + dur * 0.55                   # (she rushes back in while the other is still rising)
	_blows = 0
	for x in S.values():
		if x != o:
			x.range_d = rng.randf_range(4.0, 5.2)
			x.next_at = mode_until
	o.vel = dir * 3.0
	at(0.35, func(): vfx.dust(d.pos(o.id), dir, 18, 1.0))
	events.append([snappedf(t, 0.01), "knockdown", o.id, ""])


# ------------------------------------------------------------------------------------------------ defending
## She saw the windup: pick the answer that fits the attack, if there is still time for it.
func _respond(s: Dictionary, o: Dictionary, atk: Dictionary) -> void:
	if String(atk.outcome) != "":
		return
	if String(s.state) in ["react", "down", "dash"]:
		return
	if String(s.state) == "attack":
		var mine: Dictionary = s.atk
		if String(mine.get("phase", "")) == "wind" and rng.randf() < 0.55:
			_interrupt(s)                            # she aborts her windup to defend
		else:
			return
	atk.react_delay = t - float(atk.t0)
	if t < float(s.get("guard_broken_until", 0.0)):
		atk.defence = "guard_broken"                 # (her guard was just broken: she cannot answer this one)
		return
	if rng.randf() < float(s.p.late):
		atk.defence = "late"
		return
	if atk.has("spell"):
		_respond_spell(s, o, atk)
		return
	var m: Dictionary = atk.m
	var left := float(atk.t_hit) - t
	# she reads the strike off the attacker's real limb: where the striking hand / foot is and how it moves, plus where
	# the hips and shoulders aim it (a good reader trusts the aim more; a poor one the moving limb, and guesses wrong)
	var af: MeleeFighter = F[o.id]
	var vf: MeleeFighter = F[s.id]
	var pr := BodyAwareness.predict(af, String(atk.limb), vf, left, limb_vel.get(o.id + ":" + String(atk.limb), Vector3.ZERO))
	var aim_p: Vector3 = vf.target_point(String(m.aim), af.trace.get("Chest", d.pos(o.id)))
	var w_aim := clampf(0.35 + float(s.p.read) * 0.6 + rng.randf_range(-0.15, 0.15), 0.0, 1.0)
	var guess: Vector3 = (pr.point as Vector3).lerp(aim_p, w_aim)
	var hd: Vector3 = vf.trace.get("Head", guess)
	var ch: Vector3 = vf.trace.get("Chest", guess)
	var hp: Vector3 = vf.trace.get("Hips", guess)
	var h := "mid"
	if guess.y > (hd.y + ch.y) * 0.5:
		h = "high"
	elif guess.y < hp.y - 0.05 * vf.k:
		h = "low"
	var bs: Basis = vf.trace.get("basis", vf.sk.global_transform.basis)
	var lateral := (guess - ch).dot((bs * Vector3(1, 0, 0)).normalized())
	var from := "C"
	if lateral > 0.12 * vf.k:
		from = "L"
	elif lateral < -0.12 * vf.k:
		from = "R"
	atk.read = {"height": h, "from": from, "true_height": String(m.height), "true_from": String(m.from)}
	var read := rng.randf() < float(s.p.read)
	var opts := {}
	if h == "high":
		if from == "C":
			if atk.name == "uppercut":
				opts = {"backstep": 0.5, "cover": 0.5}
			else:
				opts = {"cover": 0.35, "slip": 0.3, "duck": 0.15, "backstep": 0.08}
				if read:
					opts["parry"] = 0.6
		else:
			opts = {"block_high": 0.55, "duck": 0.35, "backstep": 0.1}
	elif h == "mid":
		if m.weight == "heavy":
			opts = {"backstep": 0.5, "sidestep": 0.4, "block_mid": 0.1}
		else:
			opts = {"block_mid": 0.65, "backstep": 0.35}
	else:
		opts = {"jump": 0.6, "check": 0.4}
	var names: Array = []
	var ws: Array = []
	for kname in opts:
		var gname: String = "backstep" if kname == "sidestep" else kname
		var g: Dictionary = MeleeBook.GUARDS[gname]
		if float(g.rise) <= left + 0.03:
			names.append(kname)
			ws.append(float(opts[kname]))
	var pick := _weighted(names, ws)
	if pick == "":
		atk.defence = "too_late"
		return
	_defend(s, o, pick, atk)


## A spell coming: she answers what she reads - over spikes and waves (a jump), out of a bolt's or a beam's line (a
## sidestep, a step back), a barrier from her hands, or under a high one (a duck); the dodge starts when she SEES the
## release (it flies at where she stands then), a barrier can go up early.
func _respond_spell(s: Dictionary, o: Dictionary, atk: Dictionary) -> void:
	var sp: Dictionary = atk.spell
	var kind := String(sp.kind)
	var opts := {}
	match kind:
		"spikes", "wave":
			opts = {"jump": 0.65, "sidestep": 0.25, "barrier": 0.1}
		"beam":
			opts = {"sidestep": 0.55, "barrier": 0.45}
		"weapon":
			opts = {"cover": 0.35, "block_mid": 0.25, "backstep": 0.4} if not sp.get("throw", false) else {"sidestep": 0.6, "barrier": 0.4}
		_:
			opts = {"sidestep": 0.45, "backstep": 0.15, "barrier": 0.25, "duck": 0.15 if String(sp.get("height", "mid")) == "high" else 0.0}
	if float(s.get("energy", 0.0)) < float(SpellBook.SPELLS[SpellBook.barrier_of(String(s.id))].energy):
		opts.erase("barrier")
	opts["barrier"] = float(opts.get("barrier", 0.0)) * float(s.p.get("magic", 1.0))
	var names: Array = []
	var ws: Array = []
	for k in opts:
		if float(opts[k]) > 0.0:
			names.append(k)
			ws.append(float(opts[k]))
	var pick := _weighted(names, ws)
	if pick == "":
		atk.defence = "too_late"
		return
	atk.defence = pick
	var t_rel := float(atk.get("t_release", float(atk.t0) + 0.14 + float(sp.get("gather", 0.2)) + 0.09))   # when it leaves her
	if pick == "barrier":
		var wait_b := maxf(float(atk.t_hit) - t - 0.55, 0.0) if kind != "weapon" else 0.0
		at(wait_b, func():
			if String(atk.outcome) == "" and String(s.state) in ["free", "defend"]:
				magic.cast(s, o, SpellBook.barrier_of(String(s.id))))
		return
	var wait := maxf(t_rel - t, 0.0) + rng.randf_range(0.04, 0.11)
	if kind == "weapon" and not sp.get("throw", false):
		wait = maxf(t_rel - t, 0.0)
	at(wait, func():
		if String(atk.outcome) == "" and String(s.state) in ["free", "defend"]:
			_defend(s, o, pick, atk))


func _defend(s: Dictionary, o: Dictionary, kind: String, atk: Dictionary) -> void:
	var gname := "backstep" if kind == "sidestep" else kind
	var g: Dictionary = MeleeBook.GUARDS[gname]
	var f: MeleeFighter = F[s.id]
	f.move_tag = "guard:" + kind
	var m: Dictionary = atk.m
	var pose: Dictionary = (g.pose as Dictionary).duplicate()
	var arm := ""
	var sgn := 1.0
	var rd: Dictionary = atk.get("read", {})
	var from := String(rd.get("from", m.from))              # (the side SHE read it coming from)
	if from == "R":
		sgn = -1.0
	elif from == "C":
		sgn = 1.0 if rng.randf() < 0.5 else -1.0
	match String(g.get("arm", "")):
		"side":
			arm = "lh" if sgn > 0.0 else "rh"
			var other := "rh" if arm == "lh" else "lh"
			var aa: Vector3 = g.arm_at
			var oa: Vector3 = g.other_at
			pose[arm] = Vector3(aa.x * sgn, aa.y, aa.z)
			pose[other] = Vector3(-oa.x * sgn, oa.y, oa.z)
			var ap: Vector3 = g.arm_pole
			pose["lp" if arm == "lh" else "rp"] = Vector3(ap.x * sgn, ap.y, ap.z)
		"both":
			arm = "lh" if sgn > 0.0 else "rh"
		"lead":
			arm = "lh"
	if g.get("side_pose", false):
		for key in ["hip", "hip_rot", "spine", "head"]:
			if pose.has(key):
				var v: Vector3 = pose[key]
				pose[key] = Vector3(v.x * (sgn if key == "hip" else 1.0), v.y, v.z * sgn) if key != "hip" else Vector3(v.x * sgn, v.y, v.z)
	var rise := float(g.rise)
	var hold := maxf(float(atk.t_hit) - (t + rise), 0.0) + 0.08
	s.state = "defend"
	# a read on the wrong side or height leaves her guard where the blow is not (it lands on her instead)
	var read_ok: bool = rd.is_empty() or (String(rd.height) == String(m.height) and (String(m.from) == "C" or from == "C" or from == String(m.from)))
	s.def = {"kind": gname, "start": t, "ready": t + rise, "arm": arm, "atk": atk, "read_ok": read_ok}
	if gname == "check":
		# a shin check lifts the lead leg: her weight goes onto the rear foot first, as in a kick
		var lead := f.front_leg()
		f.kick_support = "rf" if lead == "lf" else "lf"
		f._lift_hold = f.life_t + minf(0.08, rise * 0.5)
		at(rise + hold + 0.12, func():
			if f.move_tag.begins_with("guard:check") or f.move_tag == "":
				f.kick_support = "")
	s.until = t + rise + hold
	atk.defence = kind
	action_starts.append(t)
	var segs: Array = []
	if gname == "parry":
		var pf := func() -> Vector3:
			var src := "LeftHand" if atk.limb == "lh" else "RightHand"
			var w: Vector3 = (F[atk.by] as MeleeFighter).trace.get(src, d.bone(atk.by, src))
			return w + d.fwd(s.id) * -0.02
		segs.append({"dur": rise, "ease": "snap", "pose": pose, "dyn": {"lh": pf}})
		segs.append({"dur": hold, "ease": "hold", "pose": pose, "dyn": {"lh": pf}})
		f.palm["lh"] = "fwd"
	else:
		segs.append({"dur": rise, "ease": "out", "pose": pose})
		segs.append({"dur": hold, "ease": "hold", "pose": pose})
	segs.append({"dur": 0.14, "ease": "inout", "pose": {}, "start": func(): f.palm["lh"] = "guard"})
	f.play(segs)
	var dirv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	if g.get("evade", false) and not atk.has("spell"):
		# out of the way: from here on the strike flies at the empty air where she was
		var surf_from: Vector3 = (F[o.id] as MeleeFighter).trace.get("RightUpperArm" if atk.limb in ["rh", "rf"] else "LeftUpperArm", d.chest(o.id))
		var pt: Vector3 = f.target_point(String(m.aim), surf_from)
		atk.locked = pt + (pt - surf_from).normalized() * 0.1
		match kind:
			"backstep":
				s.glide = {"from": d.pos(s.id), "to": d.clamp_arena(d.pos(s.id) - dirv * 0.8 * f.k), "t": 0.0, "dur": rise + 0.12, "ease": "out"}
				f.skim(rise + 0.14)
			"sidestep":
				var sv := dirv.cross(Vector3.UP) * sgn
				s.glide = {"from": d.pos(s.id), "to": d.clamp_arena(d.pos(s.id) + sv * 0.8 - dirv * 0.25), "t": 0.0, "dur": rise + 0.12, "ease": "out"}
				f.skim(rise + 0.14)
			"jump":
				d.hop(s.id, float(g.lift), 0.46)
	if g.get("evade", false) and atk.has("spell"):
		match kind:
			"backstep":
				s.glide = {"from": d.pos(s.id), "to": d.clamp_arena(d.pos(s.id) - dirv * 0.9 * f.k), "t": 0.0, "dur": rise + 0.14, "ease": "out"}
				f.skim(rise + 0.16)
			"sidestep":
				_spell_evade(s, o, atk, sgn)
				d.fx.afterimages(f.c, s.id, 3, 0.04)
			"jump":
				d.hop(s.id, float(g.lift) * 1.2, 0.5)
	events.append([snappedf(t, 0.01), "defend", s.id, kind])


## A creative escape from a spell (Selwyn 2026-10-20): a real mocap evade (a side dodge, a roll, a back flip, a
## cartwheel) carrying her 3 to 5 m across the field, sideways to the spell's line, timed late (just before it
## arrives), afterimages behind her and dust where she leaves and lands.
const EVADES := [["dodge_left", 0.9, 1.7, 4.2, 0.0], ["roll_dodge", 0.7, 2.0, 3.4, 0.0], ["backflip_evade", 0.9, 1.9, 3.6, 0.0],
	["cartwheel_evade", 0.8, 1.9, 4.0, 0.0], ["dodge_right", 1.1, 1.9, 4.2, 0.0]]


func _spell_evade(s: Dictionary, o: Dictionary, atk: Dictionary, sgn: float) -> void:
	var f: MeleeFighter = F[s.id]
	var pick: Array = EVADES[rng.randi() % EVADES.size()]
	var clip := String(pick[0])
	if clip == "dodge_left" or clip == "dodge_right":
		clip = "dodge_left" if sgn > 0.0 else "dodge_right"
	var dirv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	var sv := dirv.cross(Vector3.UP) * sgn
	var dist := float(pick[3]) * rng.randf_range(0.85, 1.15)
	var from_c := float(pick[1])
	var to_c := float(pick[2])
	var dur := (to_c - from_c) / 1.1
	var start := maxf(float(atk.t_hit) - t - dur * 0.55, 0.0)
	at(start, func():
		if String(s.state) in ["react", "down"]:
			return
		s.state = "defend"
		s.until = t + dur
		var to := d.clamp_arena(d.pos(s.id) + sv * dist - dirv * rng.randf_range(0.0, 1.2))
		s.glide = {"from": d.pos(s.id), "to": to, "t": 0.0, "dur": dur * 0.8, "ease": "out"}
		if f.c.has_clip("ml_" + clip):
			d.anim(s.id, "ml_" + clip, from_c, to_c, 1.1, 0.08)
			f.rig_w = 0.0
			f.play([{"dur": dur, "ease": "hold", "pose": {}}])
		else:
			f.skim(dur * 0.8)
		if clip == "backflip_evade":
			d.hop(s.id, 0.9, dur * 0.7)
		d.fx.afterimages(f.c, s.id, 6, 0.05)
		vfx.dust(d.pos(s.id), -sv, 22, 1.2)
		events.append([snappedf(t, 0.01), "evade", s.id, clip])
		at(dur * 0.8, func(): vfx.dust(d.pos(s.id), sv, 18, 1.0))
		at(dur, func():
			if f.rig_w < 0.5 and String(s.state) == "defend":
				f.replant()
				f.rig_w = 1.0
				d.stance(s.id, 0.25)
			if String(s.state) == "defend":
				s.state = "free"))


## The fight travels (Selwyn 2026-10-20: "change the location frequently, not fixed in that position"): every 7 to 11 s
## of range play both girls leap and dash to a new part of the area 9 to 16 m away, the arena's centre moving with
## them; a spot must be on the walkable ground with a clear line from here (no trunk or wall in the way).
var _next_reloc := 7.0


func _relocate_due() -> bool:
	if RenderProfile.options.has("duel-fixed") or t < _next_reloc:
		return false
	for x in S.values():
		if String(x.state) != "free" or (magic and magic.performing(String(x.id))):
			return false
	return true


func _relocate() -> void:
	_next_reloc = t + rng.randf_range(7.0, 11.0)
	var c: WorldCharacter = (F.values()[0] as MeleeFighter).c
	var map := c.get_world_3d().navigation_map
	var space := c.get_world_3d().direct_space_state
	var best := Vector3.INF
	for tries in 16:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(9.0, 16.0)
		var want := d.center + Vector3(cos(ang) * r, 0, sin(ang) * r)
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if _flat(p - want).length() > 1.5:
			continue
		var q := PhysicsRayQueryParameters3D.create(d.center + Vector3.UP * 1.2, p + Vector3.UP * 1.2)
		if not space.intersect_ray(q).is_empty():
			continue
		# room for the duel there: its sides on the ground too
		var ok := true
		for k in 4:
			var a2 := TAU * float(k) / 4.0
			var side_p := p + Vector3(cos(a2), 0, sin(a2)) * 4.0
			if _flat(NavigationServer3D.map_get_closest_point(map, side_p) - side_p).length() > 1.2:
				ok = false
		if ok:
			best = p
			break
	if best == Vector3.INF:
		return
	var old := d.center
	var tw := d.create_tween()
	tw.tween_property(d, "center", best, 0.9).set_trans(Tween.TRANS_SINE)
	var dir := _flat(best - old).normalized()
	var i := 0
	for x in S.values():
		var f: MeleeFighter = F[x.id]
		var lat := dir.cross(Vector3.UP) * (3.2 if i == 0 else -3.2)
		var land: Vector3 = best + lat + dir * rng.randf_range(-1.0, 1.0)
		var delay := 0.12 * float(i)
		var dur := rng.randf_range(0.8, 1.05)
		x.state = "dash"
		at(delay, func():
			x.glide = {"from": d.pos(x.id), "to": land, "t": 0.0, "dur": dur, "ease": "inout"}
			d.hop(x.id, rng.randf_range(1.0, 1.8), dur)
			f.skim(dur)
			d.fx.afterimages(f.c, x.id, 8, 0.06)
			vfx.dust(d.pos(x.id), -dir, 24, 1.3))
		at(delay + dur, func():
			vfx.dust(d.pos(x.id), dir, 20, 1.1)
			f.replant()
			if String(x.state) == "dash":
				x.state = "free"
			x.next_at = t + rng.randf_range(0.3, 0.7))
		i += 1
	mode_until = t + 1.4
	events.append([snappedf(t, 0.01), "travel", String(S.keys()[0]), "%.0f m" % _flat(best - old).length()])


# ------------------------------------------------------------------------------------------------ phases
## A heavy blow landed or was blocked: they break apart, circle at range, and one of them blinks back in.
func _separation(s: Dictionary, o: Dictionary) -> void:
	exchanges += 1
	_blows = 0
	_target_blows = rng.randi_range(2, 3)
	mode = "range"
	mode_until = t + rng.randf_range(0.35, 0.6)
	var dirv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	for x in [s, o]:
		x.range_d = rng.randf_range(6.5, 9.0)
		x.next_at = mode_until + rng.randf_range(0.0, 0.25)
	# the one knocked back pushes off further (a hop back), the kicker hops away too
	at(0.32, func():
		if String(o.state) != "down":
			d.hop(o.id, 0.35, 0.4)
			(F[o.id] as MeleeFighter).skim(0.42)
			o.glide = {"from": d.pos(o.id), "to": d.clamp_arena(d.pos(o.id) + dirv * 1.6), "t": 0.0, "dur": 0.4, "ease": "out"})
	at(0.18, func():
		if String(s.state) in ["free", "attack"]:
			d.hop(s.id, 0.3, 0.36)
			(F[s.id] as MeleeFighter).skim(0.38)
			s.glide = {"from": d.pos(s.id), "to": d.clamp_arena(d.pos(s.id) - dirv * 1.4), "t": 0.0, "dur": 0.36, "ease": "out"})
	events.append([snappedf(t, 0.01), "separation", s.id, ""])


## The rush: a crouch (her tell), a blink across the gap with afterimages, straight into a strike.
func _rush(s: Dictionary, o: Dictionary) -> void:
	var f: MeleeFighter = F[s.id]
	var dirv := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	var land: Vector3 = d.pos(o.id) - dirv * 1.0 * f.k
	var span := _flat(land - d.pos(s.id)).length()
	var dash_t := clampf(span / 22.0, 0.15, 0.28)
	var move := "palm_strike" if rng.randf() < 0.55 else "cross"
	var pre := [
		{"dur": 0.1, "ease": "inout", "pose": {"hip": Vector3(0, -0.22, -0.06), "hip_rot": Vector3(18, -22, 0), "spine": Vector3(16, 10, 0)},
			"start": func():
				vfx.dust(d.pos(s.id), -dirv, 16, 1.2)},
		{"dur": dash_t, "ease": "inout", "pose": {"hip": Vector3(0, -0.12, 0.04), "hip_rot": Vector3(30, -18, 0), "spine": Vector3(22, 6, 0),
			"lf": Vector3(0.12, 0.10, 0.25), "rf": Vector3(-0.12, 0.22, -0.32), "rfp": 50.0},
			"start": func():
				s.glide = {"from": d.pos(s.id), "to": d.clamp_arena(land), "t": 0.0, "dur": dash_t, "ease": "snap"}
				f.skim(dash_t + 0.06)
				d.fx.afterimages(f.c, s.id, 6, 0.03)
				_shot_now("duo", {"k": 0.9, "high": 0.25})},
	]
	mode = "close"
	_blows = 0
	_attack(s, o, move, pre)
	s.state = "attack"
	events.append([snappedf(t, 0.01), "rush", s.id, "%.1f m in %.2f s" % [span, dash_t]])
	for x in S.values():
		if x != s:
			x.next_at = t + 0.6


# ------------------------------------------------------------------------------------------------ camera
## Medium-wide on both of them, knees up and the ground visible, a new angle every few seconds.
func _camera() -> void:
	if t < _next_cam:
		return
	var close := mode == "close"
	var v := {"k": rng.randf_range(0.95, 1.08) if close else 0.95, "high": rng.randf_range(0.0, 0.45), "min": 3.0 if close else 4.0}
	if rng.randf() < 0.3:
		v["lead"] = rng.randf_range(-0.6, 0.6)
	if rng.randf() < 0.25:
		d.side = -d.side
	d.cut(d.ft + 0.001, "duo", S.keys()[0], v)
	_next_cam = t + rng.randf_range(2.6, 4.2)


func _shot_now(kind: String, v: Dictionary) -> void:
	d.cut(d.ft + 0.001, kind, S.keys()[0], v)
	_next_cam = t + rng.randf_range(1.6, 2.6)


# ------------------------------------------------------------------------------------------------ results
func result() -> Dictionary:
	var errs: Array = []
	var delays: Array = []
	var outcomes := {}
	for a in attacks:
		outcomes[a.outcome] = int(outcomes.get(a.outcome, 0)) + 1
		if float(a.err) >= 0.0:
			errs.append(float(a.err))
		if float(a.react_delay) >= 0.0:
			delays.append(float(a.react_delay))
	var gaps: Array = []
	var st := action_starts.duplicate()
	st.sort()
	for i in range(1, st.size()):
		gaps.append(snappedf(float(st[i]) - float(st[i - 1]), 0.01))
	return {"length": snappedf(t, 0.01), "attacks": attacks, "outcomes": outcomes, "contact_err": errs, "react_delays": delays,
		"gaps": gaps, "exchanges": exchanges, "events": events, "vfx": vfx.stats}


func teardown() -> void:
	SpellVFX.fight_glow(d.main, false)
	if realm and is_instance_valid(realm):
		realm.teardown()
	for n in _hidden:
		if is_instance_valid(n):
			(n as Node3D).visible = true
	for id in F:
		(F[id] as MeleeFighter).teardown()
	if is_instance_valid(vfx):
		vfx.queue_free()
	queue_free()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
