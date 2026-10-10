extends Node3D
## Composition root. Persistent across the whole session: Mika (and future characters), camera,
## controls, AI bridge, HUD, travel overlay. Areas are streamed in/out underneath by
## WorldStreamingManager; `world` always refers to the currently active area.

var streaming: WorldStreamingManager
var travel: TravelController
var characters := {}
var camera_rig: ThirdPersonCamera
var player: PlayerController
var bridge: ActionBridge
var overlay: TravelOverlay
var hud: Label
var prompt: Label
var _fps_acc := 0.0
var _fps_frames := 0

var world: AreaBase:
	get: return streaming.current if streaming else null


func _ready() -> void:
	RenderProfile.apply_to_viewport(get_viewport())
	WorldState.night = RenderProfile.night
	print("[main] renderer=%s/%s adapter=%s profile=%s night=%s" % [RenderingServer.get_current_rendering_driver_name(),
			RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), RenderProfile.profile, RenderProfile.night])
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_E
		InputMap.action_add_event("interact", ev)

	overlay = TravelOverlay.new()
	add_child(overlay)
	streaming = WorldStreamingManager.new()
	streaming.name = "WorldStreaming"
	streaming.overlay = overlay
	add_child(streaming)

	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)
	var mika := spawn_character("mika", "Mika", "res://assets/characters/mika/Mika.vrm", Transform3D.IDENTITY, chars)
	mika.set_physics_process(false)

	camera_rig = ThirdPersonCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = mika
	add_child(camera_rig)
	streaming.camera_rig = camera_rig

	player = PlayerController.new()
	player.character = mika
	player.camera_rig = camera_rig
	add_child(player)

	travel = TravelController.new()
	travel.name = "Travel"
	travel.streaming = streaming
	travel.character = mika
	add_child(travel)
	mika.action_finished.connect(travel.on_character_action)

	_build_hud()

	# Start location: --start=<location_id> or the registry default.
	var start: String = RenderProfile.options.get("start", WorldState.registry.start_location)
	if not WorldState.locations.has(start):
		start = WorldState.registry.start_location
	var report := await streaming.travel(WorldState.area_of(start), mika)
	if not report.get("ok", false):
		push_error("[main] could not load start area: %s" % report)
		return
	if start != WorldState.registry.start_location and world.points_of_interest.has(start):
		mika.global_position = world.points_of_interest[start].position + Vector3(0, 0.1, 1.5)
		camera_rig.snap_behind()

	bridge = ActionBridge.new()
	bridge.name = "ActionBridge"
	add_child(bridge)
	bridge.setup(self)

	if RenderProfile.options.has("facetest"):
		var ft := FaceTest.new()
		ft.main = self
		add_child(ft)
	elif RenderProfile.options.has("worldtour"):
		var wt := WorldTour.new()
		wt.main = self
		add_child(wt)
	elif RenderProfile.tour:
		var tour := TourRunner.new()
		tour.main = self
		add_child(tour)
	print("[main] ready in %s. WASD move | Shift run | Space cast | E interact | mouse orbit | N night | P profile | H hud | F12 screenshot" % streaming.current_id)


## Spawn any VRM humanoid. Future companion: spawn_character("mentor", ..., world.spawn_point("companion"), ...)
func spawn_character(id: String, display: String, avatar_path: String, at: Transform3D, parent: Node3D) -> WorldCharacter:
	var c := WorldCharacter.new()
	c.name = display
	c.character_id = id
	c.display_name = display
	c.avatar_path = avatar_path
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
	prompt = Label.new()
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 0.82
	prompt.position = Vector2(-300, 0)
	prompt.custom_minimum_size = Vector2(600, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	prompt.add_theme_constant_override("outline_size", 6)
	layer.add_child(prompt)


func nearest_interactable(max_d := 3.0) -> Interactable:
	if world == null:
		return null
	var mika: WorldCharacter = characters["mika"]
	var best: Interactable = null
	var bd := max_d
	for id in world.interactables:
		var it: Interactable = world.interactables[id]
		var d := Vector2(it.global_position.x - mika.global_position.x, it.global_position.z - mika.global_position.z).length() - it.radius
		if d < bd:
			bd = d
			best = it
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_night"):
		WorldState.night = not WorldState.night
		if world:
			world.set_night(WorldState.night)
	elif event.is_action_pressed("cycle_profile"):
		RenderProfile.cycle_profile()
		if world:
			RenderProfile.apply_to_environment(world.env)
	elif event.is_action_pressed("toggle_hud"):
		hud.visible = not hud.visible
	elif event.is_action_pressed("interact"):
		var it := nearest_interactable()
		if it:
			var r: Dictionary = await it.perform(characters["mika"])
			print("[main] interact ", it.id, " -> ", JSON.stringify(r))
	elif event.is_action_pressed("screenshot"):
		var path := "%s/manual_%s.png" % [RenderProfile.shots_dir, Time.get_datetime_string_from_system().replace(":", "-")]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RenderProfile.shots_dir))
		get_viewport().get_texture().get_image().save_png(path)
		print("[main] saved ", path)


func _process(delta: float) -> void:
	_fps_acc += delta
	_fps_frames += 1
	if world == null:
		return
	var mika: WorldCharacter = characters["mika"]
	var it := nearest_interactable(1.5)
	prompt.text = ("E — " + it.label) if it and not it.busy else ""
	var loc := world.location_at(mika.global_position)
	if streaming.state == "idle":
		WorldState.enter_location(loc)
	if _fps_acc >= 0.5 and hud.visible:
		var lname: String = WorldState.locations[loc].name if WorldState.locations.has(loc) else loc
		hud.text = "%s · %s  |  %s  |  %.0f fps (%.1f ms)  |  %s\nArea loaded: %s  (streaming: %s, instantiated areas: %d)  Action: %s\nDiscovered %d/%d locations · WASD move · Shift run · Space cast · E interact · N day/night · P profile · H hide" % [
			WorldState.regions[WorldState.areas[world.area_id].region].name, lname, RenderProfile.profile,
			_fps_frames / _fps_acc, 1000.0 * _fps_acc / _fps_frames, "NIGHT" if WorldState.night else "DAY",
			streaming.current_id, streaming.state, streaming._instantiated_count(), mika.current_action,
			WorldState.discovered_locations.size(), WorldState.locations.size()]
		_fps_acc = 0.0
		_fps_frames = 0
