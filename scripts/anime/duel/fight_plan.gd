class_name FightPlan
extends RefCounted
## The referee (2026-10-19): decides what happens in a duel or a training bout before it is staged - the order of the
## exchanges, who attacks, whether each blow lands, is blocked (a shield takes it and cracks) or dodged, the damage,
## and who wins. Rolled from the two mages' levels with a seeded RandomNumberGenerator, so a bout is reproducible
## (same seed, same fight) and every seed is a different fight. The director turns each exchange into a staged beat.
##   duel:     HP 100 each; 5-7 exchanges with a beam clash in the middle; the one ahead finishes it (the finisher
##             always breaks through); then the aftermath (the winner helps her up, a high five).
##   training: touches instead of damage, lighter, first to 3 touches (or the time budget), teasing and laughs; no
##             finisher; they end laughing.

const DAMAGE := {"volley": 14.0, "dash_strike": 18.0, "aerial": 22.0, "spin": 16.0, "counter": 16.0, "clash": 20.0}
const CHIP := 4.0                         # a blocked blow still costs a little
## Fight-time length of each beat (the director's move library matches these).
const LEN := {"faceoff": 2.5, "charge": 1.6, "volley": 2.3, "dash_strike": 2.0, "aerial": 2.5, "spin": 1.9, "counter": 2.1,
	"clash": 3.7, "finisher": 4.0, "aftermath": 4.9, "bow": 2.4, "laugh": 4.2}
const DUEL_BUDGET := 13.6                 # seconds of exchanges between the opening and the finisher
const TRAINING_BUDGET := 15.5


## The spell duel (22 Oct): 45 to 60 s in all, nobody hurt. Every exchange ends on a ward or a dodge (or two spells
## meeting mid-air); one beam clash past the middle ends in a draw; the opening carries the reason they duel and the
## truce its end (opts open_lines / close_lines: [[who, text], ...]).
static func make_spell(rng: RandomNumberGenerator, opts: Dictionary) -> Array:
	var L: Dictionary = SpellBeats.LEN
	var total := rng.randf_range(45.0, 60.0)
	var out: Array = [{"move": "s_faceoff", "att": "mika", "def": "luna", "lines": opts.get("open_lines", [])}]
	var used := float(L.s_faceoff) + float(L.s_truce) + float(L.s_clash)
	var lib := ["s_volley", "s_blink", "s_counter", "s_aerial", "s_barrage", "s_dash"]
	var att := "mika" if rng.randf() < 0.5 else "luna"
	var last := ""
	var clash_done := false
	var start_used := used
	while true:
		var mv := ""
		if not clash_done and used - start_used > (total - start_used) * 0.6:
			mv = "s_clash"
			clash_done = true
		else:
			var pool := lib.filter(func(x): return x != last)
			mv = pool[rng.randi() % pool.size()]
			if used + float(L[mv]) > total:
				break
			used += float(L[mv])
		var d: String = "luna" if att == "mika" else "mika"
		var oc := "block"
		if mv in ["s_volley", "s_aerial"]:
			oc = "block" if rng.randf() < 0.55 else "dodge"
		out.append({"move": mv, "att": att, "def": d, "outcome": oc})
		last = mv
		att = d if rng.randf() < 0.65 else att
	if not clash_done:
		out.append({"move": "s_clash", "att": "mika", "def": "luna", "outcome": "draw"})
	out.append({"move": "s_truce", "att": "mika", "def": "luna", "lines": opts.get("close_lines", [])})
	return out


