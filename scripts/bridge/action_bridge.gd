class_name ActionBridge
extends Node
## Isolated, local-only structured action interface for a future Mika brain.
##
## Transport: newline-delimited JSON over TCP on 127.0.0.1:<port> (default 47651, DEV only;
## never production ports). Also accepts an in-process mock command script (--mock-commands=...).
## The renderer never thinks: it executes actions, reports real outcomes, and exposes observations.
##
## Requests  {"id": 1, "cmd": "observe" | "navigate_to" | "look_at" | "cast_spell" |
##            "start_training" | "stop" | "list_interactions", "character": "mika", ...}
## Replies   {"id": 1, "ok": true|false, "status": "started"|"done"|"error", ...}
## Events    {"event": "action_finished", "character": "mika", "action": "...", "ok": bool, "detail": "..."}

signal command_processed(request: Dictionary, reply: Dictionary)

var world: Sanctuary
var characters := {}          # id -> WorldCharacter
var camera: Camera3D
var server: TCPServer
var peers: Array[StreamPeerTCP] = []
var _buffers := {}
var event_log: Array[Dictionary] = []
var _mock_queue: Array = []
var _mock_wait := ""          # action we are waiting to finish before the next mock command
var _mock_wait_until := 0.0
var _mock_sleep_until := 0.0
var _training := {}           # character id -> true while a training routine runs


func setup(w: Sanctuary, chars: Dictionary, cam: Camera3D) -> void:
	world = w
	characters = chars
	camera = cam
	for id in characters:
		var c: WorldCharacter = characters[id]
		c.action_finished.connect(_on_action_finished.bind(id))
		c.action_started.connect(func(a, d): _emit_event({"event": "action_started", "character": id, "action": a, "detail": d}))
		c.cast_event.connect(func(e): _emit_event({"event": "cast_phase", "character": id, "phase": e}))
	if RenderProfile.bridge_enabled:
		server = TCPServer.new()
		var err := server.listen(RenderProfile.bridge_port, "127.0.0.1")
		if err != OK:
			push_warning("[bridge] port %d unavailable (%s); bridge disabled" % [RenderProfile.bridge_port, error_string(err)])
			server = null
		else:
			print("[bridge] listening on 127.0.0.1:%d (dev only)" % RenderProfile.bridge_port)
	if RenderProfile.mock_commands != "":
		var f := FileAccess.open(RenderProfile.mock_commands, FileAccess.READ)
		if f:
			_mock_queue = JSON.parse_string(f.get_as_text())
			print("[bridge] loaded %d mock commands from %s" % [_mock_queue.size(), RenderProfile.mock_commands])


func _process(_delta: float) -> void:
	_poll_network()
	_run_mock()


# ------------------------------------------------------------------ transport
func _poll_network() -> void:
	if server == null:
		return
	while server.is_connection_available():
		var p := server.take_connection()
		peers.append(p)
		_buffers[p] = ""
		_send(p, {"event": "hello", "protocol": "mika-world-bridge/0.1", "characters": characters.keys()})
	for p in peers.duplicate():
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			peers.erase(p)
			_buffers.erase(p)
			continue
		var n: int = p.get_available_bytes()
		if n > 0:
			_buffers[p] += p.get_utf8_string(n)
			while "\n" in _buffers[p]:
				var line: String = _buffers[p].get_slice("\n", 0)
				_buffers[p] = _buffers[p].substr(line.length() + 1)
				if line.strip_edges() == "":
					continue
				var req = JSON.parse_string(line)
				if typeof(req) != TYPE_DICTIONARY:
					_send(p, {"ok": false, "status": "error", "error": "invalid JSON"})
				else:
					_send(p, handle(req))


func _send(p: StreamPeerTCP, msg: Dictionary) -> void:
	p.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())


func _emit_event(ev: Dictionary) -> void:
	ev["t"] = snappedf(Time.get_ticks_msec() / 1000.0, 0.01)
	event_log.append(ev)
	if event_log.size() > 200:
		event_log.pop_front()
	print("[bridge] event ", JSON.stringify(ev))
	for p in peers:
		_send(p, ev)


func _on_action_finished(action: String, ok: bool, detail: String, id: String) -> void:
	_emit_event({"event": "action_finished", "character": id, "action": action, "ok": ok, "detail": detail,
			"observation": observe(id)})
	if _mock_wait == action:
		_mock_wait = ""
	if _training.get(id, false) and action == "navigate_to" and ok:
		var c: WorldCharacter = characters[id]
		var tc := world.points_of_interest["training_clearing"].position as Vector3
		c.look_at_point(tc + Vector3(0, 0, -5))
	elif _training.get(id, false) and action == "look_at":
		_training[id] = false
		characters[id].cast_spell(ArcaneOrbSpell, "magic_attack_2h")


