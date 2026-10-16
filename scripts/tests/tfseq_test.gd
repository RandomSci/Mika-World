extends Node
## --tfseq=<who>:<level>[:skip] - the test command: trigger any character at any form right now (preview: changes no
## saved progress and reverts). Options: --tfseq-shots=<dir> (a screenshot at every beat), --tfseq-prev=<stage id>
## (start in that look; default: the look before the form), --tfseq-skip-at=<s> (a viewer types "skip" after s
## seconds; the form counts as seen before), --tfseq-quit (quit when done). Record a video with Movie Maker:
## --write-movie <file>.avi --fixed-fps 30.

var main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var arg := String(RenderProfile.options.get("tfseq", "mika:50"))
	var who := arg.get_slice(":", 0)
	var level := int(arg.get_slice(":", 1))
	var mode := "skip" if arg.get_slice_count(":") > 2 and arg.get_slice(":", 2) == "skip" else "full"
	if not main.characters.has(who):
		push_error("[tfseq] no character %s in this scene (pass --luna for Luna)" % who)
		get_tree().quit(1)
		return
	main.player.enabled = false
	main.hud.visible = false
	main.prompt.visible = false
	for k in ["overlay_ui", "rank_tag"]:
		var n = main.get(k)
		if n:
			n.visible = false
	for k in ["brain", "duel", "companionship", "attention", "impacts", "mage_talk", "performance"]:
		var n2: Node = main.get(k)
		if n2:
			n2.process_mode = Node.PROCESS_MODE_DISABLED
	var m: WorldCharacter = main.characters[who]
	# start in the look before the form
	var prev := String(RenderProfile.options.get("tfseq-prev", ""))
	if prev == "":
		var below := TransformationSequence.target_avatar(who, level - 1)
		prev = String(below.get("stage", ""))
	if prev != "":
		AppearanceRegistry.preview(who, prev)
		m.swap_avatar(AppearanceRegistry.avatar_for(who))
		AppearanceRegistry.preview(who, "")
	var skip_at := float(RenderProfile.options.get("tfseq-skip-at", "-1"))
	if skip_at > 0.0:
		var sn: Dictionary = WorldState.mind(who).progress.get("tfseq_seen", {})
		sn[str(level)] = true
		WorldState.mind(who).progress["tfseq_seen"] = sn
		get_tree().create_timer(4.0 + skip_at).timeout.connect(func(): print("[tfseq] skip -> ", main.transformer.sequence.request_skip("test viewer")))
	await get_tree().create_timer(4.0).timeout
	print("[tfseq] start %s L%d %s" % [who, level, mode])
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await main.transformer.play(who, mode, true, level)
	print("[tfseq] result ", JSON.stringify(res))
	print("[tfseq] seconds %.1f, beats %s" % [(Time.get_ticks_msec() - t0) / 1000.0, JSON.stringify(main.transformer.sequence.log.slice(0, 40))])
	await get_tree().create_timer(3.0).timeout
	print("[tfseq] done")
	if RenderProfile.options.has("tfseq-quit") or RenderProfile.options.has("tfseq-shots"):
		get_tree().quit()
