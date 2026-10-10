class_name DialogueService
extends Node
## One shared, on-demand conversation system for every traveller (no permanent per-NPC processes).
## For a conversation the engine decides WHAT can be said: it picks beats whose conditions hold in verified
## world state (what Mika knows, what the NPC witnessed or was told, items she carries). Each NPC only ever
## gets its own identity, its own facts, its own memories and the current situation. An optional LLM may
## re-phrase a beat's lines in the NPC's voice; its output is checked (length, no em dashes, no facts outside
## the beat) and otherwise the authored lines are used. Knowledge transfer, trades and relationship changes
## are applied by the engine from the beat, never by the model.

var main: Node
var travellers := {}
var last := {}


func setup(m: Node) -> void:
	main = m
	var f := FileAccess.open("res://data/npcs.json", FileAccess.READ)
	travellers = JSON.parse_string(f.get_as_text()).travellers


func state_of(npc_id: String) -> Dictionary:
	if not WorldState.npc_state.has(npc_id):
		WorldState.npc_state[npc_id] = {"met": false, "visits": 0, "conversations": 0, "relationship": 0.0, "taught": [], "knows_from_mika": [],
			"used_beats": [], "memories": []}
	return WorldState.npc_state[npc_id]


func _ok(npc_id: String, beat: Dictionary, npc: TravelerNPC) -> bool:
	var st := state_of(npc_id)
	if st.used_beats.has(beat.id) and not beat.when.is_empty():
		return false
	var w: Dictionary = beat.when
	if w.get("first_meeting", false) and st.met:
		return false
	if w.has("mika_knows") and not WorldState.knowledge.has(w.mika_knows):
		return false
	if w.has("not_taught") and st.taught.has(w.not_taught):
		return false
	if w.has("mika_has_item") and int(WorldState.inventory.get(w.mika_has_item, 0)) <= 0:
		return false
	if w.has("witnessed_effect") and not npc.witnessed.any(func(e): return e.effect == w.witnessed_effect):
		return false
	if beat.has("requires_mika_event"):
		var ev: String = beat.requires_mika_event
		if not WorldState.knowledge.keys().any(func(k): return String(k).begins_with("reaction:") and String(k).ends_with(":" + ev)):
			return false
	if beat.has("learn") and st.knows_from_mika.has(beat.learn):
		return false
	return true


## Beats for this conversation: greeting first, then specific beats in order, then one generic line.
func choose_beats(npc_id: String, npc: TravelerNPC, max_beats := 2) -> Array:
	var t: Dictionary = travellers[npc_id]
	var specific := []
	var generic := []
	for b in t.beats:
		if not _ok(npc_id, b, npc):
			continue
		if (b.when as Dictionary).is_empty():
			generic.append(b)
		else:
			specific.append(b)
	var out := specific.slice(0, max_beats)
	if out.size() < max_beats and not generic.is_empty():
		out.append(generic[state_of(npc_id).conversations % generic.size()])
	return out


func context_for(npc_id: String, npc: TravelerNPC) -> Dictionary:
	var t: Dictionary = travellers[npc_id]
	var st := state_of(npc_id)
	var own := {}
	for k in t.knowledge:
		own[k] = t.knowledge[k]
	return {"identity": {"name": t.name, "role": t.role, "personality": t.personality, "dialogue_style": t.dialogue_style, "motive": t.motive},
		"knows": own, "told_by_mika": st.knows_from_mika, "memories": st.memories.slice(maxi(0, st.memories.size() - 5)),
		"situation": {"location": WorldState.current_location, "night": WorldState.night, "relationship": snappedf(st.relationship, 0.01)},
		"witnessed_here": npc.witnessed.slice(maxi(0, npc.witnessed.size() - 4))}


