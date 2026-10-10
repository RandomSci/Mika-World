class_name SanctuaryBrain
extends Node
## Mika's deterministic planner for her home region, built on multi-stage ACTIVITIES instead of short
## one-shot actions. Every decision is generated from the real world and executed through the same
## systems a player or the AI bridge would use; outcomes come back from the engine and feed the next choice.
##
## Activities (options are generated, never a fixed list):
##   research    - pick an unread book (any order), walk / travel to it, really read its pages
##   magic       - practise a castable spell on a fitting reactive target; several attempts while improving;
##                 experiments prefer reactions she has never observed; stops on success, fatigue or failure
##   investigate - follow a story lead from StoryManager (wake the gate sign, the pond, the Heartstone...)
##   explore     - visit the least-recently seen sub-area, look around at its points of interest
##   rest        - sit and meditate (longer when more tired), watch the pond
##   alchemy     - brew the known recipe, or experiment when curious and the recipe is unknown
##   converse    - approach a visiting traveller she has not spoken to this visit
##   journal     - write an entry from verified events
## Utility = base + needs (energy, curiosity, mastery drive, social) + story pull + novelty
##           - repetition (same kind / same target recently) - travel + small jitter.
## An optional curiosity model (CuriosityModule) may only add a bonus to one of the currently valid options.
## Private reasoning (scores, choices) is never spoken: it is a developer-HUD thought and a bridge event.

signal thought(text: String, sub_area: String)
signal decided(decision: Dictionary)

const REGION := "arcane_sanctuary"

var main: Node
var mika: WorldCharacter
var enabled := false
var busy := false
var needs := {"energy": 0.85, "curiosity": 0.7, "mastery": 0.6, "social": 0.4}
var last_decision := {}
var history: Array = []
var current := {}              # the running activity {kind, label, key, stage, started}
var rng := RandomNumberGenerator.new()
var _recent_kinds: Array[String] = []
var _recent_targets: Array[String] = []
var _failures := {}            # option key -> decisions left to avoid
var _interrupt := ""
var _cancel := false
var _speak_cd := 0.0
var _talked_this_visit := {}
var curiosity_bonus := {}      # option key -> bonus from the curiosity module (one decision only)
var viewer_request := {}            # spell id -> {target, t}: a viewer suggestion, kept until chosen or 4 minutes old
const VIEWER_REQUEST_S := 240.0


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
	if not v and main.book_reader.reading():
		main.book_reader.stop()
	if v and not busy:
		_loop()


func interrupt(reason: String) -> void:
	_interrupt = reason


func status() -> Dictionary:
	var n := {}
	for k in needs:
		n[k] = snappedf(needs[k], 0.01)
	return {"enabled": enabled, "busy": busy, "needs": n, "current": current, "last_decision": last_decision,
		"recent": history.slice(maxi(0, history.size() - 8))}


func _in_region() -> bool:
	return WorldState.areas.get(main.streaming.current_id, {}).get("region", "") == REGION


