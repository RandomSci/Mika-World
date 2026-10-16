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
## Milestone I: comments are ROUTED - one naming Luna is for Luna, one naming Mika for Mika, a general one
## for the mage the camera follows. A mage answers only when she is in view and free (otherwise the comment
## waits until it expires), in her own voice, looking at the camera; she remembers the viewer in HER mind.
## DEV only: comments come from the bridge / F9 / tests, never from a real stream.

signal replied(entry: Dictionary)

const DIRECT_RE := "\\b(you|your|yours|do you|can you|could you|would you|what do you|tell me|how do you|are you|will you|what's your|what is your|mika)\\b"
const SIDE_RE := "(^@\\S+|\\b(chat|guys|everyone|anyone|somebody|viewers|mods)\\b|\\b(lol|lmao|haha|same|true|yeah|yep|nope|bruh)\\b$)"
const COOLDOWN_S := 45.0
const MAX_AGE_S := 120.0
const REPEAT_WINDOW_S := 300.0    # identical text from anyone is limited within this window (not forever)

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
	# "skip" during a transformation she has already shown in full: the 8 s version (not answered as a comment)
	if norm.strip_edges().trim_prefix("!") == "skip" and main.transformer and main.transformer.sequence and main.transformer.sequence.playing != "":
		var ok: bool = main.transformer.sequence.request_skip(String(msg.get("author", "viewer")))
		return {"accepted": ok, "skip": ok, "why": "" if ok else "this transformation can't be skipped (first showing or nearly over)"}
	var times: Array = (recent_texts.get(norm, []) as Array).filter(func(t): return _now() - float(t) < REPEAT_WINDOW_S)
	if times.size() >= 2:
		return {"accepted": false, "why": "same text repeated too often (within %d s)" % int(REPEAT_WINDOW_S)}
	times.append(_now())
	recent_texts[norm] = times
	var entry := {"message_id": id, "author_id": String(msg.get("author_id", "viewer")), "author": String(msg.get("author", "viewer")),
		"text": text, "score": snappedf(score(text), 0.01), "received": snappedf(_now(), 0.1), "to": addressee(text)}
	queue.append(entry)
	var dance := dance_intent(text)
	if not dance.is_empty() and main.get("performance"):
		entry["dance"] = dance
		if bool(dance.get("stop", false)):
			main.performance.interrupt("a viewer asked her to stop")
		else:
			main.performance.request(String(dance.who), {"with": String(dance.get("with", "")), "dance": String(dance.get("dance", "")),
				"partner_if_near": bool(dance.get("together", false)), "why": "asked by " + String(entry.author)})
	return {"accepted": true, "score": entry.score, "dance": dance}


## A request to dance, in the words viewers used on the Three.js stream ("go dancing", "can you dance", "let's
## dance", "Mika, do the macarena", "you two dance!", "stop dancing"). Returns {} when it is not one, else
## {who, with?, together?, dance?} or {stop: true}. Talking ABOUT dancing ("I don't dance", "what dance was
## that?") is not a request.
const DANCES := [["macarena", "dance_macarena"], ["ymca", "dance_ymca"], ["chicken", "dance_chicken"], ["belly", "dance_belly"],
	["snake", "dance_snake"], ["booty", "dance_booty"], ["bounce", "dance_booty"], ["step", "dance_step"], ["hip hop", "dance_step"]]


func dance_intent(text: String) -> Dictionary:
	var t := text.to_lower().replace("-", " ")
	if RegEx.create_from_string("\\b(stop|quit|cancel|enough)\\b.*\\b(danc\\w*|routine)\\b").search(t):
		return {"stop": true}
	if RegEx.create_from_string("\\b(don't|dont|do not|never|can't|cannot)\\s+(go\\s+)?danc").search(t):
		return {}
	if RegEx.create_from_string("\\b(what|which|how did|who taught)\\b.*\\bdanc").search(t):
		return {}
	var routine := ""
	for d in DANCES:
		if t.contains(String(d[0])):
			routine = String(d[1])
			break
	var asks := RegEx.create_from_string("(^|\\b)(please\\s+)?(dance|danc(e|ing) (for|with) us)\\b|\\b(can|could|would|will) (you|u)\\s+(please\\s+)?(go\\s+)?(dance|do|try|perform|show)\\b|\\b(let's|lets|let us|time to|wanna|want to|go)\\s+(go\\s+)?(dance|dancing|party)\\b|\\b(do|try|show|perform)\\s+(the|a|your|us)\\b").search(t) != null
	if not asks or (routine == "" and not t.contains("danc") and not t.contains("party")):
		return {}
	var both := RegEx.create_from_string("\\b(both|you two|together|everyone dance|mika and luna|luna and mika)\\b").search(t) != null
	var to := addressee(text)
	var who := to if to != "general" else String(main.get("focus") if main.get("focus") else "mika")
	var out := {"who": who, "dance": routine}
	if both:
		out["with"] = "luna" if who == "mika" else "mika"
		out["together"] = true
	return out


