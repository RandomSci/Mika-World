class_name MageDialogue
extends Node
## Mika and Luna talking to each other for real (V3 launch blocker). A conversation is built ONE LINE AT A TIME:
## each line comes from the speaker's own mind (her level, what she is doing, where, her recent deeds, her spells,
## her memories of earlier talks, what the other has told her) plus the words actually said so far - so every
## reply answers what the other really said. Either mage can start one:
##   * a planned meeting (her planner picked "talk with ..."; MageTalk walks her over, then calls converse())
##   * on the way / at rest: both nearby and doing something calm (walking, resting, reading, camping) - a
##     short exchange while they carry on; no one is stopped or moved
##   * because something happened: a level, a discovery, a won fight, the other struggling in a fight
## Pipelined so there are no dead pauses: while a line is being spoken, the listener's reply is already being
## written (she has heard the words) and its voice synthesised. Either of them can end it ("end": true) and both
## go back to what they were doing. Afterwards each keeps HER OWN one-line memory of it (talks:<other>), and the
## lines she said recently are fed back so she does not repeat herself. Separate minds: a speaker is only ever
## given her own facts; the other's knowledge never leaks in.

signal conversation_started(entry: Dictionary)
signal conversation_finished(entry: Dictionary)

const PERSONA := {
	"mika": "a young mage: curious, playful, slightly chaotic, opinionated and independent, warm and gentle with friends, honest when something goes wrong",
	"luna": "a young Umbral mage: calm and confident, a little proud and competitive, with a dry deadpan sense of humour; she loves stars, puzzles and quiet facts, teases Mika when she gets dramatic, but clearly cares about her",
}
const EMOTIONS := ["happy", "excited", "curious", "thoughtful", "playful", "proud", "concerned", "surprised", "relieved", "frustrated", "determined", "neutral"]
const CALM := ["", "roam", "explore", "rest", "journal", "gather", "research", "attune", "together", "listen_rain", "investigate", "away"]
const AMBIENT_GAP_S := 200.0          # at least this long after their last talk before a chat on the way
const EVENT_GAP_S := 45.0             # a real event can start one sooner (but never over another talk)
const MAX_LINES := {"meet": 8, "ambient": 4, "event": 4, "combat": 2, "stargaze": 7}

var main: Node
var active := false
var current := {}                     # {between, mode, lines (spoken so far), topic}
var log: Array = []                   # finished conversations (tests / report)
var pending := {}                     # who -> {kind, text, t} something that just happened to her
var _acc := 0.0
var _rng := RandomNumberGenerator.new()
var _last_end := -1e9                 # unix time the last conversation ended


func setup(m: Node) -> void:
	main = m
	_rng.randomize()
	if main.progression:
		main.progression.leveled.connect(func(w, l): _event(w, "level", "you just reached Level %d" % int(l)))
	if main.spawner:
		main.spawner.monster_defeated.connect(func(mon, by): if by != "": _event(by, "victory", "you just won a fight against a %s" % _creature(mon)))
		main.spawner.mage_hit.connect(_on_hit)
	WorldState.mage_event.connect(_on_mage_event)


static func _now() -> float:
	return Time.get_unix_time_from_system()


func _creature(mon) -> String:
	return String(Spawner.load_data().monsters.get(String(mon.kind), {}).get("name", String(mon.kind))).to_lower()


func _other(who: String) -> String:
	for w in main.mages:
		if w != who:
			return w
	return ""


func _event(who: String, kind: String, text: String) -> void:
	pending[who] = {"kind": kind, "text": text, "t": _now()}


func _on_mage_event(who: String, kind: String, data) -> void:
	if kind != "activity" or not data is Dictionary:
		return
	var id := String(data.get("activity", {}).get("id", ""))
	var label := String(data.get("activity", {}).get("label", ""))
	if id.contains("disc_") or id.begins_with("discover") or id.begins_with("clue:") or (data.get("changes", {}) as Dictionary).keys().any(func(k): return String(k).begins_with("knowledge.clue:")):
		_event(who, "discovery", "you just found something: %s" % label)


