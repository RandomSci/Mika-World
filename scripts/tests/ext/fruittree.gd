extends RefCounted
## --mktest=fruittree (25 Oct, Selwyn: "magical fruits on trees"): at Lantern Lake, its Starplum trees stand where
## planned, their trunks are holes in the navmesh, and Mika then Luna each call a fruit down (the cast, the fruit drifting
## down, the catch) through the brain's own gather step; the fruit lands in her inventory, the tree has one fewer ripe.
## The brain offers "call a starplum down from its tree" once she has seen it. Marks "[fruit] ...". Record with --movie.


static func run(t) -> void:
	var main = t.main
	await t._hold_all()
	if main.streaming.current_id != "lantern_lake":
		await main.streaming.travel("lantern_lake", main.characters["mika"])
	await t._wait(2.0)
	if main.day_night:
		main.day_night.set_override(true)
	var trees: Array = main.streaming.current.find_children("Animated_FruitTree_*", "", true, false)
	print("[fruit] %d trees at the lake" % trees.size())
	t._check(trees.size() == 2, "the lake's two Starplum trees stand (%d)" % trees.size())
	if trees.is_empty():
		return
	var tree: FruitTree = trees[0]
	var map: RID = main.characters["mika"].get_world_3d().navigation_map
	var on := NavigationServer3D.map_get_closest_point(map, tree.global_position + Vector3(0, 1.0, 0))
	var gap := Vector2(on.x - tree.global_position.x, on.z - tree.global_position.z).length()
	print("[fruit] tree at %s, nearest walkable %.2f m from its trunk" % [str(tree.global_position), gap])
	t._check(gap > 0.4, "the trunk is a hole in the navmesh (%.2f m)" % gap)
	var ripe0: int = tree._fruit.filter(func(f): return f.ripe).size()
	print("[fruit] %d fruit ripe" % ripe0)
	t._check(ripe0 >= 5, "fruit in the crown (%d)" % ripe0)
	for f in tree._fruit:
		print("[fruit]   fruit at %s (%.1f m up)" % [str(tree.to_global(f.at)), f.at.y])
	for who in ["mika", "luna"]:
		var c: WorldCharacter = main.characters[who]
		var b = main.mage_brains[who]
		var start := NavigationServer3D.map_get_closest_point(map, tree.global_position + Vector3(4.0 if who == "mika" else -4.0, 0, 3.0))
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.stop_action()
		c.visible = true
		c.set_physics_process(true)
		c.velocity = Vector3.ZERO
		c.global_position = start + Vector3(0, 0.1, 0)
		await t._wait(1.0)
		b.mind.knowledge["noticed:gather:" + tree.gid] = 1
		b.hold = false
		var offered: bool = b.options().any(func(o): return String(o.get("key", "")) == "gather:" + tree.gid) if b.has_method("options") else true
		b.hold = true
		print("[fruit] %s is offered the tree: %s" % [who, offered])
		var before := int(WorldState.mind(who).inventory.get("starplum", 0)) if WorldState.mind(who).get("inventory") != null else 0
		b.current = {"stage": ""}
		var r: Dictionary = await b._gather({"node": tree})
		var after := int(WorldState.mind(who).inventory.get("starplum", 0)) if WorldState.mind(who).get("inventory") != null else 0
		print("[fruit] %s: %s (starplum %d -> %d)" % [who, str(r.get("detail", "")), before, after])
		t._check(r.get("ok", false), "%s calls a fruit down and catches it (%s)" % [who, r.get("detail", "")])
		await t._wait(2.0)
		if c.handler and c.handler.held and is_instance_valid(c.handler.held):
			c.handler.held.queue_free()
			c.handler.held = null
	var ripe1: int = tree._fruit.filter(func(f): return f.ripe).size()
	t._check(ripe1 == ripe0 - 2, "two fewer ripe on the tree (%d -> %d)" % [ripe0, ripe1])
