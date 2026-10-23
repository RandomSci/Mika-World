extends RefCounted
## --mktest=samewords (2026-10-23 live: "look at a cluster of rocks and old stones" three times running, a new spot
## each time): once a label is done, no option with the same words comes back within 30 minutes.

static func run(t) -> void:
	var b = t.main.mage_brains["mika"]
	await t._wait(3.0)
	var counts := {}
	for o in b.options():
		counts[String(o.label)] = int(counts.get(String(o.label), 0)) + 1
	var label := ""
	for l in counts:
		if counts[l] > 1:
			label = l
			break
	if label == "":
		label = String(b.options()[0].label) if not b.options().is_empty() else ""
	var before: int = int(counts.get(label, 0))
	WorldState.note_activity("label:" + label, "mika")
	var after: int = b.options().filter(func(o): return String(o.label) == label).size()
	print("[samewords] '%s' offered %d times before, %d after -> %s" % [label, before, after, "PASS" if before > 0 and after == 0 else "FAIL"])
