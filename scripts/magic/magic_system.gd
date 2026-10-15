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
var _casting := {}               # caster id -> true while that mage's cast is in flight (mages cast independently)
var busy: bool:                  # true while ANY mage is casting (viewer chat waits for a quiet moment)
	get: return not _casting.is_empty()
var history: Array = []
var _combat_words := {}          # mage -> when she last voiced a spell word in a fight (no recitation in combat)
var fusion: SpellFusion
var rng := RandomNumberGenerator.new()


static func load_catalog() -> Dictionary:
	if catalog.is_empty():
		var f := FileAccess.open("res://data/spells.json", FileAccess.READ)
		catalog = JSON.parse_string(f.get_as_text())
	return catalog


static func spell(id: String) -> Dictionary:
	return load_catalog().spells.get(id, {})


static func mastery(id: String, who := "mika") -> float:
	return float(WorldState.mind(who).skills.get(id, 0.0))


static func tier_name(m: float) -> String:
	var name := "Untested"
	for t in load_catalog().mastery_tiers:
		if m >= float(t.min):
			name = t.name
	return name


static func power_of(id: String, charge := 0.0, who := "mika") -> float:
	var s := spell(id)
	return clampf(float(s.get("base_power", 0.5)) + float(s.get("power_per_mastery", 0.3)) * minf(mastery(id, who), 3.0) + charge, 0.05, 1.6)


## How far from the aimed point a cast may land (metres): practice makes it tighter.
static func aim_error(id: String, who := "mika") -> float:
	return clampf(0.55 - 0.2 * mastery(id, who), 0.04, 0.55)


## How the incantation is voiced at this mastery: full words while learning, a single word once Adept,
## silence from Expert on (data: incantation / incantation_short; tiers from spells.json).
static func voicing(id: String, who := "mika") -> Dictionary:
	var s := spell(id)
	var m := mastery(id, who)
	var adept := 1.5
	var expert := 3.0
	for t in load_catalog().mastery_tiers:
		if t.name == "Adept": adept = float(t.min)
		if t.name == "Expert": expert = float(t.min)
	if m >= expert:
		return {"mode": "silent", "text": ""}
	if m >= adept and s.has("incantation_short"):
		return {"mode": "short", "text": String(s.incantation_short)}
	return {"mode": "full", "text": String(s.get("incantation", ""))}


static func display_name(who: String) -> String:
	Progression.load_data()
	return String(Progression.mages.get(who, {}).get("name", who.capitalize()))


static func starting_spells(who: String) -> Array:
	Progression.load_data()
	return Progression.mages.get(who, {}).get("starting_spells", ["arcane_orb"] if who == "mika" else [])


func _init() -> void:
	rng.seed = 77
	load_catalog()


func setup(m: Node) -> void:
	main = m


## Known = castable at all. Unknown spells explain what is missing (read the incantation first).
func can_cast(id: String, who := "mika") -> Dictionary:
	var s := spell(id)
	var m := WorldState.mind(who)
	if s.is_empty():
		return {"ok": false, "reason": "unknown spell '%s' (catalogue: %s)" % [id, ", ".join(load_catalog().spells.keys())]}
	if starting_spells(who).has(id) or (m.legacy and s.get("known_from_start", false)) or m.skills.has(id):
		return {"ok": true}
	var need: String = s.get("requires_knowledge", "")
	for pre in s.get("requires_all", []):
		if not m.knowledge.has(String(pre)):
			return {"ok": false, "reason": "%s cannot cast %s yet: she does not understand it (%s)" % [display_name(who), s.name, pre]}
	if need != "" and m.knowledge.has(need):
		for other in s.get("requires_mastery", {}):
			if mastery(other, who) < float(s.requires_mastery[other]):
				return {"ok": false, "reason": "%s needs %s mastery of at least %.1f first (now %.2f)" % [s.name, spell(other).name, float(s.requires_mastery[other]), mastery(other, who)]}
		return {"ok": true, "first_attempt": true}
	return {"ok": false, "reason": "%s doesn't know %s yet: she has not learned its incantation (%s)" % [display_name(who), s.name, need]}


