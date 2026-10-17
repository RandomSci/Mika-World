class_name CameraPin
extends Node
## Tests only (the close-up stills): every frame, after every camera script and the framing guard, put the live
## camera exactly here, looking exactly there - nothing else may move it while a still is taken.
var pos := Vector3.ZERO
var look := Vector3.ZERO
var fov := 32.0
var active := false


func _init() -> void:
	process_priority = 1 << 30            # after everything (the director lifts the rig above itself)


func _process(_delta: float) -> void:
	if not active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	cam.top_level = true
	cam.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	cam.fov = fov
