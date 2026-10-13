class_name CameraDirector
extends Node
## Automatic cinematographer layered on the ThirdPersonCamera rig. Chooses a shot each frame by priority:
##   spell      — dramatic low three-quarter front angle while casting (side kept for the whole cast)
##   activity   — framing by activity kind: reading/inspecting = over-the-shoulder on the object,
##                meditate/rest = gentle front three-quarter, practice = side-on wide (Mika + target),
##                explore = the sub-area's scenic composition (Watchpoint vista)
##   conversation — two-shot when focus_conversation(other) is active (future mentor NPC)
##   establishing — the sub-area's wide shot (data/sanctuary.json camera) for a few seconds on entry
##   chase      — over-the-shoulder follow while exploring (spring-arm collision of the rig)
##   combat     — (Milestone J) a wide lateral shot of the fight: the mage, the creatures engaging her, a
##                blow telegraphed at her, the other mage if fighting alongside (CombatFraming)
##   signature  — (Milestone J) the short beats of a signature cast: stance, push-in on the build-up,
##                over-the-shoulder release, hold on the impact; then back to combat
## Rules: minimum shot duration, cuts for big moves and blends for small ones, line-of-sight checks
## (camera pulled in front of walls), and the 180° rule (side shots keep the current screen side).
## Enabled automatically while Mika's brain drives her; V toggles it for the player.

signal shot_changed(mode: String)

const MIN_SHOT := 2.2
const ESTABLISH_TIME := 4.0
const ESTABLISH_COOLDOWN := 90.0

var rig: ThirdPersonCamera
var mika: WorldCharacter
var main: Node
var enabled := false:
	set(v):
		if enabled == v:
			return
		enabled = v
		if not v and rig:
			rig.clear_shot()
			mode = "off"
var mode := "off"
var current_sub := ""
var _since_change := 99.0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _fov := 52.0
var _interaction: Interactable = null
var _establish_until := 0.0
var _establish_target := []
var _last_established := {}
var _side := 1.0
var _conversation: Node3D = null
var _conversation_until := 0.0
var _perf := {}                  # music performance: {mode, shot, t0, yaw0, last}
var _combat := {}                # CombatFraming.subjects() for this frame
var _combat_until := 0.0         # combat framing holds a moment after the last sign of a fight
var _combat_blocked := 0.0       # seconds the current side has been blocked
var _sig := {}                   # signature cast: {c, target, beat, t0, impact, end_at}

## Performance shot profiles (radius / height in metres, yaw degrees from her facing at the cut; yaw_to
## makes a slow orbit across the shot; look = face | chest | hands | feet).
const PERF_SHOTS := {
	"casual": [
		{"name": "medium_front", "radius": 3.0, "height": 1.35, "yaw": 15.0, "look": "chest", "fov": 44.0},
		{"name": "full_body", "radius": 4.3, "height": 1.05, "yaw": -32.0, "look": "chest", "fov": 50.0},
		{"name": "face_close", "radius": 1.4, "height": 1.5, "yaw": 12.0, "look": "face", "fov": 36.0},
		{"name": "slow_orbit", "radius": 3.6, "height": 1.25, "yaw": -70.0, "yaw_to": 10.0, "look": "chest", "fov": 47.0},
		{"name": "wide_env", "radius": 7.5, "height": 2.3, "yaw": 38.0, "look": "chest", "fov": 54.0},
		{"name": "low_hero", "radius": 2.9, "height": 1.05, "yaw": -18.0, "look": "face", "fov": 50.0},
	],
	"special": [
		{"name": "establishing", "radius": 9.0, "height": 3.0, "yaw": 25.0, "look": "chest", "fov": 55.0},
		{"name": "slow_orbit", "radius": 3.8, "height": 1.3, "yaw": -90.0, "yaw_to": 20.0, "look": "chest", "fov": 46.0},
		{"name": "hands", "radius": 1.7, "height": 1.3, "yaw": 30.0, "look": "hands", "fov": 40.0},
		{"name": "face_close", "radius": 1.35, "height": 1.52, "yaw": -10.0, "look": "face", "fov": 35.0},
		{"name": "full_body_low", "radius": 4.0, "height": 1.1, "yaw": 20.0, "look": "chest", "fov": 50.0},
		{"name": "finale_pullback", "radius": 4.5, "height": 1.6, "yaw": 0.0, "look": "chest", "fov": 50.0, "pull": 2.5},
	],
}