func known_spells(who := "mika") -> Array:
	var out := []
	for id in load_catalog().spells:
		var c := can_cast(id, who)
		var s := spell(id)
		out.append({"id": id, "name": s.name, "element": s.element, "castable": c.ok, "reason": c.get("reason", ""),
			"mastery": snappedf(mastery(id, who), 0.01), "tier": tier_name(mastery(id, who)), "power": snappedf(power_of(id, 0.0, who), 0.01),
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
	var who := caster.character_id
	var res := {"spell": id, "target": target_id, "ok": false, "caster": who}
	var cc := can_cast(id, who)
	if not cc.ok:
		res["outcome"] = "refused"
		res["reason"] = cc.reason
		return _finish(res)
	if _casting.has(who) or caster.casting:
		res["outcome"] = "refused"
		res["reason"] = "already casting"
		return _finish(res)
	if not caster.is_on_floor():
		res["outcome"] = "refused"
		res["reason"] = "not standing on the ground"
		return _finish(res)
	var target: ReactiveElement = null
	var self_spell: bool = s.get("projectile", "") in ["self", "ward"]
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
	if String(s.get("projectile", "")) != "ward" and not main.world.has_space_for_magic(caster.global_position):
		# (a ward stays on her and throws nothing: it needs no room)
		res["outcome"] = "refused"
		res["reason"] = "not enough space around her to cast"
		return _finish(res)
	_casting[who] = true
	last_spell = id
	caster.set_meta("casting_spell", id)
	# a ward that covers only her front (the Gilded Mirror) is raised TOWARD the threat
	if String(s.get("projectile", "")) == "ward" and String(s.get("ward_kind", "mirror" if who == "luna" else "leaf")) == "mirror":
		var br = main.get("mage_brains").get(who) if main.get("mage_brains") else null
		if br and br.threat and is_instance_valid(br.threat):
			caster.look_at_point((br.threat as Node3D).global_position)
			var tw0 := Time.get_ticks_msec()
			while caster.current_action == "look_at" and Time.get_ticks_msec() - tw0 < 1200:
				await get_tree().process_frame
	if target:
		caster.set_meta("cast_target", target)          # she keeps turning to it while the cast plays (WorldCharacter)
	# face the target first (a cast is never thrown sideways)
	if target:
		caster.look_at_point(target.aim_point())
		var t0 := Time.get_ticks_msec()
		while caster.current_action == "look_at" and Time.get_ticks_msec() - t0 < 2500:
			await get_tree().process_frame
	var charge: float = caster.get_meta("magic_charge", 0.0)
	if charge > 0.0 and not self_spell:
		caster.remove_meta("magic_charge")
	var power := power_of(id, charge if not self_spell else 0.0, who)
	if caster.has_meta("form_power"):
		power = minf(power + float(caster.get_meta("form_power")), 1.9)   # a transformed form casts stronger
	if caster.has_meta("signature_power"):
		power = minf(power + float(caster.get_meta("signature_power")), 1.9)   # a signature cast: the full channel
		res["signature"] = true
	# story unlock: the awakened Heartstone makes the ritual circle amplify spells cast inside it
	var amplified: bool = WorldState.mind(who).knowledge.has("story:circle_amplified") and main.streaming.current_id == "sanctuary" \
		and Vector2(caster.global_position.x, caster.global_position.z).length() < 7.8
	if amplified:
		power = minf(power + 0.15, 1.75)
	var aim := Vector3.ZERO
	var fwd := -caster.global_transform.basis.z
	var aim_err := Vector3.ZERO
	if target:
		var err := aim_error(id, who)
		var perp := fwd.cross(Vector3.UP).normalized()
		aim_err = perp * rng.randf_range(-err, err) + Vector3.UP * rng.randf_range(-err, err) * 0.6
		aim = target.aim_point() + aim_err
	else:
		aim = caster.chest.global_position + fwd * minf(float(s.range), 6.0)
	last_cast_dir = Vector3(aim.x - caster.global_position.x, 0, aim.z - caster.global_position.z).normalized()
	# spoken casting: full incantation while learning, one word once Adept, silent from Expert
	var vo := voicing(id, who)
	# V3 Part 2: no recitation in an ordinary fight - the gesture and the light carry the spell. At most the one
	# word now and then (first cast of a fight, then rarely); a signature moment keeps its full words.
	if vo.text != "" and caster.combat_stance and not caster.has_meta("signature"):
		var now := Time.get_ticks_msec() / 1000.0
		var last := float(_combat_words.get(who, -999.0))
		if now - last < 90.0:
			vo = {"mode": "silent_combat", "text": ""}
		else:
			_combat_words[who] = now
			vo = {"mode": "short_combat", "text": String(spell(id).get("incantation_short", ""))}
	res["voicing"] = vo.mode
	if vo.text != "" and main.voice:
		main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), vo.text, {"latin": true, "priority": 1, "subtitle": true})
	var node: Node3D
	# in a fight (combat stance) a spell may use its quicker combat gesture instead of the full ritual one
	var clip := String(s.get("clip_combat", s.clip)) if (caster.combat_stance or caster.has_meta("signature")) else String(s.clip)
	res["clip"] = clip
	if s.has("family"):
		# V3 Part XIII: the mages' own families (Mika: SylvanSpell, Luna: UmbralSpell)
		node = caster.cast_spell(SylvanSpell if String(s.family) == "sylvan" else UmbralSpell, clip)
		if node:
			(node as FamilySpell).configure(id, s, aim, target, power, mastery(id, who))
	elif String(s.get("projectile", "")) == "lance":
		node = caster.cast_spell(CombatSpell, clip)
		if node:
			(node as CombatSpell).configure(id, s, aim, target, power, mastery(id, who))
	elif id == "arcane_orb":
		node = caster.cast_spell(ArcaneOrbSpell, clip)
		if node:
			node.set("aim_point", aim)
			node.set("target_ref", target)
			node.set("spell_id", id)
	else:
		node = caster.cast_spell(ElementalSpell, clip)
		if node:
			(node as ElementalSpell).configure(id, s, aim, target, power, mastery(id, who))
	if node:
		node.set_meta("aim_err", aim_err)
		node.set_meta("mastery", mastery(id, who))
	if node == null:
		_casting.erase(who)
		res["outcome"] = "refused"
		res["reason"] = caster.last_rejection if caster.last_rejection != "" else "the cast animation could not start"
		return _finish(res)
	var flight: Dictionary = await node.resolved
	_casting.erase(who)
	res.merge(flight)
	res["ok"] = true
	res["power"] = snappedf(power, 0.01)
	res["circle_amplified"] = amplified
	res["mastery_before"] = snappedf(mastery(id, who), 0.01)
	res["incantation"] = s.incantation
	if String(s.get("projectile", "")) == "ward":
		# a ward is judged later, by the bolts that really cross it (Ward.absorb awards that practice)
		res["effect"] = "warded"
		res["detail"] = "%s is up: %d charge(s) for %.1f s" % [s.name, int(flight.get("charges", 1)), float(flight.get("seconds", 0.0))]
		res["changes"] = _award(id, 0.015, "self", "warded", cc.get("first_attempt", false), "", who)
	elif self_spell:
		caster.set_meta("magic_charge", power * 0.5)
		res["effect"] = "charged"
		res["detail"] = "ambient power gathered: the next spell is %d%% stronger" % int(power * 50)
		res["changes"] = _award(id, 0.04, "self", "charged", cc.get("first_attempt", false), "", who)
	elif flight.outcome == "hit" and target:
		var pt: Array = flight.point
		if target is Monster:
			(target as Monster).last_attacker = caster      # before the hit resolves: a killing blow knows its caster
			(target as Monster).hit_by[who] = true
		var reaction := target.react(String(s.element), power, Vector3(pt[0], pt[1], pt[2]), id)
		if target is Monster:
			ImpactFX.play(main.world, Vector3(pt[0], pt[1], pt[2]), String(s.element), power, reaction.get("effect", "") == "defeated")
			if fusion:
				var fz := fusion.on_hit(who, id, target as Monster, Vector3(pt[0], pt[1], pt[2]))
				if not fz.is_empty():
					res["fusion"] = fz
		res["reaction"] = reaction
		res["effect"] = reaction.effect
		res["detail"] = reaction.detail
		if reaction.effect != "none":
			res["changes"] = _award(id, 0.08, target.kind, reaction.effect, cc.get("first_attempt", false), target.id, who)
			if reaction.has("defeat"):
				(res["changes"] as Dictionary).merge(WorldState.record_activity(reaction.defeat.activity, reaction.defeat.effects, who))
			if reaction.has("clue"):
				var c2 := WorldState.record_activity({"id": "clue_found", "verb": "discover", "label": target.label}, {"knowledge": {reaction.clue: 1}}, who)
				(res["changes"] as Dictionary).merge(c2)
		else:
			# a real observation too: this spell does nothing to this kind of object (no mastery, no XP)
			res["changes"] = WorldState.record_activity({"id": "spell_noeffect:%s" % id, "verb": "observe", "label": "%s on %s: nothing" % [s.name, target.label]},
				{"knowledge": {"noeffect:%s:%s" % [id, target.kind]: 1}}, who)
			res["mastery_note"] = "no mastery: the spell landed but produced no effect on %s" % target.label
	else:
		res["effect"] = "none"
		res["changes"] = {}
		res["mastery_note"] = "no mastery from a %s cast" % flight.outcome
	res["mastery_after"] = snappedf(mastery(id, who), 0.01)
	res["seconds"] = snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.01)
	return _finish(res)


