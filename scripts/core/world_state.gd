extends Node
## Authoritative world registry + persistent world/character state (autoload "WorldState").
## The registry (data/world.json) says what exists; this node tracks what Mika has discovered,
## visited and done. Areas, the streaming manager and the AI bridge all read from here so the
## engine — not the AI — decides what is real, reachable, loaded or unfinished.

signal location_entered(location_id: String)
signal discovered(kind: String, id: String)
signal state_changed(change: Dictionary)
signal trial_completed(trial: Dictionary)
signal rank_changed(rank: String)
signal interaction_started(interactable: Node, character: Node)
signal interaction_finished(interactable: Node, character: Node, result: Dictionary)
## Per-mage progress events: kind = "trial" | "rank" | "activity" (data = the trial / rank / log entry).
signal mage_event(who: String, kind: String, data: Variant)

var registry := {}
var regions := {}
var areas := {}
var locations := {}
var landmarks := {}
var adjacency := {}       # area -> {neighbour_area: route description}
var sealed := {}               # "a|b" -> why: connections that exist but cannot be travelled (no free teleportation)

var night := false
var habitats := {}            # Milestone K8: per-area habitat state (defeats, depletion), persisted
var play_s := 0.0             # accumulated game seconds across sessions (habitat recovery clocks)
## THE WORLD CLOCK (V3 continuation: travel takes days; the world goes on while nobody watches).
## world_min counts world minutes since the first dawn (day 1, 06:00 = 360). It runs at `clock_rate` world minutes per
## real second (data/world.json "clock"); journeys on the road run it faster (the time really passes on the road), and
## on a restart it catches up on the real time that passed while the game was closed (capped).
var world_min := 360.0
var clock_rate := 0.5
var clock_boost := 1.0            # > 1 while a journey's road time passes (set by the JourneyDirector)
var clock_catch_up := {}          # what the last load caught up: {real_s, world_min}
signal hour_changed(day: int, hour: int)
var _last_hour := -1
var current_area := ""
var current_location := ""
var discovered_locations := {}   # id -> true
var visited_locations := {}      # id -> visit count
var seen_landmarks := {}         # id -> true
var activity_log: Array[Dictionary] = []
var knowledge := {}              # e.g. {"spell:arcane_orb": 1.0, "lore:...": true}
var inventory := {}              # item -> count
var skills := {"arcane_orb": 1}  # known spells and their practice level
var current_goal := ""
var journey := {}                # the party's multi-day journey (JourneyDirector): persisted, resumed after restarts
var rivals := {}                 # human rivals met on the road (AmbushDirector): who, how often, how it ended, grudges
var weather := {}              # WeatherSystem: {kind, intensity, until (world_min), next}
var sanctuary := {}              # data/sanctuary.json: sub-areas, lore, trials, ranks, actions, thoughts
var trials_done := {}            # trial id -> true
var npc_state := {}              # traveller id -> {met, visits, relationship, taught, knows_from_mika, used_beats, memories}
var story_state := {}            # StoryManager: {found: {clue: unix}, stage}
var activity_counts := {}        # activity kind / id -> {count, last_unix}
var activity_seq := 0            # monotonic id of the last activity_log entry (survives log trimming and restarts)
const ACTIVITY_LOG_MAX := 1000   # in-memory log length (the save keeps the last 200; readers use "seq", never indices)
const SAVE_PATH := "user://mika_world_save.json"
var save_path := SAVE_PATH       # --save-path=user://name.json (tests use their own file, never the real save)
const SAVE_VERSION := 1
var persistent := false          # true when this run loads/saves (normal play); tests run ephemeral
var _dirty := false
var _save_timer := 0.0
var _prefix_counts := {}         # activity prefix -> distinct activity ids done
## Every mage's private state. "mika" is a live view onto the fields above; others own their data.
var minds := {}
var _saved_agents := {}          # loaded "agents" save data, applied when that mage's mind is registered


