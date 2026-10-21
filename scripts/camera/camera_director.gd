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
var _established_sub := ""

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
var _chase_hidden_t := 0.0
var _chase_tight_t := 0.0
var _chase_override := false
var _override_pos := Vector3.ZERO
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
var _stargaze := {}              # quiet scene: {a, b, t0, shot}


## V3 quiet scenes: two mages lying in the grass. Shots alternate between a low side view (bodies in the
## foreground, the sky above the trees) and a high three-quarter from the head side (faces); never from the feet
## (a skirt), never below hip height from behind the heads.
## A staged scene (an ambush's standoff, a story beat): `shot` is called every frame with delta and returns
## {pos, look, fov, rate, cut}; it outranks everything but a performance until end_scene().
var _scene: Callable = Callable()


func begin_scene(shot: Callable) -> void:
	_scene = shot
	_scene_failed = false
	_since_change = 0.0


func end_scene() -> void:
	_scene = Callable()
	_scene_failed = false


func begin_stargaze(a: WorldCharacter, b: WorldCharacter) -> void:
	_stargaze = {"a": a, "b": b, "t0": _now(), "shot": 0}


func end_stargaze() -> void:
	_stargaze = {}

## Performance shot profiles (radius / height in metres, yaw degrees from her facing at the cut; yaw_to
## makes a slow orbit across the shot; look = chest | feet). PERMANENT RULE (docs/world_look_rules.md): no face or
## hands close-ups - every shot is knees-up or wider, and _apply() enforces it (FramingRule).
const PERF_SHOTS := {
	"casual": [
		{"name": "medium_front", "radius": 3.0, "height": 1.35, "yaw": 15.0, "look": "chest", "fov": 44.0},
		{"name": "full_body", "radius": 4.3, "height": 1.05, "yaw": -32.0, "look": "chest", "fov": 50.0},
		{"name": "full_body_side", "radius": 4.0, "height": 1.2, "yaw": 55.0, "look": "chest", "fov": 48.0},
		{"name": "slow_orbit", "radius": 3.6, "height": 1.25, "yaw": -70.0, "yaw_to": 10.0, "look": "chest", "fov": 47.0},
		{"name": "wide_env", "radius": 7.5, "height": 2.3, "yaw": 38.0, "look": "chest", "fov": 54.0},
		{"name": "low_hero", "radius": 3.6, "height": 0.9, "yaw": -18.0, "look": "chest", "fov": 50.0},
	],
	"special": [
		{"name": "establishing", "radius": 9.0, "height": 3.0, "yaw": 25.0, "look": "chest", "fov": 55.0},
		{"name": "slow_orbit", "radius": 3.8, "height": 1.3, "yaw": -90.0, "yaw_to": 20.0, "look": "chest", "fov": 46.0},
		{"name": "medium_wide", "radius": 3.3, "height": 1.3, "yaw": 30.0, "look": "chest", "fov": 48.0},
		{"name": "silhouette_low", "radius": 5.0, "height": 0.55, "yaw": -150.0, "look": "chest", "fov": 50.0},
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
	# the rig places the lens AFTER the director decides it (same frame): it ran first, so every cut showed one frame
	# of the old angle - with a fighter already where it had been (2026-10-17)
	rig.process_priority = maxi(rig.process_priority, process_priority + 10)
	mika = main.characters["mika"]
	WorldState.interaction_started.connect(func(it, c): if c == mika: _interaction = it)
	WorldState.interaction_finished.connect(func(it, c, _r): if c == mika and _interaction == it: _interaction = null)


# ------------------------------------------------------------------ music performances
var _subject_before_perf: WorldCharacter = null

func start_performance(c: WorldCharacter, mode: String) -> void:
	if _perf.is_empty():
		_subject_before_perf = mika
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


## A duet: frame both dancers (the midpoint between them, pulled back so both fit; no single-face close-ups).
func set_performance_pair(other: WorldCharacter) -> void:
	if not _perf.is_empty():
		_perf["pair"] = other


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
	# the camera goes back to whom it followed before the dance (after a dance of Luna's it stayed on her, fights
	# included, until the next area load - 2026-10-17 stream)
	if _subject_before_perf != null and is_instance_valid(_subject_before_perf) and _subject_before_perf != mika:
		set_subject(_subject_before_perf)
	_subject_before_perf = null


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
var _chase_mate_off := 0.0
var _chase_mate_tgt := 0.0
var _chase_mate_clear := 0.0


## Another visible character's body (hips to head) within half a metre of the line from the lens to her.
func _mate_blocks(from: Vector3, to: Vector3) -> bool:
	var seg := to - from
	var l2 := seg.length_squared()
	if l2 < 0.01:
		return false
	for c in main.characters.values():
		var oc := c as WorldCharacter
		if oc == null or oc == mika or not oc.visible:
			continue
		for hgt: float in [0.9, 1.4]:
			var q := oc.global_position + Vector3(0, hgt, 0)
			var t := (q - from).dot(seg) / l2
			if t > 0.05 and t < 0.97 and (from + seg * t).distance_to(q) < 0.5:
				return true
	return false


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


var _trailer := TrailerCam.new()
var _shake_t := 0.0


func _process(delta: float) -> void:
	_since_change += delta
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	TrailerCam.tick_global(real_dt)
	_shake_t += real_dt
	if rig and rig.camera:
		var so := TrailerCam.shake_offset(_shake_t)
		rig.camera.h_offset = so.x
		rig.camera.v_offset = so.y
	var world = main.world
	var sub := ""
	if world and world.has_method("sub_area_at"):
		sub = world.sub_area_at(mika.global_position)
	if sub != current_sub:
		# she left the place the wide shot introduces: it ends (the 35-min proof: running through the library's stair
		# mouth, the fixed lens held on while she went out of view behind a tree - 14 near-black stretches)
		if _now() < _establish_until and sub == "":
			_establish_until = 0.0
		current_sub = sub
		# only when she arrives, not running straight through it
		var passing := Vector2(mika.velocity.x, mika.velocity.z).length() > 2.6
		if sub != "" and not passing and _now() - float(_last_established.get(sub, -999.0)) > ESTABLISH_COOLDOWN:
			var cam: Dictionary = WorldState.sanctuary.sub_areas[sub].camera
			var tgt := [_arr(cam.pos), _arr(cam.look)]
			_last_established[sub] = _now()
			# played only from where it was set: a lens the line-of-sight clamp would move (someone or something
			# between it and the place) is not walked in toward the place - that put it in the library's stairwell
			if _clear_line(tgt[1], tgt[0]).distance_to(tgt[0]) < 1.0 and _view_ok(tgt[0], tgt[1]):
				_established_sub = sub
				_establish_target = tgt
				_establish_until = _now() + ESTABLISH_TIME
	if not enabled or main.streaming.state != "idle":
		return
	var want := _choose()
	if want != mode:
		var urgent := want in ["spell", "activity", "signature", "combat"] or (mode == "establishing" and _establish_until == 0.0)
		if _since_change < MIN_SHOT and not urgent and mode != "off":
			want = mode  # hold the current shot a little longer
		else:
			_switch(want)
	_frame(delta)
	_guard_mika(delta)


## The stream's camera shows Mika (Selwyn, 20 October: never the camera on Luna). Whatever the shot, her head must be
## in the picture with nobody (Luna) and nothing solid in front of it; hidden for 0.6 s, a dance goes to its next shot
## and anything else cuts to the chase lens close behind her for 4 s (a two-shot behind a rock, the dance shot over
## open water, Luna's back filling the chase shot all happened in the soaks).
var _hidden_t := 0.0
var _rescue_until := 0.0
var _scene_failed := false              # a scene's own shots hid her: the chase lens for the rest of that scene


func _guard_mika(delta: float) -> void:
	if not enabled or mika == null or not mika.visible or main.streaming.state != "idle" or mode in ["off", "chase"]:
		_hidden_t = 0.0
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head := mika.global_position + Vector3(0, 1.35, 0)
	var vs := get_viewport().get_visible_rect().size
	var seen := not cam.is_position_behind(head) and Rect2(Vector2.ZERO, vs).has_point(cam.unproject_position(head)) \
		and not _mate_blocks(cam.global_position, head)
	if seen:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, head, 1 | 4)     # (walls, rocks and the trunks)
		q.exclude = [mika.get_rid()]
		var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
		seen = hit.is_empty() or (hit.position as Vector3).distance_to(head) < 0.4
	_hidden_t = 0.0 if seen else _hidden_t + delta
	if _hidden_t < 0.6:
		return
	_hidden_t = 0.0
	if mode == "performance" and not _perf.is_empty():
		print("[camera] Mika hidden in the dance shot %s: next shot" % String((_perf.shot as Dictionary).get("name", "")))
		performance_cut()
	else:
		print("[camera] Mika hidden in a %s shot: the chase lens%s" % [mode, " until the scene ends" if mode == "scene" else " for 4 s"])
		_rescue_until = _now() + 4.0
		if mode == "scene":
			_scene_failed = true
		_switch("chase")


func _choose() -> String:
	if (_now() < _rescue_until or (_scene_failed and _scene.is_valid())) and _perf.is_empty():
		return "chase"
	if not _perf.is_empty():
		return "performance"
	if _scene.is_valid():
		return "scene"
	if not _sig.is_empty():
		return "signature"
	if not _stargaze.is_empty() and is_instance_valid(_stargaze.a) and is_instance_valid(_stargaze.b):
		return "stargaze"
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
	_chase_override = false
	_chase_tight_t = 0.0
	if m in ["spell", "activity", "conversation", "combat", "signature", "stargaze", "scene"]:
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
		"scene":
			var sh: Dictionary = _scene.call(delta) if _scene.is_valid() else {}
			if sh.is_empty():
				return
			if bool(sh.get("cut", false)):
				_since_change = 0.0
			_apply(sh.pos, sh.look, float(sh.get("fov", 50.0)), delta, float(sh.get("rate", 3.0)))
			return
		"stargaze":
			# (16 script errors on the 2026-10-21 stream: the shot outlived its pair; back to following her)
			if not _stargaze.has("a") or not is_instance_valid(_stargaze.get("a")) or not is_instance_valid(_stargaze.get("b")):
				_switch("chase")
				return
			var ca: WorldCharacter = _stargaze.a
			var cb: WorldCharacter = _stargaze.b
			var ha := ca.skeleton.global_transform * ca.skeleton.get_bone_global_pose(ca.skeleton.find_bone("Head"))
			var hpa := ca.skeleton.global_transform * ca.skeleton.get_bone_global_pose(ca.skeleton.find_bone("Hips"))
			var hb := cb.skeleton.global_transform * cb.skeleton.get_bone_global_pose(cb.skeleton.find_bone("Hips"))
			var mid := (hpa.origin + hb.origin) * 0.5
			var axis := Vector3(ha.origin.x - hpa.origin.x, 0, ha.origin.z - hpa.origin.z)   # hips -> head along the ground
			axis = axis.normalized() if axis.length() > 0.1 else -fwd
			var sd := axis.cross(Vector3.UP).normalized()
			var el := _now() - float(_stargaze.t0)
			var phase := int(el / 14.0) % 2
			var drift := sin(el * 0.08) * 0.35
			if phase == 0:
				# high three-quarter from the head side, wide: the two of them whole, the grass around them
				pos = mid + axis * 2.2 + sd * (3.3 + drift) + Vector3(0, 2.6, 0)
				look = hpa.origin + axis * 0.2 + Vector3(0, 0.15, 0)
				fov = 46.0
			else:
				# low from the side: the two of them in the foreground, the night sky over the trees
				pos = mid + sd * (2.9 + drift) - axis * 0.3 + Vector3(0, 0.85, 0)
				look = mid + Vector3(0, 1.1, 0) + axis * 0.5
				fov = 50.0
			_apply(pos, look, fov, delta, 1.6)
			return
		"combat":
			# trailer cinematography in every fight (TrailerCam): close moving shots, cuts, punches on big hits
			var th: Dictionary = _trailer.frame(main, mika, _combat, delta)
			if not th.has("pos"):
				th = {"pos": mika.global_position + Vector3(0, 2.0, 4.0), "look": mika.global_position + Vector3(0, 1.0, 0), "fov": 50.0}
			if th.get("cut", false):
				_since_change = 0.0
			pos = _clear_line(mika.global_position + Vector3(0, 1.2, 0), th.pos)
			_apply(pos, th.look, th.fov, delta, float(th.get("rate", 4.0)))
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
			var pc := p
			var pair = _perf.get("pair")
			if pair != null and is_instance_valid(pair) and (pair as Node3D).visible:
				# two dancers: centred between them, far enough back for both, chest height
				var other := pair as WorldCharacter
				pc = (p + other.global_position) * 0.5
				var gap := Vector2(other.global_position.x - p.x, other.global_position.z - p.z).length()
				r = maxf(r, 2.4 + gap * 1.1)
				look = (mika.chest.global_position + other.chest.global_position) * 0.5
			pos = pc + Vector3(-sin(yaw), 0, -cos(yaw)) * r + Vector3(0, float(sh.height), 0)
			if main.world and main.world.has_method("ground_at"):
				pos.y = maxf(pos.y, float(main.world.ground_at(pos.x, pos.z)) + 0.25)
			fov = float(sh.fov)
			pos = _clear_line(_perf_look("chest"), _clear_line(look, pos))
			# (pulled in against a trunk to under 1.8 m, the lens saw only grass: that counts as blocked too)
			if not _sees_dancers(pos, pair) or pos.distance_to(_perf_look("chest")) < 1.8:
				# something solid between the lens and the dancers (a ruin wall, a column): swing the shot round to
				# the first open side and keep that side for the rest of the shot (no flicker between sides)
				for off in [0.8, -0.8, 1.6, -1.6, PI]:
					var y2: float = yaw + float(off)
					var p2 := pc + Vector3(-sin(y2), 0, -cos(y2)) * r + Vector3(0, float(sh.height), 0)
					if main.world and main.world.has_method("ground_at"):
						p2.y = maxf(p2.y, float(main.world.ground_at(p2.x, p2.z)) + 0.25)
					p2 = _clear_line(_perf_look("chest"), _clear_line(look, p2))
					if _sees_dancers(p2, pair) and p2.distance_to(_perf_look("chest")) >= 1.8:
						pos = p2
						_perf.yaw0 = float(_perf.yaw0) + float(off)
						break
			_apply(pos, look, fov, delta)
			return
		"chase":
			# the rig's spring arm handles collisions; we only steer its yaw/pitch behind her heading
			var moving := Vector2(mika.velocity.x, mika.velocity.z).length() > 0.3
			var k := 1.0 - exp(-(2.2 if moving else 0.6) * delta)
			# the other mage between the lens and her (Luna walking right behind her: the chase shot was all Luna with
			# Mika hidden in front of her, 20 October): the lens swings round to a side that sees Mika and stays there
			# while Luna is close behind; back to straight behind her once the line is clear for a while
			var head0 := mika.global_position + Vector3(0, 1.3, 0)
			var rel := rig.camera.global_position - head0
			if _mate_blocks(rig.camera.global_position, head0):
				_chase_mate_clear = 0.0
				if _chase_mate_tgt == 0.0 or _mate_blocks(head0 + rel.rotated(Vector3.UP, _chase_mate_tgt - _chase_mate_off), head0):
					for off: float in [0.9, -0.9, 1.5, -1.5, 2.2, -2.2]:
						if not _mate_blocks(head0 + rel.rotated(Vector3.UP, off - _chase_mate_off), head0):
							_chase_mate_tgt = off
							# a cut, not a glide: the glide still showed Luna's back for half a second
							_chase_mate_off = off
							rig.yaw = mika.rotation.y + off
							rig.rotation = Vector3(rig.pitch, rig.yaw, 0.0)
							break
			else:
				_chase_mate_clear += delta
				if _chase_mate_clear > 4.0:
					_chase_mate_tgt = 0.0
			_chase_mate_off = lerpf(_chase_mate_off, _chase_mate_tgt, 1.0 - exp(-3.0 * delta))
			rig.yaw = lerp_angle(rig.yaw, mika.rotation.y + _chase_mate_off, maxf(k, 1.0 - exp(-3.0 * delta)) if _chase_mate_tgt != 0.0 else k)
			# spring arm squeezed by a wall, or a wall / house between the lens and her: rise quickly, and swing
			# round to the most open side (a doorway, a narrow lane) instead of ending up inside her hair or
			# staring at a wall with her behind it
			var hit_len := rig.arm.get_hit_length()
			var squeezed := hit_len < 1.6
			var head := mika.global_position + Vector3(0, 1.45, 0)
			var oq := PhysicsRayQueryParameters3D.create(rig.camera.global_position, head, 1 | 4)
			oq.exclude = [mika.get_rid()]
			var ohit := mika.get_world_3d().direct_space_state.intersect_ray(oq)
			_chase_hidden_t = (_chase_hidden_t + delta) if (not ohit.is_empty() and (ohit.position as Vector3).distance_to(head) > 0.5) else 0.0
			if squeezed or _chase_hidden_t > 0.5:
				var best_yaw := rig.yaw
				var best_len := hit_len if not squeezed else _arm_room(rig.yaw, rig.pitch)
				for off: float in [0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4]:
					var room := _arm_room(rig.yaw + off, rig.pitch)
					if room > best_len + 0.35:
						best_len = room
						best_yaw = rig.yaw + off
				rig.yaw = lerp_angle(rig.yaw, best_yaw, 1.0 - exp(-5.0 * delta))
			var tight := hit_len < 1.0
			rig.pitch = lerpf(rig.pitch, -0.85 if tight else (-0.62 if squeezed else -0.2), 1.0 - exp(-(9.0 if tight else 6.0) * delta) if squeezed else k)
			# last resort: the arm stays crushed against something whichever way it turns - take a validated shot
			# (lens above her waist, 1.3 m+ away, a clear line to her head) and hold it until there is room again
			_chase_tight_t = (_chase_tight_t + delta) if tight else 0.0
			if _chase_tight_t > 0.3 and not _chase_override:
				var f2 := -mika.global_transform.basis.z
				var alt := _solve_shot(p, p + Vector3(0, 1.3, 0) + Vector3(f2.x, 0, f2.z).normalized() * 1.5, 55.0, Vector3(f2.x, 0, f2.z).normalized())
				if alt != Vector3.INF:
					_chase_override = true
					_override_pos = alt
			if _chase_override:
				if _arm_room(rig.yaw, rig.pitch) > 2.2 or p.distance_to(_override_pos) > 7.0:
					_chase_override = false
					rig.clear_shot()
				else:
					rig.set_shot(_override_pos, p + Vector3(0, 1.3, 0), 55.0)
					_pos = _override_pos
					return
			rig.distance = lerpf(rig.distance, 3.6, k)
			_pos = rig.camera.global_position
			return
		"establishing":
			pos = _establish_target[0]
			look = _establish_target[1].lerp(p + Vector3(0, 1.2, 0), 0.25)
			fov = 55.0
			if _clear_line(look, pos).distance_to(pos) > 1.0:
				_establish_until = 0.0          # something came between: dropped (cuts away next frame)
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
			# (no shot / reverse shot onto the speaker's face any more: the permanent no-close-up rule)
			if false and _conv_ots != null and is_instance_valid(_conv_ots.speaker) and is_instance_valid(_conv_ots.listener):
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
			look = mid.lerp(p, 0.15) + Vector3(0, 1.0, 0)
			fov = 46.0
		"activity":
			var it := _interaction
			if it == null or not is_instance_valid(it):     # the interaction just ended: back to following her
				_switch("chase")
				return
			var obj: Vector3 = it.get_parent().to_global(it.face_point) if it.face_point != null else it.global_position
			if it.book_id != "" and BookReader.instance and BookReader.instance.reading() and it.book_xf != null:
				# reading: a medium-wide three-quarter from her side, her and the lectern whole (no close-up)
				var anchor: Vector3 = BookReader.instance.current.anchor
				pos = p + right * _side * 2.6 + fwd * 1.2 + Vector3(0, 1.45, 0)
				look = anchor.lerp(p + Vector3(0, 1.0, 0), 0.5)
				fov = 48.0
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
			pos = _clear_line(p + Vector3(0, 1.5, 0), pos)
			if not _frame_ok(pos, look, fov, p + Vector3(0, 1.5, 0), p.y):
				var alt := _solve_shot(p, look, fov, fwd)
				if alt != Vector3.INF:
					pos = alt
			_apply(pos, look, fov, delta)
			return
	pos = _clear_line(look, pos)
	_apply(pos, look, fov, delta)


## The stream's framing (Part 5 look pass): every shot a little wider and further back so the world shows round
## them - except the trailer-cut fights, which stay close on purpose. Pulled back only as far as the line of sight is
## clear (never behind a bush or into a wall).
const WIDE_FOV := 1.12
const PULL_BACK := 1.18


func _apply(pos: Vector3, look: Vector3, fov: float, delta: float, rate := 3.0) -> void:
	if mika and not (mode in ["combat", "signature"]) and not RenderProfile.options.has("no-wide"):
		fov = minf(fov * WIDE_FOV, 66.0)
		pos = _clear_line(look, look + (pos - look) * PULL_BACK) if (pos - look).length() > 0.7 else pos
	var as_set := pos
	# never inside something solid, whatever shot asked for it (a ray from inside a rock reports nothing: the overlap
	# test does) - pulled toward what it looks at, and up, until it is in open air
	if mika:
		var space := mika.get_world_3d().direct_space_state
		var tries := 0
		while CombatFraming.inside_solid(space, pos) and tries < 14:
			pos = pos.lerp(look, 0.12) + Vector3(0, 0.22, 0)
			tries += 1
		# nor rubbing against one (a post filling a quarter of the frame) or tucked under a roof she is not under
		# (its dark underside across the top of the picture): stepped toward her until it is in the open
		tries = 0
		while tries < 8 and pos.distance_to(look) > 1.6 and _crowded(space, pos, look):
			pos = pos.lerp(look, 0.14)
			tries += 1
		# an authored wide shot only plays from where it was set: one that has to be walked toward its subject to be
		# clean is dropped (the library's lens ended at the stair mouth looking down the unlit stairwell: near-black)
		if mode == "establishing" and pos.distance_to(as_set) > 1.5:
			_establish_until = 0.0
	# she is IN the shot: in a director-made frame (a fight, a conversation, an activity) her head must be inside
	# the view and not behind something solid - otherwise the shot is re-solved round her instead of trusted
	if mika and mode in ["combat", "conversation", "activity", "spell"]:
		var head := mika.global_position + Vector3(0, 1.45, 0)
		var seen := rad_to_deg((look - pos).angle_to(head - pos)) < fov * 0.5 * 0.85
		if seen:
			var vq := PhysicsRayQueryParameters3D.create(pos, head, 1 | 4)
			vq.exclude = [mika.get_rid()]
			var vh := mika.get_world_3d().direct_space_state.intersect_ray(vq)
			seen = vh.is_empty() or (vh.position as Vector3).distance_to(head) < 0.5
		if not seen:
			var f3 := -mika.global_transform.basis.z
			var alt := _solve_shot(mika.global_position, look.lerp(head, 0.6), maxf(fov, 50.0), Vector3(f3.x, 0, f3.z).normalized())
			if alt != Vector3.INF:
				pos = alt
				look = look.lerp(head, 0.6)
	# never looking up at her from below her waist when the lens is near her (any shot the director makes)
	if mika and mode != "scene":
		var fp := mika.global_position
		if Vector2(pos.x - fp.x, pos.z - fp.z).length() < 5.0 and pos.y < fp.y + 1.1:
			pos.y = fp.y + 1.1
	# PERMANENT RULE: never a close-up - no mage's face over 10% of the frame height, knees-up or wider (FramingRule)
	if mika:
		var chars: Array = main.characters.values() if main and main.get("characters") else [mika]
		var fr := FramingRule.enforce(pos, look, fov, FramingRule.heads_of(chars), mika.get_world_3d().direct_space_state)
		pos = fr.pos
		look = fr.look
		fov = fr.fov
	# a fight's shot change is a CUT (eased, the lens swept between two angles - through a fighter, 2026-10-17)
	var cut := _since_change < 0.05 and (_pos.distance_to(pos) > 4.0 or not rig.shot_active or mode == "combat")
	if cut or not rig.shot_active:
		_pos = pos
		_look = look
		_fov = fov
	else:
		var k2 := 1.0 - exp(-rate * delta)
		_pos = _pos.lerp(pos, k2)
		_look = _look.lerp(look, k2)
		_fov = lerpf(_fov, fov, k2)
		# the eased lens itself never passes through (or brushes) a body: if it would, it takes the target at once
		if main and main.get("characters") and _lens_in_body(_pos) and not _lens_in_body(pos):
			_pos = pos
			_look = look
			_fov = fov
	# the eased lens lags its target: in a frame that must hold her (an activity, a talk, a spell) she never drifts
	# out of view while it catches up - if the lens actually used would lose her head, it cuts to the target shot
	if mika and mode in ["conversation", "activity", "spell"]:
		var hd0 := mika.global_position + Vector3(0, 1.45, 0)
		var in_eased := rad_to_deg((_look - _pos).angle_to(hd0 - _pos)) < _fov * 0.5 * 0.92
		var in_target := rad_to_deg((look - pos).angle_to(hd0 - pos)) < fov * 0.5 * 0.92
		if not in_eased and in_target:
			_pos = pos
			_look = look
			_fov = fov
	# the eased path between two safe shots can cross a rock too: the lens actually used is checked as well
	if mika and CombatFraming.inside_solid(mika.get_world_3d().direct_space_state, _pos):
		_pos = pos
	# and whatever shot this is (a staged scene included): open air round the lens and a clear view of what it looks
	# at - a lens pressed against a boulder fills the screen with rock (QA: a black screen while Luna spoke)
	if mika and mode == "establishing" and not _view_ok(_pos, _look):
		_establish_until = 0.0          # an authored wide shot with its view blocked is dropped, not re-placed
	elif mika and not _view_ok(_pos, _look):
		var rs := _rescue_shot(_pos, _look)
		if rs != Vector3.INF:
			_pos = rs
	# the eased lens itself (not only its target): above her waist when near her, and never closer than 0.9 m to her head
	if mika and mode != "scene":
		var fp2 := mika.global_position
		if Vector2(_pos.x - fp2.x, _pos.z - fp2.z).length() < 5.0 and _pos.y < fp2.y + 1.1:
			_pos.y = fp2.y + 1.1
		var hd := fp2 + Vector3(0, 1.45, 0)
		if _pos.distance_to(hd) < 0.95:
			var away := (_pos - hd)
			away = away.normalized() if away.length() > 0.01 else (_look - hd).normalized() * -1.0
			_pos = hd + away * 0.95
	# LAST, after every adjustment above (each of which can step the lens toward the look point - between two
	# fighters, into one of them): never inside or brushing ANY mage's body - pushed straight out to 1.2 m
	if main and main.get("characters"):
		# (two bodies close together: out of one ring can be into the other - a few passes, then over their heads)
		var top := -INF
		for _pass in 3:
			var moved := false
			for c in main.characters.values():
				var w := c as WorldCharacter
				if w == null or not w.visible:
					continue
				var bp := w.global_position
				top = maxf(top, bp.y)
				var off := Vector2(_pos.x - bp.x, _pos.z - bp.z)
				if off.length() < 1.2 and _pos.y > bp.y - 0.2 and _pos.y < bp.y + 2.1:
					var dir2 := off.normalized() if off.length() > 0.05 else Vector2(_pos.x - _look.x, _pos.z - _look.z).normalized()
					_pos = Vector3(bp.x + dir2.x * 1.2, _pos.y, bp.z + dir2.y * 1.2)
					moved = true
			if not moved:
				break
		if _lens_in_body(_pos):
			_pos.y = top + 2.25
	if mode == "combat" and mika:
		_combat_guard(delta)
	rig.set_shot(_pos, _look, _fov)


var _blocked_t := 0.0

## A fight's frame: the fighters must be in it and seen. Neither in view -> aimed back at them at once; one of them
## behind something solid (a post, a rock) for more than a quarter second -> the fight camera picks a new angle.
func _combat_guard(delta: float) -> void:
	var fighters: Array = []
	for c in main.characters.values():
		if (c as WorldCharacter).visible and (c as WorldCharacter).global_position.distance_to(mika.global_position) < 14.0:
			fighters.append(c)
	var any_in := false
	for c in fighters:
		var hd := (c as Node3D).global_position + Vector3(0, 1.2, 0)
		if rad_to_deg((_look - _pos).angle_to(hd - _pos)) < _fov * 0.5 * 0.9:
			any_in = true
	if not any_in:
		var mid := Vector3.ZERO
		for c in fighters:
			mid += (c as Node3D).global_position + Vector3(0, 1.15, 0)
		_look = mid / maxf(float(fighters.size()), 1.0)
	var space := mika.get_world_3d().direct_space_state
	var ex: Array = []
	for c in fighters:
		ex.append((c as CollisionObject3D).get_rid())
	var blocked := false
	for c in fighters:
		for hgt in [1.15, 0.8]:
			var aim := (c as Node3D).global_position + Vector3(0, hgt, 0)
			var q := PhysicsRayQueryParameters3D.create(_pos, aim, 1 | 4)
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit.position as Vector3).distance_to(aim) > 0.5:
				blocked = true
	_blocked_t = _blocked_t + delta if blocked else 0.0
	if _blocked_t > 0.25:
		_trailer.since = 99.0           # a new shot next frame (its own clearance test rejects this angle)
		_blocked_t = 0.0


