extends RefCounted
## --mktest=fallguard (2026-10-23 live: Mika fell out of the world at Lantern Lake for 21 minutes): a mage dropped far
## below where she stood is put back on her last floor within a second.

static func run(t) -> void:
	await t._hold_all()
	await t._wait(3.0)
	var c = t.main.characters["mika"]
	var stood: Vector3 = c.global_position
	t.main.teleport_guard.allow(c)
	c.global_position = stood + Vector3(0, -40.0, 0)
	await t._wait(1.0)
	var back: float = c.global_position.distance_to(stood)
	print("[fallguard] stood %s, after the drop %.1f m from it, falls logged %d -> %s" % [stood.snapped(Vector3.ONE * 0.1), back,
		t.main.teleport_guard.falls.size(), "PASS" if back < 2.0 and t.main.teleport_guard.falls.size() >= 1 else "FAIL"])
