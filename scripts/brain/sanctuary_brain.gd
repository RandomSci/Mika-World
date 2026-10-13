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
##   attune      - attune to the ritual circle / the Heartstone, offered only once she has read the text that
##                 describes it (the interactable's lore_id); an open trial for it adds a pull
## Utility = base + needs (energy, curiosity, mastery drive, social) + story pull + novelty
##           - repetition (same kind / same target recently) - travel + small jitter.
## An optional curiosity model (CuriosityModule) may only add a bonus to one of the currently valid options.
## Private reasoning (scores, choices) is never spoken: it is a developer-HUD thought and a bridge event.

signal thought(text: String, sub_area: String)
signal decided(decision: Dictionary)

const REGION := "arcane_sanctuary"

var main: Node
var me: WorldCharacter            # the mage this planner instance drives
var mika: WorldCharacter:         # compatibility alias (older callers read brain.mika)
	get: return me
var agent_id := "mika"
var mind: MageMind                # HER knowledge, inventory, skills and trials (never another mage's)
var profile := {}                 # data/mages.json entry: activities, temperament, voice, signature spell
var threat: Monster = null        # a creature attacking her right now (set by the spawner)
var hold := false                 # another mage asked to talk: finish nothing new until released
var _speak_lines := {}
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


func setup(m: Node, who := "mika") -> void:
	main = m
	agent_id = who
	me = main.characters[who]
	mind = WorldState.mind(who)
	Progression.load_data()
	profile = Progression.mages.get(who, {})
	rng.seed = 2026 + hash(who) % 1000


func _voice() -> String:
	return String(profile.get("voice", agent_id))


func _allowed(kind: String) -> bool:
	return (profile.get("activities", []) as Array).is_empty() or (profile.activities as Array).has(kind)


