class_name LakeRitual
extends Node
## LANTERN LAKE in the living world (2026-10-19): the night ritual in normal play, and the viewers' lanterns.
##
## The boat (a MoonBoat moored on the west side of the pier) is theirs to take out, day and night:
##   night - Luna rows them out to the clear water among the floating lanterns, Mika lights the bow lantern with a
##           spark, each sets a floating lantern on the water for a wish of her own, the viewers' lanterns that were
##           waiting rise one by one, they let one go for the two of them, lie back and look at the stars, row back.
##   day   - a quiet row out and back (a hand in the water, looking down into it); lanterns and stars are for the
##           night only. A ritual started at night finishes as a night ritual even if dawn comes meanwhile.
## Their planner offers it at the lake (SanctuaryBrain "lakeboat"); the walk down is a home-region visit whose pull
## grows the more nights they have missed the lake (longing) and the more viewers' lanterns wait there.
##
## Viewer lanterns: offer(name, kind) - a new subscriber, member, Super Chat (LiveLink) or a chat wish. Queued, one
## at a time: at the lake at night a lantern with the viewer's name rises beside them (from the water beside the boat
## when they are out on it), both look up at it and thank the viewer by name (local voices, with subtitles). Anywhere
## else (or by day) Mika thanks them at once where it is not the show's own reply, and the lantern waits for the next
## night at the lake (saved with Mika's mind).
##
## Persistence: group "persistent_activity" (ScenePersist): a ritual cut by a restart carries on from its step (the
## boat itself is restored by MoonBoat: who sits where); the queue and the waiting lanterns live in Mika's mind.

static var instance: LakeRitual

const BOAT_NAME := "LakeMoonBoat"
## Lake space (scripts/areas/lantern_lake.gd): the pier runs along x = 4 from the bank (z = 9) out to z = -3.5.
const MOOR := Vector3(1.95, 0.0, -1.5)          # the west side of the pier, bow out to the lake
const MOOR_YAW := -PI * 0.5
const OUT := [Vector3(0.8, 0.0, -7.5), Vector3(-1.5, 0.0, -12.0)]
const SPOT := Vector3(-1.5, 0.0, -12.5)         # the clear water among the floating lanterns
const BACK := [Vector3(-4.6, 0.0, -10.2), Vector3(-1.0, 0.0, -8.6), Vector3(1.95, 0.0, -6.8)]
const TURN_IN := Vector3(1.95, 0.0, -6.2)       # off the end of the pier: she brings the bow round to face the bank
const DOCK := Vector3(1.95, 0.0, -1.3)          # then coasts in bow first along the pier
const DOCK_YAW := PI * 0.5
const DECK_X := 3.55
const DECK_Y := 0.62
const MEM_KEY := "lake_viewer_lanterns"         # Mika's mind: {"queue": [[name, kind, wish]], "pending": [[name, kind]]}
const MAX_QUEUE := 30
const MAX_PENDING := 40
const DEDUPE_S := 120.0
const REACT_S := 9.5

var main: Node
var boat: MoonBoat
var lake: Node3D
var queue: Array = []                # {name, kind, wish, t}
var pending: Array = []              # [name, kind]: thanked, their lantern waits for a night at the lake
var running := ""                    # the ritual's step ("" = no ritual)
var night_ritual := false
var participants: Array = []
var rower := ""
var log: Array = []                  # QA: every viewer event {t, name, kind, where, lines}
var _react := {}                     # the lantern reaction playing {node, t0, name, kind}
var _busy_event := false
var _quiet := false                  # a wish of their own is being made: no viewer lantern now
var _last_launch := -100.0
var _recent := {}                    # "name|kind" -> unix (dedupe)
var _shot := "shore"
var _shot_t := 0.0
var _shot_cut := false
var _cam_owner := ""                 # "ritual" | "react" | ""
var _scene_prev: Callable
var _cam_fn: Callable
var _springs := {}                   # who -> [spring chains, centers] parked by MoonBoat.seat (restored on stepping out)
var _mm_origin := {}                 # WaterLanterns instance -> pushed origin (floating lanterns parted by the hull)
var _say_i := 0
var _abort := false
var _part_frames := 0                 # (a freshly moored boat parts the floating lanterns round it once)


func setup(m: Node) -> void:
	main = m
	instance = self
	name = "LakeRitual"
	add_to_group("persistent_activity")
	_cam_fn = Callable(self, "_cam")
	var mem: Dictionary = WorldState.mind("mika").knowledge.get(MEM_KEY, {}) if WorldState.mind("mika").knowledge.get(MEM_KEY) is Dictionary else {}
	for it in (mem.get("pending", []) as Array):
		if it is Array and (it as Array).size() >= 2:
			pending.append([String(it[0]), String(it[1])])
	for it in (mem.get("queue", []) as Array):
		if it is Array and (it as Array).size() >= 2:
			queue.append({"name": String(it[0]), "kind": String(it[1]), "wish": bool(it[2]) if (it as Array).size() > 2 else false, "t": 0.0})
	main.streaming.area_activated.connect(_on_area)
	if main.streaming.current_id == "lantern_lake":
		_on_area.call_deferred("lantern_lake")
	if not pending.is_empty() or not queue.is_empty():
		print("[lakeritual] from the save: %d viewer lanterns waiting at the lake, %d events queued" % [pending.size(), queue.size()])


# ------------------------------------------------------------------------------------------------ the place
func _on_area(area: String, _r = null) -> void:
	boat = null
	lake = null
	if area != "lantern_lake":
		return
	await get_tree().create_timer(1.2).timeout          # (ScenePersist may bring a saved boat back first)
	if main.streaming.current_id != "lantern_lake":
		return
	_lake()
	# moored at the pier as set dressing - except in other test scenes, which build their own boat at this spot
	if not RenderProfile.options.has("mktest") or RenderProfile.options.has("lake-ritual"):
		_ensure_boat()
	# nobody stands in the lake (a save made while out on the water before the boat existed): back onto the pier
	if running == "" and lake:
		for who in main.characters:
			var c: WorldCharacter = main.characters[who]
			if c.has_meta("persist_activity"):
				continue                                   # (being restored into an activity: a lake dance, the boat)
			if c.visible and not c.seated and _in_water(c.global_position):
				var p := _L(Vector3(DECK_X, DECK_Y, -1.0 + (0.9 if who == "luna" else 0.0)))
				if main.teleport_guard:
					main.teleport_guard.allow(c)
				c.global_position = p + Vector3(0, 0.05, 0)
				c.velocity = Vector3.ZERO
				c.set_physics_process(true)
				print("[lakeritual] %s was in the water: back on the pier" % who)


