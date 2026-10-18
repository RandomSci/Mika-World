## QA (--mktest=foot_slide): locomotion blend vs real ground speed, and foot sliding, in every character state.
## Owner bug 2026-10-19: "Luna plays a walk animation while standing still on the pier. When velocity is zero, always
## blend to idle." Each frame both girls are sampled: the loco blend (0 idle, 1 walk, 2 run), the loco time scale, the
## body's horizontal ground speed, and both feet in world space. Per state:
##   tread  = frames she stands still (< 0.05 m/s for over 0.45 s) while the blend still says walk (> 0.15)
##   foot   = median horizontal speed of a planted foot (the lowest moment of each step) - 0 = no sliding
##   lag    = seconds from the stop to the blend reaching idle (< 0.1)
## --fs-pier-only: just the lake pier stop (for a GPU clip / stills; _shot PNGs land in <shots-dir>/mktest).
extends RefCounted


class Probe extends Node:
	var t: Node
	var chars: Array = []
	var rec := {}

	func _process(_d: float) -> void:
		for c in chars:
			var wc := c as WorldCharacter
			if wc.skeleton == null or wc.anim_tree == null:
				continue
			var sk := wc.skeleton
			var gt := sk.global_transform
			(rec[wc.character_id] as Array).append({"t": float(t._game_t), "p": wc.global_position,
				"L": gt * sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin,
				"R": gt * sk.get_bone_global_pose(sk.find_bone("RightFoot")).origin,
				"b": float(wc.anim_tree.get("parameters/loco/blend_position")),
				"s": float(wc.anim_tree.get("parameters/loco_speed/scale")),
				"g": bool(wc.anim_tree.get("parameters/cast/active"))})


static var _probe: Probe
static var _t
static var _results: Array = []


static func run(t) -> void:
	_t = t
	_results = []
	await t._hold_all()
	for w in t.main.mage_brains:
		t.main.mage_brains[w].set_enabled(false)
		t.main.mage_brains[w].current = {}
	t.main.director.enabled = false
	t.main.spawner.enabled = false
	if t.main.performance and t.main.performance.busy():
		t.main.performance.interrupt("test")
	if t.main.performance:
		t.main.performance.set_process(false)
	var mika: WorldCharacter = t.main.characters["mika"]
	var luna: WorldCharacter = t.main.characters["luna"]
	_probe = Probe.new()
	_probe.t = t
	_probe.chars = [mika, luna]
	_probe.rec = {"mika": [], "luna": []}
	t.add_child(_probe)
	if RenderProfile.options.has("fs-sweep"):
		await _sweep(mika, luna)
		_probe.queue_free()
		return
	if not RenderProfile.options.has("fs-pier-only"):
		await _home_states(mika, luna)
	await _pier_states(mika, luna)
	var bad := _results.filter(func(r): return not bool(r.ok))
	print("[footslide] SUMMARY %d states, %d FAIL: %s" % [_results.size(), bad.size(), ", ".join(bad.map(func(r): return String(r.state)))])
	_probe.queue_free()


# ------------------------------------------------------------------ helpers
static func _hz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _place(c: WorldCharacter, at: Vector3, yaw = null) -> void:
	if _t.main.teleport_guard:
		_t.main.teleport_guard.allow(c)
	c.stop_action()
	c.visible = true
	c.set_physics_process(true)
	c.velocity = Vector3.ZERO
	c.global_position = at + Vector3(0, 0.05, 0)
	if yaw != null:
		c.rotation.y = float(yaw)