func is_lead() -> bool:
	return agent_id == "mika"


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
		var visible := (b.pages as Array).filter(func(pg): return not pg.has("requires_knowledge") or mind.knowledge.has(pg.requires_knowledge))
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
		for s in main.magic.known_spells(agent_id):
			if not s.castable or s.id == "elemental_charge":
				continue
			var spell := MagicSystem.spell(s.id)
			var best_t := ""
			var best_novel := false
			var best_rank := -1
			for rid in reactives:
				var r: ReactiveElement = reactives[rid]
				if r is Monster:
					continue          # creatures are hunted (their own option), not practice targets
				var kinds: Array = spell.get("target_kinds", ["*"])
				if not kinds.has("*") and not kinds.has(r.kind):
					continue
				if mind.knowledge.has("noeffect:%s:%s" % [s.id, r.kind]) and not _advances_trial(rid):
					continue          # she has seen this spell do nothing to this kind of object
				var novel: bool = not mind.knowledge.keys().any(func(k): return String(k).begins_with("reaction:%s:%s:" % [s.id, r.kind]))
				var rank := (2 if _advances_trial(rid) else 0) + (1 if novel else 0)
				if best_t == "" or rank > best_rank or (rank == best_rank and rng.randf() < 0.3):
					best_t = rid
					best_novel = novel
					best_rank = rank
			# a viewer asked for this spell on a particular object: offer exactly that (if it is a valid target)
			var asked: String = viewer_request.get(s.id, {}).get("target", "")
			if asked != "" and reactives.has(asked):
				var ak: Array = spell.get("target_kinds", ["*"])
				if ak.has("*") or ak.has((reactives[asked] as ReactiveElement).kind):
					best_t = asked
					best_novel = not mind.knowledge.keys().any(func(k): return String(k).begins_with("reaction:%s:%s:" % [s.id, (reactives[asked] as ReactiveElement).kind]))
			if best_t != "":
				out.append({"kind": "magic", "key": "magic:%s:%s" % [s.id, best_t], "spell": s.id, "target": best_t, "novel": best_novel,
					"mastery": s.mastery, "trial": _advances_trial(best_t), "label": "%s %s at %s" % ["experiment with" if best_novel else "practise", s.name, reactives[best_t].label]})
	# story leads (reading leads are covered by research options, with a story bonus) - the story is Mika's
	for l in (main.story.next_leads() if _allowed("investigate") else []):
		if l.activity == "research":
			continue
		if not main.magic.can_cast(String(l.get("spell", "")), agent_id).ok:
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
		var knows: bool = mind.knowledge.has("recipe:luminous_draught")
		if knows or not mind.knowledge.has("alchemy:ember_salt_fizz"):
			out.append({"kind": "alchemy", "key": "alchemy", "label": "brew a Luminous Draught" if knows else "experiment at the alchemy table"})
	# converse (the travellers' memories are about Mika in this slice)
	for nid in (main.npcs.present if _allowed("converse") else {}):
		var npc = main.npcs.present[nid]
		if is_instance_valid(npc) and npc.state == "idle" and not _talked_this_visit.has(nid + str(main.dialogue.state_of(nid).visits)):
			out.append({"kind": "converse", "key": "converse:" + nid, "npc": nid, "label": "talk with %s" % main.dialogue.travellers[nid].name})
	# attune: only where the place exists and once she has read what it is for
	if here == "sanctuary":
		for id in ATTUNE:
			var it = main.world.interactables.get(id)
			if it and (ATTUNE[id] as Array).any(func(k): return mind.knowledge.has(k)):
				out.append({"kind": "attune", "key": "attune:" + id, "interactable": id, "label": String(it.label).to_lower(),
					"attuned": mind.activity_counts.has("attune:" + id)})
	# hunt: only creatures SHE can see right now (no knowledge of what lurks out of sight)
	if main.spawner and here == "sanctuary":
		for mon in main.spawner.perceived_by(me):
			var mk: String = mon.kind
			var mdef: Dictionary = Spawner.data.monsters.get(mk, {})
			out.append({"kind": "hunt", "key": "hunt:" + mon.id, "monster": mon.id, "monster_kind": mk, "tier": mon.tier(),
				"attacking_me": mon.target_mage == me, "distance": snappedf(me.global_position.distance_to(mon.global_position), 0.1),
				"label": "%s the %s" % ["fight off" if mon.target_mage == me else "hunt", String(mdef.get("name", mk)).to_lower()]})
		# loot she saw fall and has not picked up
		for l in LootPickup.all_in(main.world):
			if not l.claimed and me.global_position.distance_to(l.global_position) < 18.0:
				out.append({"kind": "collect", "key": "collect:" + str(l.get_instance_id()), "loot": l, "label": "pick up %s" % l.label()})
		# recover: hurt in battle -> withdraw inside the circle's ward and catch her breath
		if mind.vigor < 0.6:
			out.append({"kind": "recover", "key": "recover", "label": "catch my breath inside the circle"})
	# meet another mage she can see (she may also simply not)
	for other_id in main.mages:
		if other_id == agent_id:
			continue
		var oc: WorldCharacter = main.characters.get(other_id)
		if oc and oc.visible and me.global_position.distance_to(oc.global_position) < 30.0:
			var last_met := float(mind.knowledge.get("met_last:" + other_id, 0.0))
			if Time.get_unix_time_from_system() - last_met > MEET_COOLDOWN_S:
				out.append({"kind": "meet", "key": "meet:" + other_id, "other": other_id,
					"label": ("talk with %s" if mind.knowledge.has("met:" + other_id) else "introduce myself to %s") % MagicSystem.display_name(other_id)})
	# journal
	if not Journal.compose(mind).is_empty():
		out.append({"kind": "journal", "key": "journal", "label": "write in my journal"})
	return out.filter(func(o): return _allowed(o.kind) or o.kind == "recover" or o.kind == "collect")


const MEET_COOLDOWN_S := 420.0


## Attunements and the knowledge that tells her about them (the interactable's lore source).
const ATTUNE := {"ritual_circle_attune": ["read:scroll_first_circle"], "heartstone_attune": ["read:chamber_tablet", "lore:heartstone"]}


## The open trial an activity (interactable id or struck object) would advance, or {}.
func _open_trial(deed: String) -> Dictionary:
	for tr in WorldState.sanctuary.get("trials", []):
		if mind.trials_done.has(tr.id):
			continue
		if tr.get("activity", "") == deed:
			return tr
		if tr.has("activity_prefix") and deed.begins_with(tr.activity_prefix):
			if not mind.prefix_counts.get(tr.activity_prefix, {}).has(deed):
				return tr
	return {}


