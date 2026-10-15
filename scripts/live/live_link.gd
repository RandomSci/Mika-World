class_name LiveLink
extends Node
## The Godot world as Mika-Live's Stage (--live-link[=ws://127.0.0.1:12393/client-ws]). It speaks the same room
## protocol the Three.js world page spoke (Mika-Live frontend/vr-agent/teaching-dev-room.js + world/lifestyle-
## executor.js), so the server's brain - YouTube chat, the conversational LLM, Kokoro speech, viewer intents, the
## showrunner's goals and dance sessions, pre-live and the broadcast lifecycle - drives Mika and Luna here instead:
##   in : audio (her speech: base64 WAV + caption) -> spoken by her, mouth and body following; backend-synth-complete;
##        control interrupt; youtube-live-selected-message (the chat card); lifestyle-action (an activity) ->
##        done in this world and answered with lifestyle-action-result; lifestyle-cancel; lifestyle-status.
##   out: vr-agent-hello (the Stage, with a lifestyle), heartbeat, audio-play-start / -end, frontend-playback-
##        complete, lifestyle-client-state (what is really true here: area, activity, places, capabilities).
## Only activities this world can really do are advertised (capabilities); the server plans only those.

const DEFAULT_URL := "ws://127.0.0.1:12393/client-ws"
# server routine ids (Mika-Live dance-game.js ROUTINES) -> this world's dance clips
const ROUTINES := {"macarena": "dance_macarena", "chicken": "dance_chicken", "step": "dance_step", "snake_hiphop": "dance_snake",
	"booty_hiphop": "dance_booty", "ymca": "dance_ymca", "belly": "dance_belly"}
# what this world can do, in the server's capability names
const CAPABILITIES := ["dance", "dance_session", "dance_session_start", "dance_routine", "dance_session_end", "repeat_dance", "stop_dancing",
	"magic_lesson", "magic_prepare", "magic_cast", "magic_finish", "read_book", "sit_chair", "look_out_window", "explore", "go_to",
	"walk_to_anchor", "stand_relaxed", "casual_phone_chat", "listen_to_viewer", "presentation_beat", "stabilize_camera", "quiet_outside"]

# seconds this world answers within (a little under the server's wait for each action)
const LIMITS := {"magic_lesson": 400, "magic_prepare": 230, "magic_cast": 40, "magic_finish": 90, "read_book": 150, "explore": 310,
	"go_to": 240, "walk_to_anchor": 55, "sit_chair": 55, "quiet_outside": 310, "look_out_window": 55}

var main: Node
var url := DEFAULT_URL
var ws := WebSocketPeer.new()
var connected := false
var _retry_t := 0.0
var _hb_t := 0.0
var _state_t := 0.0
var _speech: Array = []          # queued {who, wav, text, trace}
var _speaking := false
var _synth_complete := false
var _command := {}               # the running lifestyle action {id, action}
var _results := {}               # id -> result (a repeated id is answered again, never re-run)
var activity := "stand_relaxed"
var log: Array = []


func setup(m: Node) -> void:
	main = m
	var u := String(RenderProfile.options.get("live-link", ""))
	if u != "" and u != "true":
		url = u
	ws.inbound_buffer_size = 16 * 1024 * 1024      # a long line of speech arrives as one message
	ws.outbound_buffer_size = 1024 * 1024
	# a fixed window name: OBS captures this window by name and class (the project name may change)
	get_window().title = "Mika World Stage"
	print("[livelink] Stage for Mika-Live at %s" % url)


func _process(delta: float) -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			_hello()
		while ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var msg = JSON.parse_string(txt)
			if msg is Dictionary:
				_on_message(msg)
		_hb_t += delta
		if _hb_t > 20.0:
			_hb_t = 0.0
			_send({"type": "heartbeat"})
		_state_t += delta
		if _state_t > 2.5:
			_state_t = 0.0
			_report()
	elif st == WebSocketPeer.STATE_CLOSED:
		if connected:
			connected = false
			print("[livelink] disconnected (%d); retrying" % ws.get_close_code())
		_retry_t -= delta
		if _retry_t <= 0.0:
			_retry_t = 3.0
			ws = WebSocketPeer.new()
			ws.inbound_buffer_size = 16 * 1024 * 1024
			ws.outbound_buffer_size = 1024 * 1024
			ws.connect_to_url(url)
	if not _speaking and not _speech.is_empty():
		_play_next()


