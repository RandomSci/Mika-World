class_name SanctuaryBrain
extends Node
## Mika's local decision layer for her home base (no network, no LLM calls). Region-level actions,
## sub-areas, lore and trials come from data/sanctuary.json. Each decision scores every action:
##   utility = base + needs fit (energy / curiosity) + mastery (unfinished trial) − repetition − distance + small jitter
## then executes it for real through the same APIs the bridge uses (navigate, Interactable.perform,
## cast, travel to the library and back). Thoughts are templated lines from the data file, shown as a
## subtitle and emitted as bridge events. An external AI can still drive her instead (brain off), or
## ask for one specific action (perform_action) and read region_context() to decide for itself.

signal thought(text: String, sub_area: String)
signal decided(decision: Dictionary)

const REGION := "arcane_sanctuary"

var main: Node
var mika: WorldCharacter
var enabled := false
var needs := {"energy": 0.8, "curiosity": 0.65}
var last_decision := {}
var history: Array = []          # recent decisions (id, utility, result)
var busy := false
var rng := RandomNumberGenerator.new()
var _recent: Array[String] = []
var _thought_used := {}
var _last_sub := ""
var _curious_cooldown := 0.0
var _cancel := false
var _failures := {}               # action id -> decisions left during which it is avoided after failing


## Sub-area at a position in whichever area is loaded ("" outside the Sanctuary region).
static func sub_area(world: Node, pos: Vector3) -> String:
	if world == null:
		return ""
	if world.has_method("sub_area_at"):
		return world.sub_area_at(pos)
	if world.get("area_id") == "arcane_library":
		return "ancient_spell_library"
	return ""


func setup(m: Node) -> void:
	main = m
	mika = main.characters["mika"]
	rng.seed = 2026


func set_enabled(v: bool) -> void:
	enabled = v
	_cancel = not v
	if v and not busy:
		_loop()


func status() -> Dictionary:
	return {"enabled": enabled, "busy": busy, "needs": _rounded(needs), "last_decision": last_decision,
		"recent": history.slice(maxi(0, history.size() - 6))}


