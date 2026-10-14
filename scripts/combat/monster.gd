class_name Monster
extends ReactiveElement
## A hostile creature (data/monsters.json). It is a ReactiveElement, so every spell reaches it through the
## normal truthful pipeline (range, line of sight, projectile sweep, judged hit) - nothing is assumed.
## Behaviour: wander near its spawn -> notice a mage inside aggro radius -> (alert) -> close in / position
## -> attack -> give up past its leash. The ritual circle's ward keeps it out. Damage = power x spell damage
## x element resistance x 100 (x a recovery-window weakness, see below). On defeat it comes apart and drops
## physical loot; the defeat is recorded for the mage whose spell landed it.
##
## Milestone J creatures (def.body + def.attacks) fight fairly and readably:
##   windup   - every attack is TELEGRAPHED first (the body winds up; slams and sweeps mark their ground,
##              bolts are visible in flight): an AttackHazard resolves against where each mage really is
##   strike   - the blow / bolt / dive itself
##   recover  - a window after a heavy attack: it cannot attack and takes extra damage ("exposed")
##   stagger  - a hard enough hit interrupts it (heavy creatures shrug off small hits while winding up)
##   rest     - out of stamina: it backs off and catches its breath before attacking again
##   retreat  - (flyers) once badly hurt, it flies off to recover for a moment, then returns
## Legacy creatures (no def.attacks) keep their original single attack.

signal defeated(monster: Monster, by: String)
signal attacked(monster: Monster, mage: WorldCharacter, amount: float)

var def := {}
static var last_fled := {}          # the last creature that fled from a fire (kind, uid)
var gone := false                  # walked away out of the world (fled), not defeated
var hp := 100.0
var max_hp := 100.0
var home := Vector3.ZERO
var mstate := "wander"            # wander | alert | chase | attack | windup | strike | recover | stagger | rest | retreat | return | dying
var target_mage: WorldCharacter = null
var last_attacker: WorldCharacter = null
var hit_by := {}                  # mage id -> true for every mage whose spell landed on it
var main: Node
var body: Node3D                  # legacy procedural body, or the CreatureBody
var creature: CreatureBody = null
var stamina := 1.0
var hazard: AttackHazard = null   # the telegraphed attack in progress (if any)
var _attack := {}                 # the attack being performed
var _attack_cd := {}              # attack kind -> seconds until ready
var _state_t := 0.0
var _retreated := false
var _last_strike_t := -99.0
var _eyes: Array[MeshInstance3D] = []
var _legs: Array[Node3D] = []
var _core_mat: StandardMaterial3D
var _wander_to := Vector3.ZERO
var _wander_t := 0.0
var _cd := 0.0
var _t := 0.0
var _hurt := 0.0
var _stagger := 0.0               # struck: it reels for a moment (no moving, no attacking)
var _spell := ""
var _strafe_dir := 1.0
var _rng := RandomNumberGenerator.new()
var move_vel := Vector3.ZERO      # observed motion (what a caster leading her shot can see)
var _prev_pos := Vector3.INF
var state_history: Array = []     # [t, state] of its behaviour changes (diagnostics, tests)
# Milestone K8 territory life (data/habitats.json through Territory). routine: patrol | guard | rest |
# investigate | withdraw. Ground creatures follow navmesh paths (round trunks and boulders); flyers go straight.
var territory: Territory = null
var routine := ""
var routine_history: Array = []
var _routine_t := 0.0
var _patrol_i := 0
var _pause_t := 0.0
var _look_t := 0.0
var _noise := Vector3.INF
var _noise_kind := ""
var _tpath := PackedVector3Array()
var _tpi := 0
var _tgoal := Vector3.INF
var _tplan_t := 0.0
var _perception := 1.0
var _prev_routine := "patrol"
## V3 Part XIII: control effects the mages' families put on it (data-driven from the spell: bind_s / daze_s / push)
var _bound := 0.0                  # held by roots: no moving, no attacking, a struggle
var _bound_by := ""
var controls: Array = []           # [t, kind, seconds] of binds / dazes / pushes it took (diagnostics, tests)
## Human rivals (AmbushDirector): a scene can drive them before the fight ("scripted": walk to a mark while talking,
## face someone), and they can give up: "yielded" (kneels, drops the weapon) or "fleeing" (runs off, gone).
var script_goal := Vector3.INF
var script_speed := 1.4
var script_face: Node3D = null
var script_anim := ""
var afterimages := 0               # ghost copies left behind by its fast dashes (diagnostics, tests)


## Fight tempo (the developer: "their movements should be fast"): creatures close in faster than they wander, and
## their wind-ups are snappier - still telegraphed (the marks show, a quick mage can still dodge).
const CHASE_TEMPO := 1.35
const WINDUP_TEMPO := 0.85


func setup_monster(p_main: Node, kind_id: String, uid: String, at: Vector3, d: Dictionary) -> void:
	main = p_main
	d = d.duplicate(true)
	for a in d.get("attacks", []):
		if (a as Dictionary).has("windup"):
			a["windup"] = float(a.windup) * WINDUP_TEMPO
	def = d
	id = uid
	kind = kind_id
	label = "the %s" % String(d.name).to_lower()
	max_hp = float(d.hp)
	hp = max_hp
	home = at
	aim_radius = float(d.radius) + 0.15
	aim_offset = Vector3(0, float(d.get("aim_height", maxf(float(d.float), 0.45 if kind_id != "hollow_sentinel" else 1.4))), 0)
	supports = ["arcane", "umbral", "wind", "water", "fire", "mist", "rune", "eclipse", "nature"]
	_rng.seed = hash(uid)
	_strafe_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_build()
	add_to_group("avoid")
	# a solid body on physics layer 2: mages cannot walk through it; navmesh baking and the camera ignore it
	var bodyc := AnimatableBody3D.new()
	bodyc.name = "Animated_Collider"
	bodyc.sync_to_physics = false
	bodyc.collision_layer = 2
	bodyc.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = float(d.radius) * 0.8
	cap.height = maxf(cap.radius * 2.0 + 0.1, float(d.get("height", 1.0 if kind_id != "hollow_sentinel" else 2.2)))
	cs.shape = cap
	cs.position.y = cap.height * 0.5 + (float(d.float) - 0.4 if float(d.float) > 0.0 else 0.0)
	bodyc.add_child(cs)
	add_child(bodyc)
	bodies.append(bodyc)
	global_position = at
	_wander_to = at
	_sync()


func _sync() -> void:
	state = {"health": "%d%%" % int(100.0 * hp / max_hp), "behaviour": mstate, "creature": def.get("name", kind)}


## What a mage can observe about it: what it looks like, how hurt it seems and what it is visibly doing
## (winding up, recovering, catching its breath) - not its numbers.
func observed_state() -> Dictionary:
	var f := hp / max_hp
	var o := {"looks": def.get("describe", ""), "condition": "unhurt" if f > 0.95 else "wounded" if f > 0.4 else "badly hurt" if f > 0.0 else "dissolving",
		"behaviour": mstate}
	if mstate == "windup":
		o["doing"] = "winding up an attack"
	elif mstate == "recover":
		o["doing"] = "stuck in its follow-through (exposed)"
	elif mstate == "rest":
		o["doing"] = "catching its breath"
	return o


func tier() -> String:
	return String(def.get("tier", "weak"))


func alive() -> bool:
	return hp > 0.0 and mstate != "dying" and not gone


