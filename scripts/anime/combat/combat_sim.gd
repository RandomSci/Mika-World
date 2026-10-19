class_name CombatSim
extends Node
## A real-time fight (2026-10-19, Selwyn: "it looks like turn-based card play"). Nothing is planned ahead: every
## fighter is a small brain that, many times a second, looks at the distance, its stamina and health, what the
## opponent is doing right now and how far the fight has escalated, and picks one move from MoveBook (or keeps
## moving: chasing, circling, backing off, sprinting in). Bodies move continuously over the terrain - nobody has a
## start mark to return to - they dash in and out, jump, fight in the air and vault obstacles. Hits are resolved when
## they land: dodged (a late dodge is a perfect dodge in slow motion), blocked on a cracking shield, parried, or taken
## (a flinch, a stagger and slide, a launch into the air, a knockdown). The fight is as long as the dice say (45 s to
## 3 min) and escalates: light moves, then heavy ones, then power moves with bigger effects, then a climax - the winner's
## cut-in, her domain over the sky, a beam clash, slow motion and the finisher. Highlights are counted, and nudged
## if the fight has had too few.
## It drives a FightDirector (its fighters, effects, hit-stop / slow motion / flashes, camera lens), for any number of
## fighters on any teams (duels, two girls against enemies, team-ups).

signal finished(result: Dictionary)

const ATTACKS := ["melee", "ranged", "dash", "aerial", "launcher", "slam", "beam", "parry"]
const MOVE_ACCEL := 16.0
const RUN_SPEED := 6.2
const STRAFE_SPEED := 3.0
const BACK_SPEED := 2.4
const GRAVITY := 20.0
const DODGE_IFRAMES := 0.7               # of a dodge's length
const PERFECT_WINDOW := 0.2              # s before a hit that a dodge counts as perfect
const ARENA := 11.5                      # m from the clearing's centre (soft wall)
const TIER_W := [{1: 1.0, 2: 0.12, 3: 0.0}, {1: 0.75, 2: 1.0, 3: 0.12}, {1: 0.45, 2: 0.9, 3: 1.0}, {1: 0.4, 2: 0.8, 3: 1.0}]
const DOMAIN := {
	"mika": {"top": Color(0.01, 0.03, 0.12), "hor": Color(0.25, 0.55, 0.95), "star": Color(0.85, 0.95, 1.0), "dens": 0.55, "moon": 0.0,
		"fog": Color(0.35, 0.6, 1.0), "amb": Color(0.45, 0.65, 1.0)},
	"luna": {"top": Color(0.04, 0.0, 0.1), "hor": Color(0.5, 0.2, 0.85), "star": Color(0.9, 0.8, 1.0), "dens": 0.25, "moon": 0.22,
		"fog": Color(0.55, 0.25, 0.9), "amb": Color(0.6, 0.4, 0.95)},
}

var d: FightDirector
var rng := RandomNumberGenerator.new()
var S := {}                              # id -> fighter state
var t := 0.0                             # fight time
var length := 90.0                       # the dice's fight length (s)
var phase := 0
var dmg_k := 1.0
var running := false
var climax := false
var done := false
var highlights: Array = []               # [t, kind, who, frame]
var move_count := {}                     # move -> times chosen
var events: Array = []                   # (QA) [t, who, what]
var _shot_until := 0.0
var _shot_kind := ""
var _next_base_shot := 0.0
var _closeups := 0
var _last_slowmo := -99.0
var _last_hl := -99.0
var _env: Environment
var _env0 := {}
var _dome: MeshInstance3D
var _dome_mat: ShaderMaterial
var _mark_tex: Texture2D
var _mark_glow: Texture2D
var _sched: Array = []                   # [t, Callable] (fight time)


static func make(director: FightDirector, opts := {}) -> CombatSim:
	var s := CombatSim.new()
	s.name = "CombatSim"
	s.process_priority = -60             # before the director places the bodies
	director.add_child(s)
	s._setup(director, opts)
	return s


func _setup(director: FightDirector, opts: Dictionary) -> void:
	d = director
	d.no_comic = true
	rng.seed = int(opts.get("seed", Time.get_ticks_usec()))
	length = float(opts.get("length", rng.randf_range(45.0, 180.0)))
	d.ARENA_R = ARENA
	var teams: Dictionary = opts.get("teams", {"mika": 0, "luna": 1})
	for id in d.F:
		var f: Dictionary = d.F[id]
		S[id] = {"id": id, "team": int(teams.get(id, 0)), "hp": 100.0, "stam": 100.0, "meter": 0.0, "state": "free",
			"act": {}, "act_t": 0.0, "act_len": 0.0, "hits_done": 0, "from": f.pos, "dest": f.pos, "vel": Vector3.ZERO,
			"intent": {"mode": "approach", "until": 0.0, "dir": 1.0}, "next_decide": rng.randf_range(0.2, 0.8), "recent": [],
			"react_until": 0.0, "iframes_until": 0.0, "block_until": 0.0, "parry_until": 0.0, "vy": 0.0, "air": false,
			"loco": "", "seen": {}, "vault_cd": 0.0, "shield": {}, "aura": {}, "down": false,
			# personality: Mika quick and aggressive at close range, Luna patient and deadly at range
			"aggr": 0.65 if id == "mika" else 0.5, "range_pref": 2.2 if id == "mika" else 6.5, "agility": 0.55 if id == "mika" else 0.45,
			"flair": rng.randf_range(0.3, 0.9)}
	_find_env()
	_mark_tex = _make_mark_texture(false)
	_mark_glow = _make_mark_texture(true)
	print("[combat] seed %d length %.0f s, arena %.1f m" % [rng.seed, length, ARENA])


func run() -> Dictionary:
	d.set_process(true)
	running = true
	_grade(true)
	d.cut(d.ft + 0.01, "duo", "mika", {"k": 1.15, "high": 0.6})
	_next_base_shot = 4.0
	for id in S:
		_say_start(id)
	while not done:
		await get_tree().process_frame
	running = false
	_grade(false)
	var r := _result()
	finished.emit(r)
	return r


# ------------------------------------------------------------------------------------------------ the frame
func _process(delta: float) -> void:
	if not running or done:
		return
	var dt := maxf(delta, 0.0)
	t += dt
	while not _sched.is_empty() and float(_sched[0][0]) <= t:
		var e: Array = _sched.pop_front()
		(e[1] as Callable).call()
	_escalate()
	for id in S:
		_tick(S[id], dt)
	_separate()
	_camera_director()
	if not climax and (t >= length * 0.84 or _lowest_hp() <= 24.0):
		_start_climax()


func at(dt_from_now: float, fn: Callable) -> void:
	var e := [t + dt_from_now, fn]
	var i := _sched.size()
	while i > 0 and float(_sched[i - 1][0]) > float(e[0]):
		i -= 1
	_sched.insert(i, e)


