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
var voice: VoiceService
var book_reader: BookReader
var book_overlay: BookOverlay
var audio: AudioDirector
var llm: LLMClient
var dialogue: DialogueService
var npcs: NPCManager
var phoenix_mgr: PhoenixManager
var story: StoryManager
var curiosity: CuriosityModule
var notice: Label
var last_thought := ""
var viewer_mode := false        # clean presentation for streaming (F1 toggles; --viewer starts in it)
var rank_tag: Label
var comment_label: Label
var chat: ViewerChat
# Milestone H: several autonomous mages, progression, creatures, transformations
var mages: Array = ["mika"]                 # spawned mage ids (each has a mind, planner, voice)
var mage_brains := {}                        # mage id -> SanctuaryBrain instance
var progression: Progression
var spawner: Spawner
var mage_talk: MageTalk
var transformer: TransformationDirector
var overlay_ui: MageOverlay
var attention: AttentionDirector
var affect: Affect
var impacts: ImpactDirector       # area impacts with consequences + the aftermath behaviours (V3 continuation)
var perf_overlay: PerfOverlay      # F6: the developer's performance / adaptive-quality panel
var gfx: AdaptiveQuality          # Adaptive 60: quality follows the measured frame budget (docs/ADAPTIVE_GRAPHICS.md)
var auditor: InvariantAuditor      # automatic checks for visible defects (at the object, tool in hand, on the ground)
var town: TownLife                # the people who live in the Village and the Academy (data/residents.json)
var weather: WeatherSystem        # one sky for the world: clear, overcast, rain, storm (persists)
var teleport_guard: TeleportGuard  # the no-teleport rule, watched every physics frame
var journeys: JourneyDirector      # multi-day journeys across the overland world (persistent)
var ambush: AmbushDirector         # road ambushes by human rivals (data/ambush.json)
var companionship: Companionship
var duel: TrainingDuel
var performance: PerformanceController
var live_link: LiveLink                    # --live-link: Mika-Live's Stage (null otherwise)
var quiet_test := false                      # older single-mage tests: no Luna / creatures unless asked
var _spot_t := 0.0
var _spot_since := 0.0
var _comment_until := 0.0
var _last_rank := ""
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
	# places to find (data/discoveries.json): set into each area as it opens, behind the travel card
	streaming.before_reveal.append(func(): await Discoveries.populate(world))
	if not RenderProfile.options.has("no-grade"):
		var grade := StreamGrade.new()
		grade.name = "StreamGrade"
		add_child(grade)
		grade.setup(self)

	stream_profile = String(RenderProfile.options.get("stream-profile", "mika"))
	var chars := Node3D.new()
	chars.name = "Characters"
	add_child(chars)
	# each mage appears in her saved appearance (a form reached at a tenth level is permanent)
	var mika := spawn_character("mika", "Mika", TransformationDirector.avatar_for("mika"), Transform3D.IDENTITY, chars)
	mika.add_to_group("player_character")
	mika.set_physics_process(false)
	mika.sword = SwordLayer.attach(mika)
	Progression.load_data()
	quiet_test = WorldState._TEST_FLAGS.any(func(f): return RenderProfile.options.has(f) and f != "brainrun")
	if not RenderProfile.options.has("no-luna") and (not quiet_test or RenderProfile.options.has("luna")):
		WorldState.register_mind("luna")
		var luna := spawn_character("luna", "Luna", TransformationDirector.avatar_for("luna"), Transform3D.IDENTITY, chars)
		luna.set_physics_process(false)
		luna.visible = false
		mages.append("luna")

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
	_on_area_for_mages(streaming.current_id)
	GatherNode.populate(world, streaming.current_id)
	if not RenderProfile.options.has("no-polish"):
		env_polish_report = EnvPolish.apply(world, streaming.current_id)
	streaming.transition_started.connect(func(_f, _t): _park_mages())
	streaming.area_activated.connect(func(a, _r): _on_area_for_mages(a); GatherNode.populate(world, a))
	# Milestone J: targeted visual polish of the stream's home area (leaf material, meadow cover)
	streaming.area_activated.connect(func(a, _r): if not RenderProfile.options.has("no-polish"): env_polish_report = EnvPolish.apply(world, a))

	bridge = ActionBridge.new()
	bridge.name = "ActionBridge"
	add_child(bridge)
	bridge.setup(self)

	# Event-driven sound (spells, reactions, books, footsteps, ambience)
	audio = AudioDirector.new()
	audio.name = "AudioDirector"
	add_child(audio)
	audio.setup(self)
	audio._build_beds()
	WorldState.interaction_started.connect(func(it, c): audio.on_interaction(it, "start", c))

	# Speech (DEV Kokoro), reading (books / scrolls / inscriptions)
	voice = VoiceService.new()
	BodyReaction.voice = voice
	voice.name = "VoiceService"
	add_child(voice)
	voice.setup(self)
	voice.register_speaker("mika", mika)
	if characters.has("luna"):
		voice.register_speaker("luna", characters["luna"])
	book_overlay = BookOverlay.new()
	add_child(book_overlay)
	book_reader = BookReader.new()
	book_reader.name = "BookReader"
	add_child(book_reader)
	book_reader.setup(self)

	# Optional language model (mock unless explicitly configured), shared dialogue, visiting travellers
	llm = LLMClient.new()
	llm.name = "LLMClient"
	add_child(llm)
	llm.setup()
	dialogue = DialogueService.new()
	dialogue.name = "DialogueService"
	add_child(dialogue)
	dialogue.setup(self)
	npcs = NPCManager.new()
	npcs.name = "NPCManager"
	add_child(npcs)
	npcs.setup(self)
	phoenix_mgr = PhoenixManager.new()
	phoenix_mgr.name = "PhoenixManager"
	add_child(phoenix_mgr)
	phoenix_mgr.setup(self)

	# Story (Echoes of the Heartstone) + optional curiosity (consulted between activities only)
	story = StoryManager.new()
	story.name = "StoryManager"
	add_child(story)
	story.setup(self)
	progression = Progression.new()
	progression.name = "Progression"
	add_child(progression)
	progression.setup(self)
	# levelling has its own single, low cue (only for the mage the stream is following)
	progression.leveled.connect(func(who, _lvl): if audio and who == focus: audio.play_progress("level_up", -4.0, "level_up"))

	# Target-aware magic (spell catalogue, targeting, reactive world)
	magic = MagicSystem.new()
	magic.name = "MagicSystem"
	add_child(magic)
	magic.setup(self)
	player.magic = magic
	magic.fusion = SpellFusion.new()
	magic.fusion.name = "SpellFusion"
	add_child(magic.fusion)
	magic.fusion.setup(self)
	spawner = Spawner.new()
	spawner.name = "Spawner"
	add_child(spawner)
	spawner.setup(self)
	if quiet_test and not RenderProfile.options.has("monsters"):
		spawner.enabled = false
	spawner.mage_hit.connect(func(mage, m, _a): if mage_brains.has(mage.character_id): mage_brains[mage.character_id].on_threat(m))

	# Cinematographer + Mika's own decision layer for her home region (both local, no network)
	director = CameraDirector.new()
	director.name = "CameraDirector"
	add_child(director)
	director.setup(self)
	brain = SanctuaryBrain.new()
	brain.name = "SanctuaryBrain"
	add_child(brain)
	brain.setup(self)
	brain.thought.connect(func(text, _sub): last_thought = text)   # private reasoning: developer HUD only, never spoken
	mage_brains["mika"] = brain
	for who in mages:
		if who == "mika":
			continue
		var b := SanctuaryBrain.new()
		b.name = "Brain_" + who
		add_child(b)
		b.setup(self, who)
		mage_brains[who] = b
	mage_talk = MageTalk.new()
	mage_talk.name = "MageTalk"
	add_child(mage_talk)
	mage_talk.setup(self)
	transformer = TransformationDirector.new()
	transformer.name = "Transformations"
	add_child(transformer)
	transformer.setup(self)
	for who in mages:
		var got := progression.backfill(who)
		if got > 0.0:
			print("[progression] %s: %.0f XP from what she already knew -> Level %d" % [who, got, WorldState.mind(who).level()])
	attention = AttentionDirector.new()
	attention.name = "Attention"
	add_child(attention)
	attention.setup(self)
	affect = Affect.new()
	affect.name = "Affect"
	add_child(affect)
	affect.setup(self)
	impacts = ImpactDirector.new()
	impacts.name = "Impacts"
	add_child(impacts)
	impacts.setup(self)
	weather = WeatherSystem.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(self)
	town = TownLife.new()
	town.name = "TownLife"
	add_child(town)
	town.setup(self)
	auditor = InvariantAuditor.new()
	auditor.name = "Auditor"
	add_child(auditor)
	auditor.setup(self)
	gfx = AdaptiveQuality.new()
	gfx.name = "AdaptiveQuality"
	add_child(gfx)
	gfx.setup(self)
	perf_overlay = PerfOverlay.new()
	perf_overlay.name = "PerfOverlay"
	add_child(perf_overlay)
	perf_overlay.setup(self)
	streaming.area_activated.connect(func(a, _r): town.area_activated(a))
	town.area_activated(streaming.current_id)
	teleport_guard = TeleportGuard.new()
	teleport_guard.name = "TeleportGuard"
	add_child(teleport_guard)
	teleport_guard.setup(self)
	journeys = JourneyDirector.new()
	journeys.name = "Journeys"
	add_child(journeys)
	journeys.setup(self)
	ambush = AmbushDirector.new()
	ambush.name = "Ambush"
	add_child(ambush)
	ambush.setup(self)
	companionship = Companionship.new()
	companionship.name = "Companionship"
	add_child(companionship)
	companionship.setup(self)
	duel = TrainingDuel.new()
	duel.name = "TrainingDuel"
	add_child(duel)
	duel.setup(self)
	performance = PerformanceController.new()
	performance.name = "Performance"
	add_child(performance)
	performance.setup(self)
	overlay_ui = MageOverlay.new()
	overlay_ui.name = "MageOverlay"
	add_child(overlay_ui)
	overlay_ui.setup(self)
	WorldState.interaction_finished.connect(func(_it, _c, r): if r.has("read") and not r.has("reading"): show_subtitle("%s: %s" % [r.read.title, r.read.text], 8.0))
	chat = ViewerChat.new()
	chat.name = "ViewerChat"
	add_child(chat)
	chat.setup(self)
	# region-specific portal effects: departing as the travel mask closes, arriving as the next area appears
	streaming.transition_started.connect(func(_from, to):
		if characters.has("mika"):
			PortalFX.play(self, characters[focus].global_position, WorldState.areas.get(to, {}).get("region", ""), false))
	streaming.area_activated.connect(func(a, _r):
		await get_tree().create_timer(0.15).timeout
		if world and characters.has("mika"):
			PortalFX.play(world, characters[focus].global_position, WorldState.areas.get(a, {}).get("region", ""), true))
	if RenderProfile.options.has("viewer"):
		set_viewer_mode(true)
	curiosity = CuriosityModule.new()
	curiosity.name = "CuriosityModule"
	add_child(curiosity)
	curiosity.setup(self)
	bridge.attach_brain(brain, director)
	if RenderProfile.options.has("brain"):
		set_brain(true)
	# the live show (Mika-Live drives chat, speech and the broadcast; this world is its Stage)
	if RenderProfile.options.has("live-link"):
		live_link = LiveLink.new()
		live_link.name = "LiveLink"
		add_child(live_link)
		live_link.setup(self)
	# the other mages live their own lives from the start (B only hands Mika to the player and back)
	for who in mage_brains:
		if who != "mika" and not RenderProfile.options.has("no-luna-brain"):
			mage_brains[who].set_enabled(true)

	if RenderProfile.options.has("facetest"):
		var ft := FaceTest.new()
		ft.main = self
		add_child(ft)
	elif RenderProfile.options.has("mktest"):
		travel._cooldown_until = 1e12
		var mk := MilestoneKTest.new()
		mk.main = self
		add_child(mk)
	elif RenderProfile.options.has("mjtest"):
		travel._cooldown_until = 1e12
		var mj := MilestoneJTest.new()
		mj.main = self
		add_child(mj)
	elif RenderProfile.options.has("mitest"):
		travel._cooldown_until = 1e12
		var mi := MilestoneITest.new()
		mi.main = self
		add_child(mi)
	elif RenderProfile.options.has("mhtest"):
		travel._cooldown_until = 1e12
		var mh := MilestoneHTest.new()
		mh.main = self
		add_child(mh)
	elif RenderProfile.options.has("persisttest"):
		travel._cooldown_until = 1e12
		var ps := PersistTest.new()
		ps.main = self
		add_child(ps)
	elif RenderProfile.options.has("chattest"):
		travel._cooldown_until = 1e12
		var ct := ChatTest.new()
		ct.main = self
		add_child(ct)
	elif RenderProfile.options.has("brainrun"):
		travel._cooldown_until = 1e12
		var br := BrainRun.new()
		br.main = self
		add_child(br)
	elif RenderProfile.options.has("lifetest"):
		travel._cooldown_until = 1e12
		var lt := LifeTest.new()
		lt.main = self
		add_child(lt)
	elif RenderProfile.options.has("audiotest"):
		travel._cooldown_until = 1e12
		var aut := AudioTest.new()
		aut.main = self
		add_child(aut)
	elif RenderProfile.options.has("alchemytest"):
		travel._cooldown_until = 1e12
		var at := AlchemyTest.new()
		at.main = self
		add_child(at)
	elif RenderProfile.options.has("readtest"):
		travel._cooldown_until = 1e12
		var rt := ReadTest.new()
		rt.main = self
		add_child(rt)
	elif RenderProfile.options.has("magictest"):
		travel._cooldown_until = 1e12
		var mt := MagicTest.new()
		mt.main = self
		add_child(mt)
	elif RenderProfile.options.has("outfittest"):
		travel._cooldown_until = 1e12
		var ot = load("res://scripts/tests/outfit_test.gd").new()
		ot.main = self
		add_child(ot)
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
	c.add_to_group("mage")
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
	notice = Label.new()
	notice.anchor_left = 0.5
	notice.anchor_right = 0.5
	notice.anchor_top = 0.06
	notice.position = Vector2(-450, 0)
	notice.custom_minimum_size = Vector2(900, 30)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_font_size_override("font_size", 22)
	notice.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
	notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	notice.add_theme_constant_override("outline_size", 6)
	notice.modulate.a = 0.0
	layer.add_child(notice)
	rank_tag = Label.new()
	rank_tag.position = Vector2(22, 18)
	rank_tag.add_theme_font_size_override("font_size", 17)
	rank_tag.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
	rank_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	rank_tag.add_theme_constant_override("outline_size", 5)
	rank_tag.modulate.a = 0.0
	layer.add_child(rank_tag)
	comment_label = Label.new()
	comment_label.anchor_left = 0.5
	comment_label.anchor_right = 0.5
	comment_label.anchor_top = 0.80
	comment_label.position = Vector2(-520, 0)
	comment_label.custom_minimum_size = Vector2(1040, 26)
	comment_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	comment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	comment_label.add_theme_font_size_override("font_size", 16)
	comment_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	comment_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	comment_label.add_theme_constant_override("outline_size", 5)
	comment_label.modulate.a = 0.0
	layer.add_child(comment_label)