func aim_point() -> Vector3:
	if creature:
		return creature.aim_point()
	return global_position + aim_offset


## How far its attacks reach (what a mage learns by watching it fight).
func reach() -> float:
	var r := 0.0
	for a in _attacks():
		r = maxf(r, float(a.get("range", 2.0)))
	return r


func is_melee() -> bool:
	return reach() < 4.0


## A visible opening: it just finished an attack or is stuck/staggered/resting.
func observed_opening() -> bool:
	return mstate in ["recover", "stagger", "rest", "bound"] or (_t - _last_strike_t) < 0.9


func _attacks() -> Array:
	if def.has("attacks"):
		return def.attacks
	return [def.attack]


# ------------------------------------------------------------------ taking magic
func react(element: String, power: float, point: Vector3, spell_id: String) -> Dictionary:
	_spell = spell_id
	var r := super.react(element, power, point, spell_id)
	# V3 Part XIII: what the spell DOES to it besides hurting it, from the spell's data - roots hold it, a rift
	# dazes it, a gust shoves it. Only when the hit was real and it is still standing.
	var sp := MagicSystem.spell(spell_id)
	if alive() and r.get("effect", "none") not in ["none", "defeated"]:
		if sp.has("bind_s") and bind(float(sp.bind_s) * (0.75 + 0.25 * minf(power, 1.0)), spell_id):
			r["effect"] = "bound"
			r["detail"] = "%s was caught: roots closed round its legs and held it" % label
			r["bound_s"] = snappedf(_bound, 0.1)
		if sp.has("daze_s") and daze(float(sp.daze_s) * (0.7 + 0.3 * minf(power, 1.0))):
			r["effect"] = "dazed" if r.get("effect", "") != "bound" else "bound"
			r["detail"] = String(r.get("detail", "")) + "; it reeled, dazed, in the rift's light"
			r["dazed_s"] = snappedf(_stagger, 0.1)
		if sp.has("push"):
			var dir := _flat(aim_point() - point)
			if dir.length() < 0.2:
				dir = _flat(MagicSystem.last_cast_dir)
			var moved := push(dir.normalized(), float(sp.push) * (0.6 + 0.6 * minf(power, 1.2)))
			if moved > 0.05:
				r["detail"] = String(r.get("detail", "")) + "; the gust shoved it back %.1f m" % moved
				r["pushed_m"] = snappedf(moved, 0.01)
	return r


func _hit(element: String, power: float) -> Dictionary:
	if not alive():
		return {"effect": "none", "detail": "%s is already fading" % label}
	var mult := float(def.get("resist", {}).get(element, 1.0))
	var dmg := power * float(MagicSystem.spell(_spell).get("damage", 1.0) if _spell != "" else 1.0) * mult * 100.0
	return apply_damage(dmg, element)


## Also used by fusions (extra damage that is not a spell of its own).
func apply_damage(dmg: float, element: String) -> Dictionary:
	var exposed := mstate == "recover"
	if exposed:
		dmg *= float(def.get("exposed_mult", 1.0))
	hp = maxf(0.0, hp - dmg)
	TrailerCam.punch(clampf(0.22 + dmg / maxf(max_hp, 1.0) * 1.6, 0.2, 0.6))
	_hurt = 0.35
	if creature:
		creature.flash(clampf(dmg / (max_hp * 0.25), 0.4, 1.0))
	var who: String = last_attacker.character_id if last_attacker else ""
	if territory:
		territory.spawner.hear(global_position, 14.0, "fight")
		var b := beh()
		if alive() and hp > 0.0 and float(def.float) < 0.5 and bool(b.get("retreat_to_lair", false)) and territory.lair_center() != Vector3.INF \
				and hp < max_hp * float(b.get("retreat_hp", 0.0)) and routine != "withdraw" and territory.lair_center().distance_to(_flat(global_position)) > 6.0:
			_cancel_hazard()
			target_mage = null
			_set_routine("withdraw")
			_set_state("return")
			_sync()
			return {"effect": "struck", "detail": "%s broke off and fled toward its den" % label, "damage": snappedf(dmg, 0.1), "health": state.health, "exposed": exposed, "fled": true}
	if last_attacker and alive() and mstate in ["wander", "return", "rest"]:
		target_mage = last_attacker        # being struck makes it turn on whoever did it
		_set_state("alert" if creature and mstate != "rest" else "chase")
	# poise: a heavy creature winding up only flinches if the hit is strong; otherwise it reels
	var interrupt := dmg >= max_hp * float(def.get("poise", 0.0))
	if interrupt and alive() and mstate not in ["recover", "retreat"]:
		_cancel_hazard()
		_stagger = float(def.get("stagger_s", 0.6))
		if creature:
			_set_state("stagger")
	var r := float(def.get("resist", {}).get(element, 1.0))
	var note := " (it shrugged much of it off)" if r < 0.75 else (" (it reeled: a weakness)" if r > 1.2 else "")
	if exposed and float(def.get("exposed_mult", 1.0)) > 1.0:
		note += " (struck while it was exposed)"
	_sync()
	if hp <= 0.0:
		_die(who)
		var loot := _roll_loot()
		return {"effect": "defeated", "detail": ("%s went down, knocked out%s" if bool(def.get("humanoid", false)) else "%s came apart in light%s") % [label, note], "damage": snappedf(dmg, 0.1), "loot": loot, "exposed": exposed,
			"defeat": {"activity": {"id": "defeat:" + kind, "verb": "defeat", "label": "Defeated %s" % def.name, "target": id},
				"effects": {"knowledge": {"defeated:" + kind: 1}}}}
	return {"effect": "struck", "detail": "%s was struck%s" % [label, note], "damage": snappedf(dmg, 0.1), "health": state.health, "exposed": exposed}


func _react_arcane(p: float, _pt: Vector3) -> Dictionary: return _hit("arcane", p)
func _react_umbral(p: float, _pt: Vector3) -> Dictionary: return _hit("umbral", p)
func _react_wind(p: float, _pt: Vector3) -> Dictionary: return _hit("wind", p)
func _react_water(p: float, _pt: Vector3) -> Dictionary: return _hit("water", p)
func _react_fire(p: float, _pt: Vector3) -> Dictionary: return _hit("fire", p)
func _react_mist(p: float, _pt: Vector3) -> Dictionary: return _hit("mist", p)
func _react_rune(p: float, _pt: Vector3) -> Dictionary: return _hit("rune", p)
func _react_eclipse(p: float, _pt: Vector3) -> Dictionary: return _hit("eclipse", p)
func _react_nature(p: float, _pt: Vector3) -> Dictionary: return _hit("nature", p)


# ------------------------------------------------------------------ control effects (V3 Part XIII)
## Roots close round it: it cannot move or attack until they wither. A creature high in the air is out of
## reach of roots; a heavy one with real poise breaks them sooner.
func bind(seconds: float, by := "") -> bool:
	if not alive() or seconds <= 0.0 or float(def.float) > 1.0:
		return false
	_cancel_hazard()
	_bound = seconds * (1.0 - 0.5 * float(def.get("poise", 0.0)))
	_bound_by = by
	controls.append([snappedf(_t, 0.01), "bind", snappedf(_bound, 0.1)])
	_set_state("bound")
	_sync()
	return true


## A short daze: it reels (no moving, no attacking) and its attack is lost.
func daze(seconds: float) -> bool:
	if not alive() or seconds <= 0.0:
		return false
	_cancel_hazard()
	_stagger = maxf(_stagger, seconds)
	controls.append([snappedf(_t, 0.01), "daze", snappedf(_stagger, 0.1)])
	if creature:
		_set_state("stagger")
	_sync()
	return true


