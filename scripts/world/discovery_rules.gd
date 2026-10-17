class_name DiscoveryRules
extends RefCounted
## Day 3: the discovery director's pure decisions (no world, no autoloads), so the rate test can simulate hours of
## play headless: how often (rate_per_min), how rare (roll_tier), what (pick), and simulate().

const MEMORY := 200                 # finds the "freshness" memory looks back over
const REPEAT_GAP := 40              # a repeatable find comes back only after this many other finds (preferred)
const HARD_GAP := 10                # ... and never within this many, even when nothing fresher is left
const TIER_ORDER := ["legendary", "rare", "uncommon", "common"]


static func load_pool() -> Dictionary:
	if FileAccess.file_exists("res://data/discovery_pool.json"):
		return JSON.parse_string(FileAccess.get_file_as_string("res://data/discovery_pool.json"))
	return {}


## Finds per minute in this context. 0 inside the minimum gap after a find; a pity ramp after a long dry spell.
static func rate_per_min(p: Dictionary, ctx: Dictionary, since_min: float) -> float:
	var rate: Dictionary = p.get("rate", {})
	if since_min < float(rate.get("min_gap_min", 14.0)):
		return 0.0
	var r := float(rate.get("per_hour", 1.0)) / 60.0
	var mult: Dictionary = rate.get("mult", {})
	for k in mult:
		if bool(ctx.get(k, false)):
			r *= float(mult[k])
	var pity := float(rate.get("pity_after_min", 85.0))
	if since_min > pity:
		r *= 1.0 + (since_min - pity) / 15.0
	return r


static func roll_tier(p: Dictionary, r: RandomNumberGenerator) -> String:
	var tiers: Dictionary = p.get("tiers", {})
	var x := r.randf()
	var acc := 0.0
	for t in ["common", "uncommon", "rare", "legendary"]:
		acc += float(tiers.get(t, 0.0))
		if x < acc:
			return t
	return "common"


## The find for this region and tier (falling to the next tier down when nothing fits). {} when nothing fits at all.
static func pick(p: Dictionary, region: String, tier: String, st: Dictionary, knowledge: Dictionary, r: RandomNumberGenerator, force_id := "") -> Dictionary:
	var finds: Array = p.get("finds", [])
	if force_id != "":
		for f in finds:
			if String(f.id) == force_id:
				return f
	var log_: Array = st.get("log", [])
	var ever := {}
	for e in log_:
		ever[String(e.id)] = true
	var recent := {}
	for e in log_.slice(maxi(0, log_.size() - REPEAT_GAP)):
		recent[String(e.id)] = true
	var last_kind := String(st.get("last_kind", ""))
	var start := TIER_ORDER.find(tier)
	for ti in range(maxi(start, 0), TIER_ORDER.size()):
		var t: String = TIER_ORDER[ti]
		var cands := []
		var weights := []
		for f in finds:
			if String(f.tier) != t or String(f.kind) == last_kind:
				continue
			var regions: Array = f.get("regions", ["*"])
			if not (regions.has(region) or regions.has("*")):
				continue
			var id := String(f.id)
			if bool(f.get("repeatable", false)):
				if recent.has(id):
					continue
			elif ever.has(id):
				continue
			var ok := true
			for k in f.get("requires", {}):
				if not knowledge.has(k):
					ok = false
			if not ok:
				continue
			cands.append(f)
			weights.append(2.0 if regions.has(region) else 1.0)       # this region's own finds first
		if cands.is_empty():
			# nothing fresh at this tier: the repeatable find she has gone longest without (never one of the last
			# HARD_GAP, never the same kind as the last) - the long memory keeps finds varied without ever running dry
			var last_seen := {}
			for i in log_.size():
				last_seen[String(log_[i].id)] = i
			var oldest := {}
			var oldest_i := log_.size() - HARD_GAP
			for f in finds:
				if String(f.tier) != t or String(f.kind) == last_kind or not bool(f.get("repeatable", false)):
					continue
				var regions2: Array = f.get("regions", ["*"])
				if not (regions2.has(region) or regions2.has("*")):
					continue
				var li := int(last_seen.get(String(f.id), -1))
				if li < oldest_i:
					oldest_i = li
					oldest = f
			if not oldest.is_empty():
				return oldest
			continue
		var total := 0.0
		for w in weights:
			total += w
		var x := r.randf() * total
		for i in cands.size():
			x -= weights[i]
			if x <= 0.0:
				return cands[i]
		return cands[-1]
	return {}


## Simulated play (no world): `mix` = [[weight, context], ...]; one step per minute. For the rate test.
static func simulate(p: Dictionary, mix: Array, minutes: int, seed_v: int, region_cycle: Array) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var st := {"log": [], "seq": 0, "since_min": 0.0, "last_kind": ""}
	var knowledge := {}
	var total_w := 0.0
	for m in mix:
		total_w += float(m[0])
	var tiers := {}
	var kinds := {}
	var back_to_back := 0
	var dupes_in_memory := 0
	var gaps := []
	for minute in minutes:
		var x := r.randf() * total_w
		var ctx: Dictionary = mix[-1][1]
		for m in mix:
			x -= float(m[0])
			if x <= 0.0:
				ctx = m[1]
				break
		st.since_min += 1.0
		if r.randf() >= 1.0 - exp(-rate_per_min(p, ctx, st.since_min)):
			continue
		var region: String = region_cycle[(minute / 90) % region_cycle.size()]
		var f := pick(p, region, roll_tier(p, r), st, knowledge, r)
		if f.is_empty():
			continue
		if String(f.kind) == String(st.last_kind):
			back_to_back += 1
		var last_ids := (st.log as Array).slice(maxi(0, st.log.size() - HARD_GAP)).map(func(e): return e.id)
		if last_ids.has(f.id):
			dupes_in_memory += 1
		gaps.append(st.since_min)
		st.seq += 1
		st.log.append({"id": f.id, "kind": f.kind, "tier": f.tier})
		st.last_kind = f.kind
		st.since_min = 0.0
		for k in f.get("reward", {}).get("knowledge", {}):
			knowledge[k] = 1
		tiers[f.tier] = int(tiers.get(f.tier, 0)) + 1
		kinds[f.kind] = int(kinds.get(f.kind, 0)) + 1
	return {"finds": st.log.size(), "per_hour": float(st.log.size()) * 60.0 / float(minutes), "tiers": tiers, "kinds": kinds,
		"back_to_back": back_to_back, "dupes_in_memory": dupes_in_memory, "min_gap": gaps.min() if not gaps.is_empty() else 0.0,
		"max_gap": gaps.max() if not gaps.is_empty() else 0.0, "log": st.log}