func _send(d: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


func _hello() -> void:
	print("[livelink] connected: the Godot world is the Stage")
	_send({"type": "vr-agent-hello", "mode": "room", "role": "scene1-stage", "lifestyle": true, "obs": true, "renderer": "godot"})
	_report(true)


func _on_message(m: Dictionary) -> void:
	match String(m.get("type", "")):
		"audio":
			_enqueue_audio(m)
		"backend-synth-complete":
			_synth_complete = true
			_maybe_playback_complete()
		"control":
			match String(m.get("text", "")):
				"interrupt":
					_speech.clear()
					if main.voice:
						main.voice.stop()
				"conversation-chain-start":
					_synth_complete = false
		"youtube-live-selected-message":
			_chat_card(m)
		"lifestyle-action":
			_action(m)
		"lifestyle-cancel":
			if String(_command.get("id", "")) == String(m.get("id", "")) and main.performance:
				main.performance.interrupt("the show asked to stop")
		"lifestyle-viewer-noticed":
			_glance("mika")
		_:
			pass


# ------------------------------------------------------------------ speech
func _enqueue_audio(m: Dictionary) -> void:
	var who := String(m.get("character")) if m.get("character") is String else "mika"
	if not main.characters.has(who):
		return                                   # a voice for someone not in this world (as the world page did)
	var b64 := String(m.get("audio", "")) if m.get("audio") is String else ""
	var text := ""
	if m.get("display_text") is Dictionary:
		text = String((m.display_text as Dictionary).get("text", ""))
	_speech.append({"who": who, "wav": Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray(), "text": text,
		"trace": m.get("speech_trace") if m.get("speech_trace") is Dictionary else {}, "monitor": bool(m.get("monitor", false)), "received": int(Time.get_unix_time_from_system() * 1000.0)})


func _play_next() -> void:
	_speaking = true
	var item: Dictionary = _speech.pop_front()
	var tr: Dictionary = item.trace
	if not item.monitor:
		_send({"type": "audio-play-start", "display_text": {"text": item.text} if item.text != "" else null, "forwarded": true,
			"trace_id": tr.get("trace_id"), "sequence": tr.get("sequence"), "received_at_ms": item.received, "at_ms": int(Time.get_unix_time_from_system() * 1000.0)})
	var opts := {"wav": item.wav, "priority": 1}
	await main.voice.say(String(item.who), String(item.text), opts)
	if not item.monitor and not tr.is_empty():
		_send({"type": "audio-play-end", "sequence": tr.get("sequence"), "trace_id": tr.get("trace_id"), "at_ms": int(Time.get_unix_time_from_system() * 1000.0)})
	_speaking = false
	_maybe_playback_complete()


func _maybe_playback_complete() -> void:
	if _synth_complete and not _speaking and _speech.is_empty():
		_synth_complete = false
		_send({"type": "frontend-playback-complete"})


## The viewer comment she is answering, as a card on screen (what the Three.js page showed): @author, the message,
## a Super Chat amount, "to Mika & Luna". Hidden again when the server says the answer is over.
var _card: PanelContainer
var _card_id := ""


func _chat_card(m: Dictionary) -> void:
	if not bool(m.get("active", false)):
		if _card and (String(m.get("id", "")) == _card_id or _card_id == ""):
			_card.visible = false
		return
	var to: Array = (m.get("to") as Array).filter(func(t): return main.characters.has(String(t))) if m.get("to") is Array else []
	_glance(String(to[0]) if not to.is_empty() else "mika")
	if _card == null:
		var layer := CanvasLayer.new()
		layer.layer = 40
		add_child(layer)
		_card = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.06, 0.14, 0.82)
		sb.border_color = Color(0.95, 0.78, 0.5, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(16)
		_card.add_theme_stylebox_override("panel", sb)
		_card.anchor_left = 0.03
		_card.anchor_top = 0.06
		_card.offset_right = 520
		layer.add_child(_card)
		var v := VBoxContainer.new()
		v.name = "V"
		_card.add_child(v)
		for n in ["Author", "Message", "To"]:
			var l := Label.new()
			l.name = n
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 480
			l.add_theme_font_size_override("font_size", 30 if n == "Message" else 22)
			l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6) if n == "Author" else (Color(0.8, 0.78, 0.9) if n == "To" else Color(1, 1, 1)))
			v.add_child(l)
	var author := String(m.get("author", "Viewer")).left(60)
	var amount := String(m.get("amount", "")) if m.get("amount") is String else ""
	(_card.get_node("V/Author") as Label).text = (author if author.begins_with("@") else "@" + author) + ("   " + amount if amount != "" else "")
	(_card.get_node("V/Message") as Label).text = String(m.get("message", "")).left(220)
	var names := to.map(func(t): return String(t).capitalize())
	(_card.get_node("V/To") as Label).text = ("to " + " & ".join(names)) if not names.is_empty() else ""
	_card_id = String(m.get("id", ""))
	_card.visible = true


