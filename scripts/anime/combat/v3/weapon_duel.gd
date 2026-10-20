class_name WeaponDuel
extends RefCounted
## Their duel with weapons (2026-10-20). Rebuilt the same day on paired exchanges of suit mocap (Selwyn: "The duel is
## not acceptable. Their bodies barely move, they stand chest to chest, the weapons are held like flags and nobody
## really swings ... Every exchange is a paired animation ... Both girls attack and move about equally"; then "Mixamo
## is real suit mocap with true depth, so it becomes the core fighting body motion"):
##   exchange   the attacker's whole clip (Mika the UAL one-handed sword set for her rapier, Luna the Mixamo great sword
##              set for her two-handed longsword, the Shadow Blade) through PairedPlay, the defender's answer clip synced to every blow: a guard, a
##              parry, a duck, a jump or a roll out of the line, a hit, on a heavy last blow sometimes a knock-down and
##              the get up; spacing from the weapon's reach (rapier 1.5 m, longsword 1.8 m)
##   turns      whoever answered well often counters at once; else the turn passes; both lead about equally
##   spacing    between exchanges they circle: a side step clip while the line between them turns 25 to 50 deg
##   magic      every 7 to 10 s one breaks away and casts (her gesture clip and the petal arts; video mocap stays for
##              hand signs, gestures and ultimate poses)
##   ultimates  at the given fight seconds, the full kit (UltimateKit through UltimateCast)
## Every exchange is logged to `rows` and printed "[duel] ...".

## [clip, weight] her attacks (weight: light / medium / heavy, a heavy last blow may knock her down)
const ATTACKS := {
	"mika": [["ualf:Sword_Attack", "medium"], ["ualf:Sword_Regular_A", "light"], ["ualf:Sword_Regular_C", "medium"],
		["ualf:Sword_Regular_Combo", "medium"], ["ualf:Sword_Heavy_Combo", "heavy"], ["ualf:Sword_Dash", "medium"],
		["ml_r_lunge_thrust", "medium"]],
	"luna": [["sword:great_sword_attack", "light"], ["sword:great_sword_slash", "medium"], ["sword:great_sword_slash_2", "heavy"],
		["sword:great_sword_slash_3", "heavy"], ["sword:great_sword_slash_4", "medium"], ["sword:great_sword_slash_5", "medium"],
		["sword:great_sword_high_spin_attack", "heavy"], ["sword:great_sword_jump_attack", "heavy"], ["sword:great_sword_slide_attack", "medium"]],
}
## her answers: kind -> [[clip, meet s], ...] (Mika's steps and dodges: her one-handed guard over the legs, "<upper>|<lower>")
const MU := "ualf:Sword_Idle|"
const ANSWERS := {
	"mika": {"block": [["ualf:Sword_Block", 0.35]], "parry": [["ualf:Sword_Regular_B", 0.27]],
		"hit": [["ualf:Hit_Chest", 0.05], ["ualf:Hit_Head", 0.05], ["ualf:Idle_Shield_Break", 0.1]],
		"duck": [[MU + "sword:great_sword_crouching_4", 0.2]], "jump": [[MU + "sword:great_sword_jump_2", 0.35]], "roll": [["ualf:Roll", 0.35]],
		"side": [[MU + "sword:great_sword_strafe_3", 0.3], [MU + "sword:great_sword_strafe_4", 0.3]],
		"back": [[MU + "sword:great_sword_jump@rev", 0.35]]},
	"luna": {"block": [["sword:great_sword_blocking", 0.25], ["sword:great_sword_blocking_3", 0.25], ["sword:great_sword_blocking_2", 0.35]],
		"parry": [["sword:great_sword_blocking_3", 0.25]],
		"hit": [["sword:great_sword_impact", 0.08], ["sword:great_sword_impact_2", 0.1], ["sword:great_sword_impact_3", 0.1]],
		"duck": [["sword:great_sword_crouching_4", 0.2], ["sword:great_sword_crouching_2@mirror", 0.25]], "jump": [["sword:great_sword_jump_2", 0.35]],
		"roll": [["ualf:Roll", 0.35]], "side": [["sword:great_sword_strafe_3", 0.3], ["sword:great_sword_strafe_4", 0.3]],
		"back": [["sword:great_sword_jump@rev", 0.35]]},
}
const KNOCK := ["ualf:Hit_Knockback", 0.05, "ualf:LayToIdle"]
## the dodge that fits a blow: a sweep low (jump it), a leap down on her (roll under), a high spin (duck it), a thrust or
## a dash (out of its line), a long cut (a step back out of reach)
const DODGE := {"sword:great_sword_slide_attack": "jump", "sword:great_sword_slash_5": "jump", "sword:great_sword_jump_attack": "roll",
	"sword:great_sword_high_spin_attack": "duck", "sword:great_sword_slash_4": "duck", "sword:great_sword_slash_3": "side",
	"sword:great_sword_attack": "back", "sword:great_sword_slash": "back", "ualf:Sword_Attack": "side", "ualf:Sword_Dash": "side",
	"ml_r_lunge_thrust": "side", "ualf:Sword_Regular_C": "back", "ualf:Sword_Regular_A": "back"}
