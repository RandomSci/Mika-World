class_name BodyReaction
extends Node
## Believable impact and recovery (V3 continuation - the developer: "Characters must never instantly snap from a
## knocked-down position into a standing pose. Impact -> loss of balance -> stumble or fall -> settling -> recovery
## effort -> standing -> regaining balance -> resume activity").
##
## Severity (0..1+, from ImpactDirector: strength, distance, cover, wards, guarding, her balance) picks the tier:
##   notice  (< 0.12)  she only looks: surprise on her face
##   flinch  (< 0.35)  a light blow: a flinch, a half step, balance back at once
##   stagger (< 0.62)  stumbles back (or is thrown off balance from behind), catches herself, steadies
##   down    (>= 0.62) a real fall: backwards when struck from the front (thrown through the air when it is
##                     very strong), forwards onto her knees when struck from behind. She lies / kneels a while
##                     (dazed, breathing hard), props herself up, gets her feet under her and stands, then steadies.
## Every phase is a real clip crossfaded into the next through the "react" state machine of her AnimationTree;
## the falls carry her body over the ground by the clip's own hip travel (root motion) plus the blast's push,
## through collision and on the real floor; on a slope her body is laid along the ground while she is down.
## Pace depends on the blow, her own body (data/mages.json "body": balance, recovery, style), her vigor and how
## often she has been knocked down lately. Lines and sounds come from her own voice.

signal reacted(info: Dictionary)
signal recovered(info: Dictionary)

const TIERS := [[0.12, "notice"], [0.35, "flinch"], [0.62, "stagger"]]

var c: WorldCharacter
var active := false
var tier := ""
var phase := ""
var info := {}
var history: Array = []          # the last reactions (tests / overlay)
var body := {"balance": 1.0, "recovery": 1.0, "style": "steady"}
var _seq := 0
var _state := ""
var _state_t := 0.0
var _speed := 1.0
var _push := Vector3.ZERO
var _tilt := 0.0
var _tilt_target := 0.0
var _turn_to := INF
var _avatar_q := Quaternion.IDENTITY
var _clock := 0.0
var _downs: Array = []           # game times of recent knock-downs (fatigue)
var _guard_until := -1.0


static func attach(ch: WorldCharacter) -> BodyReaction:
	var r := BodyReaction.new()
	r.name = "BodyReaction"
	r.c = ch
	ch.add_child(r)
	var prof: Dictionary = Progression.mages.get(ch.character_id, {}).get("body", {}) if Progression.mages else {}
	for k in prof:
		r.body[k] = prof[k]
	r._avatar_q = ch.avatar.quaternion if ch.avatar else Quaternion.IDENTITY
	return r


## True while the reaction owns her body (actions are refused: she is falling, down or getting up).
func blocks_actions() -> bool:
	return active and tier in ["stagger", "down"]


## A brace she has just taken (Sword_Block guard, a ward raised) softens what comes next.
func guard(seconds := 1.4) -> void:
	_guard_until = _clock + seconds


func guarding() -> bool:
	return _clock < _guard_until


func tier_for(sev: float) -> String:
	for t in TIERS:
		if sev < float(t[0]):
			return String(t[1])
	return "down"


## Receive an impact from `from` (world point) with `severity`. Returns what happened.
func receive(from: Vector3, severity: float, ctx := {}) -> Dictionary:
	var t := tier_for(severity)
	var away := Vector3(c.global_position.x - from.x, 0, c.global_position.z - from.z)
	away = away.normalized() if away.length() > 0.05 else c.global_transform.basis.z
	var fwd := -c.global_transform.basis.z
	var from_behind := fwd.dot(-away) < -0.34          # the source is more than ~110 degrees off her facing
	var res := {"t": snappedf(_clock, 0.01), "who": c.character_id, "severity": snappedf(severity, 0.01), "tier": t,
		"from_behind": from_behind, "kind": String(ctx.get("kind", "")), "source": String(ctx.get("source", ""))}
	for k in ["cover", "warded", "guarded", "dist"]:
		if ctx.has(k):
			res[k] = ctx[k]
	if t in ["notice", "flinch"]:
		c.look_head_at(from + Vector3(0, 1.2, 0))
	else:
		c.look_head_at(null)
	_face("surprised", 0.9 if t != "notice" else 0.6, 1.0)
	if t == "notice":
		_log(res)
		return res
	# already down: a further blow keeps her down a little longer, she does not fall again
	if active and tier == "down":
		info["extra_hits"] = int(info.get("extra_hits", 0)) + 1
		res["tier"] = "down (already)"
		_log(res)
		return res
	if active and tier == "stagger" and t == "flinch":
		_log(res)
		return res
	if c.seated or c.ground_pose != "":
		res["tier"] = "flinch (seated)"
		_log(res)
		return res
	if c.casting:
		if t == "flinch":
			res["tier"] = "flinch (casting)"
			_log(res)
			return res
		c.anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		c.casting = false
		res["cast_broken"] = true
	c._finish_action(false, "struck")
	c._nav_active = false
	c._dash = {}
	c.velocity = Vector3(0, c.velocity.y, 0)
	c.end_gesture()
	_seq += 1
	tier = t
	info = res
	active = true
	TrailerCam.punch({"flinch": 0.3, "stagger": 0.5, "down": 0.8}.get(t, 0.2))
	reacted.emit(res)
	var strength := clampf(severity, 0.0, 1.4)
	match t:
		"flinch": _flinch(away, strength, from_behind, _seq)
		"stagger": _stagger(away, strength, from_behind, from, _seq)
		"down": _fall(away, strength, from_behind, from, _seq)
	_log(res)
	return res