# ------------------------------------------------------------------ option generation
func options() -> Array:
	var out := []
	var here: String = main.streaming.current_id
	# research: books with unread (visible) pages
	for bid in BookLibrary.data().books:
		var b := BookLibrary.book(bid)
		var visible := (b.pages as Array).filter(func(pg): return not pg.has("requires_knowledge") or WorldState.knowledge.has(pg.requires_knowledge))
		var unread := visible.size() - BookLibrary.pages_read(bid).filter(func(i): return i < visible.size()).size()
		if unread <= 0:
			continue
		var loc := _book_location(bid)
		if loc.is_empty():
			continue
		out.append({"kind": "research", "key": "research:" + bid, "book": bid, "interactable": loc.interactable, "area": loc.area,
			"label": "read %s" % b.title, "unread": unread})
	# magic: castable spells x fitting reactive targets in this area
	if here == "sanctuary":
		var reactives: Dictionary = main.magic.reactives()
		for s in main.magic.known_spells():
			if not s.castable or s.id == "elemental_charge":
				continue
			var spell := MagicSystem.spell(s.id)
			var best_t := ""
			var best_novel := false
			for rid in reactives:
				var r: ReactiveElement = reactives[rid]
				var kinds: Array = spell.get("target_kinds", ["*"])
				if not kinds.has("*") and not kinds.has(r.kind):
					continue
				var novel: bool = not WorldState.knowledge.keys().any(func(k): return String(k).begins_with("reaction:%s:%s:" % [s.id, r.kind]))
				if best_t == "" or (novel and not best_novel) or (novel == best_novel and rng.randf() < 0.3):
					best_t = rid
					best_novel = novel
			# a viewer asked for this spell on a particular object: offer exactly that (if it is a valid target)
			var asked: String = viewer_request.get(s.id, {}).get("target", "")
			if asked != "" and reactives.has(asked):
				var ak: Array = spell.get("target_kinds", ["*"])
				if ak.has("*") or ak.has((reactives[asked] as ReactiveElement).kind):
					best_t = asked
					best_novel = not WorldState.knowledge.keys().any(func(k): return String(k).begins_with("reaction:%s:%s:" % [s.id, (reactives[asked] as ReactiveElement).kind]))
			if best_t != "":
				out.append({"kind": "magic", "key": "magic:%s:%s" % [s.id, best_t], "spell": s.id, "target": best_t, "novel": best_novel,
					"mastery": s.mastery, "label": "%s %s at %s" % ["experiment with" if best_novel else "practise", s.name, reactives[best_t].label]})
	# story leads (reading leads are covered by research options, with a story bonus)
	for l in main.story.next_leads():
		if l.activity == "research":
			continue
		if not main.magic.can_cast(String(l.get("spell", ""))).ok:
			continue
		out.append({"kind": "investigate", "key": "investigate:%s:%s" % [l.target, l.spell], "target": l.target, "spell": l.spell, "label": l.lead})
	# explore
	for sid in WorldState.sanctuary.sub_areas:
		if sid == "ancient_spell_library":
			continue
		out.append({"kind": "explore", "key": "explore:" + sid, "sub_area": sid, "label": "explore the %s" % WorldState.sanctuary.sub_areas[sid].name})
	# rest
	var rest_labels := {"garden_meditate": "meditate on the Still Stone", "watchpoint_rest": "rest on the watchpoint bench", "pond_reflect": "watch the pond"}
	for seat in rest_labels:
		out.append({"kind": "rest", "key": "rest:" + seat, "interactable": seat, "label": rest_labels[seat]})
	# alchemy
	if main.world is Sanctuary and main.world.alchemy and main.world.alchemy.bowl_state == "empty":
		var knows: bool = WorldState.knowledge.has("recipe:luminous_draught")
		if knows or not WorldState.knowledge.has("alchemy:ember_salt_fizz"):
			out.append({"kind": "alchemy", "key": "alchemy", "label": "brew a Luminous Draught" if knows else "experiment at the alchemy table"})
	# converse
	for nid in main.npcs.present:
		var npc = main.npcs.present[nid]
		if is_instance_valid(npc) and npc.state == "idle" and not _talked_this_visit.has(nid + str(main.dialogue.state_of(nid).visits)):
			out.append({"kind": "converse", "key": "converse:" + nid, "npc": nid, "label": "talk with %s" % main.dialogue.travellers[nid].name})
	# journal
	if not Journal.compose().is_empty():
		out.append({"kind": "journal", "key": "journal", "label": "write in my journal"})
	return out


func _book_location(bid: String) -> Dictionary:
	match bid:
		"liber_orbis": return {"interactable": "altar_spellbook", "area": "sanctuary"}
		"scroll_first_circle": return {"interactable": "scroll_first_circle", "area": "sanctuary"}
		"keepers_daybook": return {"interactable": "keepers_daybook", "area": "sanctuary"}
		"chamber_tablet": return {"interactable": "chamber_tablet", "area": "sanctuary"}
		"gate_inscription": return {"interactable": "gate_inscription", "area": "sanctuary"}
		"elementa_prima": return {"interactable": "lectern_warding_glyph", "area": "arcane_library"}
		"signs_and_wakings": return {"interactable": "research_desk", "area": "arcane_library"}
		"on_gathering": return {"interactable": "desk_gathering", "area": "arcane_library"}
	return {}