func _lake() -> Node3D:
	if lake and is_instance_valid(lake) and lake.is_inside_tree():
		return lake
	lake = null
	if main.world == null or main.streaming.current_id != "lantern_lake":
		return null
	var l = main.world.get("lake")
	if l is Node3D and (l as Node3D).get("water_mat") != null:
		lake = l
	else:
		for n in main.world.find_children("*", "Node3D", true, false):
			if n.get("water_mat") != null:
				lake = n
				break
	if lake and lake.has_signal("viewer_launched") and not lake.is_connected("viewer_launched", _on_launched):
		lake.connect("viewer_launched", _on_launched)
	return lake


func _L(v: Vector3) -> Vector3:
	return lake.to_global(v) if lake else v


func _local(v: Vector3) -> Vector3:
	return lake.to_local(v) if lake else v


func _in_water(p: Vector3) -> bool:
	if lake == null:
		return false
	var lp := _local(p)
	if absf(lp.x - 4.0) < 1.15 and lp.z < 9.2 and lp.z > -3.6:
		return false                                   # on the pier
	return float(lake.call("shore_e", lp.x, lp.z)) < -0.6 and lp.y < 0.4


## The boat at this lake (a saved one, or moored now). null where there is no lake.
func _ensure_boat() -> MoonBoat:
	if boat and is_instance_valid(boat) and boat.is_inside_tree():
		return boat
	boat = null
	if _lake() == null:
		return null
	for n in main.world.find_children("*", "", true, false):
		if n is MoonBoat and (n as MoonBoat).is_inside_tree():
			boat = n
			break
	if boat == null:
		boat = MoonBoat.spawn(main.world, _L(MOOR), MOOR_YAW + lake.global_rotation.y, lake.global_position.y)
		boat.name = BOAT_NAME
		print("[lakeritual] the boat is moored at the pier")
	_part_frames = 3
	boat.lake = lake
	boat.day_night = main.get("day_night")
	return boat


## Night? (the day/night cycle's night amount, its override; WorldState.night without one)
func is_night() -> bool:
	var dn = main.get("day_night") if main else null
	if dn:
		if int(dn.override) == 1:
			return true
		if int(dn.override) == 0:
			return false
		if float(dn.k) >= 0.0:
			return float(dn.k) >= 0.5
	return WorldState.night


func _night_now() -> bool:
	return (running != "" and night_ritual) or is_night()


static func is_wish(text: String) -> bool:
	var t := text.strip_edges().to_lower()
	return t.begins_with("!wish") or t.begins_with("i wish ") or t.begins_with("i wish,") or t == "i wish"


# ------------------------------------------------------------------------------------------------ the planner's side
## The boat on offer here, now ("" = not now): once a night (with lanterns), once a day (just the boat).
func boat_offer(b: SanctuaryBrain) -> String:
	if running != "" or main.streaming.current_id != "lantern_lake" or _lake() == null or not b.me.visible or b.threat != null:
		return ""
	if main.travel and main.travel.active():
		return ""
	if is_night():
		if int(b.mind.knowledge.get("lake_boat_night", -1)) == SanctuaryBrain.night_id():
			return ""
		return "take the boat out and light lanterns for our wishes"
	var h := WorldState.hour_f()
	if h < 8.0 or h > 18.0 or int(b.mind.knowledge.get("lake_boat_day", -1)) == WorldState.day():
		return ""
	return "take the boat out on the lake"


func boat_score(b: SanctuaryBrain) -> Dictionary:
	if is_night():
		return {"u": 1.32 + minf(pending.size(), 5) * 0.03, "why": ["the lanterns are why we came"] + (["%d viewers' lanterns waiting" % pending.size()] if not pending.is_empty() else [])}
	return {"u": 0.5 + float(b.needs.curiosity) * 0.2, "why": ["a quiet row on the lake"]}


## How much she misses the lake: grows slowly with every night they have not been (from the second one).
func longing(b: SanctuaryBrain) -> float:
	var k: Dictionary = b.mind.knowledge
	if not k.has("lake_night") and not k.has("lake_boat_night"):
		return 0.12                                    # never been: a gentle pull
	var last := maxi(int(k.get("lake_night", -1000000)), int(k.get("lake_boat_night", -1000000)))
	var missed := SanctuaryBrain.night_id() - last
	return clampf((missed - 1) * 0.12, 0.0, 0.48)


## The walk down to the lake, adjusted: the longing and the viewers' lanterns waiting pull; by day now and then a row.
func visit_pull(b: SanctuaryBrain, u: float) -> Dictionary:
	var why := []
	var lg := longing(b)
	if WorldState.night:
		if int(b.mind.knowledge.get("lake_boat_night", -1)) == SanctuaryBrain.night_id():
			return {"u": -1.0, "why": ["been out on the lake tonight"]}
		if u < 0.0:
			return {"u": u, "why": why}
		if lg > 0.0:
			u += lg
			why.append("missed the lake for nights +%.2f" % lg)
		if not pending.is_empty():
			var pb := 0.15 + 0.05 * minf(pending.size(), 5)
			u += pb
			why.append("%d viewers' lanterns waiting +%.2f" % [pending.size(), pb])
		return {"u": u, "why": why}
	var h := WorldState.hour_f()
	if h >= 9.0 and h <= 16.0 and int(b.mind.knowledge.get("lake_boat_day", -1)) != WorldState.day():
		return {"u": 0.06 + float(b.needs.curiosity) * 0.22 + lg * 0.6, "why": ["a row on the lake by day"]}
	return {"u": u, "why": why}


# ------------------------------------------------------------------------------------------------ viewers' lanterns
## A viewer's lantern: kind subscriber | member | superchat | chat (wish = a chat wish). Queued; never twice in a row
## for the same viewer and kind.
func offer(viewer: String, kind := "chat", wish := false) -> void:
	var n := _clean_name(viewer)
	if n == "":
		return
	if kind not in ["subscriber", "member", "superchat", "chat"]:
		kind = "chat"
	var key := n.to_lower() + "|" + kind
	var now := Time.get_unix_time_from_system()
	if now - float(_recent.get(key, -1e9)) < DEDUPE_S:
		return
	_recent[key] = now
	if queue.size() >= MAX_QUEUE:
		queue.pop_front()
	queue.append({"name": n, "kind": kind, "wish": wish, "t": Time.get_ticks_msec() / 1000.0})
	print("[lakeritual] viewer lantern queued: %s (%s%s), %d in the queue" % [n, kind, ", a wish" if wish else "", queue.size()])
	_save_mem()


static func _clean_name(v: String) -> String:
	var n := VoiceService.clean(v).strip_edges().trim_prefix("@").strip_edges()
	var out := ""
	for ch in n:
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.substr(0, 24).strip_edges()