func _view_ok(pos: Vector3, look: Vector3) -> bool:
	var space := mika.get_world_3d().direct_space_state
	if CombatFraming.inside_solid(space, pos, 0.35):
		return false
	var q := PhysicsRayQueryParameters3D.create(pos, look, 1 | 4)
	q.exclude = [mika.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(look) < 0.6


## A valid lens near the intended one: round what it looks at (2.5-4 m, a little above it), open air, a clear view;
## the one closest in direction to the shot that was asked for.
func _rescue_shot(pos: Vector3, look: Vector3) -> Vector3:
	var want := Vector3(pos.x - look.x, 0, pos.z - look.z)
	want = want.normalized() if want.length() > 0.05 else Vector3.BACK
	var best := Vector3.INF
	var best_s := -INF
	for dist: float in [2.6, 3.4, 4.2]:
		for deg: float in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0, 180.0]:
			for up: float in [0.3, 0.8]:
				var c := look + want.rotated(Vector3.UP, deg_to_rad(deg)) * dist + Vector3(0, up, 0)
				if not _view_ok(c, look):
					continue
				var sc := -absf(deg) * 0.02 - dist * 0.2 - up * 0.3
				if sc > best_s:
					best_s = sc
					best = c
	return best


var _conv_pick := {}
var _conv_ots = null          # {speaker, listener} while a substantive line is spoken in a conversation
var _conv_lines := 0


