class_name Monster
extends ReactiveElement
## A hostile creature (data/monsters.json). It is a ReactiveElement, so every spell reaches it through the
## normal truthful pipeline (range, line of sight, projectile sweep, judged hit) - nothing is assumed.
## Behaviour: wander near its spawn -> notice a mage inside aggro radius (with line of sight) -> close in
## -> attack on a cooldown (drains vigor; never kills) -> give up past its leash. The ritual circle's ward
## keeps it out. Damage = power x spell damage x element resistance x 100. On defeat it dissolves and drops
## physical loot; the defeat is recorded for the mage whose spell landed it.

signal defeated(monster: Monster, by: String)
signal attacked(monster: Monster, mage: WorldCharacter, amount: float)

var def := {}
var hp := 100.0
var max_hp := 100.0
var home := Vector3.ZERO
var mstate := "wander"            # wander | chase | attack | return | dying
var target_mage: WorldCharacter = null
var last_attacker: WorldCharacter = null
var hit_by := {}                  # mage id -> true for every mage whose spell landed on it
var main: Node
var body: Node3D
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
var _rng := RandomNumberGenerator.new()


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
	cap.height = maxf(cap.radius * 2.0 + 0.1, 1.0 if kind_id != "hollow_sentinel" else 2.2)
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


## What a mage can observe about it: what it looks like and how hurt it seems (not its numbers).
func observed_state() -> Dictionary:
	var f := hp / max_hp
	return {"looks": def.get("describe", ""), "condition": "unhurt" if f > 0.95 else "wounded" if f > 0.4 else "badly hurt" if f > 0.0 else "dissolving",
		"behaviour": mstate}


func tier() -> String:
	return String(def.get("tier", "weak"))


func alive() -> bool:
	return hp > 0.0 and mstate != "dying"


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
	hp = maxf(0.0, hp - dmg)
	_hurt = 0.35
	_stagger = float(def.get("stagger_s", 0.6))
	var who: String = last_attacker.character_id if last_attacker else ""
	if last_attacker and alive() and mstate in ["wander", "return"]:
		target_mage = last_attacker        # being struck makes it turn on whoever did it
		mstate = "chase"
	var note := " (it shrugged much of it off)" if float(def.get("resist", {}).get(element, 1.0)) < 0.75 else (" (it reeled: a weakness)" if float(def.get("resist", {}).get(element, 1.0)) > 1.2 else "")
	_sync()
	if hp <= 0.0:
		_die(who)
		var loot := _roll_loot()
		return {"effect": "defeated", "detail": "%s came apart in light%s" % [label, note], "damage": snappedf(dmg, 0.1), "loot": loot,
			"defeat": {"activity": {"id": "defeat:" + kind, "verb": "defeat", "label": "Defeated %s" % def.name, "target": id},
				"effects": {"knowledge": {"defeated:" + kind: 1}}}}
	return {"effect": "struck", "detail": "%s was struck%s" % [label, note], "damage": snappedf(dmg, 0.1), "health": state.health}


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
	for l in out:
		LootPickup.drop(get_parent(), global_position + Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6)), l.item, int(l.count), kind)
	return out


func _die(by: String) -> void:
	mstate = "dying"
	_sync()
	defeated.emit(self, by)
	var pal: Array = def.color
	FX.burst(get_parent(), aim_point(), 70, 1.4, FX.pm_motes("arcane", "burst"), FX.mote_mesh(0.06))
	FX.burst(get_parent(), aim_point(), 18, 1.8, FX.pm_puff("smoke"), FX.puff_mesh(0.6))
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3.ONE * 0.05, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	if _core_mat:
		_core_mat.emission = Color(pal[0], pal[1], pal[2]).lerp(Color.WHITE, 0.6)


