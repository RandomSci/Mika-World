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


func setup(m: Node) -> void:
	main = m
	rig = main.camera_rig
	mika = main.characters["mika"]
	WorldState.interaction_started.connect(func(it, c): if c == mika: _interaction = it)
	WorldState.interaction_finished.connect(func(it, c, _r): if c == mika and _interaction == it: _interaction = null)


func focus_conversation(other: Node3D, seconds := 8.0) -> void:
	_conversation = other
	_conversation_until = _now() + seconds


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
		var urgent := want == "spell" or want == "activity"
		if _since_change < MIN_SHOT and not urgent and mode != "off":
			want = mode  # hold the current shot a little longer
		else:
			_switch(want)
	_frame(delta)


func _choose() -> String:
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
	if m == "spell" or m == "activity" or m == "conversation":
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
			pos = p + fwd * 2.6 + right * _side * 2.0 + Vector3(0, 0.75, 0)
			look = p + fwd * 1.6 + Vector3(0, 1.45, 0)
			fov = 54.0
		"conversation":
			var o := _conversation.global_position
			var mid := (p + o) * 0.5
			var axis := (o - p).normalized()
			var perp := Vector3(-axis.z, 0, axis.x) * _side
			pos = mid + perp * 3.2 + Vector3(0, 1.5, 0)
			look = mid + Vector3(0, 1.35, 0)
			fov = 45.0
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


func _apply(pos: Vector3, look: Vector3, fov: float, delta: float) -> void:
	var cut := _since_change < 0.05 and (_pos.distance_to(pos) > 4.0 or not rig.shot_active)
	if cut or not rig.shot_active:
		_pos = pos
		_look = look
		_fov = fov
	else:
		var k2 := 1.0 - exp(-3.0 * delta)
		_pos = _pos.lerp(pos, k2)
		_look = _look.lerp(look, k2)
		_fov = lerpf(_fov, fov, k2)
	rig.set_shot(_pos, _look, _fov)


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
