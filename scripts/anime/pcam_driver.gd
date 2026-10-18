class_name PCamDriver
extends Node
## Ticks a PhantomCameraHost (interpolation MANUAL) once per rendered frame, after every other script (camera rigs,
## directors, framing guards), so Phantom Camera has the last word on the live camera during a cinematic.
var host: PhantomCameraHost


func _init() -> void:
	process_priority = 1 << 29
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if host and is_instance_valid(host):
		host.process(delta)