## Shoved along `dir` (flat): the body really travels (clamped to walkable ground for a ground creature) and it
## loses a beat. Returns the distance really covered.
func push(dir: Vector3, dist: float) -> float:
	if not alive() or dist <= 0.0:
		return 0.0
	var d := _flat(dir).normalized()
	var dest := global_position + d * dist
	if float(def.float) < 0.5 and main and main.world:
		var np := NavigationServer3D.map_get_closest_point(main.world.get_world_3d().navigation_map, dest)
		if Vector2(np.x - dest.x, np.z - dest.z).length() > 0.6:
			dest = global_position + d * dist * 0.35       # a tree or a wall behind it: it goes only so far
		else:
			dest = Vector3(np.x, dest.y, np.z)
	if main and main.world and main.world.has_method("ground_at"):
		dest.y = float(main.world.ground_at(dest.x, dest.z)) + (global_position.y - (float(main.world.ground_at(global_position.x, global_position.z))))
	var moved := _flat(dest - global_position).length()
	_stagger = maxf(_stagger, 0.35)
	if creature and mstate not in ["bound", "dying"]:
		_set_state("stagger")
	var tw := create_tween()
	tw.tween_property(self, "global_position", dest, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	controls.append([snappedf(_t, 0.01), "push", snappedf(moved, 0.01)])
	return moved


func _roll_loot() -> Array:
	var out := []
	for l in def.get("loot", []):
		if _rng.randf() <= float(l.chance):
			out.append({"item": l.item, "count": _rng.randi_range(int(l.count[0]), int(l.count[1]))})
	var ground := global_position
	if main and main.world and main.world.has_method("ground_at"):
		ground.y = float(main.world.ground_at(ground.x, ground.z))
	for l in out:
		LootPickup.drop(get_parent(), ground + Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6)), l.item, int(l.count), kind)
	return out


func _die(by: String) -> void:
	TrailerCam.punch(1.0)
	_cancel_hazard()
	mstate = "dying"
	_sync()
	defeated.emit(self, by)
	var pal: Array = def.color
	if creature and bool(def.get("humanoid", false)):
		_knocked_out()           # people are never killed: they go down, and later get up and limp away
		return
	if creature:
		_dissolve_creature()
		return
	FX.burst(get_parent(), aim_point(), 70, 1.4, FX.pm_motes("arcane", "burst"), FX.mote_mesh(0.06))
	FX.burst(get_parent(), aim_point(), 18, 1.8, FX.pm_puff("smoke"), FX.puff_mesh(0.6))
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3.ONE * 0.05, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	if _core_mat:
		_core_mat.emission = Color(pal[0], pal[1], pal[2]).lerp(Color.WHITE, 0.6)


## A human rival beaten: falls (the death clip as a fall), lies still, then gets up slowly and walks off - gone.
func _knocked_out() -> void:
	if creature is ClipRig:
		(creature as ClipRig).drop_weapons()
	creature.play("defeat")
	FX.burst(get_parent(), global_position + Vector3(0, 0.2, 0), 10, 0.9, FX.pm_puff("dust"), FX.puff_mesh(0.35))
	await get_tree().create_timer(7.0).timeout
	if not is_inside_tree():
		return
	creature.play("get_up")
	await get_tree().create_timer(maxf(1.2, (creature as ClipRig).clip_length("get_up") if creature is ClipRig else 1.5)).timeout
	if not is_inside_tree():
		return
	creature.play("walk")
	gone = true
	var away := _flat(global_position - (target_mage.global_position if target_mage and is_instance_valid(target_mage) else home)).normalized()
	if away.length() < 0.1:
		away = Vector3.FORWARD
	var walked := 0.0
	while walked < 26.0 and is_inside_tree():
		var dt := get_physics_process_delta_time()
		var nxt := global_position + away * 1.3 * dt
		if main and main.world and main.world.has_method("ground_at"):
			nxt.y = lerpf(global_position.y, float(main.world.ground_at(nxt.x, nxt.z)), minf(1.0, dt * 8.0))
		global_position = nxt
		rotation.y = lerp_angle(rotation.y, atan2(away.x, away.z), 1.0 - exp(-4.0 * dt))
		_sync()
		walked += 1.3 * dt
		await get_tree().physics_frame
	queue_free()


