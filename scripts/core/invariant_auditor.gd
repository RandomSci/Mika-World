class_name InvariantAuditor
extends Node
## Catches the defects a viewer would see, automatically, while anything runs (live or test). Every new feature
## gets checked by these rules for free; each violation is logged once per subject+rule with what was measured.
##
##   at_object      using / reading something: she stands at it (the thing she reads or works on is within
##                  reach), FACES it (within FACE_MAX_DEG) and can SEE it (nothing solid between her eyes and it)
##   tool_in_hand   a resident's tool is in the hand: the prop's nearest surface is within GRIP_MAX of the palm
##   held_in_hand   a mage's held object follows her palm
##   camera         what the stream shows: the lens never looks up at her from below her waist, is never
##                  inside / against her, keeps her head in frame and does not hide her behind a wall
##   weapon         a fighter's blade: its tip never inside its own body or the ground, and in a strike it
##                  points toward the one it strikes at
##   facing         whoever attacks faces what it attacks (a creature winding up / striking; a mage casting at one)
##   on_ground      nobody floats or sinks: feet within FOOT_MAX of the ground under them (unless lifted by a
##                  spell, seated, lying, mid-dodge or travelling)
##
## Tests: `violations` (and the "[audit]" log lines) - a suite fails on any. --mktest=audit walks every area's
## interactions and the townsfolk's working hours under these rules.

const FACE_MAX_DEG := 40.0
const GRIP_MAX := 0.09
const FOOT_MAX := 0.28
const SETTLE_S := 1.4             # an interaction is judged once she has had time to settle and turn

var main: Node
var enabled := true
var violations: Array = []
var checks := {}                  # rule -> how many times it was checked
var _seen := {}                   # subject|rule -> true (log once)
var _t := 0.0
var _hidden_t := 0.0
var _cast_off_t := {}
var _arrived_t := 0.0
var _mstate_prev := {}
var _persist := {}
var _last_pos := {}


func setup(m: Node) -> void:
	main = m
	if RenderProfile.options.has("no-audit"):
		enabled = false
	WorldState.interaction_started.connect(_on_interaction)
	if BookReader.instance:
		BookReader.instance.page_shown.connect(_on_page)


func _flag(subject: String, rule: String, detail: Dictionary) -> void:
	var key := subject + "|" + rule
	if _seen.has(key):
		return
	_seen[key] = true
	var v := {"subject": subject, "rule": rule, "area": String(main.streaming.current_id) if main.get("streaming") else "", "clock": WorldState.clock_text()}
	v.merge(detail)
	violations.append(v)
	if violations.size() > 300:
		violations.pop_front()
	print("[audit] VIOLATION ", JSON.stringify(v))


func _count(rule: String) -> void:
	checks[rule] = int(checks.get(rule, 0)) + 1


## A mage's front (WorldCharacter: look_at turns her -Z to the target).
static func mage_forward(c: Node3D) -> Vector3:
	var f := -c.global_transform.basis.z
	return Vector3(f.x, 0, f.z).normalized()


# ------------------------------------------------------------------ using / reading something
func _on_interaction(it, c) -> void:
	if not enabled or not (c is WorldCharacter):
		return
	await get_tree().create_timer(SETTLE_S).timeout
	if not is_instance_valid(it) or not is_instance_valid(c) or not it.busy:
		return
	# a seat / a marked spot: she is "at it" when she is on that spot (what she faces - a teacher, a view - may
	# be metres away); otherwise at the thing itself
	if it.stand_point != null or it.sit_point != null:
		var spot: Vector3 = it.get_parent().to_global(it.sit_point if it.sit_point != null else it.stand_point)
		check_at_object(c, spot, "%s@%s" % [c.character_id, it.id], 0.9, _target_of(it))
	else:
		check_at_object(c, _target_of(it), "%s@%s" % [c.character_id, it.id], it.radius)


func _on_page(book_id: String, page: int, _data: Dictionary) -> void:
	if not enabled or page != 0 or BookReader.instance == null:
		return
	var who := String(BookReader.instance.current.get("reader", ""))
	var c = main.characters.get(who)
	var at = BookReader.instance.current.get("anchor")
	if c == null or not (at is Vector3):
		return
	check_at_object(c, at, "%s@book:%s" % [who, book_id], 1.6)


