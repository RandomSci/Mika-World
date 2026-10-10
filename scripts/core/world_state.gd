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

var registry := {}
var regions := {}
var areas := {}
var locations := {}
var landmarks := {}
var adjacency := {}       # area -> {neighbour_area: route description}

var night := false
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
var sanctuary := {}              # data/sanctuary.json: sub-areas, lore, trials, ranks, actions, thoughts
var trials_done := {}            # trial id -> true
var npc_state := {}              # traveller id -> {met, visits, relationship, taught, knows_from_mika, used_beats, memories}
var _prefix_counts := {}         # activity prefix -> distinct activity ids done


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
	for a in areas:
		adjacency.get_or_add(a, {})
	discovered_locations[registry.start_location] = true
	var sf := FileAccess.open("res://data/sanctuary.json", FileAccess.READ)
	if sf:
		sanctuary = JSON.parse_string(sf.get_as_text())


func area_of(location_id: String) -> String:
	return locations[location_id].area if locations.has(location_id) else ""


func locations_in_area(area_id: String) -> Array:
	return locations.keys().filter(func(l): return locations[l].area == area_id)


## Shortest chain of areas (inclusive) from `from_area` to `to_area`; [] if unreachable.
func route(from_area: String, to_area: String) -> Array:
	if from_area == to_area:
		return [from_area]
	var prev := {from_area: ""}
	var queue := [from_area]
	while not queue.is_empty():
		var a: String = queue.pop_front()
		for n in adjacency.get(a, {}):
			if not prev.has(n):
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


## Apply an activity's effects and return a truthful description of what changed.
func record_activity(activity: Dictionary, effects: Dictionary) -> Dictionary:
	var changes := {}
	for k in effects.get("knowledge", {}):
		var before = knowledge.get(k, 0)
		var v = effects.knowledge[k]
		knowledge[k] = (before + v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(before) in [TYPE_INT, TYPE_FLOAT] else v
		changes["knowledge." + k] = [before, knowledge[k]]
	for k in effects.get("items", {}):
		var before: int = inventory.get(k, 0)
		inventory[k] = before + int(effects.items[k])
		changes["inventory." + k] = [before, inventory[k]]
	for k in effects.get("skills", {}):
		var before: float = skills.get(k, 0)
		skills[k] = before + float(effects.skills[k])
		changes["skills." + k] = [before, skills[k]]
	for loc in effects.get("discover", []):
		if not discovered_locations.has(loc):
			discover("location", loc)
			changes["discovered." + loc] = [false, true]
	var rank_before := mage_rank()
	for tr in _update_trials(String(activity.get("id", ""))):
		changes["trial." + tr.id] = [false, true]
	if mage_rank() != rank_before:
		changes["rank"] = [rank_before, mage_rank()]
		rank_changed.emit(mage_rank())
	var entry := {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "location": current_location, "activity": activity, "changes": changes}
	activity_log.append(entry)
	state_changed.emit(entry)
	return changes


func location_summary(id: String) -> Dictionary:
	var l: Dictionary = locations[id]
	return {"id": id, "name": l.name, "region": l.region, "area": l.area, "status": l.status,
		"playable": is_playable(id), "discovered": discovered_locations.has(id), "visits": visited_locations.get(id, 0),
		"current": id == current_location, "loaded": l.area == current_area}


func snapshot() -> Dictionary:
	return {"current_area": current_area, "current_location": current_location, "night": night,
		"skills": skills, "knowledge": knowledge, "inventory": inventory, "goal": current_goal,
		"discovered": discovered_locations.keys(), "visited": visited_locations, "landmarks_seen": seen_landmarks.keys(),
		"activities_done": activity_log.size(), "rank": mage_rank(), "trials_done": trials_done.keys()}


# ------------------------------------------------------------------ Sanctuary mission (Path of the Mage)
func _update_trials(activity_id: String) -> Array:
	var newly := []
	for tr in sanctuary.get("trials", []):
		if trials_done.has(tr.id):
			continue
		var done := false
		if tr.has("activity") and tr.activity == activity_id:
			done = true
		elif tr.has("activity_prefix") and activity_id.begins_with(tr.activity_prefix):
			var seen: Dictionary = _prefix_counts.get_or_add(tr.activity_prefix, {})
			seen[activity_id] = true
			done = seen.size() >= int(tr.count)
		if done:
			trials_done[tr.id] = true
			newly.append(tr)
			trial_completed.emit(tr)
	return newly


func mage_rank() -> String:
	var rank := "Novice"
	for r in sanctuary.get("ranks", []):
		if trials_done.size() >= int(r.trials) and float(skills.get("arcane_orb", 0.0)) >= float(r.get("min_skill", 0.0)):
			rank = r.name
	return rank


func mission_state() -> Dictionary:
	var trials := []
	for tr in sanctuary.get("trials", []):
		var t := {"id": tr.id, "name": tr.name, "done": trials_done.has(tr.id)}
		if tr.has("activity_prefix"):
			t["progress"] = "%d/%d" % [_prefix_counts.get(tr.activity_prefix, {}).size(), int(tr.count)]
		trials.append(t)
	var next_rank := ""
	for r in sanctuary.get("ranks", []):
		if trials_done.size() < int(r.trials):
			next_rank = "%s (%d trials)" % [r.name, int(r.trials)]
			break
	return {"mission": sanctuary.get("story", {}).get("mission", ""), "rank": mage_rank(), "next_rank": next_rank,
		"trials_done": trials_done.size(), "trials_total": sanctuary.get("trials", []).size(), "trials": trials}
