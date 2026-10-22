extends RefCounted
## --mktest=villagerhelp: a villager's request start to end with the real brain steps. In the village: Wenna asks for two
## moonpetals (the chat topic), Mika says yes; the open request makes a moonpetal worth more to her; with two in her bag
## the "bring it" option appears, she walks to Wenna, hands them over, Wenna thanks her; XP paid once.


static func run(t) -> void:
	var main = t.main
	main.travel.cancel("villager help test")
	await t._hold_all()
	main.travel.cancel("villager help test")
	if main.streaming.current_id != "village":
		await main.streaming.travel("village", main.characters["mika"])
	t._check(main.streaming.current_id == "village", "in the village")
	if main.day_night:
		main.day_night.set_override(false)
	main.place_curiosity.set_process(false)
	await t._wait(4.0)
	var b = main.mage_brains["mika"]
	var m: MageMind = WorldState.mind("mika")
	for k in m.knowledge.keys():
		if String(k).begins_with("request") or String(k).begins_with("talked:wenna") or String(k).begins_with("helped_resident:"):
			m.knowledge.erase(k)
	m.knowledge["met_resident:wenna"] = 1
	var rr = main.town.residents.get("wenna")
	t._check(rr != null and is_instance_valid(rr), "Wenna lives here")
	if rr == null:
		return
	# late morning, Wenna out at her garden or stall; Mika a few steps from her (the first run started at dawn with
	# Wenna indoors, so the brain had no one to offer)
	FightDirector.set_hour(main, 11.0)
	rr.place_now()                         # (at her stall now, as when the village loads at that hour)
	var tw := Time.get_ticks_msec()
	while (not rr.visible or rr.state in ["walking", "inside"]) and Time.get_ticks_msec() - tw < 90000:
		await t._wait(1.0)
	print("[villagerhelp] Wenna %s, visible %s, at %s" % [String(rr.state), str(rr.visible), str(rr.global_position.snappedf(0.1))])
	var mc: WorldCharacter = main.characters["mika"]
	if main.teleport_guard:
		main.teleport_guard.allow(mc)
	mc.global_position = main.world.free_spot(rr.global_position + (mc.global_position - rr.global_position).normalized() * 3.0) if main.world.has_method("free_spot") else rr.global_position + Vector3(3, 0, 0)
	await t._wait(1.0)
	# 1. she asks (the brain's chat option carries her request first)
	var opts: Array = b.options()
	var chat: Array = opts.filter(func(o): return String(o.get("kind", "")) == "chat" and String(o.get("resident", "")) == "wenna")
	t._check(not chat.is_empty() and String(chat[0].topic.id).begins_with("request:"), "Wenna's chat option is her request", chat.map(func(o): return o.topic.id))
	if chat.is_empty():
		return
	var r1: Dictionary = await b._chat(chat[0])
	print("[villagerhelp] asked: %s" % str(r1))
	t._check(VillagerRequests.state(m, "wenna_moonpetal") == "open", "the request is open in her mind")
	# 2. the promise pulls: a moonpetal is worth more now
	var pull: Array = VillagerRequests.pull(m, {"kind": "gather", "item": "moonpetal"})
	t._check(float(pull[0]) > 0.0, "a moonpetal matters more now (%s)" % str(pull))
	# 3. she has two (as if gathered at home)
	WorldState.record_activity({"id": "collect:moonpetal", "verb": "gather", "label": "Picked a moonpetal"}, {"items": {"moonpetal": 2}}, "mika")
	var xp0: float = float(m.progress.get("xp", 0.0)) + float(m.progress.get("xp_bank", 0.0))
	var helps: Array = VillagerRequests.help_options(b)
	t._check(helps.size() == 1 and String(helps[0].request) == "wenna_moonpetal", "the 'bring it to her' option appears", helps)
	if helps.is_empty():
		return
	var r2: Dictionary = await VillagerRequests.help(b, helps[0])
	await t._wait(0.5)
	var gained: float = float(m.progress.get("xp", 0.0)) + float(m.progress.get("xp_bank", 0.0)) - xp0
	print("[villagerhelp] helped: %s, xp gained %.1f (paid or banked)" % [str(r2), gained])
	t._check(bool(r2.get("ok", false)), "she brought them to Wenna (%s)" % String(r2.get("detail", "")))
	t._check(VillagerRequests.state(m, "wenna_moonpetal") == "done", "the request is done")
	t._check(int(m.inventory.get("moonpetal", 0)) == 0, "the two moonpetals left her bag")
	t._check(gained >= 41.9, "42 XP for the help, paid or banked by the pacing (%.1f)" % gained)
	t._check(VillagerRequests.help_options(b).is_empty() and VillagerRequests.ask_topic(m, "wenna").is_empty(), "nothing asked or paid twice")
