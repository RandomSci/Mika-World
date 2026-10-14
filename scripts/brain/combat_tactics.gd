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
const WARD_UP_S := 0.27           # a ward's brace gesture reaches its release about here (V3 Part XIII)


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


## Her ward (V3 Part XIII): the defensive technique of her own family she can use right now (known, off
## cooldown, breath for it), or "".
static func ward_spell(brain, me: WorldCharacter) -> String:
	var who: String = brain.agent_id
	if brain.mind.vigor < 0.12 or Ward.active_for(me) != null:
		return ""
	for id in MagicSystem.load_catalog().spells:
		var s: Dictionary = MagicSystem.spell(id)
		if String(s.get("projectile", "")) != "ward" or String(s.get("caster", who)) != who:
			continue
		if brain.main.magic.can_cast(id, who).ok and brain.spell_ready(id):
			return id
	return ""


## The technique of her family that fits THIS moment, or her base spell: Mika holds a ground creature that is
## pressing in on her with roots (then keeps her distance); Luna opens a rift under a creature that stands
## still in an opening (recovering, staggered, held). Data-driven: ground spells with bind_s / daze_s.
static func family_spell(brain, me: WorldCharacter, m: Monster, base: String, opening: bool, d: float) -> String:
	var who: String = brain.agent_id
	for id in MagicSystem.load_catalog().spells:
		var s: Dictionary = MagicSystem.spell(id)
		if not s.has("family") or String(s.get("projectile", "")) != "ground" or String(s.get("caster", "")) != who:
			continue
		if not brain.main.magic.can_cast(id, who).ok or not brain.spell_ready(id) or d > float(s.range) - 0.5 or d < 1.5:
			continue
		if s.has("bind_s"):
			if float(m.def.get("float", 0.0)) <= 1.0 and m.is_melee() and m.mstate in ["chase", "attack", "windup", "alert"] and d < m.reach() + 4.5:
				return id
		elif s.has("daze_s"):
			if opening or m.mstate in ["bound", "rest", "recover", "stagger"]:
				return id
	return base


## The tactical intention for this moment. `m` is the creature she is fighting, `spell` her chosen spell.
static func decide(brain, me: WorldCharacter, m: Monster, spell: String) -> Dictionary:
	var world: Node = brain.main.world
	var vigor: float = brain.mind.vigor
	# 1. something is about to land on her and she has time to react: get out of the way - or, for a bolt
	#    she can stop, put her ward up (when tired she would rather keep her ground and her breath)
	var hz := incoming(me, world)
	if hz:
		var tt := hz.time_to(me.global_position)
		var mine := Ward.active_for(me)
		if hz.kind == "projectile" and mine != null and (mine.covers(hz.global_position) or mine.kind == "mirror"):
			# her ward is up: hold her ground (turning the mirror toward the bolt); the ward is judged when it arrives
			return {"intent": "hold", "face": hz.global_position, "turn": mine.kind == "mirror" and not mine.covers(hz.global_position), "why": "%s is up (%.1f s)" % [MagicSystem.spell(mine.spell_id).name, tt]}
		var wid := ward_spell(brain, me) if hz.kind == "projectile" else ""
		# the ward's gesture takes ~0.3 s to bring it up: it needs the bolt still well out
		if wid != "" and not me.casting and tt >= WARD_UP_S + 0.05 and (vigor < 0.45 or tt < 0.75):
			return {"intent": "ward", "spell": wid, "hazard": hz, "why": "bolt coming (%.1f s): %s" % [tt, MagicSystem.spell(wid).name]}
		if tt >= REACTION_S and not me.casting:
			var to := dodge_target(me, hz)
			if to != Vector3.INF:
				return {"intent": "dodge", "to": to, "hazard": hz, "why": "%s coming (%.1f s)" % [hz.kind, tt]}
		if wid != "" and not me.casting and tt >= WARD_UP_S + 0.02:
			return {"intent": "ward", "spell": wid, "hazard": hz, "why": "no room to move (%.2f s): %s" % [tt, MagicSystem.spell(wid).name]}
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
	# knocked down by this kind of thing before (ImpactDirector): an evasive mage keeps further off from now on
	pref_min += float(brain.mind.knowledge.get("keep_distance_bonus", 0.0))
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
	var fam := family_spell(brain, me, m, spell, opening, d)
	if fam != spell:
		return {"intent": "cast", "spell": fam, "opening": opening, "why": "%s: %s" % [MagicSystem.spell(fam).name, "it is pressing in" if MagicSystem.spell(fam).has("bind_s") else "it stands exposed"]}
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
