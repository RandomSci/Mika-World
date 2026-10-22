class_name PlaceCuriosity
extends Node
## Curiosity about places (Selwyn, 22 Oct): the first time the girls reach a place they stop, look around and wonder
## out loud what it is, then one walks up to something there for a closer look and they react to each other. Every
## place is remembered in each girl's own mind (knowledge "place:<location>", saved with the game, so it survives
## restarts and new worktrees): when she first came, how often, what they said there. A revisit is different: they
## recall the last time and notice what has changed, and only now and then (a place they know well is not news).
## Passing a new place on a journey gets a wondering remark on the move (the journey is never stopped for it).

const REVISIT_GAP_S := 1200.0          # a revisit is talked about only if they were last here this long ago
const REVISIT_TALK_GAP_S := 600.0      # and at most one revisit talk in this long, anywhere
const SETTLE_TIMEOUT_S := 15.0         # waiting for both to finish what they were doing before the stop

var main: Node
var busy := false
var log: Array = []                    # what happened (tests): {loc, kind, look_closer, unix}
var _last_revisit_talk := -1e9
var _queue: Array = []
var _rng := RandomNumberGenerator.new()


func setup(m: Node) -> void:
	main = m
	_rng.randomize()
	WorldState.location_entered.connect(_on_entered)


func _on_entered(loc: String) -> void:
	if not _queue.has(loc):
		_queue.append(loc)


func _process(_dt: float) -> void:
	if busy or _queue.is_empty() or main == null:
		return
	if main.streaming.state != "idle":
		return                        # (arrival is registered behind the travel card: the scene waits for the reveal)
	var loc := String(_queue.pop_front())
	if loc != WorldState.current_location:
		return                        # already walked on through it
	_visit(loc)


## Memory of a place in one girl's mind.
static func memory(who: String, loc: String) -> Dictionary:
	return WorldState.mind(who).knowledge.get("place:" + loc, {})


static func _remember(who: String, loc: String, said: String) -> void:
	var k := WorldState.mind(who).knowledge
	var m: Dictionary = k.get("place:" + loc, {})
	var now := Time.get_unix_time_from_system()
	if m.is_empty():
		m = {"first": now, "visits": 0, "said": []}
	m.visits = int(m.get("visits", 0)) + 1
	m.prev = float(m.get("last", now))
	m.last = now
	if said != "":
		var s: Array = m.get("said", [])
		s.append(said.left(160))
		m.said = s.slice(maxi(0, s.size() - 4))
	k["place:" + loc] = m


func _pair() -> Array:
	var mages: Array = main.get("mages") if main.get("mages") else []
	if mages.size() < 2:
		return []
	var ca: WorldCharacter = main.characters.get(mages[0])
	var cb: WorldCharacter = main.characters.get(mages[1])
	if ca == null or cb == null or not ca.visible or not cb.visible or ca.casting or cb.casting:
		return []
	if ca.global_position.distance_to(cb.global_position) > 14.0:
		return []
	return [String(mages[0]), String(mages[1])]


func _blocked() -> bool:
	if main.mage_talk.dialogue.active or main.mage_talk.busy():
		return true
	if main.get("performance") and main.performance.busy():
		return true
	for w in main.mage_brains:
		var br = main.mage_brains[w]
		if br.threat != null:
			return true
	return main.streaming.state != "idle"


func _visit(loc: String) -> void:
	var pair := _pair()
	var info: Dictionary = WorldState.locations.get(loc, {})
	if pair.is_empty() or info.is_empty() or _blocked():
		# not together or not free now: still remembered as a place she has been (no talk)
		for w in (main.get("mages") if main.get("mages") else []):
			if main.characters.has(w) and (main.characters[w] as Node3D).visible:
				_remember(String(w), loc, "")
		return
	# (visited_locations was already counted for this entry: 1 means the very first time. A place visited before this
	# memory existed is a revisit with nothing remembered yet.)
	var first: bool = memory(pair[0], loc).is_empty() and memory(pair[1], loc).is_empty() and int(WorldState.visited_locations.get(loc, 1)) <= 1
	var travelling: bool = main.travel.active() and String(main.travel.journey.get("destination", "")) != loc
	busy = true
	print("[curiosity] %s at %s (%s) frame %d" % ["first visit" if first else "back", loc, "passing on a journey" if travelling else "arrived", Engine.get_frames_drawn()])
	if main.travel.active() and not travelling:
		# arriving at the journey's own destination: the stop comes once the walk there is done
		# (never stops a journey: at most 60 s cut the grove's last stretch short 11.5 m from the end, 22 Oct)
		var tw := Time.get_ticks_msec()
		while main.travel.active() and Time.get_ticks_msec() - tw < 900000:
			await get_tree().process_frame
		if main.travel.active() or _pair().is_empty() or _blocked():
			for w in pair:
				_remember(w, loc, "")
			busy = false
			return
	if first and travelling:
		await _wonder_on_the_way(pair, loc, info)
	elif first:
		await _first_visit(pair, loc, info)
	else:
		await _revisit(pair, loc, info)
	busy = false


