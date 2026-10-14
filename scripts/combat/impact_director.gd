class_name ImpactDirector
extends Node
## Magic collisions with real consequences (V3 continuation - the developer: "An attack's area of effect should
## consider actual location, distance, collision, shielding and attack strength. Characters inside a blast radius
## should not remain unaffected simply because they are companions ... Attacks must also trigger meaningful AI
## reactions, including recognizing danger, changing tactics, retreating, defending or helping a companion. Do not
## make every character react identically.")
##
## blast(at, strength, radius, opts) - for every visible mage within `radius`:
##   severity = strength * (1 - d / radius) ^ 1.3                  distance from the centre (to her chest)
##            * 0.35 if solid world geometry stands between them    cover
##            * 0.25 if her ward faces it (the ward takes a charge) shielding
##            * 0.6  if she braced for it in the last moment        guarding
##            / her balance (data/mages.json "body")
## then BodyReaction plays the result (notice / flinch / stagger / down). Friendly fire is NON-LETHAL: it costs
## vigor (never below 8 %), never more. Afterwards, everyone near acts on it in her own way:
##   * a companion who sees her friend go down runs to her, kneels beside her, and offers a hand as she gets up;
##   * "protective" (Mika): once up she faces the danger, ready (combat stance), and says so;
##   * "evasive" (Luna): once up she backs well out of its reach before she turns to watch it;
##   * both remember it ("struck_by:<source>" in their own minds: what hurt them, how often, where).

signal blasted(at: Vector3, results: Array)

var main: Node
var log: Array = []
var aftermath_log: Array = []
var said: Array = []
var lines := {}
var _helping := {}            # helper id -> fallen id
var _busy := {}               # who is in an aftermath behaviour
var callouts: Array = []      # warnings one mage shouted to the other (who, to, kind, why)
var _callout_cd := {}         # warner -> time she may shout again
var _scan_t := 0.0


func setup(m: Node) -> void:
	main = m
	var f := FileAccess.open("res://data/impacts.json", FileAccess.READ)
	if f:
		lines = JSON.parse_string(f.get_as_text()).get("lines", {})
	for who in main.characters:
		_hook(main.characters[who])


func _hook(c: WorldCharacter) -> void:
	if c.reaction == null or c.reaction.reacted.is_connected(_on_reacted):
		return
	c.reaction.reacted.connect(_on_reacted.bind(c))
	c.reaction.recovered.connect(_on_recovered.bind(c))


## Companions watch each other's backs (V3 Part 1.4): when a blow is coming at one mage that SHE cannot see (behind
## her, out of sight) - or a heavy one - and her friend, clear of it herself, does see it, the friend shouts. The
## warned mage now knows it is coming (AttackHazard.warned -> perceived), so her own tactics can dodge it.
func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0 or main == null or main.get("world") == null:
		return
	_scan_t = 0.2
	var now := Time.get_ticks_msec() / 1000.0
	for h in AttackHazard.active(main.world):
		var hz := h as AttackHazard
		if hz == null or hz.done or hz.owner_mage != null:
			continue
		for who in main.characters:
			var m: WorldCharacter = main.characters[who]
			if m == null or not is_instance_valid(m) or not m.visible or m in hz.warned or not hz.threatens(m.global_position):
				continue
			var blind := not hz.perceived_by(m)
			if not blind and not hz.heavy:
				continue
			for w in main.characters:
				var o: WorldCharacter = main.characters[w]
				if o == m or o == null or not is_instance_valid(o) or not o.visible or now < float(_callout_cd.get(w, 0.0)):
					continue
				if (o.reaction and o.reaction.active) or hz.threatens(o.global_position) or not hz.perceived_by(o):
					continue
				if o.global_position.distance_to(m.global_position) > 24.0 or hz.time_to(m.global_position) < 0.35:
					continue
				hz.warned.append(m)
				_callout_cd[w] = now + 9.0
				var key := "warn_blind" if blind else "warn_heavy"
				callouts.append({"who": w, "to": who, "key": key, "kind": hz.kind, "t": snappedf(now, 0.1)})
				if callouts.size() > 40:
					callouts.pop_front()
				o.look_head_at(m.global_position + Vector3(0, 1.4, 0))
				if o.face:
					o.face.pulse("surprised", 0.7, 0.4)
				_say(w, key)
				break


