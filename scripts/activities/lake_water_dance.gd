class_name LakeWaterDance
extends Node
## The lake dance on the water (Selwyn, 2026-10-21, approved: "On clear nights at Lantern Lake, the girls decide on
## their own (not a fixed schedule) to walk the magic path out onto the water and dance to 月の灯り, with the
## lanterns, at most once per night, saved so it doesn't repeat after a restart. Chat can ask for it too." and
## "Walking on the lake must always be magic. Before stepping onto water, the girl plays the cast_water_walk gesture
## and creates a visible path (Mika frost and stars, Luna moonlight), the path glows under each step with ripples,
## and it fades after they leave.")
## On the shore: a line each, both cast (the mocapped cast_water_walk), the path forms (WaterPath) and the navmesh is
## baked again with it. They walk out to the circle in the clear lane among the floating lanterns, dance the lake duet
## (DanceSession: only Selwyn's six lake clips, the MV routine) to the song's chorus, walk back, and it fades. Whole
## body shots only. Mika's mind keeps the night (knowledge "lake_dance_night"), in the save.
## LakeWaterDance.instance; available(), run().

const SONG := "tsuki_no_akari"
const SONG_FILE := "res://assets/audio/music/library/tsuki_no_akari/original.mp3"
# the MV's chorus: the routine is the MV routine (MilestoneKTest.MV_ROUTINE, Selwyn's six clips only)
const FROM := 38.33
const TO := 90.5
const ROUTINE := [
	[38.33, "both", "dancing_a", 9.2, 0.9, 0.4],
	[50.13, "both", "belly_dance", 8.0, 0.9, 0.4],
	[59.26, "luna", "dancing_a", 5.5, 1.0, 0.4],
	[59.91, "mika", "dancing_a", 5.5, 1.0, 0.4],
	[67.08, "both", "belly_dance", 13.0, 0.9, 0.4],
	[72.31, "both", "bellydancing", 18.0, 0.95, 0.4],
	[78.81, "luna", "samba", 1.0, 0.9, 0.4],
	[78.81, "mika", "rumba", 0.0, 0.9, 0.4],
	[84.03, "both", "belly_dance", 1.0, 0.9, 0.4],
]
const CUTS := [38.33, 47.51, 56.63, 64.46, 72.31, 80.13, 87.91]   # camera cuts on the chorus' bar lines
const SPOT := Vector3(-1.5, 0.0, -9.0)      # lake space: the clear lane among the floating lanterns (the MV's spot)
const RADIUS := 3.0
const LINES := {
	"ask": {"mika": ["The lake is so still tonight. Shall we dance out there, on the water?", "Look at all the lanterns. I want to dance among them.",
			"Stars on the water... Luna, let's walk out to them.", "Tonight is perfect. Come dance with me on the lake!"],
		"luna": ["The water is calm enough tonight. Dance with me out there?", "The moon is on the water. Let's go stand in it."]},
	"answer": {"luna": ["Your frost, my moonlight. Together it will hold.", "Only if you light the way back too.", "Then I'll follow your stars.",
			"All right. But I lead the slow part."],
		"mika": ["Yes! Frost for me, moonlight for you.", "Always. Let's make the path together."]},
	"end": {"mika": ["The lake will remember that one.", "I could dance out here every night.", "That was the best part of my whole day.",
			"Did you see the lanterns turn with us?"],
		"luna": ["Your frost held. I knew it would.", "Let's walk back before the path forgets us.", "The moon was watching, you know.",
			"Thank you for that dance, Mika."]},
}

static var instance: LakeWaterDance

var main: Node
var running := false
var stage := ""
var path: WaterPath
var _player: AudioStreamPlayer
var _session: DanceSession
var _shot := {}
var rng := RandomNumberGenerator.new()


func setup(m: Node) -> void:
	main = m
	instance = self
	name = "LakeWaterDance"
	rng.randomize()


## "" when it can happen here and now, otherwise why not (the planner's and the chat's check).
func available(lead := "mika") -> String:
	if running:
		return "already dancing on the lake"
	if main.streaming.current_id != "lantern_lake" or main.streaming.state != "idle":
		return "not at the lake"
	if LakeRitual.instance == null or not LakeRitual.instance.is_night():
		return "not night"
	if LakeRitual.instance.running != "":
		return "the boat is out"
	var wx = main.get("weather")
	if wx and (float(wx.rain) > 0.15 or float(wx.get("cloud") if wx.get("cloud") != null else 0.0) > 0.6):
		return "not a clear night"
	if main.travel and main.travel.active():
		return "travelling"
	if main.performance and main.performance.busy():
		return "a dance is on"
	if danced_tonight():
		return "danced on the lake tonight already"
	for id in ["mika", "luna"]:
		var c: WorldCharacter = main.characters.get(id)
		if c == null or not c.visible:
			return "%s is not here" % id
	if _lake() == null:
		return "no lake"
	return ""