## Where to send a projectile at the moment of RELEASE: the target's aim point now, plus a lead for its
## observed motion over the flight time (a practised caster leads a moving creature better), plus the
## caster's own aim error (fixed at the start of the cast). Honest: no homing, no guaranteed hits.
static func lead_aim(target: ReactiveElement, from: Vector3, speed: float, p_mastery: float, aim_err: Vector3) -> Vector3:
	var p := target.aim_point()
	var vel: Vector3 = target.get("move_vel") if target.get("move_vel") != null else Vector3.ZERO
	var t_flight := from.distance_to(p) / maxf(speed, 1.0)
	var skill := clampf(0.35 + 0.35 * p_mastery, 0.0, 1.0)
	return p + vel * t_flight * skill + aim_err


## THE FOLD STEP (the Weaver of Ways' spell, docs/WORLD_BIBLE.md): the only teleportation in production, and
## only once LEARNED (the glyph stones' theory + the Weaver's words). To a place she can see from where she stands,
## within reach (12 m + 10 m per mastery), with ground and room to stand: the world folds, her shape stays behind a
## moment as she steps across the seam. TeleportGuard records it as a learned fold, never as a violation.
func fold_step(caster: WorldCharacter, to: Vector3) -> Dictionary:
	var id := "fold_step"
	var s := spell(id)
	var who := caster.character_id
	var res := {"spell": id, "ok": false, "caster": who}
	var cc := can_cast(id, who)
	if not cc.ok:
		res["outcome"] = "refused"
		res["reason"] = cc.reason
		return _finish(res)
	if _casting.has(who) or caster.casting or not caster.is_on_floor():
		res["outcome"] = "refused"
		res["reason"] = "not now (already casting / not on her feet)"
		return _finish(res)
	var reach := float(s.get("range", 12.0)) + float(s.get("range_per_mastery", 0.0)) * mastery(id, who)
	var from := caster.global_position
	var map := caster.get_world_3d().navigation_map
	# the walkable surface itself (a temple floor, a bridge deck - not the terrain under it)
	var dest := NavigationServer3D.map_get_closest_point(map, to)
	var down := PhysicsRayQueryParameters3D.create(dest + Vector3(0, 1.5, 0), dest - Vector3(0, 1.5, 0), 1)
	down.exclude = [caster.get_rid()]
	var floor_hit := caster.get_world_3d().direct_space_state.intersect_ray(down)
	if not floor_hit.is_empty():
		dest.y = (floor_hit.position as Vector3).y
	var d := Vector2(dest.x - from.x, dest.z - from.z).length()
	if d > reach:
		res["outcome"] = "refused"
		res["reason"] = "too far to fold (%.1f m; she can fold %.1f m)" % [d, reach]
		return _finish(res)
	if d < 1.5 or dest.distance_to(Vector3(to.x, dest.y, to.z)) > 1.2:
		res["outcome"] = "refused"
		res["reason"] = "no ground to stand on there"
		return _finish(res)
	# she must SEE it: a clear line from her eyes to the place
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 1.55, 0), dest + Vector3(0, 1.2, 0), 1)
	q.exclude = [caster.get_rid()]
	if not caster.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		res["outcome"] = "refused"
		res["reason"] = "she cannot see the place: a fold to what you cannot see tears"
		return _finish(res)
	# room to stand there (a body-sized shape test)
	var sq := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.3
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, dest + Vector3(0, 1.1, 0))      # knee to crown: uneven ground is not "no room"
	sq.collision_mask = 1
	sq.exclude = [caster.get_rid()]
	var blockers := caster.get_world_3d().direct_space_state.intersect_shape(sq, 4)
	if not blockers.is_empty():
		res["outcome"] = "refused"
		res["reason"] = "no room to stand there (%s)" % ", ".join(blockers.map(func(b): return String((b.collider as Node).name) if b.collider else "?"))
		return _finish(res)
	_casting[who] = true
	last_spell = id
	caster.look_at_point(dest)
	await get_tree().create_timer(0.35).timeout
	var vo := voicing(id, who)
	if vo.text != "" and main.voice and not caster.combat_stance:
		main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), vo.text, {"latin": true, "priority": 1, "subtitle": true})
	caster.play_gesture(String(s.get("clip", "magic_attack_1h")), 0.15, 0.4)
	await get_tree().create_timer(0.45).timeout
	# the seam: a ring of light at both places, her shape left behind as she crosses
	var col := Color(0.75, 0.7, 1.0)
	for at in [from, dest]:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 3.0
		l.omni_range = 4.0
		main.world.add_child(l)
		l.global_position = at + Vector3(0, 1.0, 0)
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.9)
		tw.tween_callback(l.queue_free)
	Afterimage.spawn_model(caster.avatar, col, 0.6)
	if main.get("teleport_guard"):
		main.teleport_guard.authorize_fold(caster, from, dest)
	caster.global_position = dest + Vector3(0, 0.05, 0)
	caster.velocity = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout
	_casting.erase(who)
	res["ok"] = true
	res["outcome"] = "folded"
	res["metres"] = snappedf(from.distance_to(dest), 0.1)
	res["changes"] = _award(id, 0.08, "place", "folded", not WorldState.mind(who).knowledge.has("practical:" + id), "", who)
	return _finish(res)


