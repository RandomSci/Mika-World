class_name CombatFraming
extends RefCounted
## Combat cinematography (Milestone J) for the CameraDirector. Reads the real fight - where the followed
## mage is, which creatures are engaging her, a telegraphed blow aimed at her, a spell in flight, and the
## other mage if she is in the same fight - and returns a readable shot:
##   * a lateral "two-shot" across the mage -> opponent axis, biased behind the mage so she stays the
##     foreground subject and the opponent and the spell path read left-to-right on screen,
##   * wide enough for everyone involved (distance from their spread), never a close-up that hides combat,
##   * the 180-degree rule: it keeps the screen side it is on; it only flips when that side is blocked,
##   * slow, damped motion (no spinning, no shake); the director cuts only on entering combat.
## Signature casts use their own short beats (see `signature_shot`).


## Everything the shot must include: [{p: Vector3, w: weight}] plus the main axis.
static func subjects(dir_node, main: Node, mage: WorldCharacter) -> Dictionary:
	var pts := [{"p": mage.global_position + Vector3(0, 1.0, 0), "w": 2.0}]
	var foes := []
	var brain = main.mage_brains.get(mage.character_id)
	var fight_target: Node3D = null
	if brain:
		var cur: Dictionary = brain.current
		if cur.get("kind", "") == "hunt" and main.spawner:
			for m in main.spawner.alive:
				if is_instance_valid(m) and m.id == String(cur.get("monster", "")):
					fight_target = m
		if brain.threat and is_instance_valid(brain.threat):
			fight_target = fight_target if fight_target else brain.threat
	if fight_target == null and mage.combat_stance and main.spawner:
		# she is in a fight (her stance says so): the nearest creature engaging the area is the opponent
		var bd := 20.0
		for m in main.spawner.alive:
			if is_instance_valid(m) and (m as Monster).alive() and m.global_position.distance_to(mage.global_position) < bd:
				bd = m.global_position.distance_to(mage.global_position)
				fight_target = m
	if main.spawner:
		for m in main.spawner.alive:
			var mon := m as Monster
			if mon == null or not is_instance_valid(mon) or not mon.alive():
				continue
			var engaged: bool = mon == fight_target or mon.target_mage == mage
			if engaged and mon.global_position.distance_to(mage.global_position) < 22.0:
				foes.append(mon)
				pts.append({"p": mon.aim_point(), "w": 1.4 if mon == fight_target else 0.8})
	# a blow telegraphed at her: its marked ground must be on screen
	for h in AttackHazard.active(main.world):
		var hz := h as AttackHazard
		if hz and hz.kind != "projectile" and hz.threatens(mage.global_position, 1.0):
			pts.append({"p": hz.center + Vector3(0, 0.3, 0), "w": 0.8})
	# the other mage, if she is fighting alongside (same creatures, close by)
	for who in main.characters:
		var other: WorldCharacter = main.characters[who]
		if other == mage or not other.visible:
			continue
		var ob = main.mage_brains.get(who)
		var fighting: bool = ob != null and String(ob.current.get("kind", "")) == "hunt"
		if fighting and other.global_position.distance_to(mage.global_position) < 14.0:
			pts.append({"p": other.global_position + Vector3(0, 1.0, 0), "w": 0.7})
	var axis := Vector3.ZERO
	if not foes.is_empty():
		var f: Node3D = fight_target if fight_target else foes[0]
		axis = Vector3(f.global_position.x - mage.global_position.x, 0, f.global_position.z - mage.global_position.z)
	return {"points": pts, "foes": foes, "axis": axis, "target": fight_target}


static func active(dir_node, main: Node, mage: WorldCharacter) -> bool:
	return not subjects(dir_node, main, mage).foes.is_empty()