func _on_conv_line(speaker: String, text: String) -> void:
	if _conversation == null or not is_instance_valid(_conversation) or _now() > _conversation_until:
		_conv_ots = null
		return
	var sc: Node3D = main.characters.get(speaker)
	if sc == null:
		return
	var other: Node3D = _conversation if sc == mika else mika
	if sc != mika and sc != _conversation:
		return
	_conv_lines += 1
	# alternate: two-shot for greetings / short replies, reverse shots for real content
	var words := text.split(" ", false).size()
	if words >= 5 and _conv_lines % 3 != 1:
		_conv_ots = {"speaker": sc, "listener": other}
	else:
		_conv_ots = null
	_since_change = 0.0


func setup(m: Node) -> void:
	main = m
	rig = main.camera_rig
	mika = main.characters["mika"]
	WorldState.interaction_started.connect(func(it, c): if c == mika: _interaction = it)
	WorldState.interaction_finished.connect(func(it, c, _r): if c == mika and _interaction == it: _interaction = null)


# ------------------------------------------------------------------ music performances
func start_performance(c: WorldCharacter, mode: String) -> void:
	set_subject(c)
	_perf = {"mode": mode, "i": -1, "t0": _now(), "yaw0": 0.0, "shot": {}}
	performance_cut()


## A new shot (called by the PerformanceController on musical phrase changes).
func performance_cut() -> void:
	if _perf.is_empty():
		return
	var shots: Array = PERF_SHOTS.get(_perf.mode, PERF_SHOTS.casual)
	var i := int(_perf.i) + 1
	if _perf.mode == "casual" and i > 0:
		i = (int(_perf.i) + 1 + randi() % (shots.size() - 1)) % shots.size()   # vary, never the same twice
	if _perf.mode == "special":
		i = mini(i, shots.size() - 2)                                         # the finale is kept for the end
	_perf.i = i
	_perf.shot = shots[i]
	_perf.t0 = _now()
	_perf.yaw0 = main.transformer.visual_yaw(mika) if main.transformer else mika.rotation.y
	_since_change = 0.0
	shot_changed.emit("performance:" + String(_perf.shot.name))


func performance_finale() -> void:
	if _perf.is_empty():
		return
	var shots: Array = PERF_SHOTS.get(_perf.mode, PERF_SHOTS.casual)
	_perf.shot = shots[-1]
	_perf.t0 = _now()
	_perf.yaw0 = main.transformer.visual_yaw(mika) if main.transformer else mika.rotation.y
	_since_change = 0.0


func end_performance() -> void:
	_perf = {}
	_since_change = 99.0


func _perf_look(what: String) -> Vector3:
	match what:
		"face":
			var hi := mika.skeleton.find_bone("Head")
			return (mika.skeleton.global_transform * mika.skeleton.get_bone_global_pose(hi)).origin + Vector3(0, 0.06, 0) if hi >= 0 else mika.global_position + Vector3(0, 1.5, 0)
		"hands":
			return (mika.left_hand.global_position + mika.right_hand.global_position) * 0.5
	return mika.chest.global_position


## Follow another mage (the spotlight in main picks whoever is doing the most watchable thing).
## The `mika` field is the current subject; the name is kept for older callers.
func set_subject(c: WorldCharacter) -> void:
	if c == null or c == mika:
		return
	mika = c
	_interaction = null
	_since_change = 99.0
	_last_established.clear()
	if rig:
		rig.target = c


