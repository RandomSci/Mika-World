class_name JourneyDirector
extends Node
## Multi-day journeys across the overland world (V3 continuation; docs/WORLD_TRAVEL.md, data/overland.json).
## A journey is persistent state (WorldState.journey): where the party is going and why, the route legs, how far
## along they are, the day, their condition and supplies, what happened on the way, and what is unfinished.
## The party WALKS every metre: through the playable areas to the gate, then along Wayside stretches of the road
## (generated per route and km), camping where night finds them; while they walk a stretch the world clock runs
## at road pace (the hours really pass: km = pace x hours), and nothing ever moves them instantly.
## Off camera (or while the game is closed) the same journey advances in the background at the same pace.

signal journey_event(ev: Dictionary)

static var _overland := {}

var main: Node
var live := false                  # a live (rendered) leg is being walked right now
var camp_scene: Node = null        # CampScene while they camp
var stage := ""                    # what the party is doing now (overlay / tests)
var _follow: FollowCompanion
var _bg_t := 0.0
var force_encounter := ""           # tests: the next stretch has this road encounter (kind id)
var encounters: Array = []          # what happened on the road this session (tests, overlay)
const MAX_STRETCH_H := 4.0


static func overland() -> Dictionary:
	if _overland.is_empty():
		var f := FileAccess.open("res://data/overland.json", FileAccess.READ)
		_overland = JSON.parse_string(f.get_as_text()) if f else {"routes": {}}
	return _overland


## The route between two areas (either direction). {} when the two are joined only by a local path.
static func route_info(key: String) -> Dictionary:
	var routes: Dictionary = overland().get("routes", {})
	if routes.has(key):
		return routes[key]
	var parts := key.split("|")
	if parts.size() == 2 and routes.has(parts[1] + "|" + parts[0]):
		var r: Dictionary = (routes[parts[1] + "|" + parts[0]] as Dictionary).duplicate(true)
		var km := float(r.km)
		for w in r.get("waypoints", []):
			w["km"] = km - float(w.km)
		(r.get("waypoints", []) as Array).sort_custom(func(a, b): return float(a.km) < float(b.km))
		r["reversed"] = true
		return r
	return {}


func setup(m: Node) -> void:
	main = m


static func pace() -> Dictionary:
	return overland().get("pace", {"road_kmh": 4.0, "forest_kmh": 3.2, "climb_kmh": 2.2, "march_hours_per_day": 7.0, "start_hour": 7.0, "camp_hour": 18.0})


static func kmh(terrain: String) -> float:
	var p := pace()
	match terrain:
		"forest": return float(p.forest_kmh)
		"climb": return float(p.climb_kmh)
	return float(p.road_kmh)


func active() -> bool:
	return not WorldState.journey.is_empty() and String(WorldState.journey.get("phase", "")) != "done"