## 1.0 when something solid stands just behind the subjects on the camera's line (within 3 m), 0 when open.
func _background_clutter(cam: Vector3, at: Vector3) -> float:
	var dir := (at - cam).normalized()
	var q := PhysicsRayQueryParameters3D.create(at + dir * 0.6, at + dir * 3.6)
	q.collision_mask = 1 | 4
	var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
	return 0.0 if hit.is_empty() else 1.0 - clampf((at.distance_to(hit.position) - 0.6) / 3.0, 0.0, 1.0)


func _two_clear(cam: Vector3, a: Vector3, b: Vector3) -> bool:
	var space := mika.get_world_3d().direct_space_state
	for t in [a, b]:
		var q := PhysicsRayQueryParameters3D.create(cam, t + Vector3(0, 1.4, 0))
		q.collision_mask = 1 | 4
		q.exclude = [mika.get_rid()] + ([_conversation.get_rid()] if _conversation is CollisionObject3D else [])
		if not space.intersect_ray(q).is_empty():
			return false
	return true


## Keep the subject visible: if geometry blocks the line from the subject to the camera, move the
## camera to just in front of the obstruction.
func _crowded(space: PhysicsDirectSpaceState3D, pos: Vector3, look: Vector3) -> bool:
	var ex: Array[RID] = []
	for c in main.characters.values():
		if c is CollisionObject3D:
			ex.append((c as CollisionObject3D).get_rid())
	for j in 8:                                       # level probes: the ground under a low lens never counts
		var a := TAU * j / 8.0
		var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(cos(a), 0, sin(a)) * 0.6, 1 | 4)
		q.exclude = ex
		if not space.intersect_ray(q).is_empty():
			return true
	var up := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, 3.0, 0), 1)
	up.exclude = ex
	if space.intersect_ray(up).is_empty():
		return false
	var up2 := PhysicsRayQueryParameters3D.create(look, look + Vector3(0, 3.0, 0), 1)
	up2.exclude = ex
	return space.intersect_ray(up2).is_empty()        # the lens is under a roof and she is not


