class_name ThirdPersonCamera
extends Node3D
## Orbiting third-person camera with spring-arm collision.
## Mouse: click to capture (or hold right button) and move to orbit; wheel zooms; Esc releases.
## `set_shot(pos, look)` overrides the rig for scripted cinematic shots (tour / photo mode).

@export var target: Node3D
@export var height := 1.38
@export var distance := 4.0
@export var min_distance := 1.4
@export var max_distance := 9.0
@export var sensitivity := 0.0032

var yaw := 0.0
var pitch := -0.18
var camera: Camera3D
var arm: SpringArm3D
var shot_active := false
var _shot_pos := Vector3.ZERO
var _shot_look := Vector3.ZERO
var _rmb := false
var _focus := Vector3.ZERO


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.spring_length = distance
	arm.margin = 0.15
	var probe := SphereShape3D.new()
	probe.radius = 0.18
	arm.shape = probe
	arm.position = Vector3(0.3, 0, 0)  # slight over-the-shoulder framing (camera itself is placed by the arm)
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 6000.0  # distant vistas are placed up to ~3.4 km away
	arm.add_child(camera)
	camera.current = true
	if target:
		_focus = target.global_position + Vector3(0, height, 0)
		yaw = target.rotation.y
		if target is CollisionObject3D:
			arm.add_excluded_object((target as CollisionObject3D).get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance * 0.9, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance * 1.1, min_distance, max_distance)
	elif event is InputEventMouseMotion and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _rmb):
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * sensitivity
		pitch = clampf(pitch - mm.relative.y * sensitivity, -1.2, 0.55)
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_shot(pos: Vector3, look: Vector3, fov := 50.0) -> void:
	shot_active = true
	# the spring arm would keep re-placing its child camera every physics frame (fighting the directed shot,
	# and giving anything that reads the camera position mid-frame the arm's position): pause it
	arm.process_mode = Node.PROCESS_MODE_DISABLED
	_shot_pos = pos
	_shot_look = look
	camera.fov = fov


## After a transition: put the camera behind the character immediately (no swooping across the map).
func snap_behind() -> void:
	if target:
		yaw = target.rotation.y
		pitch = -0.18
		_focus = target.global_position + Vector3(0, height, 0)
		global_position = _focus
		rotation = Vector3(pitch, yaw, 0)
		arm.spring_length = distance


func clear_shot() -> void:
	shot_active = false
	arm.process_mode = Node.PROCESS_MODE_INHERIT
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
	camera.fov = 58.0


## Planar forward of the camera, for camera-relative movement.
func planar_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func _process(delta: float) -> void:
	if shot_active:
		camera.top_level = true
		var at := _clear_of_bodies(_shot_pos, _shot_look)
		var dir := _shot_look - at
		if dir.length_squared() > 1e-6:
			# straight up/down shots need another up vector (avoids a degenerate basis)
			var up := Vector3.UP if absf(dir.normalized().y) < 0.995 else Vector3.FORWARD
			camera.global_transform = Transform3D(Basis.looking_at(dir, up), at)
		return
	if target == null:
		return
	var desired := target.global_position + Vector3(0, height, 0)
	if desired.distance_to(_focus) > 6.0:
		_focus = desired          # she arrived somewhere new (a travel, a fold): the lens is with her at once, not sweeping in
	_focus = _focus.lerp(desired, 1.0 - exp(-14.0 * delta))
	global_position = _focus
	rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = lerpf(arm.spring_length, distance, 1.0 - exp(-10.0 * delta))


## The very last word on where a directed lens stands: never inside or brushing a mage's body (1.15 m round her,
## feet to above the head) - whichever system asked for the shot, in whatever frame order (2026-10-17: a spar's
## lens ended in a fighter on frames the director's own checks never saw). Pushed straight out; between two bodies
## standing close, lifted over their heads.
func _clear_of_bodies(p: Vector3, look: Vector3) -> Vector3:
	var bodies: Array = []
	for n in get_tree().get_nodes_in_group("avoid"):
		if n is WorldCharacter and (n as Node3D).is_visible_in_tree():
			bodies.append(n)
	var top := -INF
	for _pass in 3:
		var moved := false
		for b in bodies:
			var bp: Vector3 = (b as Node3D).global_position
			top = maxf(top, bp.y)
			var off := Vector2(p.x - bp.x, p.z - bp.z)
			if off.length() < 1.15 and p.y > bp.y - 0.2 and p.y < bp.y + 2.1:
				var d2 := off.normalized() if off.length() > 0.05 else Vector2(p.x - look.x, p.z - look.z).normalized()
				p = Vector3(bp.x + d2.x * 1.15, p.y, bp.z + d2.y * 1.15)
				moved = true
		if not moved:
			return p
	return Vector3(p.x, top + 2.25, p.z)
