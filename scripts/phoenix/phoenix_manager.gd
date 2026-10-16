class_name PhoenixManager
extends Node
## When and why Oriel appears (V3 Part X). She lives at the Celestial Summit; she comes down to the Whispering
## Woods' viewpoint the first time Mika is near it in a session (and again after a cooldown that spans
## restarts, like the travellers'), lights the old fire bowls, and - when Mika comes close - takes her human
## form to talk. The first meeting ever is the long cinematic transformation; later ones the short one. After a
## while she says goodbye, becomes the Phoenix again and flies back toward the summit. She is registered with
## the dialogue system as the resident "phoenix", so Mika's planner can choose to talk with her like with any
## visitor, and her memory of those conversations persists in the save (WorldState.npc_state.phoenix).

var main: Node
var present: Phoenix = null
var events: Array = []
var _session_t := 0.0
var _stay_until := 1e12
var _greeted := false
var _driving := false
var enabled := true
var auto_greet := true              # the manager starts the transformation when Mika comes near (tests drive it themselves)
var auto_leave := true


func setup(m: Node) -> void:
	main = m
	Phoenix.load_data()
	main.dialogue.travellers["phoenix"] = Phoenix.data
	if RenderProfile.options.has("no-phoenix"):
		enabled = false


func _log(kind: String, detail := {}) -> void:
	var e := {"t": snappedf(_session_t, 0.1), "event": kind}
	e.merge(detail)
	events.append(e)
	if events.size() > 60:
		events.pop_front()


func _woods_active() -> bool:
	return main.world != null and main.streaming.state == "idle" and main.streaming.current_id == String(Phoenix.data.home.area)


func _viewpoint() -> Vector3:
	var p: Array = Phoenix.data.home.perch
	return Vector3(p[0], main.world.ground_at(p[0], p[1]) if main.world else 0.0, p[1])


func _due() -> bool:
	var st: Dictionary = main.dialogue.state_of("phoenix")
	if _session_t < float(Phoenix.data.trigger.min_session_s):
		return false
	if Time.get_unix_time_from_system() < float(st.get("next_visit_unix", 0)):
		return false
	var mika: WorldCharacter = main.characters.get("mika")
	return mika != null and mika.visible and Vector2(mika.global_position.x - _viewpoint().x, mika.global_position.z - _viewpoint().z).length() < float(Phoenix.data.trigger.radius_m)


func _process(delta: float) -> void:
	_session_t += delta
	if not enabled:
		return
	if present and not is_instance_valid(present):
		present = null
		main.npcs.present.erase("phoenix")
		_log("gone")
	if not _woods_active():
		if present and is_instance_valid(present):
			_log("area left while she was here")
			present.queue_free()
			present = null
			main.npcs.present.erase("phoenix")
		return
	if present == null:
		# never into the middle of someone else's fight: she comes once it is over
		var fighting: bool = main.get("gfx") != null and main.gfx.in_fight()
		if Engine.get_process_frames() % 30 == 0 and not fighting and (_due() or RenderProfile.options.has("phoenix")):
			summon()
		return
	if _driving:
		return
	var mika: WorldCharacter = main.characters.get("mika")
	if present.phase == "perched" and auto_greet and not present.busy and mika and mika.visible and not mika.casting \
			and mika.global_position.distance_to(present.global_position) < float(Phoenix.data.approach_to_greet_m):
		_drive_greeting()
	elif present.phase == "human" and auto_leave and present.state == "idle" and _session_t >= _stay_until and not present.busy:
		_driving = true
		present.leave()
		_log("leaving")
		_driving = false


## Bring her in now (the trigger, the --phoenix option, or a test).
func summon() -> Phoenix:
	if present or not _woods_active():
		return present
	var ph := Phoenix.new()
	main.world.add_child(ph)
	ph.setup(main, main.world)
	present = ph
	main.npcs.present["phoenix"] = ph
	var st: Dictionary = main.dialogue.state_of("phoenix")
	st.visits += 1
	var stay: Array = Phoenix.data.stay_s
	_stay_until = _session_t + randf_range(stay[0], stay[1]) + 60.0
	var cd := float(Phoenix.data.trigger.cooldown_s)
	st["next_visit_unix"] = Time.get_unix_time_from_system() + cd
	ph.arrive()
	_log("summoned", {"visit": st.visits})
	call_luna()
	_prefetch_lines()
	if main.curiosity and main.curiosity.has_method("on_visitor"):
		main.curiosity.on_visitor("phoenix")
	return ph


