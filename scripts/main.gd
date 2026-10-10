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
var subtitle: Label
var director: CameraDirector
var brain: SanctuaryBrain
var magic: MagicSystem
var _subtitle_until := 0.0
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
	mika.sword = SwordLayer.attach(mika)

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
	streaming.prewarm_once = func(): await ShaderPrewarm.run(camera_rig.camera, self)
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

	# Target-aware magic (spell catalogue, targeting, reactive world)
	magic = MagicSystem.new()
	magic.name = "MagicSystem"
	add_child(magic)
	magic.setup(self)
	player.magic = magic

	# Cinematographer + Mika's own decision layer for her home region (both local, no network)
	director = CameraDirector.new()
	director.name = "CameraDirector"
	add_child(director)
	director.setup(self)
	brain = SanctuaryBrain.new()
	brain.name = "SanctuaryBrain"
	add_child(brain)
	brain.setup(self)
	brain.thought.connect(func(text, sub): show_subtitle("Mika: \u201c%s\u201d" % text, 5.5))
	WorldState.interaction_finished.connect(func(_it, _c, r): if r.has("read"): show_subtitle("%s \u2014 %s" % [r.read.title, r.read.text], 8.0))
	bridge.attach_brain(brain, director)
	if RenderProfile.options.has("brain"):
		set_brain(true)

	if RenderProfile.options.has("facetest"):
		var ft := FaceTest.new()
		ft.main = self
		add_child(ft)
	elif RenderProfile.options.has("magictest"):
		travel._cooldown_until = 1e12
		var mt := MagicTest.new()
		mt.main = self
		add_child(mt)
	elif RenderProfile.options.has("posetest"):
		travel._cooldown_until = 1e12
		var pz := PoseTest.new()
		pz.main = self
		add_child(pz)
	elif RenderProfile.options.has("physicstest"):
		travel._cooldown_until = 1e12  # no gate auto-travel while Mika is teleported around
		var pt := PhysicsTest.new()
		pt.main = self
		add_child(pt)
	elif RenderProfile.options.has("sanctuarytour"):
		var st := SanctuaryTour.new()
		st.main = self
		add_child(st)
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
	subtitle = Label.new()
	subtitle.anchor_left = 0.5
	subtitle.anchor_right = 0.5
	subtitle.anchor_top = 0.88
	subtitle.position = Vector2(-520, 0)
	subtitle.custom_minimum_size = Vector2(1040, 30)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 19)
	subtitle.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	subtitle.add_theme_constant_override("outline_size", 6)
	layer.add_child(subtitle)


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
	elif event.is_action_pressed("camera_director"):
		director.enabled = not director.enabled
		print("[main] camera director ", "on" if director.enabled else "off")
	elif event.is_action_pressed("brain_toggle"):
		set_brain(not brain.enabled)
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


## Let Mika decide for herself (player controls pause; the director frames her) or hand control back.
func set_brain(on: bool) -> void:
	player.enabled = not on
	if on:
		characters["mika"].set_move_input(Vector3.ZERO, false)
	director.enabled = on
	brain.set_enabled(on)
	show_subtitle("Mika is choosing what to do (B to take control)" if on else "You are in control (B: let Mika decide)", 3.0)


func show_subtitle(text: String, seconds: float) -> void:
	subtitle.text = text
	subtitle.modulate.a = 1.0
	_subtitle_until = Time.get_ticks_msec() / 1000.0 + seconds


func _process(delta: float) -> void:
	_fps_acc += delta
	if subtitle and _subtitle_until > 0.0:
		var left := _subtitle_until - Time.get_ticks_msec() / 1000.0
		subtitle.modulate.a = clampf(left / 0.8, 0.0, 1.0)
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
		var sub := ""
		var sid := SanctuaryBrain.sub_area(world, mika.global_position)
		if sid != "":
			sub = " · " + String(WorldState.sanctuary.sub_areas[sid].name)
		var ms := WorldState.mission_state()
		var spell_txt := ""
		if magic and player:
			var sp := MagicSystem.spell(player.spell_id)
			spell_txt = " · Spell (Q): %s [%s]" % [sp.get("name", "?"), MagicSystem.tier_name(MagicSystem.mastery(player.spell_id))]
		hud.text = ("Rank: %s · Trials %d/%d%s · Brain %s · Director %s%s\n" % [ms.rank, ms.trials_done, ms.trials_total, (" · next: " + ms.next_rank) if ms.next_rank != "" else "",
			"ON" if brain and brain.enabled else "off", director.mode if director and director.enabled else "off", spell_txt]) + "%s · %s%s  |  %s  |  %.0f fps (%.1f ms)  |  %s\nArea loaded: %s  (streaming: %s, instantiated areas: %d)  Action: %s\nDiscovered %d/%d locations · WASD move · Shift run · Space cast · E interact · R sword · F slash · G charge · T element · B Mika decides · V director · N day/night · P profile · H hide" % [
			WorldState.regions[WorldState.areas[world.area_id].region].name, lname, sub, RenderProfile.profile,
			_fps_frames / _fps_acc, 1000.0 * _fps_acc / _fps_frames, "NIGHT" if WorldState.night else "DAY",
			streaming.current_id, streaming.state, streaming._instantiated_count(), mika.current_action,
			WorldState.discovered_locations.size(), WorldState.locations.size()]
		_fps_acc = 0.0
		_fps_frames = 0