func _log(res: Dictionary) -> void:
	history.append(res)
	if history.size() > 40:
		history.pop_front()


# ------------------------------------------------------------------ sequences
func _flinch(away: Vector3, s: float, behind: bool, my: int) -> void:
	phase = "flinch"
	_mix(1.0, 0.08)
	_go("hit_head" if (not behind and randf() < 0.4) else "hit_chest", 0.08, 1.15)
	_push = away * (0.9 + s * 1.2)
	_voice("gasp")
	await _wait(0.55)
	if my != _seq:
		return
	_finish(my, 0.35)


func _stagger(away: Vector3, s: float, behind: bool, from: Vector3, my: int) -> void:
	phase = "stagger"
	_turn_to = _yaw_towards(-away) if not behind else INF
	_mix(1.0, 0.1)
	_push = away * (1.8 + s * 2.2)
	_voice("oof")
	_face_hold("hurt", 0.6)
	if behind:
		_go("rx_absorb", 0.1, 1.15)          # thrown off balance from behind: crouches, arms out, catches herself
		await _wait(1.0)
	else:
		_go("rx_stagger", 0.1, 0.85 / float(body.recovery))
		await _wait(0.75)
		if my != _seq:
			return
		_go("rx_steady", 0.3, 0.8)
		await _wait(0.5)
	if my != _seq:
		return
	_face_hold("hurt", 0.0)
	c.look_head_at(from + Vector3(0, 1.2, 0))
	_finish(my, 0.45)