## The other one is being hurt in a fight nearby: a short, urgent exchange, started by whoever sees it.
func _on_hit(mage, monster, _amount: float) -> void:
	var hurt := String(mage.character_id)
	var helper := _other(hurt)
	if helper == "" or active:
		return
	var mind := WorldState.mind(hurt)
	if mind.vigor > 0.45 or _now() - _last_end < 25.0:
		return
	var hc: WorldCharacter = main.characters.get(helper)
	if hc == null or not hc.visible or hc.global_position.distance_to(mage.global_position) > 16.0:
		return
	converse(helper, hurt, {"mode": "combat", "topic": {"text": "%s is being hurt badly by a %s right now (she is nearly spent): call out to her - warn, encourage or tell her to fall back" % [MagicSystem.display_name(hurt), _creature(monster)], "key": ""}})


# ------------------------------------------------------------------ talk on the way / because something happened
func _process(delta: float) -> void:
	_acc += delta
	if _acc < 2.0:
		return
	_acc = 0.0
	if active or main.get("mage_talk") == null or main.mage_talk.busy() or not main.get("mages") or main.mages.size() < 2:
		return
	if main.llm == null or main.llm.provider != "openai":
		return                       # without a language model only planned meetings talk (authored lines)
	var a := String(main.mages[0])
	var b := String(main.mages[1])
	var ca: WorldCharacter = main.characters.get(a)
	var cb: WorldCharacter = main.characters.get(b)
	if ca == null or cb == null or not ca.visible or not cb.visible or ca.casting or cb.casting:
		return
	var d := ca.global_position.distance_to(cb.global_position)
	if d > 7.0 or not _calm(a) or not _calm(b):
		return
	# never to someone's back: neither is walking away from the other (a line to nobody is worse than none)
	for pair in [[ca, cb], [cb, ca]]:
		var c1: WorldCharacter = pair[0]
		var away := (c1.global_position - (pair[1] as WorldCharacter).global_position).normalized()
		if c1.velocity.length() > 0.3 and c1.velocity.normalized().dot(away) > 0.3:
			return
	var since := _now() - _last_end
	for w in pending.keys():
		if _now() - float(pending[w].t) > 150.0:
			pending.erase(w)
	# something just happened to one of them: she brings it up (or the other asks about it)
	if not pending.is_empty() and since > EVENT_GAP_S:
		var who := String(pending.keys()[_rng.randi() % pending.size()])
		var ev: Dictionary = pending[who]
		pending.erase(who)
		converse(who, _other(who), {"mode": "event", "topic": {"text": String(ev.text), "key": ""}})
		return
	# otherwise, now and then, a few words on the way (about one every few minutes while they are together)
	if since > AMBIENT_GAP_S and _rng.randf() < 0.06:
		var starter := a if _rng.randf() < _initiative(a, b) else b
		converse(starter, _other(starter), {"mode": "ambient"})


func _calm(who: String) -> bool:
	var br = main.mage_brains.get(who)
	if br == null:
		return true
	if br.threat != null:
		return false
	return String(br.current.get("kind", "")) in CALM


## How likely she is the one to speak first: who has more to tell, and her own temperament for talk.
func _initiative(a: String, b: String) -> float:
	var wa := 1.0 + _news(a, b) * float(Progression.mages.get(a, {}).get("temperament", {}).get("meet", 1.0))
	var wb := 1.0 + _news(b, a) * float(Progression.mages.get(b, {}).get("temperament", {}).get("meet", 1.0))
	return wa / (wa + wb)


func _news(who: String, other: String) -> float:
	var t: Array = Companionship.topics(who, other) if main.get("companionship") else []
	return float(t[0].w) if not t.is_empty() else 0.0


# ------------------------------------------------------------------ one conversation
var _prepared := {}                   # {between: [a, b], seed, target, job} - the opening line, written early


