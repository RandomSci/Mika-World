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
		"distance": snappedf(from.distance_to(global_position), 0.01), "in_reach": from.distance_to(global_position) <= radius + 0.6,
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
	if d > radius + 0.6:
		return {"ok": false, "detail": "too far: %.1f m away (reach %.1f m)" % [d, radius + 0.6]}
	if not repeatable and times_done > 0:
		return {"ok": false, "detail": "already done; not repeatable"}
	if not _requirements_met():
		return {"ok": false, "detail": "requires %s" % str(requires)}
	busy = true
	c.look_at_point(global_position)
	await get_tree().create_timer(0.6).timeout
	if gesture != "":
		c.play_gesture(gesture)
	await get_tree().create_timer(duration).timeout
	busy = false
	times_done += 1
	for k in requires.get("items", {}):
		WorldState.inventory[k] -= requires.items[k]
	var changes := WorldState.record_activity({"id": id, "verb": verb, "label": label}, effects)
	if on_done.is_valid():
		on_done.call()
	var result := {"ok": true, "detail": "%s: %s" % [verb, label], "changes": changes, "times_done": times_done}
	performed.emit(result)
	return result