func score(o: Dictionary) -> Dictionary:
	var u := 0.0
	var why := []
	match o.kind:
		"research":
			u = 0.4 + needs.curiosity * 0.45 + minf(o.unread, 4) * 0.04
			if main.story.next_leads().any(func(l): return l.get("book", "") == o.book):
				u += 0.45
				why.append("story lead +0.45")
			if o.area != main.streaming.current_id:
				u -= 0.18
				why.append("needs travel -0.18")
		"magic":
			u = 0.35 + needs.mastery * 0.5 * (1.0 - minf(float(o.mastery), 3.0) / 3.0)
			if o.novel:
				u += 0.3 * needs.curiosity + 0.1
				why.append("untested reaction")
			u -= (1.0 - needs.energy) * 0.45
		"investigate":
			u = 0.85
			why.append("story lead")
		"explore":
			var last: int = int(WorldState.activity_counts.get(o.key, {}).get("last_unix", 0))
			var age := minf((Time.get_unix_time_from_system() - last) / 600.0, 1.0) if last > 0 else 1.0
			u = 0.2 + needs.curiosity * 0.35 * age
		"rest":
			u = 0.1 + (1.0 - needs.energy) * 0.95
			if o.interactable == "pond_reflect":
				u -= 0.05
		"alchemy":
			var wants: bool = WorldState.knowledge.has("recipe:luminous_draught") and int(WorldState.inventory.get("luminous_draught", 0)) == 0
			u = 0.4 + (0.25 if wants else 0.05) + needs.curiosity * 0.15
		"converse":
			u = 0.55 + needs.social * 0.5
			why.append("visitor present")
		"journal":
			# grows with the number of things done since the last entry: she writes after a meaningful stretch
			var unwritten := WorldState.activity_log.size() - int(WorldState.knowledge.get("journal_cursor", 0))
			u = 0.2 + 0.055 * minf(unwritten, 14)
			if unwritten >= 8:
				why.append("%d things unwritten" % unwritten)
	var kind_reps := _recent_kinds.slice(maxi(0, _recent_kinds.size() - 3)).count(o.kind)
	if kind_reps > 0:
		u -= 0.22 * kind_reps
		why.append("same kind recently -%.2f" % (0.22 * kind_reps))
	if _recent_targets.has(o.key):
		u -= 0.55
		why.append("same target recently -0.55")
	if _failures.get(o.key, 0) > 0:
		u -= 0.9
		why.append("failed recently -0.90")
	if o.kind == "magic" and viewer_request.get(o.spell, {}).get("target", "") == o.target:
		u += 0.45
		why.append("a viewer suggested it +0.45")
	if curiosity_bonus.has(o.key):
		u += float(curiosity_bonus[o.key])
		why.append("curiosity proposal +%.2f" % float(curiosity_bonus[o.key]))
	u += rng.randf_range(0.0, 0.06)
	return {"utility": snappedf(u, 0.001), "why": why}


func ranked() -> Array:
	var scored := []
	for o in options():
		scored.append(o.merged(score(o)))
	scored.sort_custom(func(a, b): return a.utility > b.utility)
	return scored


## What the decision layer can see (also served over the bridge as region_context).
func region_context() -> Dictionary:
	var data: Dictionary = WorldState.sanctuary
	var pos := mika.global_position
	var here := SanctuaryBrain.sub_area(main.world, pos)
	var subs := []
	for id in data.sub_areas:
		var s: Dictionary = data.sub_areas[id]
		subs.append({"id": id, "name": s.name, "purpose": s.purpose,
			"distance": snappedf(Vector2(pos.x - s.center[0], pos.z - s.center[2]).length(), 0.1) if main.streaming.current_id == "sanctuary" else -1.0})
	return {"region": REGION, "in_region": _in_region(), "story": main.story.describe(), "sub_area": here,
		"sub_area_info": data.sub_areas.get(here, {}).get("purpose", ""), "sub_areas": subs,
		"options": ranked().slice(0, 10).map(func(o): return {"key": o.key, "kind": o.kind, "label": o.label, "utility": o.utility, "why": o.why}),
		"needs": status().needs, "mission": WorldState.mission_state(), "spells": main.magic.known_spells(),
		"visitors": main.npcs.nearby(pos, 60.0), "current": current}