## The combat shot. Returns {pos, look, fov}.
##   one opponent at range - a wide over-the-shoulder shot from behind the mage: she is the large foreground
##                           subject, the creature and the spell path read ahead of her
##   melee / several foes  - a lateral shot across the fight, sized to include everyone (never huge)
static func shot(main: Node, mage: WorldCharacter, s: Dictionary, side: float) -> Dictionary:
	var pts: Array = s.points
	# during a dodge, frame where she is GOING (the camera must never lose her mid-roll)
	var base := mage.global_position
	if not mage._dash.is_empty():
		base = (mage._dash.from as Vector3) + (mage._dash.dir as Vector3) * float(mage._dash.dist)
	var mp := base + Vector3(0, 1.1, 0)
	var axis: Vector3 = s.axis
	if axis.length() < 0.1:
		axis = -mage.global_transform.basis.z
	var foe_d := Vector3(axis.x, 0, axis.z).length()
	axis = Vector3(axis.x, 0, axis.z).normalized()
	var perp := Vector3(-axis.z, 0, axis.x) * side
	var out := {}
	if (s.foes as Array).size() <= 1 and foe_d > 3.2:
		var back := clampf(3.4 + foe_d * 0.12, 3.4, 4.8)
		var pos := base - axis * back + perp * 1.6 + Vector3(0, 1.8 + foe_d * 0.03, 0)
		var look := mp + axis * clampf(foe_d * 0.4, 1.2, 5.5) + Vector3(0, -0.1, 0)
		# wide enough that the creature stays in frame: angle between the look direction and the creature
		var to_look := (look - pos).normalized()
		var foe_p: Vector3 = (s.points[1].p if pts.size() > 1 else mp + axis * foe_d)
		var ang := rad_to_deg(acos(clampf(to_look.dot((foe_p - pos).normalized()), -1.0, 1.0)))
		out = {"pos": pos, "look": look, "fov": clampf(ang * 2.0 + 18.0, 50.0, 66.0)}
	else:
		var sum := Vector3.ZERO
		var wsum := 0.0
		for e in pts:
			sum += (e.p as Vector3) * float(e.w)
			wsum += float(e.w)
		var c := sum / maxf(wsum, 0.001)
		var spread := 0.0
		for e in pts:
			spread = maxf(spread, Vector2((e.p as Vector3).x - c.x, (e.p as Vector3).z - c.z).length())
		var dist := clampf(spread * 1.15 + 3.0, 4.2, 9.5)
		out = {"pos": c + perp * dist - axis * dist * 0.45 + Vector3(0, clampf(1.3 + dist * 0.14, 1.5, 2.8), 0),
			"look": c.lerp(mp, 0.35), "fov": clampf(48.0 + spread * 1.0, 48.0, 58.0)}
	if main.world and main.world.has_method("ground_at"):
		out.pos.y = maxf(out.pos.y, float(main.world.ground_at(out.pos.x, out.pos.z)) + 0.6)
	return out


## Is the line from the camera to the mage (and to her main opponent) clear?
static func clear(mage: WorldCharacter, pos: Vector3, s: Dictionary) -> bool:
	var space := mage.get_world_3d().direct_space_state
	var targets := [mage.global_position + Vector3(0, 1.2, 0)]
	if s.target and is_instance_valid(s.target):
		targets.append((s.target as Monster).aim_point())
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(pos, t)
		q.exclude = [mage.get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(t) > 0.8:
			return false
	return true


## Signature cast beats, keyed by the caster's cast phase (awaken | gather | release | burst | after).
## `t_in` = seconds in this beat. Returns {pos, look, fov, cut} (cut = hard cut at the beat start).
static func signature_shot(c: WorldCharacter, target: Node3D, beat: String, t_in: float, side: float, impact: Vector3) -> Dictionary:
	var p := c.global_position
	var fwd := -c.global_transform.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var right := Vector3(-fwd.z, 0, fwd.x) * side
	var face := c.chest.global_position + Vector3(0, 0.32, 0) if c.chest else p + Vector3(0, 1.45, 0)
	var hands := (c.left_hand.global_position + c.right_hand.global_position) * 0.5 if c.left_hand else p + Vector3(0, 1.2, 0)
	match beat:
		"awaken":
			# a low three-quarter front: her stance and the formation opening under her feet
			var k := clampf(t_in / 1.2, 0.0, 1.0)
			return {"pos": p + fwd * lerpf(4.2, 3.4, k) + right * 2.0 + Vector3(0, 1.05, 0), "look": p + Vector3(0, 1.0, 0), "fov": 50.0, "cut": t_in < 0.05}
		"gather":
			# push in on her face and hands as the energy builds (her expression is part of the moment)
			var k2 := clampf(t_in / 1.6, 0.0, 1.0)
			var look := face.lerp(hands, 0.45)
			# three-quarter, beside the formation (never through it): her face, her hands and the sigil
			return {"pos": look + fwd * lerpf(1.9, 1.5, k2) + right * lerpf(1.6, 1.3, k2) + Vector3(0, 0.1, 0), "look": look, "fov": lerpf(44.0, 38.0, k2), "cut": t_in < 0.05}
		"release", "flight":
			# over her shoulder, wide: the release, the path and the target all on screen
			var tgt := target.global_position + Vector3(0, 1.0, 0) if target and is_instance_valid(target) else p + fwd * 8.0
			return {"pos": p - fwd * 3.0 + right * 1.5 + Vector3(0, 1.9, 0), "look": p.lerp(tgt, 0.6) + Vector3(0, 0.9, 0), "fov": 52.0, "cut": t_in < 0.05}
		_:
			# impact: hold on what it did to the creature, from the same side (no jump across the line)
			var at := impact if impact != Vector3.INF else (target.global_position if target and is_instance_valid(target) else p + fwd * 8.0)
			var axis := Vector3(at.x - p.x, 0, at.z - p.z)
			var dist := axis.length()
			axis = axis.normalized() if dist > 0.1 else fwd
			var perp := Vector3(-axis.z, 0, axis.x) * side
			return {"pos": p.lerp(at, 0.55) + perp * clampf(dist * 0.6 + 2.5, 4.0, 10.0) + Vector3(0, 2.0, 0), "look": p.lerp(at, 0.65) + Vector3(0, 0.9, 0), "fov": 50.0, "cut": false}