func _advances_trial(deed: String) -> bool:
	return not _open_trial(deed).is_empty()


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
			if o.get("trial", false):
				u += 0.25
				why.append("advances a trial +0.25")
			u -= (1.0 - needs.energy) * 0.45
		"investigate":
			u = 0.85
			why.append("story lead")
		"explore":
			var last: int = int(mind.activity_counts.get(o.key, {}).get("last_unix", 0))
			var age := minf((Time.get_unix_time_from_system() - last) / 600.0, 1.0) if last > 0 else 1.0
			u = 0.2 + needs.curiosity * 0.35 * age
		"rest":
			u = 0.1 + (1.0 - needs.energy) * 0.95
			if o.interactable == "pond_reflect":
				u -= 0.05
		"alchemy":
			var wants: bool = mind.knowledge.has("recipe:luminous_draught") and int(mind.inventory.get("luminous_draught", 0)) == 0
			u = 0.4 + (0.25 if wants else 0.05) + needs.curiosity * 0.15
		"converse":
			u = 0.55 + needs.social * 0.5
			why.append("visitor present")
		"attune":
			u = 0.3 + needs.mastery * 0.3 - (1.0 - needs.energy) * 0.2
			var tr := _open_trial(o.interactable)
			if not tr.is_empty():
				u += 0.35
				why.append("trial: %s +0.35" % tr.name)
			elif o.attuned:
				u -= 0.15
		"hunt":
			var first: bool = not mind.knowledge.has("defeated:" + String(o.monster_kind))
			var risk: float = {"weak": 0.0, "medium": 0.28 if mind.level() < 4 else 0.08, "rare": 0.55 if mind.level() < 8 else 0.2}.get(o.tier, 0.2)
			u = 0.35 + needs.mastery * 0.25 - risk - (1.0 - mind.vigor) * 0.7 - (1.0 - needs.energy) * 0.25 - float(o.distance) * 0.006
			if risk > 0.0:
				why.append("risky -%.2f" % risk)
			if first:
				u += 0.3
				why.append("never beaten one +0.30")
			if o.attacking_me:
				u += 0.65 * mind.vigor
				why.append("it is attacking me")
		"collect":
			u = 0.7
			why.append("it fell right here")
		"recover":
			u = (1.0 - mind.vigor) * 1.5 + (0.3 if threat and is_instance_valid(threat) and mind.vigor < 0.35 else 0.0)
			why.append("vigor %.0f%%" % (mind.vigor * 100.0))
		"meet":
			var rel: Dictionary = mind.knowledge.get("rel:" + String(o.other), {})
			u = 0.3 + needs.social * 0.45 + 0.15 * float(rel.get("camaraderie", 0.0)) - 0.1 * float(rel.get("rivalry", 0.0))
			if not mind.knowledge.has("met:" + String(o.other)):
				u += 0.2
				why.append("we have never spoken")
		"journal":
			# grows with the number of things done since the last entry: she writes after a meaningful stretch
			var unwritten := mind.activity_seq - int(mind.knowledge.get("journal_cursor", 0))
			u = 0.2 + 0.055 * minf(unwritten, 14)
			if unwritten >= 8:
				why.append("%d things unwritten" % unwritten)
	var temper := float(profile.get("temperament", {}).get(o.kind, 1.0))
	if temper != 1.0 and u > 0.0:
		u *= temper
		why.append("temperament x%.2f" % temper)
	var kind_reps := _recent_kinds.slice(maxi(0, _recent_kinds.size() - 3)).count(o.kind)
	if o.kind in ["hunt", "collect", "recover"]:
		kind_reps = 0      # a fight is not "the same thing again" while creatures keep coming
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
	var pos := me.global_position
	var here := SanctuaryBrain.sub_area(main.world, pos)
	var subs := []
	for id in data.sub_areas:
		var s: Dictionary = data.sub_areas[id]
		subs.append({"id": id, "name": s.name, "purpose": s.purpose,
			"distance": snappedf(Vector2(pos.x - s.center[0], pos.z - s.center[2]).length(), 0.1) if main.streaming.current_id == "sanctuary" else -1.0})
	return {"region": REGION, "in_region": _in_region(), "story": main.story.describe(), "sub_area": here,
		"sub_area_info": data.sub_areas.get(here, {}).get("purpose", ""), "sub_areas": subs,
		"options": ranked().slice(0, 10).map(func(o): return {"key": o.key, "kind": o.kind, "label": o.label, "utility": o.utility, "why": o.why}),
		"needs": status().needs, "mission": WorldState.mission_state(agent_id), "spells": main.magic.known_spells(agent_id),
		"visitors": main.npcs.nearby(pos, 60.0), "current": current}


