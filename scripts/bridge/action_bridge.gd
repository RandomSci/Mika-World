class_name ActionBridge
extends Node
## Isolated, local-only structured action interface for a future Mika brain (DEV ONLY).
##
## Transport: newline-delimited JSON over TCP on 127.0.0.1:<port> (default 47651; never a
## production port). Also accepts an in-process mock command script (--mock-commands=...).
## The renderer never thinks: it executes actions, reports real outcomes and exposes
## observations drawn from the authoritative world state (registry + streaming + physics).
##
## Commands (all accept "id"; character defaults to "mika"):
##  observe · list_interactions · navigate_to{target,run} · look_at|face{target} · cast_spell{spell,clip}
##  start_training · stop · list_regions · list_locations{filter} · travel_to{location,mode:walk} (no instant travel)
##  transition_state · nearby_interactables{radius} · interact{object} · landmarks · world_state · set_time{night}
## Events: hello · action_started · action_finished · cast_phase · journey_started · journey_progress ·
##         journey_finished · player_crossed · area_activated · activity_done

signal command_processed(request: Dictionary, reply: Dictionary)

var main: Node
var characters := {}
var server: TCPServer
var peers: Array[StreamPeerTCP] = []
var _buffers := {}
var event_log: Array[Dictionary] = []
var _mock_queue: Array = []
var _mock_wait := ""
var _mock_wait_until := 0.0
var _mock_sleep_until := 0.0
var _training := {}
var brain: SanctuaryBrain
var director: CameraDirector

var world: AreaBase:
	get: return main.world


func setup(m: Node) -> void:
	main = m
	characters = main.characters
	for id in characters:
		var c: WorldCharacter = characters[id]
		c.action_finished.connect(_on_action_finished.bind(id))
		c.action_started.connect(func(a, d): _emit_event({"event": "action_started", "character": id, "action": a, "detail": d}))
		c.cast_event.connect(func(e): _emit_event({"event": "cast_phase", "character": id, "phase": e}))
	main.travel.journey_event.connect(_on_journey_event)
	main.streaming.area_activated.connect(func(a, r): _emit_event({"event": "area_activated", "area": a, "transition": _short_transition(r)}))
	WorldState.state_changed.connect(func(entry): _emit_event({"event": "activity_done", "entry": entry}))
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


func attach_brain(b: SanctuaryBrain, d: CameraDirector) -> void:
	brain = b
	director = d
	b.thought.connect(func(text, sub): _emit_event({"event": "thought", "character": "mika", "text": text, "sub_area": sub}))
	b.decided.connect(func(dec): _emit_event({"event": "brain_decision", "character": "mika", "decision": dec}))
	d.shot_changed.connect(func(m): _emit_event({"event": "camera_shot", "mode": m, "sub_area": d.current_sub}))
	WorldState.trial_completed.connect(func(tr): _emit_event({"event": "trial_completed", "trial": tr}))
	WorldState.rank_changed.connect(func(r): _emit_event({"event": "rank_changed", "rank": r}))


func _on_journey_event(ev: Dictionary) -> void:
	var e: Dictionary = ev.duplicate()
	if e.has("transition"):
		e.transition = _short_transition(e.transition)
	_emit_event(e)
	if e.event == "journey_finished" and _mock_wait == "travel_to":
		_mock_wait = ""


static func _short_transition(r: Dictionary) -> Dictionary:
	var keys := ["ok", "from", "to", "total_ms", "wait_for_preload_ms", "unload_ms", "build_ms", "nav_bake_ms", "worst_build_step_ms",
		"mem_static_mb_after", "instantiated_areas", "arrived_location", "reason"]
	var out := {}
	for k in keys:
		if r.has(k):
			out[k] = r[k]
	return out


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
		_send(p, {"event": "hello", "protocol": "mika-world-bridge/0.3", "characters": characters.keys(), "area": main.streaming.current_id})
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
					_reply_async(p, req)


func _reply_async(p: StreamPeerTCP, req: Dictionary) -> void:
	var r: Dictionary = await handle(req)
	if p.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_send(p, r)


func _send(p: StreamPeerTCP, msg: Dictionary) -> void:
	p.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())