var _body := {"min_d": 99.0, "twitch_mm": 0.0, "n": 0}


## While a talk runs: how close they stand and how much their bodies twitch frame to frame (a standing body should
## not move; a few mm/frame is the idle sway; more is two bodies pushing each other).
func _watch_bodies(ca: WorldCharacter, cb: WorldCharacter) -> void:
	_body = {"min_d": 99.0, "twitch_mm": 0.0, "n": 0}
	var pa := ca.global_position
	var pb := cb.global_position
	while active and is_instance_valid(ca) and is_instance_valid(cb):
		await get_tree().physics_frame
		var d := Vector2(ca.global_position.x - cb.global_position.x, ca.global_position.z - cb.global_position.z).length()
		_body.min_d = minf(float(_body.min_d), d)
		if ca.velocity.length() < 0.2 and cb.velocity.length() < 0.2:
			_body.twitch_mm = float(_body.twitch_mm) + (ca.global_position.distance_to(pa) + cb.global_position.distance_to(pb)) * 500.0
			_body.n = int(_body.n) + 1
		pa = ca.global_position
		pb = cb.global_position


## A planned meeting: her opening line is written (and voiced) while she is still walking over, so she speaks the
## moment they meet instead of standing there thinking. converse() uses it if the pair and mode match.
func prepare(a: String, b: String, mode := "meet") -> void:
	if active:
		return
	var seed := _seed(a, b)
	var max_lines: int = int(MAX_LINES.get(mode, 6))
	var target := _rng.randi_range(maxi(2, max_lines - 3), max_lines)
	var job := {"done": false}
	_prepared = {"between": [a, b], "mode": mode, "seed": seed, "target": target, "job": job, "t": _now()}
	_gen(a, b, [], seed, 1, target, mode, job)

