extends Node3D
## Composition root: world + characters + camera + player control + AI bridge (+ optional tour).
## Characters live in a registry so a second character (the mentor) can be added
## without anything depending on a single hard-coded Mika node.

var world: Sanctuary
var characters := {}
var camera_rig: ThirdPersonCamera
var player: PlayerController
var bridge: ActionBridge
var hud: Label
var _fps_acc := 0.0
var _fps_frames := 0


func _ready() -> void:
	RenderProfile.apply_to_viewport(get_viewport())
	print("[main] renderer=%s/%s adapter=%s profile=%s night=%s" % [RenderingServer.get_current_rendering_driver_name(),
			RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), RenderProfile.profile, RenderProfile.night])
	world = Sanctuary.new()
	world.name = "Sanctuary"
	add_child(world)

	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)
	var mika := spawn_character("mika", "Mika", "res://assets/characters/mika/Mika.vrm", world.spawn_point("mika"), chars)

	camera_rig = ThirdPersonCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = mika
	add_child(camera_rig)

	player = PlayerController.new()
	player.character = mika
	player.camera_rig = camera_rig
	add_child(player)

	bridge = ActionBridge.new()
	bridge.name = "ActionBridge"
	add_child(bridge)
	bridge.setup(world, characters, camera_rig.camera)

	_build_hud()
	if RenderProfile.tour:
		var tour := TourRunner.new()
		tour.main = self
		add_child(tour)
	print("[main] ready. WASD move | Shift run | Space cast | mouse orbit (click to capture, Esc release) | N night | P profile | H hud | F12 screenshot")


## Spawn any VRM humanoid into the world. Future companion: spawn_character("mentor", ..., world.spawn_point("companion"), ...)
func spawn_character(id: String, display: String, avatar_path: String, at: Transform3D, parent: Node3D) -> WorldCharacter:
	var c := WorldCharacter.new()
	c.name = display
	c.character_id = id
	c.display_name = display
	c.avatar_path = avatar_path
	c.world = world
	parent.add_child(c)
	c.global_transform = at
	characters[id] = c
	return c


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hud.add_theme_constant_override("outline_size", 5)
	hud.visible = not RenderProfile.tour
	layer.add_child(hud)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_night"):
		world.set_night(not world.night)
	elif event.is_action_pressed("cycle_profile"):
		RenderProfile.cycle_profile()
	elif event.is_action_pressed("toggle_hud"):
		hud.visible = not hud.visible
	elif event.is_action_pressed("screenshot"):
		var path := "%s/manual_%s.png" % [RenderProfile.shots_dir, Time.get_datetime_string_from_system().replace(":", "-")]
		get_viewport().get_texture().get_image().save_png(path)
		print("[main] saved ", path)


func _process(delta: float) -> void:
	_fps_acc += delta
	_fps_frames += 1
	if _fps_acc >= 0.5 and hud.visible:
		var mika: WorldCharacter = characters["mika"]
		hud.text = "MIKA WORLD 2.0 · DEV  |  %s  |  %.0f fps (%.1f ms)  |  %s\nArea: %s   Action: %s\nWASD move · Shift run · Space cast · Mouse orbit (click) · Wheel zoom · N day/night · P profile · H hide" % [
			RenderProfile.profile, _fps_frames / _fps_acc, 1000.0 * _fps_acc / _fps_frames, "NIGHT" if world.night else "DAY",
			world.area_at(mika.global_position), mika.current_action]
		_fps_acc = 0.0
		_fps_frames = 0