# ------------------------------------------------------------------ main loop
func _loop() -> void:
	busy = true
	while enabled and is_inside_tree():
		if main.streaming.state != "idle" or not main.travel.journey.is_empty():
			await get_tree().create_timer(0.5).timeout
			continue
		if not _in_region():
			current = {"kind": "travel", "label": "return home"}
			await _travel("ritual_sanctuary")
			continue
		if main.curiosity:
			await main.curiosity.consult(self)
		var scored := ranked()
		if scored.is_empty():
			await get_tree().create_timer(2.0).timeout
			continue
		var choice: Dictionary = scored[0]
		curiosity_bonus.clear()
		if choice.kind == "magic":
			viewer_request.erase(choice.spell)
		var now_s := Time.get_ticks_msec() / 1000.0
		for k in viewer_request.keys():
			if now_s - float(viewer_request[k].t) > VIEWER_REQUEST_S:
				viewer_request.erase(k)
		last_decision = {"key": choice.key, "kind": choice.kind, "label": choice.label, "utility": choice.utility, "why": choice.why,
			"alternatives": scored.slice(1, 4).map(func(x): return [x.label, x.utility])}
		decided.emit(last_decision)
		_private_thought("I'll %s." % choice.label)
		current = {"kind": choice.kind, "label": choice.label, "key": choice.key, "stage": "starting", "started": snappedf(Time.get_ticks_msec() / 1000.0, 0.1)}
		var t0 := Time.get_ticks_msec()
		var result: Dictionary = await run_activity(choice)
		if _cancel:
			break
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		WorldState.note_activity(choice.key)
		WorldState.note_activity("kind:" + choice.kind)
		_recent_kinds.append(choice.kind)
		_recent_targets.append(choice.key)
		if _recent_kinds.size() > 6:
			_recent_kinds.pop_front()
		if _recent_targets.size() > 5:
			_recent_targets.pop_front()
		for k in _failures.keys():
			_failures[k] -= 1
			if _failures[k] <= 0:
				_failures.erase(k)
		if not result.get("ok", false):
			_failures[choice.key] = 3
		needs.social = clampf(needs.social + 0.05, 0.0, 1.0)
		needs.curiosity = clampf(needs.curiosity + 0.04, 0.0, 1.0)
		needs.mastery = clampf(needs.mastery + 0.05, 0.0, 1.0)
		history.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "kind": choice.kind, "label": choice.label, "utility": choice.utility,
			"ok": result.get("ok", false), "seconds": snappedf(secs, 0.1), "detail": str(result.get("detail", "")).left(110)})
		if history.size() > 150:
			history.pop_front()
		current = {}
		if main.curiosity:
			main.curiosity.on_activity_finished(choice, result)
		await get_tree().create_timer(rng.randf_range(0.8, 2.4)).timeout
	busy = false


# ------------------------------------------------------------------ activities
func run_activity(o: Dictionary) -> Dictionary:
	_interrupt = ""
	match o.kind:
		"research": return await _research(o)
		"magic": return await _magic(o)
		"investigate": return await _investigate(o)
		"explore": return await _explore(o)
		"rest": return await _rest(o)
		"alchemy": return await _use("alchemy_table")
		"converse": return await _converse(o)
		"journal": return await _journal()
	return {"ok": false, "detail": "unknown activity"}