func _emit_event(ev: Dictionary) -> void:
	ev["t"] = snappedf(Time.get_ticks_msec() / 1000.0, 0.01)
	event_log.append(ev)
	if event_log.size() > 300:
		event_log.pop_front()
	print("[bridge] event ", JSON.stringify(ev).left(600))
	for p in peers:
		_send(p, ev)


func _on_action_finished(action: String, ok: bool, detail: String, id: String) -> void:
	_emit_event({"event": "action_finished", "character": id, "action": action, "ok": ok, "detail": detail,
			"observation": observe(id)})
	if _mock_wait == action:
		_mock_wait = ""
	if _training.get(id, false) and action == "navigate_to" and ok:
		var c: WorldCharacter = characters[id]
		c.look_at_point(_training_spot() + Vector3(0, 0, -5))
	elif _training.get(id, false) and action == "look_at":
		_training[id] = false
		characters[id].cast_spell(ArcaneOrbSpell, "magic_attack_2h")


func _training_spot() -> Vector3:
	for k in ["training_clearing", "mage_training_grounds", "advanced_magic_arena"]:
		if world.points_of_interest.has(k):
			return world.points_of_interest[k].position
	return Vector3.INF


# ------------------------------------------------------------------ commands
func handle(req: Dictionary) -> Dictionary:
	var cid: String = req.get("character", "mika")
	var reply := {"id": req.get("id", null), "cmd": req.get("cmd", "")}
	if not characters.has(cid):
		reply.merge({"ok": false, "status": "error", "error": "unknown character '%s'" % cid})
		return reply
	var c: WorldCharacter = characters[cid]
	var busy_transition: bool = main.streaming.state != "idle"
	var cmd := String(req.get("cmd", ""))
	if busy_transition and cmd in ["navigate_to", "look_at", "face", "cast_spell", "interact", "start_training"]:
		reply.merge({"ok": false, "status": "error", "error": "area transition in progress (%s)" % main.streaming.state})
		return reply
	match cmd:
		"observe":
			reply.merge({"ok": true, "status": "done", "observation": observe(cid)})
		"list_interactions":
			reply.merge({"ok": true, "status": "done", "interactions": interactions(cid)})
		"navigate_to":
			var target = _resolve_target(req.get("target"))
			if target == null:
				reply.merge({"ok": false, "status": "error", "error": "unknown target %s in loaded area %s (use travel_to for other areas)" % [str(req.get("target")), main.streaming.current_id]})
			else:
				c.last_rejection = ""
				c.navigate_to(target, bool(req.get("run", false)))
				if c.current_action == "navigate_to":
					reply.merge({"ok": true, "status": "started", "target": _v(target)})
				else:
					reply.merge({"ok": false, "status": "error", "error": c.last_rejection if c.last_rejection != "" else "refused", "target": _v(target)})
		"look_at", "face":
			var target = _resolve_target(req.get("target"))
			if target == null:
				reply.merge({"ok": false, "status": "error", "error": "unknown target %s" % str(req.get("target"))})
			else:
				c.look_at_point(target)
				reply.merge({"ok": true, "status": "started", "target": _v(target)})
		"cast_spell" when main.magic != null and (req.has("target") or String(req.get("spell", "arcane_orb")) != "arcane_orb"):
			# target-aware path: validated, aimed, real reaction (see MagicSystem)
			var r3: Dictionary = await main.magic.cast(c, String(req.get("spell", "arcane_orb")), String(req.get("target", "")))
			reply.merge(r3)
			reply["status"] = "done" if r3.get("ok", false) else "error"
		"spells":
			reply.merge({"ok": true, "status": "done", "spells": main.magic.known_spells()})
		"magic_targets":
			reply.merge({"ok": true, "status": "done", "spell": String(req.get("spell", "arcane_orb")),
				"targets": main.magic.targets_for(String(req.get("spell", "arcane_orb")), c)})
		"cast_spell":
			var spell := String(req.get("spell", "arcane_orb"))
			if not WorldState.skills.has(spell):
				reply.merge({"ok": false, "status": "error", "error": "unknown spell '%s' (known: %s)" % [spell, ", ".join(WorldState.skills.keys())]})
			elif c.casting:
				reply.merge({"ok": false, "status": "error", "error": "already casting"})
			elif not world.has_space_for_magic(c.global_position):
				reply.merge({"ok": false, "status": "error", "error": "not enough space to cast here"})
			else:
				var clip := String(req.get("clip", "prepare_and_cast"))
				if not ArcaneOrbSpell.TIMING.has(clip):
					clip = "prepare_and_cast"
				var s = c.cast_spell(ArcaneOrbSpell, clip)
				reply.merge({"ok": s != null, "status": "started" if s else "error", "clip": clip})
		"start_training":
			var spot := _training_spot()
			if spot == Vector3.INF:
				reply.merge({"ok": false, "status": "error", "error": "no training spot in %s; travel_to mage_training_grounds or advanced_magic_arena" % main.streaming.current_id})
			else:
				_training[cid] = true
				c.navigate_to(spot)
				reply.merge({"ok": true, "status": "started", "plan": ["navigate_to training spot", "face the targets", "cast practice spell"]})
		"stop":
			_training[cid] = false
			main.travel.cancel("stopped")
			c.stop_action()
			reply.merge({"ok": true, "status": "done"})
		"list_regions":
			var out := {}
			for r in WorldState.regions:
				out[r] = {"name": WorldState.regions[r].name, "locations": WorldState.locations.keys().filter(func(l): return WorldState.locations[l].region == r)}
			reply.merge({"ok": true, "status": "done", "regions": out})
		"list_locations":
			var only_known: bool = req.get("filter", "") == "discovered"
			var list := []
			for l in WorldState.locations:
				if only_known and not WorldState.discovered_locations.has(l):
					continue
				var s := WorldState.location_summary(l)
				s["route_hops"] = WorldState.route(main.streaming.current_id, WorldState.area_of(l)).size() - 1
				list.append(s)
			reply.merge({"ok": true, "status": "done", "locations": list})
		"travel_to":
			var r: Dictionary = main.travel.travel_to(String(req.get("location", req.get("target", ""))), String(req.get("mode", "walk")))
			reply.merge(r)
			if not r.has("status"):
				reply["status"] = "error"
		"transition_state":
			reply.merge({"ok": true, "status": "done", "travel": main.travel.status(), "streaming": main.streaming.status()})
		"nearby_interactables":
			reply.merge({"ok": true, "status": "done", "interactables": nearby_interactables(cid, float(req.get("radius", 25.0)))})
		"interact":
			var oid := String(req.get("object", ""))
			if not world.interactables.has(oid):
				reply.merge({"ok": false, "status": "error", "error": "no interactable '%s' in loaded area %s" % [oid, main.streaming.current_id]})
			else:
				var it: Interactable = world.interactables[oid]
				var r: Dictionary = await it.perform(c)
				reply.merge(r)
				reply["status"] = "done" if r.ok else "error"
				reply["world_state"] = WorldState.snapshot()
		"landmarks":
			reply.merge({"ok": true, "status": "done", "landmarks": landmarks(cid)})
		"world_state":
			reply.merge({"ok": true, "status": "done", "state": WorldState.snapshot(), "recent_activities": WorldState.activity_log.slice(maxi(0, WorldState.activity_log.size() - 5))})
		"sword":
			if c.sword == null or not c.sword.available:
				reply.merge({"ok": false, "status": "error", "error": "sword layer unavailable"})
			else:
				var act := String(req.get("action", "draw"))
				var r: Dictionary
				match act:
					"draw": r = await c.sword.draw()
					"sheathe": r = c.sword.sheathe()
					"attack": r = await c.sword.attack()
					"power_up": r = await c.sword.power_up(String(req.get("element", "")))
					"element": r = {"ok": c.sword.set_element(String(req.get("element", ""))), "detail": "element " + c.sword.element}
					"summon": r = await c.sword.summon(String(req.get("weapon", "")))
					"mode": r = {"ok": c.sword.set_idle_mode(String(req.get("mode", "hold"))), "detail": "idle " + c.sword.idle_mode}
					"arsenal": r = {"ok": true, "detail": "arsenal", "arsenal": WeaponArsenal.describe(cid)}
					_: r = {"ok": false, "detail": "unknown sword action (draw|sheathe|attack|power_up|element|summon|mode|arsenal)"}
				reply.merge(r)
				reply["status"] = "done" if r.ok else "error"
				reply["sword"] = {"drawn": c.sword.drawn, "element": c.sword.element, "weapon": c.sword.weapon_id, "idle": c.sword.idle_mode}
		"probe_space":
			# dev diagnostic: physics bodies overlapping a sphere around the character
			var q := PhysicsShapeQueryParameters3D.new()
			var sph := SphereShape3D.new()
			sph.radius = float(req.get("radius", 1.5))
			q.shape = sph
			q.transform = Transform3D(Basis.IDENTITY, c.global_position + Vector3(0, 0.9, 0))
			q.exclude = [c.get_rid()]
			var hits := []
			for h in c.get_world_3d().direct_space_state.intersect_shape(q, 16):
				var o: Node = h.collider
				hits.append("%s <- %s <- %s" % [o.name, o.get_parent().name, o.get_parent().get_parent().name if o.get_parent().get_parent() else ""])
			reply.merge({"ok": true, "status": "done", "position": _v(c.global_position), "hits": hits,
				"nav_next": _v(c.nav_agent.get_next_path_position()), "nav_final": _v(c.nav_agent.get_final_position()),
				"map_regions": NavigationServer3D.map_get_regions(c.get_world_3d().navigation_map).size(),
				"agent_map_is_world_map": c.nav_agent.get_navigation_map() == c.get_world_3d().navigation_map,
				"area_region_rid_in_map": world.nav_region != null and NavigationServer3D.map_get_regions(c.get_world_3d().navigation_map).has(world.nav_region.get_rid()),
				"closest_point_to_target": _v(NavigationServer3D.map_get_closest_point(c.get_world_3d().navigation_map, Vector3(2, 0, 6)))})
		"chat":
			# DEV mock viewer comment (never connected to a real stream)
			reply.merge({"ok": true, "status": "done", "result": main.chat.receive({"message_id": String(req.get("message_id", str(Time.get_ticks_usec()))),
				"author_id": String(req.get("author_id", "mock_viewer")), "author": String(req.get("author", "Viewer")), "text": String(req.get("text", ""))})})
		"chat_status":
			reply.merge({"ok": true, "status": "done", "chat": main.chat.describe()})
		"story":
			reply.merge({"ok": true, "status": "done", "story": main.story.describe()})
		"mages":
			var ms := {}
			for who in main.mage_brains:
				var mm := WorldState.mind(who)
				ms[who] = {"progress": Progression.describe(who), "vigor": snappedf(mm.vigor, 0.01), "inventory": mm.inventory,
					"brain": main.mage_brains[who].status(), "transformed": main.transformer.is_transformed(who) if main.transformer else false}
			reply.merge({"ok": true, "status": "done", "mages": ms, "creatures": main.spawner.describe() if main.spawner else {},
				"transformations": main.transformer.describe() if main.transformer else {}})
		"transform":
			# DEV: preview is the default (changes no progress and reverts); preview:false needs an unlocked form
			var who2 := String(req.get("who", "mika"))
			var preview := bool(req.get("preview", true))
			if not preview and not main.transformer.can_transform(who2):
				reply.merge({"ok": false, "status": "error", "error": "%s has no unlocked form or is already transformed" % who2})
			else:
				var r3: Dictionary = await main.transformer.play(who2, String(req.get("version", "short")), preview)
				reply.merge(r3)
				reply["status"] = "done" if r3.get("ok", false) else "error"
		"transformation":
			# DEV test command: any character, any form, now (full | skip). preview (default) changes no progress
			var who3 := String(req.get("who", cid))
			var r4: Dictionary = await main.transformer.play(who3, String(req.get("mode", "full")), bool(req.get("preview", true)), int(req.get("level", 10)))
			reply.merge(r4)
			reply["status"] = "done" if r4.get("ok", false) else "error"
		"transformation_skip":
			var okk: bool = main.transformer.sequence.request_skip(String(req.get("by", "bridge")))
			reply.merge({"ok": okk, "status": "done" if okk else "error"})
		"spawn_monster":
			var mon: Monster = main.spawner.spawn(String(req.get("kind", "")))
			reply.merge({"ok": mon != null, "status": "done" if mon else "error", "monster": mon.id if mon else "", "error": "" if mon else "no valid spawn spot right now"})
		"progression":
			reply.merge({"ok": true, "status": "done", "recent_xp": main.progression.recent.slice(maxi(0, main.progression.recent.size() - 15)),
				"mika": Progression.describe("mika"), "luna": Progression.describe("luna") if WorldState.minds.has("luna") else {}})
		"region_context":
			if brain == null:
				reply.merge({"ok": false, "status": "error", "error": "no region brain"})
			else:
				reply.merge({"ok": true, "status": "done", "context": brain.region_context()})
		"brain":
			if req.has("on"):
				main.set_brain(bool(req.on))
			reply.merge({"ok": true, "status": "done", "brain": brain.status(), "camera": director.status()})
		"perform_action":
			if brain.busy:
				reply.merge({"ok": false, "status": "error", "error": "Mika's own brain is driving her (send brain{on:false} first)"})
			else:
				var r2 := await brain.perform_action(String(req.get("action", "")))
				reply.merge(r2)
				reply["status"] = "done" if r2.get("ok", false) else "error"
				reply["mission"] = WorldState.mission_state()
		"camera":
			var m := String(req.get("mode", "auto"))
			if m == "off":
				director.enabled = false
			elif m == "conversation" and characters.has(String(req.get("with", ""))):
				director.enabled = true
				director.focus_conversation(characters[String(req.with)], float(req.get("seconds", 8.0)))
			else:
				director.enabled = true
			reply.merge({"ok": true, "status": "done", "camera": director.status()})
		"set_time":
			WorldState.night = bool(req.get("night", false))
			world.set_night(WorldState.night)
			reply.merge({"ok": true, "status": "done", "night": WorldState.night})
		_:
			reply.merge({"ok": false, "status": "error", "error": "unknown cmd"})
	command_processed.emit(req, reply)
	return reply


