class_name WeaponDuel
extends RefCounted
## Their duel with weapons (2026-10-20, Selwyn: "camera angles are really bad and they are not really fighting well
## at all"; the duel had them 7 to 16 m apart taking turns to cast, the weapons only in the spar). A brain that keeps
## them fighting: both draw their weapons and fight at blade range inside the clearing, every attack answered.
##   exchange   the attacker closes and strikes with one of her weapon clips (Mika fast and many, Luna wide and heavy);
##              the defender answers by her read: a block or a parry timed to the contact (Mika's parry ripostes), a
##              dodge out of the line (the mocap evades), or too late, a hit; after a guard she often counters at once
##   spacing    between exchanges they circle: the line between them turns 25 to 50 deg, 2.8 to 4.2 m apart, always
##              inside the clearing (the old duel's travel took them into the trees, the camera behind trunks)
##   magic      every 7 to 10 s one breaks away and casts (her gesture, the petal arts); the other dodges or takes it
##   ultimates  at the given fight seconds, the full kit (UltimateKit through UltimateCast)
## Every exchange is logged to `rows` and printed "[duel] ...".

const MIKA_ATTACKS := ["r_lunge_thrust", "r_triple_thrust", "r_flick_cut", "r_dash_through", "r_backstep_slash", "r_aerial_thrust", "s_iaido_draw"]
const LUNA_ATTACKS := ["g_wide_sweep", "g_overhead_arc", "g_long_thrust", "g_spin_multi_slash", "g_plant_burst", "s_running_slash"]
## defence clips by girl (guard, kind); the shaft block is HIGH (meets the overhead and aerial strikes)
const GUARDS := {"mika": [["r_parry_riposte", "parry"], ["s_blade_clash", "block"]],
	"luna": [["g_shaft_block", "high"], ["s_blade_clash", "block"], ["s_weapon_lock", "block"]]}
const HIGH := ["g_overhead_arc", "r_aerial_thrust", "s_running_slash"]
## per girl: how often she guards, dodges, counters (the rest she reads too late)
const STYLE := {"mika": {"guard": 0.35, "dodge": 0.35, "counter": 0.6, "magic": "frost_orb,star_daggers,starlight_lance,frost_arrow,meteor_rain"},
	"luna": {"guard": 0.5, "dodge": 0.2, "counter": 0.5, "magic": "moon_crescent,violet_moon,sigil_beam,moonlit_pillars,moon_seal"}}

var sim: MeleeSim
var wp: WeaponPlay
var rng: RandomNumberGenerator
var rows: Array = []
var next_at := 0.0
var next_magic := 8.0
var ult_at := {}
var ult_pick := {}
var _ult_done := {}
var attacker := "mika"


static func make(s: MeleeSim, opts := {}) -> WeaponDuel:
	var w := WeaponDuel.new()
	w.sim = s
	w.rng = s.rng
	w.wp = WeaponPlay.make(s)
	s.set_meta("weapon_play", w.wp)
	w.ult_at = opts.get("ult_at", {})
	w.ult_pick = opts.get("ult_pick", {})
	w.next_at = s.t + 2.2
	w.next_magic = s.t + 8.0
	w.wp.draw("mika")
	w.wp.draw("luna")
	w.wp.pose("mika", "r_salute_draw", 1.15)
	w.wp.pose("luna", "g_two_hand_spin", 1.15)
	return w


func _free(id: String) -> bool:
	var st := String(sim.S[id].state)
	return st in ["free", "idle", ""] and not (sim.magic and sim.magic.performing(id)) and not (sim.gestures and sim.gestures.busy(id))


## Called every frame by the test (fight time).
func update() -> void:
	# ultimates first: at their time, when the caster is free
	for id in ult_at:
		if not _ult_done.has(id) and sim.t >= float(ult_at[id]) and _free(id):
			_ult_done[id] = true
			var other := "luna" if id == "mika" else "mika"
			var L := UltimateCast.perform(sim, id, other, String(ult_pick.get(id, UltimateCast.SHAPES.keys()[0])))
			next_at = sim.t + L + 1.2
			print("[duel] %.2f ultimate %s" % [sim.t, id])
			return
	if sim.t < next_at or not _free("mika") or not _free("luna"):
		return
	if sim.t >= next_magic:
		_magic()
		return
	_exchange(attacker)


