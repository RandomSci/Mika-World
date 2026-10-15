class_name MageTalk
extends Node
## Conversations between autonomous mages. Never forced: the one who starts it walks over; the other only
## joins if she is between activities or doing something interruptible (exploring, journaling, idling),
## otherwise she declines. Every line comes from the SPEAKER's own mind (her level, her latest real
## deeds, what she has or has not fought) - never from the listener's knowledge. The listener records only
## that she met / heard about a topic ("heard:<speaker>:<topic>"), not the fact itself: minds stay separate.
## Relations (rel:<other> in each mind) drift with what actually happens: meetings and shared fusions build
## camaraderie, a creature "stolen" mid-fight builds rivalry. An optional language model may rephrase the
## authored lines using only the speaker's own facts; anything invalid falls back to the authored line.

signal talked(entry: Dictionary)

const INTERRUPTIBLE := ["", "explore", "journal", "rest", "magic"]

var main: Node
var log: Array = []
var _active := false


var phrase_ms: Array = []       # how long phrasing a conversation took (LLM), for the latency report

func setup(m: Node) -> void:
	main = m
	if main.spawner:
		main.spawner.monster_defeated.connect(_on_defeat)


func _line(who: String, key: String, other := "") -> String:
	var lines: Array = Progression.mages.get(who, {}).get("lines", {}).get(key, [])
	if lines.is_empty():
		return ""
	return String(lines[randi() % lines.size()]).replace("{other}", MagicSystem.display_name(other))


static func rel(who: String, other: String) -> Dictionary:
	var k: Dictionary = WorldState.mind(who).knowledge
	if not k.get("rel:" + other) is Dictionary:
		k["rel:" + other] = {"meetings": 0, "camaraderie": 0.0, "rivalry": 0.0}
	return k["rel:" + other]


## A deed from HER memory worth mentioning, as {topic, text}; {} if nothing notable.
static func latest_deed(who: String) -> Dictionary:
	var log: Array = WorldState.mind(who).activity_log
	for i in range(log.size() - 1, maxi(-1, log.size() - 40), -1):
		var e: Dictionary = log[i]
		var id := String(e.get("activity", {}).get("id", ""))
		if id.begins_with("defeat:"):
			var kind := id.trim_prefix("defeat:")
			return {"topic": "monster:" + kind, "kind": kind, "text": "I fought off a %s out past the circle." % String(Spawner.load_data().monsters.get(kind, {}).get("name", kind)).to_lower()}
		if id.begins_with("fusion:"):
			return {"topic": "fusion", "text": "Our spells met inside that creature. I can still feel it."}
		for k in e.get("changes", {}):
			if String(k).begins_with("trial."):
				return {"topic": "trial", "text": "I finished a trial today: %s." % String(k).trim_prefix("trial.").replace("_", " ")}
			if String(k).begins_with("knowledge.reaction:") and e.changes[k][0] == 0:
				var parts := String(k).trim_prefix("knowledge.reaction:").split(":")
				return {"topic": "reaction:" + parts[1], "text": Journal._reaction_line(parts[0], parts[1], parts[2])}
	return {}


func busy() -> bool:
	return _active


## Run a meeting started by planner `a` toward mage `other_id`. Returns the planner result.
func meet(a: SanctuaryBrain, other_id: String) -> Dictionary:
	var b: SanctuaryBrain = main.mage_brains.get(other_id)
	var bc: WorldCharacter = main.characters.get(other_id)
	var me := a.me
	var now := Time.get_unix_time_from_system()
	a.mind.knowledge["met_last:" + other_id] = now
	if _active or b == null or bc == null or not bc.visible:
		return {"ok": false, "detail": "%s is not around" % MagicSystem.display_name(other_id)}
	if String(b.current.get("kind", "")) not in INTERRUPTIBLE or bc.casting or (b.enabled and b.current.get("kind", "") == "rest" and bc.seated):
		a.mind.knowledge["met_last:" + other_id] = now - SanctuaryBrain.MEET_COOLDOWN_S + 120.0
		return {"ok": false, "detail": "%s was busy (%s)" % [MagicSystem.display_name(other_id), b.current.get("label", "busy")]}
	_active = true
	b.hold = true
	b.interrupt("social")
	a.current.stage = "walking over to %s" % MagicSystem.display_name(other_id)
	await Companionship.approach_for_talk(a, bc, 1.6)
	var t0 := Time.get_ticks_msec()
	while not b.current.is_empty() and b.current.get("kind", "") != "away" and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	if me.global_position.distance_to(bc.global_position) > 4.0:
		b.hold = false
		_active = false
		return {"ok": false, "detail": "%s moved off" % MagicSystem.display_name(other_id)}
	b.current = {"kind": "meet", "label": "talking with %s" % MagicSystem.display_name(a.agent_id), "stage": "talking"}
	a.current.stage = "talking"
	me.look_at_point(bc.global_position)
	bc.look_at_point(me.global_position)
	me.look_head_at(bc.global_position + Vector3(0, 1.5, 0))
	bc.look_head_at(me.global_position + Vector3(0, 1.5, 0))
	if main.director and main.director.enabled:
		main.director.focus_conversation(bc if main.director.mika == me else me, 14.0)
	var first := not WorldState.mind(a.agent_id).knowledge.has("met:" + other_id)
	var lines: Array = _compose(a.agent_id, other_id) if first or main.get("companionship") == null else main.companionship.compose(a.agent_id, other_id)
	if lines.size() < 2:
		lines = _compose(a.agent_id, other_id)
	var t_phrase := Time.get_ticks_msec()
	lines = await _phrase(a.agent_id, other_id, lines)
	phrase_ms.append(Time.get_ticks_msec() - t_phrase)
	if phrase_ms.size() > 50:
		phrase_ms.pop_front()
	# the whole exchange is known now: every next line synthesises while the one before it is spoken
	if main.voice:
		main.voice.prefetch_lines(lines.map(func(l): return {"speaker": String(Progression.mages.get(l.who, {}).get("voice", l.who)), "text": String(l.text)}))
	var spoken := []
	for l in lines:
		var spk: WorldCharacter = main.characters.get(String(l.who))
		if String(l.get("gesture", "")) != "" and spk and not spk.casting:
			spk.play_gesture(String(l.gesture), 0.3, 0.5)
		var r: Dictionary = await main.voice.say(String(Progression.mages.get(l.who, {}).get("voice", l.who)), String(l.text))
		Companionship.remember_told(l.get("teach", {}), String(l.who))
		spoken.append({"who": l.who, "text": l.text, "audio": r.get("audio", false), "told": l.get("teach", {}).get("topic", "")})
		# a natural beat between turns: shorter after a short reply, longer after news
		await get_tree().create_timer(0.25 + clampf(String(l.text).length() / 120.0, 0.0, 0.6)).timeout
	me.look_head_at(null)
	bc.look_head_at(null)
	# what each of them now remembers (social memory only; no knowledge crosses over)
	for pair in [[a.agent_id, other_id], [other_id, a.agent_id]]:
		var r2 := rel(pair[0], pair[1])
		r2.meetings = int(r2.meetings) + 1
		r2.camaraderie = minf(1.0, float(r2.camaraderie) + 0.08)
		var know := {"met:" + pair[1]: 1}
		var deed := latest_deed(pair[1])
		if not deed.is_empty():
			know["heard:%s:%s" % [pair[1], deed.topic]] = 1
		WorldState.record_activity({"id": "meet:" + pair[1], "verb": "talk", "label": "Talked with %s" % MagicSystem.display_name(pair[1])}, {"knowledge": know}, pair[0])
		WorldState.mind(pair[0]).knowledge["met_last:" + pair[1]] = now
	b.current = {}
	b.hold = false
	_active = false
	var entry := {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "between": [a.agent_id, other_id], "lines": spoken}
	log.append(entry)
	if log.size() > 200:
		log.pop_front()
	talked.emit(entry)
	return {"ok": true, "detail": "talked with %s (%d lines)" % [MagicSystem.display_name(other_id), spoken.size()], "lines": spoken}


