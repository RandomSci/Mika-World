class_name MagicSystem
extends Node
## Target-aware casting. Owns the spell catalogue (data/spells.json) and the whole truthful pipeline:
##   can_cast -> resolve target (stable id) -> range / line-of-sight / compatibility checks -> face it
##   -> run the spell (visuals synced to the animation) -> real projectile sweep (hit / blocked / missed)
##   -> ReactiveElement.react() -> mastery only for verified hits that produced an effect.
## Every refusal and outcome is returned with the reason. Used by the player, the AI bridge and the brain.

signal cast_resolved(result: Dictionary)

static var catalog := {}
static var last_cast_dir := Vector3.ZERO
static var last_spell := ""

var main: Node
var busy := false
var history: Array = []
var rng := RandomNumberGenerator.new()


static func load_catalog() -> Dictionary:
	if catalog.is_empty():
		var f := FileAccess.open("res://data/spells.json", FileAccess.READ)
		catalog = JSON.parse_string(f.get_as_text())
	return catalog


static func spell(id: String) -> Dictionary:
	return load_catalog().spells.get(id, {})


static func mastery(id: String) -> float:
	return float(WorldState.skills.get(id, 0.0))


static func tier_name(m: float) -> String:
	var name := "Untested"
	for t in load_catalog().mastery_tiers:
		if m >= float(t.min):
			name = t.name
	return name


static func power_of(id: String, charge := 0.0) -> float:
	var s := spell(id)
	return clampf(float(s.get("base_power", 0.5)) + float(s.get("power_per_mastery", 0.3)) * minf(mastery(id), 3.0) + charge, 0.05, 1.6)


## How far from the aimed point a cast may land (metres): practice makes it tighter.
static func aim_error(id: String) -> float:
	return clampf(0.55 - 0.2 * mastery(id), 0.04, 0.55)


func _init() -> void:
	rng.seed = 77
	load_catalog()


func setup(m: Node) -> void:
	main = m


## Known = castable at all. Unknown spells explain what is missing (read the incantation first).
func can_cast(id: String) -> Dictionary:
	var s := spell(id)
	if s.is_empty():
		return {"ok": false, "reason": "unknown spell '%s' (catalogue: %s)" % [id, ", ".join(load_catalog().spells.keys())]}
	if s.get("known_from_start", false) or WorldState.skills.has(id):
		return {"ok": true}
	var need: String = s.get("requires_knowledge", "")
	if need != "" and WorldState.knowledge.has(need):
		for other in s.get("requires_mastery", {}):
			if mastery(other) < float(s.requires_mastery[other]):
				return {"ok": false, "reason": "%s needs %s mastery of at least %.1f first (now %.2f)" % [s.name, spell(other).name, float(s.requires_mastery[other]), mastery(other)]}
		return {"ok": true, "first_attempt": true}
	return {"ok": false, "reason": "Mika doesn't know %s yet: she has not learned its incantation (%s)" % [s.name, need]}


func known_spells() -> Array:
	var out := []
	for id in load_catalog().spells:
		var c := can_cast(id)
		var s := spell(id)
		out.append({"id": id, "name": s.name, "element": s.element, "castable": c.ok, "reason": c.get("reason", ""),
			"mastery": snappedf(mastery(id), 0.01), "tier": tier_name(mastery(id)), "power": snappedf(power_of(id), 0.01),
			"range_m": s.range, "incantation": s.incantation, "translation": s.translation})
	return out


func reactives() -> Dictionary:
	return ReactiveElement.registry_of(main.world)


## Every reactive target with range / line-of-sight / compatibility for one spell, from where Mika stands.
func targets_for(id: String, caster: WorldCharacter) -> Array:
	var out := []
	for r in reactives().values():
		var v := validate(id, caster, r)
		var d: Dictionary = (r as ReactiveElement).describe(caster.global_position)
		d["valid"] = v.ok
		d["reason"] = v.get("reason", "")
		out.append(d)
	out.sort_custom(func(a, b): return a.distance < b.distance)
	return out