func focus_conversation(other: Node3D, seconds := 8.0) -> void:
	_conv_pick = {}
	_conv_ots = null
	_conv_lines = 0
	if main.get("voice") and not main.voice.line_started.is_connected(_on_conv_line):
		main.voice.line_started.connect(_on_conv_line)
	_conversation = other
	_conversation_until = _now() + seconds


## Signature cast beats follow the caster's real cast phases (CombatFraming.signature_shot). Only for the
## followed mage, or for the other mage when she is fighting right beside her (a shared moment).
func begin_signature(c: WorldCharacter, target: Node3D) -> void:
	if not enabled:
		return
	if c != mika and c.global_position.distance_to(mika.global_position) > 14.0:
		return
	_sig = {"c": c, "target": target, "beat": "awaken", "t0": _now(), "impact": Vector3.INF, "end_at": 0.0}
	if not c.cast_event.is_connected(_on_sig_event):
		c.cast_event.connect(_on_sig_event)


func _on_sig_event(ev: String) -> void:
	if _sig.is_empty():
		return
	var beat: String = {"gather": "gather", "release": "release", "burst": "impact", "impact": "impact"}.get(ev, "")
	if beat == "" or beat == String(_sig.beat):
		return
	if beat == "impact" and _sig.target and is_instance_valid(_sig.target):
		_sig.impact = (_sig.target as Node3D).global_position + Vector3(0, 1.0, 0)
	_sig.beat = beat
	_sig.t0 = _now()


func end_signature(c: WorldCharacter) -> void:
	if not _sig.is_empty() and _sig.c == c:
		_sig.end_at = _now() + 1.2                 # hold on the outcome, then back to the fight
	if c.cast_event.is_connected(_on_sig_event):
		c.cast_event.disconnect(_on_sig_event)


func status() -> Dictionary:
	return {"enabled": enabled, "mode": mode, "sub_area": current_sub, "shot_age_s": snappedf(_since_change, 0.1),
		"camera": [snappedf(_pos.x, 0.01), snappedf(_pos.y, 0.01), snappedf(_pos.z, 0.01)]}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	_since_change += delta
	var world = main.world
	var sub := ""
	if world and world.has_method("sub_area_at"):
		sub = world.sub_area_at(mika.global_position)
	if sub != current_sub:
		current_sub = sub
		if sub != "" and _now() - float(_last_established.get(sub, -999.0)) > ESTABLISH_COOLDOWN:
			var cam: Dictionary = WorldState.sanctuary.sub_areas[sub].camera
			_establish_target = [_arr(cam.pos), _arr(cam.look)]
			_establish_until = _now() + ESTABLISH_TIME
			_last_established[sub] = _now()
	if not enabled or main.streaming.state != "idle":
		return
	var want := _choose()
	if want != mode:
		var urgent := want in ["spell", "activity", "signature", "combat"]
		if _since_change < MIN_SHOT and not urgent and mode != "off":
			want = mode  # hold the current shot a little longer
		else:
			_switch(want)
	_frame(delta)


func _choose() -> String:
	if not _perf.is_empty():
		return "performance"
	if not _sig.is_empty():
		return "signature"
	_combat = CombatFraming.subjects(self, main, mika) if main.spawner else {"foes": []}
	if not (_combat.foes as Array).is_empty():
		_combat_until = _now() + 2.5
	if _now() < _combat_until and _combat.has("points"):
		return "combat"
	if mika.casting:
		return "spell"
	if _interaction != null:
		return "activity"
	if _conversation and is_instance_valid(_conversation) and _now() < _conversation_until:
		return "conversation"
	if _now() < _establish_until:
		return "establishing"
	return "chase"


func _switch(m: String) -> void:
	mode = m
	_since_change = 0.0
	if m in ["spell", "activity", "conversation", "combat", "signature"]:
		# keep the side of the screen the viewer already sees Mika on (180° rule)
		var f := -mika.global_transform.basis.z
		var right := Vector3(-f.z, 0, f.x)
		_side = 1.0 if (rig.camera.global_position - mika.global_position).dot(right) >= 0.0 else -1.0
	if m == "chase":
		rig.clear_shot()
		rig.yaw = mika.rotation.y
	shot_changed.emit(m)