func _escalate() -> void:
	var p := 0 if t < length * 0.2 else (1 if t < length * 0.48 else (2 if t < length * 0.84 else 3))
	if p != phase:
		phase = p
		d.fx.level = 0.75 + phase * 0.22
		events.append([snappedf(t, 0.1), "", "phase %d" % phase])
		print("[combat] phase %d at %.1f s" % [phase, t])
	# damage scaling: the lowest health should reach ~30 by the climax, so the fight lasts what the dice said
	if int(t * 10.0) % 30 == 0 and not climax:
		var want := 100.0 - 70.0 * clampf(t / (length * 0.84), 0.0, 1.0)
		var err := _lowest_hp() - want
		dmg_k = clampf(dmg_k * (1.0 + err * 0.004), 0.3, 3.5)


# ------------------------------------------------------------------------------------------------ one fighter
func _tick(s: Dictionary, dt: float) -> void:
	var id: String = s.id
	var f: Dictionary = d.F[id]
	var o: Dictionary = _target(s)
	var me: Vector3 = f.pos
	var op: Vector3 = d.F[o.id].pos
	var to := _flat(op - me)
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
	s.stam = clampf(float(s.stam) + dt * (9.0 if s.state == "free" else 3.0), 0.0, 100.0)
	s.meter = clampf(float(s.meter) + dt * 1.2, 0.0, 100.0)
	s.vault_cd = maxf(float(s.vault_cd) - dt, 0.0)
	# airborne (launched, jumping off a wall): gravity, then a landing
	if s.air and s.state != "act":
		s.vy = float(s.vy) - GRAVITY * dt
		f.lift = maxf(float(f.lift) + float(s.vy) * dt, 0.0)
		if float(f.lift) <= 0.0 and float(s.vy) < 0.0:
			s.air = false
			f.lift = 0.0
			_land(s)
	match String(s.state):
		"act":
			_run_act(s, o, dt)
		"react":
			_slide(s, dt)
			if t >= float(s.react_until):
				_free(s)
		"down":
			_slide(s, dt)
			if t >= float(s.react_until) and not s.get("ko", false):
				_free(s)
		"free":
			_react_to_threat(s, o, dist)
			if String(s.state) == "free":
				_locomote(s, o, dir, dist, dt)
				s.next_decide = float(s.next_decide) - dt
				if float(s.next_decide) <= 0.0 and not s.air:
					_decide(s, o, dist)
	_arena_wall(s)


## Free movement between moves: the brain's current intent, steered and smoothed - never a return to a mark.
func _locomote(s: Dictionary, o: Dictionary, dir: Vector3, dist: float, dt: float) -> void:
	var f: Dictionary = d.F[s.id]
	var it: Dictionary = s.intent
	if t >= float(it.until):
		_pick_intent(s, dist)
		it = s.intent
	var side := dir.cross(Vector3.UP) * float(it.dir)
	var want := Vector3.ZERO
	var loco := "idle"
	match String(it.mode):
		"approach":
			want = dir * RUN_SPEED * (1.0 if dist > 3.0 else 0.4)
			loco = "run" if dist > 3.0 else "jog"
		"sprint":
			want = (dir * 0.85 + side * 0.35).normalized() * RUN_SPEED * 1.3
			loco = "sprint"
		"circle":
			# around her at the distance she likes, drifting in and out
			var radial := (dist - float(it.get("r", s.range_pref))) * 1.2
			want = side * STRAFE_SPEED + dir * clampf(radial, -2.0, 2.0)
			loco = "strafe_l" if float(it.dir) > 0.0 else "strafe_r"
		"retreat":
			want = -dir * BACK_SPEED + side * 0.8
			loco = "back"
		"hold":
			want = side * 1.4 + dir * (0.4 if dist > 4.0 else -0.3)       # (sizing her up: a slow circle, never planted)
			loco = "strafe_l" if float(it.dir) > 0.0 else "strafe_r"
	s.vel = (s.vel as Vector3).move_toward(want, MOVE_ACCEL * dt)
	var step := (s.vel as Vector3) * dt
	step = _terrain(s, step)
	f.pos = (f.pos as Vector3) + step
	if loco != s.loco:
		s.loco = loco
		var clip: String = MoveBook.LOCO[loco]
		d.anim(s.id, clip, 0.0, -1.0, 1.15 if loco in ["run", "sprint"] else 1.0, 0.18, true)


func _pick_intent(s: Dictionary, dist: float) -> void:
	var pref: float = s.range_pref
	var r := rng.randf()
	var mode := "circle"
	if s.stam < 25.0 and r < 0.6:
		mode = "retreat"
	elif dist > pref + 2.5:
		mode = "approach" if r < 0.6 else ("sprint" if r < 0.85 else "circle")
	elif dist < pref - 1.0 and pref > 4.0:
		mode = "retreat" if r < 0.55 else "circle"
	else:
		mode = "circle" if r < 0.7 else ("approach" if r < 0.85 else "hold")
	s.intent = {"mode": mode, "until": t + rng.randf_range(0.5, 1.6), "dir": -1.0 if rng.randf() < 0.5 else 1.0, "r": pref + rng.randf_range(-0.8, 0.8)}


## Walls and rocks: a fighter running at an obstacle vaults it (a jump off it), otherwise slides along it.
func _terrain(s: Dictionary, step: Vector3) -> Vector3:
	if step.length() < 0.0005:
		return step
	var c: WorldCharacter = d.F[s.id].c
	var from := c.global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + step.normalized() * 0.8)
	var ex: Array[RID] = []
	for id in d.F:
		var cc: WorldCharacter = d.F[id].c
		ex.append(cc.get_rid())
	q.exclude = ex
	var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return step
	var n: Vector3 = _flat(hit.normal).normalized()
	if float(s.vault_cd) <= 0.0 and not s.air and step.length() > 3.0 * get_process_delta_time():
		# off the wall: up and back the way she came, a flip - the terrain is part of the fight
		s.vault_cd = rng.randf_range(7.0, 12.0)            # (a moment, not a habit)
		s.air = true
		s.vy = 7.0
		s.vel = n * 4.5 + (s.vel as Vector3).slide(n) * 0.5
		d.anim(s.id, "lift_off", 0.25, -1.0, 1.4, 0.08)
		d.fx.afterimages(d.F[s.id].c, s.id, 3, 0.06)
		_highlight("wall_vault", s.id)
		return Vector3.ZERO
	return step.slide(n)


func _arena_wall(s: Dictionary) -> void:
	var f: Dictionary = d.F[s.id]
	var off := _flat((f.pos as Vector3) - d.center)
	if off.length() > ARENA:
		f.pos = d.center + off.normalized() * ARENA + Vector3(0, (f.pos as Vector3).y - d.center.y, 0)
		s.vel = (s.vel as Vector3).slide(off.normalized()) - off.normalized() * 1.5
		if String(s.state) == "free":
			s.intent = {"mode": "circle", "until": t + 0.8, "dir": s.intent.dir, "r": s.range_pref}