## An area impact. opts: source (String), kind (String), friendly (bool, default true), exclude (Array of ids).
func blast(at: Vector3, strength: float, radius: float, opts := {}) -> Array:
	var results: Array = []
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		if c == null or not is_instance_valid(c) or not c.visible or who in opts.get("exclude", []):
			continue
		_hook(c)
		var chest := c.global_position + Vector3(0, 1.1, 0)
		var d := chest.distance_to(at)
		if d > radius:
			continue
		var ctx := {"source": String(opts.get("source", "")), "kind": String(opts.get("kind", "blast")), "dist": snappedf(d, 0.01)}
		var sev := strength * pow(1.0 - d / radius, 1.3)
		if _blocked(at, chest, c):
			sev *= 0.35
			ctx["cover"] = true
		var w := Ward.active_for(c)
		if w and w.covers(at):
			sev *= 0.25
			ctx["warded"] = w.kind
		if c.reaction.guarding():
			sev *= 0.6
			ctx["guarded"] = true
		sev /= maxf(float(c.reaction.body.get("balance", 1.0)), 0.3)
		var r := c.reaction.receive(at, sev, ctx)
		if bool(opts.get("friendly", true)) and r.get("tier", "notice") != "notice":
			var m := WorldState.mind(who)
			m.vigor = maxf(0.08, m.vigor - sev * 0.12)
		r["who"] = who
		results.append(r)
		if r.get("tier", "notice") != "notice":
			var src := String(opts.get("source", "unknown"))
			var mind := WorldState.mind(who)
			var k := "struck_by:" + src
			mind.knowledge[k] = int(mind.knowledge.get(k, 0)) + 1
			mind.knowledge["struck_last"] = {"source": src, "tier": r.tier, "area": main.streaming.current_id if main.get("streaming") else "",
				"unix": int(Time.get_unix_time_from_system())}
	log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "at": [snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)],
		"strength": strength, "radius": radius, "results": results})
	if log.size() > 60:
		log.pop_front()
	blasted.emit(at, results)
	return results


func _blocked(a: Vector3, b: Vector3, c: WorldCharacter) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 0.3, 0), b, 1)
	q.exclude = [c.get_rid()]
	var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and (hit.position as Vector3).distance_to(b) > 0.5


func _say(who: String, key: String, delay := 0.0) -> void:
	var pool: Array = lines.get(who, {}).get(key, [])
	if pool.is_empty() or main.get("voice") == null:
		return
	var line := String(pool[randi() % pool.size()])
	said.append({"who": who, "key": key, "line": line})
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if main.get("voice"):
		main.voice.say(who, line, {"mood": "urgent" if key.begins_with("warn_") else "concerned", "max_wait": 1.2, "priority": 1 if key.begins_with("warn_") else 0})


# ------------------------------------------------------------------ aftermath behaviour
func _on_reacted(info: Dictionary, c: WorldCharacter) -> void:
	_hold(c.character_id, true)
	if String(info.get("tier", "")) != "down":
		return
	# a companion who sees her go down comes to help (if she is up herself and close enough to see it)
	for who in main.characters:
		var h: WorldCharacter = main.characters[who]
		if h == c or not h.visible or _helping.has(who):
			continue
		if h.global_position.distance_to(c.global_position) > 25.0:
			continue
		_help_when_able(h, c)


## She goes to her friend as soon as she can herself: at once, or once her own flinch / stagger is over. If she
## was knocked down too, each looks after herself.
func _help_when_able(h: WorldCharacter, fallen: WorldCharacter) -> void:
	_helping[h.character_id] = fallen.character_id
	var t0 := Time.get_ticks_msec()
	while h.reaction.active and Time.get_ticks_msec() - t0 < 6000:
		if h.reaction.tier == "down":
			_helping.erase(h.character_id)
			return
		await get_tree().physics_frame
	if fallen.reaction.active and fallen.reaction.tier == "down" and not h.reaction.active:
		_help(h, fallen)
	else:
		_helping.erase(h.character_id)


func _on_recovered(info: Dictionary, c: WorldCharacter) -> void:
	var who := c.character_id
	if String(info.get("tier", "")) == "pose":
		return
	if String(info.get("tier", "")) == "flinch":
		_hold(who, false)
		return
	if _helping.has(who):
		return
	_after(c, info)


var _held_before := {}        # who -> the planner's hold state before a reaction took it (restored afterwards)


func _hold(who: String, on: bool) -> void:
	var b = main.mage_brains.get(who) if main.get("mage_brains") else null
	if b == null:
		return
	if on:
		if not _held_before.has(who):
			_held_before[who] = bool(b.hold)     # a scene or a test may already hold her: never release that
		b.hold = true
		b.interrupt("struck")
	elif not _busy.has(who) and not _helping.has(who) and not (main.characters[who] as WorldCharacter).reaction.active:
		b.hold = bool(_held_before.get(who, false))
		_held_before.erase(who)


