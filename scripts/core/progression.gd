class_name Progression
extends Node
## Hybrid Level 1-100 progression (data/progression.json + per-mage orbit gates in data/mages.json).
## XP is derived ONLY from verified changes in WorldState.record_activity entries, per mage:
##   * firsts (new knowledge of a scoring kind, first page of a book, first talk, trial, rank, location,
##     mastery tier, first victory over a monster kind) pay once - each is keyed in progress.awarded;
##   * repeats (practice casts, later victories) pay a small amount that decays with every repeat;
##   * every 10th level is an Orbit Gate: XP alone stops at 9, 19, ...; the gate needs real milestones.
## Reaching a form level (10, 20, ...) unlocks that form; the TransformationDirector stages it.

signal xp_gained(who: String, amount: float, reason: String)
signal leveled(who: String, level: int)
signal gate_blocked(who: String, level: int, missing: Array)
signal form_unlocked(who: String, level: int, form: Dictionary)

static var data := {}
static var mages := {}
static var monsters := {}

var main: Node
var recent: Array = []          # last events for the overlays: {who, amount, reason, t}
var _gate_reported := {}        # who:level -> true (gate_blocked is announced once per session)


static func load_data() -> void:
	if not data.is_empty():
		return
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/progression.json"))
	mages = JSON.parse_string(FileAccess.get_file_as_string("res://data/mages.json")).mages
	if FileAccess.file_exists("res://data/monsters.json"):
		monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json")).monsters


func setup(m: Node) -> void:
	main = m
	load_data()
	WorldState.mage_event.connect(_on_event)


## Cumulative XP needed to reach `level`.
static func xp_for(level: int) -> float:
	load_data()
	return float(data.curve_base) * pow(maxf(level - 1, 0), float(data.curve_exp))


static func describe(who: String) -> Dictionary:
	var m := WorldState.mind(who)
	var lv := m.level()
	var lo := xp_for(lv)
	var hi := xp_for(lv + 1)
	return {"level": lv, "xp": snappedf(float(m.progress.xp), 0.1), "level_floor": snappedf(lo, 0.1), "next_level_xp": snappedf(hi, 0.1),
		"fraction": clampf((float(m.progress.xp) - lo) / maxf(hi - lo, 1.0), 0.0, 1.0), "title": title(lv),
		"gate": gate_status(who, (lv / 10 + 1) * 10), "forms_unlocked": m.progress.forms_unlocked}


static func title(level: int) -> String:
	load_data()
	var t := ""
	for k in data.level_titles:
		if level >= int(k):
			t = data.level_titles[k]
	return t


# ------------------------------------------------------------------ gates
static func gate_status(who: String, gate_level: int) -> Dictionary:
	load_data()
	var reqs: Array = mages.get(who, {}).get("orbit_gates", {}).get(str(gate_level), [])
	var out := []
	for r in reqs:
		out.append({"label": r.label, "met": _req_met(who, r)})
	return {"level": gate_level, "defined": not reqs.is_empty(), "met": not reqs.is_empty() and out.all(func(x): return x.met), "requirements": out}


static func _req_met(who: String, r: Dictionary) -> bool:
	var m := WorldState.mind(who)
	match String(r.kind):
		"rank_at_least":
			var names: Array = WorldState.sanctuary.get("ranks", []).map(func(x): return x.name)
			return names.find(WorldState.mage_rank(who)) >= names.find(r.value)
		"defeated_tier":
			var order := ["weak", "medium", "rare"]
			for kind in monsters:
				if order.find(String(monsters[kind].tier)) >= order.find(String(r.value)) and int(m.knowledge.get("defeated:" + kind, 0)) > 0:
					return true
			return false
		"spells_at_tier":
			return m.skills.values().filter(func(v): return float(v) >= float(r.get("tier", 0.05))).size() >= int(r.value)
		"skill_at_least":
			return float(m.skills.get(r.value, 0.0)) >= float(r.min)
		"reactions_seen":
			return m.knowledge.keys().filter(func(k): return String(k).begins_with("reaction:")).size() >= int(r.value)
	return false