# ------------------------------------------------------------------ planning
## Plan a journey from the area the party is in now to `dest_area`, for a reason of their own. Every leg is a real
## connection; overland legs carry their km, terrain and waypoints. Persisted at once.
func start(dest_area: String, purpose: String, party: Array = ["mika", "luna"], why_who := "mika") -> Dictionary:
	if active():
		return {"ok": false, "error": "already on a journey to " + String(WorldState.journey.dest)}
	var here: String = main.streaming.current_id
	var path := WorldState.route(here, dest_area)
	if path.size() < 2:
		return {"ok": false, "error": "no road from %s to %s" % [here, dest_area]}
	var legs := []
	var total := 0.0
	for i in path.size() - 1:
		var key := "%s|%s" % [path[i], path[i + 1]]
		var r := route_info(key)
		var leg := {"from": path[i], "to": path[i + 1], "key": key, "overland": not r.is_empty(),
			"name": String(r.get("name", WorldState.adjacency.get(path[i], {}).get(path[i + 1], "path"))),
			"km": float(r.get("km", 0.3)), "terrain": String(r.get("terrain", "path")), "biome": String(r.get("biome", "")),
			"danger": float(r.get("danger", 0.1)), "waypoints": r.get("waypoints", []), "habitats": r.get("habitats", [])}
		legs.append(leg)
		total += float(leg.km)
	var cond := {}
	for who in party:
		cond[who] = {"fatigue": 0.0, "hunger": 0.2}
	WorldState.journey = {"id": "j%d" % int(Time.get_unix_time_from_system()), "dest": dest_area, "purpose": purpose, "purpose_of": why_who,
		"party": party, "legs": legs, "leg": 0, "km": 0.0, "total_km": total, "phase": "walking", "stretch": 0,
		"started": WorldState.clock_text(), "started_min": WorldState.world_min, "log": [], "seen": {}, "condition": cond,
		"supplies": {"food": 6, "firewood": 0}, "camps": [], "unresolved": [], "discoveries": []}
	note("set out from %s for %s: %s" % [WorldState.areas[here].get("region", here).replace("_", " "), dest_area.replace("_", " "), purpose])
	return {"ok": true, "legs": legs.size(), "km": total, "days_estimate": snappedf(total / (kmh("forest") * float(pace().march_hours_per_day)), 0.1)}


## A line in the journey's own record (persisted): "Day 2, 09:40 - crossed Mossfall Ford".
func note(what: String, kind := "event", extra := {}) -> void:
	var j: Dictionary = WorldState.journey
	if j.is_empty():
		return
	var e := {"when": WorldState.clock_text(), "min": snappedf(WorldState.world_min, 0.1), "kind": kind, "what": what,
		"leg": int(j.get("leg", 0)), "km": snappedf(float(j.get("km", 0.0)), 0.01)}
	e.merge(extra)
	(j.log as Array).append(e)
	WorldState._dirty = true
	print("[journey] %s  %s" % [e.when, what])
	journey_event.emit(e)


func leg() -> Dictionary:
	var j: Dictionary = WorldState.journey
	return (j.legs as Array)[int(j.leg)] if not j.is_empty() and int(j.leg) < (j.legs as Array).size() else {}


func leg_km_left() -> float:
	return maxf(0.0, float(leg().get("km", 0.0)) - float(WorldState.journey.get("km", 0.0)))


## Waypoints passed between km a and b of the current leg: what they saw and did there goes in the record.
func _pass_waypoints(a: float, b: float) -> Array:
	var out := []
	var j: Dictionary = WorldState.journey
	for w in leg().get("waypoints", []):
		var wk := float(w.km)
		var wid := String(w.id)
		if wk > a and wk <= b and not (j.seen as Dictionary).has(wid):
			j.seen[wid] = WorldState.clock_text()
			out.append(w)
			var did := ""
			match String(w.get("kind", "")):
				"hamlet", "village", "inn":
					j.supplies.food = int(j.supplies.food) + 2
					did = " - bought bread and cheese there (food %d)" % int(j.supplies.food)
				"crossing":
					did = " - crossed it with care"
				"landmark":
					did = " - stopped to look at it"
			note("passed %s (%s)%s" % [w.name, String(w.get("describe", w.get("kind", ""))), did], "waypoint", {"id": wid})
			if String(w.get("kind", "")) in ["landmark", "crossing"] and not (j.discoveries as Array).has(wid):
				(j.discoveries as Array).append(wid)
	return out


# ------------------------------------------------------------------ the live journey (rendered)
func _party() -> Array[WorldCharacter]:
	var out: Array[WorldCharacter] = []
	for who in WorldState.journey.get("party", []):
		var c: WorldCharacter = main.characters.get(who)
		if c:
			out.append(c)
	return out


func _hold_brains(on: bool) -> void:
	for who in WorldState.journey.get("party", ["mika", "luna"]):
		var b = main.mage_brains.get(who)
		if b:
			b.hold = on
			if on:
				b.interrupt("journey")


