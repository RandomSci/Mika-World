class_name PlayerController
extends Node
## Keyboard/mouse → WorldCharacter. WASD move (camera-relative), Shift run, Space cast.

var character: WorldCharacter
var camera_rig: ThirdPersonCamera
var spell_clip := "prepare_and_cast"
var enabled := true
var magic: MagicSystem
var spell_id := "arcane_orb"


func _physics_process(_delta: float) -> void:
	if not enabled or character == null:
		return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	if v.length() > 0.05:
		dir = camera_rig.planar_basis() * Vector3(v.x, 0, v.y)
	if dir != Vector3.ZERO or not character._nav_active:
		character.nav_bound = dir == Vector3.ZERO       # the player walks where she likes
		character.set_move_input(dir, Input.is_action_pressed("run"))


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or character == null:
		return
	if event.is_action_pressed("cast"):
		if magic:
			magic.cast(character, spell_id, auto_target())
		else:
			character.cast_spell(ArcaneOrbSpell, spell_clip)
	elif event.is_action_pressed("spell_cycle") and magic:
		var ids: Array = magic.known_spells().filter(func(x): return x.castable).map(func(x): return x.id)
		if not ids.is_empty():
			spell_id = ids[(ids.find(spell_id) + 1) % ids.size()]
	elif character.sword == null:
		return
	elif event.is_action_pressed("sword_toggle"):
		if character.sword.drawn:
			character.sword.sheathe()
		else:
			character.sword.draw()
	elif event.is_action_pressed("sword_attack"):
		character.sword.attack()
	elif event.is_action_pressed("sword_power"):
		character.sword.power_up()
	elif event.is_action_pressed("sword_element"):
		var keys: Array = SwordLayer.ELEMENTS.keys()
		character.sword.set_element(keys[(keys.find(character.sword.element) + 1) % keys.size()])


## The valid reactive target closest to the centre of the view (within ~25 degrees), or "" (cast ahead).
func auto_target() -> String:
	if magic == null:
		return ""
	var cam := camera_rig.camera
	var best := ""
	var best_ang := deg_to_rad(25.0)
	for d in magic.targets_for(spell_id, character):
		if not d.valid:
			continue
		var p := Vector3(d.aim_point[0], d.aim_point[1], d.aim_point[2])
		var ang := (-cam.global_transform.basis.z).angle_to((p - cam.global_position).normalized())
		if ang < best_ang:
			best_ang = ang
			best = d.id
	return best
