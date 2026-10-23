extends RefCounted
## --mktest=nodance (2026-10-23 live, a viewer: "why does she randomly start dancing"): with every dance long cooled
## down, Mika's own options hold no idle dance; the celebration one only comes with a reason.

static func run(t) -> void:
	var b = t.main.mage_brains["mika"]
	b.mind.music["last_unix"] = 0
	b.mind.music["last_special_unix"] = 0
	await t._wait(2.0)
	var keys := []
	for o in b.options():
		if String(o.get("kind", "")) == "perform":
			keys.append(String(o.get("key", "")))
	print("[nodance] perform options %s -> %s" % [keys, "PASS" if not keys.has("perform:casual") else "FAIL"])
