class_name ViewerChat
extends Node
## DEV viewer-comment path for Godot Mika (mock comments only; never connected to a real livestream).
## Mirrors the production YouTube rules (read-only reference: Mika-Live src/open_llm_vtuber/live/youtube_live.py):
##   * de-duplication by message id + same-text repeat limit inside a window
##   * priority score: questions +3, addressed to Mika +3, wh-words +1, sensible length +0.7, tiny -1.5,
##     side conversation -2.5, @mention of someone else -2
##   * per-viewer cooldown; stale messages expire
## Routing: the best eligible comment is answered at a SAFE POINT only (not mid-cast, not while she or a
## visitor is speaking, not mid-page while reading); committed gameplay is never aborted by chat.
## The reply is built from verified state (what she is doing, her spells, the story) by the shared LLM client
## (mock by default), spoken with her real voice and subtitled with the viewer's name preserved. A comment
## that suggests a valid activity ("try the wind spell on the brazier") nudges the planner's next choice.

signal replied(entry: Dictionary)

const DIRECT_RE := "\\b(you|your|yours|do you|can you|could you|would you|what do you|tell me|how do you|are you|will you|what's your|what is your|mika)\\b"
const SIDE_RE := "(^@\\S+|\\b(chat|guys|everyone|anyone|somebody|viewers|mods)\\b|\\b(lol|lmao|haha|same|true|yeah|yep|nope|bruh)\\b$)"
const COOLDOWN_S := 45.0
const MAX_AGE_S := 120.0

var main: Node
var queue: Array = []
var seen_ids := {}
var recent_texts := {}
var answered_at := {}            # author id -> time
var log: Array = []
var _direct := RegEx.new()
var _side := RegEx.new()
var _busy := false


func setup(m: Node) -> void:
	main = m
	_direct.compile("(?i)" + DIRECT_RE)
	_side.compile("(?i)" + SIDE_RE)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func score(text: String) -> float:
	var t := text.strip_edges()
	var n := t.to_lower()
	var s := 0.0
	if t.contains("?"): s += 3.0
	if _direct.search(n): s += 3.0
	if RegEx.create_from_string("\\b(why|how|what|when|where|can|should|would|who)\\b").search(n): s += 1.0
	if t.length() >= 12 and t.length() <= 180: s += 0.7
	if t.length() < 4: s -= 1.5
	if _side.search(n) and not t.contains("?"): s -= 2.5
	if n.begins_with("@") and not _direct.search(n): s -= 2.0
	return s


## Accept a comment (from the bridge's mock injection or a test file). Returns whether it was queued and why.
func receive(msg: Dictionary) -> Dictionary:
	var id := String(msg.get("message_id", ""))
	var text := String(msg.get("text", "")).strip_edges()
	if id == "" or text == "":
		return {"accepted": false, "why": "missing id or text"}
	if seen_ids.has(id):
		return {"accepted": false, "why": "duplicate message id"}
	seen_ids[id] = _now()
	var norm := text.to_lower()
	if int(recent_texts.get(norm, 0)) >= 2:
		return {"accepted": false, "why": "same text repeated too often"}
	recent_texts[norm] = int(recent_texts.get(norm, 0)) + 1
	var entry := {"message_id": id, "author_id": String(msg.get("author_id", "viewer")), "author": String(msg.get("author", "viewer")),
		"text": text, "score": snappedf(score(text), 0.01), "received": snappedf(_now(), 0.1)}
	queue.append(entry)
	return {"accepted": true, "score": entry.score}


func _safe_point() -> bool:
	var m: WorldCharacter = main.characters["mika"]
	if m.casting or main.voice.busy() or main.magic.busy:
		return false
	if main.book_reader.reading():
		return false   # wait for the page to finish (the reader keeps its own pace)
	return main.streaming.state == "idle"


func _process(_delta: float) -> void:
	if _busy or queue.is_empty() or not _safe_point():
		return
	var now := _now()
	queue = queue.filter(func(e): return now - float(e.received) < MAX_AGE_S)
	var eligible := queue.filter(func(e): return now - float(answered_at.get(e.author_id, -1e9)) > COOLDOWN_S and float(e.score) > -1.0)
	if eligible.is_empty():
		return
	eligible.sort_custom(func(a, b): return a.score > b.score)
	var pick: Dictionary = eligible[0]
	queue.erase(pick)
	_answer(pick)


