class_name CombatTactics
extends RefCounted
## A mage's tactical choice in a fight, made from what SHE can perceive (Milestone J). The planner picks
## the intention; Godot's deterministic systems execute and validate it (movement on the navmesh, the
## truthful spell pipeline, attack hazards that resolve against real positions).
##
## Intentions: dodge · retreat · keep_distance · approach · reposition · cast · assist · steady (catch
## breath) · wait. Inputs: telegraphs she can see (AttackHazard.perceived_by), the creature's visible
## behaviour (winding up, recovering, staggered), distances, line of sight, her own vigor, and whether the
## other mage is being attacked. Never: hidden creatures, attacks not yet telegraphed, exact hit points.

const REACTION_S := 0.22          # nobody reacts instantly
const DODGE_S := 0.55             # duration of a dodge (roll / side-step)
const DODGE_DIST := 2.6


## Danger she can see coming at her right now: the most urgent perceived hazard that threatens her spot.
static func incoming(me: WorldCharacter, world: Node) -> AttackHazard:
	var best: AttackHazard = null
	var best_t := INF
	for h in AttackHazard.active(world):
		var hz := h as AttackHazard
		if hz == null or hz.done or hz.owner_mage == me or not hz.threatens(me.global_position) or not hz.perceived_by(me):
			continue
		var tt := hz.time_to(me.global_position)
		if tt < best_t:
			best_t = tt
			best = hz
	return best


## A safe landing spot for a dodge away from `hz`: on the navmesh, clear of the danger, not into a wall.
static func dodge_target(me: WorldCharacter, hz: AttackHazard) -> Vector3:
	var map := me.get_world_3d().navigation_map
	var base := hz.escape_dir(me.global_position)
	for ang: float in [0.0, 0.5, -0.5, 1.0, -1.0, PI]:
		var d: Vector3 = base.rotated(Vector3.UP, ang)
		for dist: float in [DODGE_DIST, DODGE_DIST * 0.7]:
			var want: Vector3 = me.global_position + d * dist
			var p := NavigationServer3D.map_get_closest_point(map, want)
			if p == Vector3.ZERO or p.distance_to(want) > 0.6:
				continue
			if hz.threatens(p, 0.1):
				continue
			if me.test_move(me.global_transform, Vector3(p.x - me.global_position.x, 0.05, p.z - me.global_position.z)):
				continue
			return p
	return Vector3.INF