func _fall(away: Vector3, s: float, behind: bool, from: Vector3, my: int) -> void:
	phase = "falling"
	_downs.append(_clock)
	while not _downs.is_empty() and _clock - float(_downs[0]) > 120.0:
		_downs.pop_front()
	var vigor: float = WorldState.mind(c.character_id).vigor
	# condition: tired, hurt or knocked down repeatedly -> she stays down longer and rises more slowly
	var cond := 1.0 + (1.0 - vigor) * 0.8 + (_downs.size() - 1) * 0.3
	var rec := float(body.recovery)
	var down_s := clampf((1.1 + 2.4 * (s - 0.62)) * cond / rec, 0.9, 4.5)
	var rise := clampf(0.68 * rec / sqrt(cond), 0.45, 1.0)
	info["down_s"] = snappedf(down_s, 0.01)
	info["rise_speed"] = snappedf(rise, 0.01)
	_turn_to = _yaw_towards(-away) if not behind else _yaw_towards(away)
	_mix(1.0, 0.1)
	_voice("oof")
	_face_hold("hurt", 0.8)
	if behind:
		_go("rx_fall_fwd", 0.12, 1.0)
		_push = away * (2.2 + s * 1.8)
		await _wait(1.35)
		if my != _seq:
			return
		phase = "down"
		_go("rx_kneel_hold", 0.35, 1.0)
		_tilt_target = 0.5
		_face_hold("dazed", 0.7)
		await _wait(down_s * 0.8)
		if my != _seq:
			return
		_voice("breath")
		await _wait(0.6 + int(info.get("extra_hits", 0)) * 0.8)
		if my != _seq:
			return
		phase = "rising"
		_tilt_target = 0.0
		_face_hold("dazed", 0.0)
		_face_hold("hurt", 0.5)
		_voice("effort")
		_go("rx_kneel_rise", 0.45, rise)
		await _wait(0.87 / rise)
	else:
		var blown := s >= 0.9
		_go("rx_blown_back" if blown else "rx_fall_back", 0.1, 1.0)
		_push = away * ((3.6 + s * 2.0) if blown else (1.6 + s * 1.6))
		await _wait(0.8 if blown else 1.2)
		if my != _seq:
			return
		phase = "down"
		_go("rx_down_back", 0.45, 1.0)
		_tilt_target = 1.0
		_face_hold("hurt", 0.0)
		_face_hold("dazed", 0.85)
		await _wait(down_s)
		if my != _seq:
			return
		while int(info.get("extra_hits", 0)) > int(info.get("_extra_seen", 0)):
			info["_extra_seen"] = int(info.get("_extra_seen", 0)) + 1
			await _wait(0.9)
		if my != _seq:
			return
		phase = "sitting_up"
		_voice("breath")
		_go("rx_sit_up", 0.4, rise)
		await _wait(0.62 / rise)
		if my != _seq:
			return
		_tilt_target = 0.0
		_face_hold("dazed", 0.3)
		var agile := String(body.style) == "agile" and s < 0.95 and cond < 1.4
		if agile:
			# she springs back up from sitting (Luna: light on her feet)
			phase = "rising"
			_voice("effort")
			_go("rx_quick_up", 0.3, 0.8)
			await _wait(0.5 / 0.8)
		else:
			phase = "catching_breath"
			_go("rx_sit_hold", 0.35, 1.0)
			c.look_head_at(from + Vector3(0, 1.0, 0))
			await _wait(clampf(0.7 * cond / rec, 0.5, 2.0))
			if my != _seq:
				return
			phase = "rising"
			_face_hold("dazed", 0.0)
			_face_hold("hurt", 0.45)
			_voice("effort")
			_go("rx_stand_from_sit", 0.35, rise)
			await _wait(0.88 / rise)
	if my != _seq:
		return
	phase = "steadying"
	_face_hold("hurt", 0.0)
	_face_hold("dazed", 0.0)
	_go("rx_steady", 0.35, 0.75)
	c.look_head_at(from + Vector3(0, 1.2, 0))
	await _wait(0.55)
	if my != _seq:
		return
	_finish(my, 0.55)


func _finish(my: int, blend_out: float) -> void:
	phase = "resuming"
	_mix(0.0, blend_out)
	await _wait(blend_out)
	if my != _seq:
		return
	active = false
	phase = ""
	var done := info.duplicate()
	done["finished_t"] = snappedf(_clock, 0.01)
	done["duration_s"] = snappedf(_clock - float(info.get("t", _clock)), 0.01)
	var t := tier
	tier = ""
	if t != "flinch":
		_face(_after_emotion(), 0.7, 1.4)
	recovered.emit(done)
	get_tree().create_timer(2.5).timeout.connect(func(): if not active and is_instance_valid(c): c.look_head_at(null))


func _after_emotion() -> String:
	return "determined" if String(body.style) == "steady" else "concerned"


## A scripted reaction-layer pose for other behaviours (kneeling beside a fallen friend, reaching a hand out).
## Blends in over `fade`; `release()` blends back out to normal life.
func pose(state: String, fade := 0.4, speed := 1.0) -> void:
	if active:
		return
	_seq += 1
	tier = "pose"
	phase = "pose:" + state
	active = true
	_mix(1.0, fade)
	_go(state, fade, speed)


func release(fade := 0.5) -> void:
	if tier != "pose":
		return
	_finish(_seq, fade)


# ------------------------------------------------------------------ helpers
func _go(state: String, xfade: float, speed: float) -> void:
	var sm := (c.anim_tree.tree_root as AnimationNodeBlendTree).get_node("react_sm") as AnimationNodeStateMachine
	if not sm.has_node(state):
		push_warning("[reaction] no state " + state)
		return
	var pb: AnimationNodeStateMachinePlayback = c.anim_tree.get("parameters/react_sm/playback")
	if _state != "" and _state != state:
		for i in sm.get_transition_count():
			if sm.get_transition_from(i) == StringName(_state) and sm.get_transition_to(i) == StringName(state):
				sm.get_transition(i).xfade_time = xfade
		pb.travel(state)
	else:
		pb.start(state, true)
	c.anim_tree.set("parameters/react_speed/scale", speed)
	_speed = speed
	_state = state
	_state_t = 0.0
	phase_changed(state)


func phase_changed(_s: String) -> void:
	pass