func _save_mem() -> void:
	var q := queue.map(func(e): return [String(e.name), String(e.kind), bool(e.wish)])
	WorldState.mind("mika").knowledge[MEM_KEY] = {"queue": q, "pending": pending.duplicate(true)}


func _process(delta: float) -> void:
	_shot_t += delta
	if boat and is_instance_valid(boat) and boat.is_inside_tree() and (running != "" or boat.speed > 0.02 or _part_frames > 0):
		_part_frames -= 1
		_part_lanterns()
	if _busy_event:
		return
	var at_lake: bool = main.streaming.current_id == "lantern_lake" and _lake() != null
	if queue.is_empty():
		# the waiting lanterns rise when they are at the lake at night (in the boat the ritual sends them up itself)
		if at_lake and not pending.is_empty() and _night_now() and running == "" and _can_show() and Time.get_ticks_msec() / 1000.0 - _last_launch > 20.0:
			var p: Array = pending.pop_front()
			queue.append({"name": String(p[0]), "kind": String(p[1]), "wish": false, "t": Time.get_ticks_msec() / 1000.0, "later": true})
		return
	if not _can_show():
		return
	var e: Dictionary = queue.pop_front()
	_save_mem()
	_busy_event = true
	_event(e)


## A moment to show a lantern: nothing loading, no transformation, dance or fight, the boat not mid-step, the show not
## in the middle of a line (at most 15 s of waiting for that).
func _can_show() -> bool:
	if main.streaming.state != "idle" or _quiet or running in ["walking", "boarding", "ashore"]:
		return false
	if main.get("transformer") and main.transformer and String(main.transformer.playing) != "":
		return false
	if main.get("performance") and main.performance and main.performance.busy():
		return false
	for w in main.mage_brains:
		var th = main.mage_brains[w].threat
		var cw: WorldCharacter = main.characters.get(w)
		if (th != null and is_instance_valid(th) and cw and (th as Node3D).global_position.distance_to(cw.global_position) < 25.0) or (cw and cw.combat_stance):
			return false
	var oldest: float = float(queue[0].t) if not queue.is_empty() else 0.0
	if main.get("voice") and main.voice and main.voice.busy() and Time.get_ticks_msec() / 1000.0 - oldest < 15.0:
		return false
	return true


## QA: why a queued lantern waits (the gates of _can_show).
func debug_state() -> Dictionary:
	var th := {}
	for w in main.mage_brains:
		var x = main.mage_brains[w].threat
		th[w] = (str(x.get("id")) if is_instance_valid(x) else "freed") if x != null else ""
	return {"queue": queue.size(), "pending": pending.size(), "busy_event": _busy_event, "can_show": _can_show(), "streaming": main.streaming.state,
		"quiet": _quiet, "running": running, "voice_busy": main.voice.busy() if main.get("voice") and main.voice else false,
		"performance": main.performance.busy() if main.get("performance") and main.performance else false,
		"transform": String(main.transformer.playing) if main.get("transformer") and main.transformer else "", "threats": th}


func _event(e: Dictionary) -> void:
	var at_lake: bool = main.streaming.current_id == "lantern_lake" and _lake() != null
	var rec := {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.01), "name": e.name, "kind": e.kind, "wish": e.wish, "lines": []}
	if at_lake and _night_now():
		rec["where"] = "boat" if _on_water() else "pier"
		await _lantern(e, rec)
	else:
		rec["where"] = "waiting (%s)" % ("by day" if at_lake else main.streaming.current_id)
		if pending.size() >= MAX_PENDING:
			pending.pop_front()
		pending.append([String(e.name), String(e.kind)])
		_save_mem()
		await _thank_later(e, rec)
		if main.get("overlay_ui") and main.overlay_ui:
			main.overlay_ui.note("A lantern for %s waits at Lantern Lake" % e.name)
	log.append(rec)
	if log.size() > 60:
		log.pop_front()
	_busy_event = false


## Both of them out on the water in the boat?
func _on_water() -> bool:
	return boat != null and is_instance_valid(boat) and not boat.riders.is_empty() and running not in ["", "walking", "boarding", "ashore"]


func _lantern(e: Dictionary, rec: Dictionary) -> void:
	var lk := _lake()
	var at := Vector3.INF
	var face := Vector3.INF
	var cam_pos := Vector3.INF
	if _on_water():
		var s := _react_frame()
		at = s.lantern
		cam_pos = s.cam
		face = s.cam
	else:
		cam_pos = _L(Vector3(4.0 - 2.4, 1.15, -2.2 - 7.2))
		face = cam_pos
	_react = {"wait": true, "name": e.name, "kind": e.kind, "t0": Time.get_ticks_msec() / 1000.0, "cam": cam_pos}
	lk.viewer_lantern(String(e.name), String(e.kind), at, face)
	var t0 := Time.get_ticks_msec()
	while _react.get("wait", false) and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	if not _react.has("node"):
		print("[lakeritual] the lantern for %s did not appear" % e.name)
		_react = {}
		return
	_last_launch = Time.get_ticks_msec() / 1000.0
	var node: Node3D = _react.node
	rec["lantern_at"] = str(node.global_position.snappedf(0.01))
	_cam_take("react")
	# they notice it: eyes and heads up to it, a smile; the one in the stern points at it
	await get_tree().create_timer(0.5).timeout
	_look_all(node, true)
	await get_tree().create_timer(0.9).timeout
	var lines := _thanks(e)
	for ln in lines:
		rec.lines.append("%s: %s" % [ln[0], ln[1]])
		await _say(String(ln[0]), String(ln[1]), 7.0)
		await get_tree().create_timer(0.35).timeout
	var t_end := float(_react.t0) + REACT_S
	while Time.get_ticks_msec() / 1000.0 < t_end:
		await get_tree().process_frame
	_look_all(null, false)
	_cam_release("react")
	_react = {}
	if main.get("overlay_ui") and main.overlay_ui:
		main.overlay_ui.note("A lantern rose for %s%s" % [e.name, {"subscriber": " (new subscriber)", "member": " (new member)", "superchat": " (Super Chat)", "chat": " (a wish)"}.get(e.kind, "")])


