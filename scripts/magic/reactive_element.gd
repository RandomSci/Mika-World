class_name ReactiveElement
extends Node3D
## Something in the world that magic can physically affect (brazier, pond, rune, relic, practice target).
## Every reaction is real engine state with bounded, reversible consequences: `react()` changes the
## object, schedules its own recovery and returns exactly what happened. Subclasses implement
## `_react_<element>(power, point)` and `_recover(key)`; the base class handles ids, hit bodies,
## recovery timers, state reporting and the world-wide `magic_event` broadcast (wildlife, NPCs, camera).

signal reacted(result: Dictionary)

var id := ""
var kind := ""                     # brazier | water | rune | marked_stone | relic | practice_crystal | dummy | stone
var label := ""
var aim_offset := Vector3.ZERO     # where spells should aim, relative to this node
var aim_radius := 0.5              # how close an impact must land to count as on target
var bodies: Array[CollisionObject3D] = []   # colliders that belong to this object (a projectile hitting them = hit)
var state := {}                    # reported verbatim to the AI
var supports := []                 # elements that produce a real reaction (others: "no visible effect")
var _timers := {}                  # recovery key -> seconds left


static func registry_of(world: Node) -> Dictionary:
	var out := {}
	if world == null:
		return out
	for n in world.find_children("*", "ReactiveElement", true, false):
		out[(n as ReactiveElement).id] = n
	return out


func aim_point() -> Vector3:
	return global_position + aim_offset


func owns_collider(o: Object) -> bool:
	if o == null:
		return false
	for b in bodies:
		if b == o:
			return true
	return o is Node and is_ancestor_of(o)


func describe(from: Vector3) -> Dictionary:
	return {"id": id, "kind": kind, "label": label, "distance": snappedf(from.distance_to(aim_point()), 0.01),
		"state": state.duplicate(), "responds_to": supports.duplicate(), "aim_point": [snappedf(aim_point().x, 0.01), snappedf(aim_point().y, 0.01), snappedf(aim_point().z, 0.01)]}


## Apply a spell that actually reached this object. power is 0..~1.5 (mastery-scaled).
func react(element: String, power: float, point: Vector3, spell_id: String) -> Dictionary:
	var before := state.duplicate(true)
	var r: Dictionary
	if supports.has(element) and has_method("_react_" + element):
		r = call("_react_" + element, power, point)
	else:
		r = {"effect": "none", "detail": "%s shows no visible response to %s magic" % [label, element]}
	r["object"] = id
	r["element"] = element
	r["spell"] = spell_id
	r["power"] = snappedf(power, 0.01)
	r["state_before"] = before
	r["state_after"] = state.duplicate(true)
	r["changed"] = before != state
	MagicEvents.emit_magic(global_position, element, power, r.get("effect", "none"), id)
	reacted.emit(r)
	return r


func schedule(key: String, seconds: float) -> void:
	_timers[key] = seconds


func cancel(key: String) -> void:
	_timers.erase(key)


func _process(delta: float) -> void:
	if _timers.is_empty():
		return
	for k in _timers.keys():
		_timers[k] -= delta
		if _timers[k] <= 0.0:
			_timers.erase(k)
			_recover(k)


func _recover(_key: String) -> void:
	pass


func pending_recoveries() -> Dictionary:
	var o := {}
	for k in _timers:
		o[k] = snappedf(_timers[k], 0.1)
	return o
