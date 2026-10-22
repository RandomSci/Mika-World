extends RefCounted
## The spell duel for Selwyn's approval (22 Oct): Mika and Luna settle an argument with magic, 45 to 60 s, nobody
## hurt, no close combat, no swords, they talk, whole-body shots only. Record with --movie (30 fps). Nothing from this
## goes near the stream until he has seen the full video and said yes.
## Options: --fight-seed=N, --fight-hour=H (default 17.6), --duel-reason=<one of REASONS> (default: the first).
## Checks: 45 to 60 s; no blow ever lands; only magic, dodge and jump clips (no sword or kick clip); every shot a
## whole-body kind; both spoke during it; the magic really spawned; no T-pose; they stay in the clearing.

## Why they duel (the opening lines) and how it ends (the closing lines). A reason, never out of nowhere.
const REASONS := {
	"heartstone": {
		"open": [["luna", "The third beat is a warning, Mika. We leave the Heartstone alone."], ["mika", "It's an invitation! You just don't want me to be right."],
			["luna", "Fine. The mages' way, then."]],
		"close": [["mika", "Okay, okay. A draw. We read the inscription together."], ["luna", "Together. And slowly."], ["mika", "Deal. But I'm still right."]]},
	"last_cookie": {
		"open": [["mika", "That was my moon cake, Luna."], ["luna", "Your name wasn't on it. Prove you deserve it."], ["mika", "Oh, you're on!"]],
		"close": [["luna", "Nobody won. So we split the next one."], ["mika", "Half and half. Promise?"], ["luna", "Promise. Mostly."]]},
}

const ALLOWED_SHOTS := ["establish", "wide", "wide_low", "profile", "orbit", "overhead", "track", "impact", "two_mid"]


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("spell duel test")         # (a brain may set off on a day trip in the first second)
	await t._hold_all()
	await t._force_luna_l1()
	for w in main.mage_brains:
		main.mage_brains[w].set_enabled(false)
	main.travel.cancel("spell duel test")
	# in the sanctuary's training clearing (the first render ran in the Whispering Woods, among the trees)
	if main.streaming.current_id != "sanctuary":
		await main.streaming.travel("sanctuary", main.characters["mika"])
	main.mage_talk.dialogue.set_process(false)    # (no chat from before the duel carries into it)
	main.place_curiosity.set_process(false)       # (nor a remark about the place: one slipped into the second render)
	main.director.enabled = false
	main.spawner.enabled = false
	if main.performance:
		main.performance.set_process(false)
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	for id in main.characters:
		if not (id in ["mika", "luna"]):
			(main.characters[id] as Node3D).visible = false
	FightDirector.set_hour(main, float(RenderProfile.options.get("fight-hour", "17.6")))
	if main.get("weather") and main.weather:
		main.weather.set_weather("clear", 48.0)
		main.weather.cloud = 0.0
		main.weather.rain = 0.0
	await t._wait(2.5)
	if main.get("voice") and main.voice:
		main.voice.stop()
	await t._wait(0.3)
	var reason_id := String(RenderProfile.options.get("duel-reason", "heartstone"))
	var reason: Dictionary = REASONS.get(reason_id, REASONS.heartstone)
	var d := FightDirector.new()
	main.add_child(d)
	d.setup(main, "spell", {"seed": int(RenderProfile.options.get("fight-seed", "2210")), "open_lines": reason.open, "close_lines": reason.close})
	var watch := {"frames": 0, "overlap": 0, "min_gap": 99.0, "tpose": 0, "out": 0, "fx_peak": 0}
	var watcher := func():
		while not d.done:
			await t.get_tree().process_frame
			watch.frames += 1
			var gap := d._flat(d.chest("mika") - d.chest("luna")).length()
			watch.min_gap = minf(float(watch.min_gap), gap)
			if gap < 0.42:
				watch.overlap += 1
			for id in ["mika", "luna"]:
				if d._flat(d.pos(id) - d.center).length() > d.arena_r + 0.05:
					watch.out += 1
				if _tpose(d, id):
					watch.tpose += 1
			watch.fx_peak = maxi(int(watch.fx_peak), d.fx.get_child_count())
	watcher.call()
	var v0: int = (main.voice.log as Array).size() if main.get("voice") and main.voice else 0
	var r: Dictionary = await d.run()
	t.report["fight"] = r
	t.report["plan"] = d.plan
	t.report["cuts"] = d.cam_log
	print("[spellduel] reason %s, length %.1f s, plan %s" % [reason_id, float(r.fight_s), JSON.stringify(d.plan.map(func(e): return "%s %s>%s %s" % [e.move, e.get("att", ""), e.get("def", ""), e.get("outcome", "")]))])
	var spoken := []
	if main.get("voice") and main.voice:
		for e in (main.voice.log as Array).slice(v0):
			spoken.append("%s: %s" % [String(e.get("speaker", e.get("voice", "?"))), String(e.get("text", ""))])
	print("[spellduel] dialogue %s" % JSON.stringify(spoken))
	var clips := {}
	for id in ["mika", "luna"]:
		for e in (d.F[id].deck as FightDeck).log:
			clips[String(e[0])] = true
	print("[spellduel] clips %s" % str(clips.keys()))
	var kinds := {}
	for c in d.cam_log:
		kinds[String(c[2])] = true
	print("[spellduel] shots %s (%d cuts)" % [str(kinds.keys()), d.cam_log.size()])
	t._check(float(r.fight_s) >= 45.0 and float(r.fight_s) <= 62.0, "45 to 60 s long (%.1f s)" % float(r.fight_s))
	t._check(int(r.hits.mika) + int(r.hits.luna) == 0, "no blow ever lands", r.hits)
	t._check(not clips.keys().any(func(k): return String(k).begins_with("sword:") or String(k).contains("kick")), "no sword or kick clip", clips.keys())
	t._check(kinds.keys().all(func(k): return String(k) in ALLOWED_SHOTS), "every shot whole body", kinds.keys())
	t._check(spoken.size() >= 6, "they talk through it (%d lines)" % spoken.size(), spoken)
	t._check(int(watch.fx_peak) >= 12, "the magic really spawned (peak %d effect nodes)" % int(watch.fx_peak))
	t._check(int(watch.tpose) == 0, "no T-pose frames (%d)" % int(watch.tpose))
	t._check(int(watch.out) == 0, "they stayed inside the clearing")
	t._check(float(watch.min_gap) >= 1.8, "no close combat: always at least 1.8 m apart (closest %.2f m)" % float(watch.min_gap))
	t._check(main.streaming.current_id == "sanctuary", "in the sanctuary's training clearing")


static func _tpose(d: FightDirector, id: String) -> bool:
	var n := 0
	for s in ["Left", "Right"]:
		var u := d.bone(id, s + "UpperArm")
		var l := d.bone(id, s + "LowerArm")
		var h := d.bone(id, s + "Hand")
		var a := (l - u).normalized()
		var b := (h - l).normalized()
		if absf(a.y) < 0.2 and a.dot(b) > 0.97:
			n += 1
	return n == 2