func _init() -> void:
	var f := FileAccess.open("res://data/world.json", FileAccess.READ)
	registry = JSON.parse_string(f.get_as_text())
	regions = registry.regions
	areas = registry.areas
	locations = registry.locations
	landmarks = registry.landmarks
	for c in registry.connections:
		adjacency.get_or_add(c[0], {})[c[1]] = c[2]
		adjacency.get_or_add(c[1], {})[c[0]] = c[2]
		if c.size() > 3 and bool((c[3] as Dictionary).get("sealed", false)):
			sealed[c[0] + "|" + c[1]] = String(c[3].get("why", "sealed"))
			sealed[c[1] + "|" + c[0]] = String(c[3].get("why", "sealed"))
	for a in areas:
		adjacency.get_or_add(a, {})
	discovered_locations[registry.start_location] = true
	var sf := FileAccess.open("res://data/sanctuary.json", FileAccess.READ)
	if sf:
		sanctuary = JSON.parse_string(sf.get_as_text())
	minds["mika"] = MageMind.create("mika", true)


## The mind of mage `who` (registered by main when the mage is spawned). Unknown ids fall back to Mika.
func mind(who := "mika") -> MageMind:
	return minds.get(who, minds["mika"])


## Register a non-legacy mage; restores her saved state if the save had one.
func register_mind(who: String, starting_skills := {}) -> MageMind:
	if minds.has(who):
		return minds[who]
	var m := MageMind.create(who, false, starting_skills)
	if _saved_agents.has(who):
		m.from_dict(_saved_agents[who])
	minds[who] = m
	return m


const _TEST_FLAGS := ["fresh", "physicstest", "posetest", "magictest", "readtest", "alchemytest", "audiotest", "lifetest",
	"storytest", "brainrun", "sanctuarytour", "worldtour", "facetest", "tour", "mock-commands", "viewertest", "chattest", "perfrun",
	"persisttest", "mhtest", "mitest", "mjtest", "mktest", "outfittest", "transformvideo", "qareel"]


func _ready() -> void:
	persistent = true
	for f in _TEST_FLAGS:
		if RenderProfile.options.has(f):
			persistent = false
	if RenderProfile.options.has("persist"):
		persistent = true
	var sp := String(RenderProfile.options.get("save-path", ""))
	if sp.begins_with("user://") and sp.ends_with(".json") and not sp.contains(".."):
		save_path = sp
	if persistent:
		load_game()
	state_changed.connect(func(_e): _dirty = true)


func _process(delta: float) -> void:
	play_s += delta
	world_min += delta * clock_rate * clock_boost
	var h := int(world_min / 60.0)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(day(), hour())
	if not persistent:
		return
	_save_timer += delta
	if _dirty and _save_timer > 2.0:
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if persistent and _dirty:
			save_game()


## Save integrity:
##  * the file is written to <save>.tmp, read back and parsed, and only then renamed over the save;
##  * before overwriting, the previous good save is rotated into <save>.bak1..BACKUP_COUNT (at most one
##    rotation per BACKUP_INTERVAL_S, and always once per session, so autosaves don't churn backups);
##  * a save that cannot be read (corrupt / missing fields / wrong version) is never overwritten: it is
##    preserved as <save>.unreadable-<unix>.json and the newest readable backup is restored instead;
##  * a save NEWER than this build understands disables saving for the session (nothing is clobbered);
##  * progress only grows (knowledge, trials, discoveries are never removed), so a write that would hold
##    less of it than what was loaded is refused as a sign of an accidental reset.
const BACKUP_COUNT := 5
const BACKUP_INTERVAL_S := 600.0
const _REQUIRED_KEYS := ["discovered_locations", "visited_locations", "seen_landmarks", "knowledge", "inventory", "skills", "trials_done"]
var load_report := {}            # what load_game found and did (for tests, the bridge and the log)
var _loaded_floor := {}          # progress sizes at load time: saves never go below these
var _last_rotation := -1e12


func save_data() -> Dictionary:
	return {"version": SAVE_VERSION, "saved_unix": int(Time.get_unix_time_from_system()),
		"discovered_locations": discovered_locations, "visited_locations": visited_locations, "seen_landmarks": seen_landmarks,
		"knowledge": knowledge, "inventory": inventory, "skills": skills, "trials_done": trials_done, "prefix_counts": _prefix_counts,
		"npc_state": npc_state, "story_state": story_state, "activity_counts": activity_counts, "activity_seq": activity_seq, "activity_log": activity_log.slice(maxi(0, activity_log.size() - 200)),
		"progress": minds["mika"].progress, "agents": _agents_data(),
		"mika_location": minds["mika"].location, "mika_music": minds["mika"].music, "mika_deferred": minds["mika"].deferred,
		"mika_explored": minds["mika"].explored, "habitats": habitats, "play_s": play_s, "world_min": world_min,
		"journey": journey, "rivals": rivals, "weather": weather}