## her side steps between exchanges (the line between them turns)
const STEPS := {"mika": [MU + "sword:great_sword_strafe", MU + "sword:great_sword_strafe_2"],
	"luna": ["sword:great_sword_strafe", "sword:great_sword_strafe_2"]}
## per girl: how often she guards, dodges, counters (the rest lands)
const STYLE := {"mika": {"guard": 0.4, "dodge": 0.3, "counter": 0.6, "magic": "frost_orb,star_daggers,starlight_lance,frost_arrow,meteor_rain"},
	"luna": {"guard": 0.55, "dodge": 0.15, "counter": 0.5, "magic": "moon_crescent,violet_moon,sigil_beam,moonlit_pillars,moon_seal"}}

var sim: MeleeSim
var pp: PairedPlay
var wp: WeaponPlay
var rng: RandomNumberGenerator
var rows: Array = []
var next_at := 0.0
var next_magic := 8.0
var ult_at := {}
var ult_pick := {}
var _ult_done := {}
var attacker := "mika"
var led := {"mika": 0, "luna": 0}


static func make(s: MeleeSim, opts := {}) -> WeaponDuel:
	var w := WeaponDuel.new()
	w.sim = s
	w.rng = s.rng
	w.pp = PairedPlay.make(s)
	w.wp = w.pp.wp
	w.ult_at = opts.get("ult_at", {})
	w.ult_pick = opts.get("ult_pick", {})
	w.next_at = s.t + 1.2
	w.next_magic = s.t + 8.0
	return w


func _free(id: String) -> bool:
	var st := String(sim.S[id].state)
	return st in ["free", "idle", ""] and not (sim.magic and sim.magic.performing(id)) and not (sim.gestures and sim.gestures.busy(id)) \
		and float(pp.busy_until.get(id, 0.0)) <= sim.t


## Called every frame by the test (fight time).
func update() -> void:
	pp.update()
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


func _pick(arr: Array) -> Array:
	return arr[rng.randi() % arr.size()]