func _research(o: Dictionary) -> Dictionary:
	if main.streaming.current_id != o.area:
		current.stage = "travelling to the library"
		var j := await _travel("ancient_spell_library" if o.area == "arcane_library" else "ritual_sanctuary")
		if not j.get("ok", false):
			return {"ok": false, "detail": "could not reach %s" % o.area}
	current.stage = "reading"
	var r := await _use(o.interactable)
	var reading: Dictionary = r.get("reading", {})
	var learned: Array = reading.get("learned", [])
	needs.curiosity = clampf(needs.curiosity - 0.08 * reading.get("pages_read", []).size(), 0.0, 1.0)
	needs.energy = clampf(needs.energy - 0.04, 0.0, 1.0)
	if learned.any(func(k): return String(k).begins_with("incantation:")):
		needs.mastery = clampf(needs.mastery + 0.25, 0.0, 1.0)   # a new incantation makes her want to try it
		_maybe_say(["I want to try that incantation for real.", "Reading it is one thing. Now I should practise it."], 0.6)
	if o.area == "arcane_library":
		await _travel("ritual_sanctuary")
	return r


## Several real attempts while she is improving; stops when the goal effect happens, when she tires,
## or after a refused cast.
func _magic(o: Dictionary) -> Dictionary:
	var goal := ""
	if o.spell == "wind_gust" and String(o.target).begins_with("brazier"):
		goal = "extinguished"
	var attempts := 0
	var res := {}
	var effects := []
	while attempts < 3 and not _cancel:
		attempts += 1
		current.stage = "attempt %d" % attempts
		if not await _stand_for_cast(o.spell, o.target):
			return {"ok": false, "detail": "no clear casting position for %s" % o.target}
		res = await main.magic.cast(mika, o.spell, o.target)
		if res.get("outcome", "") == "refused":
			return {"ok": false, "detail": res.get("reason", "refused")}
		effects.append(res.get("effect", "none"))
		needs.energy = clampf(needs.energy - 0.07, 0.0, 1.0)
		needs.mastery = clampf(needs.mastery - 0.08, 0.0, 1.0)
		_react_to_result(res, attempts, goal)
		if goal == "" or res.get("effect", "") == goal or needs.energy < 0.3 or _interrupt != "":
			break
		await get_tree().create_timer(rng.randf_range(1.5, 3.0)).timeout
	res["attempts"] = attempts
	res["effects"] = effects
	res["ok"] = res.get("outcome", "") in ["hit", "self"]
	res["detail"] = "%d attempt(s): %s" % [attempts, ", ".join(effects)]
	return res


func _react_to_result(res: Dictionary, attempt: int, goal: String) -> void:
	var eff := String(res.get("effect", ""))
	var ch: Dictionary = res.get("changes", {})
	var first_time: bool = ch.keys().any(func(k): return String(k).begins_with("knowledge.reaction:") and ch[k][0] == 0)
	if goal != "" and eff != goal and eff in ["flicker", "guttered"] and attempt >= 2:
		_maybe_say(["Ha, still not enough. Breathe out first, then the words.", "Closer. Not there yet."] if WorldState.knowledge.has("fact:breath_before_word") else ["Ha, it barely moved. My gust needs more practice.", "Not enough. Again."], 0.8)
	elif first_time and eff == "extinguished":
		_maybe_say(["It went out! The gust was strong enough this time."], 1.0)
	elif first_time:
		var lines := {"surge": ["The water stood up! Just for a moment."], "shattered": ["It shattered. I'll let it grow back."],
			"revealed": ["There it is. A sign, woken."], "pattern_reflection": ["Seven points. The same shape as the gate sign."],
			"awakened": ["Three beats. It's awake."], "arcane_flame": ["Blue fire. That's beautiful."]}
		if lines.has(eff):
			_maybe_say(lines[eff], 1.0)


func _investigate(o: Dictionary) -> Dictionary:
	current.stage = "following a lead"
	_private_thought("Lead: %s" % o.label)
	if String(o.spell) != "":
		return await _magic({"spell": o.spell, "target": o.target, "kind": "magic", "key": o.key})
	return {"ok": false, "detail": "no way to follow this lead yet"}


