extends RefCounted
## --mktest=training: a friendly training bout (ext/duel.gd in training mode: touches, teasing and laughs, lighter
## effects, no finisher), then the XP.

static func run(t) -> void:
	await (load("res://scripts/tests/ext/duel.gd") as GDScript).call("run", t, "training")
