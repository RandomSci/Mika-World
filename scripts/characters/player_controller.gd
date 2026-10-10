class_name PlayerController
extends Node
## Keyboard/mouse → WorldCharacter. WASD move (camera-relative), Shift run, Space cast.

var character: WorldCharacter
var camera_rig: ThirdPersonCamera
var spell_clip := "prepare_and_cast"
var enabled := true


func _physics_process(_delta: float) -> void:
	if not enabled or character == null:
		return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	if v.length() > 0.05:
		dir = camera_rig.planar_basis() * Vector3(v.x, 0, v.y)
	if dir != Vector3.ZERO or not character._nav_active:
		character.set_move_input(dir, Input.is_action_pressed("run"))


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or character == null:
		return
	if event.is_action_pressed("cast"):
		character.cast_spell(ArcaneOrbSpell, spell_clip)