## Who a comment is for: a mage it names, else "general" (answered by whoever the camera follows).
func addressee(text: String) -> String:
	var t := text.to_lower()
	var hits := []
	for who in main.mages:
		if RegEx.create_from_string("\\b%s\\b" % MagicSystem.display_name(who).to_lower()).search(t):
			hits.append(who)
	return hits[0] if hits.size() == 1 else "general"


func speaker_for(e: Dictionary) -> String:
	return String(e.to) if String(e.get("to", "general")) != "general" else String(main.get("focus") if main.get("focus") else "mika")


## Is `who` able to answer right now? In view, not casting / reading / talking / fighting / performing.
func _safe_point(who := "mika") -> bool:
	var m: WorldCharacter = main.characters.get(who)
	if m == null or not m.visible or m.casting or main.voice.busy() or main.magic.busy:
		return false
	if main.book_reader.reading() and main.book_reader.current.get("reader", "") == who:
		return false   # wait for the page to finish (the reader keeps its own pace)
	if main.performance and main.performance.busy():
		return false
	var b = main.mage_brains.get(who)
	if b and (b.threat != null or String(b.current.get("kind", "")) in ["hunt", "meet", "converse"]):
		return false
	if main.transformer and main.transformer.playing != "":
		return false
	return main.streaming.state == "idle"


func _process(_delta: float) -> void:
	if _busy or queue.is_empty():
		return
	var now := _now()
	for e in queue.filter(func(x): return now - float(x.received) >= MAX_AGE_S):
		log.append({"message_id": e.message_id, "author": e.author, "comment": e.text, "to": e.to, "expired": true, "t": snappedf(now, 0.1)})
	queue = queue.filter(func(e): return now - float(e.received) < MAX_AGE_S)
	var eligible := queue.filter(func(e): return now - float(answered_at.get(e.author_id, -1e9)) > COOLDOWN_S and float(e.score) > -1.0 and _safe_point(speaker_for(e)))
	if eligible.is_empty():
		return
	eligible.sort_custom(func(a, b): return a.score > b.score)
	var pick: Dictionary = eligible[0]
	queue.erase(pick)
	_answer(pick)