## ---------------------------------------------------------------- simulation tiers (Milestone I)
## Only ONE area is ever loaded: the area of the FOCUS mage (the one the camera follows).
##   foreground - the focus mage: full simulation; the only mage who may cause an area change
##   nearby     - another mage whose saved location is the loaded area: full physics, animation and planning
##   background - a mage whose area is not loaded: hidden and frozen; her planner runs an honest abstract
##                simulation (see SanctuaryBrain._background_step) and defers what needs the real world
## Every mage's location is kept in her mind (saved), so she is rebuilt exactly where she was.
var focus := "mika"
var focus_locked := false          # an explicit request (F3, bridge, tests) holds the focus until released
## Stream profile (Milestone J): which mage the automatic camera serves.
##   mika   - the default livestream: Mika is the protagonist. The camera stays with her; Luna lives her own
##            life but never takes the camera on her own (no Luna-only cutaways). Shared scenes (the two of
##            them talking or fighting together) are framed by the director with both in shot.
##   luna   - (future) the same policy centred on Luna
##   shared - (future) the Milestone I spotlight: whoever is doing the most watchable thing
## Set with --stream-profile=<id>; a developer's explicit focus (F3 / bridge / tests) always overrides.
var stream_profile := "mika"
var env_polish_report := {}
var _loc_t := 0.0


