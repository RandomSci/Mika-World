class_name NPCManager
extends Node
## Visiting schedule for the three travellers (data/npcs.json). They are not standing around waiting:
## each has an arrival window after the session starts, a stay length, a cooldown between visits that also
## spans restarts (unix time in WorldState.npc_state), conditions (day-only merchant; the scholar comes
## sooner once Mika has read about the Heartstone's heartbeat), and a real route in and out.
## Visitors only exist while the Sanctuary is the loaded area; leaving the area ends the visit.

const ENTRIES := {"forest_gate": Vector3(1.0, 0.0, -31.0), "east_trail": Vector3(43.0, 0.0, 18.2)}

var main: Node
var present := {}             # id -> TravelerNPC
var _visit_end := {}          # id -> session seconds when they leave
var _session_t := 0.0
var _rng := RandomNumberGenerator.new()
var time_scale := 1.0         # --visitors=fast compresses waiting for tests
var events: Array = []


func setup(m: Node) -> void:
	main = m
	_rng.seed = int(Time.get_unix_time_from_system())
	if String(RenderProfile.options.get("visitors", "")) == "fast":
		time_scale = 0.05
	elif String(RenderProfile.options.get("visitors", "")) == "quick":
		time_scale = 0.25
	if RenderProfile.options.has("no-visitors"):
		set_process(false)


func _due(id: String, t: Dictionary) -> bool:
	var st: Dictionary = main.dialogue.state_of(id)
	var sch: Dictionary = t.schedule
	if sch.get("day_only", false) and WorldState.night:
		return false
	var first: float = float(sch.first_after_s)
	if sch.has("earlier_if") and WorldState.knowledge.has(sch.earlier_if):
		first *= 0.4
	if _session_t < first * time_scale:
		return false
	var next_unix := float(st.get("next_visit_unix", 0))
	return Time.get_unix_time_from_system() >= next_unix


func _process(delta: float) -> void:
	_session_t += delta
	if main.world == null or main.streaming.state != "idle" or main.streaming.current_id != "sanctuary":
		for id in present.keys():
			if not is_instance_valid(present[id]):
				_end(id, "area unloaded")
		return
	for id in present.keys():
		var n = present[id]
		if not is_instance_valid(n):
			_end(id, "left")
		elif _session_t >= float(_visit_end.get(id, 1e12)) and n.state == "idle":
			n.leave()
			_visit_end[id] = 1e12
			events.append({"t": snappedf(_session_t, 0.1), "npc": id, "event": "leaving"})
	if Engine.get_process_frames() % 30 != 0:
		return
	for id in main.dialogue.travellers:
		if present.has(id):
			continue
		var t: Dictionary = main.dialogue.travellers[id]
		if bool(t.get("schedule", {}).get("resident", false)):
			continue   # the Phoenix comes and goes on her own terms (PhoenixManager)
		if _due(id, t):
			arrive(id)
			break   # one arrival at a time


func arrive(id: String) -> TravelerNPC:
	if present.has(id) or main.world == null or not main.world.has_method("ground_at"):
		return null
	var t: Dictionary = main.dialogue.travellers[id]
	var e: Vector3 = ENTRIES.get(t.arrives_from, ENTRIES.forest_gate)
	e.y = main.world.ground_at(e.x, e.z)
	var npc := TravelerNPC.new()
	main.world.add_child(npc)   # owned by the area: unloading the Sanctuary ends the visit
	npc.setup(id, t, main.world, e, e)
	var h: Array = t.hangout
	var dest := Vector3(h[0], main.world.ground_at(h[0], h[2]), h[2])
	npc.walk_to(dest)
	present[id] = npc
	var st: Dictionary = main.dialogue.state_of(id)
	st.visits += 1
	var stay: Array = t.schedule.stay_s
	_visit_end[id] = _session_t + _rng.randf_range(stay[0], stay[1]) * maxf(time_scale, 0.25)
	var cd: Array = t.schedule.cooldown_s
	st["next_visit_unix"] = Time.get_unix_time_from_system() + _rng.randf_range(cd[0], cd[1]) * time_scale
	events.append({"t": snappedf(_session_t, 0.1), "npc": id, "event": "arrived", "from": t.arrives_from})
	main.voice.register_speaker(String(t.voice), npc)
	print("[npcs] %s (%s) arrives from %s" % [t.name, t.role, t.arrives_from])
	if main.curiosity:
		main.curiosity.on_visitor(id)
	return npc


func _end(id: String, why: String) -> void:
	present.erase(id)
	_visit_end.erase(id)
	events.append({"t": snappedf(_session_t, 0.1), "npc": id, "event": "visit ended", "why": why})


func nearby(from: Vector3, radius := 30.0) -> Array:
	var out := []
	for id in present:
		var n = present[id]
		if is_instance_valid(n) and n.global_position.distance_to(from) <= radius:
			out.append(n.describe(from))
	return out


func describe() -> Dictionary:
	var sched := {}
	for id in main.dialogue.travellers:
		var st: Dictionary = main.dialogue.state_of(id)
		if bool(main.dialogue.travellers[id].get("schedule", {}).get("resident", false)):
			continue
		sched[id] = {"present": present.has(id), "visits": st.visits, "met": st.met, "relationship": snappedf(st.relationship, 0.01),
			"next_visit_in_s": maxi(0, int(float(st.get("next_visit_unix", 0)) - Time.get_unix_time_from_system()))}
	return {"session_s": int(_session_t), "time_scale": time_scale, "travellers": sched, "events": events.slice(maxi(0, events.size() - 10))}