func _resolve_target(t) -> Variant:
	if typeof(t) == TYPE_STRING and world.interactables.has(t):
		return world.interactables[t].approach_point()  # where to stand, not the object itself
	if typeof(t) == TYPE_STRING and world.points_of_interest.has(t):
		return world.points_of_interest[t].position
	if typeof(t) == TYPE_STRING and characters.has(t):
		return (characters[t] as WorldCharacter).global_position
	if typeof(t) == TYPE_STRING:
		for v in world.visible_landmarks:
			if v.id == t:
				return v.position  # can be faced; navigate_to's reachability check refuses walking to it
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
	var loc := world.location_at(pos)
	obs["region"] = WorldState.areas[world.area_id].region
	obs["area_loaded"] = main.streaming.current_id
	obs["location"] = loc
	obs["area"] = world.area_at(pos)
	if WorldState.areas[world.area_id].region == SanctuaryBrain.REGION:
		var sid := SanctuaryBrain.sub_area(world, pos)
		obs["sub_area"] = sid
		obs["sub_area_purpose"] = WorldState.sanctuary.sub_areas.get(sid, {}).get("purpose", "")
	obs["rank"] = WorldState.mage_rank()
	if director:
		obs["camera"] = director.status()
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
		if d < 16.0:
			nearby.append(entry)
		if absf(bearing) < 60.0 and d < 45.0:
			var q := PhysicsRayQueryParameters3D.create(head, p + Vector3(0, 0.8, 0))
			q.exclude = [c.get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit.position as Vector3).distance_to(p) < 2.5:
				visible.append(poi_id)
	nearby.sort_custom(func(a, b): return a.distance < b.distance)
	obs["nearby"] = nearby.slice(0, 10)
	obs["visible"] = visible
	obs["visible_landmarks"] = landmarks(cid).filter(func(l): return l.in_view).map(func(l): return l.id)
	obs["interactions"] = interactions(cid)
	obs["exits"] = world.gates.keys().map(func(a): return {"to_area": a, "route": world.gates[a].label,
		"locations": WorldState.locations_in_area(a), "distance": snappedf(pos.distance_to(world.gates[a].position), 0.1)})
	var others := []
	for other in characters:
		if other != cid:
			others.append({"id": other, "position": _v((characters[other] as WorldCharacter).global_position)})
	obs["other_characters"] = others
	obs["transition"] = main.streaming.state
	obs["recent_events"] = event_log.slice(maxi(0, event_log.size() - 5)).map(func(e): return {"event": e.event, "action": e.get("action", e.get("phase", "")), "ok": e.get("ok", true), "detail": str(e.get("detail", "")).left(80)})
	return obs