# ------------------------------------------------------------------ XP from verified events
func _on_event(who: String, kind: String, entry) -> void:
	if kind != "activity":
		return
	var m := WorldState.mind(who)
	var total := 0.0
	var reasons := []
	for pair in xp_for_entry(m, entry):
		total += pair[0]
		reasons.append(pair[1])
	if total > 0.0:
		gain(who, total, ", ".join(reasons))


## [[amount, reason], ...] for one log entry; marks firsts as awarded (so a second call pays nothing).
static func xp_for_entry(m: MageMind, entry: Dictionary) -> Array:
	load_data()
	var out := []
	var aw: Dictionary = m.progress.awarded
	var ch: Dictionary = entry.get("changes", {})
	var act_id := String(entry.get("activity", {}).get("id", ""))
	for k in ch:
		var key := String(k)
		if key.begins_with("knowledge.") and _is_new(ch[k]):
			var kn := key.trim_prefix("knowledge.")
			var v := _prefix_value(data.first_knowledge, kn)
			if v > 0.0 and not aw.has("k:" + kn):
				aw["k:" + kn] = true
				out.append([v, kn])
		elif key.begins_with("trial.") and not aw.has(key):
			aw[key] = true
			out.append([float(data.trial), "trial " + key.trim_prefix("trial.")])
		elif key == "rank" and not aw.has("rank:" + String(ch[k][1])):
			aw["rank:" + String(ch[k][1])] = true
			out.append([float(data.rank), "rank " + String(ch[k][1])])
		elif key.begins_with("discovered.") and not aw.has(key):
			aw[key] = true
			out.append([float(data.discovered), "found " + key.trim_prefix("discovered.")])
		elif key.begins_with("skills."):
			var sid := key.trim_prefix("skills.")
			var t0 := _tier_index(float(ch[k][0]))
			var t1 := _tier_index(float(ch[k][1]))
			for t in range(t0 + 1, t1 + 1):
				if not aw.has("tier:%s:%d" % [sid, t]):
					aw["tier:%s:%d" % [sid, t]] = true
					out.append([float(data.mastery_tier[mini(t, data.mastery_tier.size() - 1)]), "%s mastery tier %d" % [sid, t]])
	# first time doing an activity of a scoring kind (one book page, one talk...)
	var fa := _prefix_value(data.first_activity, act_id)
	if fa > 0.0 and not aw.has("a:" + act_id):
		aw["a:" + act_id] = true
		out.append([fa, act_id])
	# victories: first per monster kind is a milestone, later ones decay (and halve once outgrown)
	if act_id.begins_with("defeat:"):
		var kind := act_id.trim_prefix("defeat:")
		var d: Dictionary = data.defeat.get(kind, {})
		if not d.is_empty():
			if not aw.has("defeat_first:" + kind):
				aw["defeat_first:" + kind] = true
				out.append([float(d.first), "first victory over a " + kind])
			else:
				var n := int(m.progress.repeats.get(act_id, 0))
				var v := float(d.repeat) / (1.0 + 0.5 * n)
				if m.level() > int(d.outgrown_at):
					v *= 0.5
				m.progress.repeats[act_id] = n + 1
				out.append([snappedf(v, 0.1), "another " + kind])
	else:
		# practice repeats decay per activity id
		for pre in data.repeat:
			if act_id.begins_with(pre) and not out.any(func(p): return String(p[1]) == act_id):
				var rp: Dictionary = data.repeat[pre]
				var n2 := int(m.progress.repeats.get(act_id, 0))
				m.progress.repeats[act_id] = n2 + 1
				if n2 > 0 and float(rp.base) > 0.0:
					out.append([snappedf(float(rp.base) / (1.0 + float(rp.decay) * (n2 - 1)), 0.1), "practice " + act_id])
	return out


static func _is_new(pair) -> bool:
	return pair is Array and (pair[0] == null or (typeof(pair[0]) in [TYPE_INT, TYPE_FLOAT] and float(pair[0]) == 0.0))