func _explore(o: Dictionary) -> Dictionary:
	var sub: Dictionary = WorldState.sanctuary.sub_areas[o.sub_area]
	var c := Vector3(sub.center[0], 0, sub.center[2])
	c.y = main.world.ground_at(c.x, c.z) if main.world.has_method("ground_at") else 0.0
	current.stage = "walking to the %s" % sub.name
	var map := mika.get_world_3d().navigation_map
	var dest := NavigationServer3D.map_get_closest_point(map, c + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)))
	if not await _walk(dest):
		return {"ok": false, "detail": "could not reach the %s" % sub.name}
	current.stage = "looking around"
	var pois := []
	for id in main.world.points_of_interest:
		var p: Vector3 = main.world.points_of_interest[id].position
		if p.distance_to(mika.global_position) < float(sub.radius) + 4.0 and not String(id).begins_with("gate:"):
			pois.append(p)
	pois.shuffle()
	var looked := 0
	for p in pois.slice(0, rng.randi_range(2, 4)):
		mika.look_at_point(p + Vector3(0, 1.0, 0))
		mika.look_head_at(p + Vector3(0, 1.0, 0))
		await get_tree().create_timer(rng.randf_range(2.0, 4.0)).timeout
		looked += 1
	mika.look_head_at(null)
	var lines: Array = WorldState.sanctuary.thoughts.get(o.sub_area, [])
	if not lines.is_empty():
		_private_thought(lines[rng.randi() % lines.size()])
	needs.curiosity = clampf(needs.curiosity - 0.12, 0.0, 1.0)
	needs.energy = clampf(needs.energy - 0.03, 0.0, 1.0)
	for id in ["gate_inscription", "chamber_tablet"]:
		var it = main.world.interactables.get(id)
		if it and it.global_position.distance_to(mika.global_position) < 9.0 and BookLibrary.pages_read(it.book_id).is_empty():
			await _use(id)
	return {"ok": true, "detail": "looked at %d places in the %s" % [looked, sub.name]}


func _rest(o: Dictionary) -> Dictionary:
	var it: Interactable = main.world.interactables.get(o.interactable)
	if it == null:
		return {"ok": false, "detail": "no %s here" % o.interactable}
	var deficit: float = 1.0 - needs.energy
	it.duration_override = clampf(12.0 + deficit * 50.0, 10.0, 60.0)   # a real rest takes as long as she needs
	current.stage = "resting %.0f s" % it.duration_override
	var r := await _use(o.interactable)
	if r.get("ok", false):
		needs.energy = clampf(needs.energy + 0.35 + deficit * 0.3, 0.0, 1.0)
		needs.curiosity = clampf(needs.curiosity + 0.15, 0.0, 1.0)
	return r


func _converse(o: Dictionary) -> Dictionary:
	var npc = main.npcs.present.get(o.npc)
	if npc == null or not is_instance_valid(npc):
		return {"ok": false, "detail": "they left"}
	current.stage = "walking over to %s" % main.dialogue.travellers[o.npc].name
	var to: Vector3 = npc.global_position + (mika.global_position - npc.global_position).normalized() * 1.6
	await _walk(to)
	current.stage = "talking"
	var r: Dictionary = await main.dialogue.converse(o.npc, mika)
	_talked_this_visit[o.npc + str(main.dialogue.state_of(o.npc).visits)] = true
	needs.social = clampf(needs.social - 0.4, 0.0, 1.0)
	return r


func _journal() -> Dictionary:
	var it: Interactable = main.world.interactables.get("mika_journal")
	if it == null:
		return {"ok": false, "detail": "the journal is in the sanctuary"}
	await _walk(it.approach_point())
	var entry := Journal.compose()
	if entry.is_empty():
		return {"ok": false, "detail": "nothing new to write"}
	current.stage = "writing"
	mika.look_at_point(it.global_position)
	mika.look_head_at(it.global_position + Vector3(0, 0.75, 0))
	await get_tree().create_timer(clampf(String(entry.text).split(" ").size() / 2.5, 4.0, 14.0)).timeout
	var j: Array = WorldState.knowledge.get("journal", []).duplicate()
	j.append({"heading": entry.heading, "text": entry.text, "unix": int(Time.get_unix_time_from_system())})
	WorldState.knowledge["journal"] = j
	WorldState.knowledge["journal_cursor"] = entry.cursor
	var ch := WorldState.record_activity({"id": "journal_write", "verb": "write", "label": entry.heading}, {})
	mika.look_head_at(null)
	return {"ok": true, "detail": "wrote %s: %s" % [entry.heading, String(entry.text).left(80)], "entry": entry, "changes": ch}