## The tactical intention for this moment. `m` is the creature she is fighting, `spell` her chosen spell.
static func decide(brain, me: WorldCharacter, m: Monster, spell: String) -> Dictionary:
	var world: Node = brain.main.world
	var vigor: float = brain.mind.vigor
	# 1. something is about to land on her and she has time to react: get out of the way
	var hz := incoming(me, world)
	if hz:
		var tt := hz.time_to(me.global_position)
		if tt >= REACTION_S and not me.casting:
			var to := dodge_target(me, hz)
			if to != Vector3.INF:
				return {"intent": "dodge", "to": to, "hazard": hz, "why": "%s coming (%.1f s)" % [hz.kind, tt]}
		return {"intent": "brace", "why": "too late to move (%.2f s)" % tt}
	# 2. exhausted: withdraw to the ward
	if vigor < 0.22:
		return {"intent": "retreat", "why": "vigor %d%%" % int(vigor * 100)}
	# 3. the other mage is under attack by a creature she can see: help her (switch target)
	var ally_threat: Monster = _ally_threat(brain, me, m)
	if ally_threat:
		return {"intent": "assist", "monster": ally_threat, "why": "%s is attacking %s" % [ally_threat.label, ally_threat.target_mage.display_name]}
	if m == null or not is_instance_valid(m) or not m.alive():
		return {"intent": "wait", "why": "no target"}
	var d := Vector2(me.global_position.x - m.global_position.x, me.global_position.z - m.global_position.z).length()
	var reach := m.reach()                    # how far its blows / bolts reach (what she has seen of it)
	var s: Dictionary = MagicSystem.spell(spell)
	var spell_range := float(s.get("range", 10.0))
	var pref_min := reach + 1.5 if m.is_melee() else 4.0
	var pref_max := minf(spell_range - 1.0, pref_min + 5.0)
	# 4. it is winding up at her but its blow will not reach where she stands: fine, she can still cast
	var opening: bool = m.mstate in ["recover", "stagger"] or m.observed_opening()
	# 5. low on vigor: keep more distance, catch her breath when it is not pressing
	if vigor < 0.4 and d < pref_min + 2.0 and not opening:
		return {"intent": "keep_distance", "to": _ring_point(me, m, pref_min + 3.0), "why": "tired: keeping away"}
	if d < pref_min and m.is_melee() and not opening:
		return {"intent": "keep_distance", "to": _ring_point(me, m, pref_min + 1.0), "why": "inside its reach (%.1f m)" % d}
	if d > pref_max:
		return {"intent": "approach", "to": _ring_point(me, m, (pref_min + pref_max) * 0.5), "why": "out of range (%.1f m)" % d}
	if not brain.main.world.has_space_for_magic(me.global_position):
		return {"intent": "reposition", "to": _side_step_point(me, m), "why": "no room to cast here"}
	var v: Dictionary = brain.main.magic.validate(spell, me, m)
	if not v.get("ok", false):
		return {"intent": "reposition", "to": _side_step_point(me, m), "why": String(v.get("reason", "no clear line"))}
	if vigor < 0.5 and m.mstate == "return":
		return {"intent": "steady", "why": "it backed off: catching her breath"}
	return {"intent": "cast", "spell": spell, "opening": opening, "why": "opening" if opening else "in range (%.1f m)" % d}


static func _ally_threat(brain, me: WorldCharacter, current: Monster) -> Monster:
	if brain.main.spawner == null:
		return null
	for mon in brain.main.spawner.alive:
		var mm := mon as Monster
		if mm == null or not is_instance_valid(mm) or not mm.alive() or mm == current:
			continue
		var tm = mm.target_mage
		if tm == null or tm == me or not is_instance_valid(tm) or not (tm as WorldCharacter).visible:
			continue
		if not mm.mstate in ["attack", "windup", "chase"]:
			continue
		if me.global_position.distance_to(mm.global_position) > 18.0 or not brain.can_see(mm.global_position + Vector3(0, 1.0, 0)):
			continue
		return mm
	return null


## A point on a circle of radius r around the creature, on her side of it, on the navmesh.
static func _ring_point(me: WorldCharacter, m: Monster, r: float) -> Vector3:
	var away := Vector3(me.global_position.x - m.global_position.x, 0, me.global_position.z - m.global_position.z)
	if away.length() < 0.1:
		away = Vector3.BACK
	var map := me.get_world_3d().navigation_map
	for ang: float in [0.0, 0.35, -0.35, 0.8, -0.8]:
		var want: Vector3 = m.global_position + away.normalized().rotated(Vector3.UP, ang) * r
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if p != Vector3.ZERO and p.distance_to(want) < 1.5:
			return p
	return me.global_position


## Circle-strafe a few metres to find a clear line of sight.
static func _side_step_point(me: WorldCharacter, m: Monster) -> Vector3:
	var away := Vector3(me.global_position.x - m.global_position.x, 0, me.global_position.z - m.global_position.z)
	var r := maxf(away.length(), 4.0)
	var map := me.get_world_3d().navigation_map
	for ang: float in [0.6, -0.6, 1.1, -1.1]:
		var want: Vector3 = m.global_position + away.normalized().rotated(Vector3.UP, ang) * r
		var p := NavigationServer3D.map_get_closest_point(map, want)
		if p != Vector3.ZERO and p.distance_to(want) < 1.5:
			return p
	return me.global_position