## The fallen one's helper: run to her side, kneel, wait, offer a hand as she rises, stand with her.
func _help(h: WorldCharacter, fallen: WorldCharacter) -> void:
	var hid := h.character_id
	_helping[hid] = fallen.character_id
	_busy[hid] = true
	_hold(hid, true)
	var ev := {"who": hid, "helps": fallen.character_id, "t0": snappedf(Time.get_ticks_msec() / 1000.0, 0.1)}
	h.look_head_at(fallen.global_position + Vector3(0, 0.3, 0))
	_say(hid, "friend_down", 0.3)
	await get_tree().create_timer(0.5).timeout
	var side := (h.global_position - fallen.global_position)
	side.y = 0
	side = side.normalized() if side.length() > 0.1 else Vector3.RIGHT
	var spot := fallen.global_position + side * 0.95
	var map := h.get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_closest_point(map, spot)
	if p != Vector3.ZERO and p.distance_to(spot) < 2.0:
		spot = p
	h.navigate_to(spot, true)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(h) and h.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 9000:
		await get_tree().physics_frame
	ev["reached_m"] = snappedf(h.global_position.distance_to(fallen.global_position), 0.01)
	if h.reaction.active or not fallen.reaction.active:
		_helping.erase(hid)
		_busy.erase(hid)
		_hold(hid, false)
		ev["outcome"] = "she was already up" if not fallen.reaction.active else "struck herself"
		aftermath_log.append(ev)
		return
	h.look_at_point(fallen.global_position)
	await get_tree().create_timer(0.35).timeout
	h.reaction.pose("rx_crouch_help", 0.6)
	h.look_head_at(fallen.global_position + Vector3(0, 0.25, 0))
	if h.face:
		h.face.set_hold("concerned", 0.8)
	_say(hid, "kneel", 0.4)
	# wait while she is down; as she starts to rise, reach out a hand, then stand up together
	t0 = Time.get_ticks_msec()
	while fallen.reaction.active and fallen.reaction.phase in ["falling", "down", "sitting_up", "catching_breath"] and Time.get_ticks_msec() - t0 < 12000:
		await get_tree().physics_frame
	if h.reaction.tier == "pose":
		h.reaction._go("rx_reach_help", 0.45, 0.9)
		await get_tree().create_timer(0.9).timeout
		h.reaction.release(0.6)
	if h.face:
		h.face.set_hold("concerned", 0.0)
	ev["outcome"] = "knelt beside her and helped her up"
	aftermath_log.append(ev)
	await get_tree().create_timer(0.8).timeout
	_helping.erase(hid)
	_busy.erase(hid)
	_hold(hid, false)


## Once she is steady: her own way of dealing with what hit her.
func _after(c: WorldCharacter, info: Dictionary) -> void:
	var who := c.character_id
	_busy[who] = true
	var style := String(c.reaction.body.get("after", "protective"))
	var src_pos := c.global_position
	var last_blast: Dictionary = log.back() if not log.is_empty() else {}
	if last_blast.has("at"):
		var a: Array = last_blast.at
		src_pos = Vector3(a[0], a[1], a[2])
	var ev := {"who": who, "style": style, "tier": info.get("tier", ""), "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1)}
	var helped_by := ""
	for k in _helping:
		if _helping[k] == who:
			helped_by = k
	if helped_by != "":
		ev["helped_by"] = helped_by
		_say(who, "thanks", 0.2)
	var b = main.mage_brains.get(who) if main.get("mage_brains") else null
	if b and String(b.current.get("kind", "")) == "hunt":
		# in the middle of a fight her own tactics take over again (they keep distance, ward, dodge) - but she
		# remembers what knocked her down, and says so
		ev["back_into_fight"] = true
		_say(who, "retreat" if style == "evasive" else "recovered", 0.3)
		if style == "evasive":
			b.mind.knowledge["keep_distance_bonus"] = 2.0
		aftermath_log.append(ev)
		_busy.erase(who)
		_hold(who, false)
		return
	if style == "evasive":
		# out of its reach first, then watch it
		var away := c.global_position - src_pos
		away.y = 0
		away = away.normalized() if away.length() > 0.1 else -c.global_transform.basis.z
		var want := c.global_position + away * 5.0
		var p := NavigationServer3D.map_get_closest_point(c.get_world_3d().navigation_map, want)
		if p != Vector3.ZERO and p.distance_to(want) < 3.0:
			_say(who, "retreat", 0.0)
			c.navigate_to(p, true)
			var t0 := Time.get_ticks_msec()
			while c.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 6000:
				await get_tree().physics_frame
			ev["retreated_m"] = snappedf(c.global_position.distance_to(src_pos), 0.1)
		c.look_at_point(src_pos)
	else:
		c.look_at_point(src_pos)
		c.set_combat_stance(true)
		_say(who, "recovered", 0.3)
		await get_tree().create_timer(2.5).timeout
		c.set_combat_stance(false)
		ev["faced_danger"] = true
	aftermath_log.append(ev)
	await get_tree().create_timer(1.0).timeout
	_busy.erase(who)
	_hold(who, false)