## Authored exchange from each speaker's own state.
func _compose(a: String, b: String) -> Array:
	var out := []
	var first := not WorldState.mind(a).knowledge.has("met:" + b)
	if first:
		out.append({"who": a, "text": _line(a, "intro", b)})
		out.append({"who": b, "text": _line(b, "intro", a)})
	else:
		out.append({"who": a, "text": _line(a, "greet_again", b)})
	var deed := latest_deed(a)
	if deed.is_empty():
		out.append({"who": a, "text": _line(a, "share_none", b)})
	else:
		out.append({"who": a, "text": deed.text})
		if deed.has("kind"):
			var b_fought := int(WorldState.mind(b).knowledge.get("defeated:" + String(deed.kind), 0)) > 0
			out.append({"who": b, "text": _line(b, "same_too" if b_fought else "not_yet", a)})
	var la := WorldState.mind(a).level()
	var lb := WorldState.mind(b).level()
	if absi(la - lb) >= 2:
		var ahead := a if la > lb else b
		var behind := b if ahead == a else a
		out.append({"who": behind, "text": _line(behind, "rival_up", ahead)})
		out.append({"who": ahead, "text": _line(ahead, "rival_down", behind)})
	out.append({"who": b, "text": _line(b, "farewell", a)})
	return out.filter(func(l): return String(l.text) != "")


## Optional LLM phrasing: one call per meeting, each speaker described only by her own facts.
func _phrase(a: String, b: String, lines: Array) -> Array:
	var llm: LLMClient = main.llm
	if llm == null or llm.provider == "mock" or not (main.get("focus") in [a, b]):
		return lines          # API calls only when the conversation is on camera
	var facts := {}
	for who in [a, b]:
		var m := WorldState.mind(who)
		facts[who] = {"name": MagicSystem.display_name(who), "level": m.level(), "personality": "bright, curious, gentle" if who == "mika" else "proud, confident, competitive, dry humour",
			"own_latest_deed": latest_deed(who).get("text", "")}
	var sys := "Rewrite the lines of a short spoken exchange between two young mages in a fantasy world, keeping each line's meaning and speaker. Use only the facts given; each speaker knows only her own facts. Under 22 words per line. No em dashes. Reply as JSON {\"lines\": [string, ...]} with exactly %d lines in the same order." % lines.size()
	var r: Dictionary = await llm.ask_json(sys, JSON.stringify({"speakers": facts, "lines": lines.map(func(l): return {"speaker": l.who, "text": l.text})}), {"lines": []})
	var got = r.json.get("lines", [])
	if not got is Array or (got as Array).size() != lines.size():
		return lines
	var out := []
	for i in lines.size():
		var tx := VoiceService.clean(String(got[i]))
		var nl: Dictionary = (lines[i] as Dictionary).duplicate()
		# lines that state a remembered fact verbatim (a clue's own words) are kept exactly
		if not nl.has("teach") or String(nl.teach.get("text", "")) != String(nl.text):
			nl["text"] = tx if tx.length() > 2 and tx.split(" ").size() <= 28 else lines[i].text
		out.append(nl)
	return out


## A creature finished by one mage while the other had been fighting it: a small spark of rivalry.
func _on_defeat(m: Monster, by: String) -> void:
	for who in m.hit_by:
		if who != by and by != "":
			var r := rel(who, by)
			r.rivalry = minf(1.0, float(r.rivalry) + 0.15)