static func _snap(c: WorldCharacter, p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(c.get_world_3d().navigation_map, p)


static func _wait_action(c: WorldCharacter, action: String, limit: float) -> float:
	var t0: float = _t._game_t
	while c.current_action == action and float(_t._game_t) - t0 < limit:
		await _t.get_tree().process_frame
	return float(_t._game_t)


## Stats of one girl's samples in [t0, t1].
static func _stats(id: String, t0: float, t1: float, t_stop := -1.0) -> Dictionary:
	var s: Array = (_probe.rec[id] as Array).filter(func(x): return float(x.t) >= t0 and float(x.t) <= t1)
	var out := {"frames": s.size()}
	if s.size() < 8:
		return out
	var v := [0.0]
	for i in range(1, s.size()):
		var dt := float(s[i].t) - float(s[i - 1].t)
		v.append(_hz(s[i].p - s[i - 1].p).length() / dt if dt > 0.0 else float(v[i - 1]))
	# planted feet: the lowest moment of each step (height relative to the body, so slopes and the deck do not matter)
	var contact := []
	for k in ["L", "R"]:
		for i in range(3, s.size() - 3):
			var y: float = (s[i][k] as Vector3).y - (s[i].p as Vector3).y
			var lo := y
			for j in range(i - 3, i + 4):
				lo = minf(lo, (s[j][k] as Vector3).y - (s[j].p as Vector3).y)
			if y <= lo + 0.004:
				var dt2 := float(s[i + 1].t) - float(s[i - 1].t)
				if dt2 > 0.0:
					contact.append(_hz(s[i + 1][k] - s[i - 1][k]).length() / dt2)
	# treading: standing still for over 0.45 s while the blend still plays a walk
	var tread := 0
	var still_since := -1.0
	for i in s.size():
		if float(v[i]) < 0.05:
			if still_since < 0.0:
				still_since = float(s[i].t)
			if float(s[i].t) - still_since > 0.45 and float(s[i].b) > 0.15:
				tread += 1
		else:
			still_since = -1.0
	var vs := v.duplicate()
	vs.sort()
	contact.sort()
	var blends := s.map(func(x): return float(x.b))
	var scales := s.map(func(x): return float(x.s))
	scales.sort()
	out["body"] = snappedf(float(vs[vs.size() / 2]), 0.01)
	out["body_max"] = snappedf(float(vs[vs.size() - 1]), 0.01)
	out["foot"] = snappedf(float(contact[contact.size() / 2]), 0.01) if not contact.is_empty() else -1.0
	out["foot_p90"] = snappedf(float(contact[int(contact.size() * 0.9)]), 0.01) if not contact.is_empty() else -1.0
	out["contacts"] = contact.size()
	out["blend_min"] = snappedf(blends.min(), 0.01)
	out["blend_max"] = snappedf(blends.max(), 0.01)
	out["scale"] = snappedf(float(scales[scales.size() / 2]), 0.01)
	out["tread"] = tread
	if t_stop >= 0.0:
		out["lag"] = -1.0
		for x in s:
			if float(x.t) >= t_stop and float(x.b) < 0.1:
				out["lag"] = snappedf(float(x.t) - t_stop, 0.01)
				break
	return out


static func _report(state: String, ok: bool, st: Dictionary, why := "") -> void:
	_results.append({"state": state, "ok": ok})
	print("[footslide] %s %s %s %s" % ["PASS" if ok else "FAIL", state, JSON.stringify(st), why])
	_t._check(ok, "foot_slide " + state, JSON.stringify(st).left(200))


## A walk / run is clean when the planted foot barely moves next to the body (<= 25 % of body speed + 3 cm/s).
static func _feet_ok(st: Dictionary) -> bool:
	return float(st.get("foot", -1.0)) >= 0.0 and float(st.foot) <= float(st.body) * 0.25 + 0.03


# ------------------------------------------------------------------ the home area
static func _home_states(mika: WorldCharacter, luna: WorldCharacter) -> void:
	var lanes := {"mika": [Vector3(-2, 0, 12), Vector3(-2, 0, -8)], "luna": [Vector3(-6, 0, 12), Vector3(-6, 0, -8)]}
	for id in ["mika", "luna"]:
		var c: WorldCharacter = _t.main.characters[id]
		var other: WorldCharacter = luna if c == mika else mika
		var a := _snap(c, lanes[id][0])
		var b := _snap(c, lanes[id][1])
		_place(other, _snap(other, Vector3(10, 0, 14)))
		_place(c, a, atan2(-(b - a).x, -(b - a).z))
		await _t._wait(1.2)

		# 1. idle: standing, nothing to do
		var t0: float = _t._game_t
		await _t._wait(1.5)
		var st := _stats(id, t0, _t._game_t)
		_report(id + " idle", int(st.get("tread", 1)) == 0 and float(st.get("blend_max", 1.0)) < 0.05 and float(st.get("foot", 1.0)) < 0.05, st)

		# 2. walk (mid-path) and 3. arrival at the end of the path
		c.navigate_to(b, false)
		t0 = _t._game_t
		var t_arr := await _wait_action(c, "navigate_to", 25.0)
		await _t._wait(1.5)
		st = _stats(id, t0 + 1.5, t_arr - 0.8)
		_report(id + " walk", _feet_ok(st) and float(st.get("blend_min", 0.0)) > 0.9, st)
		st = _stats(id, t_arr - 0.3, t_arr + 1.5, t_arr)
		_report(id + " arrival", int(st.get("tread", 1)) == 0 and float(st.get("lag", -1.0)) >= 0.0 and float(st.lag) <= 0.45, st)

		# 4. run, back along the lane
		c.navigate_to(a, true)
		t0 = _t._game_t
		t_arr = await _wait_action(c, "navigate_to", 20.0)
		await _t._wait(1.2)
		st = _stats(id, t0 + 1.5, t_arr - 1.0)
		_report(id + " run", _feet_ok(st) and float(st.get("blend_min", 0.0)) > 1.8, st)
		st = _stats(id, t_arr - 0.3, t_arr + 1.2, t_arr)
		_report(id + " run stop", int(st.get("tread", 1)) == 0 and float(st.get("lag", -1.0)) >= 0.0 and float(st.lag) <= 0.5, st)

		# 5. walk -> run -> walk on the same path (the transitions)
		c.navigate_to(b, false)
		t0 = _t._game_t
		await _t._wait(2.5)
		c.navigate_to(b, true)
		await _t._wait(2.0)
		c.navigate_to(b, false)
		await _t._wait(2.0)
		var t1: float = _t._game_t
		c.stop_action()
		await _t._wait(1.2)
		st = _stats(id, t0 + 1.0, t1)
		var st_stop := _stats(id, t1, t1 + 1.2, t1)
		st["stop_lag"] = st_stop.get("lag", -1.0)
		_report(id + " walk-run-walk", float(st.get("foot", 9.0)) <= float(st.get("body", 0.0)) * 0.3 + 0.04 \
			and float(st.stop_lag) >= 0.0 and float(st.stop_lag) <= 0.45, st)

		# 6. a slow walk beside a friend (FollowCompanion pace 0.6): the idle/walk mix region
		c.pace = 0.6
		c.navigate_to(_snap(c, c.global_position + (a - c.global_position).normalized() * 6.0), false)
		t0 = _t._game_t
		t_arr = await _wait_action(c, "navigate_to", 20.0)
		c.pace = 1.0
		await _t._wait(1.0)
		st = _stats(id, t0 + 1.5, t_arr - 0.8)
		# (the idle/walk mix region: the tempo must follow the shorter stride - 0.18-0.20 m/s at the full tempo, 0.13 matched)
		_report(id + " slow walk (pace 0.6)", float(st.get("foot", -1.0)) >= 0.0 and float(st.foot) <= 0.16, st)

		# 7. turning in place (look behind her): no walk cycle while only the body turns
		await _t._wait(0.5)
		c.look_at_point(c.global_position + c.global_transform.basis.z * 3.0)
		t0 = _t._game_t
		await _wait_action(c, "look_at", 6.0)
		await _t._wait(0.5)
		st = _stats(id, t0, _t._game_t)
		_report(id + " turn in place", int(st.get("tread", 1)) == 0 and float(st.get("blend_max", 1.0)) < 0.1, st)

		# 8. blocked / stuck: a wall across the path the navmesh does not know about
		var here := c.global_position
		var fwd := Vector3(-sin(c.rotation.y), 0, -cos(c.rotation.y))
		var wall := StaticBody3D.new()
		wall.collision_layer = c.collision_mask
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(5.0, 2.5, 0.4)
		cs.shape = box
		wall.add_child(cs)
		_t.main.world.add_child(wall)
		wall.global_position = here + fwd * 1.6 + Vector3(0, 1.2, 0)
		wall.rotation.y = c.rotation.y
		var goal := _snap(c, here + fwd * 5.0)
		c.navigate_to(goal, false)
		t0 = _t._game_t
		t_arr = await _wait_action(c, "navigate_to", 12.0)
		var why := String(c.last_rejection)
		await _t._wait(1.2)
		st = _stats(id, t0 + 1.2, t_arr + 1.2, t_arr)
		st["ended"] = snappedf(t_arr - t0, 0.1)
		_report(id + " blocked/stuck", int(st.get("tread", 1)) == 0 and float(st.get("lag", -1.0)) >= 0.0 and float(st.lag) <= 0.45, st, why)
		wall.queue_free()
		await _t._wait(0.3)

		# 9. a gesture that ends, then a walk
		_place(c, a, atan2(-(b - a).x, -(b - a).z))
		await _t._wait(1.0)
		c.play_gesture("idle_talk", 0.5, 0.7)
		t0 = _t._game_t
		await _t._wait(2.0)
		c.end_gesture()
		await _t._wait(1.5)
		st = _stats(id, t0, _t._game_t)
		_report(id + " gesture ends", int(st.get("tread", 1)) == 0 and float(st.get("blend_max", 1.0)) < 0.05 and float(st.get("body_max", 1.0)) < 0.05, st)
		c.navigate_to(_snap(c, a + (b - a).normalized() * 7.0), false)
		t0 = _t._game_t
		t_arr = await _wait_action(c, "navigate_to", 15.0)
		await _t._wait(1.0)
		st = _stats(id, t0 + 1.5, t_arr - 0.8)
		_report(id + " walk after gesture", _feet_ok(st) and float(st.get("blend_min", 0.0)) > 0.9, st)

		# 10. sitting on the ground and getting up
		if c.has_clip("sit_ground_enter"):
			t0 = _t._game_t
			c.play_gesture("sit_ground_enter", 0.3, 0.3)
			c.set_ground_pose("sit", c.animation_length("sit_ground_enter") * 0.9)
			await _t._wait(c.animation_length("sit_ground_enter") * 0.85)
			c.play_gesture("sit_ground_loop", 0.3, 0.6)
			await _t._wait(2.0)
			c.end_gesture()
			c.play_gesture("sit_ground_exit", 0.2, 0.4)
			c.set_ground_pose("", c.animation_length("sit_ground_exit") * 0.9)
			await _t._wait(c.animation_length("sit_ground_exit") + 0.6)
			st = _stats(id, t0, _t._game_t)
			_report(id + " ground sit", int(st.get("tread", 1)) == 0 and float(st.get("blend_max", 1.0)) < 0.05 and float(st.get("body_max", 1.0)) < 0.05, st)

		# 11. physics turned off mid-walk, WITHOUT stop_action (a scene takes her over): settles into idle anyway
		c.navigate_to(b, false)
		await _t._wait(2.5)
		t1 = _t._game_t
		c.set_physics_process(false)
		await _t._wait(1.5)
		st = _stats(id, t1, _t._game_t, t1)
		_report(id + " physics off mid-walk", int(st.get("tread", 1)) == 0 and float(st.get("lag", -1.0)) >= 0.0 and float(st.lag) <= 0.4, st)
		c.set_physics_process(true)
		c.stop_action()
		await _t._wait(0.8)


# ------------------------------------------------------------------ the pier (the owner's case)
static func _pier_states(mika: WorldCharacter, luna: WorldCharacter) -> void:
	var tr: Dictionary = await _t.main.streaming.travel("lantern_lake", luna, false)
	_t._check(_t.main.streaming.current_id == "lantern_lake", "at Lantern Lake (%s)" % str(tr).left(120))
	await _t._wait(2.0)
	var lake: Node3D = null
	for n in _t.main.world.find_children("*", "Node3D", true, false) + [_t.main.world]:
		if n.get("water_mat") != null:
			lake = n
			break
	if lake == null:
		_report("pier setup", false, {}, "no lake node")
		return
	var shots := DisplayServer.get_name() != "headless"
	var cam: Camera3D = null
	for id in ["luna", "mika"]:
		var c: WorldCharacter = _t.main.characters[id]
		var other: WorldCharacter = mika if c == luna else luna
		var land := lake.to_global(Vector3(4.0, 0.62, 8.2))
		var far := lake.to_global(Vector3(4.0, 0.62, -2.6))
		other.stop_action()
		other.set_physics_process(false)
		other.visible = false
		_place(c, _snap(c, land), atan2(-(far - land).x, -(far - land).z))
		await _t._wait(1.2)
		if shots and cam == null:
			# a medium-wide side view of the pier (whole body, face well under 10 % of the frame)
			cam = Camera3D.new()
			cam.fov = 50.0
			_t.main.world.add_child(cam)
			if _t.main.get("camera_rig") and _t.main.camera_rig:
				_t.main.camera_rig.set_process(false)
			cam.make_current()
		var dest := _snap(c, far)
		_t._check(dest.distance_to(far) < 1.0, "%s: the pier's end is on the navmesh (%.2f m off)" % [id, dest.distance_to(far)])

		# A. the exact scene: navigate along the pier, then stop_action + physics off WHILE she is still walking
		c.navigate_to(dest, false)
		var t0: float = _t._game_t
		while float(_t._game_t) - t0 < 3.5:
			if cam:
				cam.global_position = c.global_position + Vector3(4.6, 1.3, 0.0)
				cam.look_at(c.global_position + Vector3(0, 0.85, 0))
			await _t.get_tree().process_frame
		if shots:
			_t._shot("%s_pier_walking" % id)
		var t1: float = _t._game_t
		c.stop_action()
		c.set_physics_process(false)
		for k in [0.2, 0.5, 1.0, 2.5]:
			while float(_t._game_t) - t1 < k:
				await _t.get_tree().process_frame
			if shots:
				_t._shot("%s_pier_stop_%03d" % [id, int(k * 100)])
		var st := _stats(id, t1, _t._game_t, t1)
		st["blend_now"] = snappedf(float(c.anim_tree.get("parameters/loco/blend_position")), 0.01)
		_report(id + " pier: stop_action + physics off mid-walk", int(st.get("tread", 1)) == 0 and float(st.get("lag", -1.0)) >= 0.0 \
			and float(st.lag) <= 0.4 and float(st.blend_now) < 0.02, st)
		var st_feet := _stats(id, t1 + 0.6, _t._game_t)
		_report(id + " pier: standing feet planted", float(st_feet.get("foot", 1.0)) < 0.05 and float(st_feet.get("body_max", 1.0)) < 0.02, st_feet)

		# B. arrival at the pier's end, then the scene takes her over the same frame
		c.set_physics_process(true)
		c.navigate_to(dest, false)
		var t_arr := await _wait_action(c, "navigate_to", 20.0)
		c.stop_action()
		c.set_physics_process(false)
		await _t._wait(1.5)
		st = _stats(id, t_arr, _t._game_t, t_arr)
		st["blend_now"] = snappedf(float(c.anim_tree.get("parameters/loco/blend_position")), 0.01)
		st["arrived"] = c.global_position.distance_to(dest) < 1.3
		_report(id + " pier: arrival + physics off", bool(st.arrived) and int(st.get("tread", 1)) == 0 and float(st.get("lag", -1.0)) >= 0.0 \
			and float(st.lag) <= 0.4 and float(st.blend_now) < 0.02, st)
		if shots:
			if cam:
				cam.global_position = c.global_position + Vector3(4.6, 1.3, 0.0)
				cam.look_at(c.global_position + Vector3(0, 0.85, 0))
			await _t._wait(0.1)
			_t._shot("%s_pier_end_idle" % id)
		c.set_physics_process(true)
	if cam:
		cam.queue_free()
		if _t.main.get("camera_rig") and _t.main.camera_rig:
			_t.main.camera_rig.set_process(true)


# ------------------------------------------------------------------ calibration (--fs-sweep)
## Walks each girl at full and slow pace with the loco tempo forced to several values: the tempo where the planted
## foot is slowest is the one her clip really matches.
static func _sweep(mika: WorldCharacter, luna: WorldCharacter) -> void:
	for id in ["mika", "luna"]:
		var c: WorldCharacter = _t.main.characters[id]
		var other: WorldCharacter = luna if c == mika else mika
		_place(other, _snap(other, Vector3(10, 0, 14)))
		var tempo0 := float(c.motion.get("loco_tempo", 1.0))
		for pace in [1.0, 0.6]:
			for tempo in [0.8, 0.9, 1.0, 1.1, 1.2]:
				var a := _snap(c, Vector3(-2, 0, 12))
				var b := _snap(c, Vector3(-2, 0, -2))
				_place(c, a, atan2(-(b - a).x, -(b - a).z))
				await _t._wait(0.6)
				c.motion["loco_tempo"] = tempo
				c.pace = pace
				c.navigate_to(b, false)
				var t0: float = _t._game_t
				var t_arr := await _wait_action(c, "navigate_to", 25.0)
				var st := _stats(id, t0 + 1.5, t_arr - 0.8)
				print("[footslide] sweep %s pace %.1f tempo %.2f: %s" % [id, pace, tempo, JSON.stringify(st)])
		c.motion["loco_tempo"] = tempo0
		c.pace = 1.0
