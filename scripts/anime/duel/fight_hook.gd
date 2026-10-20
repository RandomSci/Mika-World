class_name FightHook
extends RefCounted
## Fights on the stream (2026-10-19): chat votes start a duel or a training bout. Called from LiveLink (two lines):
##  - FightHook.chat(main, m) for every chat message the show forwards: "!duel" / "!spar" (also "!fight", "!train")
##    count as votes, one per viewer, inside a 2-minute window; VOTES_NEEDED votes start that fight when the stage is
##    free (no fight running, the cooldown over, Mika not dancing or in a cinematic);
##  - FightHook.act(main, action, args) for the show's own actions: "duel_fight", "training_fight", or "fight_vote"
##    ({mode, votes}: a tally the server already counted).
## The fight itself is FightDirector at the sanctuary's training clearing; afterwards the camera and the world go back
## to normal and the mages' own planners resume.

const VOTES_NEEDED := 3
const WINDOW_MS := 120000
const COOLDOWN_MS := 600000
const WORDS := {"!duel": "duel", "!fight": "duel", "!spar": "training", "!train": "training", "!training": "training"}

static var votes := {"duel": {}, "training": {}}     # mode -> {viewer: ticks ms}
static var running := false
static var last_end := -10000000
static var log: Array = []


## A chat message: a vote if it carries one of the words. Returns the mode voted for ("" = not a vote).
static func chat(main: Node, m: Dictionary) -> String:
	var text := String(m.get("message", m.get("text", ""))).strip_edges().to_lower()
	var who := String(m.get("author", m.get("user", m.get("name", "viewer"))))
	var mode := ""
	for w in WORDS:
		if text.begins_with(w):
			mode = WORDS[w]
			break
	if mode == "":
		return ""
	var now := Time.get_ticks_msec()
	for k in votes:
		var vk: Dictionary = votes[k]
		for v in vk.keys():
			if now - int(vk[v]) > WINDOW_MS:
				vk.erase(v)
	(votes[mode] as Dictionary)[who] = now
	log.append({"t": now, "who": who, "mode": mode, "count": (votes[mode] as Dictionary).size()})
	if (votes[mode] as Dictionary).size() >= VOTES_NEEDED and can_start(main):
		(votes[mode] as Dictionary).clear()
		start(main, mode)
	return mode


static func can_start(main: Node) -> bool:
	if running or Time.get_ticks_msec() - last_end < COOLDOWN_MS:
		return false
	if main.get("performance") and main.performance and main.performance.busy():
		return false
	return main.characters.has("mika") and main.characters.has("luna")


## The show asked for a fight (or reports a vote tally). {ok, value?, reason?}
static func act(main: Node, action: String, args: Dictionary) -> Dictionary:
	var mode := "duel"
	match action:
		"training_fight":
			mode = "training"
		"fight_vote":
			mode = "training" if String(args.get("mode", "duel")) in ["training", "spar", "train"] else "duel"
			if int(args.get("votes", 0)) < VOTES_NEEDED:
				return {"ok": true, "value": {"started": false, "votes": int(args.get("votes", 0)), "needed": VOTES_NEEDED}}
	if not can_start(main):
		return {"ok": false, "reason": "fight_not_possible_now"}
	var r: Dictionary = await start(main, mode)
	return {"ok": not r.is_empty(), "value": r}


## Runs one fight start to finish and puts everything back. Returns the fight's result.
static func start(main: Node, mode: String) -> Dictionary:
	if running:
		return {}
	running = true
	var tree := main.get_tree()
	# the mages finish (or drop) what they are doing; their planners wait
	for w in main.mage_brains:
		var b = main.mage_brains[w]
		b.hold = true
		if b.has_method("interrupt"):
			b.interrupt("a fight on the training ground")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and main.mage_brains.values().any(func(b): return not b.current.is_empty()):
		await tree.process_frame
	if main.streaming.current_id != "sanctuary":
		await main.streaming.travel("sanctuary", main.characters["mika"], true)
	if main.get("performance") and main.performance and main.performance.busy():
		main.performance.interrupt("a fight on the training ground")
	await tree.create_timer(1.5).timeout
	if main.get("voice") and main.voice:
		main.voice.stop()
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, mode, {"seed": Time.get_ticks_msec() % 100000})
	var r: Dictionary = await d.run()
	await tree.create_timer(1.0).timeout
	d.teardown()
	d.queue_free()
	for w in main.mage_brains:
		main.mage_brains[w].hold = false
	running = false
	last_end = Time.get_ticks_msec()
	log.append({"t": last_end, "fight": mode, "winner": r.get("winner", ""), "award": r.get("award", {})})
	return r
