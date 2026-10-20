extends RefCounted
## --mktest=duelmv: the anime duel (ext/duel.gd; the name "duel" is taken by the built-in Milestone K sparring test).

static func run(t) -> void:
	await (load("res://scripts/tests/ext/duel.gd") as GDScript).call("run", t, "duel")
