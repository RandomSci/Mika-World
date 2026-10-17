class_name TravelController
extends Node
## Journeys between locations. Within an area → navigation. Across areas → walk to the gate of
## the next area on the registry route (that area preloads while she walks), cross through a
## masked streaming transition, repeat. There is NO instant travel in production (V3 continuation: "Teleportation is
## forbidden in normal production gameplay ... No free instant region travel"): mode "fast" is a developer utility,
## refused unless the game was started with --dev-fast-travel (tests / scene loading), and never offered to a mage. Player-driven gate crossings and
## proximity preloading also live here.

signal journey_event(ev: Dictionary)

const PRELOAD_DISTANCE := 22.0
const GATE_COOLDOWN := 2.0

var streaming: WorldStreamingManager
var character: WorldCharacter
var journey := {}            # active journey: {destination, route, hop, mode, started}
var _cooldown_until := 0.0


## Developer-only (scene loading in tests and tools); never available in a normal run.
static func dev_fast_travel() -> bool:
	return RenderProfile.options.has("dev-fast-travel")


func active() -> bool:
	return not journey.is_empty()


func status() -> Dictionary:
	return {"journey": journey.duplicate(), "streaming": streaming.state, "current_area": streaming.current_id}


## Start a journey to a registry location. Returns an immediate {ok, ...} verdict; progress and the
## final truthful result arrive as journey_event signals ("journey_finished").
func travel_to(location_id: String, mode := "walk") -> Dictionary:
	if not WorldState.locations.has(location_id):
		return {"ok": false, "error": "unknown location '%s'" % location_id}
	if not WorldState.is_playable(location_id):
		return {"ok": false, "error": "'%s' is not playable yet (status: %s)" % [location_id, WorldState.locations[location_id].status]}
	if active():
		return {"ok": false, "error": "already travelling to " + journey.destination}
	if character.casting:
		return {"ok": false, "error": "busy casting"}
	var dest_area := WorldState.area_of(location_id)
	var path := WorldState.route(streaming.current_id, dest_area)
	if path.is_empty():
		return {"ok": false, "error": "no known route from %s to %s" % [streaming.current_id, dest_area]}
	if mode == "fast" and not dev_fast_travel():
		return {"ok": false, "error": "there is no instant travel: Mika and Luna must walk (teleportation is an unlearned spatial art)"}
	if mode == "fast":
		for a in path.slice(1, path.size() - 1):
			if not _area_visited(a):
				return {"ok": false, "error": "fast travel needs a known route; '%s' has not been visited yet" % a}
	journey = {"destination": location_id, "destination_area": dest_area, "route": path, "hop": 0, "mode": mode,
		"started": Time.get_ticks_msec(), "transitions": []}
	WorldState.current_goal = "travel:" + location_id
	journey_event.emit({"event": "journey_started", "destination": location_id, "route": path, "mode": mode})
	_advance()
	return {"ok": true, "status": "started", "route": path, "mode": mode, "hops": path.size() - 1}


func cancel(reason := "cancelled") -> void:
	if active():
		_finish(false, reason)


func _area_visited(area_id: String) -> bool:
	for l in WorldState.locations_in_area(area_id):
		if WorldState.visited_locations.has(l):
			return true
	return false


func _advance() -> void:
	if not active():
		return
	var path: Array = journey.route
	var here := streaming.current_id
	if streaming.current == null:
		_finish(false, "no area loaded")
		return
	if here == journey.destination_area:
		var target: Vector3 = streaming.current.points_of_interest[journey.destination].position
		# a freshly built area's navmesh answers an empty path for a few physics frames after its bake (Day 2: the
		# walk from the library stairs to its centre started on that and was "stuck" at once - wait for a real path)
		var map := character.get_world_3d().navigation_map
		var has_path := func() -> bool:
			return not NavigationServer3D.map_get_path(map, character.global_position, NavigationServer3D.map_get_closest_point(map, target), true).is_empty()
		for i in 90:
			if has_path.call():
				break
			await get_tree().physics_frame
		if not has_path.call() and streaming.current and streaming.current.has_method("bake_navigation"):
			# still no path on a freshly loaded area's navmesh (seen in the Ancient Spell Library: every query empty for
			# the whole visit in some loads): bake it once more and wait for it to answer
			print("[travel] %s: no path from the arrival to %s - re-baking its navigation" % [here, journey.destination])
			await streaming.current.bake_navigation()
			for i in 90:
				if has_path.call():
					break
				await get_tree().physics_frame
			print("[travel] %s: after the re-bake a path %s" % [here, "exists" if has_path.call() else "STILL missing"])
		if not active():
			return
		character.navigate_to(target, false)      # a journey is walked (never a dash)
		journey.phase = "final_approach"
		if character.current_action != "navigate_to":
			_finish(false, "final approach refused: " + character.last_rejection)
		return
	var idx := path.find(here)
	if idx < 0:
		_finish(false, "left the planned route (now in %s)" % here)
		return
	var next_area: String = path[idx + 1]
	if journey.mode == "fast":
		journey.phase = "fast_travel"
		_cross(path.back())
		return
	streaming.preload_area(next_area)  # predictive: loads while she walks to the gate
	var gate: Dictionary = streaming.current.gates.get(next_area, {})
	if gate.is_empty():
		_finish(false, "area %s has no gate to %s" % [here, next_area])
		return
	journey.next_area = next_area
	# walk to the walkable point closest to the gate (approach), then cross
	var map := character.get_world_3d().navigation_map
	var approach := NavigationServer3D.map_get_closest_point(map, gate.position)
	if approach.distance_to(gate.position) > 6.0:
		approach = NavigationServer3D.map_get_closest_point(map, (gate.arrive as Transform3D).origin)
	character.navigate_to(approach, false)
	journey.phase = "to_gate:" + next_area
	if character.current_action != "navigate_to":
		_finish(false, "gate approach refused: " + character.last_rejection)