## Rising Air (learned, never given): the air lifts her - up, across and down to a place she can see, at the pace
## of a slow breath (about 1.3 m/s; never a jump cut, so TeleportGuard sees ordinary motion). The way must be open
## air the whole way for a body her size, and there must be room to stand where she sets down.
func rise_to(caster: WorldCharacter, to: Vector3) -> Dictionary:
	var id := "rising_air"
	var s := spell(id)
	var who := caster.character_id
	var res := {"spell": id, "ok": false, "caster": who}
	var cc := can_cast(id, who)
	if not cc.ok:
		res["outcome"] = "refused"
		res["reason"] = cc.reason
		return _finish(res)
	if _casting.has(who) or caster.casting or caster.lifted or not caster.is_on_floor():
		res["outcome"] = "refused"
		res["reason"] = "not now (already casting / not on her feet)"
		return _finish(res)
	var m := mastery(id, who)
	var reach := float(s.get("range", 6.0)) + float(s.get("range_per_mastery", 4.0)) * m
	var lift := float(s.get("lift", 8.5)) + float(s.get("lift_per_mastery", 3.0)) * m
	var from := caster.global_position
	var space := caster.get_world_3d().direct_space_state
	var dest := NavigationServer3D.map_get_closest_point(caster.get_world_3d().navigation_map, to)
	var down := PhysicsRayQueryParameters3D.create(dest + Vector3(0, 1.5, 0), dest - Vector3(0, 1.5, 0), 1)
	down.exclude = [caster.get_rid()]
	var fh := space.intersect_ray(down)
	if not fh.is_empty():
		dest.y = (fh.position as Vector3).y
	var d := Vector2(dest.x - from.x, dest.z - from.z).length()
	if dest.distance_to(Vector3(to.x, dest.y, to.z)) > 1.2 or absf(dest.y - to.y) > 1.5:
		res["outcome"] = "refused"
		res["reason"] = "no ground to set down on there"
		return _finish(res)
	if d > reach or dest.y - from.y > lift:
		res["outcome"] = "refused"
		res["reason"] = "too far for the air to carry her (%.1f m across, %.1f m up; she can manage %.1f / %.1f)" % [d, dest.y - from.y, reach, lift]
		return _finish(res)
	# the flight: straight up, across at the higher level plus clearance, straight down
	var top := maxf(from.y, dest.y) + 0.9          # clear of a parapet or a gallery rail at the far end
	# she must see where she will set down - from the ground, or from the air as it carries her (risen, she looks
	# across; out over an edge, she looks down onto it); the open-air test below covers the whole way
	var seen := false
	for eye_at in [from + Vector3(0, 1.55, 0), Vector3(from.x, top + 1.55, from.z), Vector3(dest.x, top + 1.55, dest.z)]:
		var eye := PhysicsRayQueryParameters3D.create(eye_at, dest + Vector3(0, 1.2, 0), 1)
		eye.exclude = [caster.get_rid()]
		if space.intersect_ray(eye).is_empty():
			seen = true
			break
	if not seen:
		res["outcome"] = "refused"
		res["reason"] = "she cannot see where she would set down"
		return _finish(res)
	var path: Array = [from, Vector3(from.x, top, from.z), Vector3(dest.x, top, dest.z), dest]
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.3
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = 1
	sq.exclude = [caster.get_rid()]
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var n := maxi(1, int(a.distance_to(b) / 0.4))
		for k in range(n + 1):
			var pt := a.lerp(b, float(k) / float(n))
			if (i == 1 and k == 0) or (i == path.size() - 1 and k == n):
				pt.y += 0.25        # standing on the ground at either end is not "blocked"
			sq.transform = Transform3D(Basis.IDENTITY, pt + Vector3(0, 1.0, 0))
			var hits := space.intersect_shape(sq, 2)
			if not hits.is_empty():
				res["outcome"] = "refused"
				res["reason"] = "no open air that way (%s in the way)" % String((hits[0].collider as Node).name if hits[0].collider else "something")
				return _finish(res)
	_casting[who] = true
	last_spell = id
	caster.stop_action()
	caster.look_at_point(dest)
	var vo := voicing(id, who)
	if vo.text != "" and main.voice and not caster.combat_stance:
		main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), vo.text, {"latin": true, "priority": 1, "subtitle": true})
	caster.play_gesture("cast_quick_enter", 0.15, 0.3)
	await get_tree().create_timer(0.5).timeout
	# the air gathers under her: a ring of lifted leaves (Sylvan) or drifting dusk motes, a soft light at her feet
	var fx: GPUParticles3D
	if who == "luna":
		fx = FX.particles(36, 1.4, FX.pm_motes("umbral", "rise"), FX.mote_mesh(0.07), true)
	else:
		fx = FX.particles(40, 1.6, FX.pm_leaves("lift"), FX.leaf_mesh(0.09), true)
	fx.emitting = true
	caster.add_child(fx)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.8, 1.0, 0.85) if who != "luna" else Color(0.7, 0.6, 1.0)
	glow.light_energy = 0.0
	glow.omni_range = 3.0
	caster.add_child(glow)
	glow.position = Vector3(0, 0.2, 0)
	create_tween().tween_property(glow, "light_energy", 1.6, 0.6)
	if main.get("audio"):
		main.audio.play3d("phoenix_wing_gust", caster.global_position, "SFX", -8.0, "rising_air", 0.75)   # a soft up-draught
	caster.play_gesture("lift_off", 0.15, 0.25)
	await get_tree().create_timer(0.35).timeout
	caster.lifted = true
	caster.play_gesture("combat_idle", 0.3, 0.5)          # hands held out, holding the spell that holds her
	var flown := 0.0
	var speeds := [1.3, 1.6, 1.1]                          # up, across, settling down
	for i in range(1, path.size()):
		var a2: Vector3 = path[i - 1]
		var b2: Vector3 = path[i]
		var len := a2.distance_to(b2)
		if len < 0.05:
			continue
		if i == 2:
			caster.look_at_point(b2)
		var dur := len / float(speeds[i - 1])
		var t := 0.0
		while t < dur:
			if not is_instance_valid(caster):
				_casting.erase(who)
				return _finish(res)
			t = minf(t + get_process_delta_time(), dur)
			var k2 := t / dur
			k2 = k2 * k2 * (3.0 - 2.0 * k2)
			caster.global_position = a2.lerp(b2, k2)
			await get_tree().process_frame
		flown += len
	caster.global_position = dest + Vector3(0, 0.03, 0)
	caster.lifted = false
	caster.velocity = Vector3.ZERO
	caster.play_gesture("land_soft", 0.1, 0.4)
	var tw := create_tween()
	tw.tween_property(glow, "light_energy", 0.0, 0.6)
	tw.tween_callback(glow.queue_free)
	fx.emitting = false
	get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(fx): fx.queue_free())
	await get_tree().create_timer(0.6).timeout
	_casting.erase(who)
	res["ok"] = true
	res["outcome"] = "rose"
	res["metres"] = snappedf(flown, 0.1)
	res["height"] = snappedf(dest.y - from.y, 0.1)
	res["changes"] = _award(id, 0.08, "place", "rose", not WorldState.mind(who).knowledge.has("practical:" + id), "", who)
	return _finish(res)