## Walk the whole journey live, leg by leg, stretch by stretch, camping where the night finds them. Awaitable;
## `max_stretches` bounds a test. Returns the final journey state.
func run_live(max_stretches := 99) -> Dictionary:
	if not active():
		return {"ok": false, "error": "no journey"}
	live = true
	_hold_brains(true)
	main.travel._cooldown_until = 1e12            # gates are crossed by the journey, not by walking into them
	var stretches := 0
	while active() and stretches < max_stretches:
		var lg := leg()
		if lg.is_empty():
			break
		if main.streaming.current_id == String(lg.to) and not bool(lg.overland):
			_next_leg()
			continue
		if not bool(lg.overland):
			await _walk_local_leg(lg)
			continue
		# an overland leg: from its start area, walk out to its gate; then stretch after stretch
		if main.streaming.current_id == String(lg.from):
			stage = "walking to the %s" % lg.name
			if not await _walk_to_gate(String(lg.to)):
				note("could not reach the way out (%s)" % lg.name, "problem")
				break
			await _enter_stretch()
			stretches += 1
			continue
		if main.streaming.current_id == "wayside":
			var arrived := await _walk_stretch()
			stretches += 1
			if arrived:
				await _leave_stretch(String(lg.to))
				_next_leg()
			else:
				await _enter_stretch()
			continue
		break
	live = false
	stage = ""
	_hold_brains(false)
	main.travel._cooldown_until = 0.0
	return WorldState.journey


func _next_leg() -> void:
	var j: Dictionary = WorldState.journey
	note("reached %s" % String(leg().get("to", "")).replace("_", " "), "arrival")
	j.leg = int(j.leg) + 1
	j.km = 0.0
	j.stretch = 0
	if int(j.leg) >= (j.legs as Array).size():
		j.phase = "done"
		j.arrived = WorldState.clock_text()
		var days := (WorldState.world_min - float(j.started_min)) / 1440.0
		note("arrived at %s after %.1f days on the road" % [String(j.dest).replace("_", " "), days], "arrived")
	WorldState._dirty = true


func _walk_local_leg(lg: Dictionary) -> void:
	stage = "walking to %s" % lg.to
	if await _walk_to_gate(String(lg.to)):
		await _cross(String(lg.to))
	_next_leg()


func _start_follow() -> void:
	var p := _party()
	if p.size() < 2:
		return
	if _follow and is_instance_valid(_follow):
		_follow.queue_free()
	_follow = FollowCompanion.new()
	_follow.leader = p[0]
	_follow.follower = p[1]
	add_child(_follow)


func _stop_follow() -> void:
	if _follow and is_instance_valid(_follow):
		_follow.queue_free()
	_follow = null


func _walk_to_gate(next_area: String) -> bool:
	var area: AreaBase = main.world
	var gate: Dictionary = area.gates.get(next_area, {})
	if gate.is_empty():
		return false
	var p := _party()
	var lead := p[0]
	var map := lead.get_world_3d().navigation_map
	# walk to the gate's arrival spot (always on the walkable side, a few metres in) and on toward the gate itself;
	# the crossing is the masked transition, so standing at the gate's mouth is enough
	var arr = gate.get("arrive", gate.position)
	var arrive: Vector3 = (arr as Transform3D).origin if arr is Transform3D else arr
	var goal := NavigationServer3D.map_get_closest_point(map, gate.position)
	var path := NavigationServer3D.map_get_path(map, lead.global_position, goal, true)
	if path.size() < 2 or (path[path.size() - 1] as Vector3).distance_to(goal) > 2.0:
		goal = NavigationServer3D.map_get_closest_point(map, arrive)
	_start_follow()
	var ok := false
	if _follow:
		ok = await main.companionship.walk_together(lead, _follow, goal, 240.0)
	else:
		lead.navigate_to(goal, false)
		var t0 := Time.get_ticks_msec()
		while lead.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 240000:
			await get_tree().physics_frame
		ok = lead.global_position.distance_to(goal) < 3.0
	_stop_follow()
	return ok or lead.global_position.distance_to(gate.position) < float(gate.radius) + 4.0 or lead.global_position.distance_to(arrive) < 3.5


