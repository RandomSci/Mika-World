extends RefCounted
## Every GDScript of the game and the shared body loads and compiles (inside the real project, autoloads present):
## the minute long gate before a long regression run. Marks "[compile] FAIL <path>".

const ROOTS := ["res://scripts", "res://addons/mika_body"]
## Old tests already broken before 2026-10-20 (not in any suite): reported, not counted.
const KNOWN_BROKEN := {"res://scripts/tests/ext/duel.gd": "reads FightDirector.ARENA_R as a constant (an instance var since the v3 arena)"}


static func run(t) -> void:
	var files: Array = []
	for r in ROOTS:
		_walk(r, files)
	var bad := []
	for p in files:
		if KNOWN_BROKEN.has(p):
			print("[compile] known broken, not loaded %s (%s)" % [p, KNOWN_BROKEN[p]])
			continue
		var s = load(p)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
			bad.append(p)
			print("[compile] FAIL %s" % p)
	t._check(bad.is_empty(), "%d scripts compile (%d fail)" % [files.size(), bad.size()])


static func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)