func _target_of(it) -> Vector3:
	if it.book_xf != null:
		return (it.get_parent().global_transform * (it.book_xf as Transform3D)).origin
	if it.face_point != null:
		return it.get_parent().to_global(it.face_point)
	return it.global_position


## She is at the thing, facing it, and can see it. Returns the measurement.
func check_at_object(c: WorldCharacter, target: Vector3, subject: String, reach := 2.0, look_target = null) -> Dictionary:
	_count("at_object")
	var flat := Vector2(target.x - c.global_position.x, target.z - c.global_position.z)
	var dist := flat.length()
	var fwd := mage_forward(c)
	var lt: Vector3 = look_target if look_target is Vector3 else target
	var lflat := Vector2(lt.x - c.global_position.x, lt.z - c.global_position.z)
	var ang := 0.0 if lflat.length() < 0.35 else rad_to_deg(fwd.angle_to(Vector3(lflat.x, 0, lflat.y).normalized()))
	var eye := c.global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(eye, lt, 1)
	q.exclude = [c.get_rid()]
	var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
	var blocked := not hit.is_empty() and (hit.position as Vector3).distance_to(lt) > 0.7
	var m := {"dist": snappedf(dist, 0.01), "face_deg": snappedf(ang, 0.1), "blocked_by": String((hit.collider as Node).name) if blocked and hit.collider else "",
		"pos": [snappedf(c.global_position.x, 0.1), snappedf(c.global_position.z, 0.1)], "target": [snappedf(target.x, 0.1), snappedf(target.y, 0.1), snappedf(target.z, 0.1)]}
	var limit := maxf(reach + 0.9, 2.4) if look_target == null else reach
	if dist > limit:
		_flag(subject, "at_object:too_far", m.merged({"limit": limit}))
	elif ang > FACE_MAX_DEG:
		_flag(subject, "at_object:not_facing", m)
	elif blocked:
		_flag(subject, "at_object:cannot_see", m)
	m["ok"] = dist <= limit and ang <= FACE_MAX_DEG and not blocked
	return m


# ------------------------------------------------------------------ continuous: tools, held objects, feet
func _process(delta: float) -> void:
	if not enabled or main == null:
		return
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	if main.get("town"):
		for rid in main.town.residents:
			var r = main.town.residents[rid]
			if is_instance_valid(r) and r.visible:
				_check_tools(r)
				_check_feet(r, "res:" + String(rid))
	_check_camera()
	_check_fights()
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		if not is_instance_valid(c) or not c.visible or not c.is_inside_tree():
			continue
		_check_feet(c, who)
		if c.handler and c.handler.held and is_instance_valid(c.handler.held):
			_count("held_in_hand")
			var d: float = (c.handler.held as Node3D).global_position.distance_to(c.handler.palm())
			if d > 0.6:
				_flag("%s:%s" % [who, (c.handler.held as Node).name], "held_in_hand", {"dist": snappedf(d, 0.01)})