## a speaks first, to b. opts: {mode: meet|ambient|event|combat, topic: {text, key}}. Awaitable; returns the
## finished entry {between, mode, topic, lines [{who, text, audio, gen_ms, gap_ms}], ended_by, provider}.
func converse(a: String, b: String, opts := {}) -> Dictionary:
	if active:
		return {"ok": false, "detail": "already talking"}
	var mode := String(opts.get("mode", "meet"))
	var ca: WorldCharacter = main.characters.get(a)
	var cb: WorldCharacter = main.characters.get(b)
	if ca == null or cb == null:
		return {"ok": false, "detail": "not here"}
	active = true
	var t_start := Time.get_ticks_msec()
	# a few words on the way / about what just happened: neither starts something new (walks off) mid-talk -
	# the 35-min proof had both event talks end after one question, the one asked walking away. Meet / stargaze
	# already hold them (MageTalk / Companionship).
	var held: Array = []
	if mode in ["event", "ambient"]:
		for w in [a, b]:
			var br = main.mage_brains.get(w)
			if br and not br.hold:
				br.hold = true
				held.append(br)
	var seed_a: Dictionary = opts.get("topic", {})
	var pre := _prepared
	_prepared = {}
	var use_pre: bool = not pre.is_empty() and pre.between == [a, b] and String(pre.mode) == mode and seed_a.is_empty() and _now() - float(pre.t) < 60.0
	if seed_a.is_empty():
		seed_a = pre.seed if use_pre else _seed(a, b)
	var seed_b := _seed(b, a)
	var max_lines: int = int(MAX_LINES.get(mode, 6))
	var target: int = int(pre.target) if use_pre else (max_lines if mode == "combat" else _rng.randi_range(maxi(2, max_lines - 3), max_lines))
	current = {"between": [a, b], "mode": mode, "topic": String(seed_a.get("text", "")), "lines": [], "started": _now()}
	conversation_started.emit(current)
	if mode != "stargaze" and mode != "combat":
		await Companionship.make_room(ca, cb)
	_watch_bodies(ca, cb)
	print("[dialogue] start %s -> %s (%s, %s remembers %d earlier talks)%s: %s" % [a, b, mode, a, (WorldState.mind(a).knowledge.get("talks:" + b, []) as Array).size(), " [opening line prepared on the way]" if use_pre else "", String(seed_a.get("text", "")).left(100)])
	var transcript: Array = []
	var spoken: Array = []
	var ended_by := ""
	var provider := ""
	# the first line
	var job: Dictionary = pre.job if use_pre else {"done": false}
	if not use_pre:
		_gen(a, b, transcript, seed_a, 1, target, mode, job)
	var speaker := a
	var listener := b
	var last_end_ms := t_start
	while true:
		while not job.done:
			await get_tree().process_frame
		var line: Dictionary = job.line
		provider = String(job.get("provider", provider))
		var text := VoiceService.clean(String(line.get("text", "")))
		if text.length() < 2:
			ended_by = "nothing to say"
			break
		transcript.append({"speaker": MagicSystem.display_name(speaker), "text": text})
		var is_last: bool = bool(line.get("end", false)) or transcript.size() >= target or transcript.size() >= max_lines
		# the listener has heard the words: her reply is written (and voiced) while this line is still playing
		var next := {"done": true}
		if not is_last:
			next = {"done": false}
			_gen(listener, speaker, transcript.duplicate(), seed_b if listener == b else seed_a, transcript.size() + 1, target, mode, next)
		# break off if they are no longer together, or a fight started
		if not _still_together(speaker, listener, mode):
			ended_by = "they moved apart"
			break
		print("[dialogue]   %s (gen %d ms, %s): %s" % [speaker, int(job.get("ms", 0)), String(job.get("provider", "")), text])
		await _wait_for_air()
		var gap := Time.get_ticks_msec() - last_end_ms
		var r: Dictionary = await _speak(speaker, listener, text, line)
		last_end_ms = Time.get_ticks_msec()
		var silence := gap + int(r.get("tts_ms", 0))   # from the end of the last line to this one's first sound
		print("[dialogue]   spoken %s audio=%s silence_before=%d ms (gap %d + tts %d) %s" % [speaker, str(r.get("audio", false)), silence, gap, int(r.get("tts_ms", 0)), String(r.get("error", ""))])
		spoken.append({"who": speaker, "text": text, "audio": bool(r.get("audio", false)), "gen_ms": int(job.get("ms", 0)), "gap_ms": gap, "silence_ms": gap + int(r.get("tts_ms", 0)),
			"tts_ms": int(r.get("tts_ms", 0)), "emotion": String(line.get("emotion", "")), "provider": String(job.get("provider", ""))})
		current.lines = spoken
		_remember_said(speaker, listener, text)
		if is_last:
			ended_by = speaker
			break
		job = next
		var s := speaker
		speaker = listener
		listener = s
		# a natural beat between turns
		await get_tree().create_timer(0.2 + _rng.randf() * 0.35).timeout
	# what was brought up is now known to the other (as being told, not as her own knowledge)
	if spoken.size() >= 2:
		var key := String(seed_a.get("key", ""))
		if key != "":
			Companionship.remember_told({"to": b, "topic": key, "text": String(seed_a.get("text", "")).left(160)}, a)
	var entry := {"between": [a, b], "mode": mode, "topic": String(seed_a.get("text", "")), "lines": spoken, "ended_by": ended_by,
		"provider": provider, "secs": snappedf((Time.get_ticks_msec() - t_start) / 1000.0, 0.1), "unix": int(_now()),
		"where": _where()}
	if spoken.size() >= 2:
		await _memories(a, b, entry)
	_last_end = _now()
	for w in [a, b]:
		WorldState.mind(w).knowledge["talked_last:" + _other(w)] = _last_end
	log.append(entry)
	if log.size() > 100:
		log.pop_front()
	current = {}
	active = false
	for br in held:
		br.hold = false
	print("[dialogue] bodies: closest %.2f m, root twitch %.1f mm/frame (mika-luna, while talking)" % [_body.min_d, _body.twitch_mm / maxf(_body.n, 1.0)])
	print("[dialogue] end %s -> %s (%s) %d lines, ended by %s: %s" % [a, b, mode, spoken.size(), ended_by, JSON.stringify(spoken.map(func(l): return "%s: %s" % [l.who, l.text]))])
	conversation_finished.emit(entry)
	return entry