# ------------------------------------------------------------------ main loop
func _loop() -> void:
	busy = true
	while enabled and is_inside_tree():
		if hold:
			current = {}
			await get_tree().create_timer(0.3).timeout
			continue
		if main.streaming.state != "idle" or not main.travel.journey.is_empty():
			await get_tree().create_timer(0.5).timeout
			continue
		if not is_lead() and (main.streaming.current_id != "sanctuary" or not me.visible):
			current = {"kind": "away", "label": "waiting in the Sanctuary"}
			await get_tree().create_timer(1.0).timeout     # she lives in the Sanctuary: paused while it is not loaded
			continue
		if is_lead() and not _in_region():
			current = {"kind": "travel", "label": "return home"}
			await _travel("ritual_sanctuary")
			continue
		if main.curiosity and is_lead():
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
		WorldState.note_activity(choice.key, agent_id)
		WorldState.note_activity("kind:" + choice.kind, agent_id)
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
		if main.curiosity and is_lead():
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
		"attune": return await _attune(o)
		"hunt": return await _hunt(o)
		"collect": return await _collect(o.loot)
		"recover": return await _recover()
		"meet": return await main.mage_talk.meet(self, String(o.other))
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
		res = await main.magic.cast(me, o.spell, o.target)
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
		_maybe_say(["Ha, still not enough. Breathe out first, then the words.", "Closer. Not there yet."] if mind.knowledge.has("fact:breath_before_word") else ["Ha, it barely moved. My gust needs more practice.", "Not enough. Again."], 0.8)
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
	var map := me.get_world_3d().navigation_map
	var dest := NavigationServer3D.map_get_closest_point(map, c + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)))
	if not await _walk(dest):
		return {"ok": false, "detail": "could not reach the %s" % sub.name}
	current.stage = "looking around"
	var pois := []
	for id in main.world.points_of_interest:
		var p: Vector3 = main.world.points_of_interest[id].position
		if p.distance_to(me.global_position) < float(sub.radius) + 4.0 and not String(id).begins_with("gate:"):
			pois.append(p)
	pois.shuffle()
	var looked := 0
	for p in pois.slice(0, rng.randi_range(2, 4)):
		me.look_at_point(p + Vector3(0, 1.0, 0))
		me.look_head_at(p + Vector3(0, 1.0, 0))
		await get_tree().create_timer(rng.randf_range(2.0, 4.0)).timeout
		looked += 1
	me.look_head_at(null)
	var lines: Array = WorldState.sanctuary.thoughts.get(o.sub_area, [])
	if not lines.is_empty():
		_private_thought(lines[rng.randi() % lines.size()])
	needs.curiosity = clampf(needs.curiosity - 0.12, 0.0, 1.0)
	needs.energy = clampf(needs.energy - 0.03, 0.0, 1.0)
	for id in ["gate_inscription", "chamber_tablet"]:
		var it = main.world.interactables.get(id)
		if it and it.global_position.distance_to(me.global_position) < 9.0 and BookLibrary.pages_read(it.book_id).is_empty():
			await _use(id)
	# standing at the Watchpoint for the first time: actually survey the realm from it (the plaque is right there)
	var survey = main.world.interactables.get("watchpoint_survey")
	if survey and o.sub_area == "watchpoint" and not mind.knowledge.has("survey:realm") and survey.global_position.distance_to(me.global_position) < 9.0:
		current.stage = "surveying the realm"
		await _use("watchpoint_survey")
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


func _attune(o: Dictionary) -> Dictionary:
	current.stage = "attuning"
	var r := await _use(o.interactable)
	if r.get("ok", false):
		needs.mastery = clampf(needs.mastery - 0.15, 0.0, 1.0)
		needs.energy = clampf(needs.energy - 0.03, 0.0, 1.0)
	return r