static func _prefix_value(table: Dictionary, key: String) -> float:
	var best := ""
	for p in table:
		if String(p).begins_with("_"):
			continue
		if key.begins_with(p) and String(p).length() > best.length():
			best = p
	return float(table[best]) if best != "" else 0.0


static func _tier_index(v: float) -> int:
	var idx := 0
	var tiers: Array = MagicSystem.load_catalog().mastery_tiers
	for i in tiers.size():
		if v >= float(tiers[i].min):
			idx = i
	return idx


func gain(who: String, amount: float, reason: String) -> void:
	var m := WorldState.mind(who)
	m.progress.xp = float(m.progress.xp) + amount
	recent.append({"who": who, "amount": snappedf(amount, 0.1), "reason": reason.left(80), "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1)})
	if recent.size() > 30:
		recent.pop_front()
	xp_gained.emit(who, amount, reason)
	check_level(who)
	WorldState._dirty = true


## Raise the level while XP allows; stop at an unmet Orbit Gate. Returns levels gained.
func check_level(who: String, silent := false) -> int:
	var m := WorldState.mind(who)
	var gained := 0
	while m.level() < int(data.max_level) and float(m.progress.xp) >= xp_for(m.level() + 1):
		var next := m.level() + 1
		if next % 10 == 0:
			var g := gate_status(who, next)
			if not g.met:
				if not _gate_reported.has("%s:%d" % [who, next]) and not silent:
					_gate_reported["%s:%d" % [who, next]] = true
					gate_blocked.emit(who, next, g.requirements.filter(func(r): return not r.met).map(func(r): return r.label))
				break
			m.progress.gates[str(next)] = int(Time.get_unix_time_from_system())
		m.progress.level = next
		gained += 1
		if not silent:
			leveled.emit(who, next)
		var form: Dictionary = mages.get(who, {}).get("forms", {}).get(str(next), {})
		if not form.is_empty() and not (m.progress.forms_unlocked as Array).has(form.id):
			(m.progress.forms_unlocked as Array).append(form.id)
			var orb: Dictionary = mages.get(who, {}).get("orbits", {}).get(str(next / 10), {})
			if not orb.is_empty() and not (m.progress.orbits as Array).has(orb.name):
				(m.progress.orbits as Array).append(orb.name)
			form_unlocked.emit(who, next, form)
	return gained


## Gates can open later (a victory satisfies the last requirement after the XP was already there).
func recheck_gates() -> void:
	for who in WorldState.minds:
		check_level(who)


## One-time catch-up for saves made before progression existed: score what the mind ALREADY verifiably
## holds (knowledge, trials, ranks reached, discoveries, mastery tiers, victories) without announcements.
func backfill(who: String) -> float:
	var m := WorldState.mind(who)
	if bool(m.progress.get("backfilled", false)):
		return 0.0
	m.progress["backfilled"] = true
	var ch := {}
	for k in m.knowledge:
		ch["knowledge." + String(k)] = [0, m.knowledge[k]]
	for t in m.trials_done:
		ch["trial." + String(t)] = [false, true]
	for s in m.skills:
		ch["skills." + String(s)] = [0.0, m.skills[s]]
	if m.legacy:
		for loc in WorldState.discovered_locations:
			if loc != WorldState.registry.start_location:
				ch["discovered." + String(loc)] = [false, true]
	var total := 0.0
	for p in xp_for_entry(m, {"changes": ch, "activity": {}}):
		total += float(p[0])
	var names: Array = WorldState.sanctuary.get("ranks", []).map(func(x): return x.name)
	for i in range(1, names.find(WorldState.mage_rank(who)) + 1):
		if not m.progress.awarded.has("rank:" + String(names[i])):
			m.progress.awarded["rank:" + String(names[i])] = true
			total += float(data.rank)
	for k in m.knowledge:
		if String(k).begins_with("defeated:"):
			for p in xp_for_entry(m, {"changes": {}, "activity": {"id": "defeat:" + String(k).trim_prefix("defeated:")}}):
				total += float(p[0])
	m.progress.xp = float(m.progress.xp) + total
	check_level(who, true)
	return total