static func danced_tonight() -> bool:
	return int(WorldState.mind("mika").knowledge.get("lake_dance_night", -1)) == SanctuaryBrain.night_id()


func _lake() -> Node3D:
	return LakeRitual.instance._lake() if LakeRitual.instance else null


# ------------------------------------------------------------------------------------------------- the whole night
func run(why := "their own idea") -> Dictionary:
	var why_not := available()
	if why_not != "":
		return {"ok": false, "detail": why_not}
	running = true
	stage = "starting"
	var lake := _lake()
	var area = main.streaming.current
	var chars := {"mika": main.characters["mika"] as WorldCharacter, "luna": main.characters["luna"] as WorldCharacter}
	var held := []
	for id in chars:
		var b = main.mage_brains.get(id)
		if b:
			if not b.hold:
				held.append(b)
			b.hold = true
			if not (b.current as Dictionary).is_empty():
				b.interrupt("the lake dance")
	# the night is theirs from here (a restart mid-dance does not dance it again)
	WorldState.mind("mika").knowledge["lake_dance_night"] = SanctuaryBrain.night_id()
	WorldState.mind("luna").knowledge["lake_dance_night"] = SanctuaryBrain.night_id()
	WorldState.save_async("lake dance")
	print("[lakedance] start (%s)" % why)
	var res := {"ok": false, "detail": ""}
	var ok := await _sequence(lake, area, chars)
	res.ok = ok
	res.detail = "danced on the lake" if ok else "the lake dance stopped: %s" % stage
	# whatever happened: everything back
	_end_music(1.2)
	if main.director:
		main.director.end_scene()
	if path and is_instance_valid(path):
		await _remove_path(area)
	for b in held:
		b.hold = false
	running = false
	stage = ""
	print("[lakedance] end: %s" % res.detail)
	if ok:
		for id in chars:
			WorldState.record_activity({"id": "lake_dance:%s" % SONG, "verb": "perform", "label": "Danced on Lantern Lake to 月の灯り"}, {}, id)
	return res