## The dancer's head and chest (and her partner's chest) can be seen from `cam`: nothing solid in between.
func _sees_dancers(cam: Vector3, pair) -> bool:
	var space := mika.get_world_3d().direct_space_state
	var ex: Array[RID] = [mika.get_rid()]
	var targets: Array = [mika.global_position + Vector3(0, 1.45, 0), mika.chest.global_position]
	if pair != null and is_instance_valid(pair) and (pair as Node3D).visible:
		ex.append((pair as CollisionObject3D).get_rid())
		targets.append((pair as WorldCharacter).chest.global_position)
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(cam, t, 0xFFFFFFFF)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(t) > 0.35:
			return false
	return true


func _clear_line(subject: Vector3, cam: Vector3) -> Vector3:
	var space := mika.get_world_3d().direct_space_state
	# start a little out from the subject: a look point ON an object (a plaque, a notice board) sits inside that
	# object's collider, and a ray from there "hits" at once - which used to put the lens 0.35 m from the object,
	# low and looking up
	var dir := cam - subject
	if dir.length() < 0.7:
		return cam
	var start := subject + dir.normalized() * 0.6
	var q := PhysicsRayQueryParameters3D.create(start, cam, 1 | 4)
	q.exclude = [mika.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return cam
	var hp: Vector3 = hit.position
	return hp + (subject - hp).normalized() * 0.35


## A shot a viewer can watch: the lens above her waist (never looking up at her), not inside her, her head in
## frame and not hidden behind a wall. (InvariantAuditor checks the same on whatever the camera shows.)
## How far the chase arm could reach at this yaw / pitch before something solid (world and vegetation).
func _arm_room(yaw: float, pitch: float) -> float:
	var from := mika.global_position + Vector3(0, rig.height, 0)
	var dir := Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, 1)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * rig.distance, 1 | 4)
	q.exclude = [mika.get_rid()]
	var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
	return rig.distance if hit.is_empty() else from.distance_to(hit.position)