func sim_mode(who: String) -> String:
	if who == focus:
		return "foreground"
	var c: WorldCharacter = characters.get(who)
	return "nearby" if c and c.visible else "background"


func _home_area(who: String) -> String:
	return String(Progression.mages.get(who, {}).get("home_area", "sanctuary"))


## Before an area unloads: remember where everyone in it stands; hide every mage but the focus (who travels).
func _park_mages() -> void:
	for who in mages:
		var c: WorldCharacter = characters[who]
		if c.visible and world:
			WorldState.mind(who).set_location(streaming.current_id, c.global_position)
		if who == focus:
			continue
		c.set_physics_process(false)
		c.visible = false


## After an area is built: the focus mage is placed by the streaming manager; every other mage whose saved
## location is this area reappears where she was (or at her spawn), the rest stay in the background.
func _on_area_for_mages(area_id: String) -> void:
	for who in mages:
		var c: WorldCharacter = characters[who]
		var m := WorldState.mind(who)
		if who == focus:
			c.visible = true
			m.set_location(area_id, c.global_position)
			continue
		var her_area := String(m.location.get("area", _home_area(who)))
		if her_area != area_id or world == null:
			c.visible = false
			c.set_physics_process(false)
			continue
		var at := m.location_pos()
		if at == Vector3.INF:
			var sp: Array = Progression.mages.get(who, {}).get("spawn", [20, 0, 8])
			at = Vector3(sp[0], 0, sp[2])
			at.y = world.ground_at(at.x, at.z) if world.has_method("ground_at") else 0.0
		var snapped := NavigationServer3D.map_get_closest_point(world.get_world_3d().navigation_map, at)
		# a map that has not synchronised yet answers (0,0,0): never teleport her there
		at = snapped if snapped != Vector3.ZERO and snapped.distance_to(at) < 3.0 else at
		if teleport_guard:
			teleport_guard.allow(c)       # restoring her saved place in the area being loaded
		c.global_position = at + Vector3(0, 0.1, 0)
		c.world = world
		c.velocity = Vector3.ZERO
		c.visible = true
		c.set_physics_process(true)
		m.set_location(area_id, c.global_position)