static func _rounded(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[k] = snappedf(d[k], 0.01)
	return o


func _in_region() -> bool:
	return WorldState.areas.get(main.streaming.current_id, {}).get("region", "") == REGION


## What the decision layer can see: where she is, what each sub-area is for, what she can do and why.
func region_context() -> Dictionary:
	var data: Dictionary = WorldState.sanctuary
	var pos := mika.global_position
	var world = main.world
	var here := SanctuaryBrain.sub_area(world, pos)
	var subs := []
	for id in data.sub_areas:
		var s: Dictionary = data.sub_areas[id]
		var d := -1.0
		if main.streaming.current_id == "sanctuary":
			d = snappedf(Vector2(pos.x - s.center[0], pos.z - s.center[2]).length(), 0.1)
		subs.append({"id": id, "name": s.name, "purpose": s.purpose, "distance": d})
	var nearby := []
	for id in world.interactables:
		var it: Interactable = world.interactables[id]
		var dd := pos.distance_to(it.global_position)
		if dd < 14.0:
			var lore: Dictionary = data.lore.get(it.lore_id if it.lore_id != "" else id, {})
			nearby.append({"id": id, "label": it.label, "kind": it.kind if it.kind != "" else it.verb, "distance": snappedf(dd, 0.1),
				"times_done": it.times_done, "lore_title": lore.get("title", "")})
	nearby.sort_custom(func(a, b): return a.distance < b.distance)
	return {"region": REGION, "in_region": _in_region(), "story": data.story, "sub_area": here,
		"sub_area_info": data.sub_areas.get(here, {}).get("purpose", ""), "sub_areas": subs, "nearby": nearby,
		"actions": score_actions(), "needs": _rounded(needs), "mission": WorldState.mission_state(), "brain": {"enabled": enabled, "busy": busy}}


func _activity_of(action: Dictionary) -> String:
	var t: String = action.target
	if t == "@next_rune_target":
		var tgt := _next_rune_target()
		return tgt if tgt != "" else "rune_target_1"
	if t.begins_with("library:"):
		return t.get_slice(":", 1)
	return t


func _next_rune_target() -> String:
	var best := ""
	var best_n := 1 << 30
	for k in range(1, 5):
		var id := "rune_target_%d" % k
		var n := 1 << 20  # not in the loaded area: unknown count, lowest priority
		if main.world.interactables.has(id):
			n = (main.world.interactables[id] as Interactable).times_done
		if n < best_n:
			best_n = n
			best = id
	return best


func score_actions() -> Array:
	var out := []
	var pos := mika.global_position
	var open_trials := {}
	for tr in WorldState.sanctuary.trials:
		if not WorldState.trials_done.has(tr.id):
			if tr.has("activity"):
				open_trials[tr.activity] = tr.id
			else:
				open_trials["prefix:" + String(tr.activity_prefix)] = tr.id
	for a in WorldState.sanctuary.actions:
		var u: float = a.base
		var why := []
		for need in a.needs:
			var dlt: float = a.needs[need]
			if need == "energy":
				var fit: float = dlt * (1.0 - needs.energy) * 1.6 if dlt > 0.0 else dlt * (1.0 - needs.energy) * 1.2
				u += fit
				if absf(fit) > 0.05: why.append("energy %+.2f" % fit)
			elif need == "curiosity" and dlt < 0.0:
				var fit2: float = -dlt * needs.curiosity * 1.3
				u += fit2
				if fit2 > 0.05: why.append("curiosity +%.2f" % fit2)
		var act := _activity_of(a)
		if open_trials.has(act) or (act.begins_with("rune_target_") and open_trials.has("prefix:rune_target_")):
			u += 0.4
			why.append("trial +0.40")
		if _failures.get(a.id, 0) > 0:
			u -= 0.9
			why.append("failed recently -0.90")
		var reps := _recent.count(a.id)
		if reps > 0:
			u -= 0.35 * reps
			why.append("repetition -%.2f" % (0.35 * reps))
		if not _recent.is_empty() and _recent.back() == a.id:
			u -= 0.6
		var sub: Dictionary = WorldState.sanctuary.sub_areas.get(a.sub_area, {})
		var dist := 0.0
		if main.streaming.current_id == "sanctuary" and not sub.is_empty():
			dist = Vector2(pos.x - sub.center[0], pos.z - sub.center[2]).length()
		elif main.streaming.current_id == "arcane_library":
			dist = 0.0 if a.sub_area == "ancient_spell_library" else 30.0
		u -= dist * 0.006
		if a.target == "@cast" and not WorldState.skills.has("arcane_orb"):
			u -= 1.0
		out.append({"id": a.id, "kind": a.kind, "sub_area": a.sub_area, "target": act, "utility": snappedf(u, 0.001), "why": why})
	out.sort_custom(func(x, y): return x.utility > y.utility)
	return out


func _think(sub: String) -> void:
	var lines: Array = WorldState.sanctuary.thoughts.get(sub, [])
	if lines.is_empty():
		return
	var used: Array = _thought_used.get(sub, [])
	var pool := []
	for i in lines.size():
		if not used.has(i):
			pool.append(i)
	if pool.is_empty():
		used = []
		pool = range(lines.size())
	var pick: int = pool[rng.randi() % pool.size()]
	used.append(pick)
	_thought_used[sub] = used
	thought.emit(lines[pick], sub)


func _loop() -> void:
	busy = true
	while enabled and is_inside_tree():
		if main.streaming.state != "idle" or not main.travel.journey.is_empty():
			await get_tree().create_timer(0.5).timeout
			continue
		if not _in_region():
			# outside her home region: the brain only travels her home (other regions are not its domain)
			last_decision = {"id": "return_home", "utility": 1.0}
			await _travel("ritual_sanctuary")
			continue
		var scores := score_actions()
		var choice: Dictionary = scores[0]
		# a little indecision among near-equal options, so she isn't a metronome
		if scores.size() > 1 and absf(scores[0].utility - scores[1].utility) < 0.05 and rng.randf() < 0.5:
			choice = scores[1]
		last_decision = {"id": choice.id, "utility": choice.utility, "why": choice.why, "alternatives": scores.slice(1, 4).map(func(x): return [x.id, x.utility])}
		decided.emit(last_decision)
		var result := await perform_action(choice.id)
		if _cancel:
			break
		for k in _failures.keys():
			_failures[k] -= 1
			if _failures[k] <= 0:
				_failures.erase(k)
		if not result.get("ok", false):
			_failures[choice.id] = 3  # try something else for a while instead of insisting
		history.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "action": choice.id, "utility": choice.utility, "ok": result.get("ok", false),
			"detail": str(result.get("detail", result.get("error", ""))).left(90)})
		if history.size() > 60:
			history.pop_front()
		await get_tree().create_timer(rng.randf_range(1.2, 2.8)).timeout  # a beat between activities
	busy = false


## Execute one region action for real. Returns what actually happened.
func perform_action(action_id: String) -> Dictionary:
	var action: Dictionary = {}
	for a in WorldState.sanctuary.actions:
		if a.id == action_id:
			action = a
	if action.is_empty():
		return {"ok": false, "error": "unknown sanctuary action '%s'" % action_id}
	var result := {}
	var t: String = action.target
	if t.begins_with("library:"):
		if main.streaming.current_id != "arcane_library":
			var j := await _travel("ancient_spell_library")
			if not j.get("ok", false):
				return {"ok": false, "error": "could not reach the library: %s" % j.get("detail", "")}
		result = await _do_interactable(t.get_slice(":", 1), action.sub_area)
	else:
		if main.streaming.current_id != "sanctuary":
			var j2 := await _travel("ritual_sanctuary")
			if not j2.get("ok", false):
				return {"ok": false, "error": "could not return to the sanctuary: %s" % j2.get("detail", "")}
		if t == "@cast":
			result = await _do_cast()
		else:
			result = await _do_interactable(_activity_of(action), action.sub_area)
	if result.get("ok", false):
		for need in action.needs:
			needs[need] = clampf(needs[need] + float(action.needs[need]), 0.0, 1.0)
		# exploring makes her curious again; time passing slowly tires her
		needs.curiosity = clampf(needs.curiosity + 0.08, 0.0, 1.0)
		needs.energy = clampf(needs.energy - 0.02, 0.0, 1.0)
		_recent.append(action_id)
		if _recent.size() > 4:
			_recent.pop_front()
	result["action"] = action_id
	return result