func _frame_ok(pos: Vector3, look: Vector3, fov: float, head: Vector3, feet_y: float) -> bool:
	if pos.y < feet_y + 1.15 or pos.distance_to(head) < 1.3:
		return false
	if CombatFraming.inside_solid(mika.get_world_3d().direct_space_state, pos):
		return false
	var ang := rad_to_deg((look - pos).angle_to(head - pos))
	if ang > fov * 0.5 * 0.8:
		return false
	var q := PhysicsRayQueryParameters3D.create(pos, head, 1 | 4)
	q.exclude = [mika.get_rid()]
	var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.position as Vector3).distance_to(head) < 0.4


## Search round her for a watchable shot of her and what she is doing (behind a shoulder first, then the sides).
func _solve_shot(p: Vector3, look: Vector3, fov: float, fwd: Vector3) -> Vector3:
	var head := p + Vector3(0, 1.5, 0)
	var best := Vector3.INF
	var best_s := -INF
	for dist: float in [2.4, 3.1, 3.9]:
		for deg: float in [150.0, -150.0, 125.0, -125.0, 100.0, -100.0, 180.0, 70.0, -70.0]:
			var d := fwd.rotated(Vector3.UP, deg_to_rad(deg))
			var c := p + d * dist + Vector3(0, 1.75 + dist * 0.12, 0)
			if not _frame_ok(c, look, fov, head, p.y):
				continue
			# what she works on should be visible from there too
			var q := PhysicsRayQueryParameters3D.create(c, look, 1 | 4)
			q.exclude = [mika.get_rid()]
			var hit := mika.get_world_3d().direct_space_state.intersect_ray(q)
			var sees := hit.is_empty() or (hit.position as Vector3).distance_to(look) < 0.6
			var sc := (2.0 if sees else 0.0) - dist * 0.3 - absf(absf(deg) - 145.0) * 0.008 + (0.3 if signf(deg) == signf(_side) else 0.0)
			if sc > best_s:
				best_s = sc
				best = c
	return best


static func _arr(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Is a lens here inside or brushing a mage's body (1.0 m round her, feet to above the head)?
func _lens_in_body(p: Vector3) -> bool:
	for c in main.characters.values():
		var w := c as WorldCharacter
		if w and w.visible:
			var bp := w.global_position
			if Vector2(p.x - bp.x, p.z - bp.z).length() < 1.15 and p.y > bp.y - 0.2 and p.y < bp.y + 2.1:
				return true
	return false