static func make(mode: String, rng: RandomNumberGenerator, levels: Dictionary, opts := {}) -> Array:
	if mode == "spell":
		return make_spell(rng, opts)
	var out: Array = []
	var dl := float(levels.get("mika", 1)) - float(levels.get("luna", 1))
	var edge := {"mika": clampf(dl * 0.03, -0.15, 0.15), "luna": clampf(-dl * 0.03, -0.15, 0.15)}
	var hp := {"mika": 100.0, "luna": 100.0}
	var touches := {"mika": 0, "luna": 0}
	if mode == "duel":
		out.append({"move": "faceoff", "att": "mika", "def": "luna"})
		out.append({"move": "charge", "att": "mika", "def": "luna"})
	else:
		out.append({"move": "bow", "att": "mika", "def": "luna"})
	var lib: Array = ["volley", "dash_strike", "aerial", "spin", "counter"]
	var budget := DUEL_BUDGET if mode == "duel" else TRAINING_BUDGET
	var used := 0.0
	var att := "mika" if rng.randf() < 0.5 + float(edge.mika) else "luna"
	var last := ""
	var n := 0
	var clash_done := mode != "duel"
	while used < budget - 1.0:
		var mv := ""
		if not clash_done and n == 2:
			mv = "clash"
			clash_done = true
		else:
			var pool := lib.filter(func(x): return x != last and not (n == 0 and x == "counter"))
			mv = pool[rng.randi() % pool.size()]
		var d: String = "luna" if att == "mika" else "mika"
		var ex := {"move": mv, "att": att, "def": d}
		var r := rng.randf()
		var p_hit := 0.42 + float(edge[att]) - float(edge[d]) * 0.5
		if mv == "clash":
			# the push: the stronger (and luckier) one wins it
			var mika_wins := rng.randf() < 0.5 + float(edge.mika) * 1.5
			ex.att = "mika" if mika_wins else "luna"
			ex.def = "luna" if mika_wins else "mika"
			ex.outcome = "hit"
		elif mv == "counter":
			# the attacker's blow is dodged and the defender answers: the outcome is the counter's
			ex.outcome = "hit" if r < p_hit + 0.1 else "block"
		else:
			ex.outcome = "hit" if r < p_hit else ("block" if r < p_hit + 0.3 else "dodge")
		var taker: String = ex.def if mv != "counter" else ex.att
		if ex.outcome == "hit":
			hp[taker] = float(hp[taker]) - float(DAMAGE[mv])
			if mv == "counter":
				touches[ex.def] = int(touches[ex.def]) + 1
			else:
				touches[ex.att] = int(touches[ex.att]) + 1
		elif ex.outcome == "block":
			hp[taker] = float(hp[taker]) - CHIP
		ex.hp = hp.duplicate()
		ex.touches = touches.duplicate()
		out.append(ex)
		used += float(LEN[mv])
		last = mv
		n += 1
		if mode != "duel" and (int(touches.mika) >= 3 or int(touches.luna) >= 3):
			break
		# who attacks next: mostly the one who did not just get the better of it
		var turn := rng.randf() < 0.7
		if ex.outcome == "hit" and mv != "counter":
			att = ex.def if turn else ex.att
		else:
			att = ex.def if rng.randf() < 0.6 else ex.att
	if mode == "duel":
		var w := "mika" if float(hp.mika) > float(hp.luna) else ("luna" if float(hp.luna) > float(hp.mika) else ("mika" if rng.randf() < 0.5 + float(edge.mika) else "luna"))
		var l := "luna" if w == "mika" else "mika"
		hp[l] = 0.0
		out.append({"move": "finisher", "att": w, "def": l, "outcome": "hit", "hp": hp.duplicate()})
		out.append({"move": "aftermath", "att": w, "def": l})
	else:
		out.append({"move": "laugh", "att": "mika", "def": "luna", "touches": touches.duplicate()})
	return out


static func outcome(mode: String, plan: Array) -> Dictionary:
	var hits := {"mika": 0, "luna": 0}
	var blocks := {"mika": 0, "luna": 0}
	var dodges := {"mika": 0, "luna": 0}
	var last_hp := {"mika": 100.0, "luna": 100.0}
	var touches := {"mika": 0, "luna": 0}
	for ex in plan:
		if not ex.has("outcome"):
			continue
		var mv := String(ex.move)
		var landed_by: String = ex.att if mv != "counter" else ex.def
		var defender: String = ex.def if mv != "counter" else ex.att
		match String(ex.outcome):
			"hit":
				hits[landed_by] = int(hits[landed_by]) + 1
			"block":
				blocks[defender] = int(blocks[defender]) + 1
			"dodge":
				dodges[defender] = int(dodges[defender]) + 1
		if ex.has("hp"):
			last_hp = ex.hp
		if ex.has("touches"):
			touches = ex.touches
	var r := {"mode": mode, "hits": hits, "blocks": blocks, "dodges": dodges, "hp": last_hp, "touches": touches,
		"exchanges": plan.filter(func(e): return e.has("outcome")).size()}
	if mode == "spell":
		r["winner"] = ""
		r["draw"] = true
	elif mode == "duel":
		var fin: Array = plan.filter(func(e): return String(e.move) == "finisher")
		r["winner"] = String(fin[0].att) if not fin.is_empty() else ""
		r["loser"] = String(fin[0].def) if not fin.is_empty() else ""
	else:
		r["winner"] = "mika" if int(touches.mika) > int(touches.luna) else ("luna" if int(touches.luna) > int(touches.mika) else "")
	return r