## Cross into `to_area` through the gate they are standing at - the companion walked here too and comes along
## through the same masked transition, a pace behind (her saved place in the new area is set before the load).
func _cross(to_area: String) -> bool:
	var p := _party()
	var lead := p[0]
	if p.size() > 1:
		var mate := p[1]
		WorldState.mind(mate.character_id).set_location(to_area, Vector3.INF)
		mate.set_meta("journey_follow", true)
	var r: Dictionary = await main.streaming.travel(to_area, lead)
	if not r.get("ok", false):
		note("the way was blocked (%s)" % r.get("reason", "?"), "problem")
		return false
	if p.size() > 1:
		await _place_companion(p[1], lead)
	return true


## Her place after the shared crossing: a step behind Mika on the same path (both just came through the gate).
func _place_companion(mate: WorldCharacter, lead: WorldCharacter) -> void:
	var back := lead.global_transform.basis.z.normalized()
	var want := lead.global_position + back * 1.6 + lead.global_transform.basis.x * 0.8
	# the navigation map answers (0,0,0) for a few frames after a load: wait for it (main.snap_to_nav), and never
	# accept a point that is not near where she should be
	var at: Vector3 = await main.snap_to_nav(want)
	if at.distance_to(want) > 3.0:
		at = want
	if main.world and main.world.has_method("ground_at"):
		at.y = maxf(at.y, float(main.world.ground_at(at.x, at.z)))
	if main.teleport_guard:
		main.teleport_guard.allow(mate)
	mate.global_position = at + Vector3(0, 0.1, 0)
	mate.rotation.y = lead.rotation.y
	mate.world = main.world
	mate.visible = true
	mate.set_physics_process(true)
	WorldState.mind(mate.character_id).set_location(main.streaming.current_id, mate.global_position)


func _enter_stretch() -> void:
	var j: Dictionary = WorldState.journey
	var lg := leg()
	var k := float(j.km)
	Wayside.params = {"route": String(lg.key), "km": k, "seed": abs(hash(String(lg.key))) % 100000 + int(j.stretch) * 7919,
		"from": String(lg.from), "to": String(lg.to), "title": String(lg.name), "biome": String(lg.biome)}
	# a waypoint this stretch of road will pass (a hamlet, an inn, a shelter, a landmark) stands at the roadside,
	# where its km falls along the stretch
	var cover := minf(leg_km_left(), kmh(String(lg.terrain)) * MAX_STRETCH_H)
	for w in lg.get("waypoints", []):
		var wk := float(w.km)
		if wk > k and wk <= k + cover and String(w.get("kind", "")) in ["hamlet", "village", "inn", "shelter", "landmark"]:
			Wayside.params["waypoint"] = w
			Wayside.params["waypoint_t"] = 0.12 + 0.76 * (wk - k) / maxf(cover, 0.1)
			break
	j.stretch = int(j.stretch) + 1
	stage = "on %s, km %.0f of %.0f" % [lg.name, k, float(lg.km)]
	await _cross("wayside")


