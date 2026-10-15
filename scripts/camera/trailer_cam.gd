class_name TrailerCam
extends RefCounted
## Fight cinematography like a trailer (the developer: "the camera should be following them closely like it's a
## trailer. In every single fight."). Close, moving shots that cut every few seconds, chosen from what is happening:
##   ots        over her shoulder onto the enemy (she big in the foreground, it ahead)
##   foe_ots    over the enemy's shoulder onto her (its menace in the foreground)
##   hero_low   low and close in front of her, looking up past her (heroic)
##   orbit      circling the fight at mid distance
##   wide       a wide sliding dolly when several enemies close in (the pack reads)
##   track      a close side track when she dashes / dodges (the camera keeps up with her)
## Every candidate is tested for clear lines to her and to the enemy and lifted off the ground; a blocked one is
## skipped. Big hits "punch": a short FOV kick, a decaying shake and (heavy ones) a brief slow-motion beat.

static var _punch := 0.0
static var _shake := 0.0
static var _slowmo_until := 0.0
static var log: Array = []

var shot := ""
var since := 99.0
var hold := 3.0
var _orbit_a := 0.0
var _dolly := 0.0
var _rng := RandomNumberGenerator.new()
var _side := 1.0


## A hit worth feeling: strength 0..1 (0.3 a solid blow, 0.7 a knock-down, 1.0 a kill / huge blast).
static func punch(strength: float) -> void:
	_punch = maxf(_punch, clampf(strength, 0.0, 1.0))
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))
	if strength >= 0.65 and Time.get_ticks_msec() / 1000.0 > _slowmo_until + 1.5:
		_slowmo_until = Time.get_ticks_msec() / 1000.0 + 0.28 + 0.2 * strength
		Engine.time_scale = 0.32
	log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "punch": snappedf(strength, 0.01)})
	if log.size() > 60:
		log.pop_front()


static func tick_global(delta_real: float) -> void:
	_punch = move_toward(_punch, 0.0, delta_real * 3.0)
	_shake = move_toward(_shake, 0.0, delta_real * 2.2)
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() / 1000.0 > _slowmo_until:
		Engine.time_scale = move_toward(Engine.time_scale, 1.0, delta_real * 4.0)


static func shake_offset(t: float) -> Vector2:
	var s := _shake * _shake * 0.09
	return Vector2(sin(t * 47.0) + 0.5 * sin(t * 91.0 + 1.3), cos(t * 53.0) + 0.5 * sin(t * 77.0)) * s


static func fov_kick() -> float:
	return -9.0 * _punch