func _converse(o: Dictionary) -> Dictionary:
	var npc = main.npcs.present.get(o.npc)
	if npc == null or not is_instance_valid(npc):
		return {"ok": false, "detail": "they left"}
	current.stage = "walking over to %s" % main.dialogue.travellers[o.npc].name
	var to: Vector3 = npc.global_position + (me.global_position - npc.global_position).normalized() * 1.6
	await _walk(to)
	current.stage = "talking"
	var r: Dictionary = await main.dialogue.converse(o.npc, me)
	_talked_this_visit[o.npc + str(main.dialogue.state_of(o.npc).visits)] = true
	needs.social = clampf(needs.social - 0.4, 0.0, 1.0)
	return r


func _journal() -> Dictionary:
	var it: Interactable = main.world.interactables.get("mika_journal") if is_lead() else null
	if it == null and is_lead():
		return {"ok": false, "detail": "the journal is in the sanctuary"}
	if it:
		await _walk(it.approach_point())
	var entry := Journal.compose(mind)
	if entry.is_empty():
		return {"ok": false, "detail": "nothing new to write"}
	current.stage = "writing"
	if it:
		me.look_at_point(it.global_position)
		me.look_head_at(it.global_position + Vector3(0, 0.75, 0))
	else:
		me.look_head_at(me.global_position + -me.global_transform.basis.z * 0.5 + Vector3(0, 1.0, 0))   # her own notebook
	await get_tree().create_timer(clampf(String(entry.text).split(" ").size() / 2.5, 4.0, 14.0)).timeout
	var j: Array = mind.knowledge.get("journal", []).duplicate()
	j.append({"heading": entry.heading, "text": entry.text, "unix": int(Time.get_unix_time_from_system())})
	mind.knowledge["journal"] = j
	mind.knowledge["journal_cursor"] = entry.cursor
	var ch := WorldState.record_activity({"id": "journal_write", "verb": "write", "label": entry.heading}, {}, agent_id)
	me.look_head_at(null)
	return {"ok": true, "detail": "wrote %s: %s" % [entry.heading, String(entry.text).left(80)], "entry": entry, "changes": ch}


# ------------------------------------------------------------------ combat
## The spell she trusts most against a creature: her signature spell first, then whichever castable spell
## hits hardest (damage x her power with it), ignoring spells that cannot reach creatures.
func combat_spell() -> String:
	var best := ""
	var best_v := -1.0
	for sp in main.magic.known_spells(agent_id):
		if not sp.castable or sp.id in ["elemental_charge", "rune_activation"]:
			continue
		var d := MagicSystem.spell(sp.id)
		var kinds: Array = d.get("target_kinds", ["*"])
		if not kinds.has("*"):
			continue
		var v := float(d.get("damage", 0.5)) * float(sp.power) + (0.25 if sp.id == profile.get("signature_spell", "") else 0.0)
		if v > best_v:
			best_v = v
			best = sp.id
	return best


## Called by the spawner when a creature strikes her: she stops what she is walking to and decides again.
func on_threat(m: Monster) -> void:
	threat = m
	if current.get("kind", "") not in ["hunt", "recover"]:
		_interrupt = "threat"


func _monster(id: String) -> Monster:
	if main.spawner == null:
		return null
	for m in main.spawner.alive:
		if is_instance_valid(m) and m.id == id:
			return m
	return null