func _glance(who: String) -> void:
	var c: WorldCharacter = main.characters.get(who)
	var cam := get_viewport().get_camera_3d()
	if c and cam:
		c.look_head_at(cam.global_position)
		get_tree().create_timer(2.2).timeout.connect(func(): if is_instance_valid(c): c.look_head_at(null))


# ------------------------------------------------------------------ activities
func _action(m: Dictionary) -> void:
	var id := String(m.get("id", ""))
	if _results.has(id):
		_send(_results[id])
		return
	var action := String(m.get("action", ""))
	var args: Dictionary = m.get("args", {}) if m.get("args") is Dictionary else {}
	if not _command.is_empty() and String(m.get("priority", "")) != "viewer_micro":
		_send({"type": "lifestyle-action-result", "id": id, "ok": false, "reason": "action_in_progress", "state": _snapshot()})
		return
	_command = {"id": id, "action": action}
	var r: Dictionary = await _do(action, args)
	_command = {}
	var res := {"type": "lifestyle-action-result", "id": id, "ok": bool(r.get("ok", false)), "state": _snapshot()}
	if r.has("value"):
		res["value"] = r.value
	if not res.ok:
		res["reason"] = String(r.get("reason", "unsupported_in_this_world"))
	_results[id] = res
	if _results.size() > 64:
		_results.erase(_results.keys()[0])
	log.append({"action": action, "ok": res.ok, "reason": res.get("reason", ""), "t": Time.get_unix_time_from_system()})
	if log.size() > 40:
		log.pop_front()
	_send(res)
	_report(true)


## One server activity, done for real in this world. {ok, value?, reason?}
func _do(action: String, args: Dictionary) -> Dictionary:
	match action:
		"dance", "dance_routine", "repeat_dance", "dance_session", "dance_session_start":
			if main.performance == null:
				return {"ok": false, "reason": "no_dance_system"}
			var routine := String(args.get("routine", ""))
			var clip := String(ROUTINES.get(routine, ""))
			# she finishes (or drops) what she is doing first: her own planner is held while the show's dance runs
			var mb = main.mage_brains.get("mika")
			if mb:
				mb.hold = true
				mb.interrupt("the show asked for a dance")
			var w0 := Time.get_ticks_msec()
			while mb and not mb.current.is_empty() and Time.get_ticks_msec() - w0 < 25000:
				await get_tree().process_frame
			activity = "dance"
			var req := {"dance": clip, "partner_if_near": true, "why": "the show"}
			main.performance.request("mika", req)
			var t0 := Time.get_ticks_msec()
			while not main.performance.busy() and Time.get_ticks_msec() - t0 < 45000:
				await get_tree().process_frame
			if not main.performance.busy():
				# never danced later after saying it could not
				main.performance.requests = main.performance.requests.filter(func(r): return String(r.get("why", "")) != "the show")
				activity = "stand_relaxed"
				if mb:
					mb.hold = false
				var av: Dictionary = main.performance.available("mika")
				return {"ok": false, "reason": "could_not_start_dancing_now: %s" % String(av.get("why", av.get("reason", "")))}
			if mb:
				# held a little after the dance too: the show's next request usually follows at once
				main.performance.ended.connect(func(_e): get_tree().create_timer(8.0).timeout.connect(func(): if _command.is_empty(): mb.hold = false), CONNECT_ONE_SHOT)
			var t1 := Time.get_ticks_msec()
			while main.performance.busy() and Time.get_ticks_msec() - t1 < 195000:
				await get_tree().process_frame
			if main.performance.busy():
				return {"ok": true, "value": {"routine": routine, "still_dancing": true}}
			activity = "stand_relaxed"
			var last: Dictionary = main.performance.log[-1] if not main.performance.log.is_empty() else {}
			return {"ok": bool(last.get("ok", false)), "value": {"routine": routine, "clips": last.get("clips", []), "partner": last.get("partner", ""), "completed": bool(last.get("ok", false))}, "reason": String(last.get("detail", ""))}
		"stop_dancing", "dance_session_end":
			if main.performance and main.performance.busy():
				main.performance.interrupt("asked to stop")
			return {"ok": true}
		"magic_lesson", "magic_prepare", "magic_cast", "magic_finish":
			return await _brain_do(["magic", "drill", "lesson"], "magic")
		"read_book":
			return await _brain_do(["research"], "read_book")
		"sit_chair", "quiet_outside":
			return await _brain_do(["rest", "attune", "listen_rain"], "sit")
		"look_out_window", "explore", "go_to", "walk_to_anchor":
			return await _brain_do(["explore", "investigate", "roam"], "explore")
		"stand_relaxed", "casual_phone_chat", "listen_to_viewer", "presentation_beat", "stabilize_camera":
			_glance("mika")
			activity = "stand_relaxed"
			return {"ok": true}
	return {"ok": false, "reason": "unsupported_in_this_world"}