func _still_together(sp: String, ls: String, mode: String) -> bool:
	var c1: WorldCharacter = main.characters.get(sp)
	var c2: WorldCharacter = main.characters.get(ls)
	if c1 == null or c2 == null or not c1.visible or not c2.visible:
		return false
	var limit := 7.0 if mode == "meet" else 16.0
	if c1.global_position.distance_to(c2.global_position) > limit:
		return false
	if mode != "combat":
		for w in [sp, ls]:
			var br = main.mage_brains.get(w)
			if br and br.threat != null:
				return false
	return true


## Never over the show's own speech (Mika-Live speaking for Mika) or a line already playing.
func _wait_for_air() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		var ll = main.get("live_link")
		# only a line actually playing: queued show speech waits for this conversation (LiveLink._play_next)
		var show_playing: bool = ll != null and ll._speaking and not active
		if not show_playing and not main.voice.busy():
			return
		await get_tree().process_frame


func _speak(sp: String, ls: String, text: String, line: Dictionary) -> Dictionary:
	var spc: WorldCharacter = main.characters.get(sp)
	var lsc: WorldCharacter = main.characters.get(ls)
	if spc and lsc:
		lsc.look_head_at(spc.global_position + Vector3(0, 1.5, 0))
		spc.look_head_at(lsc.global_position + Vector3(0, 1.5, 0))
	var emo := String(line.get("emotion", ""))
	if spc and spc.face and emo in EMOTIONS and emo != "neutral":
		spc.face.pulse(emo, 0.75, clampf(text.length() / 14.0, 1.2, 5.0))
	match String(line.get("gesture", "")):
		"wave":
			if spc:
				spc.play_gesture("waving", 0.3, 0.5)
		"point":
			if spc:
				spc.play_gesture("pointing", 0.3, 0.5)
		"nod":
			if spc and spc.head_posture:
				spc.head_posture.nod(0.12)
	var r: Dictionary = await main.voice.say(String(Progression.mages.get(sp, {}).get("voice", sp)), text)
	# the listener answers with her body too: a nod or a reaction to what she heard
	if lsc and lsc.head_posture and _rng.randf() < 0.45:
		lsc.head_posture.nod(0.1)
	return r


