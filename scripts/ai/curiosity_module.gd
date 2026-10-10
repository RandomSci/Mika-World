class_name CuriosityModule
extends Node
## Optional contextual curiosity on top of Mika's deterministic planner. Event-driven, not per frame:
## it is consulted at most once per decision, only when something happened (an activity finished, a visitor
## arrived, a clue was found) and the cooldown has passed. It is never asked during travel, conversations
## or spells (the planner only consults between activities).
## It receives concise, real observations and the CURRENT VALID options (ids + labels); it may propose one.
## The proposal is validated (must be one of those ids) and only adds a bonus to that option's utility;
## the planner still decides, Godot executes, the world confirms. It can never change progress, collision,
## inventory or story flags. With no LLM configured, a deterministic mock proposes the most novel option.

var main: Node
var brain: SanctuaryBrain
var cooldown_s := 90.0
var bonus := 0.35
var log: Array = []
var _pending := ""
var _last_consult := -1e9
var _last_events: Array = []


func setup(m: Node) -> void:
	main = m
	if RenderProfile.options.has("curiosity-cooldown"):
		cooldown_s = float(RenderProfile.options["curiosity-cooldown"])
	main.story.clue_found.connect(func(id, _c): _note("found a clue: " + id))
	MagicEvents.magic_event.connect(func(_p, el, _pw, eff, obj): if eff != "none": _last_events.append("%s magic on %s: %s" % [el, obj, eff]))


func _note(why: String) -> void:
	_pending = why
	_last_events.append(why)
	if _last_events.size() > 8:
		_last_events.pop_front()


func on_activity_finished(choice: Dictionary, result: Dictionary) -> void:
	_note("finished %s (%s)" % [choice.label, "ok" if result.get("ok", false) else "failed: %s" % str(result.get("detail", "")).left(60)])


func on_visitor(npc_id: String) -> void:
	_note("a visitor arrived: " + npc_id)


func consult(b: SanctuaryBrain) -> void:
	brain = b
	var now := Time.get_ticks_msec() / 1000.0
	if _pending == "" or now - _last_consult < cooldown_s:
		return
	if main.voice.busy() or main.book_reader.reading():
		return
	_last_consult = now
	var why := _pending
	_pending = ""
	var opts: Array = b.ranked().slice(0, 6)
	if opts.size() < 2:
		return
	var valid := opts.map(func(o): return o.key)
	var obs := {
		"where": {"area": main.streaming.current_id, "sub_area": SanctuaryBrain.sub_area(main.world, b.mika.global_position), "night": WorldState.night},
		"goal": main.story.data.goal, "story_stage": main.story.objective(), "leads": main.story.next_leads().map(func(l): return l.lead),
		"needs": b.status().needs, "recent": b.history.slice(maxi(0, b.history.size() - 4)).map(func(h): return "%s (%s)" % [h.label, "ok" if h.ok else "failed"]),
		"recent_events": _last_events.slice(maxi(0, _last_events.size() - 5)), "visitors": main.npcs.present.keys(),
		"options": opts.map(func(o): return {"id": o.key, "what": o.label}),
	}
	# deterministic mock: the most novel valid option (a kind she has not done in the last few activities)
	var recent_kinds := b.history.slice(maxi(0, b.history.size() - 3)).map(func(h): return h.kind)
	var pick: Dictionary = opts[0]
	for o in opts:
		if not recent_kinds.has(o.kind):
			pick = o
			break
	var mock := {"choice": pick.key, "reason": "something I have not done for a while"}
	var system := "You choose what a curious young mage does next in a fantasy sanctuary. Pick exactly one option id from the list. Reply as JSON {\"choice\": id, \"reason\": short}."
	var r: Dictionary = await main.llm.ask_json(system, JSON.stringify(obs), mock)
	var choice := String(r.json.get("choice", ""))
	var accepted := valid.has(choice)
	if accepted:
		b.curiosity_bonus[choice] = bonus
	log.append({"t": snappedf(now, 0.1), "trigger": why, "provider": r.provider, "proposal": choice, "accepted": accepted,
		"reason": String(r.json.get("reason", "")).left(120), "options": valid})
	if log.size() > 60:
		log.pop_front()


func describe() -> Dictionary:
	return {"cooldown_s": cooldown_s, "bonus": bonus, "llm": main.llm.describe(), "recent": log.slice(maxi(0, log.size() - 6))}