## The show asked for an activity: her own planner's best-scoring option of that kind, run by her brain (held so its
## loop does not start something else meanwhile) - so it is always something real and possible here.
func _brain_do(kinds: Array, label: String) -> Dictionary:
	var mb = main.mage_brains.get("mika")
	if mb == null or not mb.enabled:
		return {"ok": false, "reason": "not_ready"}
	var pick := {}
	for o in mb.ranked():
		if String(o.kind) in kinds:
			pick = o
			break
	if pick.is_empty():
		return {"ok": false, "reason": "nothing_for_%s_here" % label}
	mb.hold = true
	mb.interrupt("the show")
	var t0 := Time.get_ticks_msec()
	while not mb.current.is_empty() and Time.get_ticks_msec() - t0 < 45000:
		await get_tree().process_frame
	if not mb.current.is_empty():
		mb.hold = false
		return {"ok": false, "reason": "she_is_busy"}
	activity = label
	var job := {"done": false, "r": {}}
	_run_pick(mb, pick, job)
	# answered before the server's own wait runs out (Mika-Live lifestyle.ACTION_TIMEOUTS); she keeps going
	var limit_ms := int(float(LIMITS.get(_command.get("action", ""), 55)) * 1000.0)
	var t1 := Time.get_ticks_msec()
	while not job.done and Time.get_ticks_msec() - t1 < limit_ms:
		await get_tree().process_frame
	if not job.done:
		return {"ok": true, "value": {"what": String(pick.label), "still_doing_it": true}}
	var r: Dictionary = job.r
	return {"ok": bool(r.get("ok", false)), "value": {"what": String(pick.label)}, "reason": String(r.get("detail", "")).left(100)}


func _run_pick(mb, pick: Dictionary, job: Dictionary) -> void:
	mb.current = {"kind": pick.kind, "label": pick.label, "key": pick.key, "stage": "starting", "started": snappedf(Time.get_ticks_msec() / 1000.0, 0.1)}
	job.r = await mb.run_activity(pick)
	mb.current = {}
	mb.hold = false
	activity = "stand_relaxed"
	job.done = true


# ------------------------------------------------------------------ what is true here
func _snapshot() -> Dictionary:
	var area := String(main.streaming.current_id) if main.get("streaming") else ""
	return {"ready": true, "activity": activity, "camera": "ROOM_FALLBACK", "location": area, "held_object": null, "placement": null, "last_error": null}


func _report(_force := false) -> void:
	if not connected:
		return
	var c: WorldCharacter = main.characters.get("mika")
	var area := String(main.streaming.current_id) if main.get("streaming") else ""
	var caps := {}
	for k in CAPABILITIES:
		caps[k] = {"implemented": true, "available": true, "canPlan": true, "status": "AVAILABLE"}
	var nearby := []
	var objects := []
	if main.get("world") and c:
		for id in main.world.interactables:
			var it: Interactable = main.world.interactables[id]
			var d := c.global_position.distance_to(it.global_position)
			objects.append({"name": String(it.label), "id": String(id)})
			if d < 25.0:
				nearby.append({"id": String(id), "label": String(it.label), "distance_m": snappedf(d, 0.1)})
	var b = main.mage_brains.get("mika")
	var cur: Dictionary = b.current if b and b.get("current") is Dictionary else {}
	var ws_state := {"scene": area, "sceneName": String(WorldState.areas.get(area, {}).get("region", area)).replace("_", " "),
		"currentActivity": String(cur.get("label", activity)), "capabilities": caps, "availableActions": CAPABILITIES, "objects": objects.slice(0, 40),
		"spatial": {"zone": area, "region": String(WorldState.areas.get(area, {}).get("region", "")), "nearby": nearby.slice(0, 10),
			"landmarks": main.world.points_of_interest.keys().slice(0, 20).map(func(k): return {"id": String(k), "label": String(main.world.points_of_interest[k].get("description", k)).left(60), "zone": area}) if main.get("world") else []},
		"dance": {"busy": main.performance.busy() if main.performance else false, "qualityReady": true, "game": {"active": main.performance.busy() if main.performance else false}},
		"world": "a fantasy mage world (Godot): Mika and Luna, Level %d and %d" % [WorldState.mind("mika").level(), WorldState.mind("luna").level() if WorldState.minds.has("luna") else 1],
		"clock": WorldState.clock_text()}
	# which characters are drawn here (the server's "Stage is loaded" check before it goes live)
	_send({"type": "vr-room-client-status", "loaded": main.characters.keys().filter(func(k): return (main.characters[k] as Node3D).visible), "failed": []})
	var payload := _snapshot()
	payload["type"] = "lifestyle-client-state"
	payload["supported_actions"] = CAPABILITIES
	payload["worldState"] = ws_state
	_send(payload)
