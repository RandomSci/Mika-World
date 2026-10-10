class_name Interactable
extends Node3D
## A real, physically placed activity. `perform()` requires the character to be within `radius`,
## faces the object, plays a gesture, waits for the activity's duration, then applies effects to
## WorldState and returns exactly what changed. Nothing here is narrated without happening.

signal performed(result: Dictionary)

var id := ""
var label := ""
var verb := "examine"         # study, meditate, practice, craft, observe, collect, light, rest, read, pray, inspect
var location_id := ""
var radius := 1.8
var duration := 3.0
var gesture := ""             # Mixamo clip name in WorldCharacter.CLIPS, "" = just face it
var effects := {}             # {"knowledge": {...}, "items": {...}, "skills": {...}}
var repeatable := true
var times_done := 0
var requires := {}            # {"items": {"crystal_shard": 1}} etc. checked against WorldState
var on_done: Callable         # optional visual change (e.g. light a lantern)
var busy := false
var lore_id := ""             # key into data/sanctuary.json "lore" → readable title/text
var kind := ""                # study | practice | meditate | inspect | explore | rest (brain/camera hints)
var stand_point = null         # optional exact spot (local to the area) to stand at, e.g. in front of a seat
var face_point = null          # optional point to face while performing (default: the object itself)
var on_begin: Callable         # optional visual cue when the gesture starts (e.g. a target lights up)
var seat_body: PhysicsBody3D   # solid seat: ignored by the seated character only while she sits on it
var sit_point = null           # where her root goes while seated (pelvis over the seat), local to the area
var book_id := ""              # a readable book/scroll/inscription (data/books.json): perform() = real reading
var book_xf = null             # Transform3D (area-local) where the open book lies; null = read in place
var book_props: Array = []     # closed-book decor hidden while the open book is out
var custom_activity: Callable  # multi-step physical activity (alchemy...): awaited instead of the plain wait
var _approach = null           # closest walkable point (computed once navigation exists)


## Where a character should stand to use this: the navmesh point closest to the object.
func approach_point() -> Vector3:
	if stand_point != null and is_inside_tree():
		return get_parent().to_global(stand_point)
	if _approach == null:
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			_approach = NavigationServer3D.map_get_closest_point(map, global_position)
		else:
			return global_position
	return _approach


func in_reach(from: Vector3) -> bool:
	var flat := func(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.z - b.z).length()
	return flat.call(from, global_position) <= radius + 0.6 or flat.call(from, approach_point()) <= 1.1


static func make(p_id: String, p_label: String, p_verb: String, p_loc: String, pos: Vector3, p_effects := {}, p_gesture := "", p_duration := 3.0) -> Interactable:
	var it := Interactable.new()
	it.id = p_id
	it.name = p_id
	it.label = p_label
	it.verb = p_verb
	it.location_id = p_loc
	it.position = pos
	it.effects = p_effects
	it.gesture = p_gesture
	it.duration = p_duration
	return it


func describe(from: Vector3) -> Dictionary:
	return {"id": id, "label": label, "verb": verb, "location": location_id,
		"distance": snappedf(from.distance_to(global_position), 0.01), "in_reach": in_reach(from),
		"times_done": times_done, "available": (repeatable or times_done == 0) and not busy and _requirements_met()}


func _requirements_met() -> bool:
	for k in requires.get("items", {}):
		if WorldState.inventory.get(k, 0) < requires.items[k]:
			return false
	return true


func perform(c: WorldCharacter) -> Dictionary:
	var d := Vector2(c.global_position.x - global_position.x, c.global_position.z - global_position.z).length()
	if busy:
		return {"ok": false, "detail": "already in use"}
	if not in_reach(c.global_position):
		return {"ok": false, "detail": "too far: %.1f m away (reach %.1f m, or stand at the approach point)" % [d, radius + 0.6]}
	if not repeatable and times_done > 0:
		return {"ok": false, "detail": "already done; not repeatable"}
	if not _requirements_met():
		return {"ok": false, "detail": "requires %s" % str(requires)}
	busy = true
	WorldState.interaction_started.emit(self, c)
	if seat_body:
		c.add_collision_exception_with(seat_body)
	if stand_point != null:
		# settle exactly onto the spot (seats, casting marks); the nav agent stops up to ~0.7 m short.
		# Never slide through geometry: if the short move would collide, she stays where she is.
		var spot: Vector3 = approach_point()
		var delta := Vector3(spot.x - c.global_position.x, 0.0, spot.z - c.global_position.z)
		if delta.length() < 1.2 and not c.test_move(c.global_transform, delta):
			var tw := c.create_tween()
			tw.tween_property(c, "global_position", c.global_position + delta, 0.35)
	c.look_at_point(get_parent().to_global(face_point) if face_point != null else global_position)
	await get_tree().create_timer(0.6).timeout
	var sitting := gesture == "sit" and sit_point != null
	if sitting:
		# lower onto the seat: the root (and so the pelvis) slides back over the seat while the pose blends in
		c.play_gesture(gesture, 0.7, 0.7)
		c.set_seated(true, 0.8)
		var sp: Vector3 = get_parent().to_global(sit_point)
		var tws := c.create_tween()
		tws.tween_property(c, "global_position", Vector3(sp.x, c.global_position.y, sp.z), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif gesture != "" and book_id == "":
		c.play_gesture(gesture)
	if on_begin.is_valid():
		on_begin.call()
	var read_result := {}
	var act_result := {}
	if custom_activity.is_valid():
		act_result = await custom_activity.call(c)
	elif book_id != "" and BookReader.instance:
		for bp in book_props:
			bp.visible = false
		var anchor = get_parent().global_transform * (book_xf as Transform3D) if book_xf != null else null
		read_result = await BookReader.instance.read(c, book_id, anchor)
		for bp in book_props:
			bp.visible = true
	else:
		await get_tree().create_timer(duration).timeout
	if seat_body:
		# stand up: rise forward off the seat, clear of it, before it becomes solid for her again
		if sitting:
			c.set_seated(false, 0.6)
		var fwd := -c.global_transform.basis.z
		fwd.y = 0
		var tw2 := c.create_tween()
		tw2.tween_property(c, "global_position", c.global_position + fwd.normalized() * (0.75 if sitting else 0.4), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw2.finished
		c.remove_collision_exception_with(seat_body)
	busy = false
	times_done += 1
	for k in requires.get("items", {}):
		WorldState.inventory[k] -= requires.items[k]
	var changes := WorldState.record_activity({"id": id, "verb": verb, "label": label}, effects)
	if on_done.is_valid():
		on_done.call()
	var result := {"ok": true, "detail": "%s: %s" % [verb, label], "changes": changes, "times_done": times_done}
	if not act_result.is_empty():
		result["activity"] = act_result
		result["ok"] = act_result.get("ok", false)
		result["detail"] = String(act_result.get("detail", result.detail))
	if not read_result.is_empty():
		result["reading"] = read_result
		result["ok"] = read_result.get("ok", false) and not read_result.get("interrupted", false)
		if read_result.get("interrupted", false):
			result["detail"] = "stopped reading %s after %d page(s)" % [read_result.title, read_result.pages_read.size()]
	var lore: Dictionary = WorldState.sanctuary.get("lore", {}).get(lore_id if lore_id != "" else id, {})
	if not lore.is_empty():
		result["read"] = lore
	WorldState.interaction_finished.emit(self, c, result)
	performed.emit(result)
	return result