## Mastery grows with diminishing returns; the first success of an untested spell is "practical understanding".
## `target_id`: the struck object, recorded so trials about specific objects ("strike all four rune
## targets") are satisfied by real hits that produced an effect, not only by the E-key interaction.
func _award(id: String, base: float, kind: String, effect: String, first: bool, target_id := "", who := "mika") -> Dictionary:
	var m := mastery(id, who)
	var gain := base / (1.0 + m * 0.8)
	var know := {"reaction:%s:%s:%s" % [id, kind, effect]: 1}
	if first:
		know["practical:" + id] = 1
		gain += 0.05
	var act := {"id": "spell:%s" % id, "verb": "practice", "label": "%s (%s)" % [spell(id).name, effect]}
	if target_id != "":
		act["target"] = target_id
	return WorldState.record_activity(act, {"skills": {id: gain}, "knowledge": know}, who)


func _finish(res: Dictionary) -> Dictionary:
	var who_c = main.characters.get(String(res.get("caster", ""))) if main and main.get("characters") else null
	if who_c and is_instance_valid(who_c) and who_c.has_meta("casting_spell"):
		who_c.remove_meta("casting_spell")
	if who_c and is_instance_valid(who_c) and who_c.has_meta("cast_target"):
		who_c.remove_meta("cast_target")
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