## One exchange: she closes and strikes, the other answers.
func _exchange(a: String) -> void:
	var b := "luna" if a == "mika" else "mika"
	_circle()
	var clip: String = (MIKA_ATTACKS if a == "mika" else LUNA_ATTACKS)[rng.randi() % (MIKA_ATTACKS if a == "mika" else LUNA_ATTACKS).size()]
	var atk := wp.strike(a, b, clip, rng.randf_range(1.0, 1.12))
	if atk.is_empty():
		next_at = sim.t + 0.5
		return
	var st: Dictionary = STYLE[b]
	var r := rng.randf()
	var answer := "late"
	if r < float(st.guard):
		var opts: Array = GUARDS[b]
		var pick: Array = opts[rng.randi() % opts.size()]
		if clip in HIGH and b == "luna":
			pick = opts[0]                                   # (the shaft held high for the overhead and aerial cuts)
		elif b == "luna" and String(pick[1]) == "high":
			pick = opts[1]
		wp.defend(b, String(pick[0]), float(atk.t_hit))
		answer = String(pick[1])
		if String(pick[0]) == "r_parry_riposte":
			var g: Array = WeaponPlay.GUARD["r_parry_riposte"]
			var rip := float(WeaponPlay.STRIKES["r_parry_riposte"][0]) - float(g[0])
			sim.at(maxf(float(atk.t_hit) - sim.t, 0.0), func(): wp.followup(b, a, "r_parry_riposte", rip))
			answer = "parry+riposte"
	elif r < float(st.guard) + float(st.dodge):
		sim._spell_evade(sim.S[b], sim.S[a], atk, 1.0 if rng.randf() < 0.5 else -1.0)
		answer = "dodge"
	var L := float(atk.t_hit) - sim.t + WeaponPlay.AFTER
	rows.append({"t": snappedf(sim.t, 0.01), "a": a, "clip": clip, "answer": answer})
	print("[duel] %.2f %s %s -> %s %s" % [sim.t, a, clip, b, answer])
	# who goes next: after a guard or a dodge the defender often counters at once; else the attacker presses or the
	# turn passes
	var counter := answer != "late" and rng.randf() < float(st.counter)
	attacker = b if counter or rng.randf() < 0.4 else a
	next_at = sim.t + L + (0.05 if counter else rng.randf_range(0.25, 0.6))


## Between exchanges: the line between them turns and the gap resets, inside the clearing.
func _circle() -> void:
	var d := sim.d
	var c0 := (d.pos("mika") + d.pos("luna")) * 0.5
	c0 = c0.lerp(d.center, 0.35)
	var ax := sim._flat(d.pos("luna") - d.pos("mika")).normalized()
	var turn := deg_to_rad(rng.randf_range(25.0, 50.0) * (1.0 if rng.randf() < 0.5 else -1.0))
	ax = ax.rotated(Vector3.UP, turn)
	var gap := rng.randf_range(2.8, 4.2)
	for pr in [["mika", c0 - ax * gap * 0.5], ["luna", c0 + ax * gap * 0.5]]:
		var s: Dictionary = sim.S[String(pr[0])]
		s.glide = {"from": d.pos(String(pr[0])), "to": d.clamp_arena(pr[1]), "t": 0.0, "dur": 0.45, "ease": "inout"}


## One breaks away and casts; the other dodges it or takes it.
func _magic() -> void:
	var a := "mika" if rng.randf() < 0.5 else "luna"
	var b := "luna" if a == "mika" else "mika"
	var pool: PackedStringArray = String(STYLE[a].magic).split(",")
	var name := String(pool[rng.randi() % pool.size()])
	# a step back first (the gap for a spell), then the gesture
	var away := sim._flat(sim.d.pos(a) - sim.d.pos(b)).normalized()
	var s: Dictionary = sim.S[a]
	s.glide = {"from": sim.d.pos(a), "to": sim.d.clamp_arena(sim.d.pos(a) + away * 1.6), "t": 0.0, "dur": 0.4, "ease": "out"}
	sim.at(0.42, func():
		if sim.gestures:
			sim.gestures.request(sim.S[a], sim.S[b], name)
		else:
			sim.magic.cast(sim.S[a], sim.S[b], name))
	sim.events.append([snappedf(sim.t, 0.01), "spell", a, name])
	print("[duel] %.2f %s casts %s" % [sim.t, a, name])
	rows.append({"t": snappedf(sim.t, 0.01), "a": a, "clip": name, "answer": "spell"})
	next_magic = sim.t + rng.randf_range(7.0, 10.0)
	next_at = sim.t + 3.2
	attacker = b