func _answer(e: Dictionary) -> void:
	_busy = true
	answered_at[e.author_id] = _now()
	var ctx := _context()
	var mock := {"reply": _mock_reply(e, ctx), "suggestion": _suggestion(e)}
	var sys := "You are Mika, a young mage streaming from her sanctuary. Answer the viewer in one or two short, natural sentences using ONLY the facts provided. No em dashes. JSON {\"reply\": string}."
	var r: Dictionary = await main.llm.ask_json(sys, JSON.stringify({"viewer": e.author, "comment": e.text, "facts": ctx}), {"reply": mock.reply})
	var reply := VoiceService.clean(String(r.json.get("reply", mock.reply)))
	if reply.split(" ").size() > 45 or reply.length() < 2:
		reply = mock.reply
	main.show_comment(e.author, e.text)
	var spoken: Dictionary = await main.voice.say("mika", reply)
	var applied := ""
	if mock.suggestion != "" and main.brain:
		if not mock.suggestion.begins_with("magic:"):
			main.brain.curiosity_bonus[mock.suggestion] = 0.45   # spell requests carry their own bonus in the planner
		applied = mock.suggestion
	var out := {"message_id": e.message_id, "author": e.author, "comment": e.text, "score": e.score, "reply": reply, "provider": r.provider,
		"audio": spoken.get("audio", false), "seconds": spoken.get("seconds", 0), "suggestion_applied": applied, "t": snappedf(_now(), 0.1)}
	log.append(out)
	replied.emit(out)
	_busy = false


func _context() -> Dictionary:
	var b = main.brain
	return {"doing": b.current.get("label", "taking a short break") if b else "", "story": main.story.objective(),
		"rank": WorldState.mage_rank(), "spells": main.magic.known_spells().filter(func(s): return s.castable).map(func(s): return "%s (%s)" % [s.name, s.tier]),
		"visitors": main.npcs.present.keys().map(func(k): return main.dialogue.travellers[k].name)}


func _mock_reply(e: Dictionary, ctx: Dictionary) -> String:
	var t := String(e.text).to_lower()
	var name := String(e.author)
	if t.contains("what are you doing") or t.contains("what you doing") or t.contains("doing now"):
		return "Hi %s! Right now I'm going to %s." % [name, ctx.doing] if not String(ctx.doing).begins_with("taking") else "Hi %s! Just catching my breath between lessons." % name
	if t.contains("spell") and (t.contains("know") or t.contains("which") or t.contains("what")):
		var names: Array = ctx.spells.slice(0, 4).map(func(x): return String(x).get_slice(" (", 0))
		if names.size() == 1:
			return "So far I can cast %s." % names[0]
		return "So far I can cast %s and %s." % [", ".join(names.slice(0, names.size() - 1)), names[-1]]
	if t.contains("heartstone") or t.contains("story") or t.contains("mystery"):
		return "The Heartstone is the big question. %s" % String(ctx.story)
	if t.contains("rank") or t.contains("level"):
		return "I'm %s now. Level 100 Archmage is a long way off." % String(ctx.rank)
	var sug := _suggestion(e)
	if sug != "":
		return "Good idea, %s. I might try that next." % name
	if t.contains("try") or t.contains("cast") or t.contains("use"):
		return "I don't think I can do that yet, %s. I'll keep studying." % name
	if t.begins_with("hi") or t.begins_with("hello") or t.begins_with("hey"):
		return "Hello %s! Welcome to the sanctuary." % name
	return "Thanks, %s. I'm still learning, so I'll keep that in mind." % name


## A comment that names something she can actually do maps to one of the planner's options.
## Spells are matched by name ("wind gust", "water ripple") and objects by kind ("brazier", "pond"); the nearest
## valid object of that kind becomes a viewer request the planner may honour. Anything else falls back to label words.
const KIND_WORDS := {"brazier": ["brazier", "fire", "flame"], "water": ["pond", "water"], "rune": ["rune"],
	"marked_stone": ["marked stone", "gate stone", "sign"], "relic": ["heartstone", "relic"], "practice_crystal": ["crystal"], "dummy": ["dummy", "target"]}

func _suggestion(e: Dictionary) -> String:
	if main.brain == null:
		return ""
	var t := String(e.text).to_lower()
	var spell_id := ""
	for s in main.magic.known_spells():
		if s.castable and t.contains(String(s.name).to_lower()):
			spell_id = s.id
	if spell_id != "":
		var mika: WorldCharacter = main.characters["mika"]
		var spell := MagicSystem.spell(spell_id)
		var kinds: Array = spell.get("target_kinds", ["*"])
		var best := ""
		var best_d := INF
		var reactives: Dictionary = main.magic.reactives()
		for rid in reactives:
			var r: ReactiveElement = reactives[rid]
			if not kinds.has("*") and not kinds.has(r.kind):
				continue
			var named := false
			for w in KIND_WORDS.get(r.kind, [r.kind]):
				if t.contains(w):
					named = true
			if named and r.global_position.distance_to(mika.global_position) < best_d:
				best = rid
				best_d = r.global_position.distance_to(mika.global_position)
		if best != "":
			main.brain.viewer_request[spell_id] = {"target": best, "t": Time.get_ticks_msec() / 1000.0}
			return "magic:%s:%s" % [spell_id, best]
	for o in main.brain.options():
		var words := String(o.label).to_lower().split(" ")
		var hits := 0
		for w in words:
			if w.length() > 4 and t.contains(w):
				hits += 1
		if hits >= 2:
			return o.key
	return ""


func describe() -> Dictionary:
	return {"queued": queue.size(), "seen": seen_ids.size(), "recent_replies": log.slice(maxi(0, log.size() - 6))}
