extends RefCounted
## The action player in a fight (Selwyn: "one 30 second fight using the same action player"): the melee exchange
## (MeleeSim, its camera director) run for 30 s, where every strike the sim picks and every cast goes through each
## girl's ActionPlayer (a strike plays its catalog entry's procedural move, a cast its gesture through the
## GestureDirector), then counts what the players played. Marks "[action] {...}" per action and "[fightdemo] ...".

static func run(t) -> void:
	if not RenderProfile.options.has("fight-length"):
		RenderProfile.options["fight-length"] = "30"
	await load("res://scripts/tests/ext/melee_exchange.gd").run(t)
	var rows := []
	for id in ["mika", "luna"]:
		var c: WorldCharacter = t.main.characters[id]
		var p := c.get_node_or_null("ActionPlayer") as ActionPlayer
		if p:
			rows += p.log
	var by := {}
	for r in rows:
		var k := String(r.get("how", "?"))
		by[k] = int(by.get(k, 0)) + 1
	print("[fightdemo] %d actions through the action players %s" % [rows.size(), JSON.stringify(by)])
	t._check(rows.size() >= 12, "the fight's actions went through the action player (%d)" % rows.size())
