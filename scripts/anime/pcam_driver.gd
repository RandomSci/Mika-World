class_name PCamDriver
extends Node
## Ticks a PhantomCameraHost (interpolation MANUAL) once per rendered frame, after every other script (camera rigs,
## directors, framing guards), so Phantom Camera has the last word on the live camera during a cinematic.
var host: PhantomCameraHost
var roll := 0.0                        # radians: a dutch angle on whatever shot is live (anime roll)


func _init() -> void:
	process_priority = 1 << 29
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if host and is_instance_valid(host):
		host.process(delta)
		if absf(roll) > 0.0001:
			var cam := get_viewport().get_camera_3d()
			if cam:
				cam.rotate_object_local(Vector3.FORWARD, roll)