func validate(id: String, caster: WorldCharacter, target: ReactiveElement) -> Dictionary:
	var s := spell(id)
	var kinds: Array = s.get("target_kinds", ["*"])
	if not kinds.has("*") and not kinds.has(target.kind):
		return {"ok": false, "reason": "%s cannot target a %s (it works on: %s)" % [s.name, target.kind, ", ".join(kinds)]}
	var from := caster.chest.global_position
	var aim := target.aim_point()
	var dist := from.distance_to(aim)
	if dist > float(s.range):
		return {"ok": false, "reason": "out of range: %.1f m (range %.0f m)" % [dist, s.range]}
	if dist < 1.2:
		return {"ok": false, "reason": "too close (%.1f m): step back to cast safely" % dist}
	var q := PhysicsRayQueryParameters3D.create(from, aim)
	q.exclude = [caster.get_rid()]
	var hit := caster.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and not target.owns_collider(hit.collider) and (hit.position as Vector3).distance_to(aim) > target.aim_radius + 0.35:
		var by: String = (hit.collider as Node).name if hit.collider is Node else "geometry"
		return {"ok": false, "reason": "no line of sight to %s (blocked by %s %.1f m away)" % [target.label, by, from.distance_to(hit.position)]}
	return {"ok": true, "distance": dist}


## Cast `id` at reactive target `target_id` ("" = straight ahead; "self" for self spells).
func cast(caster: WorldCharacter, id: String, target_id := "") -> Dictionary:
	var started := Time.get_ticks_msec()
	var s := spell(id)
	var res := {"spell": id, "target": target_id, "ok": false}
	var cc := can_cast(id)
	if not cc.ok:
		res["outcome"] = "refused"
		res["reason"] = cc.reason
		return _finish(res)
	if busy or caster.casting:
		res["outcome"] = "refused"
		res["reason"] = "already casting"
		return _finish(res)
	if not caster.is_on_floor():
		res["outcome"] = "refused"
		res["reason"] = "not standing on the ground"
		return _finish(res)
	var target: ReactiveElement = null
	var self_spell: bool = s.get("projectile", "") == "self"
	if not self_spell and target_id != "":
		target = reactives().get(target_id)
		if target == null:
			res["outcome"] = "refused"
			res["reason"] = "no reactive target '%s' here (available: %s)" % [target_id, ", ".join(reactives().keys())]
			return _finish(res)
		var v := validate(id, caster, target)
		if not v.ok:
			res["outcome"] = "refused"
			res["reason"] = v.reason
			return _finish(res)
	if not main.world.has_space_for_magic(caster.global_position):
		res["outcome"] = "refused"
		res["reason"] = "not enough space around her to cast"
		return _finish(res)
	busy = true
	last_spell = id
	# face the target first (a cast is never thrown sideways)
	if target:
		caster.look_at_point(target.aim_point())
		var t0 := Time.get_ticks_msec()
		while caster.current_action == "look_at" and Time.get_ticks_msec() - t0 < 2500:
			await get_tree().process_frame
	var charge: float = caster.get_meta("magic_charge", 0.0)
	if charge > 0.0 and not self_spell:
		caster.remove_meta("magic_charge")
	var power := power_of(id, charge if not self_spell else 0.0)
	var aim := Vector3.ZERO
	var fwd := -caster.global_transform.basis.z
	if target:
		var err := aim_error(id)
		var perp := fwd.cross(Vector3.UP).normalized()
		aim = target.aim_point() + perp * rng.randf_range(-err, err) + Vector3.UP * rng.randf_range(-err, err) * 0.6
	else:
		aim = caster.chest.global_position + fwd * minf(float(s.range), 6.0)
	last_cast_dir = Vector3(aim.x - caster.global_position.x, 0, aim.z - caster.global_position.z).normalized()
	var node: Node3D
	if id == "arcane_orb":
		node = caster.cast_spell(ArcaneOrbSpell, String(s.clip))
		if node:
			node.set("aim_point", aim)
			node.set("target_ref", target)
			node.set("spell_id", id)
	else:
		node = caster.cast_spell(ElementalSpell, String(s.clip))
		if node:
			(node as ElementalSpell).configure(id, s, aim, target, power, mastery(id))
	if node == null:
		busy = false
		res["outcome"] = "refused"
		res["reason"] = caster.last_rejection if caster.last_rejection != "" else "the cast animation could not start"
		return _finish(res)
	var flight: Dictionary = await node.resolved
	busy = false
	res.merge(flight)
	res["ok"] = true
	res["power"] = snappedf(power, 0.01)
	res["mastery_before"] = snappedf(mastery(id), 0.01)
	res["incantation"] = s.incantation
	if self_spell:
		caster.set_meta("magic_charge", power * 0.5)
		res["effect"] = "charged"
		res["detail"] = "ambient power gathered: the next spell is %d%% stronger" % int(power * 50)
		res["changes"] = _award(id, 0.04, "self", "charged", cc.get("first_attempt", false))
	elif flight.outcome == "hit" and target:
		var pt: Array = flight.point
		var reaction := target.react(String(s.element), power, Vector3(pt[0], pt[1], pt[2]), id)
		res["reaction"] = reaction
		res["effect"] = reaction.effect
		res["detail"] = reaction.detail
		if reaction.effect != "none":
			res["changes"] = _award(id, 0.08, target.kind, reaction.effect, cc.get("first_attempt", false))
			if reaction.has("clue"):
				var c2 := WorldState.record_activity({"id": "clue_found", "verb": "discover", "label": target.label}, {"knowledge": {reaction.clue: 1}})
				(res["changes"] as Dictionary).merge(c2)
		else:
			res["changes"] = {}
			res["mastery_note"] = "no mastery: the spell landed but produced no effect on %s" % target.label
	else:
		res["effect"] = "none"
		res["changes"] = {}
		res["mastery_note"] = "no mastery from a %s cast" % flight.outcome
	res["mastery_after"] = snappedf(mastery(id), 0.01)
	res["seconds"] = snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.01)
	return _finish(res)