func _frame(delta: float) -> void:
	var p := mika.global_position
	var fwd := -mika.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)  # same as her basis.x (she faces -Z)
	var pos := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := 50.0
	match mode:
		"combat":
			var sh: Dictionary = CombatFraming.shot(main, mika, _combat, _side)
			if not CombatFraming.clear(mika, sh.pos, _combat):
				_combat_blocked += delta
				if _combat_blocked > 0.6:
					var other: Dictionary = CombatFraming.shot(main, mika, _combat, -_side)
					if CombatFraming.clear(mika, other.pos, _combat):
						_side = -_side            # the only reason to cross the line: this side is blocked
						sh = other
					_combat_blocked = 0.0
			else:
				_combat_blocked = 0.0
			pos = _clear_line(mika.global_position + Vector3(0, 1.2, 0), sh.pos)
			_apply(pos, sh.look, sh.fov, delta, 6.0 if not mika._dash.is_empty() else 2.4)
			return
		"signature":
			var beat_t := _now() - float(_sig.t0)
			if float(_sig.get("end_at", 0.0)) > 0.0 and _now() > float(_sig.end_at):
				_sig = {}
				_combat_until = _now() + 2.5
				return
			var ss: Dictionary = CombatFraming.signature_shot(_sig.c, _sig.target, String(_sig.beat), beat_t, _side, _sig.impact)
			if ss.cut:
				_since_change = 0.0
			pos = _clear_line(ss.look, ss.pos)
			_apply(pos, ss.look, ss.fov, delta, 4.0)
			return
		"performance":
			var sh: Dictionary = _perf.shot
			var age := _now() - float(_perf.t0)
			if String(sh.look) in ["face", "hands"] and main.transformer:
				# close shots keep finding her face as she turns in the dance (smoothly, never snapping)
				_perf.yaw0 = lerp_angle(float(_perf.yaw0), main.transformer.visual_yaw(mika), 1.0 - exp(-1.6 * delta))
			var yaw: float = float(_perf.yaw0) + deg_to_rad(lerpf(float(sh.yaw), float(sh.get("yaw_to", sh.yaw)), clampf(age / 12.0, 0.0, 1.0)))
			var r: float = float(sh.radius) + float(sh.get("pull", 0.0)) * clampf(age / 5.0, 0.0, 1.0)
			look = _perf_look(String(sh.look))
			pos = p + Vector3(-sin(yaw), 0, -cos(yaw)) * r + Vector3(0, float(sh.height), 0)
			if main.world and main.world.has_method("ground_at"):
				pos.y = maxf(pos.y, float(main.world.ground_at(pos.x, pos.z)) + 0.25)
			fov = float(sh.fov)
			pos = _clear_line(_perf_look("chest"), _clear_line(look, pos))
			_apply(pos, look, fov, delta)
			return
		"chase":
			# the rig's spring arm handles collisions; we only steer its yaw/pitch behind her heading
			var moving := Vector2(mika.velocity.x, mika.velocity.z).length() > 0.3
			var k := 1.0 - exp(-(2.2 if moving else 0.6) * delta)
			rig.yaw = lerp_angle(rig.yaw, mika.rotation.y, k)
			# spring arm squeezed by a wall: rise above it instead of ending up inside her hair
			var squeezed := rig.arm.get_hit_length() < 1.6
			rig.pitch = lerpf(rig.pitch, -0.62 if squeezed else -0.2, 1.0 - exp(-3.0 * delta) if squeezed else k)
			rig.distance = lerpf(rig.distance, 3.6, k)
			_pos = rig.camera.global_position
			return
		"establishing":
			pos = _establish_target[0]
			look = _establish_target[1].lerp(p + Vector3(0, 1.2, 0), 0.25)
			fov = 55.0
		"spell":
			pos = p + fwd * 2.6 + right * _side * 2.0 + Vector3(0, 1.05, 0)   # never a low angle on her
			look = p + fwd * 1.6 + Vector3(0, 1.45, 0)
			fov = 54.0
		"conversation":
			# a two-shot across their eye line, from the side where BOTH faces are clear (flips the side only
			# when this one is blocked), a little toward the followed mage so she stays the main subject
			var o := _conversation.global_position
			var mid := (p + o) * 0.5
			var axis := Vector3(o.x - p.x, 0, o.z - p.z)
			var sep := axis.length()
			axis = axis.normalized() if sep > 0.05 else fwd
			var dist := clampf(sep * 1.0 + 1.5, 2.4, 4.2)
			# candidates: both sides of the eye line, swung a little either way; prefer the current side, both faces
			# clear, and an OPEN background behind them (no column / wall right between their heads)
			if _since_change < 0.05 or _conv_pick.is_empty():
				var best_sc := -INF
				for sd in [_side, -_side]:
					for sw in [0.0, 0.35, -0.35]:
						var pr: Vector3 = Vector3(-axis.z, 0, axis.x).rotated(Vector3.UP, sw) * sd
						var cp: Vector3 = mid + pr * dist + Vector3(0, 1.45, 0)
						var sc: float = (1.0 if sd == _side else 0.0) - absf(sw) * 0.5
						if not _two_clear(cp, p, o):
							sc -= 10.0
						sc -= _background_clutter(cp, mid + Vector3(0, 1.3, 0)) * 3.0
						if sc > best_sc:
							best_sc = sc
							_conv_pick = {"side": sd, "swing": sw}
				_side = float(_conv_pick.side)
			var prf := Vector3(-axis.z, 0, axis.x).rotated(Vector3.UP, float(_conv_pick.get("swing", 0.0))) * _side
			pos = mid + prf * dist + Vector3(0, 1.45, 0)
			# shot / reverse shot: on a substantive line, over the LISTENER's shoulder onto the speaker's face
			if _conv_ots != null and is_instance_valid(_conv_ots.speaker) and is_instance_valid(_conv_ots.listener):
				var spk: Node3D = _conv_ots.speaker
				var lis: Node3D = _conv_ots.listener
				var sh_axis := Vector3(spk.global_position.x - lis.global_position.x, 0, spk.global_position.z - lis.global_position.z).normalized()
				var lperp := Vector3(-sh_axis.z, 0, sh_axis.x) * _side
				var ots: Vector3 = lis.global_position - sh_axis * 1.35 + lperp * 0.72 + Vector3(0, 1.55, 0)
				var face_pt: Vector3 = spk.global_position + Vector3(0, 1.42, 0)
				if _two_clear(ots, spk.global_position, spk.global_position):
					pos = ots
					look = face_pt.lerp(lis.global_position + Vector3(0, 1.4, 0), 0.18)
					fov = 34.0
					pos = _clear_line(look, pos)
					_apply(pos, look, fov, delta, 5.0)
					return
			look = mid.lerp(p, 0.15) + Vector3(0, 1.38, 0)
			fov = 42.0
		"activity":
			var it := _interaction
			var obj: Vector3 = it.get_parent().to_global(it.face_point) if it.face_point != null else it.global_position
			if it.book_id != "" and BookReader.instance and BookReader.instance.reading() and it.book_xf != null:
				# book close-up: over her right shoulder, looking down onto the open pages
				var anchor: Vector3 = BookReader.instance.current.anchor
				pos = p - fwd * 0.45 + right * _side * 0.55 + Vector3(0, 1.72, 0)
				pos = pos.lerp(anchor + Vector3(0, 0.75, 0), 0.25)
				look = anchor + Vector3(0, 0.02, 0)
				fov = 42.0
				pos = _clear_line(look, pos)
				_apply(pos, look, fov, delta)
				return
			match it.kind:
				"study", "inspect":
					# over the shoulder, onto the page / inscription
					# wide enough of her shoulder that the page / inscription stays clear of her hair
					pos = p - fwd * 1.5 + right * _side * 1.05 + Vector3(0, 1.75, 0)
					look = obj.lerp(p + Vector3(0, 1.35, 0), 0.3)
					fov = 50.0
				"meditate", "rest":
					# side profile looking past her toward what she contemplates: no close front shots of
					# the seated pose (the skirt drape over the thighs is the weakest part of the pose)
					pos = p + right * _side * 2.9 + fwd * 0.9 - fwd * 0.0 + Vector3(0, 1.15, 0)
					look = p + fwd * 1.6 + Vector3(0, 0.95, 0)
					fov = 46.0
				"practice":
					var mid := (p + obj) * 0.5
					var axis := (obj - p)
					axis.y = 0
					axis = axis.normalized()
					var perp := Vector3(-axis.z, 0, axis.x) * _side
					pos = mid + perp * (2.2 + (p.distance_to(obj)) * 0.6) + Vector3(0, 1.25, 0)
					look = mid + Vector3(0, 1.1, 0)
					fov = 52.0
				"explore":
					var vista = WorldState.sanctuary.sub_areas.get(current_sub, {}).get("vista", null)
					if vista:
						pos = _arr(vista.pos)
						look = _arr(vista.look)
					else:
						pos = p - fwd * 2.4 + Vector3(0, 2.2, 0)
						look = p + fwd * 20.0 + Vector3(0, 1.0, 0)
					fov = 60.0
				_:
					pos = p - fwd * 2.2 + right * 0.6 + Vector3(0, 1.7, 0)
					look = obj
	pos = _clear_line(look, pos)
	_apply(pos, look, fov, delta)