func _dissolve_creature() -> void:
	for b in bodies:
		if is_instance_valid(b):
			b.collision_layer = 0
	await creature.collapse()
	if not is_inside_tree():
		return
	FX.burst(get_parent(), aim_point(), 60, 1.4, FX.pm_motes("arcane", "burst"), FX.mote_mesh(0.05))
	FX.burst(get_parent(), global_position + Vector3(0, 0.4, 0), 14, 1.6, FX.pm_puff("smoke"), FX.puff_mesh(0.6))
	var tw := create_tween()
	tw.tween_property(creature, "scale", Vector3.ONE * 0.02, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


# ------------------------------------------------------------------ behaviour
func _set_state(s: String) -> void:
	if mstate == "dying":
		return
	mstate = s
	_state_t = 0.0
	state_history.append([snappedf(_t, 0.01), s])
	if state_history.size() > 200:
		state_history.pop_front()
	if creature:
		match s:
			"wander", "chase", "return", "attack", "rest", "retreat":
				creature.play("move" if s != "attack" and s != "rest" else "idle")
			"bound":
				creature.play("idle")
			"alert":
				creature.play("alert")
			"stagger":
				creature.play("hit")
			"windup":
				creature.play(String(_attack.get("anim_windup", "windup")))
			"strike":
				creature.play(String(_attack.get("anim_strike", "strike")))
			"recover":
				creature.play(String(_attack.get("anim_recover", "recover")))


func _physics_process(delta: float) -> void:
	_t += delta
	_state_t += delta
	if _prev_pos != Vector3.INF and delta > 0.0:
		move_vel = move_vel.lerp((global_position - _prev_pos) / delta, 0.3)
	_prev_pos = global_position
	_cd = maxf(0.0, _cd - delta)
	_hurt = maxf(0.0, _hurt - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_bound = maxf(0.0, _bound - delta)
	for k in _attack_cd:
		_attack_cd[k] = maxf(0.0, float(_attack_cd[k]) - delta)
	stamina = clampf(stamina + delta * float(def.get("stamina_regen", 0.08)), 0.0, 1.0)
	if creature:
		creature.move_speed = 0.0
	else:
		_animate(delta)
	if not alive() or main == null or main.world == null:
		return
	if creature:
		_think_j(delta)
		_sync()
		return
	if _stagger > 0.0:
		return
	if mstate == "bound":
		_struggle(delta)
		if _bound <= 0.0:
			mstate = "chase" if target_mage and is_instance_valid(target_mage) else "return"
		_sync()
		return
	match mstate:
		"wander":
			if territory:
				_territory(delta)
			else:
				_wander(delta)
		"chase", "attack":
			if _lost_target():
				target_mage = null
				mstate = "return"
			else:
				var to := target_mage.global_position
				var d := _flat(to - global_position).length()
				var rng := float(def.attack.range)
				if d > rng * 0.9:
					mstate = "chase"
					_approach(to, float(def.speed), delta)
				else:
					mstate = "attack"
					_face(to, delta)
					if _cd <= 0.0:
						_attack_legacy()
		"return":
			if _go_home(delta):
				mstate = "wander"
	_sync()


func _wander(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = _rng.randf_range(3.0, 7.0)
		_wander_to = home + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
	_move_toward(_wander_to, float(def.speed) * 0.4, delta)
	var m := _notice()
	if m:
		target_mage = m
		if creature:
			_set_state("alert")
		else:
			mstate = "chase"


func _lost_target() -> bool:
	return target_mage == null or not is_instance_valid(target_mage) or not target_mage.visible \
		or _flat(global_position - home).length() > float(def.leash) or _in_ward(target_mage.global_position, 0.0)


## Milestone J behaviour (creatures with a body + attack list).
## Old forest creatures fear fire (V3 continuation, camping): once hurt and close to a burning campfire, it backs off
## into the dark and does not come back; out of sight it is gone (the journey records it as still out there).
func _fire_fear(delta: float) -> bool:
	if mstate == "fleeing":
		var fire: Node3D = get_meta("fled_from_fire") as Node3D if has_meta("fled_from_fire") and is_instance_valid(get_meta("fled_from_fire")) else null
		var src: Vector3 = fire.global_position if fire else (get_meta("flee_from") if has_meta("flee_from") else home)
		var away := _flat(global_position - src).normalized()
		_move_toward(global_position + away * 4.0, float(def.speed) * 1.1, delta)
		_face(global_position + away * 4.0, delta, 3.0)
		if _flat(global_position - src).length() > 32.0:
			last_fled = {"kind": String(kind), "uid": id, "t": Time.get_ticks_msec()}
			gone = true            # not dead: gone - it walked out of sight into the forest
			queue_free()
		return true
	if not bool(def.get("fears_fire", false)):
		return false
	if hp > max_hp * 0.85 or mstate in ["windup", "strike", "dying"]:
		return false
	for f in get_tree().get_nodes_in_group("campfire"):
		if float(f.get("heat")) > 0.3 and _flat((f as Node3D).global_position - global_position).length() < 10.0:
			_cancel_hazard()
			set_meta("fled_from_fire", f)
			_set_state("fleeing")
			if AudioDirector.instance:
				AudioDirector.instance.play3d("monster_slam", global_position, "SFX", -10.0, "monster_flee")
			return true
	return false


## ---- scenes with human rivals (AmbushDirector) ----
## Walk (or run) to a mark under the scene's control, facing `face` when given; "idle"/"talk" when there.
func script_to(goal: Vector3, speed := 1.4, face: Node3D = null, anim := "") -> void:
	_cancel_hazard()
	if mstate != "scripted":
		_set_state("scripted")
	script_goal = goal
	script_speed = speed
	script_face = face
	script_anim = anim


## The scene lets go: it fights (`target`) or goes back to its own life.
func release_script(target: WorldCharacter = null) -> void:
	script_goal = Vector3.INF
	script_face = null
	target_mage = target
	_set_state("chase" if target else "wander")


## It gives up: kneels with its hands open and lets the weapon fall (a real prop on the ground).
func yield_fight() -> void:
	_cancel_hazard()
	target_mage = null
	_set_state("yielded")
	if creature is ClipRig:
		(creature as ClipRig).drop_weapons()


## It runs for it, away from `from`, and is gone when out of sight (not defeated).
func flee(from: Vector3) -> void:
	_cancel_hazard()
	target_mage = null
	set_meta("flee_from", from)
	_set_state("fleeing")
	if creature:
		creature.play("move")


func _think_j(delta: float) -> void:
	var flyer := float(def.float) > 0.5
	if _fire_fear(delta):
		return
	match mstate:
		"scripted":
			var moving := script_goal != Vector3.INF and _flat(script_goal - global_position).length() > 0.35
			if moving:
				_move_toward(script_goal, script_speed, delta, script_face == null)
			if script_face and is_instance_valid(script_face):
				_face(script_face.global_position, delta, 5.0)
			if creature:
				var want := ("walk" if script_speed < 3.0 else "move") if moving else (script_anim if script_anim != "" else "idle")
				if creature.state != want:
					creature.play(want)
			return
		"yielded":
			if creature and creature.state != "yield":
				creature.play("yield")
			return
		"wander":
			if territory:
				_territory(delta)
			else:
				_wander(delta)
		"alert":
			# it has seen her: a beat of recognition (readable), turning to face her
			if target_mage and is_instance_valid(target_mage):
				_face(target_mage.global_position, delta, 3.0)
			if _state_t > float(def.get("alert_s", 0.7)):
				_set_state("chase")
		"stagger":
			if _stagger <= 0.0:
				_set_state("chase" if target_mage and is_instance_valid(target_mage) else "return")
		"bound":
			_struggle(delta)
			if creature:
				creature.move_speed = 0.0
			if _bound <= 0.0:
				_set_state("chase" if target_mage and is_instance_valid(target_mage) else "return")
		"windup":
			if _lost_target():
				_cancel_hazard()
				_set_state("return")
				return
			if not bool(_attack.get("lock_aim", true)):
				_face(target_mage.global_position, delta, float(def.get("turn", 4.0)))
			if creature:
				creature.glow_level = 1.0 + 2.0 * clampf(_state_t / float(_attack.windup), 0.0, 1.0)
			if _state_t >= float(_attack.windup):
				_strike()
		"strike":
			if _state_t >= float(_attack.get("strike_s", 0.35)):
				if float(_attack.get("recover", 0.0)) > 0.0:
					_set_state("recover")
				else:
					_set_state("attack")
		"recover":
			if creature:
				creature.glow_level = 0.5
			if _state_t >= float(_attack.get("recover", 0.6)):
				if flyer and creature is ClipRig:
					(creature as ClipRig).hover = 0.0
				_set_state("attack")
		"rest":
			# out of breath: it backs off a little and recovers stamina before engaging again
			if target_mage and is_instance_valid(target_mage):
				var away := _flat(global_position - target_mage.global_position).normalized()
				_move_toward(global_position + away * 2.0, float(def.speed) * 0.35, delta)
				_face(target_mage.global_position, delta, 2.0)
			if stamina > 0.6 or _state_t > 4.0:
				_set_state("chase")
		"retreat":
			# flyers withdraw once when badly hurt, high and away, then come back
			var away2 := _flat(global_position - (target_mage.global_position if target_mage and is_instance_valid(target_mage) else home)).normalized()
			_move_toward(global_position + away2 * 4.0, float(def.speed) * 0.9, delta)
			if creature is ClipRig:
				(creature as ClipRig).hover = 1.4
			stamina = clampf(stamina + delta * 0.15, 0.0, 1.0)
			if _state_t > float(def.get("retreat_s", 4.0)):
				if creature is ClipRig:
					(creature as ClipRig).hover = 0.0
				_set_state("chase")
		"chase", "attack":
			if _lost_target():
				target_mage = null
				_set_state("return")
				return
			if flyer and not _retreated and hp < max_hp * float(def.get("retreat_below", 0.0)):
				_retreated = true
				_set_state("retreat")
				return
			var to := target_mage.global_position
			var d := _flat(to - global_position).length()
			var a := _choose_attack(d)
			if not a.is_empty():
				_begin_attack(a)
				return
			var pref := float(def.get("keep_at", 0.0))
			if pref > 0.0:
				# ranged: hold a distance and circle her (strafing), facing her
				var radial := _flat(global_position - to).normalized()
				var tangent := Vector3(-radial.z, 0, radial.x) * _strafe_dir
				var want := to + radial * pref + tangent * 2.5
				if _state_t > 3.0:
					_state_t = 0.0
					if _rng.randf() < 0.35:
						_strafe_dir = -_strafe_dir
				mstate = "chase" if absf(d - pref) > 1.5 else "attack"
				_move_toward(want, float(def.speed) * (1.0 if absf(d - pref) > 1.5 else 0.55), delta, false)
				_face(to, delta, float(def.get("turn", 4.0)))
			else:
				var rng := reach() * 0.85
				if d > rng:
					mstate = "chase"
					_approach(to, float(def.speed), delta)
				else:
					mstate = "attack"
					_face(to, delta, float(def.get("turn", 4.0)))
					if stamina < 0.2:
						_set_state("rest")
		"return":
			if _go_home(delta):
				_set_state("wander")


func _choose_attack(d: float) -> Dictionary:
	if stamina < 0.15:
		return {}
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var to := _flat(target_mage.global_position - global_position)
	var facing := fwd.dot(to.normalized()) > float(0.55)
	var best := {}
	for a in _attacks():
		if float(_attack_cd.get(a.kind, 0.0)) > 0.0 or stamina < float(a.get("stamina", 0.2)):
			continue
		if d > float(a.range) or d < float(a.get("min_range", 0.0)):
			continue
		if not facing and String(a.kind) != "slam":
			continue
		if best.is_empty() or float(a.get("priority", 1.0)) > float(best.get("priority", 1.0)):
			best = a
	return best


func _begin_attack(a: Dictionary) -> void:
	_attack = a
	stamina = clampf(stamina - float(a.get("stamina", 0.2)), 0.0, 1.0)
	_attack_cd[a.kind] = float(a.cooldown) * _rng.randf_range(0.9, 1.15)
	var to := target_mage.global_position
	var fwd := _flat(to - global_position).normalized()
	match String(a.kind):
		"slam":
			# marks the ground where she stands NOW (+ a short lead): stepping out of it avoids the blow
			var lead := target_mage.velocity * 0.15
			var center := to + Vector3(lead.x, 0, lead.z)
			center.y = float(main.world.ground_at(center.x, center.z)) if main.world.has_method("ground_at") else to.y
			hazard = _make_hazard("area", center, fwd, float(a.radius), float(a.windup), a)
		"sweep":
			var c2 := global_position
			c2.y = float(main.world.ground_at(c2.x, c2.z)) if main.world.has_method("ground_at") else global_position.y
			hazard = _make_hazard("arc", c2, fwd, float(a.range) + 0.4, float(a.windup), a)
			hazard.half_angle = deg_to_rad(float(a.get("half_angle_deg", 65.0)))
		"dive", "charge":
			# a straight swoop / rush along the line to her: the line is marked as a narrow sector
			var c3 := global_position
			c3.y = float(main.world.ground_at(c3.x, c3.z)) if main.world.has_method("ground_at") else global_position.y
			# it lands when the rush reaches her, partway through the travel (not the instant it sets off)
			hazard = _make_hazard("arc", c3, fwd, float(a.range) + 0.6, float(a.windup) + float(a.get("strike_s", 0.45)) * 0.6, a)
			hazard.half_angle = deg_to_rad(float(a.get("half_angle_deg", 12.0)))
		_:
			hazard = null       # bolts: the windup is the tell; the bolt itself is the hazard; a blink marks on arrival
	_set_state("windup")
	if AudioDirector.instance and a.has("sfx_windup"):
		AudioDirector.instance.play3d(String(a.sfx_windup), global_position, "SFX", -6.0, "monster_windup")


func _make_hazard(k: String, center: Vector3, fwd: Vector3, radius: float, t_hit: float, a: Dictionary) -> AttackHazard:
	var h := AttackHazard.new()
	h.kind = k
	h.owner_monster = self
	h.center = center
	h.dir = fwd
	h.radius = radius
	h.t_hit = t_hit
	h.vigor = float(a.vigor)
	h.heavy = bool(a.get("heavy", false))
	var c: Array = a.get("color", def.eye)
	h.color = Color(c[0], c[1], c[2])
	h.resolved.connect(_on_hazard_resolved)
	get_parent().add_child(h)
	h.set_exclude([bodies[0].get_rid()] if not bodies.is_empty() else [])
	return h


func _strike() -> void:
	var a := _attack
	_last_strike_t = _t
	if creature:
		creature.glow_level = 1.0
	_set_state("strike")
	match String(a.kind):
		"slam":
			var hex := String(a.get("style", "")) == "hex"
			var wc: Array = a.get("color", [1.0, 0.8, 0.4])
			ImpactFX.shockwave(get_parent(), hazard.center + Vector3(0, 0.05, 0) if hazard else global_position, Color(wc[0], wc[1], wc[2]) if hex else Color(1.0, 0.8, 0.4), float(a.radius) * 1.3)
			FX.burst(get_parent(), (hazard.center if hazard else global_position) + Vector3(0, 0.2, 0), 22, 1.2, FX.pm_puff("smoke"), FX.puff_mesh(0.45))
			if hex:
				FX.burst(get_parent(), (hazard.center if hazard else global_position) + Vector3(0, 0.4, 0), 40, 1.1, FX.pm_motes("umbral", "burst"), FX.mote_mesh(0.06, true))
			_play_sfx("monster_slam", -2.0)
			# the shockwave throws anyone else standing near the blow (V3 continuation: real consequences); the
			# target herself is resolved by the hazard (stepping out of the mark avoids it)
			if main.get("impacts"):
				var ex: Array = [target_mage.character_id] if target_mage else []
				main.impacts.blast((hazard.center if hazard else global_position) + Vector3(0, 0.4, 0), 0.85, float(a.radius) * 2.2,
					{"source": String(kind), "kind": "slam", "friendly": false, "exclude": ex})
		"sweep":
			_play_sfx("monster_lunge", -3.0)
		"dive", "charge":
			# it really travels along the marked line (the hazard resolves when it passes)
			var dest := global_position + (hazard.dir if hazard else Vector3.FORWARD) * float(a.range)
			var tw := create_tween()
			tw.tween_property(self, "global_position", Vector3(dest.x, global_position.y, dest.z), float(a.get("strike_s", 0.45))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			if creature is ClipRig and not bool(creature.spec.get("ground", false)):
				(creature as ClipRig).hover = -0.9
			if bool(a.get("afterimage", false)):
				_trail_afterimages(float(a.get("strike_s", 0.45)), a)
			_play_sfx("monster_lunge", -3.0)
		"blink":
			# an assassin's dash: a real, very fast run round to her flank (afterimages trail it), then the cut
			var to := target_mage.global_position
			var side := Vector3(-(to - global_position).z, 0, (to - global_position).x).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
			var dest2 := to + side * 1.25 + _flat(to - global_position).normalized() * 0.4
			var g2: float = main.world.ground_at(dest2.x, dest2.z) if main.world.has_method("ground_at") else global_position.y
			var dur := clampf(global_position.distance_to(dest2) / float(a.get("dash_speed", 16.0)), 0.12, 0.5)
			var tw2 := create_tween()
			tw2.tween_property(self, "global_position", Vector3(dest2.x, g2, dest2.z), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw2.tween_callback(func() -> void:
				if not alive() or target_mage == null or not is_instance_valid(target_mage):
					return
				rotation.y = atan2((target_mage.global_position - global_position).x, (target_mage.global_position - global_position).z)
				hazard = _make_hazard("arc", global_position, _flat(target_mage.global_position - global_position).normalized(), float(a.get("cut_range", 2.0)), 0.12, a)
				hazard.half_angle = deg_to_rad(float(a.get("half_angle_deg", 55.0)))
				_play_sfx("monster_lunge", -3.0))
			_trail_afterimages(dur + 0.1, a)
			_play_sfx("monster_lunge", -6.0)
		"bolt", "ember_bolt", "hurl":
			var from := (creature as ClipRig).mouth_point() if creature is ClipRig else aim_point() + Vector3(0, 0.6, 0)
			if String(a.get("from", "")) == "weapon" and creature is ClipRig:
				from = (creature as ClipRig).weapon_tip()
			var aim := target_mage.global_position + Vector3(0, 1.1, 0)
			var h := AttackHazard.new()
			h.kind = "projectile"
			h.owner_monster = self
			h.center = from
			h.dir = (aim - from).normalized()
			h.speed = float(a.get("speed", 10.0))
			h.max_range = float(a.range) + 3.0
			h.vigor = float(a.vigor)
			h.heavy = bool(a.get("heavy", false))
			h.style = String(a.get("style", "ember"))
			var c: Array = a.get("color", def.eye)
			h.color = Color(c[0], c[1], c[2])
			h.resolved.connect(_on_hazard_resolved)
			get_parent().add_child(h)
			h.set_exclude([bodies[0].get_rid()] if not bodies.is_empty() else [])
			_play_sfx("monster_bolt" if String(a.kind) != "hurl" else "monster_slam", -4.0 if String(a.kind) != "hurl" else -10.0)
	# a ground hazard resolves on its own timer (already at t_hit == windup); nothing else to do here
	if hazard and String(a.kind) in ["slam", "sweep", "dive"]:
		pass


## Ghost copies of its body left along a fast dash (the pose of that instant, fading out).
func _trail_afterimages(seconds: float, a: Dictionary) -> void:
	if not (creature is ClipRig):
		return
	var c: Array = a.get("ghost_color", a.get("color", [0.3, 0.2, 0.5]))
	var n := int(clampf(seconds / 0.07, 2.0, 6.0))
	for i in n:
		if not alive() or not is_inside_tree():
			return
		Afterimage.spawn(creature as ClipRig, Color(c[0], c[1], c[2]))
		afterimages += 1
		await get_tree().create_timer(seconds / n).timeout


func _cancel_hazard() -> void:
	if hazard and is_instance_valid(hazard) and not hazard.done:
		hazard.done = true
		hazard.queue_free()
	hazard = null


func _on_hazard_resolved(h: AttackHazard, struck: Array) -> void:
	if h == hazard:
		hazard = null
	for m in struck:
		if is_instance_valid(m) and not _in_ward(m.global_position, 0.0):
			_land_on(m, h.vigor, h.heavy)


func _play_sfx(name: String, db: float) -> void:
	if AudioDirector.instance:
		AudioDirector.instance.play3d(name, global_position, "SFX", db, "monster_attack")


func _notice() -> WorldCharacter:
	var best: WorldCharacter = null
	var bd := float(def.aggro_radius) * _perception
	for c in main.characters.values():
		var wc := c as WorldCharacter
		if wc == null or not wc.visible or wc.has_meta("transforming") or _in_ward(wc.global_position, 0.0):
			continue
		var d := _flat(wc.global_position - global_position).length()
		if d < bd and _can_see(wc, d):
			bd = d
			best = wc
	return best


## Trees, boulders and walls hide a mage from a creature (within 3 m it hears her anyway).
func _can_see(wc: WorldCharacter, d: float) -> bool:
	if d < 3.0 or territory == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(aim_point(), wc.global_position + Vector3(0, 1.2, 0))
	q.collision_mask = 1 | 4
	q.exclude = bodies.map(func(b): return b.get_rid())
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(wc.global_position + Vector3(0, 1.2, 0)) < 0.9


func _in_ward(p: Vector3, margin: float) -> bool:
	return main.streaming.current_id == "sanctuary" and Vector2(p.x, p.z).length() < float(Spawner.data.get("ward_radius", 12.0)) + margin


func _move_toward(to: Vector3, speed: float, delta: float, face := true) -> void:
	var dir := _flat(to - global_position)
	if dir.length() < 0.3:
		return
	var step := dir.normalized() * minf(speed * delta, dir.length())
	var nxt := global_position + step
	if _in_ward(nxt, float(def.radius)):
		return                                   # the circle's ward: it will not cross into it
	var g: float = main.world.ground_at(nxt.x, nxt.z) if main.world.has_method("ground_at") else nxt.y
	nxt.y = lerpf(global_position.y, g, minf(1.0, delta * 8.0))
	if creature:
		creature.move_speed = step.length() / maxf(delta, 1e-4)
	global_position = nxt
	if face:
		_face(to, delta, float(def.get("turn", 6.0)))


## Held by roots: it strains against them (small jerks of the body) and keeps its eyes on her.
func _struggle(delta: float) -> void:
	var jerk := sin(_t * 17.0) * sin(_t * 5.3)
	rotation.y += jerk * 0.9 * delta
	if target_mage and is_instance_valid(target_mage):
		_face(target_mage.global_position, delta, 1.5)


func _face(to: Vector3, delta: float, rate := 6.0) -> void:
	var d := _flat(to - global_position)
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-rate * delta))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## Legacy single attack (Gloomwisp, Thornback): unchanged behaviour.
func _attack_legacy() -> void:
	_cd = float(def.attack.cooldown) * _rng.randf_range(0.85, 1.15)
	var m := target_mage
	var a: Dictionary = def.attack
	match String(a.kind):
		"bolt":
			var from := aim_point()
			var p := FX.burst(get_parent(), from, 16, 0.5, FX.pm_motes("water", "burst"), FX.mote_mesh(0.05))
			var tw := create_tween()
			var to := m.global_position + Vector3(0, 1.2, 0)
			tw.tween_property(p, "global_position", to, 0.45)
			tw.tween_callback(func(): if is_instance_valid(m) and not _in_ward(m.global_position, 0.0): _land_on(m, float(a.vigor)))
		"lunge":
			var tw2 := create_tween()
			var start := global_position
			var lunge := start + _flat(m.global_position - start).normalized() * 0.9
			tw2.tween_property(self, "global_position", lunge, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw2.tween_callback(func(): if is_instance_valid(m) and _flat(m.global_position - global_position).length() < float(a.range) + 0.6: _land_on(m, float(a.vigor)))
			tw2.tween_property(self, "global_position", start, 0.35)
		"slam":
			var tw3 := create_tween()
			tw3.tween_property(body, "position:y", 0.6, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw3.tween_property(body, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw3.tween_callback(func():
				ImpactFX.shockwave(get_parent(), global_position + Vector3(0, 0.05, 0), Color(1.0, 0.8, 0.4), 3.2)
				if is_instance_valid(m) and _flat(m.global_position - global_position).length() < float(a.range) + 0.4:
					_land_on(m, float(a.vigor)))
	if AudioDirector.instance:
		AudioDirector.instance.play3d("monster_" + String(a.kind), global_position, "SFX", -4.0, "monster_attack")


func _land_on(m: WorldCharacter, amount: float, heavy := false) -> void:
	if m.has_meta("transforming"):
		return          # the transformation's light turns the blow aside
	attacked.emit(self, m, amount)
	if m.has_method("take_hit"):
		# how hard it lands: a light swipe flinches, a heavy blow staggers, a brute's slam can put her down
		m.take_hit(global_position, heavy, clampf(0.2 + amount * (3.2 if heavy else 1.6), 0.15, 1.0))


# ------------------------------------------------------------------ bodies
func _build() -> void:
	var col: Array = def.color
	var eye: Array = def.eye
	var c := Color(col[0], col[1], col[2])
	var e := Color(eye[0], eye[1], eye[2])
	var bd: Dictionary = def.get("body", {})
	if String(bd.get("type", "")) == "sentinel" and ResourceLoader.exists(SentinelRig.GLB):
		var sr := SentinelRig.new()
		sr.name = "Animated_Body"
		add_child(sr)
		sr.build(e)
		sr.footfall.connect(_on_footfall)
		creature = sr
		body = sr
		return
	if String(bd.get("type", "")) == "clip" and ResourceLoader.exists(String(bd.get("glb", ""))):
		var cr := ClipRig.new()
		cr.name = "Animated_Body"
		add_child(cr)
		cr.build(bd, e)
		cr.position.y = float(def.float)
		creature = cr
		body = cr
		return
	_build_legacy(c, e)


func _on_footfall(at: Vector3, weight: float) -> void:
	if not is_inside_tree() or main == null or main.world == null:
		return
	var g := at
	if main.world.has_method("ground_at"):
		g.y = float(main.world.ground_at(at.x, at.z))
	FX.burst(get_parent(), g + Vector3(0, 0.08, 0), int(6 * weight), 0.8, FX.pm_puff("smoke"), FX.puff_mesh(0.22))
	if AudioDirector.instance and weight > 0.5:
		AudioDirector.instance.play3d("monster_slam", g, "SFX", -22.0 + weight * 4.0, "footfall")


func _build_legacy(c: Color, e: Color) -> void:
	body = Node3D.new()
	body.name = "Animated_Body"     # "Animated" keeps it out of the layout hash
	add_child(body)
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = c
	_core_mat.roughness = 0.6
	_core_mat.emission_enabled = true
	_core_mat.emission = c * 0.4
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = e
	eye_mat.emission_enabled = true
	eye_mat.emission = e
	eye_mat.emission_energy_multiplier = 3.0
	match kind:
		"gloomwisp":
			_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_core_mat.albedo_color = Color(c, 0.55)
			_core_mat.emission = c
			_core_mat.emission_energy_multiplier = 2.2
			_core_mat.rim_enabled = true
			_core_mat.rim = 1.0
			var core := _sphere(0.28, _core_mat)
			core.position.y = float(def.float)
			body.add_child(core)
			var inner := _sphere(0.12, eye_mat)
			inner.position.y = float(def.float)
			body.add_child(inner)
			_eyes.append(inner)
			var tail := FX.particles(26, 1.2, FX.pm_motes("water", "trail"), FX.mote_mesh(0.07))
			tail.position.y = float(def.float)
			tail.emitting = true
			body.add_child(tail)
			var l := FX.light(c, 0.9 * float(RenderProfile.get_setting("magic_light_scale")), 4.0)
			l.position.y = float(def.float)
			body.add_child(l)
		"thornback":
			_core_mat.roughness = 0.9
			var shell := _sphere(0.5, _core_mat)
			shell.scale = Vector3(1.0, 0.55, 1.6)
			shell.position.y = 0.55
			body.add_child(shell)
			var spike_mat := StandardMaterial3D.new()
			spike_mat.albedo_color = Color(0.22, 0.18, 0.1)
			spike_mat.roughness = 0.8
			for i in 7:
				var sp := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.07
				cm.height = 0.38 - absf(i - 3) * 0.04
				sp.mesh = cm
				sp.material_override = spike_mat
				sp.position = Vector3(0, 0.92 - absf(i - 3) * 0.04, -0.6 + i * 0.2)
				sp.rotation.x = -0.35
				body.add_child(sp)
			for side in [-1.0, 1.0]:
				for k in 3:
					var hip := Node3D.new()
					hip.position = Vector3(side * 0.42, 0.5, -0.35 + k * 0.35)
					body.add_child(hip)
					var leg := MeshInstance3D.new()
					var lm := CylinderMesh.new()
					lm.top_radius = 0.04
					lm.bottom_radius = 0.02
					lm.height = 0.7
					leg.mesh = lm
					leg.material_override = spike_mat
					leg.position = Vector3(side * 0.22, -0.22, 0)
					leg.rotation.z = side * 0.9
					hip.add_child(leg)
					_legs.append(hip)
			for side in [-1.0, 1.0]:
				var ey := _sphere(0.06, eye_mat)
				ey.position = Vector3(side * 0.16, 0.66, 0.78)
				body.add_child(ey)
				_eyes.append(ey)
		_:
			# a creature whose body asset is missing: a plain stand-in (never crash a stream)
			var core2 := _sphere(float(def.radius), _core_mat)
			core2.position.y = maxf(float(def.float), float(def.radius))
			body.add_child(core2)


func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "gloomwisp" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _animate(delta: float) -> void:
	if body == null or mstate == "dying":
		return
	var moving := mstate in ["chase", "return", "wander"]
	match kind:
		"gloomwisp":
			body.position.y = 0.18 * sin(_t * 2.4)
			body.rotation.y += delta * 0.8
		"thornback":
			var gait := _t * (11.0 if mstate == "chase" else 6.0)
			for i in _legs.size():
				_legs[i].rotation.x = (0.45 * sin(gait + i * 1.7)) if moving else 0.0
			body.position.y = 0.03 * absf(sin(gait)) if moving else 0.0
	var flash := _hurt / 0.35
	for e in _eyes:
		e.scale = Vector3.ONE * (1.0 + 0.6 * flash)
	if _core_mat:
		_core_mat.emission_energy_multiplier = (2.2 if kind == "gloomwisp" else 0.4) + 3.0 * flash


# ------------------------------------------------------------------ territory life (Milestone K8)
func beh() -> Dictionary:
	return territory.spawner.behaviour_of(kind) if territory else {}


## Called by its Territory right after it appears: a resting-rhythm creature starts at rest (by day), others on
## patrol or at the guard post.
func begin_territory_life(active: bool) -> void:
	var b := beh()
	var pts := territory.patrol_points()
	if not active and bool(b.get("rest_by_day", false)) and not territory.rest_points().is_empty():
		_set_routine("rest")
	elif not pts.is_empty():
		_patrol_i = _rng.randi() % pts.size()
		_set_routine("patrol")
	elif bool(b.get("guards_lair", false)) and territory.guard_post() != Vector3.INF:
		_set_routine("guard")
	else:
		_set_routine("patrol")


func _set_routine(r: String) -> void:
	if routine != r and routine in ["patrol", "guard"]:
		_prev_routine = routine
	routine = r
	_routine_t = 0.0
	_pause_t = 0.0
	_tgoal = Vector3.INF
	routine_history.append([snappedf(_t, 0.01), r])
	if routine_history.size() > 200:
		routine_history.pop_front()
	match r:
		"rest":
			_perception = 0.55
		"guard":
			_perception = float(beh().get("alert_radius_guard", 1.3))
		_:
			_perception = 1.0
	if creature:
		creature.play("idle" if r in ["rest", "guard"] else "move")


## A noise reached it (Territory.hear): a resting or patrolling creature goes to look.
func on_noise(pos: Vector3, nkind: String) -> void:
	if not alive() or mstate not in ["wander", "return"] or routine == "withdraw":
		return
	if routine == "investigate" and _noise != Vector3.INF and _noise.distance_to(pos) < 4.0:
		return
	_noise = pos
	_noise_kind = nkind
	_set_routine("investigate")


## Movement to a goal: ground creatures follow the navmesh (round trunks, boulders, walls); flyers go straight.
## Returns true on arrival.
func _go_to(goal: Vector3, speed: float, delta: float) -> bool:
	if _flat(goal - global_position).length() < 1.2:
		return true
	if float(def.float) > 0.5:
		_move_toward(goal, speed, delta)
		return false
	_tplan_t -= delta
	if _tgoal.distance_to(goal) > 0.8 or _tplan_t <= 0.0 or _tpi >= _tpath.size():
		var map: RID = get_world_3d().navigation_map
		var from := NavigationServer3D.map_get_closest_point(map, global_position)
		var to := NavigationServer3D.map_get_closest_point(map, goal)
		_tpath = NavQuery.path(map, from, to)
		_tpi = 0
		_tgoal = goal
		_tplan_t = 1.5
		if _tpath.size() > 1 and _tpath[0].distance_to(global_position) < 0.5:
			_tpi = 1
	if _tpath.is_empty():
		_move_toward(goal, speed, delta)
		return false
	var wp := _tpath[mini(_tpi, _tpath.size() - 1)]
	if _flat(wp - global_position).length() < 0.6 and _tpi < _tpath.size() - 1:
		_tpi += 1
		wp = _tpath[_tpi]
	_move_toward(wp, speed, delta)
	return false


## Chasing in a forest: a territory creature paths round obstacles toward the mage; others go straight.
func _approach(to: Vector3, speed: float, delta: float) -> void:
	if mstate in ["chase", "attack"]:
		speed *= CHASE_TEMPO
		to = _pack_slot(to)
	if territory and float(def.float) < 0.5:
		_go_to(to, speed, delta)
		_face(to, delta, float(def.get("turn", 6.0)))
	else:
		_move_toward(to, speed, delta)


## A pack closes in round its prey: when several creatures hunt the same mage, each takes its own side of her
## (evenly spaced by arrival order) instead of queueing behind the first.
func _pack_slot(to: Vector3) -> Vector3:
	if target_mage == null or not is_instance_valid(target_mage) or main.spawner == null:
		return to
	var hunters: Array = main.spawner.alive.filter(func(x): return is_instance_valid(x) and x.alive() and x.target_mage == target_mage)
	if hunters.size() < 2:
		return to
	hunters.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var i := hunters.find(self)
	var base_dir := _flat(global_position - target_mage.global_position).normalized()
	if base_dir.length() < 0.1:
		base_dir = Vector3.FORWARD
	var ang := TAU * float(i) / float(hunters.size())
	var ring := maxf(float(def.radius) + 1.6, reach() * 0.9)
	var slot := target_mage.global_position + Vector3.FORWARD.rotated(Vector3.UP, ang) * ring
	# far away: run straight at her; close: fan out to its own side
	var d := _flat(global_position - target_mage.global_position).length()
	return to.lerp(slot, clampf((9.0 - d) / 6.0, 0.0, 1.0))


## Going home (leashed, or withdrawing to the lair). Returns true when there.
func _go_home(delta: float) -> bool:
	var goal := home
	if territory and routine == "withdraw" and territory.lair_center() != Vector3.INF:
		goal = territory.ground(territory.lair_center())
	if territory:
		if _go_to(goal, float(def.speed) * (0.95 if routine == "withdraw" else 0.7), delta):
			if routine == "withdraw":
				_set_routine("rest")
			return true
		return false
	_move_toward(goal, float(def.speed) * 0.7, delta)
	return _flat(global_position - goal).length() < 1.5


func _territory(delta: float) -> void:
	_routine_t += delta
	var b := beh()
	var spd := float(def.speed)
	# every routine keeps watching: a mage inside the (scaled) aggro radius with a clear line is noticed
	var m := _notice()
	if m:
		target_mage = m
		if creature:
			_set_state("alert")
		else:
			mstate = "chase"
		return
	match routine:
		"rest":
			var spots: Array = territory.rest_points()
			if bool(b.get("perches", false)) and not territory.perches().is_empty():
				spots = territory.perches()
			var spot: Vector3 = territory.ground(spots[_patrol_i % spots.size()]) if not spots.is_empty() else home
			if _go_to(spot, spd * 0.5, delta):
				if creature:
					creature.move_speed = 0.0
					creature.glow_level = 0.3
				if _routine_t > 8.0:
					hp = minf(max_hp, hp + max_hp * 0.01 * delta)   # resting heals slowly
			if territory.active_now(kind) and _routine_t > 15.0 and _rng.randf() < delta * 0.08:
				_set_routine("patrol")
		"guard":
			var post := territory.ground(territory.guard_post())
			if _go_to(post, spd * 0.6, delta):
				_look_t -= delta
				if _look_t <= 0.0:
					_look_t = _rng.randf_range(3.0, 6.0)
					var pts := territory.patrol_points()
					var toward: Vector3 = pts[0] if not pts.is_empty() else territory.center()
					var dir := _flat(toward - global_position).normalized().rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
					_face(global_position + dir * 5.0, 0.4, 3.0)
				if creature:
					creature.move_speed = 0.0
			if _routine_t > 35.0:
				if not territory.active_now(kind) and bool(b.get("rest_by_day", false)):
					_set_routine("rest")
				else:
					_set_routine("patrol")
		"patrol":
			var pts := territory.patrol_points()
			if pts.is_empty():
				_wander(delta)
				return
			if _pause_t > 0.0:
				_pause_t -= delta
				if creature:
					creature.move_speed = 0.0
				_look_t -= delta
				if _look_t <= 0.0:
					_look_t = _rng.randf_range(1.2, 2.5)
					_face(global_position + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 4.0, 0.3, 2.5)
				return
			var goal: Vector3 = territory.ground(pts[_patrol_i % pts.size()])
			if _go_to(goal, spd * float(b.get("patrol_pace", 0.45)), delta):
				_patrol_i = (_patrol_i + 1) % pts.size()
				_pause_t = _rng.randf_range(2.0, 5.0)
				_look_t = 0.0
				if _patrol_i == 0:
					if not territory.active_now(kind) and bool(b.get("rest_by_day", false)) and not territory.rest_points().is_empty():
						_set_routine("rest")
					elif bool(b.get("guards_lair", false)) and territory.guard_post() != Vector3.INF and _rng.randf() < 0.6:
						_set_routine("guard")
		"investigate":
			if _noise == Vector3.INF:
				_set_routine(_prev_routine)
				return
			if _go_to(territory.ground(_noise), spd * 0.8, delta):
				if creature:
					creature.move_speed = 0.0
				_pause_t += delta
				_look_t -= delta
				if _look_t <= 0.0:
					_look_t = _rng.randf_range(1.0, 2.0)
					_face(global_position + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * 4.0, 0.3, 3.0)
				if _pause_t > 5.0:
					_noise = Vector3.INF
					_set_routine(_prev_routine)
			elif _routine_t > 40.0:
				_noise = Vector3.INF
				_set_routine(_prev_routine)
		"withdraw":
			if _go_home(delta):
				_set_routine("rest")
		_:
			_wander(delta)