func _on_launched(viewer: String, kind: String, node: Node3D) -> void:
	if not _react.get("wait", false) or viewer != String(_react.get("name", "")):
		return
	_react.erase("wait")
	_react["node"] = node
	# it glows up out of the water (no pop): a ripple, then it grows to its size in a breath
	var s := node.scale
	node.scale = s * 0.05
	create_tween().tween_property(node, "scale", s, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if boat and is_instance_valid(boat):
		boat.ring(node.global_position, 0.8, Color(1.0, 0.8, 0.55), 0.5)


## Heads (and in the boat their upper bodies) toward the lantern - followed as it rises; null lets them go.
func _look_all(node: Node3D, on: bool) -> void:
	var riders_by := {}
	if boat and is_instance_valid(boat):
		for s in boat.riders:
			riders_by[String((boat.riders[s].c as WorldCharacter).character_id)] = s
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		if not c.visible:
			continue
		if riders_by.has(who):
			var s: String = riders_by[who]
			var r: Dictionary = boat.rider(s)
			var life: BodyLife = r.get("life")
			if on and node:
				life.look = func() -> Vector3: return node.global_position + Vector3(0, 0.35, 0) if is_instance_valid(node) else Vector3.INF
				life.look_weight = 0.8
				life.look_max = deg_to_rad(62.0)
				if s == "stern":
					var st := boat.seat_xform(s)
					var to := node.global_position + Vector3(0, 1.2, 0) - st.origin
					boat.point_at(s, to, "Left" if to.dot(st.basis.x) > 0.0 else "Right", 2.6)
			else:
				boat.free_gaze(s)
		else:
			if on and node:
				c.look_head_at(node.global_position + Vector3(0, 0.35, 0))
				_follow_head(c, node)
			else:
				c.look_head_at(null)
		if on and c.face:
			c.face.pulse("happy", 0.6, 3.0)


func _follow_head(c: WorldCharacter, node: Node3D) -> void:
	while not _react.is_empty() and is_instance_valid(node) and is_instance_valid(c):
		c.gaze_to(node.global_position + Vector3(0, 0.35, 0), 0.3)
		await get_tree().create_timer(0.3).timeout


## The thank-you, by name: Mika reads chat; Luna reads the name glowing on the lantern.
func _thanks(e: Dictionary) -> Array:
	var n := String(e.name)
	var luna_here: bool = main.characters.has("luna") and (main.characters["luna"] as Node3D).visible
	var i := _say_i
	_say_i += 1
	var out := []
	if e.get("later", false):
		var who := "luna" if luna_here and i % 2 == 1 else "mika"
		out.append([who, ["And this one is for %s. Thank you again!" % n, "One more lantern, for %s. Thank you." % n][i % 2]])
		return out
	match String(e.kind):
		"subscriber":
			out.append(["mika", ["Look, a new lantern! Thank you for subscribing, %s. Welcome to our world!" % n,
				"%s, thank you for subscribing! That lantern is all yours." % n][i % 2]])
			if luna_here:
				out.append(["luna", ["It has your name on it, %s. Welcome." % n, "Welcome, %s. It's flying high." % n][i % 2]])
		"member":
			out.append(["mika", "%s, thank you so much for becoming a member! Your lantern is going all the way up." % n])
			if luna_here:
				out.append(["luna", "Thank you, %s. We'll keep it burning." % n])
		"superchat":
			out.append(["mika", "Thank you for the Super Chat, %s! Your lantern is the brightest one tonight." % n])
			if luna_here:
				out.append(["luna", "It really is. Thank you, %s." % n])
		_:
			out.append(["mika", "%s made a wish. Up it goes! I hope it comes true." % n])
			if luna_here:
				out.append(["luna", "The lake keeps every wish, %s." % n])
	return out


## Away from the lake (or by day): Mika thanks them now - unless the show answers this one itself (a Super Chat and
## a chat wish arrive as the show's selected message: its reply is the thank-you, the lantern is the extra).
func _thank_later(e: Dictionary, rec: Dictionary) -> void:
	if String(e.kind) == "superchat" or bool(e.wish) or String(e.kind) == "chat":
		return
	var mika: WorldCharacter = main.characters.get("mika")
	if mika == null or not mika.visible:
		return
	var n := String(e.name)
	var text := "Thank you for subscribing, %s! We'll light a lantern for you at the lake tonight." % n if e.kind == "subscriber" \
		else "%s, thank you for becoming a member! There's a lantern waiting for you at the lake." % n
	rec.lines.append("mika: " + text)
	await _say("mika", text, 8.0)


func _say(who: String, text: String, max_s: float) -> void:
	if main.get("voice") == null or main.voice == null:
		return
	var st := {"done": false}
	var voice := String(Progression.mages.get(who, {}).get("voice", who))
	var run := func():
		await main.voice.say(voice, text, {})
		st.done = true
	run.call()
	var t := Time.get_ticks_msec()
	while not st.done and Time.get_ticks_msec() - t < int((max_s + 1.0) * 1000.0):
		await get_tree().process_frame


# ------------------------------------------------------------------------------------------------ the boat ritual
## Run by the planner (SanctuaryBrain "lakeboat"): {ok, detail}.
func boat_ritual(b: SanctuaryBrain, _o := {}) -> Dictionary:
	if running != "":
		return {"ok": false, "detail": "the boat is already out"}
	if _ensure_boat() == null:
		return {"ok": false, "detail": "no boat here"}
	if not boat.riders.is_empty():
		return {"ok": false, "detail": "someone is in the boat"}
	_abort = false
	night_ritual = is_night()
	running = "gathering"
	var me := b.me
	var other: WorldCharacter = null
	var ob: SanctuaryBrain = null
	for wid in main.mage_brains:
		if wid != b.agent_id:
			var oc: WorldCharacter = main.characters.get(wid)
			if oc and oc.visible and oc.global_position.distance_to(me.global_position) < 40.0 and not oc.has_meta("transforming"):
				other = oc
				ob = main.mage_brains[wid]
	if ob:
		ob.hold = true
		ob.interrupt("taking the boat out together")
		await get_tree().create_timer(0.4).timeout
	var cast := {}                                   # seat -> character
	if other and (other.character_id == "luna" or me.character_id != "luna"):
		cast = {"bow": other if other.character_id == "luna" else me, "stern": me if other.character_id == "luna" else other}
	else:
		cast = {"bow": me}
		if other:
			cast["stern"] = other
	rower = (cast.bow as WorldCharacter).character_id
	participants = cast.values().map(func(c): return String(c.character_id))
	# 1. out along the pier to the boat
	running = "walking"
	b.current["stage"] = "walking out to the boat"
	var spots := {}
	for s in cast:
		spots[s] = _deck_spot(s)
	var box := {}
	for s in cast:
		var c: WorldCharacter = cast[s]
		if c != me:
			var job := func(): box[c.character_id] = await ob._walk(spots[s])
			job.call()
	var my_seat: String = cast.keys().filter(func(s): return cast[s] == me)[0]
	var ok_walk := await b._walk(spots[my_seat])
	var tw := Time.get_ticks_msec()
	while ob and box.size() < cast.size() - 1 and Time.get_ticks_msec() - tw < 60000:
		await get_tree().process_frame
	for s in cast.keys():
		var c2: WorldCharacter = cast[s]
		if c2.global_position.distance_to(spots[s]) > 1.6 and c2 != me:
			cast.erase(s)                            # she could not get out there: the other goes alone
	if not ok_walk or me.global_position.distance_to(spots[my_seat]) > 1.6 or main.streaming.current_id != "lantern_lake":
		return _finish(b, ob, false, "could not get out to the boat")
	if cast.size() == 1 and not cast.has("bow"):
		cast = {"bow": me}
	rower = (cast.bow as WorldCharacter).character_id
	participants = cast.values().map(func(c): return String(c.character_id))
	_cam_take("ritual")
	_set_shot("shore")
	var pair := cast.size() > 1
	var lead_id := me.character_id
	var mate_id := (cast.stern as WorldCharacter).character_id if pair and cast.stern != me else ((cast.bow as WorldCharacter).character_id if pair else "")
	for c3 in cast.values():
		(c3 as WorldCharacter).look_at_point(boat.global_position)
	await get_tree().create_timer(0.8).timeout
	if night_ritual:
		await _say(lead_id, "Let's take the boat out and light our lanterns." if pair else "Just me and the lanterns tonight.", 4.0)
		if pair:
			await _say(mate_id, "I'll row. You hold the lanterns." if mate_id == "luna" else "I'll hold the lanterns.", 3.0)
	else:
		await _say(lead_id, "Want to row out for a bit?" if pair else "A little row, I think.", 3.0)
		if pair:
			await _say(mate_id, "Fine. Just a short one.", 3.0)
	# 2. into the boat
	running = "boarding"
	b.current["stage"] = "climbing into the boat"
	for s in ["bow", "stern"]:
		if cast.has(s):
			await _step_in(cast[s], s)
			await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(1.0).timeout
	if _stop(b):
		return await _come_back(b, ob, cast, "the boat came back early")
	# 3. out onto the lake
	running = "out"
	b.current["stage"] = "rowing out onto the lake"
	_set_shot("row")
	await _push_off()
	await _row_path(OUT, 1.8, b)
	if cast.has("stern"):
		boat.trail_hand("stern", "Left", true)
	await _glide_spot()
	if cast.has("stern"):
		boat.trail_hand("stern", "Left", false)
	if _stop(b):
		return await _come_back(b, ob, cast, "the boat came back early")
	if night_ritual:
		await _night_part(b, cast, lead_id, mate_id)
	else:
		await _day_part(b, cast, lead_id, mate_id)
	return await _come_back(b, ob, cast, "")


func _stop(b: SanctuaryBrain) -> bool:
	return _abort or b._cancel or main.streaming.current_id != "lantern_lake" or boat == null or not is_instance_valid(boat) \
		or b._interrupt.begins_with("the show") or b._interrupt in ["threat", "transform"]


## Lanterns for their wishes and for viewers, one for the two of them, the stars.
func _night_part(b: SanctuaryBrain, cast: Dictionary, lead_id: String, mate_id: String) -> void:
	running = "lanterns"
	boat.day_night = null                            # committed: this ritual stays a night ritual to its end
	b.current["stage"] = "lighting lanterns for their wishes"
	_set_shot("two")
	var lighter := "stern" if cast.has("stern") else "bow"
	var lit_already := float(boat.lanterns.get("bow" if lighter == "stern" else "stern", {}).get("lit", 0.0)) > 0.5
	if not lit_already:
		await boat.light_lantern(lighter, "bow" if lighter == "stern" else "stern", "Right")
		await get_tree().create_timer(0.8).timeout
	var nid := SanctuaryBrain.night_id()
	var wishes_m := ["I wish we grow strong enough to reach the tenth orbit together.", "I wish for more nights like this one.",
		"I wish everyone watching us has a good night."]
	var wishes_l := ["Mine stays a secret.", "...Same as yours. Don't tell anyone.", "That every lantern finds its way home."]
	_quiet = true
	for s in ["stern", "bow"]:
		if not cast.has(s) or _stop(b):
			continue
		var who: String = (cast[s] as WorldCharacter).character_id
		_set_shot("two")
		await boat.place_lantern(s, "Left")
		var pool: Array = wishes_l if who == "luna" else wishes_m
		await _say(who, String(pool[absi(nid) % pool.size()]), 5.0)
		await get_tree().create_timer(0.6).timeout
	_quiet = false
	# the viewers' lanterns that were waiting for tonight, one by one (each with its own thank-you)
	if not pending.is_empty() or not queue.is_empty():
		b.current["stage"] = "sending up the viewers' lanterns"
		while not pending.is_empty():
			var p: Array = pending.pop_front()
			queue.append({"name": String(p[0]), "kind": String(p[1]), "wish": false, "t": Time.get_ticks_msec() / 1000.0, "later": true})
		_save_mem()
		var tq := Time.get_ticks_msec()
		while (not queue.is_empty() or _busy_event) and Time.get_ticks_msec() - tq < 120000 and not _stop(b):
			await get_tree().process_frame
	# one for the two of them
	if not _stop(b):
		_set_shot("wide")
		var st := boat.seat_xform("stern" if cast.has("stern") else "bow")
		_lake().call("release_at", st.origin + st.basis.x * 0.9 + Vector3(0, 0.3, 0))
		await _say(lead_id, "And one for the two of us." if mate_id != "" else "And one for me.", 3.5)
		await get_tree().create_timer(3.0).timeout
	# the stars
	if not _stop(b):
		running = "stars"
		b.current["stage"] = "watching the stars from the boat"
		_set_shot("stars")
		for s in cast:
			boat.stargaze(s, true)
		await get_tree().create_timer(3.0).timeout
		await _say(lead_id, "The stars look so close from out here.", 4.0)
		if mate_id != "":
			await _say(mate_id, "Closer every night we practise.", 4.0)
		await get_tree().create_timer(5.0).timeout
		for s in cast:
			boat.stargaze(s, false)
		await get_tree().create_timer(1.0).timeout
	boat.day_night = main.get("day_night")


## By day: just the boat - a hand in the water, looking down into it.
func _day_part(b: SanctuaryBrain, cast: Dictionary, lead_id: String, mate_id: String) -> void:
	running = "drift"
	b.current["stage"] = "drifting on the lake"
	_set_shot("two")
	if cast.has("stern"):
		boat.trail_hand("stern", "Left", true)
	boat.look_water("bow", true, "Left")
	await get_tree().create_timer(2.0).timeout
	await _say(lead_id, "The water's so clear you can see the stones.", 4.0)
	if mate_id != "":
		await _say(mate_id, "And the fish laughing at your hair.", 4.0)
	await get_tree().create_timer(8.0).timeout
	if cast.has("stern"):
		boat.trail_hand("stern", "Left", false)
	boat.look_water("bow", false)
	await get_tree().create_timer(1.0).timeout


## Row back to the pier and climb out (also the way out of a ritual cut short).
func _come_back(b: SanctuaryBrain, ob: SanctuaryBrain, cast: Dictionary, why: String) -> Dictionary:
	if main.streaming.current_id == "lantern_lake" and boat and is_instance_valid(boat):
		running = "back"
		if b:
			b.current["stage"] = "rowing back to the pier"
		_set_shot("row")
		if not boat.riders.is_empty():
			await _row_path(BACK, 1.1, null, 75.0)
			boat.row(false)
			# clear of the pier's end: the bow comes round to the bank, then she coasts in along the pier
			await boat.glide_to(_L(TURN_IN), DOCK_YAW + lake.global_rotation.y, 3.4)
			var dist := boat.global_position.distance_to(_L(DOCK))
			await boat.glide_to(_L(DOCK), DOCK_YAW + lake.global_rotation.y, clampf(dist / 0.8, 3.0, 9.0))
			await get_tree().create_timer(0.5).timeout
		running = "ashore"
		if b:
			b.current["stage"] = "climbing out onto the pier"
		_set_shot("shore")
		for s in ["stern", "bow"]:
			var r := boat.rider(s)
			if not r.is_empty():
				await _step_out(r.c, s)
				await get_tree().create_timer(0.3).timeout
	else:
		_release_all(cast)
	var who_ids: Array = cast.values().map(func(c): return String(c.character_id))
	for w in who_ids:
		var m := WorldState.mind(w)
		if night_ritual:
			m.knowledge["lake_boat_night"] = SanctuaryBrain.night_id()
		else:
			m.knowledge["lake_boat_day"] = WorldState.day()
	if b:
		b.needs.social = clampf(float(b.needs.social) - 0.3, 0.0, 1.0)
		b.needs.energy = clampf(float(b.needs.energy) + 0.08, 0.0, 1.0)
	return _finish(b, ob, true, why if why != "" else ("rowed out on Lantern Lake%s%s" % [", lit lanterns for their wishes" if night_ritual else "",
		" with " + ", ".join(who_ids.filter(func(w): return b == null or w != b.agent_id).map(func(w): return MagicSystem.display_name(w))) if who_ids.size() > 1 else ""]))


func _finish(b: SanctuaryBrain, ob: SanctuaryBrain, ok: bool, detail: String) -> Dictionary:
	_cam_release("ritual")
	if ob:
		ob.hold = false
	for w in participants:
		var pb = main.mage_brains.get(w)
		if pb and pb != b:
			pb.hold = false
	running = ""
	participants = []
	_quiet = false
	if boat and is_instance_valid(boat):
		boat.day_night = main.get("day_night")
	print("[lakeritual] the boat ritual ends: %s (%s)" % [detail, "ok" if ok else "not ok"])
	return {"ok": ok, "detail": detail}


## Where she waits on the pier deck beside her seat (world).
func _deck_spot(seat_name: String) -> Vector3:
	var lp := _local(boat.seat_xform(seat_name).origin)
	return _L(Vector3(DECK_X, DECK_Y, clampf(lp.z, -3.2, 8.4)))


## She steps down from the pier into the boat beside her seat (an arc, not a teleport) and sits.
func _step_in(c: WorldCharacter, seat_name: String) -> void:
	c.stop_action()
	c.set_physics_process(false)
	c.velocity = Vector3.ZERO
	c.set_meta("on_seat", true)                      # (the auditor: stepping down into the boat, not floating)
	var a := c.global_position
	var tw := create_tween()
	tw.tween_method(func(k: float):
		if not is_instance_valid(boat):
			return
		var st := boat.seat_xform(seat_name)
		var bp := st.origin + st.basis.z * 0.22
		bp.y = boat.global_position.y - 0.03
		var p := a.lerp(bp, k)
		p.y += sin(k * PI) * 0.16
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.global_position = p, 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.play_gesture("walk", 0.2, 0.3)
	await tw.finished
	c.end_gesture()
	_park_springs(c)
	if main.teleport_guard:
		main.teleport_guard.allow(c)
	await boat.seat(c, seat_name)


## Up from the seat and onto the pier deck beside it, standing, her physics on again.
func _step_out(c: WorldCharacter, seat_name: String) -> void:
	var deck := _deck_spot(seat_name)
	boat.unseat(seat_name)
	_restore_springs(c)
	var a := c.global_position
	var shore := _L(Vector3(DECK_X, DECK_Y, 9.0)) - deck
	c.global_rotation = Vector3(0.0, atan2(-shore.x, -shore.z), 0.0)
	var tw := create_tween()
	tw.tween_method(func(k: float):
		var p := a.lerp(deck + Vector3(0, 0.03, 0), k)
		p.y += sin(k * PI) * 0.2
		if main.teleport_guard:
			main.teleport_guard.allow(c)
		c.global_position = p, 0.0, 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	c.play_gesture("walk", 0.25, 0.3)
	await tw.finished
	c.end_gesture()
	c.velocity = Vector3.ZERO
	c.set_physics_process(true)
	c.remove_meta("on_seat")


## (a ritual cut off by an area change: nobody is left seated or without physics)
func _release_all(cast: Dictionary) -> void:
	for c in cast.values():
		var wc: WorldCharacter = c
		if is_instance_valid(wc):
			if wc.seated:
				wc.set_seated(false, 0.3)
			wc.end_gesture()
			wc.set_physics_process(true)
			if wc.has_meta("on_seat"):
				wc.remove_meta("on_seat")
			_restore_springs(wc)


## MoonBoat.seat rests her cloth spring chains while she sits; they are given back when she stands up again.
func _park_springs(c: WorldCharacter) -> void:
	var sec = c.avatar.find_child("secondary", true, false) if c.avatar else null
	if sec and sec.get("spring_bones_internal") != null:
		var centers = sec.get("springs_centers")
		_springs[c.character_id] = [(sec.spring_bones_internal as Array).duplicate(), PackedInt32Array(centers) if centers != null else null, sec]


func _restore_springs(c: WorldCharacter) -> void:
	var sv: Array = _springs.get(c.character_id, [])
	_springs.erase(c.character_id)
	if sv.is_empty() or not is_instance_valid(sv[2]):
		return
	var sec = sv[2]
	sec.spring_bones_internal.assign(sv[0])
	if sv[1] != null:
		sec.springs_centers = sv[1]


## A push off from the pier: the boat glides out sideways first (its ends never swing into the posts).
func _push_off() -> void:
	var lp := _local(boat.global_position)
	var fwd := lake.global_basis.inverse() * -boat.global_transform.basis.x
	if fwd.z > 0.3:
		# moored bow to the bank (after an earlier row): pushed well out, the bow swung away to the west
		await boat.glide_to(_L(Vector3(lp.x - 2.0, 0.0, lp.z - 0.5)), boat.heading() - 0.9, 3.2)
	else:
		await boat.glide_to(_L(Vector3(lp.x - (1.4 if lp.x > 0.5 else 0.6), 0.0, lp.z)), boat.heading(), 2.2)


## Row through waypoints (lake space): she steers toward each, never faster than the stroke allows.
func _row_path(points: Array, arrive: float, b: SanctuaryBrain, max_s := 70.0) -> void:
	boat.row(true)
	var t0 := Time.get_ticks_msec()
	for wp in points:
		var tgt := _L(wp)
		while Time.get_ticks_msec() - t0 < int(max_s * 1000.0):
			if boat == null or not is_instance_valid(boat) or main.streaming.current_id != "lantern_lake":
				return
			if b and _stop(b):
				break
			var bp := boat.global_position
			var to := Vector3(tgt.x - bp.x, 0.0, tgt.z - bp.z)
			if to.length() < arrive:
				break
			var fwd := -boat.global_transform.basis.x
			fwd.y = 0.0
			var err := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
			boat.turn = clampf(err * 0.7, -0.3, 0.3)
			# no speed into a sharp turn (a rower eases off while the boat comes round)
			if absf(err) > 1.2:
				boat.speed = minf(boat.speed, 0.45)
			await get_tree().process_frame
	boat.turn = 0.0


## The last stretch out: coasting to a stop on the clear water, turning broadside to the near shore (the lens).
func _glide_spot() -> void:
	boat.row(false)
	var y0 := boat.heading()
	var base := lake.global_rotation.y
	# bow west (yaw 0) or east (yaw PI), whichever is nearer her heading
	var yaw := base if absf(angle_difference(y0, base)) < absf(angle_difference(y0, base + PI)) else base + PI
	await boat.glide_to(_L(SPOT), yaw, 4.5)
	boat.turn = 0.0


# ------------------------------------------------------------------------------------------------ floating lanterns
## The hull parts the floating lanterns (they are pushed aside and stay where they were pushed).
func _part_lanterns() -> void:
	var lk := _lake()
	if lk == null:
		return
	var mmi: MultiMeshInstance3D = lk.get_node_or_null("WaterLanterns")
	if mmi == null or mmi.multimesh == null:
		return
	var mm := mmi.multimesh
	var bx := boat.global_transform
	var c0 := mmi.to_local(bx.origin)
	var ax := mmi.global_basis.inverse() * bx.basis.x.normalized()
	ax.y = 0.0
	ax = ax.normalized()
	var half := 2.25
	for i in mm.instance_count:
		var xf := mm.get_instance_transform(i)
		var o := xf.origin
		if absf(o.x - c0.x) > 4.0 or absf(o.z - c0.z) > 4.0:
			continue
		var rel := Vector3(o.x - c0.x, 0.0, o.z - c0.z)
		var along := clampf(rel.dot(ax), -half, half)
		var near := ax * along
		var off := rel - near
		var need := 0.95 + mm.get_instance_custom_data(i).g * 1.1
		var d := off.length()
		if d < need:
			var dir := off / d if d > 0.01 else ax.cross(Vector3.UP).normalized()
			var np := Vector3(c0.x, o.y, c0.z) + near + dir * need
			xf.origin = Vector3(np.x, o.y, np.z)
			mm.set_instance_transform(i, xf)
	# the little lanterns they set on the water: the hull nudges them aside too
	var fl = boat.get("_floaters")
	if fl is Array:
		for f in fl:
			var n: Node3D = f.get("node")
			if n == null or not is_instance_valid(n):
				continue
			var rel2 := n.global_position - bx.origin
			rel2.y = 0.0
			var ax2 := bx.basis.x.normalized()
			ax2.y = 0.0
			var along2 := clampf(rel2.dot(ax2.normalized()), -half, half)
			var off2 := rel2 - ax2.normalized() * along2
			if off2.length() < 0.9 and off2.length() > 0.001:
				n.global_position += off2.normalized() * (0.9 - off2.length())


# ------------------------------------------------------------------------------------------------ the lens
## The director's scene shot (main.director.begin_scene): medium-wide and wide only (FramingRule: no face over 10%).
func _cam_take(owner: String) -> void:
	if main.get("director") == null or main.director == null:
		return
	if owner == "react":
		if _cam_owner == "ritual":
			_shot_cut = true
			return                                   # the ritual's lens already follows the reaction (see _cam)
		var subj = main.director.get("mika")
		if subj == null or main.streaming.current_id != "lantern_lake" or not main.director.enabled:
			return
		_scene_prev = main.director.get("_scene") if main.director.get("_scene") is Callable else Callable()
	elif not main.director.enabled:
		main.director.enabled = true
	_cam_owner = owner
	_shot_cut = true
	main.director.begin_scene(_cam_fn)


func _cam_release(owner: String) -> void:
	if main.get("director") == null or main.director == null or _cam_owner != owner:
		if owner == "react" and _cam_owner == "ritual":
			_shot_cut = true
		return
	var cur = main.director.get("_scene")
	if cur is Callable and cur == _cam_fn:
		if owner == "react" and _scene_prev.is_valid():
			main.director.begin_scene(_scene_prev)
		else:
			main.director.end_scene()
	_scene_prev = Callable()
	_cam_owner = ""


func _set_shot(s: String) -> void:
	if s != _shot:
		_shot = s
		_shot_t = 0.0
		_shot_cut = true


func _cam(_delta: float) -> Dictionary:
	var out := {}
	if lake == null or not is_instance_valid(lake):
		return out
	if not _react.is_empty() and _react.has("node") and is_instance_valid(_react.node):
		out = _react_shot()
	elif boat and is_instance_valid(boat):
		out = _ritual_shot()
	if out.is_empty():
		return out
	out["cut"] = _shot_cut
	_shot_cut = false
	return out


func _pair_mid() -> Vector3:
	var pts := []
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		if c.visible:
			pts.append(c.global_position)
	if pts.is_empty():
		return boat.global_position if boat else _L(Vector3(4, 0.6, -2))
	var s := Vector3.ZERO
	for p in pts:
		s += p
	return s / pts.size()


## The boat's frame without its bob: centre on the water, bow way, and the side toward the near shore.
func _boat_axes() -> Dictionary:
	var bx := boat.global_transform
	var c0 := bx.origin
	c0.y = lake.global_position.y
	var fwd := -bx.basis.x
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var shore := _L(Vector3(0.0, 0.0, 30.0)) - c0
	if side.dot(shore) < 0.0:
		side = -side
	return {"c": c0, "fwd": fwd, "side": side}


## Where the lens stands for a viewer's lantern seen from the boat, and where the lantern rises: on the near-shore
## side, a little toward the stern, 2 m off the hull - the two of them, the lantern and the lake behind in one frame.
func _react_frame() -> Dictionary:
	var a := _boat_axes()
	var c0: Vector3 = a.c
	var cam: Vector3 = c0 + (a.side as Vector3) * 6.2 + (a.fwd as Vector3) * -2.6 + Vector3(0, 1.25, 0)
	var lan: Vector3 = c0 + (a.side as Vector3) * 2.0 + (a.fwd as Vector3) * 1.35 + Vector3(0, 0.22, 0)
	return {"cam": cam, "lantern": lan}


func _react_shot() -> Dictionary:
	var node: Node3D = _react.node
	var lp := node.global_position
	if _on_water():
		var a := _boat_axes()
		var c0: Vector3 = a.c
		var cam: Vector3 = _react.get("cam", c0 + (a.side as Vector3) * 6.2 + Vector3(0, 1.25, 0))
		var mid := c0 + Vector3(0, 0.95, 0)
		var look := mid.lerp(lp + Vector3(0, 0.45, 0), 0.42)
		look.y = minf(look.y, c0.y + 2.6)
		return {"pos": cam, "look": look, "fov": 50.0, "rate": 1.6}
	var pm := _pair_mid()
	var cam2: Vector3 = _react.get("cam", _L(Vector3(1.6, 1.15, -9.4)))
	var look2 := (pm + Vector3(0, 1.1, 0)).lerp(lp + Vector3(0, 0.45, 0), 0.45)
	return {"pos": cam2, "look": look2, "fov": 50.0, "rate": 1.6}


func _ritual_shot() -> Dictionary:
	var a := _boat_axes()
	var c0: Vector3 = a.c
	var side: Vector3 = a.side
	var fwd: Vector3 = a.fwd
	var t := _shot_t
	match _shot:
		"shore":
			# wide from the bank among the reeds: the pier, the boat beside it, the lake and the lanterns beyond
			return {"pos": _L(Vector3(-2.2 + 0.02 * t, 1.55, 5.6)), "look": _L(Vector3(2.6, 0.9, -3.0)), "fov": 50.0, "rate": 1.5}
		"row":
			# beside the boat, matching its way: the rower's strokes, the two of them whole, the water round them
			return {"pos": c0 + side * 6.4 + fwd * 1.2 + Vector3(0, 2.0, 0), "look": c0 + fwd * 0.4 + Vector3(0, 0.7, 0), "fov": 48.0, "rate": 1.4}
		"two":
			# three-quarter two-shot from the near-shore side, a little high (both whole, lanterns all round)
			return {"pos": c0 + side * 5.2 + fwd * (-2.0 + 0.03 * t) + Vector3(0, 1.9, 0), "look": c0 + Vector3(0, 0.75, 0), "fov": 46.0, "rate": 1.4}
		"wide":
			return {"pos": c0 + side * 9.0 + fwd * 3.0 + Vector3(0, 3.2 + 0.04 * t, 0), "look": c0 + Vector3(0, 1.6, 0) - side * 6.0, "fov": 52.0, "rate": 1.2}
		"stars":
			# high over the water: the two of them lying back in the boat, the lantern sky over them
			return {"pos": c0 + side * 4.4 + fwd * -1.5 + Vector3(0, 4.6, 0), "look": c0 + Vector3(0, 0.3, 0), "fov": 50.0, "rate": 1.2}
	return {"pos": c0 + side * 6.0 + Vector3(0, 2.0, 0), "look": c0 + Vector3(0, 0.8, 0), "fov": 48.0, "rate": 1.4}


# ------------------------------------------------------------------------------------------------ persistence
## (ScenePersist contract) a ritual cut by a restart: the boat brings the girls back to their seats; this carries on
## from its step (the rest of the evening, then rowing back to the pier). The queue and the waiting lanterns are in
## Mika's mind (saved with her).
func persist_key() -> String:
	return "lake_ritual"


func persist_step() -> String:
	return running


func snapshot() -> Dictionary:
	if running == "":
		return {}
	set_meta("persist_area", "lantern_lake")         # (a node of main, not of the area: its activity is at the lake)
	return {"kind": "lake_ritual", "step": running, "night": night_ritual, "rower": rower, "participants": participants.duplicate()}


func restore(d: Dictionary) -> void:
	var step := String(d.get("step", ""))
	if step == "" or running != "":
		return
	var parts: Array = d.get("participants", [])
	night_ritual = bool(d.get("night", is_night()))
	participants = parts.duplicate()
	rower = String(d.get("rower", ""))
	running = "resuming"
	# the boat (ScenePersist rebuilds it with the girls on their seats): wait for it
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		if _ensure_boat() and not boat.riders.is_empty():
			break
	var cast := {}
	if boat:
		for s in boat.riders:
			cast[s] = boat.riders[s].c
	print("[lakeritual] resuming the boat ritual at step '%s' (%s)" % [step, ", ".join(cast.keys().map(func(s): return "%s=%s" % [s, cast[s].character_id]))])
	_cam_take("ritual")
	var lead: SanctuaryBrain = main.mage_brains.get("mika") if parts.has("mika") else (main.mage_brains.get(String(parts[0])) if not parts.is_empty() else null)
	if cast.is_empty():
		for w in parts:
			var c: WorldCharacter = main.characters.get(String(w))
			if c:
				cast[String(w)] = c
		_release_all(cast)
		_finish(null, null, true, "resumed after the restart: they were already ashore")
		return
	if step in ["boarding", "out", "lanterns"] and night_ritual and boat and lead:
		var lead_id := String(parts[0])
		var mate_id := String(parts[1]) if parts.size() > 1 else ""
		if step != "lanterns":
			running = "out"
			await _glide_spot()
		await _night_part(lead, cast, lead_id, mate_id)
	elif step == "stars" and boat:
		for s in cast:
			boat.stargaze(s, true)
		await get_tree().create_timer(6.0).timeout
		for s in cast:
			boat.stargaze(s, false)
	var r := await _come_back(lead if lead and is_instance_valid(lead) else null, null, cast, "resumed after the restart and rowed back")
	for w in parts:
		var pb = main.mage_brains.get(String(w))
		if pb:
			pb.hold = false
	print("[lakeritual] resumed ritual done: %s" % r.detail)
