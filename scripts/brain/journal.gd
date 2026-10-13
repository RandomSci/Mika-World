class_name Journal
extends RefCounted
## Mika's training journal: entries are written ONLY from verified events in WorldState.activity_log
## (clues found, first-time magic reactions, books finished, conversations, brews, trials, rank).
## The journal is a readable book (BookLibrary "mika_journal") whose pages are these entries.

static func entries() -> Array:
	return WorldState.knowledge.get("journal", [])


static func book() -> Dictionary:
	var pages := []
	for e in entries():
		pages.append({"heading": String(e.heading), "text": String(e.text)})
	if pages.is_empty():
		pages.append({"heading": "First Page", "text": "Nothing written yet. I should write down what actually happens, not what I hope will happen."})
	return {"title": "Mika's Training Journal", "style": "book", "location": "Ritual Circle, writing desk", "pages": pages}


## Compose the next entry from what happened since the last one. Returns {} if nothing worth writing.
static func compose() -> Dictionary:
	var log: Array = WorldState.activity_log
	var from: int = int(WorldState.knowledge.get("journal_cursor", 0))   # seq of the last event already considered
	var lines := []
	var seen := {}
	for e: Dictionary in log:
		if int(e.get("seq", 0)) <= from:
			continue
		var a: Dictionary = e.get("activity", {})
		var id := String(a.get("id", ""))
		var ch: Dictionary = e.get("changes", {})
		var line := ""
		if id.begins_with("spell:"):
			for k in ch:
				if String(k).begins_with("knowledge.reaction:") and ch[k][0] == 0:
					var parts := String(k).trim_prefix("knowledge.reaction:").split(":")
					line = _reaction_line(parts[0], parts[1], parts[2])
		elif id == "clue_found" or id == "story:echo":
			line = "Something important today: %s." % String(a.get("label", "a clue")).to_lower() if id == "clue_found" else "The Heartstone beat three times. The circle feels different now, stronger."
		elif id.begins_with("conversation:"):
			line = "I talked with %s." % String(a.get("label", "")).trim_prefix("Conversation with ")
		elif id.begins_with("talk:") and ch.keys().any(func(k): return String(k).begins_with("knowledge.fact:")):
			line = "%s taught me something useful." % String(a.get("label", "")).trim_prefix("Talked with ")
		elif id == "alchemy_luminous_draught":
			line = "I brewed a Luminous Draught. It glowed and smelled of rain, exactly like the receipt said."
		elif id == "alchemy_fizz":
			line = "Ember salt and moonwater fizzed and smoked. Never again, or at least not on purpose."
		elif id.begins_with("read:"):
			var bid := id.get_slice(":", 1)
			if not seen.has("read:" + bid):
				line = "I read %s." % BookLibrary.book(bid).get("title", bid)
				seen["read:" + bid] = true
		for k in ch:
			if String(k).begins_with("trial."):
				line = "Trial complete: %s." % String(k).trim_prefix("trial.").replace("_", " ")
			if String(k) == "rank":
				line = "I am an %s now." % String(ch[k][1]) if String(ch[k][1]).begins_with("A") or String(ch[k][1]).begins_with("I") else "I am a %s now." % String(ch[k][1])
		if line != "" and not lines.has(line):
			lines.append(line)
	if lines.is_empty():
		return {}
	var n := entries().size() + 1
	var text := " ".join(lines.slice(0, 6))
	return {"heading": "Entry %d" % n, "text": VoiceService.clean(text), "cursor": WorldState.activity_seq}


static func _reaction_line(spell: String, kind: String, effect: String) -> String:
	var s: String = MagicSystem.spell(spell).get("name", spell)
	var nice := {"flicker": "only made it flicker", "extinguished": "put it out completely", "guttered": "made it gutter low", "steam": "turned to steam",
		"relit": "brought it back", "flare": "made it flare up", "arcane_flame": "turned it blue", "surge": "lifted a column of water",
		"ripple": "sent rings across it", "ruffled": "ruffled the surface", "glow_ring": "lit a ring of light in it", "lit": "lit it up",
		"shattered": "shattered it", "rang": "made it ring but not break", "revealed": "woke a hidden glyph", "resonance": "made it answer like a heartbeat",
		"swayed": "made it sway", "scorched": "scorched it", "soaked": "soaked it", "pattern_reflection": "showed a seven-pointed pattern",
		"awakened": "woke it", "charged": "filled me with gathered power", "mist_veil": "laid a veil of mist on it"}
	var what := {"brazier": "the brazier", "water": "the pond", "rune": "a rune target", "practice_crystal": "the practice crystal", "dummy": "the practice dummy",
		"marked_stone": "the marked stone", "relic": "the Heartstone", "self": "myself"}
	return "%s on %s %s." % [s, what.get(kind, kind), nice.get(effect, effect.replace("_", " "))]