## A whole spoken exchange. Returns exactly what was said and what changed.
func converse(npc_id: String, mika: WorldCharacter) -> Dictionary:
	var npc: TravelerNPC = main.npcs.present.get(npc_id)
	if npc == null or not is_instance_valid(npc) or npc.state in ["leaving", "gone", "arriving"]:
		return {"ok": false, "detail": "%s is not here to talk to" % travellers.get(npc_id, {}).get("name", npc_id)}
	if npc.global_position.distance_to(mika.global_position) > 4.5:
		return {"ok": false, "detail": "too far from %s (%.1f m); walk closer first" % [travellers[npc_id].name, npc.global_position.distance_to(mika.global_position)]}
	var t: Dictionary = travellers[npc_id]
	var st := state_of(npc_id)
	var beats := choose_beats(npc_id, npc)
	var res := {"ok": true, "npc": npc_id, "name": t.name, "lines": [], "taught": [], "npc_learned": [], "trade": {}, "provider": "authored"}
	npc.state = "talking"
	npc.talk_target = mika
	mika.look_at_point(npc.global_position + Vector3(0, 1.4, 0))
	mika.look_head_at(npc.global_position + Vector3(0, 1.5, 0))
	if main.director and main.director.enabled:
		main.director.focus_conversation(npc, 6.0 + beats.size() * 9.0)
	await get_tree().create_timer(0.6).timeout
	for b in beats:
		var lines := {"npc": String(b.npc), "mika": String(b.mika)}
		var phr := await _phrase(npc_id, npc, b, lines)
		res.provider = phr.provider
		lines = phr.lines
		var r1: Dictionary = await main.voice.say(String(t.voice), lines.npc)
		res.lines.append({"speaker": t.name, "text": lines.npc, "audio": r1.get("audio", false)})
		await get_tree().create_timer(0.35).timeout
		var r2: Dictionary = await main.voice.say("mika", lines.mika)
		res.lines.append({"speaker": "Mika", "text": lines.mika, "audio": r2.get("audio", false)})
		await get_tree().create_timer(0.5).timeout
		# engine-applied consequences
		if b.has("teach"):
			var fact: String = b.teach
			var eff: Dictionary = {"knowledge": {fact: 1, "from:%s:%s" % [npc_id, fact]: 1}}
			var extra: Dictionary = t.get("teaches", {}).get(fact, {})
			if extra.has("skills"):
				eff["skills"] = extra.skills
			var ch := WorldState.record_activity({"id": "talk:%s:%s" % [npc_id, b.id], "verb": "talk", "label": "Talked with %s" % t.name}, eff)
			if not st.taught.has(fact):
				st.taught.append(fact)
			res.taught.append({"fact": fact, "text": t.knowledge.get(fact, ""), "changes": ch})
		if b.has("learn") and not st.knows_from_mika.has(b.learn):
			st.knows_from_mika.append(b.learn)
			res.npc_learned.append(b.learn)
		if b.has("trade"):
			var item: String = b.trade
			var tr: Dictionary = t.get("trades", {}).get(item, {})
			if int(WorldState.inventory.get(item, 0)) > 0 and not tr.is_empty():
				var gives: Dictionary = tr.gives
				var ch2 := WorldState.record_activity({"id": "trade:%s" % npc_id, "verb": "trade", "label": "Traded with %s" % t.name},
					{"items": gives.merged({item: -1})})
				res.trade = {"gave": item, "received": gives, "changes": ch2}
		st.used_beats.append(b.id)
	st.met = true
	st.conversations += 1
	st.relationship = minf(1.0, st.relationship + 0.1 + 0.05 * res.taught.size())
	st.memories.append({"unix": int(Time.get_unix_time_from_system()), "summary": "talked about %s" % ", ".join(beats.map(func(x): return x.id)),
		"facts_shared_with_mika": res.taught.map(func(x): return x.fact), "facts_mika_shared": res.npc_learned})
	res["relationship"] = snappedf(st.relationship, 0.01)
	npc.state = "idle"
	npc.talk_target = null
	mika.look_head_at(null)
	last = res
	WorldState.record_activity({"id": "conversation:%s" % npc_id, "verb": "talk", "label": "Conversation with %s" % t.name}, {})
	return res


## Optional LLM phrasing. The model only sees this NPC's identity, its own facts, its memories, the situation
## and the beat's intent; it must return {"npc": "...", "mika": "..."}; anything off-limits falls back.
func _phrase(npc_id: String, npc: TravelerNPC, beat: Dictionary, lines: Dictionary) -> Dictionary:
	var llm: LLMClient = LLMClient.instance
	if llm == null or llm.provider == "mock":
		return {"lines": lines, "provider": "authored"}
	var ctx := context_for(npc_id, npc)
	var sys := "You write two short spoken lines for a fantasy game conversation between %s and Mika, a young mage. Use only the facts given. No em dashes. Reply as JSON {\"npc\": string, \"mika\": string}, each under 30 words." % ctx.identity.name
	var user := JSON.stringify({"npc_context": ctx, "beat_intent": lines, "beat_facts": [travellers[npc_id].knowledge.get(beat.get("teach", ""), "")]})
	var r: Dictionary = await llm.ask_json(sys, user, lines)
	var j: Dictionary = r.json
	if not (j.get("npc") is String and j.get("mika") is String):
		return {"lines": lines, "provider": "authored (invalid llm output)"}
	var a := VoiceService.clean(String(j.npc))
	var b := VoiceService.clean(String(j.mika))
	if a.split(" ").size() > 40 or b.split(" ").size() > 40 or a.length() < 3 or b.length() < 3:
		return {"lines": lines, "provider": "authored (llm output rejected)"}
	return {"lines": {"npc": a, "mika": b}, "provider": r.provider}