func _apply(pos: Vector3, look: Vector3, fov: float, delta: float, rate := 3.0) -> void:
	var cut := _since_change < 0.05 and (_pos.distance_to(pos) > 4.0 or not rig.shot_active)
	if cut or not rig.shot_active:
		_pos = pos
		_look = look
		_fov = fov
	else:
		var k2 := 1.0 - exp(-rate * delta)
		_pos = _pos.lerp(pos, k2)
		_look = _look.lerp(look, k2)
		_fov = lerpf(_fov, fov, k2)
	rig.set_shot(_pos, _look, _fov)


var _conv_pick := {}
var _conv_ots = null          # {speaker, listener} while a substantive line is spoken in a conversation
var _conv_lines := 0


## 1.0 when something solid stands just behind the subjects on the camera's line (within 3 m), 0 when open.
func _background_clutter(cam: Vector3, at: Vector3) -> float:
	var dir := (at - cam).normalized()
	var q := PhysicsRayQueryParameters3D.create(at + dir * 0.6, at + dir * 3.6)
	q.collision_mask = 1
	var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
	return 0.0 if hit.is_empty() else 1.0 - clampf((at.distance_to(hit.position) - 0.6) / 3.0, 0.0, 1.0)


func _two_clear(cam: Vector3, a: Vector3, b: Vector3) -> bool:
	var space := mika.get_world_3d().direct_space_state
	for t in [a, b]:
		var q := PhysicsRayQueryParameters3D.create(cam, t + Vector3(0, 1.4, 0))
		q.collision_mask = 1
		q.exclude = [mika.get_rid()] + ([_conversation.get_rid()] if _conversation is CollisionObject3D else [])
		if not space.intersect_ray(q).is_empty():
			return false
	return true


## Keep the subject visible: if geometry blocks the line from the subject to the camera, move the
## camera to just in front of the obstruction.
func _clear_line(subject: Vector3, cam: Vector3) -> Vector3:
	var space := mika.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(subject, cam)
	q.exclude = [mika.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return cam
	var hp: Vector3 = hit.position
	return hp + (subject - hp).normalized() * 0.35


static func _arr(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