# ------------------------------------------------------------------ behaviour
func _physics_process(delta: float) -> void:
	_t += delta
	_cd = maxf(0.0, _cd - delta)
	_hurt = maxf(0.0, _hurt - delta)
	_stagger = maxf(0.0, _stagger - delta)
	_animate(delta)
	if not alive() or main == null or main.world == null or _stagger > 0.0:
		return
	match mstate:
		"wander":
			_wander_t -= delta
			if _wander_t <= 0.0:
				_wander_t = _rng.randf_range(3.0, 7.0)
				_wander_to = home + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
			_move_toward(_wander_to, float(def.speed) * 0.4, delta)
			var m := _notice()
			if m:
				target_mage = m
				mstate = "chase"
		"chase", "attack":
			if target_mage == null or not is_instance_valid(target_mage) or not target_mage.visible \
					or _flat(global_position - home).length() > float(def.leash) or _in_ward(target_mage.global_position, 0.0):
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
						_attack()
		"return":
			_move_toward(home, float(def.speed) * 0.7, delta)
			if _flat(global_position - home).length() < 1.5:
				mstate = "wander"
	_sync()


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


func _move_toward(to: Vector3, speed: float, delta: float) -> void:
	var dir := _flat(to - global_position)
	if dir.length() < 0.3:
		return
	var step := dir.normalized() * minf(speed * delta, dir.length())
	var nxt := global_position + step
	if _in_ward(nxt, float(def.radius)):
		return                                   # the circle's ward: it will not cross into it
	var g: float = main.world.ground_at(nxt.x, nxt.z) if main.world.has_method("ground_at") else nxt.y
	nxt.y = lerpf(global_position.y, g, minf(1.0, delta * 8.0))
	global_position = nxt
	_face(to, delta)


func _face(to: Vector3, delta: float) -> void:
	var d := _flat(to - global_position)
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-6.0 * delta))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _attack() -> void:
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


func _land_on(m: WorldCharacter, amount: float) -> void:
	if m.has_meta("transforming"):
		return          # the transformation's light turns the blow aside
	attacked.emit(self, m, amount)


# ------------------------------------------------------------------ procedural bodies (original designs)
func _build() -> void:
	body = Node3D.new()
	body.name = "Animated_Body"     # "Animated" keeps it out of the layout hash
	add_child(body)
	var col: Array = def.color
	var eye: Array = def.eye
	var c := Color(col[0], col[1], col[2])
	var e := Color(eye[0], eye[1], eye[2])
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
		"hollow_sentinel":
			var stone := StandardMaterial3D.new()
			stone.albedo_color = c
			stone.roughness = 0.95
			var blocks := [[Vector3(0.9, 0.5, 0.6), Vector3(0, 0.3, 0)], [Vector3(1.1, 0.9, 0.7), Vector3(0, 1.05, 0)], [Vector3(0.6, 0.5, 0.5), Vector3(0, 1.85, 0)]]
			for b in blocks:
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = b[0]
				mi.mesh = bm
				mi.material_override = stone
				mi.position = b[1]
				body.add_child(mi)
			for side in [-1.0, 1.0]:
				var arm := Node3D.new()
				arm.position = Vector3(side * 0.85, 1.25, 0)
				body.add_child(arm)
				var am := MeshInstance3D.new()
				var abm := BoxMesh.new()
				abm.size = Vector3(0.32, 0.9, 0.32)
				am.mesh = abm
				am.material_override = stone
				am.position.y = -0.35
				arm.add_child(am)
				_legs.append(arm)
			var heart := _sphere(0.17, eye_mat)
			heart.position = Vector3(0, 1.1, 0.36)
			body.add_child(heart)
			_eyes.append(heart)
			var hl := FX.light(e, 1.4 * float(RenderProfile.get_setting("magic_light_scale")), 5.0)
			hl.position = Vector3(0, 1.1, 0.6)
			body.add_child(hl)


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
		"hollow_sentinel":
			for i in _legs.size():
				_legs[i].rotation.x = 0.25 * sin(_t * 1.6 + i * PI)
			body.position.y = 0.04 * sin(_t * 1.2)
	var flash := _hurt / 0.35
	for e in _eyes:
		e.scale = Vector3.ONE * (1.0 + 0.6 * flash)
	if _core_mat:
		_core_mat.emission_energy_multiplier = (2.2 if kind == "gloomwisp" else 0.4) + 3.0 * flash
