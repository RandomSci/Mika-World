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


func setup_monster(p_main: Node, kind_id: String, uid: String, at: Vector3, d: Dictionary) -> void:
	main = p_main
	def = d
	id = uid
	kind = kind_id
	label = "the %s" % String(d.name).to_lower()
	max_hp = float(d.hp)
	hp = max_hp
	home = at
	aim_radius = float(d.radius) + 0.15
	aim_offset = Vector3(0, maxf(float(d.float), 0.45 if kind_id != "hollow_sentinel" else 1.4), 0)
	supports = ["arcane", "umbral", "wind", "water", "fire", "mist", "rune", "eclipse"]
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
	return hp > 0.0 and mstate != "dying"


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
	return mstate in ["recover", "stagger", "rest"] or (_t - _last_strike_t) < 0.9


func _attacks() -> Array:
	if def.has("attacks"):
		return def.attacks
	return [def.attack]


# ------------------------------------------------------------------ taking magic
func react(element: String, power: float, point: Vector3, spell_id: String) -> Dictionary:
	_spell = spell_id
	return super.react(element, power, point, spell_id)


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
	_hurt = 0.35
	if creature:
		creature.flash(clampf(dmg / (max_hp * 0.25), 0.4, 1.0))
	var who: String = last_attacker.character_id if last_attacker else ""
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
		return {"effect": "defeated", "detail": "%s came apart in light%s" % [label, note], "damage": snappedf(dmg, 0.1), "loot": loot, "exposed": exposed,
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
	_cancel_hazard()
	mstate = "dying"
	_sync()
	defeated.emit(self, by)
	var pal: Array = def.color
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
	match mstate:
		"wander":
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
					_move_toward(to, float(def.speed), delta)
				else:
					mstate = "attack"
					_face(to, delta)
					if _cd <= 0.0:
						_attack_legacy()
		"return":
			_move_toward(home, float(def.speed) * 0.7, delta)
			if _flat(global_position - home).length() < 1.5:
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
func _think_j(delta: float) -> void:
	var flyer := float(def.float) > 0.5
	match mstate:
		"wander":
			_wander(delta)
		"alert":
			# it has seen her: a beat of recognition (readable), turning to face her
			if target_mage and is_instance_valid(target_mage):
				_face(target_mage.global_position, delta, 3.0)
			if _state_t > float(def.get("alert_s", 0.7)):
				_set_state("chase")
		"stagger":
			if _stagger <= 0.0:
				_set_state("chase")
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
					_move_toward(to, float(def.speed), delta)
				else:
					mstate = "attack"
					_face(to, delta, float(def.get("turn", 4.0)))
					if stamina < 0.2:
						_set_state("rest")
		"return":
			_move_toward(home, float(def.speed) * 0.7, delta)
			if _flat(global_position - home).length() < 1.5:
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
			hazard = null       # bolts: the windup is the tell; the bolt itself is the hazard
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
			ImpactFX.shockwave(get_parent(), hazard.center + Vector3(0, 0.05, 0) if hazard else global_position, Color(1.0, 0.8, 0.4), float(a.radius) * 1.3)
			FX.burst(get_parent(), (hazard.center if hazard else global_position) + Vector3(0, 0.2, 0), 22, 1.2, FX.pm_puff("smoke"), FX.puff_mesh(0.45))
			_play_sfx("monster_slam", -2.0)
		"sweep":
			_play_sfx("monster_lunge", -3.0)
		"dive", "charge":
			# it really travels along the marked line (the hazard resolves when it passes)
			var dest := global_position + (hazard.dir if hazard else Vector3.FORWARD) * float(a.range)
			var tw := create_tween()
			tw.tween_property(self, "global_position", Vector3(dest.x, global_position.y, dest.z), float(a.get("strike_s", 0.45))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			if creature is ClipRig:
				(creature as ClipRig).hover = -0.9
			_play_sfx("monster_lunge", -3.0)
		"bolt", "ember_bolt", "hurl":
			var from := (creature as ClipRig).mouth_point() if creature is ClipRig else aim_point() + Vector3(0, 0.6, 0)
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
	var bd := float(def.aggro_radius)
	for c in main.characters.values():
		var wc := c as WorldCharacter
		if wc == null or not wc.visible or wc.has_meta("transforming") or _in_ward(wc.global_position, 0.0):
			continue
		var d := _flat(wc.global_position - global_position).length()
		if d < bd:
			bd = d
			best = wc
	return best


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
		m.take_hit(global_position, heavy)


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