func _separate() -> void:
	var ids := S.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = d.F[ids[i]]
			var b: Dictionary = d.F[ids[j]]
			var v := _flat((b.pos as Vector3) - (a.pos as Vector3))
			var l := v.length()
			if l < 0.85 and l > 0.0001 and absf(float(a.lift) - float(b.lift)) < 1.2:
				var push := v / l * (0.85 - l) * 0.5
				a.pos = (a.pos as Vector3) - push
				b.pos = (b.pos as Vector3) + push


# ------------------------------------------------------------------------------------------------ the brain
## Scores every move the situation allows and picks one by weight - distance, stamina, health, phase, what she did
## last (no repeats), her personality, a bit of luck. Not choosing a move is also a choice (keep moving).
func _decide(s: Dictionary, o: Dictionary, dist: float) -> void:
	s.next_decide = rng.randf_range(0.15, 0.55) * (1.3 - float(s.aggr) * 0.6)
	if climax:
		return
	var cands: Array = []
	var weights: Array = []
	var tw: Dictionary = TIER_W[phase]
	var losing := float(s.hp) < float(o.hp) - 15.0
	for name in MoveBook.MOVES:
		var m: Dictionary = MoveBook.MOVES[name]
		var kind: String = m.kind
		if not (kind in ATTACKS or kind in ["charge", "taunt", "jump"]):
			continue                                     # (dodges and blocks are reactions, below)
		var rg: Array = m.range
		if dist < float(rg[0]) or dist > float(rg[1]):
			continue
		if float(s.stam) < float(m.stam):
			continue
		var w: float = float(tw.get(int(m.tier), 0.0)) if int(m.tier) > 0 else 0.25
		if w <= 0.0:
			continue
		if kind == "charge":
			w = 0.5 if float(s.meter) < 60.0 and dist > 6.0 else 0.0
		if kind == "taunt":
			w = 0.25 if phase == 0 and dist > 5.0 else 0.03
		if kind == "jump":
			w = 0.15 if dist < 2.5 and float(s.hp) < 60.0 else 0.03
		if kind == "parry":
			w = 0.0                                      # (a reaction, never an opener)
		w /= 1.0 + float(move_count.get(name, 0)) * 0.18       # (what the fight has already seen a lot of fades)
		if (s.recent as Array).has(name):
			w *= 0.15 if (s.recent as Array).back() == name else 0.45
		if kind == "aerial" and name == "air_chase" and o.air:
			w *= 12.0                                    # (she is up in the air: follow her up)
		if kind in ["ranged", "beam"] and float(s.range_pref) > 4.0:
			w *= 1.6
		if kind in ["melee", "dash", "launcher"] and float(s.range_pref) < 3.0:
			w *= 1.5
		if losing and int(m.tier) >= 2:
			w *= 1.4
		# a fight that needs a highlight leans toward the moves that make one
		if t > length * 0.4 and highlights.size() < 2 and kind in ["launcher", "beam", "slam"]:
			w *= 3.0
		w *= rng.randf_range(0.6, 1.4) * (0.5 + float(s.flair) * 0.8 if int(m.tier) == 3 else 1.0)
		cands.append(name)
		weights.append(w)
	# keep moving instead (the more so at an awkward distance)
	cands.append("")
	weights.append(0.35 + (1.0 - float(s.aggr)) * 0.6)
	var pick := _weighted(cands, weights)
	if pick == "":
		_pick_intent(s, dist)
		return
	_start_act(s, o, pick)


func _weighted(cands: Array, weights: Array) -> String:
	var tot := 0.0
	for w in weights:
		tot += float(w)
	var r := rng.randf() * tot
	for i in cands.size():
		r -= float(weights[i])
		if r <= 0.0:
			return String(cands[i])
	return String(cands.back())


## Danger: the opponent's strike is about to land on her - dodge (late = perfect), block, parry, or take it.
func _react_to_threat(s: Dictionary, o: Dictionary, dist: float) -> void:
	if String(o.state) != "act":
		return
	var a: Dictionary = o.act
	if not (String(a.kind) in ATTACKS) or (s.seen as Dictionary).has(a.uid):
		return
	var tth := _time_to_next_hit(o)
	if tth < 0.0 or tth > 0.42:
		return
	var reach := 3.2 if String(a.kind) in ["melee", "launcher", "parry"] else 99.0
	if dist > reach:
		return
	s.seen[a.uid] = true
	var r := rng.randf()
	var ag := float(s.agility) + phase * 0.05
	if r < ag * 0.75 and float(s.stam) >= 8.0:
		var opts := ["dodge_left", "dodge_right", "backstep", "roll"] if String(a.kind) != "beam" else ["dodge_left", "dodge_right", "roll"]
		var pick: String = opts[rng.randi() % opts.size()]
		_start_act(s, o, pick)
		if tth <= PERFECT_WINDOW and t - _last_slowmo > 12.0:
			_perfect_dodge(s, o)
	elif r < ag * 0.75 + 0.18 and float(s.stam) >= 5.0:
		_start_act(s, o, "block")
	elif r < ag * 0.75 + 0.27 and float(s.stam) >= 12.0 and String(a.kind) in ["melee", "dash"] and dist < 2.6:
		_start_act(s, o, "parry")


# ------------------------------------------------------------------------------------------------ moves
func _start_act(s: Dictionary, o: Dictionary, name: String) -> void:
	var m: Dictionary = MoveBook.MOVES[name]
	var c: WorldCharacter = d.F[s.id].c
	var L := FightDeck.clip_length(c, String(m.clip))
	if L <= 0.0:
		return
	var seg: Array = m.seg
	var dur := d.anim(s.id, String(m.clip), float(seg[0]) * L, float(seg[1]) * L, float(m.speed), 0.08)
	if dur <= 0.05:
		return
	s.loco = ""
	s.state = "act"
	s.act = m.duplicate()
	s.act["name"] = name
	s.act["uid"] = "%s:%d" % [s.id, Time.get_ticks_usec()]
	s.act["target"] = o.id
	s.act_t = 0.0
	s.act_len = dur
	s.hits_done = 0
	s.stam = float(s.stam) - float(m.stam)
	s.recent = ((s.recent as Array) + [name]).slice(-3)
	move_count[name] = int(move_count.get(name, 0)) + 1
	events.append([snappedf(t, 0.1), s.id, name])
	var me: Vector3 = d.F[s.id].pos
	var op: Vector3 = d.F[o.id].pos
	var dir := _flat(op - me).normalized()
	s.from = me
	var tr = m.get("travel", 0.0)
	if tr is String:
		var side := dir.cross(Vector3.UP) * (1.0 if tr == "side_r" else -1.0)
		s.dest = me + side * float(m.get("dist", 2.4)) - dir * 0.4
	elif float(tr) > 0.0:
		var dist := _flat(op - me).length()
		s.dest = me + dir * clampf((dist - 1.05) * float(tr), 0.0, 7.5)
	else:
		s.dest = me + dir * float(tr)
	var kind: String = m.kind
	if kind == "dodge" or kind == "jump":
		s.iframes_until = t + dur * DODGE_IFRAMES
		d.fx.afterimages(c, s.id, 4, 0.05)
	if kind == "block":
		s.block_until = t + dur
		s.shield = d.fx.shield(c, s.id, func() -> Vector3: return d.F[o.id].pos)
	if kind == "parry":
		s.parry_until = t + dur * 0.45
	if kind == "charge":
		s.aura = d.fx.aura(c, s.id, 0.8 + phase * 0.2)
		s.meter = minf(float(s.meter) + 30.0, 100.0)
	if kind in ["dash", "aerial", "slam"] and dur > 0.3:
		d.fx.afterimages(c, s.id, 3, 0.07)
		if rng.randf() < 0.45:
			_shot("track", s.id, 0.9)
	if kind in ["ranged", "beam", "slam", "launcher"] or int(m.tier) >= 2:
		d.fx.hand_charge(c, s.id, "RightHand", minf(dur * 0.45, 0.6), 0.35 + int(m.tier) * 0.1)
	if kind == "beam":
		s.act["beam"] = {}


