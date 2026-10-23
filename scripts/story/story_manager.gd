class_name StoryManager
extends Node
## "Echoes of the Heartstone": a narrative state machine driven only by verified world state.
## Clues are satisfied by knowledge Mika actually gained (reading, magic reactions, conversations), in any
## order; stages advance when their clue requirements hold; the finale changes the world for good
## (persisted): the Heartstone stays awake, the circle amplifies spells, the tablet shows a second page.

signal stage_changed(stage: Dictionary)
signal clue_found(clue_id: String, clue: Dictionary)

## Chapters (Selwyn 23 Oct: "More stories/plots"). The Heartstone (data/story.json) is chapter 1; once it is done the
## next chapter begins by itself (CHAPTERS, in order). `data`, `found` and `stage` are always the running chapter's;
## a finished chapter's clues and stage are kept in story_state.done. A chapter file may give data-driven leads
## (a spot to look at in an area, known only after the listed knowledge) and a finale at a spot (PlaceSpots).
const CHAPTERS := ["res://data/story.json", "res://data/story_lamplighter.json"]
const NEXT_CHAPTER_DELAY_S := 600.0    # a breath between the end of one chapter and the next beginning

var main: Node
var data := {}
var found := {}          # clue id -> unix time
var stage := "quiet_stone"
var chapter := 0
var done := {}           # finished chapter id -> {found, stage, unix}


func setup(m: Node) -> void:
	main = m
	var saved: Dictionary = WorldState.story_state
	chapter = clampi(int(saved.get("chapter", 0)), 0, CHAPTERS.size() - 1)
	done = saved.get("done", {})
	_load(chapter)
	found = saved.get("found", {})
	stage = saved.get("stage", String(data.stages[0].id))
	WorldState.state_changed.connect(func(_e): evaluate())
	evaluate(true)


func _load(i: int) -> void:
	var f := FileAccess.open(CHAPTERS[i], FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())


func chapter_id() -> String:
	return String(data.get("id", "heartstone"))


## The last stage reached and the chapter ended: the next one, after a breath (never twice, saved).
func _maybe_next_chapter() -> void:
	if not complete() or chapter >= CHAPTERS.size() - 1:
		return
	var end_key := "chapter_done:" + chapter_id()
	if not WorldState.knowledge.has(end_key):
		WorldState.knowledge[end_key] = Time.get_unix_time_from_system()
	if Time.get_unix_time_from_system() - float(WorldState.knowledge[end_key]) < NEXT_CHAPTER_DELAY_S:
		return
	done[chapter_id()] = {"found": found, "stage": stage, "unix": int(Time.get_unix_time_from_system())}
	chapter += 1
	_load(chapter)
	found = {}
	stage = String(data.stages[0].id)
	var know: Dictionary = data.get("start_knowledge", {}).duplicate()
	know["chapter_started:" + chapter_id()] = 1
	WorldState.record_activity({"id": "story:start:" + chapter_id(), "verb": "unlock", "label": String(data.get("start_text", data.title))}, {"knowledge": know})
	print("[story] chapter %d begins: %s" % [chapter + 1, data.title])
	_notify(String(data.get("start_notice", "New chapter: " + String(data.title))))
	stage_changed.emit(stage_info())
	if main and main.get("streaming") and main.streaming.current and main.streaming.current.has_method("activate_steps"):
		pass   # the chapter's marks appear with the next build of each area (PlaceSpots.active)


func evaluate(silent := false) -> void:
	for id in data.clues:
		if found.has(id):
			continue
		var c: Dictionary = data.clues[id]
		if (c.any_knowledge as Array).any(func(k): return WorldState.knowledge.has(k)):
			found[id] = int(Time.get_unix_time_from_system())
			if not silent:
				clue_found.emit(id, c)
				_notify("Clue: " + String(c.title))
	var best := stage
	for s in data.stages:
		var ok := true
		if s.has("requires_all"):
			ok = (s.requires_all as Array).all(func(x): return found.has(x))
		elif s.has("requires_any") and not (s.requires_any as Array).is_empty():
			ok = (s.requires_any as Array).any(func(x): return found.has(x))
		if ok:
			best = s.id
	if best != stage:
		stage = best
		if complete() and data.has("unlock") and not (data.unlock.knowledge as Dictionary).keys().all(func(k): return WorldState.knowledge.has(k)):
			WorldState.record_activity({"id": "story:" + stage, "verb": "unlock", "label": data.unlock.summary}, {"knowledge": data.unlock.knowledge})
		if not silent:
			var sd := stage_info()
			stage_changed.emit(sd)
			_notify("%s: %s" % [data.title, sd.title])
			if AudioDirector.instance:
				AudioDirector.instance.play2d("rank_up" if complete() else "discovery", "UI", -4.0, "story_stage")
	WorldState.story_state = {"found": found, "stage": stage, "chapter": chapter, "done": done}
	_maybe_next_chapter()