func _place_text(loc: String, info: Dictionary) -> String:
	var region: Dictionary = WorldState.regions.get(String(info.get("region", "")), {})
	var t := "%s: %s" % [String(info.get("name", loc)), String(info.get("description", ""))]
	if not region.is_empty():
		t += " It is part of the %s (%s)." % [String(region.get("name", "")), String(region.get("theme", ""))]
	for lm in WorldState.landmarks.values():
		if String(lm.get("location", "")) == loc:
			t += " Known landmark here: %s." % String(lm.get("name", ""))
	return t


func _talk(a: String, b: String, text: String, key: String) -> Dictionary:
	return await main.mage_talk.dialogue.converse(a, b, {"mode": "event", "topic": {"text": text, "key": key}})


func _first_line(entry: Dictionary) -> String:
	var lines: Array = entry.get("lines", [])
	return "" if lines.is_empty() else "%s said \"%s\"" % [String(lines[0].who), String(lines[0].text)]


## Both stop what they were doing, look around, wonder out loud; then one walks up to something there for a closer
## look, the other comes along, and they react to it.
func _first_visit(pair: Array, loc: String, info: Dictionary) -> void:
	var held := await _stop_both(pair)
	var ca: WorldCharacter = main.characters[pair[0]]
	var cb: WorldCharacter = main.characters[pair[1]]
	var area = main.streaming.current
	var centre: Vector3 = area.points_of_interest[loc].position if area and area.points_of_interest.has(loc) else ca.global_position + -ca.global_basis.z * 6.0
	for c in [ca, cb]:
		c.look_at_point(centre)
	await get_tree().create_timer(0.8).timeout
	ca.play_gesture("look_around")
	await get_tree().create_timer(0.6).timeout
	cb.play_gesture("look_around")
	await get_tree().create_timer(2.4).timeout
	var starter: String = pair[0] if _rng.randf() < 0.55 else pair[1]
	var e1 := await _talk(starter, _other(pair, starter), "you have just arrived here for the very first time, a place neither of you has ever seen. " + _place_text(loc, info)
		+ " Stop and wonder out loud what this place is, point out one thing you actually notice, and react to each other.", "first:" + loc)
	# a closer look at one thing here
	var poi := _poi_near(loc, ca.global_position)
	var closer := ""
	if not poi.is_empty():
		closer = String(poi.description)
		var looker: String = _other(pair, starter)
		var lc: WorldCharacter = main.characters[looker]
		var oc: WorldCharacter = main.characters[_other(pair, looker)]
		var map := lc.get_world_3d().navigation_map
		var near := NavigationServer3D.map_get_closest_point(map, (poi.position as Vector3).lerp(lc.global_position, 1.6 / maxf(lc.global_position.distance_to(poi.position), 1.7)))
		lc.navigate_to(near, false)
		await get_tree().create_timer(0.7).timeout
		oc.navigate_to(NavigationServer3D.map_get_closest_point(map, near + (oc.global_position - near).normalized() * 1.6), false)
		var t0 := Time.get_ticks_msec()
		while lc.current_action == "navigate_to" and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
		lc.look_at_point(poi.position)
		oc.look_at_point(poi.position)
		lc.play_gesture("pointing")
		await get_tree().create_timer(1.6).timeout
		await _talk(looker, _other(pair, looker), "you walked up for a closer look at %s, here at %s (first time here). Say what you see up close and what you think it is, and answer each other." % [closer, String(info.get("name", loc))], "closer:" + loc)
	for w in pair:
		_remember(w, loc, _first_line(e1))
	_release(held)
	log.append({"loc": loc, "kind": "first", "look_closer": closer, "unix": int(Time.get_unix_time_from_system())})
	print("[curiosity] first visit to %s done, looked closer at: %s, frame %d" % [loc, closer if closer != "" else "-", Engine.get_frames_drawn()])


