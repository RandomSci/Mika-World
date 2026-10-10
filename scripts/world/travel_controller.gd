class_name TravelController
extends Node
## Journeys between locations. Within an area → navigation. Across areas → walk to the gate of
## the next area on the registry route (that area preloads while she walks), cross through a
## masked streaming transition, repeat. "fast" travel jumps directly (masked travel card) but only
## along routes whose areas have all been visited before. Player-driven gate crossings and
## proximity preloading also live here.

signal journey_event(ev: Dictionary)

const PRELOAD_DISTANCE := 22.0
const GATE_COOLDOWN := 2.0

var streaming: WorldStreamingManager
var character: WorldCharacter
var journey := {}            # active journey: {destination, route, hop, mode, started}
var _cooldown_until := 0.0


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
		journey.phase = "final_approach"
		character.navigate_to(target, journey.mode != "walk_slow")
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
	journey.phase = "to_gate:" + next_area
	journey.next_area = next_area
	# walk to the gate's approach point (the walkable spot just outside it), then cross
	character.navigate_to((gate.arrive as Transform3D).origin, true)


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
	if not active() or action != "navigate_to":
		return
	var phase: String = journey.get("phase", "")
	if phase == "final_approach":
		_finish(ok, detail)
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
		if active() or now < _cooldown_until or character.current_action != "idle":
			continue
		if d < g.radius and absf(p.y - gp.y) < 3.0 and Vector3(character.velocity.x, 0, character.velocity.z).length() > 0.3:
			_player_cross(n)
			return


func _player_cross(to_area: String) -> void:
	_cooldown_until = Time.get_ticks_msec() / 1000.0 + 1000.0
	var report := await streaming.travel(to_area, character)
	journey_event.emit({"event": "player_crossed", "to": to_area, "ok": report.get("ok", false), "transition": report})
	_cooldown_until = Time.get_ticks_msec() / 1000.0 + GATE_COOLDOWN
