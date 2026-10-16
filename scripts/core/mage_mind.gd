class_name MageMind
extends RefCounted
## One mage's private state: what SHE knows, carries, can cast and has achieved. Minds never share data.
## Mika's mind is a live view onto WorldState's original fields (so every pre-existing system, the save
## format and the tests keep working unchanged); every other mage owns her own dictionaries and is saved
## under "agents" in the same save file.

var id := ""
var legacy := false              # true only for Mika: properties read/write WorldState's fields

var _knowledge := {}
var _inventory := {}
var _skills := {}
var _trials_done := {}
var _prefix_counts := {}
var _activity_counts := {}
var _activity_log: Array[Dictionary] = []
var _activity_seq := 0
var discovered := {}             # places SHE has seen (sub-areas / locations), not Mika's map
## progression (both mages; Mika's lives here too and is saved as "progress")
var progress := {"xp": 0.0, "level": 1, "awarded": {}, "repeats": {}, "gates": {}, "forms_unlocked": [], "orbits": []}
var vigor := 1.0                 # 0..1 battle stamina (not saved: she recovers between sessions)
var location := {}               # {area, pos:[x,y,z]} where she is in the world (saved; drives simulation tiers)
var deferred: Array = []         # activities she wanted while in the background that need the real world
var music := {}                  # performance preferences / history (Milestone I; saved, never shared)
var explored := {}               # area -> {cell "x,z": unix} her own coverage map (ExplorationMap)

var knowledge: Dictionary:
	get: return WorldState.knowledge if legacy else _knowledge
	set(v):
		if legacy: WorldState.knowledge = v
		else: _knowledge = v
var inventory: Dictionary:
	get: return WorldState.inventory if legacy else _inventory
	set(v):
		if legacy: WorldState.inventory = v
		else: _inventory = v
var skills: Dictionary:
	get: return WorldState.skills if legacy else _skills
	set(v):
		if legacy: WorldState.skills = v
		else: _skills = v
var trials_done: Dictionary:
	get: return WorldState.trials_done if legacy else _trials_done
	set(v):
		if legacy: WorldState.trials_done = v
		else: _trials_done = v
var prefix_counts: Dictionary:
	get: return WorldState._prefix_counts if legacy else _prefix_counts
	set(v):
		if legacy: WorldState._prefix_counts = v
		else: _prefix_counts = v
var activity_counts: Dictionary:
	get: return WorldState.activity_counts if legacy else _activity_counts
	set(v):
		if legacy: WorldState.activity_counts = v
		else: _activity_counts = v
var activity_log: Array[Dictionary]:
	get: return WorldState.activity_log if legacy else _activity_log
	set(v):
		if legacy: WorldState.activity_log = v
		else: _activity_log = v
var activity_seq: int:
	get: return WorldState.activity_seq if legacy else _activity_seq
	set(v):
		if legacy: WorldState.activity_seq = v
		else: _activity_seq = v


static func create(p_id: String, p_legacy := false, starting_skills := {}) -> MageMind:
	var m := MageMind.new()
	m.id = p_id
	m.legacy = p_legacy
	if not p_legacy:
		m._skills = starting_skills.duplicate()
	return m


func location_pos() -> Vector3:
	var p: Array = location.get("pos", [])
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3.INF


## extra: what she is doing there ({doing: option key, kind, pose}) so a relaunch resumes it
func set_location(area: String, pos: Vector3, extra := {}) -> void:
	location = {"area": area, "pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)]}
	location.merge(extra)


func level() -> int:
	return int(progress.get("level", 1))


func note_activity(kind: String) -> void:
	var a: Dictionary = activity_counts.get_or_add(kind, {"count": 0, "last_unix": 0})
	a.count = int(a.count) + 1
	a.last_unix = int(Time.get_unix_time_from_system())


## Saved form of a non-legacy mind (Mika's fields stay where they always were).
func to_dict() -> Dictionary:
	return {"knowledge": _knowledge, "inventory": _inventory, "skills": _skills, "trials_done": _trials_done,
		"prefix_counts": _prefix_counts, "activity_counts": _activity_counts, "activity_seq": _activity_seq,
		"activity_log": _activity_log.slice(maxi(0, _activity_log.size() - 200)), "discovered": discovered, "progress": progress,
		"location": location, "deferred": deferred.slice(maxi(0, deferred.size() - 20)), "music": music, "explored": explored}


func from_dict(d: Dictionary) -> void:
	_knowledge = d.get("knowledge", {})
	_inventory = d.get("inventory", {})
	_skills = d.get("skills", _skills)
	_trials_done = d.get("trials_done", {})
	_prefix_counts = d.get("prefix_counts", {})
	_activity_counts = d.get("activity_counts", {})
	_activity_seq = int(d.get("activity_seq", 0))
	_activity_log.assign(d.get("activity_log", []))
	discovered = d.get("discovered", {})
	load_progress(d.get("progress", {}))
	location = d.get("location", {}) if d.get("location") is Dictionary else {}
	deferred = d.get("deferred", []) if d.get("deferred") is Array else []
	music = d.get("music", {}) if d.get("music") is Dictionary else {}
	explored = d.get("explored", {}) if d.get("explored") is Dictionary else {}


## Restores progression with JSON floats turned back into ints where they are counters.
func load_progress(p: Dictionary) -> void:
	progress.merge(p, true)
	progress.level = int(progress.get("level", 1))
	# the game stopped mid-transformation: she wakes in the form she was taking (it was already earned)
	if String(progress.get("pending_form", "")) != "":
		progress["appearance"] = String(progress.pending_form)
		progress.erase("pending_form")
	progress.xp = float(progress.get("xp", 0.0))
	for k in ["awarded", "repeats", "gates"]:
		if not progress.get(k) is Dictionary:
			progress[k] = {}
	for k in ["forms_unlocked", "orbits"]:
		if not progress.get(k) is Array:
			progress[k] = []
	for k in progress.repeats:
		progress.repeats[k] = int(progress.repeats[k])