## Line n by `sp` to `ls` (async, fills job: {done, line, ms, provider}). Her facts only + the words so far.
func _gen(sp: String, ls: String, transcript: Array, seed: Dictionary, n: int, target: int, mode: String, job: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var me := MagicSystem.display_name(sp)
	var other := MagicSystem.display_name(ls)
	var situation: String = {"meet": "%s came over to talk" % (me if n % 2 == 1 else other), "ambient": "you are both nearby, each busy with your own thing, and talk in passing",
		"event": "something just happened", "combat": "you are in the middle of a fight",
		"stargaze": "you are lying side by side in the grass on Starfall Hill under the old tree at night, looking up at the stars; speak softly"}.get(mode, "")
	var sys := ("You are %s, %s. %s is your close friend; you live and study magic together in a fantasy world. You are face to face with her now (%s). Speak ONE short line out loud to her, as %s: usually 5 to 16 words, never more than %d. "
		+ "If %s just said something, respond to exactly that first (answer her question, react, agree, disagree or tease). "
		+ "Use only YOUR facts below and what was said in this conversation; never invent events, places, creatures or spells. "
		+ "Natural spoken English: no narration, no stage directions, no emojis, no em dashes, no quotes, do not start with her name every time. "
		+ "You may ask a question, joke, disagree, share news, suggest doing something together or offer help. Never repeat lines you said recently. "
		+ "This talk should last about %d lines; this is line %d. When it has run its course, close it naturally (a short goodbye or back to what you were doing) and set end to true. "
		+ "Reply as JSON {\"text\": string, \"end\": bool, \"emotion\": one of %s, \"gesture\": one of [\"\", \"nod\", \"wave\", \"point\"]}.") % [
		me, PERSONA.get(sp, "a young mage"), other, situation, me, 12 if mode == "combat" else 22, other, target, n, JSON.stringify(EMOTIONS)]
	var user := {"your_facts": _facts(sp, ls), "something_you_could_bring_up": String(seed.get("text", "")),
		"conversation_so_far": transcript, "lines_you_said_recently_do_not_repeat": WorldState.mind(sp).knowledge.get("said:" + ls, []).slice(-12)}
	var mock := {"text": _authored(sp, ls, seed, n, target, transcript), "end": n >= target, "emotion": "", "gesture": ""}
	var r: Dictionary = await main.llm.ask_json(sys, JSON.stringify(user), mock, "dialogue")
	var line: Dictionary = r.get("json", mock)
	if not line.get("text") is String or String(line.text).split(" ").size() > 34:
		line = mock
	job["line"] = line
	job["ms"] = Time.get_ticks_msec() - t0
	job["provider"] = String(r.get("provider", "mock"))
	# her voice starts synthesising now, while the line before it is still being spoken
	var text := VoiceService.clean(String(line.get("text", "")))
	if text.length() > 1:
		main.voice.prefetch(String(Progression.mages.get(sp, {}).get("voice", sp)), text)
	job["done"] = true


## Without a language model: her own authored lines (data/mages.json, data/companionship.json).
func _authored(sp: String, ls: String, seed: Dictionary, n: int, target: int, transcript: Array) -> String:
	var mt = main.mage_talk
	if n == 1:
		return mt._line(sp, "greet_again", ls)
	if n >= target:
		return mt._line(sp, "farewell", ls)
	return main.companionship.line(sp, "ack") if main.get("companionship") else ""


## What she could bring up, from HER OWN memory (Companionship.topics), as {text, key, say}.
func _seed(who: String, other: String) -> Dictionary:
	var t: Array = Companionship.topics(who, other) if main.get("companionship") else []
	var on := MagicSystem.display_name(other)
	for c in t:
		var f: Dictionary = c.get("fill", {})
		match String(c.kind):
			"clue": return {"text": "a clue you found: %s" % String(f.get("hint", f.get("topic", ""))), "key": String(c.topic)}
			"creature": return {"text": "you fought a %s" % String(f.get("creature", "")), "key": String(c.topic)}
			"book": return {"text": "you read %s" % String(f.get("book", "")), "key": String(c.topic)}
			"place": return {"text": "a place you looked at: %s" % String(f.get("place", "")), "key": String(c.topic)}
			"ask_creature": return {"text": "ask %s about the %s she fought (you heard she did)" % [on, String(f.get("creature", ""))], "key": ""}
			"ask_clue": return {"text": "ask %s what she knows about %s" % [on, String(f.get("topic", ""))], "key": ""}
			"worry": return {"text": "you had to back away from a %s and it still bothers you" % String(f.get("creature", "")), "key": String(c.topic)}
			"triumph": return {"text": "you finally beat the %s" % String(f.get("creature", "")), "key": String(c.topic)}
			"reminisce": return {"text": "a memory you share with %s: %s" % [on, String(f.get("memory", ""))], "key": ""}
	var goal := ""
	if who == "mika" and main.get("story"):
		goal = String(main.story.objective())
	return {"text": ("your goal right now: %s" % goal) if goal != "" else "ask %s what she is up to, or say what you are doing" % on, "key": ""}


func _where() -> String:
	var sf: StarfallPlace = StarfallPlace.instance
	if sf and is_instance_valid(sf) and main.characters.has("mika") and sf.near((main.characters["mika"] as Node3D).global_position):
		return "Starfall Hill, by the old tree, in the Arcane Sanctuary"
	var area := String(main.streaming.current_id) if main.get("streaming") else ""
	return String(WorldState.areas.get(area, {}).get("name", area.replace("_", " ")))


## Her own facts only (never the other's knowledge).
func _facts(who: String, other: String) -> Dictionary:
	var m := WorldState.mind(who)
	var br = main.mage_brains.get(who)
	var recent: Array = []
	for i in range(m.activity_log.size() - 1, maxi(-1, m.activity_log.size() - 8), -1):
		recent.append(String(m.activity_log[i].get("activity", {}).get("label", "")))
	var spells: Array = []
	if main.get("magic"):
		for s in main.magic.known_spells(who):
			if s.castable:
				spells.append(String(s.name))
	var told: Array = []
	for k in m.knowledge:
		if String(k).begins_with("told:%s:" % other):
			told.append(String(m.knowledge[k]))
	var rel := MageTalk.rel(who, other)
	var fx := {"name": MagicSystem.display_name(who), "level": m.level(), "title": Progression.title(m.level()), "rank": WorldState.mage_rank(who),
		"doing_now": String(br.current.get("label", "taking a breather")) if br else "", "where": _where(), "time": WorldState.time_phrase(),
		"weather": main.weather.kind() if main.get("weather") else "", "stamina": "low" if m.vigor < 0.45 else "fine",
		"things_you_did_lately": recent, "spells_you_can_cast": spells.slice(0, 8),
		"your_memories_of_talking_with_" + MagicSystem.display_name(other): (m.knowledge.get("talks:" + other, []) as Array).slice(-5).map(func(t): return String(t.get("gist", ""))),
		"what_%s_has_told_you" % MagicSystem.display_name(other): told.slice(-5),
		"you_and_her": {"talks_so_far": int(rel.get("meetings", 0)), "camaraderie": snappedf(float(rel.get("camaraderie", 0.0)), 0.1), "rivalry": snappedf(float(rel.get("rivalry", 0.0)), 0.1)}}
	if who == "mika" and main.get("story"):
		fx["your_goal"] = String(main.story.objective())
	return fx


func _remember_said(who: String, other: String, text: String) -> void:
	var k := "said:" + other
	var arr: Array = WorldState.mind(who).knowledge.get(k, [])
	arr.append(text.left(140))
	WorldState.mind(who).knowledge[k] = arr.slice(-20)


## Each keeps her own one-line memory of the talk (what was said, decided or learned), saved with her mind.
func _memories(a: String, b: String, entry: Dictionary) -> void:
	var lines: Array = entry.lines.map(func(l): return {"speaker": MagicSystem.display_name(String(l.who)), "text": String(l.text)})
	var na := MagicSystem.display_name(a)
	var nb := MagicSystem.display_name(b)
	var fallback := {a: "I talked with %s at %s." % [nb, entry.where], b: "I talked with %s at %s." % [na, entry.where]}
	var sys := "Two young mages, %s and %s, just talked. Write what EACH remembers of it, in her own first person: one short sentence each (what was said, decided, promised or learned), max 22 words. JSON {\"%s\": string, \"%s\": string}." % [na, nb, a, b]
	var r: Dictionary = await main.llm.ask_json(sys, JSON.stringify({"where": entry.where, "conversation": lines}), fallback, "dialogue")
	for w in [a, b]:
		var gist := String(r.json.get(w, fallback[w]))
		if gist.length() < 4:
			gist = String(fallback[w])
		var k := "talks:" + _other(w)
		var arr: Array = WorldState.mind(w).knowledge.get(k, [])
		arr.append({"unix": entry.unix, "gist": gist.left(200), "where": entry.where, "mode": entry.mode, "started_by": a})
		WorldState.mind(w).knowledge[k] = arr.slice(-12)
	entry["memories"] = {a: WorldState.mind(a).knowledge["talks:" + b][-1].gist, b: WorldState.mind(b).knowledge["talks:" + a][-1].gist}


func describe() -> Dictionary:
	return {"active": active, "current": current, "conversations": log.size(), "pending": pending}
