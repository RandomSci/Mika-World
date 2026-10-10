class_name ThirdPersonCamera
extends Node3D
## Orbiting third-person camera with spring-arm collision.
## Mouse: click to capture (or hold right button) and move to orbit; wheel zooms; Esc releases.
## `set_shot(pos, look)` overrides the rig for scripted cinematic shots (tour / photo mode).

@export var target: Node3D
@export var height := 1.38
@export var distance := 3.4
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
	camera.fov = 52.0
	camera.near = 0.05
	camera.far = 600.0
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
	_shot_pos = pos
	_shot_look = look
	camera.fov = fov


func clear_shot() -> void:
	shot_active = false
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
	camera.fov = 52.0


## Planar forward of the camera, for camera-relative movement.
func planar_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func _process(delta: float) -> void:
	if shot_active:
		camera.top_level = true
		camera.global_transform = Transform3D(Basis.looking_at(_shot_look - _shot_pos, Vector3.UP), _shot_pos)
		return
	if target == null:
		return
	var desired := target.global_position + Vector3(0, height, 0)
	_focus = _focus.lerp(desired, 1.0 - exp(-14.0 * delta))
	global_position = _focus
	rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = lerpf(arm.spring_length, distance, 1.0 - exp(-10.0 * delta))