func _agents_data() -> Dictionary:
	var out := _saved_agents.duplicate()       # keep mages not spawned this session
	for who in minds:
		if not (minds[who] as MageMind).legacy:
			out[who] = (minds[who] as MageMind).to_dict()
	return out


func save_game() -> bool:
	_dirty = false
	_save_timer = 0.0
	var d := save_data()
	for k in _loaded_floor:
		if k.begins_with("agent:"):
			var who: String = String(k).trim_prefix("agent:")
			if (d.agents.get(who, {}).get("knowledge", {}) as Dictionary).size() < int(_loaded_floor[k]):
				push_warning("[save] refused: %s's knowledge would shrink (state reset?); %s left untouched" % [who, save_path])
				return false
			continue
		if (d[k] as Dictionary).size() < int(_loaded_floor[k]):
			push_warning("[save] refused: %s would shrink from %d to %d entries (state reset?); %s left untouched" % [k, _loaded_floor[k], (d[k] as Dictionary).size(), save_path])
			return false
	var text := JSON.stringify(d)
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("[save] cannot write %s" % tmp)
		return false
	f.store_string(text)
	f.close()
	var check := _read_save(tmp)
	if not check.ok or (check.data.knowledge as Dictionary).size() != knowledge.size():
		push_warning("[save] written file failed verification (%s); %s left untouched" % [check.get("why", "size mismatch"), save_path])
		return false
	_rotate_backups()
	var err := DirAccess.rename_absolute(_abs(tmp), _abs(save_path))
	if err != OK:
		push_warning("[save] could not replace %s (%s)" % [save_path, error_string(err)])
		return false
	return true


func load_game() -> bool:
	load_report = {"path": save_path, "found": FileAccess.file_exists(save_path)}
	if not load_report.found:
		return false
	var r := _read_save(save_path)
	if not r.ok and r.get("newer", false):
		persistent = false
		load_report["result"] = "save is from a newer version (%s): loaded nothing, saving disabled this session" % r.why
		push_warning("[save] " + load_report.result)
		return false
	if not r.ok:
		var kept := "%s.unreadable-%d.json" % [_base(), int(Time.get_unix_time_from_system())]
		DirAccess.rename_absolute(_abs(save_path), _abs(kept))
		load_report["unreadable"] = r.why
		load_report["preserved_as"] = kept
		push_warning("[save] %s is unreadable (%s); preserved as %s" % [save_path, r.why, kept])
		r = {}
		for i in range(1, BACKUP_COUNT + 1):
			var b := _backup_path(i)
			var rb := _read_save(b) if FileAccess.file_exists(b) else {"ok": false}
			if rb.ok:
				r = rb
				load_report["restored_from"] = b
				DirAccess.copy_absolute(_abs(b), _abs(save_path))
				push_warning("[save] restored progress from backup %s" % b)
				break
		if r.is_empty():
			load_report["result"] = "no readable backup: starting fresh (the unreadable file is kept)"
			push_warning("[save] " + load_report.result)
			return false
	_apply_save(r.data)
	_loaded_floor = {"knowledge": knowledge.size(), "trials_done": trials_done.size(), "discovered_locations": discovered_locations.size()}
	for who in _saved_agents:
		_loaded_floor["agent:" + who] = (_saved_agents[who].get("knowledge", {}) as Dictionary).size()
	load_report["result"] = "loaded"
	load_report["knowledge"] = knowledge.size()
	load_report["trials"] = trials_done.size()
	print("[save] loaded progress from %s (%d knowledge entries, %d trials)%s" % [save_path, knowledge.size(), trials_done.size(),
		(" [restored from %s]" % load_report.restored_from) if load_report.has("restored_from") else ""])
	return true