## Landmarks rendered in this area's vista. `in_view`: inside Mika's ~120° view cone right now.
## Destination landmarks report whether the location is playable; scenic ones are never reachable.
func landmarks(cid: String) -> Array:
	var c: WorldCharacter = characters[cid]
	var out := []
	for v in world.visible_landmarks:
		var lm: Dictionary = WorldState.landmarks[v.id]
		var to: Vector3 = v.position - c.global_position
		var bearing := rad_to_deg(angle_difference(c.rotation.y, atan2(-to.x, -to.z)))
		var in_view := absf(bearing) < 60.0
		if in_view:
			WorldState.discover("landmark", v.id)
		var e := {"id": v.id, "name": lm.name, "kind": lm.kind, "bearing_deg": snappedf(bearing, 0.1), "in_view": in_view,
			"true_distance_m": v.true_distance_m}
		match lm.kind:
			"destination":
				e["location"] = lm.location
				e["reachable"] = WorldState.is_playable(lm.location) and not WorldState.route(main.streaming.current_id, WorldState.area_of(lm.location)).is_empty()
				e["visited"] = WorldState.visited_locations.has(lm.location)
			"scenic":
				e["reachable"] = false
				e["note"] = "decorative scenery; no playable scene exists"
			"unfinished":
				e["reachable"] = false
				e["note"] = lm.get("note", "planned, not yet built")
		out.append(e)
	return out


