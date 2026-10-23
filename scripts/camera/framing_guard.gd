class_name FramingGuard
extends Node
## Last line of defence for the permanent no-close-up rule (FramingRule, docs/world_look_rules.md): runs after every
## camera script each frame, and if the live camera frames a mage's face bigger than 10% of the frame height it pulls
## that camera back along its own view line (clear of walls) or opens the lens. Counts every correction in `hits`
## so QA can fail a scene whose own cameras break the rule.

var characters: Array = []       # WorldCharacter nodes (or anything with a `skeleton`)
var source: Node                 # or: a node with a `characters` dictionary, read every frame (mages spawned later)
var camera: Camera3D             # the camera to guard (default: whatever camera this viewport shows)
## Cameras this guard leaves alone: the transformation cinematics belong to the outfit session's system
## (Mika-Godot-Dev-L1Outfit), which keeps the camera rule itself.
const EXEMPT_CAMERAS := ["TransformCamera"]
var hits := 0
var worst_frac := 0.0


func _init() -> void:
	process_priority = 100000          # after every camera script


func _process(_delta: float) -> void:
	var cam := camera if camera and is_instance_valid(camera) else get_viewport().get_camera_3d()
	if cam == null or String(cam.name) in EXEMPT_CAMERAS:
		return
	if source and source.get("characters") is Dictionary:
		characters = (source.characters as Dictionary).values()
	var heads := FramingRule.heads_of(characters)
	if heads.is_empty():
		return
	var pos := cam.global_position
	var look := pos - cam.global_basis.z * 4.0
	for h in heads:
		var to_h: Vector3 = (h as Vector3) - pos
		if rad_to_deg((look - pos).angle_to(to_h)) <= cam.fov * 0.5 * 1.25:
			worst_frac = maxf(worst_frac, FramingRule.face_frac(pos, h, cam.fov))
	var r := FramingRule.enforce(pos, look, cam.fov, heads, cam.get_world_3d().direct_space_state)
	if r.changed:
		hits += 1
		cam.global_position = r.pos
		cam.fov = r.fov
	# (its pull back along the view line can end inside a crystal's keep-out: out again, 24 Oct)
	var kp := ThirdPersonCamera.out_of_keepouts(cam.get_world_3d().direct_space_state, cam.global_position)
	if kp != cam.global_position:
		cam.global_position = kp