func _hunt(o: Dictionary) -> Dictionary:
	var m := _monster(o.monster)
	if m == null or not m.alive():
		return {"ok": false, "detail": "it was already gone"}
	var spell := combat_spell()
	if spell == "":
		return {"ok": false, "detail": "no spell that can reach a creature"}
	if not mind.knowledge.has("bestiary:" + m.kind):
		WorldState.record_activity({"id": "sight:" + m.kind, "verb": "observe", "label": "Saw a %s" % m.def.name}, {"knowledge": {"bestiary:" + m.kind: 1}}, agent_id)
		_maybe_say(_lines("first_sight", ["What is that?", "Something is moving out there."]), 0.9)
	# a strong creature and an unlocked form: transform first (the short sequence), if not already
	if m.tier() in ["medium", "rare"] and main.transformer and main.transformer.can_transform(agent_id) and mind.vigor > 0.4:
		current.stage = "transforming"
		await main.transformer.play(agent_id, "short")
		if not is_instance_valid(m) or not m.alive():
			return {"ok": true, "detail": "it was gone when she finished transforming"}
	var casts := 0
	var hits := 0
	var tries := 0
	while is_instance_valid(m) and m.alive() and casts < 8 and not _cancel:
		current.stage = "fighting (cast %d)" % (casts + 1)
		if mind.vigor < 0.22:
			_maybe_say(_lines("retreat", ["Too much. I need to step back.", "Back to the circle."]), 1.0)
			await _recover()
			return {"ok": false, "detail": "withdrew to the circle after %d cast(s), %d hit(s)" % [casts, hits]}
		if not await _stand_for_cast(spell, m.id):
			tries += 1
			if tries > 3:
				return {"ok": false, "detail": "could not find a clear line to %s" % m.label}
			await get_tree().create_timer(0.6).timeout
			continue
		var res: Dictionary = await main.magic.cast(me, spell, m.id)
		casts += 1
		needs.energy = clampf(needs.energy - 0.04, 0.0, 1.0)
		if res.get("outcome", "") == "hit":
			hits += 1
		elif res.get("outcome", "") == "refused":
			await get_tree().create_timer(0.5).timeout
		await get_tree().create_timer(rng.randf_range(0.3, 0.8)).timeout
	threat = null
	if not is_instance_valid(m) or not m.alive():
		needs.mastery = clampf(needs.mastery - 0.2, 0.0, 1.0)
		_maybe_say(_lines("victory", ["Got it.", "That's done. Breathe."]), 0.8)
		await get_tree().create_timer(0.8).timeout
		var picked := 0
		for l in LootPickup.all_in(main.world):
			if not l.claimed and me.global_position.distance_to(l.global_position) < 10.0:
				if (await _collect(l)).get("ok", false):
					picked += 1
		return {"ok": true, "detail": "won after %d cast(s), %d hit(s); picked up %d thing(s)" % [casts, hits, picked], "hits": hits}
	return {"ok": false, "detail": "%d cast(s), %d hit(s); it is still there" % [casts, hits], "hits": hits}


func _collect(l) -> Dictionary:
	if l == null or not is_instance_valid(l) or l.claimed:
		return {"ok": false, "detail": "nothing left to pick up"}
	current.stage = "picking up %s" % l.label()
	me.navigate_to(l.global_position, false)
	var t0 := Time.get_ticks_msec()
	while me.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 12000 and is_instance_valid(l) and not _cancel:
		await get_tree().process_frame
	if not is_instance_valid(l):
		return {"ok": false, "detail": "someone else took it"}
	return l.collect(me)


## Withdraw inside the ritual circle (creatures will not cross its ward) and recover vigor there.
func _recover() -> Dictionary:
	current.stage = "withdrawing to the circle"
	var safe := Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-3.0, 3.0))
	var map := me.get_world_3d().navigation_map
	await _walk(NavigationServer3D.map_get_closest_point(map, safe), true)
	current.stage = "catching her breath"
	me.set_expression("relaxed", 0.6)
	var t0 := Time.get_ticks_msec()
	while mind.vigor < 0.9 and Time.get_ticks_msec() - t0 < 25000 and not _cancel:
		mind.vigor = clampf(mind.vigor + 0.1 * get_process_delta_time(), 0.0, 1.0)   # ~9 s from exhausted to steady
		await get_tree().process_frame
	me.set_expression("relaxed", 0.0)
	needs.energy = clampf(needs.energy + 0.15, 0.0, 1.0)
	threat = null
	return {"ok": true, "detail": "recovered to %d%% vigor" % int(mind.vigor * 100.0)}


## Slow natural recovery of vigor; faster inside the ward.
func _process(delta: float) -> void:
	if mind == null or not enabled:
		return
	var inside: bool = main.streaming.current_id == "sanctuary" and Vector2(me.global_position.x, me.global_position.z).length() < 12.0
	mind.vigor = clampf(mind.vigor + delta * (0.012 if inside else 0.004), 0.0, 1.0)
	if threat and (not is_instance_valid(threat) or not threat.alive()):
		threat = null