func nearby_interactables(cid: String, radius: float) -> Array:
	var c: WorldCharacter = characters[cid]
	var out := []
	for id in world.interactables:
		var it: Interactable = world.interactables[id]
		var d := it.describe(c.global_position)
		if d.distance <= radius:
			out.append(d)
	out.sort_custom(func(a, b): return a.distance < b.distance)
	return out


func interactions(cid: String) -> Array:
	var c: WorldCharacter = characters[cid]
	var out := ["observe", "navigate_to", "look_at", "stop", "travel_to", "list_locations", "landmarks"]
	if c.is_on_floor() and not c.casting and world.has_space_for_magic(c.global_position):
		out.append("cast_spell:arcane_orb")
	for d in nearby_interactables(cid, 4.0):
		if d.in_reach and d.available:
			out.append("interact:" + d.id)
	if _training_spot() != Vector3.INF:
		out.append("start_training")
	return out


# ------------------------------------------------------------------ mock commands (no network)
func _run_mock() -> void:
	if _mock_queue.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _mock_wait != "":
		if now < _mock_wait_until:
			return
		print("[mock] timed out waiting for ", _mock_wait)
		_mock_wait = ""
	elif now < _mock_sleep_until:
		return
	if main.streaming.state != "idle" or _mock_busy:
		return
	var req: Dictionary = _mock_queue.pop_front()
	if req.has("sleep"):
		_mock_sleep_until = now + float(req.sleep)
		return
	if req.get("wait", false):
		_mock_wait = {"navigate_to": "navigate_to", "look_at": "look_at", "cast_spell": "cast_spell", "start_training": "cast_spell",
			"travel_to": "travel_to"}.get(req.cmd, "")
		_mock_wait_until = now + float(req.get("timeout", 60.0))
	_mock_busy = true
	var reply := await handle(req)
	_mock_busy = false
	print("[mock] ", JSON.stringify(req), " -> ", JSON.stringify(reply).left(2500))
	if reply.get("status") != "started":
		_mock_wait = ""


var _mock_busy := false