## Nearest walkable point to `at`, waiting for the navigation map to synchronise after a load (it answers
## (0,0,0) until then). Falls back to `at` itself rather than ever placing a mage somewhere arbitrary.
func snap_to_nav(at: Vector3) -> Vector3:
	# the navmesh can still be (re)baking right after an area load: wait for it, and never answer a point under
	# the terrain (a body placed below the ground falls through the world)
	var gy := -INF
	if world and world.has_method("ground_at"):
		gy = float(world.ground_at(at.x, at.z))
	for i in 45:
		var p := NavigationServer3D.map_get_closest_point(world.get_world_3d().navigation_map, Vector3(at.x, maxf(at.y, gy), at.z))
		if p != Vector3.ZERO and Vector2(p.x - at.x, p.z - at.z).length() < 3.0 and (gy == -INF or p.y > gy - 0.6):
			return p
		await get_tree().physics_frame
	return Vector3(at.x, maxf(at.y, gy), at.z) if gy != -INF else at


## Follow another mage. Same area: the camera simply changes subject. Another area: everyone in the current
## area is first allowed to finish what she is doing (nothing unloads mid-action), then the masked travel
## card loads her area and she is rebuilt exactly where she was; the others continue in the background.
func focus_mage(who: String, lock := false) -> Dictionary:
	if lock:
		focus_locked = true
	if who == focus or not characters.has(who):
		return {"ok": who == focus, "focus": focus}
	var c: WorldCharacter = characters[who]
	var m := WorldState.mind(who)
	var her_area := streaming.current_id if c.visible else String(m.location.get("area", _home_area(who)))
	if her_area == streaming.current_id:
		focus = who
		if director:
			director.set_subject(c)
		camera_rig.target = c
		return {"ok": true, "focus": who, "area_change": false}
	if streaming.state != "idle" or (transformer and transformer.playing != ""):
		return {"ok": false, "error": "busy (%s)" % streaming.state}
	var held := []
	for w in mages:
		if characters[w].visible and mage_brains.has(w) and mage_brains[w].enabled:
			mage_brains[w].hold = true
			mage_brains[w].interrupt("focus")
			held.append(w)
	var t0 := Time.get_ticks_msec()
	while held.any(func(w): return not mage_brains[w].current.is_empty() and mage_brains[w].current.get("kind", "") != "away") and Time.get_ticks_msec() - t0 < 25000:
		await get_tree().process_frame
	if held.any(func(w): return not mage_brains[w].current.is_empty()):
		for w in held:
			mage_brains[w].hold = false
		return {"ok": false, "error": "the mages here are in the middle of something; try again shortly"}
	var old_focus := focus
	var at := m.location_pos()            # read BEFORE loading: arrival records the gate position as her location
	focus = who
	var r: Dictionary = await streaming.travel(her_area, c)
	if not r.get("ok", false):
		focus = old_focus
		for w in held:
			mage_brains[w].hold = false
		return {"ok": false, "error": r.get("reason", "travel failed")}
	if at != Vector3.INF:
		var back_at := await snap_to_nav(at)
		if teleport_guard:
			teleport_guard.allow(c)       # the camera's area load restores her where she really was
		c.global_position = back_at + Vector3(0, 0.1, 0)
	c.visible = true
	m.set_location(her_area, c.global_position)
	camera_rig.target = c
	camera_rig.snap_behind()
	if director:
		director.set_subject(c)
	for w in held:
		mage_brains[w].hold = false
	return {"ok": true, "focus": who, "area_change": true, "area": her_area}