## Per-mage line overrides (data/mages.json "lines"); falls back to the given defaults.
func _lines(key: String, defaults: Array) -> Array:
	return profile.get("lines", {}).get(key, defaults)


# ------------------------------------------------------------------ helpers
func _use(id: String) -> Dictionary:
	var it: Interactable = main.world.interactables.get(id)
	if it == null:
		return {"ok": false, "detail": "no '%s' in %s" % [id, main.streaming.current_id]}
	if not await _walk(it.approach_point()):
		return {"ok": false, "detail": "could not reach %s" % it.label}
	if not it.in_reach(me.global_position):
		# the walk tolerance is looser than the interaction reach: close the last metre
		await _walk(it.approach_point())
	return await it.perform(me)


func _walk(target: Vector3, ignore_threat := false) -> bool:
	for attempt in 2:
		me.navigate_to(target, me.global_position.distance_to(target) > 14.0)
		if me.current_action != "navigate_to":
			if me.global_position.distance_to(target) < 2.0:
				return true
			continue
		while me.current_action == "navigate_to" and not _cancel:
			if _interrupt in ["threat", "social", "transform"] and not ignore_threat:
				me.stop_action()
				return false
			await get_tree().process_frame
		if me.global_position.distance_to(target) < 2.5:
			return true
		var away := me.global_position - target
		away.y = 0
		me.navigate_to(me.global_position + away.normalized() * 1.2)
		await get_tree().create_timer(1.0).timeout
	return me.global_position.distance_to(target) < 2.5


## Find a nearby navmesh spot with line of sight, range and space for this spell, then walk there.
func _stand_for_cast(spell_id: String, target_id: String) -> bool:
	var target: ReactiveElement = main.magic.reactives().get(target_id)
	if target == null:
		return false
	if main.magic.validate(spell_id, me, target).ok and main.world.has_space_for_magic(me.global_position):
		return true
	var tp := target.aim_point()
	var map := me.get_world_3d().navigation_map
	var rangev := float(MagicSystem.spell(spell_id).get("range", 8.0))
	var from_dir := Vector3(me.global_position.x - tp.x, 0, me.global_position.z - tp.z)
	var base := atan2(from_dir.x, from_dir.z)
	for ring in [minf(5.0, rangev - 1.0), minf(3.5, rangev - 1.0), minf(7.0, rangev - 1.0)]:
		for k in 12:
			var ang: float = base + (k / 2) * 0.5 * (1.0 if k % 2 == 0 else -1.0)
			var want: Vector3 = tp + Vector3(sin(ang), 0, cos(ang)) * float(ring)
			var p := NavigationServer3D.map_get_closest_point(map, want)
			if p.distance_to(Vector3(want.x, p.y, want.z)) > 0.8:
				continue
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.3, 0), tp)
			q.exclude = [me.get_rid()]
			var hit := me.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and not target.owns_collider(hit.collider) and (hit.position as Vector3).distance_to(tp) > target.aim_radius + 0.35:
				continue
			if not main.world.has_space_for_magic(p):
				continue
			if await _walk(p):
				# check where she actually stopped (navigation can stop up to ~0.7 m short)
				if main.magic.validate(spell_id, me, target).ok and main.world.has_space_for_magic(me.global_position):
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
	thought.emit(VoiceService.clean(text), SanctuaryBrain.sub_area(main.world, me.global_position))


## Spoken only when the moment justifies it, at most once a minute.
func _maybe_say(lines: Array, chance: float) -> void:
	if Time.get_ticks_msec() / 1000.0 < _speak_cd or rng.randf() > chance:
		return
	_speak_cd = Time.get_ticks_msec() / 1000.0 + 60.0
	main.voice.say(_voice(), lines[rng.randi() % lines.size()])


## Compatibility with the bridge's perform_action{action}: runs the matching activity once.
func perform_action(action_id: String) -> Dictionary:
	for o in options():
		if o.key == action_id or o.get("interactable", "") == action_id or o.label == action_id:
			return await run_activity(o)
	return {"ok": false, "error": "no available activity '%s' (see region_context.options)" % action_id}