# ------------------------------------------------------------------ helpers
func _use(id: String) -> Dictionary:
	var it: Interactable = main.world.interactables.get(id)
	if it == null:
		return {"ok": false, "detail": "no '%s' in %s" % [id, main.streaming.current_id]}
	if not await _walk(it.approach_point()):
		return {"ok": false, "detail": "could not reach %s" % it.label}
	if not it.in_reach(mika.global_position):
		# the walk tolerance is looser than the interaction reach: close the last metre
		await _walk(it.approach_point())
	return await it.perform(mika)


func _walk(target: Vector3) -> bool:
	for attempt in 2:
		mika.navigate_to(target, mika.global_position.distance_to(target) > 14.0)
		if mika.current_action != "navigate_to":
			if mika.global_position.distance_to(target) < 2.0:
				return true
			continue
		while mika.current_action == "navigate_to" and not _cancel:
			await get_tree().process_frame
		if mika.global_position.distance_to(target) < 2.5:
			return true
		var away := mika.global_position - target
		away.y = 0
		mika.navigate_to(mika.global_position + away.normalized() * 1.2)
		await get_tree().create_timer(1.0).timeout
	return mika.global_position.distance_to(target) < 2.5


## Find a nearby navmesh spot with line of sight, range and space for this spell, then walk there.
func _stand_for_cast(spell_id: String, target_id: String) -> bool:
	var target: ReactiveElement = main.magic.reactives().get(target_id)
	if target == null:
		return false
	if main.magic.validate(spell_id, mika, target).ok and main.world.has_space_for_magic(mika.global_position):
		return true
	var tp := target.aim_point()
	var map := mika.get_world_3d().navigation_map
	var rangev := float(MagicSystem.spell(spell_id).get("range", 8.0))
	var from_dir := Vector3(mika.global_position.x - tp.x, 0, mika.global_position.z - tp.z)
	var base := atan2(from_dir.x, from_dir.z)
	for ring in [minf(5.0, rangev - 1.0), minf(3.5, rangev - 1.0), minf(7.0, rangev - 1.0)]:
		for k in 12:
			var ang: float = base + (k / 2) * 0.5 * (1.0 if k % 2 == 0 else -1.0)
			var want: Vector3 = tp + Vector3(sin(ang), 0, cos(ang)) * float(ring)
			var p := NavigationServer3D.map_get_closest_point(map, want)
			if p.distance_to(Vector3(want.x, p.y, want.z)) > 0.8:
				continue
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.3, 0), tp)
			q.exclude = [mika.get_rid()]
			var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and not target.owns_collider(hit.collider) and (hit.position as Vector3).distance_to(tp) > target.aim_radius + 0.35:
				continue
			if not main.world.has_space_for_magic(p):
				continue
			if await _walk(p):
				# check where she actually stopped (navigation can stop up to ~0.7 m short)
				if main.magic.validate(spell_id, mika, target).ok and main.world.has_space_for_magic(mika.global_position):
					return true
	return false


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


func _private_thought(text: String) -> void:
	thought.emit(VoiceService.clean(text), SanctuaryBrain.sub_area(main.world, mika.global_position))


## Spoken only when the moment justifies it, at most once a minute.
func _maybe_say(lines: Array, chance: float) -> void:
	if Time.get_ticks_msec() / 1000.0 < _speak_cd or rng.randf() > chance:
		return
	_speak_cd = Time.get_ticks_msec() / 1000.0 + 60.0
	main.voice.say("mika", lines[rng.randi() % lines.size()])


## Compatibility with the bridge's perform_action{action}: runs the matching activity once.
func perform_action(action_id: String) -> Dictionary:
	for o in options():
		if o.key == action_id or o.get("interactable", "") == action_id or o.label == action_id:
			return await run_activity(o)
	return {"ok": false, "error": "no available activity '%s' (see region_context.options)" % action_id}