func _run_act(s: Dictionary, o: Dictionary, dt: float) -> void:
	var a: Dictionary = s.act
	s.act_t = float(s.act_t) + dt
	var u := clampf(float(s.act_t) / maxf(float(s.act_len), 0.01), 0.0, 1.0)
	var f: Dictionary = d.F[s.id]
	var hits: Array = a.get("hits", [])
	# travel: arrive by the strike (attacks), across the whole move (dodges)
	var arrive: float = float(hits[0]) if not hits.is_empty() else 0.75
	var k := clampf(u / maxf(arrive, 0.05), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.4)
	var want: Vector3 = (s.from as Vector3).lerp(s.dest as Vector3, e)
	if u > arrive and String(a.kind) != "dodge":
		# follow-through: after the strike the body keeps going (momentum along the strike, easing into a circle)
		var span := maxf(1.0 - arrive, 0.05)
		var fade := 1.0 - clampf((u - arrive) / span, 0.0, 1.0)
		var along := _flat((s.dest as Vector3) - (s.from as Vector3)).normalized()
		var opp: Vector3 = d.F[o.id].pos
		var circ := _flat(opp - (f.pos as Vector3)).normalized().cross(Vector3.UP) * float((s.intent as Dictionary).get("dir", 1.0))
		var ft := (along * 1.6 * fade + circ * 1.3) * dt
		s.from = (s.from as Vector3) + ft
		s.dest = (s.dest as Vector3) + ft
		want += ft
	elif String(a.kind) in ["ranged", "beam", "charge", "block", "taunt"]:
		# never planted: casting, channelling, charging and guarding on the move, circling her (the drift is
		# carried in from / dest so the move's own travel still adds up)
		var op: Vector3 = d.F[o.id].pos
		var side := _flat(op - (f.pos as Vector3)).normalized().cross(Vector3.UP) * float((s.intent as Dictionary).get("dir", 1.0))
		var drift := side * (1.6 if String(a.kind) != "beam" else 0.9) * dt
		s.from = (s.from as Vector3) + drift
		s.dest = (s.dest as Vector3) + drift
		want += drift
	var step := want - Vector3((f.pos as Vector3).x, (f.pos as Vector3).y, (f.pos as Vector3).z)
	f.pos = (f.pos as Vector3) + _terrain(s, Vector3(step.x, 0.0, step.z))
	s["carry"] = Vector3(step.x, 0.0, step.z) / maxf(dt, 0.001)
	# a jump arc: up to `lift` at the strike, down by the end
	if a.has("lift"):
		var h: float = a.lift
		var peak: float = arrive
		f.lift = h * (sin(PI * 0.5 * clampf(u / peak, 0.0, 1.0)) if u < peak else cos(PI * 0.5 * clampf((u - peak) / maxf(1.0 - peak, 0.05), 0.0, 1.0)))
	# strikes
	while int(s.hits_done) < hits.size() and u >= float(hits[int(s.hits_done)]):
		s.hits_done = int(s.hits_done) + 1
		_strike(s, o, int(s.hits_done) - 1)
	if String(a.kind) == "beam" and not (a.beam as Dictionary).is_empty() and u > 0.85:
		d.fx.beam_off(a.beam)
		a.beam = {}
	if u >= 1.0:
		_end_act(s)


func _end_act(s: Dictionary) -> void:
	var a: Dictionary = s.act
	if not (s.shield as Dictionary).is_empty():
		d.fx.shield_off(s.shield)
		s.shield = {}
	if not (s.aura as Dictionary).is_empty():
		d.fx.aura_off(s.aura)
		s.aura = {}
	if a.get("beam", {}) is Dictionary and not (a.get("beam", {}) as Dictionary).is_empty():
		d.fx.beam_off(a.beam)
	if a.has("lift"):
		d.F[s.id].lift = 0.0
		d.fx.puff(d.F[s.id].pos, 8, 0.4)
	_free(s)


func _free(s: Dictionary) -> void:
	s.state = "free"
	s.act = {}
	s.loco = ""
	s.next_decide = rng.randf_range(0.05, 0.3)
	# momentum out of the move (a dash keeps sliding into the next step), never a dead stop
	s.vel = (s.get("carry", Vector3.ZERO) as Vector3).limit_length(RUN_SPEED) * 0.8
	s["carry"] = Vector3.ZERO


func _time_to_next_hit(o: Dictionary) -> float:
	var a: Dictionary = o.act
	var hits: Array = a.get("hits", [])
	var i := int(o.hits_done)
	if i >= hits.size():
		return -1.0
	return (float(hits[i]) - float(o.act_t) / maxf(float(o.act_len), 0.01)) * float(o.act_len)


## The blow lands now (melee) or is released (ranged): resolved against where she really is.
func _strike(s: Dictionary, o: Dictionary, idx: int) -> void:
	var a: Dictionary = s.act
	var kind: String = a.kind
	var me := d.chest(s.id)
	var op := d.chest(o.id)
	var col: String = s.id
	_fx_release(s, o, idx)
	if kind in ["ranged"]:
		var dist := _flat(op - me).length()
		var speed := 16.0 + phase * 3.0
		var hand := d.bone(s.id, "RightHand")
		d.fx.projectile(hand, func() -> Vector3: return d.chest(o.id), col, maxf(dist / speed, 0.15), 0.45 + int(a.tier) * 0.12, rng.randf_range(0.1, 0.5),
			func(at_p: Vector3): _land_hit(s, o, a, at_p), rng.randf_range(-0.4, 0.4))
		return
	if kind == "beam":
		if (a.beam as Dictionary).is_empty():
			a.beam = d.fx.beam(func() -> Vector3: return d.bone(s.id, "RightHand"), func() -> Vector3: return d.chest(o.id), col, 0.3 + phase * 0.05)
			# her beam against another beam already pouring: a clash
			if String(o.state) == "act" and String(o.act.get("kind", "")) == "beam":
				_beam_clash(s, o)
				return
		_land_hit(s, o, a, op)
		return
	# melee family: does it reach her?
	var reach := 2.1 + (0.6 if int(a.tier) >= 2 else 0.0) + (1.2 if kind == "slam" else 0.0)
	if _flat(op - me).length() <= reach and absf(float(d.F[s.id].lift) - float(d.F[o.id].lift)) < 1.9:
		_land_hit(s, o, a, op)
	else:
		d.fx.puff(d.F[s.id].pos, 4, 0.3)               # (a whiff: air and dust)