## Spotlight. Profile "mika" (the default stream): the camera serves Mika - it returns to her after any
## temporary change and never cuts away to another mage on its own. Profile "shared": the Milestone I
## spotlight (another mage may take the camera for something clearly more watchable, changes at most
## every 20 s). A developer's explicit focus (focus_locked) overrides both.
func _spotlight(delta: float) -> void:
	_spot_since += delta
	_spot_t -= delta
	var home_mage := stream_profile if stream_profile in mages else "mika"
	if performance and performance.busy():
		var pw := String(performance.active.get("who", ""))
		# the performer owns the camera only if she is the stream's mage (or in the shared profile)
		if pw != "" and pw != focus and characters[pw].visible and (stream_profile == "shared" or pw == home_mage) and not focus_locked:
			focus_mage(pw)
		if stream_profile == "shared" or pw == home_mage:
			return
	if focus_locked:
		return
	if stream_profile != "shared":
		_spot_t = maxf(_spot_t, 0.0)
		if focus != home_mage and characters.has(home_mage) and _spot_since > 2.0 and (transformer == null or transformer.playing == ""):
			if characters[home_mage].visible or WorldState.mind(home_mage).location.get("area", "") != "":
				focus_mage(home_mage)      # back to the protagonist after any temporary change
				_spot_since = 0.0
		return
	if not director or not director.enabled:
		if focus != "mika" and characters["mika"].visible:
			focus_mage("mika")             # the player controls Mika: the camera is hers
		return
	if _spot_t > 0.0:
		return
	_spot_t = 2.0
	if transformer and transformer.playing != "":
		return
	var interest := {"hunt": 5.0, "collect": 4.5, "meet": 4.0, "perform": 6.0, "magic": 3.0, "investigate": 3.0, "attune": 2.5, "alchemy": 2.5,
		"research": 2.0, "converse": 3.0, "recover": 2.0, "explore": 1.5, "roam": 1.5, "gather": 1.5, "journal": 1.0, "rest": 0.8}
	var best := ""
	var best_v := -1.0
	for who in mage_brains:
		var c: WorldCharacter = characters[who]
		if not c.visible or not mage_brains[who].enabled:
			continue
		var v := float(interest.get(String(mage_brains[who].current.get("kind", "")), 0.5))
		if who == "mika":
			v += 2.5          # Mika-first: another mage takes the camera only for something clearly more watchable
		elif c == director.mika:
			v += 0.8          # small hysteresis while away from Mika
		if v > best_v:
			best_v = v
			best = who
	if best != "" and best != focus and (_spot_since > 20.0 or best == "mika" and _spot_since > 8.0):
		focus_mage(best)                    # same area (both visible): an instant change of subject
		_spot_since = 0.0


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
	if brain == null:
		return   # still starting up (the first area is loading): director/brain/HUD keys have nothing to act on yet
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
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F1:
		set_viewer_mode(not viewer_mode)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F2:
		overlay_ui.toggle_dev()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F6:
		perf_overlay.toggle()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F9:
		# DEV only: inject a fake viewer comment (cycles through a few addressed to Mika / Luna / anyone)
		var samples := [["Mika, what are you doing?", "dev_alex", "Alex"], ["Luna, what level are you?", "dev_rin", "Rin"], ["hi everyone!", "dev_sam", "Sam"],
			["Luna can you show me your lance?", "dev_kai", "Kai"], ["hi Mika!", "dev_alex", "Alex"]]
		var smp: Array = samples[int(Time.get_ticks_msec() / 1000) % samples.size()]
		chat.receive({"message_id": "f9_%d" % Time.get_ticks_usec(), "text": smp[0], "author_id": smp[1], "author": smp[2]})
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F8:
		# DEV preview of a music performance by the followed mage (no memory, no XP); Shift = special
		performance.perform(focus, "special" if (event as InputEventKey).shift_pressed else "casual", {"preview": true})
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F3:
		# follow the next mage (across areas if needed); F3 again cycles back, ending on Mika releases the lock
		if (event as InputEventKey).shift_pressed:
			focus_locked = false               # Shift+F3: let the spotlight choose again
		else:
			var i := mages.find(focus)
			focus_mage(mages[(i + 1) % mages.size()], true)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F7:
		var who: String = director.mika.character_id if director else "mika"
		transformer.play(who, "short" if (event as InputEventKey).shift_pressed else "full", true)   # preview: no progress, reverts
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