## The camera on the followed mage (the director's subject), whatever shot it is in.
func _check_camera() -> void:
	var d = main.get("director")
	if d == null or not d.enabled or d.mode in ["off", "establishing", "explore", "performance"]:
		return
	if main.get("streaming") and main.streaming.state != "idle":
		_arrived_t = 0.0
		return
	_arrived_t += 0.5
	if _arrived_t < 2.5:
		return          # just arrived: the lens settles on her first
	if main.get("camera_rig") and main.camera_rig.shot_active and d.mode == "chase":
		return          # a scripted still (a test / a tour) holds the lens, not the director
	var cam := get_viewport().get_camera_3d()
	var c: WorldCharacter = d.mika
	if cam == null or c == null or not is_instance_valid(c) or not c.visible:
		return
	_count("camera")
	var cp := cam.global_position
	var head := c.global_position + Vector3(0, 1.5, 0)
	var subject := "camera:%s:%s" % [d.mode, c.character_id]
	if CombatFraming.inside_solid(c.get_world_3d().direct_space_state, cp, 0.12):
		_flag(subject, "camera:inside_geometry", {"pos": [snappedf(cp.x, 0.1), snappedf(cp.y, 0.1), snappedf(cp.z, 0.1)]})
		return
	if d.mode == "scene":
		# a staged scene frames whoever speaks (a rival, Luna): never inside geometry, and its view not blocked
		var lk: Vector3 = cam.global_position - cam.global_transform.basis.z * 3.0
		var sq2 := PhysicsRayQueryParameters3D.create(cp, lk, 1 | 4)
		var bh := c.get_world_3d().direct_space_state.intersect_ray(sq2)
		if not bh.is_empty() and cp.distance_to(bh.position) < 0.8:
			_flag(subject, "camera:view_blocked", {"by": String((bh.collider as Node).name) if bh.collider else "", "at_m": snappedf(cp.distance_to(bh.position), 0.01)})
		return
	var flat := Vector2(cp.x - head.x, cp.z - head.z).length()
	if cp.y < c.global_position.y + 0.9 and flat < 5.0 and not c.lifted:
		_flag(subject, "camera:looking_up_from_below", {"lens_above_feet": snappedf(cp.y - c.global_position.y, 0.01), "dist": snappedf(flat, 0.01)})
	elif cp.distance_to(head) < 0.9 and d.mode != "face":
		_flag(subject, "camera:inside_her", {"dist": snappedf(cp.distance_to(head), 0.01)})
	elif not cam.is_position_in_frustum(head) and not cam.is_position_in_frustum(c.global_position + Vector3(0, 0.9, 0)):
		_flag(subject, "camera:she_is_out_of_frame", {"mode": d.mode})
	else:
		var q := PhysicsRayQueryParameters3D.create(cp, head, 1)
		q.exclude = [c.get_rid()]
		var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(head) > 0.6:
			_hidden_t += 0.5
			if _hidden_t >= 2.0:      # a moment behind a tree trunk is fine; staying hidden is not
				_flag(subject, "camera:she_is_hidden", {"by": String((hit.collider as Node).name) if hit.collider else ""})
		else:
			_hidden_t = 0.0