## One paired exchange: her attack, the other's answer to each blow.
func _exchange(a: String) -> void:
	var b := "luna" if a == "mika" else "mika"
	# (the attack least used lately, a little randomness: no clip twice in a row)
	var at: Array = _pick(ATTACKS[a])
	for _k in 3:
		if rows.is_empty() or String(rows[rows.size() - 1].clip) != String(at[0]):
			break
		at = _pick(ATTACKS[a])
	var clip := String(at[0])
	var hits: Array = BodyMoves.entry(clip).get("hits", [])
	var n := maxi(hits.size(), 1)
	var st: Dictionary = STYLE[b]
	var answers := []
	var summary := []
	var dodged := false
	for i in n:
		if dodged:
			break
		var r := rng.randf()
		var kind := "hit"
		if r < float(st.dodge) and DODGE.has(clip) and i == n - 1:
			kind = String(DODGE[clip])
		elif r < float(st.dodge) + float(st.guard) or (i < n - 1 and r < 0.85):
			kind = "parry" if b == "mika" and rng.randf() < 0.3 else "block"
		var e := {}
		if kind == "hit" and i == n - 1 and String(at[1]) == "heavy" and rng.randf() < 0.4:
			e = {"hit": i, "answer": "knock", "clip": KNOCK[0], "meet": KNOCK[1], "then": KNOCK[2]}
		elif kind in ["duck", "jump", "roll", "side", "back"]:
			var dc: Array = _pick(ANSWERS[b][kind])
			e = {"hit": i, "answer": "dodge", "clip": dc[0], "meet": dc[1]}
			dodged = true
		else:
			var ac: Array = _pick(ANSWERS[b][kind])
			e = {"hit": i, "answer": kind, "clip": ac[0], "meet": ac[1]}
		answers.append(e)
		summary.append(String(e.answer))
	var span := pp.exchange({"a": a, "b": b, "atk": clip, "answers": answers})
	led[a] = int(led[a]) + 1
	rows.append({"t": snappedf(sim.t, 0.01), "a": a, "clip": clip, "answer": ",".join(summary)})
	print("[duel] %.2f %s %s -> %s %s" % [sim.t, a, clip, b, ",".join(summary)])
	# who goes next: a good answer often counters at once; the one who has led less takes the turn otherwise
	var good := not ("hit" in summary or "knock" in summary)
	var counter := good and rng.randf() < float(st.counter)
	if counter:
		attacker = b
	else:
		attacker = b if int(led[b]) <= int(led[a]) else a
	next_at = sim.t + span + (0.1 if counter else rng.randf_range(0.2, 0.45))
	if not counter and rng.randf() < 0.5:
		sim.at(span + 0.05, func(): _circle())
		next_at += 1.2


## Between exchanges: both side step the same way round (each clip's own sideways travel), the line between them turns.
func _circle() -> void:
	var k := 0 if rng.randf() < 0.5 else 1
	for id in ["mika", "luna"]:
		var L := pp.drive(id, String(STEPS[id][k]), 0.0, -1.0, 1.0, 0.12)
		sim.at(L, func():
			if float(pp.busy_until.get(id, 0.0)) <= sim.t + 0.02:
				pp.stance(id))


## One breaks away and casts; the other dodges it or takes it.
func _magic() -> void:
	var a := "mika" if rng.randf() < 0.5 else "luna"
	var b := "luna" if a == "mika" else "mika"
	var pool: PackedStringArray = String(STYLE[a].magic).split(",")
	var name := String(pool[rng.randi() % pool.size()])
	var away := sim._flat(sim.d.pos(a) - sim.d.pos(b)).normalized()
	var s: Dictionary = sim.S[a]
	s.glide = {"from": sim.d.pos(a), "to": sim.d.clamp_arena(sim.d.pos(a) + away * 1.6), "t": 0.0, "dur": 0.4, "ease": "out"}
	(sim.F[a] as MeleeFighter).rig_w = 1.0
	sim.at(0.42, func():
		if sim.gestures:
			sim.gestures.request(sim.S[a], sim.S[b], name)
		else:
			sim.magic.cast(sim.S[a], sim.S[b], name))
	sim.at(3.0, func(): (sim.F[a] as MeleeFighter).rig_w = 0.0)
	sim.events.append([snappedf(sim.t, 0.01), "spell", a, name])
	print("[duel] %.2f %s casts %s" % [sim.t, a, name])
	rows.append({"t": snappedf(sim.t, 0.01), "a": a, "clip": name, "answer": "spell"})
	next_magic = sim.t + rng.randf_range(7.0, 10.0)
	next_at = sim.t + 3.2
	attacker = b