func _apply_save(d: Dictionary) -> void:
	discovered_locations = d.discovered_locations
	visited_locations = d.visited_locations
	seen_landmarks = d.seen_landmarks
	knowledge = d.knowledge
	inventory = d.inventory
	skills = d.skills
	trials_done = d.trials_done
	_prefix_counts = d.get("prefix_counts", {})
	npc_state = d.get("npc_state", {})
	story_state = d.get("story_state", {})
	habitats = d.get("habitats", {})
	play_s = float(d.get("play_s", 0.0))
	world_min = float(d.get("world_min", world_min))
	journey = d.get("journey", {})
	rivals = d.get("rivals", {})
	weather = d.get("weather", {})
	# the world went on while the game was closed: catch up (capped at a week), journeys included (JourneyDirector)
	var away_s := maxf(0.0, Time.get_unix_time_from_system() - float(d.get("saved_unix", Time.get_unix_time_from_system())))
	var add := minf(away_s * clock_rate, 7.0 * 1440.0)
	world_min += add
	clock_catch_up = {"real_s": int(away_s), "world_min": snappedf(add, 0.1)}
	activity_counts = d.get("activity_counts", {})
	activity_log.assign(d.get("activity_log", []))
	activity_seq = int(d.get("activity_seq", 0))
	if not d.has("activity_seq"):
		# saves before "seq" existed: entries are numbered by position and journal_cursor was a position,
		# so position i == seq i+1 and the cursor keeps its meaning. A cursor beyond the (trimmed) log is
		# clamped: those events were older than anything kept, so they count as already considered.
		for i in activity_log.size():
			activity_log[i]["seq"] = i + 1
		activity_seq = activity_log.size()
		if knowledge.has("journal_cursor"):
			knowledge["journal_cursor"] = mini(int(knowledge.journal_cursor), activity_seq)
	for e in activity_log:
		e["seq"] = int(e.get("seq", 0))
	if knowledge.has("journal_cursor"):
		knowledge["journal_cursor"] = int(knowledge.journal_cursor)
	minds["mika"].load_progress(d.get("progress", {}))
	minds["mika"].location = d.get("mika_location", {}) if d.get("mika_location") is Dictionary else {}
	minds["mika"].music = d.get("mika_music", {}) if d.get("mika_music") is Dictionary else {}
	minds["mika"].deferred = d.get("mika_deferred", []) if d.get("mika_deferred") is Array else []
	minds["mika"].explored = d.get("mika_explored", {}) if d.get("mika_explored") is Dictionary else {}
	_saved_agents = d.get("agents", {}) if d.get("agents") is Dictionary else {}
	for who in _saved_agents:
		if minds.has(who) and not (minds[who] as MageMind).legacy:
			(minds[who] as MageMind).from_dict(_saved_agents[who])


## {ok, data} or {ok: false, why, newer?}. Never prints parser errors.
func _read_save(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {"ok": false, "why": "empty or unreadable file"}
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"ok": false, "why": "invalid JSON at line %d: %s" % [j.get_error_line(), j.get_error_message()]}
	var d = j.data
	if not d is Dictionary:
		return {"ok": false, "why": "not a save object"}
	var v := int(d.get("version", 0))
	if v > SAVE_VERSION:
		return {"ok": false, "why": "version %d > %d" % [v, SAVE_VERSION], "newer": true}
	if v != SAVE_VERSION:
		return {"ok": false, "why": "unsupported version %d" % v}
	for k in _REQUIRED_KEYS:
		if not d.get(k) is Dictionary:
			return {"ok": false, "why": "missing or invalid '%s'" % k}
	return {"ok": true, "data": d}


func _rotate_backups() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_rotation < BACKUP_INTERVAL_S or not FileAccess.file_exists(save_path):
		return
	if not _read_save(save_path).ok:
		return   # never rotate a bad file into the backups (load_game already preserved any unreadable save)
	_last_rotation = now
	for i in range(BACKUP_COUNT, 1, -1):
		if FileAccess.file_exists(_backup_path(i - 1)):
			DirAccess.rename_absolute(_abs(_backup_path(i - 1)), _abs(_backup_path(i)))
	DirAccess.copy_absolute(_abs(save_path), _abs(_backup_path(1)))


func _base() -> String:
	return save_path.trim_suffix(".json")


func _backup_path(i: int) -> String:
	return "%s.bak%d.json" % [_base(), i]


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func note_activity(kind: String, who := "mika") -> void:
	mind(who).note_activity(kind)
	_dirty = true


func area_of(location_id: String) -> String:
	return locations[location_id].area if locations.has(location_id) else ""