func _answer(e: Dictionary) -> void:
	_busy = true
	answered_at[e.author_id] = _now()
	var who := speaker_for(e)
	var brain = main.mage_brains.get(who, main.brain)
	var ctx := _context(who)
	var mind := WorldState.mind(who)
	var known := int(mind.knowledge.get("viewer:" + String(e.author_id), 0))
	ctx["knows_this_viewer"] = known > 0
	var mock := {"reply": _mock_reply(e, ctx, who), "suggestion": _suggestion(e, who)}
	var persona := "a young mage, bright and curious" if who == "mika" else "a young mage, proud, confident and a little dry"
	var sys := "You are %s, %s, in a fantasy sanctuary that viewers watch through a camera. Answer the viewer in one or two short, natural sentences using ONLY the facts provided. No em dashes. JSON {\"reply\": string}." % [MagicSystem.display_name(who), persona]
	var r: Dictionary
	if who == String(main.get("focus")):
		r = await main.llm.ask_json(sys, JSON.stringify({"viewer": e.author, "comment": e.text, "facts": ctx}), {"reply": mock.reply})
	else:
		r = {"json": {"reply": mock.reply}, "provider": "authored (not on camera)"}
	var reply := VoiceService.clean(String(r.json.get("reply", mock.reply)))
	if reply.split(" ").size() > 45 or reply.length() < 2:
		reply = mock.reply
	main.show_comment(e.author, e.text)
	if main.attention:
		main.attention.glance_camera(who, clampf(reply.split(" ").size() / 2.6, 1.5, 6.0))
	var c: WorldCharacter = main.characters.get(who)
	if c and known == 0 and (String(e.text).to_lower().begins_with("hi") or String(e.text).to_lower().begins_with("hello") or String(e.text).to_lower().begins_with("hey")):
		c.play_gesture("waving", 0.3, 0.5)
	var spoken: Dictionary = await main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), reply)
	mind.knowledge["viewer:" + String(e.author_id)] = known + 1       # she remembers this viewer (her memory only)
	var applied := ""
	if mock.suggestion != "" and brain:
		if not mock.suggestion.begins_with("magic:"):
			brain.curiosity_bonus[mock.suggestion] = 0.45   # spell requests carry their own bonus in the planner
		applied = mock.suggestion
	var out := {"message_id": e.message_id, "author": e.author, "comment": e.text, "to": e.to, "speaker": who, "score": e.score, "reply": reply, "provider": r.provider,
		"audio": spoken.get("audio", false), "seconds": spoken.get("seconds", 0), "suggestion_applied": applied, "t": snappedf(_now(), 0.1)}
	log.append(out)
	replied.emit(out)
	_busy = false


func _context(who := "mika") -> Dictionary:
	var b = main.mage_brains.get(who, main.brain)
	return {"name": MagicSystem.display_name(who), "doing": b.current.get("label", "taking a short break") if b else "",
		"story": main.story.objective() if who == "mika" else "",
		"level": WorldState.mind(who).level(), "rank": WorldState.mage_rank(who),
		"spells": main.magic.known_spells(who).filter(func(s): return s.castable).map(func(s): return "%s (%s)" % [s.name, s.tier]),
		"visitors": main.npcs.present.keys().map(func(k): return main.dialogue.travellers[k].name)}


func _mock_reply(e: Dictionary, ctx: Dictionary, who := "mika") -> String:
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
		return ("I'm Level %d. Level 100 is a long way off." % int(ctx.level)) if who == "mika" else ("Level %d. For now." % int(ctx.level))
	if ctx.get("knows_this_viewer", false) and (t.begins_with("hi") or t.begins_with("hello") or t.begins_with("hey")):
		return ("%s! You're back." % name) if who == "mika" else ("%s. Again." % name)
	var sug := _suggestion(e)
	if sug != "":
		return "Good idea, %s. I might try that next." % name
	if t.contains("try") or t.contains("cast") or t.contains("use"):
		return "I don't think I can do that yet, %s. I'll keep studying." % name
	if t.begins_with("hi") or t.begins_with("hello") or t.begins_with("hey"):
		return ("Hello %s! Welcome to the sanctuary." % name) if who == "mika" else ("Hm. Hello, %s." % name)
	return ("Thanks, %s. I'm still learning, so I'll keep that in mind." % name) if who == "mika" else ("Noted, %s." % name)


## A comment that names something she can actually do maps to one of the planner's options.
## Spells are matched by name ("wind gust", "water ripple") and objects by kind ("brazier", "pond"); the nearest
## valid object of that kind becomes a viewer request the planner may honour. Anything else falls back to label words.
const KIND_WORDS := {"brazier": ["brazier", "fire", "flame"], "water": ["pond", "water"], "rune": ["rune"],
	"marked_stone": ["marked stone", "gate stone", "sign"], "relic": ["heartstone", "relic"], "practice_crystal": ["crystal"], "dummy": ["dummy", "target"]}

func _suggestion(e: Dictionary, who := "mika") -> String:
	var brain = main.mage_brains.get(who, main.brain)
	if brain == null:
		return ""
	var t := String(e.text).to_lower()
	var spell_id := ""
	for s in main.magic.known_spells(who):
		if s.castable and t.contains(String(s.name).to_lower()):
			spell_id = s.id
	if spell_id != "":
		var mika: WorldCharacter = main.characters[who]
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
			brain.viewer_request[spell_id] = {"target": best, "t": Time.get_ticks_msec() / 1000.0}
			return "magic:%s:%s" % [spell_id, best]
	for o in brain.options():
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