## On the move through a new place: a wondering remark while they walk (the journey goes on).
func _wonder_on_the_way(pair: Array, loc: String, info: Dictionary) -> void:
	var starter: String = pair[0] if _rng.randf() < 0.5 else pair[1]
	var e: Dictionary = await main.mage_talk.dialogue.converse(starter, _other(pair, starter), {"mode": "ambient", "topic": {"text":
		"you are passing through a place you have never seen before, on your way somewhere else. " + _place_text(loc, info) + " Wonder about it as you walk, and maybe say you want to come back.", "key": "first:" + loc}})
	for w in pair:
		_remember(w, loc, _first_line(e))
	log.append({"loc": loc, "kind": "passing", "look_closer": "", "unix": int(Time.get_unix_time_from_system())})


## Back again: what they remember of it, what is different now. Not every time (a place they know is not news).
func _revisit(pair: Array, loc: String, info: Dictionary) -> void:
	var m := memory(pair[0], loc)
	var now := Time.get_unix_time_from_system()
	var since := now - float(m.get("last", 0.0))
	var visits := maxi(int(m.get("visits", 0)), int(WorldState.visited_locations.get(loc, 1)) - 1)
	var talk_now := since > REVISIT_GAP_S and now - _last_revisit_talk > REVISIT_TALK_GAP_S and _rng.randf() < (1.0 if visits < 3 else 0.4)
	var said := ""
	if talk_now:
		_last_revisit_talk = now
		var said_before: Array = m.get("said", [])
		var hours := since / 3600.0
		var when := ("%.0f hours" % hours) if hours >= 1.5 else ("%.0f minutes" % (since / 60.0))
		var text := "you are back at %s (%s), a place you have been to %d times before" % [String(info.get("name", loc)), String(info.get("description", "")), visits]
		text += ("; you were last here %s ago." % when) if m.has("last") else "."
		if not said_before.is_empty():
			text += " Last time %s." % String(said_before.back())
		text += " It is %s now. Bring up something from last time and notice what is different now; do not describe the place as if it were new." % ("night" if WorldState.night else "day")
		var starter: String = pair[0] if _rng.randf() < 0.5 else pair[1]
		var e: Dictionary = await main.mage_talk.dialogue.converse(starter, _other(pair, starter), {"mode": "ambient", "topic": {"text": text, "key": "back:" + loc}})
		said = _first_line(e)
	for w in pair:
		_remember(w, loc, said)
	log.append({"loc": loc, "kind": "revisit" if talk_now else "revisit_quiet", "look_closer": "", "unix": int(now)})


func _poi_near(loc: String, from: Vector3) -> Dictionary:
	var area = main.streaming.current
	if area == null:
		return {}
	var best := {}
	var best_d := 35.0
	for id in area.points_of_interest:
		var p: Dictionary = area.points_of_interest[id]
		if id == loc or String(p.get("location", "")) != loc or String(p.get("description", "")) == "":
			continue
		var d := from.distance_to(p.position)
		if d < best_d and d > 2.0:
			best_d = d
			best = p
	return best


func _stop_both(pair: Array) -> Array:
	var held := []
	for w in pair:
		var br = main.mage_brains.get(w)
		if br == null:
			continue
		if not br.current.is_empty():
			br.interrupt("stopped to look at a new place")
		if not br.hold:
			br.hold = true
			held.append(br)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < SETTLE_TIMEOUT_S * 1000.0:
		var settled := true
		for w in pair:
			var br = main.mage_brains.get(w)
			if br and not br.current.is_empty():
				settled = false
		if settled:
			break
		await get_tree().process_frame
	for w in pair:
		(main.characters[w] as WorldCharacter).stop_action()
	return held


func _release(held: Array) -> void:
	for br in held:
		br.hold = false


func _other(pair: Array, who: String) -> String:
	return String(pair[1]) if who == pair[0] else String(pair[0])