## Viewer mode: no telemetry, controls or debug lines; only rank (when relevant), spoken subtitles,
## story notices, the viewer comment being answered, the reading card, and the interaction prompt only
## while a human is actually controlling Mika.
func set_viewer_mode(on: bool) -> void:
	viewer_mode = on
	hud.visible = not on
	print("[main] viewer mode ", "on" if on else "off")


func show_comment(author: String, text: String) -> void:
	comment_label.text = VoiceService.clean("%s: %s" % [author, text])
	comment_label.modulate.a = 1.0
	_comment_until = Time.get_ticks_msec() / 1000.0 + 9.0


## A significant story notification (stays readable in viewer mode).
func show_notice(text: String) -> void:
	notice.text = VoiceService.clean(text)
	notice.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(notice, "modulate:a", 0.0, 1.5)


func show_subtitle(text: String, seconds: float) -> void:
	subtitle.text = VoiceService.clean(text)
	subtitle.modulate.a = 1.0
	_subtitle_until = Time.get_ticks_msec() / 1000.0 + seconds


var _lb_t := 0.0

func _process(delta: float) -> void:
	_lb_t -= delta
	if _lb_t <= 0.0 and world:
		_lb_t = 1.0
		var sun: DirectionalLight3D = world.get("sun")
		var we: WorldEnvironment = world.get("world_env")
		if we and we.environment:
			var se := sun.light_energy if sun and sun.visible else 0.0
			for who in characters:
				if characters[who].visible:
					characters[who].apply_light_balance(se, we.environment.ambient_light_energy)
	_spotlight(delta)
	_fps_acc += delta
	if subtitle and _subtitle_until > 0.0:
		var left := _subtitle_until - Time.get_ticks_msec() / 1000.0
		subtitle.modulate.a = clampf(left / 0.8, 0.0, 1.0)
	_fps_frames += 1
	if world == null:
		return
	var mika: WorldCharacter = characters["mika"]
	var it := nearest_interactable(1.5)
	var human: bool = player.enabled and not (brain and brain.enabled)
	prompt.text = ("E: " + it.label) if it and not it.busy and human and not viewer_mode else ""   # a player hint, never on stream
	if _comment_until > 0.0:
		comment_label.modulate.a = clampf((_comment_until - Time.get_ticks_msec() / 1000.0) / 0.8, 0.0, 1.0)
	# rank tag: shown briefly whenever the rank changes; always visible in developer mode
	var rank := WorldState.mage_rank()
	if rank != _last_rank:
		_last_rank = rank
		rank_tag.text = rank
		rank_tag.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(10.0)
		tw.tween_property(rank_tag, "modulate:a", 0.0, 2.0)
	var loc := world.location_at(mika.global_position)
	if streaming.state == "idle" and mika.visible:
		WorldState.enter_location(loc)        # Mika's map of the world (only while she is actually here)
	_loc_t -= delta
	if _loc_t <= 0.0 and streaming.state == "idle":
		_loc_t = 1.0
		for who in mages:
			if characters[who].visible:
				WorldState.mind(who).set_location(streaming.current_id, characters[who].global_position)
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
		var thought_txt := ("\nThinking: " + last_thought) if last_thought != "" and brain and brain.enabled else ""
		hud.text = ("Rank: %s · Trials %d/%d%s · Brain %s · Director %s%s\n" % [ms.rank, ms.trials_done, ms.trials_total, (" · next: " + ms.next_rank) if ms.next_rank != "" else "",
			"ON" if brain and brain.enabled else "off", director.mode if director and director.enabled else "off", spell_txt]) + "%s · %s%s  |  %s  |  %.0f fps (%.1f ms)  |  %s\nArea loaded: %s  (streaming: %s, instantiated areas: %d)  Action: %s\nDiscovered %d/%d locations · WASD move · Shift run · Space cast · E interact · R sword · F slash · G charge · T element · B Mika decides · V director · N day/night · P profile · H hide" % [
			WorldState.regions[WorldState.areas[world.area_id].region].name, lname, sub, RenderProfile.profile,
			_fps_frames / _fps_acc, 1000.0 * _fps_acc / _fps_frames, "NIGHT" if WorldState.night else "DAY",
			streaming.current_id, streaming.state, streaming._instantiated_count(), mika.current_action,
			WorldState.discovered_locations.size(), WorldState.locations.size()] + thought_txt
		_fps_acc = 0.0
		_fps_frames = 0