## Walk this stretch of road. The hours pass at road pace while they walk (the clock runs faster - you see the
## sun move); waypoints along the km they cover are passed. Returns true if they reach the end of the leg here;
## false when night finds them and they camp (and then walk on next morning, still in this stretch).
func _walk_stretch() -> bool:
	var j: Dictionary = WorldState.journey
	var lg := leg()
	var w: Wayside = main.world
	var p := _party()
	var lead := p[0]
	var speed := kmh(String(lg.terrain))
	var camp_h := float(pace().camp_hour)
	var start_h := float(pace().start_hour)
	# before dawn (arrived late, or resumed at night): it is time to camp right here
	if WorldState.hour_f() >= camp_h or WorldState.hour_f() < start_h - 1.0:
		await _camp(w)
		return false
	var left := leg_km_left()
	var hours_today := camp_h - WorldState.hour_f()
	var reach := speed * hours_today
	var stretch_max := speed * MAX_STRETCH_H           # one stretch of road is at most a few hours' walk
	var to_camp := reach < left and reach <= stretch_max
	var cover := minf(minf(left, reach), stretch_max)
	# how much road they walk on screen: to the camp side path, or to the far end (the next stretch loads there)
	var t_end := 0.47 if to_camp else 1.0
	var t_start := float(j.get("stretch_t", 0.05))
	if t_start >= t_end - 0.02:
		t_start = 0.05
	var road_m := _road_length(w, t_start, t_end)
	var walk_s := maxf(road_m / lead.walk_speed, 10.0)
	var world_min := cover / speed * 60.0
	WorldState.clock_boost = clampf(world_min / (walk_s * WorldState.clock_rate), 1.0, 600.0)
	var k0 := float(j.km)
	stage = "walking %s (%.0f km to go)" % [lg.name, left]
	_start_follow()
	var t0_min := WorldState.world_min
	var ok := true
	# walk the road in a few legs along its points (a long navigate is re-planned at each)
	var steps := 6
	var met := false
	for i in range(1, steps + 1):
		var t := lerpf(t_start, t_end, float(i) / steps)
		var goal := w.road_point(t)
		if i == 3 and not met and _roll_encounter():
			met = true
			await _road_encounter(w, lead, t, t_end)
		if _follow:
			ok = await main.companionship.walk_together(lead, _follow, goal, 120.0)
		else:
			lead.navigate_to(goal, false)
			while lead.current_action == "navigate_to":
				await get_tree().physics_frame
		var done := clampf((WorldState.world_min - t0_min) / maxf(world_min, 0.01), 0.0, 1.0)
		var k_now := minf(k0 + cover * done, k0 + cover)
		_pass_waypoints(float(j.km), k_now)
		j.km = k_now
	WorldState.clock_boost = 1.0
	# make the km and the hours exactly what was walked (the clock may lag a walk that ended early)
	var spent := WorldState.world_min - t0_min
	if spent < world_min:
		WorldState.advance_clock(world_min - spent)
	_pass_waypoints(float(j.km), k0 + cover)
	j.km = k0 + cover
	for who in j.condition:
		var cnd: Dictionary = j.condition[who]
		cnd.fatigue = clampf(float(cnd.fatigue) + cover * 0.018, 0.0, 1.0)
		cnd.hunger = clampf(float(cnd.hunger) + world_min / 60.0 * 0.06, 0.0, 1.0)
	_stop_follow()
	j.stretch_t = t_end
	WorldState._dirty = true
	if to_camp:
		note("evening on %s, %.0f km along; looking for a place to camp" % [lg.name, float(j.km)], "dusk")
		await _camp(w)
		j.stretch_t = 0.47
		return false
	j.stretch_t = 0.05
	if leg_km_left() > 0.01:
		note("walked on along %s (%.0f km to go)" % [lg.name, leg_km_left()], "road")
	return leg_km_left() <= 0.01


# ------------------------------------------------------------------ someone on the road (data/encounters.json)
func _roll_encounter() -> bool:
	var h := WorldState.hour_f()
	if h < 8.0 or h > 17.5:
		return false
	if force_encounter != "":
		return true
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/encounters.json"))
	return randf() < float(d.get("chance_per_stretch", 0.15))


