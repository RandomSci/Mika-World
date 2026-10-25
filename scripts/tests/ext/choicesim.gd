extends RefCounted
## --mktest=choicesim (26 Oct): Mika's real planner asked 40 times in a row (each choice booked as the live loop books
## it, the activity itself not played): how many of her choices are walks and how many things on the spot, in an
## ordinary run and while walks keep going wrong. Marks "[choicesim] ...".

const Pastimes = preload("res://scripts/brain/pastimes.gd")


static func _sim(b, n: int, trouble: bool) -> Dictionary:
	var kinds := {}
	var seq := []
	for i in n:
		if trouble:
			b.walk_trouble_until = Time.get_unix_time_from_system() + 300.0
		var scored: Array = b.ranked()
		if scored.is_empty():
			continue
		var c: Dictionary = scored[0]
		kinds[String(c.kind)] = int(kinds.get(String(c.kind), 0)) + 1
		seq.append(String(c.kind) + (":" + String(c.pastime) if c.has("pastime") else ""))
		WorldState.note_activity(c.key, b.agent_id)
		WorldState.note_activity("kind:" + c.kind, b.agent_id)
		b._recent_kinds.append(String(c.kind))
		b._recent_targets.append(String(c.key))
		if b._recent_kinds.size() > 8:
			b._recent_kinds.pop_front()
		if b._recent_targets.size() > 8:
			b._recent_targets.pop_front()
		if c.has("pastime"):
			b.mind.activity_counts["pastime:" + String(c.pastime)] = {"last_unix": int(Time.get_unix_time_from_system())}
	return {"kinds": kinds, "seq": seq}


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	await t._wait(2.0)
	var b = main.mage_brains["mika"]
	var res := {}
	for mode in ["ordinary", "walks going wrong"]:
		for id in Pastimes.LIST:
			b.mind.activity_counts.erase("pastime:" + id)
		b._recent_kinds.clear()
		b._recent_targets.clear()
		b.walk_trouble_until = 0.0
		var r := _sim(b, 40, mode != "ordinary")
		var walks := 0
		for k in r.kinds:
			if k in Pastimes.WALK_KINDS:
				walks += int(r.kinds[k])
		res[mode] = {"walks": walks, "pastimes": int(r.kinds.get("pastime", 0))}
		print("[choicesim] %s: %s, walks %d of 40, on the spot %d | %s" % [mode, str(r.kinds), walks, int(r.kinds.get("pastime", 0)), ", ".join(r.seq)])
	t._check(res["ordinary"].pastimes >= 4, "in an ordinary run she picks pastimes (%d of 40)" % res["ordinary"].pastimes)
	t._check(res["ordinary"].walks <= 24, "walks are no longer most of her choices (%d of 40)" % res["ordinary"].walks)
	t._check(res["walks going wrong"].walks < res["ordinary"].walks, "while walks go wrong she walks less (%d vs %d)" % [res["walks going wrong"].walks, res["ordinary"].walks])
