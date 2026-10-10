extends Node
## Registers the input map in code so it stays readable and version-controlled.

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"cast": [KEY_SPACE],
	"toggle_night": [KEY_N],
	"cycle_profile": [KEY_P],
	"toggle_hud": [KEY_H],
	"photo_mode": [KEY_C],
	"screenshot": [KEY_F12],
	"release_mouse": [KEY_ESCAPE],
	"sword_toggle": [KEY_R],
	"sword_attack": [KEY_F],
	"sword_power": [KEY_G],
	"sword_element": [KEY_T],
}


func _enter_tree() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