## A traveller comes the other way along the road, stops for a word with them, and walks on. What they say can be a
## real clue (her knowledge), which the expedition planner can later turn into a journey of its own.
func _road_encounter(w: Wayside, lead: WorldCharacter, t_now: float, t_end: float) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/encounters.json"))
	var kinds: Dictionary = d.get("kinds", {})
	var j: Dictionary = WorldState.journey
	var met_before: Array = j.get_or_add("met_on_road", [])
	var kind := force_encounter
	force_encounter = ""
	if kind == "":
		var pool := []
		for k in kinds:
			if not met_before.has(k):
				for n in int(kinds[k].get("weight", 1)):
					pool.append(k)
		if pool.is_empty():
			return
		kind = String(pool[randi() % pool.size()])
	var e: Dictionary = kinds.get(kind, {})
	if e.is_empty():
		return
	met_before.append(kind)
	var who := Resident.new()
	w.add_child(who)
	who.setup("road_" + kind, {"name": e.name, "role": e.name, "model": e.model, "voice": e.voice, "height_m": e.get("height_m", 1.72),
		"recolor": e.get("recolor", {}), "schedule": []}, main.town, w)
	# they appear a little way up the road (about 22 m, round the next bend) and come toward the party
	var ts := t_now
	while ts < t_end - 0.02 and w.road_point(ts).distance_to(lead.global_position) < 22.0:
		ts += 0.005
	who.global_position = w.road_point(ts)
	who.visible = true
	stage = "meeting %s on the road" % e.name
	_stop_follow()
	lead.look_head_at(who.global_position + Vector3(0, 1.6, 0))
	if main.director and main.director.enabled:
		main.director.focus_conversation(who, 30.0)
	# they meet halfway: each walks toward the other, and stop a couple of metres apart
	var mid := (lead.global_position + who.global_position) * 0.5
	who._walk_to(mid)
	lead.navigate_to(NavigationServer3D.map_get_closest_point(lead.get_world_3d().navigation_map, mid), false)
	var tw := 0.0
	while who.global_position.distance_to(lead.global_position) > 2.6 and tw < 45.0:
		await get_tree().physics_frame
		tw += get_physics_process_delta_time()
		if who.state != "walking" and who.global_position.distance_to(lead.global_position) > 2.6:
			who._walk_to(lead.global_position)
	if lead.current_action == "navigate_to":
		lead.stop_action()
	who._path = PackedVector3Array()
	who.state = "talking"
	who._face_yaw = atan2(lead.global_position.x - who.global_position.x, lead.global_position.z - who.global_position.z)
	lead.look_at_point(who.global_position)
	who.play("talk", 0.3)
	var rec := {"kind": kind, "who": String(e.name), "clock": WorldState.clock_text(), "said": []}
	var lines: Array = e.get("lines", [])
	var answers: Array = e.get("mika", [])
	for i in maxi(lines.size(), answers.size()):
		if i < lines.size():
			await main.voice.say(String(e.voice), String(lines[i]), {"max_wait": 2.5})
			(rec.said as Array).append([e.name, lines[i]])
		if i < answers.size():
			await main.voice.say("mika", String(answers[i]), {"max_wait": 2.5, "mood": "happy"})
			(rec.said as Array).append(["Mika", answers[i]])
	# a rumour: a clue none of them knew (it is told, so it goes into her knowledge as something heard on the road)
	var rumours: Array = (e.get("rumours", []) as Array).filter(func(r): return not WorldState.mind("mika").knowledge.has(String(r.clue)))
	if not rumours.is_empty():
		var r: Dictionary = rumours[randi() % rumours.size()]
		await main.voice.say(String(e.voice), String(r.text), {"max_wait": 2.5})
		(rec.said as Array).append([e.name, r.text])
		for p in j.get("party", ["mika"]):
			WorldState.record_activity({"id": "road_rumour:" + kind, "verb": "listen", "label": "Heard on the road from %s" % e.name}, {"knowledge": {String(r.clue): 1}}, String(p))
		rec["clue"] = String(r.clue)
	var eff: Dictionary = e.get("effect", {})
	if eff.has("food"):
		(j.supplies as Dictionary)["food"] = int(j.supplies.get("food", 0)) + int(eff.food)
	note("met %s on the road%s" % [e.name, (" - heard: " + String(rec.get("clue", ""))) if rec.has("clue") else ""], "encounter", {"kind": kind})
	encounters.append(rec)
	lead.look_head_at(null)
	# and walks on, the way the party came
	who.play("yes", 0.3)
	await get_tree().create_timer(1.2).timeout
	who._walk_to(w.road_point(0.02))
	get_tree().create_timer(40.0).timeout.connect(func(): if is_instance_valid(who): who.queue_free())
	_start_follow()