func _land_hit(s: Dictionary, o: Dictionary, a: Dictionary, at: Vector3) -> void:
	if o.get("ko", false):
		return
	var dir := _flat(d.pos(o.id) - d.pos(s.id)).normalized()
	if t < float(o.iframes_until):
		d.fx.sparks(at, -dir, s.id, 10, 3.0)          # (dodged)
		return
	var tier := int(a.get("tier", 1))
	if t < float(o.parry_until) and String(a.kind) in ["melee", "dash", "launcher"]:
		# parried: the attacker is thrown off balance and eats the counter
		d.fx.hit_spark(at, s.id, dir, true)
		d.impact(0.7, true)
		_react(s, o, "heavy", -dir, 1.4, 0.0)
		_highlight("parry_counter", o.id)
		return
	if t < float(o.block_until) and String(a.kind) != "beam":
		if not (o.shield as Dictionary).is_empty():
			d.fx.shield_hit(o.shield, at, 0.25 + tier * 0.15)
		o.stam = float(o.stam) - 10.0 * tier
		_hurt(o, float(a.get("dmg", 5.0)) * 0.2)
		if float(o.stam) <= 0.0 and not (o.shield as Dictionary).is_empty():
			d.fx.shield_shatter(o.shield, dir)
			o.shield = {}
			_react(o, s, "heavy", dir, 1.6, 0.0)
		d.impact(0.25 + tier * 0.1, false)
		return
	# a clean hit
	_hurt(o, float(a.get("dmg", 5.0)) * dmg_k)
	d.fx.hit_spark(at, s.id, dir, tier >= 2)
	d.impact(0.1 if tier <= 1 else 0.3 + tier * 0.18, tier >= 3)      # (light hits: a 2-frame hit-stop only)
	if tier >= 2:
		d.fx.ground_ring(d.pos(o.id), s.id, 1.6 + tier * 0.6, 1, 0.5)
	if tier >= 3:
		_mark(d.pos(o.id), s.id, 2.5 + rng.randf(), 14.0)
		_highlight("power_hit", s.id)
		_shot("impact", o.id, 0.7, {"at": d.pos(o.id)})
	var launch := float(a.get("launch", 0.0))
	if launch > 0.0:
		_react(o, s, "air", dir, float(a.get("knock", 0.6)), launch)
		_shot("crane", s.id, 1.1)
	elif a.get("down", false):
		_react(o, s, "down", dir, float(a.get("knock", 1.0)), 0.0)
	elif float(a.get("knock", 0.0)) >= 1.8 or tier >= 2:
		_react(o, s, "heavy", dir, float(a.get("knock", 1.5)), 0.0)
	else:
		_react(o, s, "light", dir, float(a.get("knock", 0.6)), 0.0)
	if String(a.get("name", "")) == "air_chase" and float(d.F[o.id].lift) > 0.5:
		_highlight("air_combo", s.id)


func _hurt(o: Dictionary, dmg: float) -> void:
	var floor_hp := 22.0 if not climax else 0.0      # (nobody falls before the climax: the finisher ends it)
	o.hp = maxf(float(o.hp) - dmg, floor_hp)


func _react(o: Dictionary, by: Dictionary, kind: String, dir: Vector3, knock: float, launch: float) -> void:
	if String(o.state) == "act":
		var a: Dictionary = o.act
		if a.get("beam", {}) is Dictionary and not (a.get("beam", {}) as Dictionary).is_empty():
			d.fx.beam_off(a.beam)
		if not (o.shield as Dictionary).is_empty():
			d.fx.shield_off(o.shield)
			o.shield = {}
		if not (o.aura as Dictionary).is_empty():
			d.fx.aura_off(o.aura)
			o.aura = {}
		d.F[o.id].lift = 0.0 if launch <= 0.0 else d.F[o.id].lift
	var r: Array = MoveBook.REACT[kind]
	var c: WorldCharacter = d.F[o.id].c
	var L := FightDeck.clip_length(c, String(r[0]))
	var dur := d.anim(o.id, String(r[0]), float(r[1]) * L, float(r[2]) * L, float(r[3]), 0.06)
	o.state = "down" if kind == "down" else "react"
	o.act = {}
	o.loco = ""
	o.react_until = t + maxf(dur, 0.35) * (0.6 if kind == "light" else 1.0)
	o.vel = dir * knock * 3.2
	if launch > 0.0:
		o.air = true
		o.vy = sqrt(2.0 * GRAVITY * launch)
		o.state = "react"
		o.react_until = t + 99.0                         # (until she lands)
	d.face_fx(o.id, "hurt", 1.0, 0.6)
	if kind in ["heavy", "down"]:
		d.fx.puff(d.pos(o.id), 10, 0.5)


func _land(s: Dictionary) -> void:
	d.fx.puff(d.pos(s.id), 12, 0.6)
	if String(s.state) == "react":
		var r: Array = MoveBook.REACT.down
		var c: WorldCharacter = d.F[s.id].c
		var L := FightDeck.clip_length(c, String(r[0]))
		var dur := d.anim(s.id, String(r[0]), float(r[1]) * L, float(r[2]) * L, float(r[3]), 0.08)
		s.state = "down"
		s.react_until = t + dur * (1.0 if not s.get("ko", false) else 99.0)
		_mark(d.pos(s.id), s.id, 1.6, 10.0)
	else:
		d.anim(s.id, "land_soft", 0.0, -1.0, 1.4, 0.08)


func _slide(s: Dictionary, dt: float) -> void:
	var f: Dictionary = d.F[s.id]
	s.vel = (s.vel as Vector3).move_toward(Vector3.ZERO, 7.0 * dt)
	f.pos = (f.pos as Vector3) + _terrain(s, (s.vel as Vector3) * dt)
	if (s.vel as Vector3).length() > 2.5 and not s.air and Engine.get_process_frames() % 4 == 0:
		d.fx.puff(f.pos, 2, 0.25)