var _mix_tw: Tween


func _mix(v: float, seconds: float) -> void:
	if _mix_tw and _mix_tw.is_valid():
		_mix_tw.kill()
	var tw := create_tween()
	_mix_tw = tw
	tw.tween_property(c.anim_tree, "parameters/react_mix/blend_amount", v, maxf(seconds, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _wait(s: float) -> void:
	var until := _clock + s
	while _clock < until and is_inside_tree():
		await get_tree().physics_frame


func _yaw_towards(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static var voice: VoiceService      # set by main


func _voice(kind: String) -> void:
	if voice and is_instance_valid(voice):
		voice.react(c.character_id, kind)


func _face(emotion: String, w: float, hold: float) -> void:
	if c.face:
		c.face.pulse(emotion, w, hold)
	else:
		c.set_expression("surprised" if emotion == "surprised" else "angry", w)


func _face_hold(emotion: String, w: float) -> void:
	if c.face:
		c.face.set_hold(emotion, w)


## Called from WorldCharacter._physics_process while active: moves her by the clip's hip travel and the push,
## keeps her on the real floor, turns her into the fall, lays her body along a slope while she is down.
func physics(delta: float) -> void:
	_clock += delta
	if not active:
		_ease_tilt(delta)
		return
	_state_t += delta * _speed
	var vel := Vector3.ZERO
	var curve: PackedVector2Array = WorldCharacter.root_curves.get(_state, PackedVector2Array())
	if curve.size() > 1:
		var a := _sample(curve, (_state_t - delta * _speed) * 30.0)
		var b := _sample(curve, _state_t * 30.0)
		var d := b - a
		var sk := c.skeleton
		var w := sk.global_basis * (Vector3(d.x, 0, d.y) * sk.motion_scale)
		w.y = 0
		vel += w / maxf(delta, 1e-4) * float(c.anim_tree.get("parameters/react_mix/blend_amount"))
	vel += _push
	_push = _push.move_toward(Vector3.ZERO, (5.5 if c.is_on_floor() else 1.5) * delta * maxf(_push.length(), 1.0))
	c.velocity.x = vel.x
	c.velocity.z = vel.z
	if not c.is_on_floor():
		c.velocity.y -= c._gravity * delta
	else:
		c.velocity.y = minf(c.velocity.y, 0.0)
	c.move_and_slide()
	if _turn_to != INF:
		c.rotation.y = lerp_angle(c.rotation.y, _turn_to, 1.0 - exp(-14.0 * delta))
		if absf(angle_difference(c.rotation.y, _turn_to)) < 0.02:
			_turn_to = INF
	c.anim_tree.set("parameters/loco/blend_position", 0.0)
	_ease_tilt(delta)


func _sample(curve: PackedVector2Array, f: float) -> Vector2:
	if f <= 0.0:
		return curve[0]
	var i := int(f)
	if i >= curve.size() - 1:
		return curve[curve.size() - 1]
	return curve[i].lerp(curve[i + 1], f - i)


func _ease_tilt(delta: float) -> void:
	_tilt = move_toward(_tilt, _tilt_target if active else 0.0, delta * 1.6)
	if c.avatar == null:
		return
	if _tilt < 0.001:
		if c.avatar.quaternion != _avatar_q:
			c.avatar.quaternion = _avatar_q
		return
	var n := Vector3.UP
	var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3(0, 0.6, 0), c.global_position + Vector3(0, -1.2, 0), 1)
	q.exclude = [c.get_rid()]
	var hit := c.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		n = hit.normal
	var nl := (c.global_basis.inverse() * n).normalized()
	var align := Quaternion(Vector3.UP, nl) if nl.dot(Vector3.UP) < 0.9999 else Quaternion.IDENTITY
	c.avatar.quaternion = Quaternion.IDENTITY.slerp(align, _tilt) * _avatar_q


## Developer staging only (labs / tests placing an actor): drop any reaction at once.
func reset() -> void:
	_seq += 1
	active = false
	tier = ""
	phase = ""
	_push = Vector3.ZERO
	_tilt = 0.0
	_tilt_target = 0.0
	_turn_to = INF
	if _mix_tw and _mix_tw.is_valid():
		_mix_tw.kill()
	c.anim_tree.set("parameters/react_mix/blend_amount", 0.0)
	if c.avatar:
		c.avatar.quaternion = _avatar_q


func status() -> Dictionary:
	return {"active": active, "tier": tier, "phase": phase, "state": _state, "info": info}