func locations_in_area(area_id: String) -> Array:
	return locations.keys().filter(func(l): return locations[l].area == area_id)


## Shortest chain of areas (inclusive) from `from_area` to `to_area`; [] if unreachable.
## A connection that exists in the world but cannot be used (the dormant ley-line gate: no free teleportation).
func is_sealed(a: String, b: String) -> bool:
	return sealed.has(a + "|" + b)


func route(from_area: String, to_area: String) -> Array:
	if from_area == to_area:
		return [from_area]
	var prev := {from_area: ""}
	var queue := [from_area]
	while not queue.is_empty():
		var a: String = queue.pop_front()
		for n in adjacency.get(a, {}):
			if not prev.has(n) and not is_sealed(a, n):
				prev[n] = a
				if n == to_area:
					var path := [n]
					while prev[path[0]] != "":
						path.push_front(prev[path[0]])
					return path
				queue.append(n)
	return []


func is_playable(location_id: String) -> bool:
	return locations.has(location_id) and locations[location_id].status == "playable" \
		and ResourceLoader.exists(areas[locations[location_id].area].scene)


func enter_location(location_id: String) -> void:
	if location_id == "" or location_id == current_location:
		return
	current_location = location_id
	visited_locations[location_id] = visited_locations.get(location_id, 0) + 1
	discover("location", location_id)
	location_entered.emit(location_id)


func discover(kind: String, id: String) -> void:
	var store := discovered_locations if kind == "location" else seen_landmarks
	if not store.has(id):
		store[id] = true
		discovered.emit(kind, id)
		# seeing a destination landmark makes its location known (but not visited)
		if kind == "landmark" and landmarks.get(id, {}).get("kind") == "destination":
			discover("location", landmarks[id].location)