func _check_fights() -> void:
	if main.get("spawner") == null:
		return
	for m in main.spawner.alive:
		if not is_instance_valid(m) or not m.visible or m.mstate == "dying":
			continue
		var tgt: Node3D = m.target_mage if m.target_mage and is_instance_valid(m.target_mage) else null
		var subj := "%s(%s)" % [String(m.get("kind")), String(m.get("id"))]
		var entering_windup: bool = String(m.mstate) == "windup" and String(_mstate_prev.get(m.get_instance_id(), "")) != "windup"
		_mstate_prev[m.get_instance_id()] = String(m.mstate)
		# facing is judged as the attack BEGINS (the aim then locks on purpose, so a mage who dodges is missed)
		if tgt and entering_windup:
			_count("facing")
			var to := Vector3(tgt.global_position.x - m.global_position.x, 0, tgt.global_position.z - m.global_position.z)
			var fwd: Vector3 = (m as Node3D).global_transform.basis.z
			fwd = Vector3(fwd.x, 0, fwd.z).normalized()
			if to.length() > 0.5 and rad_to_deg(fwd.angle_to(to.normalized())) > 50.0:
				_flag(subj, "facing:attacks_without_facing", {"deg": snappedf(rad_to_deg(fwd.angle_to(to.normalized())), 0.1), "state": m.mstate})
		var rig = m.get("creature")
		if rig == null or rig.get("weapons") == null:
			continue
		for w in rig.weapons:
			if not is_instance_valid(w) or not (w as Node3D).is_visible_in_tree() or not w.has_meta("tip_local"):
				continue
			_count("weapon")
			var tip: Vector3 = (w as Node3D).global_transform * (w.get_meta("tip_local") as Vector3)
			# the fist (the measured grip point) - the holder's origin is the prop's own origin, not the hand
			var grip: Vector3 = (w as Node3D).global_transform * (w.get_meta("grip_local", Vector3.ZERO) as Vector3)
			var axis := Vector2(tip.x - m.global_position.x, tip.z - m.global_position.z).length()
			if axis < 0.14 and tip.y > m.global_position.y + 0.3 and tip.y < m.global_position.y + 1.6:
				_flag(subj, "weapon:through_own_body", {"tip_from_axis": snappedf(axis, 0.01)})
			var q := PhysicsRayQueryParameters3D.create(tip + Vector3(0, 1.0, 0), tip + Vector3(0, -0.02, 0), 1)
			var hit: Dictionary = (m as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and (hit.position as Vector3).y > tip.y + 0.08 and String((hit.collider as Node).name).contains("Terrain"):
				_flag(subj, "weapon:in_the_ground", {"depth": snappedf((hit.position as Vector3).y - tip.y, 0.01)})
			# the blade never passes through its wielder (torso, neck, head): sampled along it, past the fist
			var mp: Vector3 = (m as Node3D).global_position
			for k in range(2, 9):
				var bp := grip.lerp(tip, k / 8.0)
				var ax := Vector2(bp.x - mp.x, bp.z - mp.z).length()
				if ax < 0.17 and bp.y > mp.y + 0.95 and bp.y < mp.y + 1.85:
					_flag(subj, "weapon:through_own_body", {"at": snappedf(k / 8.0, 0.01), "from_axis": snappedf(ax, 0.01), "height": snappedf(bp.y - mp.y, 0.01), "state": String(m.mstate)})
					break
			# the LEAD blade points at the opponent on guard (a dual-wielder's off-hand dagger is held back by design)
			if tgt and w == rig.weapons[0] and String(m.mstate) in ["alert", "chase", "attack"]:
				var gd := (tip - grip).normalized()
				var td := ((tgt.global_position + Vector3(0, 1.1, 0)) - grip).normalized()
				var gk := "%s:guard" % subj
				if rad_to_deg(gd.angle_to(td)) > 75.0:
					_persist[gk] = int(_persist.get(gk, 0)) + 1
					if int(_persist[gk]) >= 2:      # still off a second later (not just settling into the guard)
						_flag(subj, "weapon:guard_not_at_opponent", {"deg": snappedf(rad_to_deg(gd.angle_to(td)), 0.1), "state": String(m.mstate)})
				else:
					_persist[gk] = 0
			# judged at the moment of the hit (a slash's follow-through legitimately sweeps past the body)
			if tgt and w == rig.weapons[0] and m.mstate == "strike" and float(m.get("_state_t")) > 0.12 and float(m.get("_state_t")) < 0.28:
				# against the attack's own direction (where it faces - the aim locks at the wind-up, so a dodged
				# mage is no longer in front of it, and that is right)
				var bd := (tip - grip).normalized()
				var mf: Vector3 = (m as Node3D).global_transform.basis.z
				var tdir := (Vector3(mf.x, 0, mf.z).normalized() + Vector3(0, -0.1, 0)).normalized()
				if rad_to_deg(bd.angle_to(tdir)) > 110.0:
					_flag(subj, "weapon:strikes_pointing_away", {"deg": snappedf(rad_to_deg(bd.angle_to(tdir)), 0.1)})
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		var b = main.mage_brains.get(who) if main.get("mage_brains") else null
		if not is_instance_valid(c) or not c.casting or b == null or b.threat == null or not is_instance_valid(b.threat):
			continue
		var sid := String(c.get_meta("casting_spell", ""))
		var sdef: Dictionary = MagicSystem.spell(sid) if sid != "" else {}
		if String(sdef.get("projectile", "")) in ["self"] or (String(sdef.get("projectile", "")) == "ward" and who != "luna"):
			continue        # a self-spell / an all-round leaf ward: no direction to face
		_count("facing")
		# what she casts AT (her chosen target), else the threat
		var aim_at: Node3D = c.get_meta("cast_target") if c.has_meta("cast_target") and is_instance_valid(c.get_meta("cast_target")) else b.threat
		var to2 := Vector3(aim_at.global_position.x - c.global_position.x, 0, aim_at.global_position.z - c.global_position.z)
		if to2.length() > 0.8 and rad_to_deg(mage_forward(c).angle_to(to2.normalized())) > 45.0:
			_cast_off_t[who] = float(_cast_off_t.get(who, 0.0)) + 0.5
			if float(_cast_off_t[who]) >= 1.0:          # she may still be turning for half a second
				_flag(who, "facing:casts_without_facing", {"deg": snappedf(rad_to_deg(mage_forward(c).angle_to(to2.normalized())), 0.1), "spell": sid,
					"cast_target": String((c.get_meta("cast_target") as Node).name) if c.has_meta("cast_target") and is_instance_valid(c.get_meta("cast_target")) else "", "threat": String(b.threat.name)})
		else:
			_cast_off_t[who] = 0.0


func _check_tools(r) -> void:
	for clip in r.tools:
		var holder: Node3D = r.tools[clip]
		if not holder.is_visible_in_tree():
			continue
		_count("tool_in_hand")
		var palm := palm_of(r, String(r.data.get("tools", {}).get(clip, {}).get("bone", "hand_r")))
		if palm == Vector3.INF:
			continue
		var d := nearest_surface(holder, palm)
		if d > GRIP_MAX:
			_flag("res:%s:%s" % [r.id, clip], "tool_in_hand", {"gap": snappedf(d, 0.3 if d > 1.0 else 0.01)})


## The palm (where a closed fist holds a handle) of a resident's hand bone, in world space.
static func palm_of(r, bone: String) -> Vector3:
	var sk: Skeleton3D = null
	for n in (r.model as Node).find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if sk == null or sk.find_bone(bone) < 0:
		return Vector3.INF
	var side := "l" if bone.ends_with("_l") else "r"
	var hg := Grip.hand_frame(sk, side)
	var bt := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))
	return bt * hg.origin