func _sequence(lake: Node3D, area, chars: Dictionary) -> bool:
	# 1. the shore point where the clear lane meets the land
	var lane := _lane(lake, area)
	var shore: Vector3 = lane.shore
	var fwd: Vector3 = lane.fwd
	var side := Vector3(-fwd.z, 0, fwd.x)
	var stand := {"mika": shore - fwd * 1.1 - side * 0.7, "luna": shore - fwd * 1.1 + side * 0.7}
	stage = "walking to the shore"
	for id in chars:
		var p: Vector3 = NavigationServer3D.map_get_closest_point(chars[id].get_world_3d().navigation_map, lake.to_global(stand[id]))
		chars[id].navigate_to(p, false)
	if not await _wait_arrive(chars.values(), 40.0):
		return false
	for id in chars:
		chars[id].look_at_point(lake.to_global(shore + fwd * 6.0))
	await get_tree().create_timer(0.8).timeout
	# 2. a line each
	stage = "talking on the shore"
	_shot = {"kind": "shore", "t0": _now(), "lake": lake, "shore": shore, "fwd": fwd}
	if main.director:
		main.director.begin_scene(Callable(self, "_cam"))
	var asker := "mika"
	await _say(asker, await _line("ask", asker))
	await _say("luna", await _line("answer", "luna"))
	# 3. both cast, the path forms
	stage = "casting the path"
	path = WaterPath.new()
	lake.add_child(path)
	path.build(shore - fwd * 0.4, SPOT, RADIUS)
	path.walkers = chars.values()
	for id in chars:
		var c: WorldCharacter = chars[id]
		if c.has_clip("ml_cast_water_walk"):
			c.play_gesture("ml_cast_water_walk", 0.3, 0.5)
	await get_tree().create_timer(1.6).timeout             # (the gather; the path answers the release)
	if main.audio and main.audio.has_method("play_progress"):
		main.audio.play_progress("discovery", -8.0, "water_path")
	await path.form(2.8)
	path.set_solid(true)
	await _rebake(area, true)
	for id in chars:
		chars[id].end_gesture()
	Highlights.moment(main, "lake_dance", "Mika and Luna walk out over Lantern Lake on a path of frost and moonlight", 5.0)
	# 4. out to the circle
	stage = "walking out on the water"
	if main.director:
		main.director.end_scene()                             # (the chase lens follows Mika out)
	var mark := {"mika": SPOT + side * 0.75, "luna": SPOT - side * 0.75}
	for id in chars:
		chars[id].navigate_to(lake.to_global(mark[id] + Vector3(0, WaterPath.TOP, 0)), false)
	if not await _wait_arrive(chars.values(), 45.0):
		# (the navmesh did not reach the circle: never walk them over bare water) back to the shore
		stage = "the path did not reach the circle"
		return false
	for id in chars:
		chars[id].look_at_point(lake.to_global(SPOT - fwd * 8.0))
	await get_tree().create_timer(0.9).timeout
	# 5. the dance
	stage = "dancing"
	_start_music()
	_session = DanceSession.begin(main.world, [chars.luna, chars.mika], ROUTINE, FROM, TO, "lake_water_dance")
	_shot = {"kind": "dance", "lake": lake, "fwd": fwd, "side": side}
	if main.director:
		main.director.begin_scene(Callable(self, "_cam"))
	while _session and is_instance_valid(_session) and _session.playing:
		await get_tree().process_frame
	await _release_decks(chars.values())
	if is_instance_valid(_session):
		_session.queue_free()
	_session = null
	_end_music(3.0)
	await get_tree().create_timer(0.6).timeout
	_shot = {"kind": "shore_back", "t0": _now(), "lake": lake, "shore": shore, "fwd": fwd}
	await _say("mika", await _line("end", "mika"))
	await _say("luna", await _line("end", "luna"))
	if main.director:
		main.director.end_scene()
	# 6. back to the shore, then the path fades
	stage = "walking back"
	for id in chars:
		var back: Vector3 = NavigationServer3D.map_get_closest_point(chars[id].get_world_3d().navigation_map, lake.to_global(stand[id] - fwd * 1.5))
		chars[id].navigate_to(back, false)
	await _wait_arrive(chars.values(), 45.0)
	return true


## The clear lane's shore: from the circle toward the bank, the first point on land (lake space).
func _lane(lake: Node3D, area) -> Dictionary:
	var fwd := Vector3(0, 0, -1)                   # out over the water, toward the circle
	var z := SPOT.z + RADIUS
	while z < 30.0 and float(area.h(SPOT.x, z)) < 0.12:
		z += 0.25
	return {"shore": Vector3(SPOT.x, float(area.h(SPOT.x, z)), z + 0.5), "fwd": fwd}


func _wait_arrive(cs: Array, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	await get_tree().process_frame
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if cs.all(func(c): return (c as WorldCharacter).current_action != "navigate_to"):
			return true
		await get_tree().process_frame
	return false


func _rebake(area, with_path: bool) -> void:
	if area == null or not area.has_method("bake_navigation"):
		return
	if with_path:
		area.set_meta("nav_aabb_before", area.nav_aabb)
		area.nav_aabb = area.nav_aabb.merge(AABB(Vector3(SPOT.x - RADIUS - 1.0, -1.0, SPOT.z - RADIUS - 1.0), Vector3((RADIUS + 1.0) * 2.0, 4.0, (RADIUS + 1.0) * 2.0)))
	elif area.has_meta("nav_aabb_before"):
		area.nav_aabb = area.get_meta("nav_aabb_before")
		area.remove_meta("nav_aabb_before")
	await area.bake_navigation()


func _remove_path(area) -> void:
	var p := path
	path = null
	await p.dissolve(6.0)
	await _rebake(area, false)
	p.queue_free()


func _release_decks(cs: Array) -> void:
	var tw := create_tween().set_parallel(true)
	var any := false
	for c in cs:
		for n in (c as WorldCharacter).skeleton.get_children():
			if n is DanceDeck:
				tw.tween_property(n, "influence", 0.0, 0.8)
				any = true
	if any:
		await tw.finished
	else:
		tw.kill()


# ------------------------------------------------------------------------------------------------- music and words
func _start_music() -> void:
	if not ResourceLoader.exists(SONG_FILE):
		push_warning("[lakedance] the song is missing: " + SONG_FILE)
		return
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.stream = load(SONG_FILE)
	_player.volume_db = -30.0
	add_child(_player)
	_player.play(FROM)
	create_tween().tween_property(_player, "volume_db", 4.0, 1.5)


func _end_music(secs: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var p := _player
	_player = null
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -40.0, secs)
	tw.tween_callback(p.queue_free)


func _say(who: String, text: String) -> void:
	if text == "" or main.voice == null:
		return
	await main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), text)