## Apply an activity's effects to the mind of mage `who` and return a truthful description of what changed.
func record_activity(activity: Dictionary, effects: Dictionary, who := "mika") -> Dictionary:
	var m := mind(who)
	var changes := {}
	for k in effects.get("knowledge", {}):
		var before = m.knowledge.get(k, 0)
		var v = effects.knowledge[k]
		m.knowledge[k] = (before + v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(before) in [TYPE_INT, TYPE_FLOAT] else v
		changes["knowledge." + k] = [before, m.knowledge[k]]
	for k in effects.get("items", {}):
		var before: int = int(m.inventory.get(k, 0))
		m.inventory[k] = before + int(effects.items[k])
		changes["inventory." + k] = [before, m.inventory[k]]
	for k in effects.get("skills", {}):
		var before: float = float(m.skills.get(k, 0))
		m.skills[k] = before + float(effects.skills[k])
		changes["skills." + k] = [before, m.skills[k]]
	for loc in effects.get("discover", []):
		if m.legacy:
			if not discovered_locations.has(loc):
				discover("location", loc)
				changes["discovered." + loc] = [false, true]
		elif not m.discovered.has(loc):
			m.discovered[loc] = true
			changes["discovered." + loc] = [false, true]
	var rank_before := mage_rank(who)
	for tr in _update_trials(String(activity.get("id", "")), String(activity.get("target", "")), who):
		changes["trial." + tr.id] = [false, true]
	if mage_rank(who) != rank_before:
		changes["rank"] = [rank_before, mage_rank(who)]
		if m.legacy:
			rank_changed.emit(mage_rank(who))
		mage_event.emit(who, "rank", mage_rank(who))
	m.activity_seq += 1
	var entry := {"seq": m.activity_seq, "unix": int(Time.get_unix_time_from_system()), "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01),
		"location": current_location, "activity": activity, "changes": changes, "who": who}
	m.activity_log.append(entry)
	if m.activity_log.size() > ACTIVITY_LOG_MAX:
		m.activity_log = m.activity_log.slice(m.activity_log.size() - ACTIVITY_LOG_MAX)
	if m.legacy:
		state_changed.emit(entry)     # Mika's story, audio, bridge listeners (unchanged)
	else:
		_dirty = true
	mage_event.emit(who, "activity", entry)
	return changes


func location_summary(id: String) -> Dictionary:
	var l: Dictionary = locations[id]
	return {"id": id, "name": l.name, "region": l.region, "area": l.area, "status": l.status,
		"playable": is_playable(id), "discovered": discovered_locations.has(id), "visits": visited_locations.get(id, 0),
		"current": id == current_location, "loaded": l.area == current_area}


func game_time() -> float:
	return play_s


## Day number (1 = the first day) and the hour of the day (0-23) / fractional hour.
func day() -> int:
	return int(world_min / 1440.0) + 1


func hour() -> int:
	return int(fmod(world_min, 1440.0) / 60.0)


func hour_f() -> float:
	return fmod(world_min, 1440.0) / 60.0


func clock_text() -> String:
	var m := int(fmod(world_min, 60.0))
	return "Day %d, %02d:%02d" % [day(), hour(), m]


## How light it is outside: 0 at night, 1 in full day, eased through dawn (05:00-07:00) and dusk (18:00-20:00).
func daylight() -> float:
	var h := hour_f()
	if h < 5.0 or h >= 20.0:
		return 0.0
	if h < 7.0:
		return smoothstep(5.0, 7.0, h)
	if h < 18.0:
		return 1.0
	return 1.0 - smoothstep(18.0, 20.0, h)


## Advance the world by `minutes` (a journey's road time, a night's sleep): everything that runs on the clock follows.
func advance_clock(minutes: float) -> void:
	world_min += minutes


func snapshot() -> Dictionary:
	return {"current_area": current_area, "current_location": current_location, "night": night,
		"skills": skills, "knowledge": knowledge, "inventory": inventory, "goal": current_goal,
		"discovered": discovered_locations.keys(), "visited": visited_locations, "landmarks_seen": seen_landmarks.keys(),
		"activities_done": activity_seq, "rank": mage_rank(), "trials_done": trials_done.keys()}


# ------------------------------------------------------------------ Sanctuary mission (Path of the Mage)
## A trial names an activity id (or an id prefix + a count of distinct ids). `target_id` is the object a
## verified spell hit landed on; it only counts for prefix trials about objects (striking rune_target_2
## with a spell is the same deed as the E-key strike), never for exact activities like reading.
func _update_trials(activity_id: String, target_id := "", who := "mika") -> Array:
	var m := mind(who)
	var newly := []
	for tr in sanctuary.get("trials", []):
		if m.trials_done.has(tr.id):
			continue
		var done := false
		if tr.has("activity") and tr.activity == activity_id:
			done = true
		elif tr.has("activity_prefix"):
			for deed in [activity_id, target_id]:
				if deed != "" and deed.begins_with(tr.activity_prefix):
					var seen: Dictionary = m.prefix_counts.get_or_add(tr.activity_prefix, {})
					seen[deed] = true
					done = seen.size() >= int(tr.count)
		if done:
			m.trials_done[tr.id] = true
			newly.append(tr)
			if m.legacy:
				trial_completed.emit(tr)
			mage_event.emit(who, "trial", tr)
	return newly


## Mika's rank keeps its original rule (Arcane Orb practice); other mages use their best-practised spell.
func mage_rank(who := "mika") -> String:
	var m := mind(who)
	var skill: float = float(m.skills.get("arcane_orb", 0.0)) if m.legacy else (float(m.skills.values().max()) if not m.skills.is_empty() else 0.0)
	var rank := "Novice"
	for r in sanctuary.get("ranks", []):
		if m.trials_done.size() >= int(r.trials) and float(skill) >= float(r.get("min_skill", 0.0)):
			rank = r.name
	return rank


func mission_state(who := "mika") -> Dictionary:
	var m := mind(who)
	var trials := []
	for tr in sanctuary.get("trials", []):
		var t := {"id": tr.id, "name": tr.name, "done": m.trials_done.has(tr.id)}
		if tr.has("activity_prefix"):
			t["progress"] = "%d/%d" % [m.prefix_counts.get(tr.activity_prefix, {}).size(), int(tr.count)]
		trials.append(t)
	var next_rank := ""
	for r in sanctuary.get("ranks", []):
		if m.trials_done.size() < int(r.trials):
			next_rank = "%s (%d trials)" % [r.name, int(r.trials)]
			break
	return {"mission": sanctuary.get("story", {}).get("mission", ""), "rank": mage_rank(who), "next_rank": next_rank,
		"trials_done": m.trials_done.size(), "trials_total": sanctuary.get("trials", []).size(), "trials": trials}