static func _road_length(w: Wayside, a: float, b: float) -> float:
	var d := 0.0
	var prev := w.road_point(a)
	for i in range(1, 11):
		var p := w.road_point(lerpf(a, b, i / 10.0))
		d += prev.distance_to(p)
		prev = p
	return d


## Through the stretch's far gate into the destination area of the leg.
func _leave_stretch(to_area: String) -> void:
	var w: Wayside = main.world
	var gate: Dictionary = w.gates.get(to_area, {})
	if not gate.is_empty():
		_start_follow()
		if _follow:
			await main.companionship.walk_together(_party()[0], _follow, gate.position, 60.0)
		_stop_follow()
	await _cross(to_area)


func _camp(w: Wayside) -> void:
	var j: Dictionary = WorldState.journey
	j.phase = "camp"
	stage = "camping"
	var cs := CampScene.new()
	cs.name = "CampScene"
	add_child(cs)
	camp_scene = cs
	var rec: Dictionary = await cs.run(main, self, w, _party())
	(j.camps as Array).append(rec)
	camp_scene = null
	cs.queue_free()
	j.phase = "walking"
	for who in j.condition:
		j.condition[who].fatigue = clampf(float(j.condition[who].fatigue) - 0.6, 0.0, 1.0)
	WorldState._dirty = true


# ------------------------------------------------------------------ off camera / while the game was closed
## The journey goes on when nobody watches: between start hour and camp hour the party covers road at pace;
## nights are spent camped (recorded). Waypoints are passed and noted. Run every few seconds of real time and
## once on load (catch-up). Never moves a rendered character.
func _process(delta: float) -> void:
	if live or not active() or main == null:
		return
	_bg_t += delta
	if _bg_t < 2.0:
		return
	var now := WorldState.world_min
	var since := float(WorldState.journey.get("bg_min", now))
	WorldState.journey["bg_min"] = now
	if now - since > 0.01:
		advance_background(since, now)
	_bg_t = 0.0


func advance_background(from_min: float, to_min: float) -> void:
	var j: Dictionary = WorldState.journey
	var t := from_min
	while t < to_min and active():
		var h := fmod(t, 1440.0) / 60.0
		var step := minf(to_min - t, 30.0)
		var lg := leg()
		if lg.is_empty():
			break
		if h >= float(pace().start_hour) and h < float(pace().camp_hour):
			var k := float(j.km) + kmh(String(lg.terrain)) * step / 60.0
			_pass_waypoints(float(j.km), k)
			j.km = minf(k, float(lg.km))
			if float(j.km) >= float(lg.km) - 0.001:
				_next_leg()
				if not active():
					for who in j.party:
						WorldState.mind(who).set_location(String(j.dest), Vector3.INF)
		elif j.get("bg_camp_day", -1) != int(t / 1440.0):
			j.bg_camp_day = int(t / 1440.0)
			note("camped for the night off the road (out of view)", "camp", {"background": true})
		t += step
	WorldState._dirty = true


func status() -> Dictionary:
	var j: Dictionary = WorldState.journey
	if j.is_empty():
		return {}
	var lg := leg()
	return {"dest": j.dest, "purpose": j.purpose, "phase": j.phase, "leg": "%d/%d" % [int(j.leg) + 1, (j.legs as Array).size()],
		"route": lg.get("name", ""), "km": snappedf(float(j.km), 0.1), "leg_km": lg.get("km", 0), "stage": stage, "clock": WorldState.clock_text(),
		"events": (j.log as Array).size()}