func _travel(location: String) -> Dictionary:
	var r: Dictionary = main.travel.travel_to(location, "walk")
	if not r.get("ok", false):
		return {"ok": false, "detail": r.get("error", "?")}
	var res := [null]
	var cb := func(ev): if ev.event == "journey_finished": res[0] = ev
	main.travel.journey_event.connect(cb)
	var t0 := Time.get_ticks_msec()
	while res[0] == null and Time.get_ticks_msec() - t0 < 180000 and not _cancel:
		await get_tree().process_frame
	main.travel.journey_event.disconnect(cb)
	if res[0] == null:
		main.travel.cancel("brain timeout")
		return {"ok": false, "detail": "timeout"}
	return res[0]


func _walk_to(target: Vector3, sub: String) -> bool:
	for attempt in 2:
		if await _walk_once(target, sub):
			return true
		if _cancel:
			return false
		# blocked: step back a little and re-plan once
		var away := (mika.global_position - target)
		away.y = 0
		mika.navigate_to(mika.global_position + away.normalized() * 1.2)
		await get_tree().create_timer(1.0).timeout
	return false


func _walk_once(target: Vector3, sub: String) -> bool:
	mika.navigate_to(target, mika.global_position.distance_to(target) > 14.0)
	if mika.current_action != "navigate_to":
		return false
	_curious_cooldown = rng.randf_range(4.0, 9.0)
	var paused := false
	while mika.current_action == "navigate_to" and not _cancel:
		await get_tree().process_frame
		var here := SanctuaryBrain.sub_area(main.world, mika.global_position)
		if here != "" and here != _last_sub:
			_last_sub = here
			if rng.randf() < 0.7:
				_think(here)
		_curious_cooldown -= get_process_delta_time()
		if _curious_cooldown <= 0.0 and not paused and rng.randf() < 0.35:
			paused = true
			var poi = _curious_poi()
			if poi != null:
				# stop for a moment to look at something on the way
				mika.look_at_point(poi)
				thought.emit(WorldState.sanctuary.thoughts.curious[rng.randi() % WorldState.sanctuary.thoughts.curious.size()], "curious")
				await get_tree().create_timer(2.2).timeout
				mika.navigate_to(target, mika.global_position.distance_to(target) > 14.0)
	return mika.global_position.distance_to(target) < 2.5


func _curious_poi():
	var pos := mika.global_position
	var best = null
	var best_d := 1e9
	for id in main.world.points_of_interest:
		var p: Vector3 = main.world.points_of_interest[id].position
		var d := pos.distance_to(p)
		if d > 3.0 and d < 11.0 and d < best_d and not String(id).begins_with("gate:"):
			best = p + Vector3(0, 1.0, 0)
			best_d = d
	return best


func _do_interactable(id: String, sub: String) -> Dictionary:
	if not main.world.interactables.has(id):
		return {"ok": false, "error": "no interactable '%s' in %s" % [id, main.streaming.current_id]}
	var it: Interactable = main.world.interactables[id]
	await _walk_to(it.approach_point(), sub)
	if _cancel:
		return {"ok": false, "error": "brain stopped"}
	var r: Dictionary = await it.perform(mika)
	if r.get("ok", false) and rng.randf() < 0.45:
		_think(sub)
	return r


func _do_cast() -> Dictionary:
	var spot := Vector3(0.0, Sanctuary.DAIS_TOP + 0.05, 0.9)
	await _walk_to(spot, "ritual_circle")
	mika.look_at_point(Vector3(0, 1.5, -6.0))
	await get_tree().create_timer(0.8).timeout
	if not main.world.has_space_for_magic(mika.global_position):
		return {"ok": false, "error": "not enough space to cast"}
	var spell = mika.cast_spell(ArcaneOrbSpell, "prepare_and_cast")
	if spell == null:
		return {"ok": false, "error": "cast refused"}
	while is_instance_valid(spell):
		await get_tree().process_frame
	var changes := WorldState.record_activity({"id": "cast_in_circle", "verb": "practice", "label": "Cast the Arcane Orb in the circle"}, {"skills": {"arcane_orb": 0.05}})
	if rng.randf() < 0.5:
		_think("ritual_circle")
	return {"ok": true, "detail": "cast the Arcane Orb in the ritual circle", "changes": changes}