func _cross(to_area: String) -> void:
	var report := await streaming.travel(to_area, character)
	if not active():
		return
	if not report.get("ok", false):
		_finish(false, "transition failed: " + str(report.get("reason", "?")))
		return
	journey.transitions.append({"to": to_area, "total_ms": report.total_ms, "build_ms": report.build_ms, "nav_bake_ms": report.nav_bake_ms})
	journey_event.emit({"event": "journey_progress", "arrived_area": to_area, "location": WorldState.current_location, "transition": report})
	_cooldown_until = Time.get_ticks_msec() / 1000.0 + GATE_COOLDOWN
	await get_tree().create_timer(0.3).timeout
	_advance()


## Called by main when the character finishes a navigate_to (from the action_finished signal).
func on_character_action(action: String, ok: bool, detail: String) -> void:
	if not active() or action != "navigate_to" or detail.begins_with("superseded"):
		return  # a "superseded" result belongs to an older navigation, not this journey's
	var phase: String = journey.get("phase", "")
	if phase == "final_approach":
		var target: Vector3 = streaming.current.points_of_interest[journey.destination].position
		var miss := Vector2(character.global_position.x - target.x, character.global_position.z - target.z).length()
		_finish(ok or miss <= 2.5, detail if ok else "%s; within %.1f m of the location marker" % [detail, miss])
	elif phase.begins_with("to_gate:"):
		var gate: Dictionary = streaming.current.gates.get(journey.next_area, {})
		var near := not gate.is_empty() and character.global_position.distance_to(gate.position) < 8.0
		if ok or near:
			_cross(journey.next_area)
		else:
			_finish(false, "could not reach the gate: " + detail)


func _finish(ok: bool, detail: String) -> void:
	var j := journey
	journey = {}
	WorldState.current_goal = ""
	journey_event.emit({"event": "journey_finished", "ok": ok, "detail": detail, "destination": j.get("destination", ""),
		"location": WorldState.current_location, "area": streaming.current_id, "seconds": (Time.get_ticks_msec() - j.get("started", 0)) / 1000.0,
		"transitions": j.get("transitions", [])})


# ------------------------------------------------------------------ player-driven gates + proximity preloading
func _physics_process(_delta: float) -> void:
	if streaming.current == null or streaming.state != "idle" or character == null:
		return
	var p := character.global_position
	var now := Time.get_ticks_msec() / 1000.0
	for n in streaming.current.gates:
		var g: Dictionary = streaming.current.gates[n]
		var gp: Vector3 = g.position
		var d := Vector2(p.x - gp.x, p.z - gp.z).length()
		if d < PRELOAD_DISTANCE:
			streaming.preload_area(n)
		if active() or now < _cooldown_until or character.current_action != "idle" or WorldState.is_sealed(streaming.current_id, n):
			continue
		if d < g.radius and absf(p.y - gp.y) < 3.0 and Vector3(character.velocity.x, 0, character.velocity.z).length() > 0.3:
			_player_cross(n)
			return


func _player_cross(to_area: String) -> void:
	_cooldown_until = Time.get_ticks_msec() / 1000.0 + 1000.0
	var report := await streaming.travel(to_area, character)
	journey_event.emit({"event": "player_crossed", "to": to_area, "ok": report.get("ok", false), "transition": report})
	_cooldown_until = Time.get_ticks_msec() / 1000.0 + GATE_COOLDOWN