func stage_info() -> Dictionary:
	for s in data.stages:
		if s.id == stage:
			return s
	return {}


func complete() -> bool:
	return stage == String((data.stages as Array).back().id)


## What Mika could sensibly look into next, using ONLY what she has learned (each lead needs a source she
## actually read, saw or was told). Nothing here reveals a step she has no reason to know about.
func next_leads() -> Array:
	var K := WorldState.knowledge
	var leads := []
	if data.has("leads"):
		# a data-driven chapter: a lead is known only after one of its `after` pieces of knowledge, until `unless`
		for l in data.leads:
			if not (l.after as Array).any(func(k): return K.has(k)) or K.has(String(l.get("unless", ""))):
				continue
			leads.append({"lead": String(l.lead), "activity": "spot", "area": String(l.area), "spot": String(l.spot), "night": bool(l.get("night", false)), "source": "the trail so far"})
		return leads
	var heard_heartbeat_hint := K.has("clue:margin_note_aurel") or K.has("lore:heartstone") or K.has("clue:heartbeat_should_be_three")
	if heard_heartbeat_hint and not found.has("heartbeat"):
		leads.append({"lead": "see how the Heartstone answers an orb of light", "activity": "experiment", "target": "heartstone", "spell": "arcane_orb", "source": "margin note / daybook"})
	if (K.has("lore:heartstone") or K.has("clue:margin_note_aurel")) and not K.has("clue:heartbeat_should_be_three"):
		leads.append({"lead": "look for the keeper's own records in the chamber", "activity": "research", "book": "keepers_daybook", "source": "tablet / margin note"})
	if K.has("clue:sign_of_return_location") and not found.has("gate_mark"):
		if K.has("incantation:rune_activation"):
			leads.append({"lead": "try to wake the faint carving by the forest gate", "activity": "investigate", "target": "marked_stone", "spell": "rune_activation", "source": "daybook"})
		else:
			leads.append({"lead": "find out how a sleeping sign can be woken", "activity": "research", "book": "signs_and_wakings", "source": "daybook says it can only be woken"})
	var water_hint := K.has("clue:water_remembers") or K.has("fact:signs_need_water")
	if found.has("gate_mark") and water_hint and not found.has("pond_pattern"):
		leads.append({"lead": "carry the woken sign's shape to still water", "activity": "investigate", "target": "pond", "spell": "arcane_orb", "source": "daybook / Elowen"})
	if found.has("pond_pattern") and not found.has("awakened") and K.has("clue:sign_of_return_location"):
		if K.has("incantation:rune_activation"):
			leads.append({"lead": "wake the remembered pattern in the Heartstone", "activity": "investigate", "target": "heartstone", "spell": "rune_activation", "source": "daybook"})
	return leads


## Objective text phrased from what Mika knows (never the hidden solution).
func objective() -> String:
	var leads := next_leads()
	if complete():
		return String(stage_info().get("objective", ""))
	if not leads.is_empty():
		return "Next: " + String(leads[0].lead)
	if found.is_empty():
		return "Study the sanctuary and its relic."
	return "Think about what the clues so far might mean."


func describe() -> Dictionary:
	# only clues she has actually found; unfound clue titles would give away the mystery
	var clues := {}
	for id in found:
		clues[id] = {"title": data.clues[id].title, "what_she_knows": data.clues[id].hint}
	return {"chapter": data.title, "goal": data.goal, "stage": {"title": stage_info().get("title", "")}, "objective": objective(),
		"clues_found": clues, "leads": next_leads().map(func(l): return l.lead), "complete": complete()}


func _notify(text: String) -> void:
	if main and main.has_method("show_notice"):
		main.show_notice(text)