## Mastery grows with diminishing returns; the first success of an untested spell is "practical understanding".
func _award(id: String, base: float, kind: String, effect: String, first: bool) -> Dictionary:
	var m := mastery(id)
	var gain := base / (1.0 + m * 0.8)
	var know := {"reaction:%s:%s:%s" % [id, kind, effect]: 1}
	if first:
		know["practical:" + id] = 1
		gain += 0.05
	return WorldState.record_activity({"id": "spell:%s" % id, "verb": "practice", "label": "%s (%s)" % [spell(id).name, effect]},
		{"skills": {id: gain}, "knowledge": know})


func _finish(res: Dictionary) -> Dictionary:
	history.append(res)
	if history.size() > 40:
		history.pop_front()
	cast_resolved.emit(res)
	print("[magic] ", JSON.stringify(res).left(400))
	return res


# ------------------------------------------------------------------ shared projectile sweep
## Move a projectile from `from` to `to` this frame: returns {} if clear, else the hit.
static func sweep(world: World3D, from: Vector3, to: Vector3, exclude: Array) -> Dictionary:
	if from.distance_to(to) < 0.0005:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude
	return world.direct_space_state.intersect_ray(q)


## Judge an impact: on target (collider owned, or close enough to the target's aim point) = hit.
static func judge(target: ReactiveElement, point: Vector3, collider: Object, spell_radius: float) -> String:
	if target == null:
		return "missed" if collider == null else "blocked"
	if collider != null and target.owns_collider(collider):
		return "hit"
	if point.distance_to(target.aim_point()) <= target.aim_radius + spell_radius:
		return "hit"
	return "blocked" if collider != null else "missed"