func _target(s: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	for id in S:
		var o: Dictionary = S[id]
		if int(o.team) == int(s.team) or o.get("ko", false):
			continue
		var dd := _flat(d.pos(id) - d.pos(s.id)).length()
		if dd < bd:
			bd = dd
			best = o
	return best if not best.is_empty() else S[d.F[s.id].other]


# ------------------------------------------------------------------------------------------------ effects
func _fx_release(s: Dictionary, o: Dictionary, idx: int) -> void:
	var a: Dictionary = s.act
	var who: String = s.id
	var me := d.chest(who)
	var op := d.chest(o.id)
	var fwd := _flat(op - me).normalized()
	var up := Vector3.UP
	var side := fwd.cross(up)
	var big := 1.0 + phase * 0.25
	match String(a.get("fx", "")):
		"jab", "palm":
			d.fx.crescent(me + fwd * 0.6, side, fwd, 0.55 * big, -40.0, 50.0 if idx % 2 == 0 else -120.0, who, 0.12, 0.07)
		"kick":
			d.fx.crescent(me + fwd * 0.4 - up * 0.3, side, fwd, 0.8 * big, -60.0, 60.0, who, 0.14, 0.09)
		"crescent", "sweep":
			d.fx.crescent(me + fwd * 0.3 - up * (0.6 if String(a.fx) == "sweep" else 0.0), up if String(a.fx) == "sweep" else side, fwd, 1.3 * big, -110.0, 110.0, who, 0.18, 0.12)
		"crescent_big", "slide":
			d.fx.crescent(me + fwd * 0.2, side.rotated(fwd, rng.randf_range(-0.6, 0.6)), fwd, 1.8 * big, -130.0, 130.0, who, 0.2, 0.16)
			d.fx.crescent(me + fwd * 0.4, up, fwd, 1.4 * big, -90.0, 90.0, who, 0.24, 0.1)
		"launch":
			d.fx.crescent(me + fwd * 0.4, side, up, 1.4 * big, -80.0, 80.0, who, 0.16, 0.12)
			_spikes(d.pos(who), d.pos(o.id), who, 5, 0.9)
		"slam_small":
			d.fx.ground_ring(d.pos(o.id), who, 2.4 * big, 2, 0.6)
			d.fx.debris(d.pos(o.id), 10, 0.8)
		"eruption":
			_spikes(d.pos(who), d.pos(o.id) + fwd * 1.5, who, 12, 1.6)
			d.fx.ground_ring(d.pos(o.id), who, 4.0 * big, 2, 0.8)
			d.fx.debris(d.pos(o.id), 18, 1.2)
			_mark(d.pos(o.id), who, 3.5, 16.0)
		"ring_slash":
			for k in 3:
				d.fx.crescent(me + up * (k - 1) * 0.35, up.rotated(fwd, (k - 1) * 0.3), fwd, (1.6 + k * 0.4) * big, -180.0, 180.0, who, 0.22 + k * 0.04, 0.12)
		"spikes":
			_spikes(d.pos(who) + fwd * 1.0, d.pos(o.id) + fwd * 2.0, who, 14, 1.8)
			_mark(d.pos(o.id), who, 2.4, 12.0)
		"blast":
			d.fx.ground_ring(d.pos(who) + fwd * 0.8, who, 1.4, 1, 0.4)
		"parry":
			d.fx.crescent(me + fwd * 0.5, side, fwd, 1.0, -70.0, 90.0, who, 0.12, 0.1)
		"bolt", "beam", "":
			pass


## Shaped energy from the ground (Part F): a line of crystals (Mika: ice) or thorns (Luna: moon-shadow) erupting one
## after another from her toward the target, rising fast, holding, sinking.
func _spikes(from: Vector3, to: Vector3, who: String, n: int, h: float) -> void:
	var col := Color(0.6, 0.88, 1.0) if who == "mika" else Color(0.55, 0.25, 0.95)
	var core := Color(0.92, 0.98, 1.0) if who == "mika" else Color(0.12, 0.03, 0.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = core
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.6 if who == "mika" else 1.8
	mat.metallic = 0.3
	mat.roughness = 0.15
	for i in n:
		var u := float(i) / maxf(n - 1, 1)
		var p := from.lerp(to, u) + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = rng.randf_range(0.08, 0.2) * (0.7 + h * 0.3)
		mesh.height = h * rng.randf_range(0.6, 1.25) * (0.6 + 0.4 * sin(PI * u))
		mesh.radial_segments = 5
		mesh.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.fx.add_child(mi)
		var gy := FightDirector.ground_y(d.F[who].c, p)
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.45))
		mi.global_transform = Transform3D(tilt, Vector3(p.x, gy - mesh.height * 0.5, p.z))
		var top := Vector3(p.x, gy + mesh.height * 0.45, p.z)
		var delay := u * 0.35
		var tw := mi.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(mi, "global_position", top, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.7 + rng.randf() * 0.3)
		tw.tween_property(mi, "global_position", top - Vector3(0, mesh.height, 0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	at(0.05, func(): d.fx.debris(from.lerp(to, 0.5), 8, 0.6))


## A mark left on the ground (Part F): a frost / moon-glyph projection that fades over `life` seconds.
func _mark(at: Vector3, who: String, size: float, life: float) -> void:
	var dc := Decal.new()
	dc.texture_albedo = _mark_tex
	dc.texture_emission = _mark_glow      # (rgb = the pattern: emission ignores albedo alpha, a white texture lit the whole box)
	dc.modulate = Color(0.6, 0.85, 1.0, 0.75) if who == "mika" else Color(0.7, 0.4, 1.0, 0.75)
	dc.emission_energy = 0.8
	dc.size = Vector3(size, 0.7, size)    # (thin: it marks the ground, never the side of a rock)
	dc.upper_fade = 0.5
	dc.lower_fade = 0.5
	dc.cull_mask = 1
	d.fx.add_child(dc)
	dc.global_position = Vector3(at.x, FightDirector.ground_y(d.F[who].c, at) + 0.05, at.z)
	dc.rotation.y = rng.randf() * TAU
	var tw := dc.create_tween()
	tw.tween_interval(life * 0.6)
	tw.tween_property(dc, "modulate:a", 0.0, life * 0.4)
	tw.tween_callback(dc.queue_free)


func _make_mark_texture(glow: bool) -> Texture2D:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 77
	var cracks: Array = []
	for k in 9:
		cracks.append([r2.randf() * TAU, r2.randf_range(0.5, 1.0)])
	for y in n:
		for x in n:
			var u := (x - n * 0.5) / (n * 0.5)
			var v := (y - n * 0.5) / (n * 0.5)
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			var a := 0.0
			a += exp(-pow((r - 0.82) * 22.0, 2.0)) * 0.9                 # the outer ring
			a += exp(-pow((r - 0.55) * 30.0, 2.0)) * 0.5
			for c in cracks:                                              # cracks out from the centre
				var da := absf(wrapf(ang - float(c[0]), -PI, PI))
				if r < float(c[1]):
					a += exp(-pow(da * r * 40.0, 2.0)) * (1.0 - r / float(c[1])) * 0.9
			a += (1.0 - smoothstep(0.0, 0.35, r)) * 0.5                   # the scorched centre
			a = clampf(a, 0.0, 1.0) * (1.0 - smoothstep(0.9, 1.0, r))
			img.set_pixel(x, y, Color(a, a, a, 1.0) if glow else Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------------------------------------ highlights
func _highlight(kind: String, who: String) -> void:
	if t - _last_hl < 1.2 and kind != "ultimate":
		return
	_last_hl = t
	highlights.append([snappedf(t, 0.1), kind, who, Engine.get_frames_drawn()])
	print("[combat] highlight %s by %s at %.1f s at frame %d" % [kind, who, t, Engine.get_frames_drawn()])


func _perfect_dodge(s: Dictionary, o: Dictionary) -> void:
	_last_slowmo = t
	d.slowmo(0.3, 0.2)                                    # (~0.7 s of real time: a key moment, never a long drag)
	d.fx.afterimages(d.F[s.id].c, s.id, 6, 0.04)
	_shot("profile", s.id, 0.9)
	_highlight("perfect_dodge", s.id)


## Two beams meet: a struggle in the middle, slow motion, then the stronger one breaks through.
func _beam_clash(s: Dictionary, o: Dictionary) -> void:
	var h := d.fx.clash(func() -> Vector3: return (d.chest(s.id) + d.chest(o.id)) * 0.5)
	_shot("wide_low", s.id, 1.6)
	d.slowmo(0.5, 0.4)
	_highlight("beam_clash", s.id)
	at(1.4, func():
		d.fx.clash_off(h)
		var win: Dictionary = s if float(s.meter) + float(s.hp) + rng.randf() * 30.0 > float(o.meter) + float(o.hp) + rng.randf() * 30.0 else o
		var lose: Dictionary = o if win == s else s
		d.impact(0.9, true)
		d.fx.explosion(d.chest(lose.id), win.id, 1.3)
		_hurt(lose, 12.0 * dmg_k)
		_react(lose, win, "down", _flat(d.pos(lose.id) - d.pos(win.id)).normalized(), 2.8, 0.0))


# ------------------------------------------------------------------------------------------------ the climax
func _start_climax() -> void:
	climax = true
	phase = 3
	var ids := S.keys()
	var win: Dictionary = S[ids[0]]
	for id in ids:
		if float(S[id].hp) > float(win.hp) or (float(S[id].hp) == float(win.hp) and rng.randf() < 0.5):
			win = S[id]
	var lose: Dictionary = _target(win)
	print("[combat] climax at %.1f s: %s's ultimate" % [t, win.id])
	_ultimate(win, lose)


func _ultimate(w: Dictionary, l: Dictionary) -> void:
	# 0: both break apart - she leaps back, the other braces
	for s in [w, l]:
		if String(s.state) == "act":
			_end_act(s)
		s.state = "climax"
	var wf: Dictionary = d.F[w.id]
	var away := _flat(d.pos(w.id) - d.pos(l.id)).normalized()
	if away.length() < 0.1:
		away = Vector3.RIGHT
	var land := d.clamp_arena(d.pos(l.id) + away * 7.0)
	d.anim(w.id, "lift_off", 0.25, -1.0, 1.3, 0.08)
	d.fx.afterimages(wf.c, w.id, 5, 0.05)
	var tw := create_tween()
	tw.tween_method(func(k: float):
		wf.pos = (wf.pos as Vector3).lerp(land, 0.18)
		wf.lift = 2.2 * sin(PI * k), 0.0, 1.0, 0.75)
	d.anim(l.id, "ml_fight_idle", 0.0, -1.0, 1.0, 0.2, true)
	# 1: the cut-in - her face, eyes open; the domain rolls over the sky
	at(0.8, func():
		wf.lift = 0.0
		var L := FightDeck.clip_length(wf.c, MoveBook.ULTIMATE.charge_clip)
		d.anim(w.id, MoveBook.ULTIMATE.charge_clip, 0.1 * L, 0.9 * L, 1.0, 0.1)
		w.aura = d.fx.aura(wf.c, w.id, 1.6)
		_shot("face", w.id, 1.3)
		d.face_fx(w.id, "determined", 1.0, 2.0)
		d.sfx.flash_seq([["white", 1]])
		_domain(w.id, true)
		_highlight("ultimate_cutin", w.id))
	# 2: the loser answers with a beam - the clash in her domain
	at(2.2, func():
		_shot("duo", w.id, 1.8, {"k": 1.25, "high": 1.0})
		for s in [l, w]:
			var c: WorldCharacter = d.F[s.id].c
			var L2 := FightDeck.clip_length(c, "ml_beam_channel")
			d.anim(s.id, "ml_beam_channel", 0.15 * L2, 0.85 * L2, 0.8, 0.1)
		var bw := d.fx.beam(func() -> Vector3: return d.bone(w.id, "RightHand"), func() -> Vector3: return (d.chest(w.id) + d.chest(l.id)) * 0.5, w.id, 0.45)
		var bl := d.fx.beam(func() -> Vector3: return d.bone(l.id, "RightHand"), func() -> Vector3: return (d.chest(w.id) + d.chest(l.id)) * 0.5, l.id, 0.38)
		var h := d.fx.clash(func() -> Vector3: return (d.chest(w.id) + d.chest(l.id)) * 0.5)
		d.slowmo(0.4, 1.4)
		_highlight("ultimate_clash", w.id)
		at(1.6, func():
			d.fx.beam_off(bl)
			d.fx.beam_off(bw)
			d.fx.clash_off(h)
			d.impact(1.0, true)))
	# 3: she breaks through - a dash in with afterimages, the finisher, slow motion on the decisive blow
	at(4.0, func():
		var dirv := _flat(d.pos(l.id) - d.pos(w.id)).normalized()
		var hit_at: Vector3 = d.pos(l.id) - dirv * 1.0
		d.fx.afterimages(wf.c, w.id, 7, 0.035)
		var tw2 := create_tween()
		tw2.tween_method(func(v: Vector3): wf.pos = v, d.pos(w.id), hit_at, 0.28).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		var L3 := FightDeck.clip_length(wf.c, MoveBook.ULTIMATE.clip)
		var dur := d.anim(w.id, MoveBook.ULTIMATE.clip, 0.05 * L3, 0.95 * L3, 1.25, 0.06)
		_shot("orbit", w.id, dur * 0.6)
		for k in 4:
			at(0.3 + k * dur * 0.16, func():
				var me := d.chest(w.id)
				var fw := _flat(d.chest(l.id) - me).normalized()
				d.fx.crescent(me + fw * 0.4, fw.cross(Vector3.UP).rotated(fw, rng.randf_range(-0.8, 0.8)), fw, 2.0 + k * 0.4, -150.0, 150.0, w.id, 0.2, 0.16)
				d.fx.hit_spark(d.chest(l.id), w.id, fw, true)
				d.impact(0.6 + k * 0.1, k == 3)
				d.shake(0.8))
		at(0.3 + dur * 0.62, func():
			# the decisive blow: slow motion, the ground erupts in her colour, the screen flashes twice
			d.slowmo(0.22, 0.9)
			_last_slowmo = t
			_spikes(d.pos(w.id), d.pos(l.id) + dirv * 3.0, w.id, 18, 2.4)
			d.fx.pillar(d.pos(l.id), w.id, 6.0, 1.4)
			d.fx.explosion(d.chest(l.id), w.id, 1.2)
			d.fx.ground_ring(d.pos(l.id), w.id, 7.0, 3, 1.2)
			d.fx.debris(d.pos(l.id), 30, 1.6)
			_mark(d.pos(l.id), w.id, 6.0, 30.0)
			d.impact(1.0, true, true)
			at(0.1, func(): d.impact(0.8, false))
			l.hp = 0.0
			l["ko"] = true
			_react(l, w, "air", dirv, 3.0, 2.2)
			_shot("crane", l.id, 2.2)
			_highlight("finisher", w.id))
		at(0.3 + dur + 1.6, func():
			if not (w.aura as Dictionary).is_empty():
				d.fx.aura_off(w.aura)
				w.aura = {}
			_domain(w.id, false)
			var Lv := FightDeck.clip_length(wf.c, "ml_victory_pose")
			d.anim(w.id, "ml_victory_pose", 0.1 * Lv, 0.95 * Lv, 1.0, 0.25)
			d.face_fx(w.id, "proud", 1.0, 3.0)
			_shot("duo", w.id, 3.5, {"k": 0.85, "high": 0.4})
			at(3.2, func(): done = true)))


## Her domain over the sky (Part F): a dome inside which her sky replaces the world's, the fog and ambient light
## tinted her colour; tweened in, held, tweened out.
func _domain(who: String, on: bool) -> void:
	var p: Dictionary = DOMAIN.get(who, DOMAIN.mika)
	if on:
		if _dome == null:
			_dome = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 60.0
			sm.height = 120.0
			sm.radial_segments = 48
			sm.rings = 24
			_dome.mesh = sm
			_dome_mat = ShaderMaterial.new()
			_dome_mat.shader = load("res://shaders/anime/combat/domain_sky.gdshader")
			_dome.material_override = _dome_mat
			_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			d.fx.add_child(_dome)
		_dome.global_position = d.center
		_dome_mat.set_shader_parameter("top_col", p.top)
		_dome_mat.set_shader_parameter("horizon_col", p.hor)
		_dome_mat.set_shader_parameter("star_col", p.star)
		_dome_mat.set_shader_parameter("star_density", p.dens)
		_dome_mat.set_shader_parameter("moon_size", p.moon)
		var md := _flat(d.pos(who) - d.center)
		_dome_mat.set_shader_parameter("moon_dir", (Vector3(-md.x, 0.0, -md.z).normalized() + Vector3(0, 0.35, 0)).normalized() if md.length() > 0.1 else Vector3(0, 0.35, -1))
	var tw := create_tween()
	tw.tween_method(func(k: float):
		if _dome_mat:
			_dome_mat.set_shader_parameter("amount", k)
		if _env:
			_env.fog_enabled = true
			_env.fog_light_color = (_env0.fog_col as Color).lerp(p.fog, k)
			_env.fog_density = lerpf(float(_env0.fog_den), maxf(float(_env0.fog_den), 0.008), k)
			_env.ambient_light_color = (_env0.amb as Color).lerp(p.amb, k * 0.8)
			_env.adjustment_saturation = lerpf(0.8, 0.55, k)
			_env.adjustment_brightness = lerpf(0.92, 0.8, k), 0.0 if on else 1.0, 1.0 if on else 0.0, 1.5 if on else 2.0)
	if on:
		_highlight("domain", who)


## The fight grade: the world a little greyer and darker while they fight, so their magic is what glows.
func _grade(on: bool) -> void:
	if _env == null:
		return
	if on:
		_env0 = {"adj": _env.adjustment_enabled, "sat": _env.adjustment_saturation, "bri": _env.adjustment_brightness,
			"fog": _env.fog_enabled, "fog_col": _env.fog_light_color, "fog_den": _env.fog_density, "amb": _env.ambient_light_color,
			"glow_cap": _env.glow_hdr_threshold}
		_env.adjustment_enabled = true
		_env.adjustment_saturation = 0.8
		_env.adjustment_brightness = 0.92
		_env.glow_hdr_threshold = maxf(_env.glow_hdr_threshold, 1.1)     # (magic never washes the frame to white)
	else:
		_env.adjustment_enabled = bool(_env0.adj)
		_env.adjustment_saturation = float(_env0.sat)
		_env.adjustment_brightness = float(_env0.bri)
		_env.fog_enabled = bool(_env0.fog)
		_env.fog_light_color = _env0.fog_col
		_env.fog_density = float(_env0.fog_den)
		_env.ambient_light_color = _env0.amb
		_env.glow_hdr_threshold = float(_env0.glow_cap)
		if _dome:
			_dome.queue_free()
			_dome = null


func _find_env() -> void:
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if we.environment and we.is_inside_tree():
			_env = we.environment
	if _env == null:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.environment:
			_env = cam.environment


# ------------------------------------------------------------------------------------------------ camera
## A follow shot that keeps every fighter in frame most of the time (the reference: wide, readable), changing angle
## every few seconds; the moves and highlights cut to their own shots for a moment, then back.
func _camera_director() -> void:
	if t < _shot_until:
		return
	if t >= _next_base_shot or _shot_kind != "duo":
		var variants := [{"k": 1.0, "high": 0.4}, {"k": 0.85, "high": -0.15, "fov": 50.0}, {"k": 1.2, "high": 2.2}, {"k": 1.0, "high": 0.6, "flip": -1.0}]
		var v: Dictionary = variants[rng.randi() % variants.size()]
		if v.get("flip", 1.0) < 0.0:
			d.side = -d.side                              # (a deliberate cross of the line, across a wide)
			v.erase("flip")
		d.cut(d.ft + 0.001, "duo", "mika", v)
		_shot_kind = "duo"
		_next_base_shot = t + rng.randf_range(3.5, 7.0)


func _shot(kind: String, who: String, hold: float, opts := {}) -> void:
	if t < _shot_until and kind in ["track", "impact"]:
		return                                            # (a bigger moment already has the lens)
	if kind in ["face", "face_ots"]:
		_closeups += 1
	d.cut(d.ft + 0.001, kind, who, opts)
	_shot_kind = kind
	_shot_until = t + hold


# ------------------------------------------------------------------------------------------------ helpers
func _lowest_hp() -> float:
	var lo := 100.0
	for id in S:
		lo = minf(lo, float(S[id].hp))
	return lo


func _say_start(id: String) -> void:
	d.face_fx(id, "determined" if id == "luna" else "playful", 0.9, 2.0)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _result() -> Dictionary:
	var win := ""
	for id in S:
		if not S[id].get("ko", false):
			win = id
	return {"winner": win, "length_s": snappedf(t, 0.1), "dice_length_s": snappedf(length, 0.1), "highlights": highlights,
		"moves": move_count, "hp": S.keys().map(func(i): return [i, snappedf(float(S[i].hp), 0.1)]), "events": events.size(), "seed": rng.seed}