## A line she has never said: from the pool, or (all said) the same thought in new words.
func _line(kind: String, who: String) -> String:
	var pool: Array = LINES.get(kind, {}).get(who, [])
	var voice := String(Progression.mages.get(who, {}).get("voice", who))
	var l := LineMemory.fresh(voice, pool, rng)
	if l != "":
		return l
	var llm: LLMClient = LLMClient.instance
	if llm == null or llm.provider == "mock" or pool.is_empty():
		return ""
	var sys := ("You are %s, a young mage, at Lantern Lake at night with %s. Say ONE short spoken line (under 22 words) meaning the same as the "
		+ "given line, in completely new words. No em dashes, no quotes. JSON {\"text\": string}.") % [MagicSystem.display_name(who), MagicSystem.display_name("luna" if who == "mika" else "mika")]
	var r: Dictionary = await llm.ask_json(sys, JSON.stringify({"line": pool[rng.randi() % pool.size()]}), {"text": ""}, "lake_dance_line")
	var nt := VoiceService.clean(String(r.get("json", {}).get("text", "")))
	return nt if nt.length() > 3 and LineMemory.said_before(voice, nt).is_empty() else ""


# ------------------------------------------------------------------------------------------------- the lens
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Whole body only. On the shore: from over the water, the two of them and the bank. Dancing: the shot list cut on
## the chorus' bar lines (wide from the shore side, a slow orbit, low over the water, a crane), always both whole.
func _cam(_delta: float) -> Dictionary:
	var lake: Node3D = _shot.get("lake")
	if lake == null or not is_instance_valid(lake):
		return {}
	var kind := String(_shot.get("kind", ""))
	if kind in ["shore", "shore_back"]:
		var sh: Vector3 = _shot.shore
		var f: Vector3 = _shot.fwd
		var focus := sh - f * 1.1 + Vector3(0, 0.95, 0)
		if kind == "shore_back":
			focus = SPOT + Vector3(0, 0.95, 0)
			return {"pos": lake.to_global(focus - f * 6.5 + Vector3(2.2, 1.5, 0)), "look": lake.to_global(focus), "fov": 50.0, "rate": 1.5}
		var el := _now() - float(_shot.t0)
		return {"pos": lake.to_global(focus + f * (6.0 - minf(el, 10.0) * 0.08) + Vector3(-1.6, 1.0, 0)), "look": lake.to_global(focus), "fov": 50.0, "rate": 1.5}
	if kind != "dance" or _session == null or not is_instance_valid(_session):
		return {}
	var t := _session.song_t
	var i := 0
	for k in CUTS.size():
		if t >= float(CUTS[k]):
			i = k
	var u := clampf((t - float(CUTS[i])) / maxf((float(CUTS[i + 1]) if i + 1 < CUTS.size() else TO) - float(CUTS[i]), 0.1), 0.0, 1.0)
	var c := SPOT + Vector3(0, 0.95, 0)
	var f2: Vector3 = _shot.fwd
	var front := -f2                                   # they face the shore
	var sd: Vector3 = _shot.side
	var pos: Vector3
	var look := c
	var fov := 50.0
	match i % 4:
		0:   # wide from the shore side: both whole, the lanterns and the lake behind them
			pos = c + front * lerpf(8.5, 7.6, u) + sd * 2.4 + Vector3(0, 1.1, 0)
		1:   # a slow orbit round the front
			var a := lerpf(-0.75, 0.75, u)
			pos = c + (front.rotated(Vector3.UP, a)) * 6.2 + Vector3(0, 0.7, 0)
			fov = 48.0
		2:   # low over the water, from the front-left
			pos = c + front * 5.2 - sd * 3.4 + Vector3(0, 0.15, 0)
			look = c + Vector3(0, 0.2, 0)
		_:   # a crane rising over them
			pos = c + front * 6.8 + Vector3(0, lerpf(2.6, 5.4, u), 0)
			look = c - Vector3(0, 0.3, 0)
			fov = 52.0
	return {"pos": lake.to_global(pos), "look": lake.to_global(look), "fov": fov, "rate": 2.0, "cut": u < 0.02}