## Distance from p to the nearest vertex of the meshes under `root` (cheap enough every half second).
static func nearest_surface(root: Node3D, p: Vector3) -> float:
	var best := INF
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var inv := (mi as MeshInstance3D).global_transform.affine_inverse()
		var lp := inv * p
		var sc := (mi as MeshInstance3D).global_transform.basis.get_scale().x
		for s in m.get_surface_count():
			var vs: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for i in range(0, vs.size(), 3):
				best = minf(best, vs[i].distance_to(lp) * sc)
	return best


func _check_feet(c: Node3D, subject: String) -> void:
	if c is WorldCharacter:
		var wc := c as WorldCharacter
		if wc.lifted or wc.seated or wc.has_meta("on_seat") or wc.ground_pose != "" or wc.has_meta("transforming") or (wc.reaction and wc.reaction.active):
			return
		if main.get("streaming") and main.streaming.state != "idle":
			return
	elif c.get("state") != null and (String(c.state) == "inside" or String(c.state).contains("sit") or String(c.get("activity")) in ["eat", "attend", "sleep"]):
		return
	# just put somewhere new (a placement, a travel, a fold): gravity settles her first
	var prev: Vector3 = _last_pos.get(subject, c.global_position)
	_last_pos[subject] = c.global_position
	if prev.distance_to(c.global_position) > 3.0:
		return
	_count("on_ground")
	var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3(0, 1.2, 0), c.global_position + Vector3(0, -3.0, 0), 1)
	if c is CollisionObject3D:
		q.exclude = [(c as CollisionObject3D).get_rid()]
	var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_flag(subject, "on_ground:no_ground", {"pos": [snappedf(c.global_position.x, 0.1), snappedf(c.global_position.y, 0.1), snappedf(c.global_position.z, 0.1)]})
		return
	var gap := c.global_position.y - (hit.position as Vector3).y
	var who_info := {"pos": [snappedf(c.global_position.x, 0.1), snappedf(c.global_position.y, 0.1), snappedf(c.global_position.z, 0.1)]}
	if c.get("state") != null:
		who_info["state"] = String(c.get("state"))
		who_info["activity"] = String(c.get("activity"))
	if gap > FOOT_MAX:
		_flag(subject, "on_ground:floating", who_info.merged({"gap": snappedf(gap, 0.01), "ground": String((hit.collider as Node).name) if hit.collider else ""}))
	elif gap < -FOOT_MAX:
		_flag(subject, "on_ground:sunk", who_info.merged({"gap": snappedf(gap, 0.01), "ground": String((hit.collider as Node).name) if hit.collider else ""}))


func summary() -> Dictionary:
	var by_rule := {}
	for v in violations:
		by_rule[v.rule] = int(by_rule.get(v.rule, 0)) + 1
	return {"violations": violations.size(), "by_rule": by_rule, "checks": checks}