# ------------------------------------------------------------------ commands
func handle(req: Dictionary) -> Dictionary:
	var id = req.get("id", null)
	var cid: String = req.get("character", "mika")
	var reply := {"id": id, "cmd": req.get("cmd", "")}
	if not characters.has(cid):
		reply.merge({"ok": false, "status": "error", "error": "unknown character '%s'" % cid})
		return reply
	var c: WorldCharacter = characters[cid]
	match String(req.get("cmd", "")):
		"observe":
			reply.merge({"ok": true, "status": "done", "observation": observe(cid)})
		"list_interactions":
			reply.merge({"ok": true, "status": "done", "interactions": interactions(cid)})
		"navigate_to":
			var target = _resolve_target(req.get("target"))
			if target == null:
				reply.merge({"ok": false, "status": "error", "error": "unknown target %s" % str(req.get("target"))})
			else:
				c.last_rejection = ""
				c.navigate_to(target, bool(req.get("run", false)))
				if c.current_action == "navigate_to":
					reply.merge({"ok": true, "status": "started", "target": _v(target)})
				else:
					reply.merge({"ok": false, "status": "error", "error": c.last_rejection if c.last_rejection != "" else "refused", "target": _v(target)})
		"look_at":
			var target = _resolve_target(req.get("target"))
			if target == null:
				reply.merge({"ok": false, "status": "error", "error": "unknown target %s" % str(req.get("target"))})
			else:
				c.look_at_point(target)
				reply.merge({"ok": true, "status": "started", "target": _v(target)})
		"cast_spell":
			var spell := String(req.get("spell", "arcane_orb"))
			if spell != "arcane_orb":
				reply.merge({"ok": false, "status": "error", "error": "unknown spell '%s' (known: arcane_orb)" % spell})
			elif c.casting:
				reply.merge({"ok": false, "status": "error", "error": "already casting"})
			else:
				var clip := String(req.get("clip", "prepare_and_cast"))
				if not ArcaneOrbSpell.TIMING.has(clip):
					clip = "prepare_and_cast"
				var s = c.cast_spell(ArcaneOrbSpell, clip)
				reply.merge({"ok": s != null, "status": "started" if s else "error", "clip": clip})
		"start_training":
			_training[cid] = true
			c.navigate_to(world.points_of_interest["training_clearing"].position)
			reply.merge({"ok": true, "status": "started", "plan": ["navigate_to training_clearing", "look_at stones", "cast practice spell"]})
		"stop":
			_training[cid] = false
			c.stop_action()
			reply.merge({"ok": true, "status": "done"})
		_:
			reply.merge({"ok": false, "status": "error", "error": "unknown cmd"})
	command_processed.emit(req, reply)
	return reply


func _resolve_target(t) -> Variant:
	if typeof(t) == TYPE_STRING and world.points_of_interest.has(t):
		return world.points_of_interest[t].position
	if typeof(t) == TYPE_STRING and characters.has(t):
		return (characters[t] as WorldCharacter).global_position
	if typeof(t) == TYPE_ARRAY and t.size() == 3:
		return Vector3(t[0], t[1], t[2])
	return null


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


# ------------------------------------------------------------------ observations
func observe(cid: String) -> Dictionary:
	var c: WorldCharacter = characters[cid]
	var obs := c.observe()
	var pos := c.global_position
	obs["area"] = world.area_at(pos)
	var nearby := []
	var visible := []
	var head := pos + Vector3(0, 1.45, 0)
	var space := c.get_world_3d().direct_space_state
	for poi_id in world.points_of_interest:
		var poi: Dictionary = world.points_of_interest[poi_id]
		var p: Vector3 = poi.position
		var d := pos.distance_to(p)
		var to := p - pos
		var bearing := rad_to_deg(angle_difference(c.rotation.y, atan2(-to.x, -to.z)))
		var entry := {"id": poi_id, "distance": snappedf(d, 0.01), "bearing_deg": snappedf(bearing, 0.1), "description": poi.description}
		if d < 14.0:
			nearby.append(entry)
		# visible: within the character's ~120° view cone and unobstructed line of sight
		if absf(bearing) < 60.0 and d < 40.0:
			var q := PhysicsRayQueryParameters3D.create(head, p + Vector3(0, 0.8, 0))
			q.exclude = [c.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit.position as Vector3).distance_to(p) < 2.5:
				visible.append(poi_id)
	nearby.sort_custom(func(a, b): return a.distance < b.distance)
	obs["nearby"] = nearby
	obs["visible"] = visible
	obs["interactions"] = interactions(cid)
	var others := []
	for other in characters:
		if other != cid:
			others.append({"id": other, "position": _v((characters[other] as WorldCharacter).global_position)})
	obs["other_characters"] = others
	obs["recent_events"] = event_log.slice(maxi(0, event_log.size() - 5)).map(func(e): return {"event": e.event, "action": e.get("action", e.get("phase", "")), "ok": e.get("ok", true), "detail": e.get("detail", "")})
	return obs


func interactions(cid: String) -> Array:
	var c: WorldCharacter = characters[cid]
	var out := ["observe", "navigate_to", "look_at", "stop"]
	var area := world.area_at(c.global_position)
	if c.is_on_floor() and not c.casting:
		out.append("cast_spell:arcane_orb")
	if area == "spell_altar":
		out.append("study_spellbook (planned)")
	if area != "training_clearing":
		out.append("start_training")
	return out


# ------------------------------------------------------------------ mock commands (no network)
func _run_mock() -> void:
	if _mock_queue.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _mock_wait != "":
		if now < _mock_wait_until:
			return  # still waiting for the awaited action to finish
		print("[mock] timed out waiting for ", _mock_wait)
		_mock_wait = ""
	elif now < _mock_sleep_until:
		return
	var req: Dictionary = _mock_queue.pop_front()
	if req.has("sleep"):
		_mock_sleep_until = now + float(req.sleep)
		return
	var reply := handle(req)
	print("[mock] ", JSON.stringify(req), " -> ", JSON.stringify(reply))
	if req.get("wait", false) and reply.get("status") == "started":
		_mock_wait = {"navigate_to": "navigate_to", "look_at": "look_at", "cast_spell": "cast_spell", "start_training": "cast_spell"}.get(req.cmd, "")
		_mock_wait_until = now + float(req.get("timeout", 60.0))