## Her arrival beat once she is perched: the cold bowls are lit, then, when Mika comes close, she changes.
func _drive_greeting() -> void:
	_driving = true
	var ph := present
	if not _greeted and ph.braziers.size() > 0 and not ph.braziers.all(func(b): return b.lit):
		await ph.say(String(Phoenix.data.lines.lighting), "", 0)
		await ph.light_bowls()
	_greeted = true
	if ph and is_instance_valid(ph) and ph.phase == "perched":
		await ph.say(String(Phoenix.data.lines.before_transform), "playful")
		var first := not bool(main.dialogue.state_of("phoenix").met)
		await ph.transform_to_human("cinematic" if first else "short")
		await ph.say(String(Phoenix.data.lines.after_transform), "playful")
		_stay_until = _session_t + randf_range(Phoenix.data.stay_s[0], Phoenix.data.stay_s[1])
		_log("human", {"cinematic": first})
	_driving = false


func describe() -> Dictionary:
	var st: Dictionary = main.dialogue.state_of("phoenix")
	return {"present": present != null and is_instance_valid(present), "phase": present.phase if present and is_instance_valid(present) else "away",
		"form": present.form if present and is_instance_valid(present) else "", "visits": st.visits, "met": st.met, "relationship": snappedf(st.relationship, 0.01),
		"next_visit_in_s": maxi(0, int(float(st.get("next_visit_unix", 0)) - Time.get_unix_time_from_system())), "events": events.slice(maxi(0, events.size() - 8))}


## Her authored lines are synthesised ahead of time (each once, ever) so the conversation never waits on the cloud.
func _prefetch_lines() -> void:
	if main.voice == null or not main.voice.enabled:
		return
	var d: Dictionary = Phoenix.data
	var items := []
	for k in ["lighting", "before_transform", "after_transform", "farewell"]:
		var mood: String = {"before_transform": "playful", "after_transform": "playful", "farewell": "tender"}.get(k, "")
		items.append([String(d.lines[k]), {"form": "phoenix" if k in ["lighting", "before_transform"] else "humanoid", "mood": mood}])
	items.append([String(d.lines.reform), {"form": "humanoid", "mood": "serious"}])
	for b in d.beats:
		items.append([String(b.npc), {"form": "humanoid", "mood": String(b.get("mood", ""))}])
	for it in items:
		main.voice.prefetch("phoenix", it[0], it[1])


## Luna and this encounter (the V3 continuation directive: "Do not silently move Luna next to Mika when an event
## occurs. If Luna is elsewhere, she must physically travel, or the encounter must proceed without her."):
##   * Luna is in this area: she has heard the phoenix's cry - she comes over on foot (runs along the navmesh) if she
##     is far, and stays herself (her planner is only paused while she comes);
##   * Luna is in another area: nothing moves her - the encounter goes on without her and that is logged.
## Returns "here", "coming" or "away".
func call_luna() -> String:
	var luna: WorldCharacter = main.characters.get("luna")
	var mika: WorldCharacter = main.characters.get("mika")
	if luna == null or mika == null or main.world == null:
		return "away"
	if not luna.visible or luna.world != main.world:
		_log("luna_absent", {"her_area": String(WorldState.mind("luna").location.get("area", "?"))})
		return "away"
	var d := luna.global_position.distance_to(mika.global_position)
	if d < 14.0:
		return "here"
	var beside := mika.global_transform.basis.x.normalized()
	var want := mika.global_position + beside * 2.5
	var at := NavigationServer3D.map_get_closest_point(main.world.get_world_3d().navigation_map, want)
	if at == Vector3.ZERO or at.distance_to(want) > 4.0:
		return "here"          # nowhere walkable beside Mika: she watches from where she is
	var b = main.mage_brains.get("luna")
	var was_held: bool = b.hold if b else false
	if b:
		b.hold = true
		b.interrupt("phoenix")
	luna.navigate_to(at, false)        # she walks over (never a dash)
	_log("luna_coming", {"from_m": snappedf(d, 0.1)})
	var release := func(_a, _ok, _d) -> void:
		if b:
			b.hold = was_held
	luna.action_finished.connect(release, CONNECT_ONE_SHOT)
	return "coming"