func _clear(m: WorldCharacter, pos: Vector3, targets: Array) -> bool:
	# never inside or brushing a body (a mage, a creature, a rival): the lens keeps 0.9 m from everyone
	for n in m.get_tree().get_nodes_in_group("avoid"):
		var b := n as Node3D
		if b and b.is_visible_in_tree():
			var bp := b.global_position
			if Vector2(pos.x - bp.x, pos.z - bp.z).length() < 0.9 and pos.y > bp.y - 0.2 and pos.y < bp.y + 2.4:
				return false
	var space := m.get_world_3d().direct_space_state
	if CombatFraming.inside_solid(space, pos):
		return false
	for tp in targets:
		var q := PhysicsRayQueryParameters3D.create(pos, tp)
		q.collision_mask = 1 | 4      # world + rocks, boulders, trunks (layer 3): the lens is never inside them
		q.exclude = [m.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(tp) > 0.6:
			return false
	return true


func _candidate(kind: String, m: WorldCharacter, foe: Node3D, foes: Array, mate: WorldCharacter) -> Dictionary:
	var mp := m.global_position
	var mc := mp + Vector3(0, 1.25, 0)
	var fp := foe.global_position if foe else mp - m.global_transform.basis.z * 4.0
	var fh := 1.2
	if foe and foe.has_method("aim_point"):
		fh = maxf((foe.aim_point() as Vector3).y - fp.y, 0.8)
	var fc := fp + Vector3(0, fh, 0)
	var axis := Vector3(fp.x - mp.x, 0, fp.z - mp.z)
	var d := maxf(axis.length(), 0.5)
	axis = axis / d
	var perp := Vector3(-axis.z, 0, axis.x) * _side
	match kind:
		"ots":
			# far enough back and wide enough that her hair and ears frame the shot instead of filling it
			return {"pos": mp - axis * 2.3 + perp * 0.95 + Vector3(0, 1.72, 0), "look": fc.lerp(mc, 0.25), "fov": 50.0, "rate": 5.0}
		"foe_ots":
			var back := clampf(fh * 0.6 + 1.2, 1.4, 3.2)
			return {"pos": fp + axis * back - perp * 0.9 + Vector3(0, fh * 0.9 + 0.5, 0), "look": mc, "fov": 48.0, "rate": 4.5}
		"hero_low":
			return {"pos": mp + axis * 1.7 + perp * 1.25 + Vector3(0, 0.42, 0), "look": mc + Vector3(0, 0.25, 0) + axis * -0.2, "fov": 50.0, "rate": 5.0}
		"orbit":
			var cen := (mc + fc) * 0.5
			var r := clampf(d * 0.75 + 3.0, 4.0, 9.0)
			var dir := axis.rotated(Vector3.UP, _orbit_a + PI * 0.5)
			return {"pos": cen + dir * r + Vector3(0, 1.4 + r * 0.12, 0), "look": cen, "fov": 52.0, "rate": 3.5}
		"wide":
			var c := mc
			for f in foes:
				c += (f as Node3D).global_position + Vector3(0, 1.0, 0)
			c /= float(foes.size() + 1)
			var spread := 3.0
			for f in foes:
				spread = maxf(spread, (f as Node3D).global_position.distance_to(mp))
			var dist := clampf(spread * 1.1 + 4.0, 7.0, 15.0)
			return {"pos": c + perp * dist + axis * (_dolly - 0.5) * dist * 0.6 + Vector3(0, 2.6 + dist * 0.12, 0), "look": c, "fov": 58.0, "rate": 2.6}
		"track":
			var v := Vector3(m.velocity.x, 0, m.velocity.z)
			var vd := v.normalized() if v.length() > 0.5 else -m.global_transform.basis.z
			var side := Vector3(-vd.z, 0, vd.x) * _side
			return {"pos": mp + side * 3.0 + vd * 1.2 + Vector3(0, 1.3, 0), "look": mc + vd * 0.8, "fov": 56.0, "rate": 9.0}
	return {}


## The shot for this frame. s = CombatFraming.subjects(...). Returns {pos, look, fov, rate, shot, cut}.
func frame(main: Node, m: WorldCharacter, s: Dictionary, delta: float) -> Dictionary:
	since += delta
	_orbit_a += delta * 0.32
	_dolly = fmod(_dolly + delta * 0.05, 1.0)
	var foes: Array = (s.get("foes", []) as Array).filter(func(f): return is_instance_valid(f))
	var tg = s.get("target", null)
	var foe: Node3D = tg if is_instance_valid(tg) and tg is Node3D else (foes[0] if not foes.is_empty() else null)
	var mate: WorldCharacter = null
	for who in main.characters:
		var o: WorldCharacter = main.characters[who]
		if o != m and o.visible and o.global_position.distance_to(m.global_position) < 18.0:
			mate = o
	var dashing := not m._dash.is_empty() or (m.reaction and m.reaction.active and m.reaction.tier == "down")
	var want := shot
	if dashing and shot != "track":
		want = "track"
	elif since > hold or shot == "" or (shot == "track" and not dashing and since > 0.9):
		var pool := ["ots", "foe_ots", "hero_low", "orbit", "ots", "orbit"]
		if foes.size() >= 3:
			pool += ["wide", "wide", "orbit"]
		pool.erase(shot)
		want = pool[_rng.randi() % pool.size()]
		_side = -_side if _rng.randf() < 0.35 else _side
	var targets := [m.global_position + Vector3(0, 1.2, 0)]
	if foe:
		targets.append(foe.global_position + Vector3(0, 1.0, 0))
	var cand := _candidate(want, m, foe, foes, mate)
	var tries := 0
	while tries < 5 and (cand.is_empty() or not _clear(m, cand.pos, targets)):
		tries += 1
		var alts := ["orbit", "ots", "foe_ots", "hero_low", "wide"]
		want = alts[(tries + _rng.randi()) % alts.size()]
		if tries > 2:
			_side = -_side
		cand = _candidate(want, m, foe, foes, mate)
	var cut := want != shot
	if cut:
		shot = want
		since = 0.0
		hold = _rng.randf_range(2.4, 3.8)
		log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "shot": shot})
		if log.size() > 60:
			log.pop_front()
	if main.world and main.world.has_method("ground_at"):
		var gy := float(main.world.ground_at(cand.pos.x, cand.pos.z))
		cand.pos.y = maxf(cand.pos.y, gy + 0.35)
	cand["fov"] = float(cand.fov) + fov_kick()
	cand["shot"] = shot
	cand["cut"] = cut
	return cand
