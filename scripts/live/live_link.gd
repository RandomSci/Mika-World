class_name LiveLink
extends Node
## The Godot world as Mika-Live's Stage (--live-link[=ws://127.0.0.1:12393/client-ws]). It speaks the same room
## protocol Mika-Live's lifestyle runner speaks to its Stage (lifestyle actions, speech, state reports), so the server's brain - YouTube chat, the conversational LLM, Kokoro speech, viewer intents, the
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
var _h_t := 0.0
var _h_frames := 0
var _h_worst := 0.0
var _h_hitches := 0
var _h_pipes := 0
var _h_cam := Vector3.ZERO      # the camera last frame (a hitch line says how far it jumped)


func _pipelines() -> int:
	return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE) + Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))
var _progress := {}
var _progress_at := -100000
var _command := {}               # the running lifestyle action {id, action}
var _results := {}               # id -> result (a repeated id is answered again, never re-run)
var activity := "stand_relaxed"
var log: Array = []


func setup(m: Node) -> void:
	main = m
	# the hitch lines carry the frame's GPU time (duel stutter, broadcast 2: what the frame was rendering)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var u := String(RenderProfile.options.get("live-link", ""))
	if u != "" and u != "true":
		url = u
	ws.inbound_buffer_size = 16 * 1024 * 1024      # a long line of speech arrives as one message
	ws.outbound_buffer_size = 1024 * 1024
	# a fixed window name: OBS captures this window by name and class (the project name may change)
	get_window().title = "Mika World Stage"
	print("[livelink] Stage for Mika-Live at %s" % url)


## Once a minute in the stage log: the real frame rate, the worst frame, hitches over 50 ms and both mages' levels
## (the soak and the operator read it; nothing of it reaches viewers).
## Every 10 minutes in the stage log (2026-10-20 go live: a 10 minute soak grew 11%, is it a leak?): static, video
## and resident memory, nodes and objects, each against the first reading.
var _m_t := 0.0
var _m_n := 0
var _m0 := {}


func _memory_log(delta: float) -> void:
	_m_t += delta
	if _m_t < 600.0 and _m_n > 0:
		return
	_m_t = 0.0
	var rss := 0.0
	var pf := FileAccess.open("/proc/self/status", FileAccess.READ)      # (line by line: /proc files report size 0)
	while pf and not pf.eof_reached():
		var ln := pf.get_line()
		if ln.begins_with("VmRSS:"):
			rss = float(ln.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
			break
	var now := {"static": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, "rss": rss,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT)}
	if _m0.is_empty():
		_m0 = now
	var pct := func(k: String) -> float: return (float(now[k]) - float(_m0[k])) / maxf(float(_m0[k]), 1.0) * 100.0
	print("[memory] %d min: static %.0f MB (%+.1f%%) video %.0f MB (%+.1f%%) rss %.0f MB (%+.1f%%) nodes %d (%+.1f%%) objects %d (%+.1f%%) area %s" % [
		_m_n * 10, now["static"], pct.call("static"), now["video"], pct.call("video"), now["rss"], pct.call("rss"), int(now["nodes"]), pct.call("nodes"),
		int(now["objects"]), pct.call("objects"), String(main.streaming.current_id) if main.get("streaming") else "-"])
	_m_n += 1


func _health(delta: float) -> void:
	_memory_log(delta)
	_h_t += delta
	_h_frames += 1
	_h_worst = maxf(_h_worst, delta)
	var pc := _pipelines()
	var cam := get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam else Vector3.ZERO
	if delta > 0.05:
		_h_hitches += 1
		# what that frame did (operator log only): new GPU pipelines compiled, a voice line, a talk, each mage's activity
		var dlg = main.mage_talk.dialogue if main.get("mage_talk") and main.mage_talk.get("dialogue") else null
		print("[hitch] %d ms t=%.1f pipelines+%d talk=%s %s" % [int(delta * 1000.0), Time.get_ticks_msec() / 1000.0, pc - _h_pipes,
			str(dlg != null and dlg.active), " ".join(main.mage_brains.keys().map(func(w): return "%s:%s" % [w, String(main.mage_brains[w].current.get("key", main.mage_brains[w].current.get("kind", "-")))]))])
		var vp := get_viewport().get_viewport_rid()
		print("[hitch]   gpu=%.0f ms render_cpu=%.1f ms proc=%.0f phys=%.0f draws=%d prims=%dk objects=%d cam=%s jump=%.1f m" % [
			RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), String(main.director.mode) if main.get("director") else "-", cp.distance_to(_h_cam)])
	_h_pipes = pc
	_h_cam = cp
	if _h_t < 60.0:
		return
	print("[health] fps=%.1f worst_ms=%.1f hitches=%d mika_level=%d luna_level=%d mika_visible=%s luna_visible=%s connected=%s" % [
		_h_frames / _h_t, _h_worst * 1000.0, _h_hitches, WorldState.mind("mika").level(),
		WorldState.mind("luna").level() if WorldState.minds.has("luna") else 0,
		main.characters.has("mika") and (main.characters["mika"] as Node3D).visible,
		main.characters.has("luna") and (main.characters["luna"] as Node3D).visible, connected])
	_h_t = 0.0
	_h_frames = 0
	_h_worst = 0.0
	_h_hitches = 0


func _process(delta: float) -> void:
	_health(delta)
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
			if not _speaking and _speech.is_empty() and main.voice:
				main.voice.hold_world(0)
		"control":
			match String(m.get("text", "")):
				"interrupt":
					_speech.clear()
					if main.voice:
						main.voice.stop()
						main.voice.hold_world(0)
				"conversation-chain-start":
					_synth_complete = false
		"youtube-live-selected-message":
			if bool(m.get("active", false)):
				_viewer_turn_until = Time.get_ticks_msec() + 30000   # the next lines answer a viewer
			_chat_card(m)
			if bool(m.get("active", false)) and main.get("chat") and main.chat.addressee(String(m.get("message", ""))) == "luna":
				_luna_answers(m)
			if bool(m.get("active", false)):
				_lantern_from_chat(m)
		"youtube-live-subscriber", "youtube-live-member", "youtube-live-superchat", "viewer-lantern":
			_lantern_event(m)
		"lifestyle-action":
			_action(m)
		"lifestyle-cancel":
			if String(_command.get("id", "")) == String(m.get("id", "")) and main.performance:
				main.performance.interrupt("the show asked to stop")
		"lifestyle-viewer-noticed":
			_glance("mika")
		_:
			pass


# ------------------------------------------------------------------ viewers' lanterns (Lantern Lake)
## A new subscriber, member or Super Chat - or a chat wish ("I wish ..." / "!wish ...") - becomes a lantern with the
## viewer's name at Lantern Lake (LakeRitual: queued, one at a time; they look up at it and thank the viewer by name).
## Server messages: {"type": "youtube-live-subscriber" | "youtube-live-member" | "youtube-live-superchat", "author",
## "amount"?} or {"type": "viewer-lantern", "author", "kind": subscriber|member|superchat|chat, "wish"?: bool}.
## A selected chat message with "paid": true is a Super Chat lantern as well (the same one is never sent up twice).
func _lantern_event(m: Dictionary) -> void:
	if LakeRitual.instance == null:
		return
	var kinds := {"youtube-live-subscriber": "subscriber", "youtube-live-member": "member", "youtube-live-superchat": "superchat"}
	var kind := String(kinds.get(String(m.get("type", "")), String(m.get("kind", "chat"))))
	LakeRitual.instance.offer(String(m.get("author", "")), kind, bool(m.get("wish", kind == "chat")))


func _lantern_from_chat(m: Dictionary) -> void:
	if LakeRitual.instance == null:
		return
	if bool(m.get("paid", false)):
		LakeRitual.instance.offer(String(m.get("author", "")), "superchat")
	elif LakeRitual.is_wish(String(m.get("message", ""))):
		LakeRitual.instance.offer(String(m.get("author", "")), "chat", true)


# ------------------------------------------------------------------ Mika passes chat on to Luna
## Luna cannot see chat (only Mika reads it). A message that names only Luna: Mika's own reply from the server
## comes first (the viewer knows at once they were heard); then, at a safe moment, Mika calls Luna over (or turns
## to her when she is near), passes the question on in her own words, and Luna answers HER - the viewer hears the
## answer through their conversation. Given up after 60 s (busy, fighting, performing); never forced on a Luna who
## is casting or resting on a seat.
var _luna_busy := false
const RELAY_NEAR_M := 3.0


func _luna_answers(m: Dictionary) -> void:
	if _luna_busy or not main.characters.has("luna") or not (main.characters["luna"] as Node3D).visible or not main.characters.has("mika"):
		return
	_luna_busy = true
	var mika: WorldCharacter = main.characters["mika"]
	var luna: WorldCharacter = main.characters["luna"]
	var lb = main.mage_brains.get("luna")
	var mb = main.mage_brains.get("mika")
	var author := String(m.get("author", "a friend"))
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(2.0).timeout          # Mika's reply (from the server) starts first
	while Time.get_ticks_msec() - t0 < 60000 and (not main.chat._safe_point("mika") or _speaking or not _speech.is_empty()
			or luna.casting or (lb and String(lb.current.get("kind", "")) not in MageTalk.INTERRUPTIBLE + ["together"]) or (lb and lb.current.get("kind", "") == "rest" and luna.seated)):
		await get_tree().create_timer(0.5).timeout
	if Time.get_ticks_msec() - t0 >= 60000 or not luna.visible:
		print("[livelink] relay to luna given up (busy): %s" % String(m.get("message", "")).left(80))
		_luna_busy = false
		return
	# the relay and Luna's answer are written together while she comes over (one call, no wait between them)
	var ctx: Dictionary = main.chat._context("luna")
	var sys := "Two young mages, Mika and Luna, live in a fantasy world that viewers watch on a livestream. Only Mika can read the chat; Luna cannot. A viewer's message was meant for Luna, so Mika passes it on. Write: mika_relay - Mika to Luna, one short natural sentence that names the viewer and puts their question or comment in her own words (never invent details); luna_reply - Luna's answer TO MIKA, one or two short sentences, Luna's voice: proud, confident, a little dry, warm underneath; she may send words back to the viewer through Mika ('tell them...'). Use ONLY the facts provided. No em dashes. JSON {\"mika_relay\": string, \"luna_reply\": string}."
	var fb_relay := "Luna, %s in chat has a question for you." % author
	var fb_reply := "Tell %s I heard them, and I'll give it proper thought." % author
	var box := {}
	var ask := func(): box["r"] = await main.llm.ask_json(sys, JSON.stringify({"viewer": author, "message": String(m.get("message", "")), "luna_facts": ctx}), {"mika_relay": fb_relay, "luna_reply": fb_reply})
	ask.call()
	var holds := []
	for b in [lb, mb]:
		if b:
			b.hold = true
			b.interrupt("social")
			holds.append(b)
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 4000 and lb and not lb.current.is_empty():
		await get_tree().process_frame
	if luna.global_position.distance_to(mika.global_position) > RELAY_NEAR_M:
		await _say_as("mika", "Luna! Come here a second, chat has something for you.")
		if lb:
			await Companionship.approach_for_talk(lb, mika, 1.8)
	var tr := Time.get_ticks_msec()
	while not box.has("r") and Time.get_ticks_msec() - tr < 15000:
		await get_tree().process_frame
	var r: Dictionary = box.get("r", {}) if box.get("r") is Dictionary else {}
	var js: Dictionary = r.get("json", {}) if r.get("json") is Dictionary else {}
	var relay := VoiceService.clean(String(js.get("mika_relay", fb_relay)))
	var reply := VoiceService.clean(String(js.get("luna_reply", fb_reply)))
	if relay.split(" ").size() > 35 or relay.length() < 2:
		relay = fb_relay
	if reply.split(" ").size() > 45 or reply.length() < 2:
		reply = fb_reply
	if luna.global_position.distance_to(mika.global_position) <= RELAY_NEAR_M + 2.0:
		mika.look_at_point(luna.global_position)
		luna.look_at_point(mika.global_position)
		await _say_as("mika", relay)
		await _say_as("luna", reply)
		print("[livelink] mika relayed %s to luna: %s | luna: %s" % [author, relay.left(100), reply.left(120)])
	else:
		print("[livelink] relay to luna: she could not come over")
	for b in holds:
		b.hold = false
	_luna_busy = false


func _say_as(who: String, text: String) -> void:
	await main.voice.say(String(Progression.mages.get(who, {}).get("voice", who)), text)


# ------------------------------------------------------------------ speech
var _viewer_turn_until := 0      # a viewer's message was just selected: its reply plays at once


func _enqueue_audio(m: Dictionary) -> void:
	var who := String(m.get("character")) if m.get("character") is String else "mika"
	if not main.characters.has(who):
		return                                   # a voice for someone not in this world (as the world page did)
	var b64 := String(m.get("audio", "")) if m.get("audio") is String else ""
	var text := ""
	if m.get("display_text") is Dictionary:
		text = String((m.display_text as Dictionary).get("text", ""))
	if main.voice and b64 != "" and not bool(m.get("monitor", false)):
		main.voice.hold_world(15000)          # her in-world chatter pauses while the show speaks (refreshed per chunk)
	_speech.append({"who": who, "wav": Marshalls.base64_to_raw(b64) if b64 != "" else PackedByteArray(), "text": text,
		"trace": m.get("speech_trace") if m.get("speech_trace") is Dictionary else {}, "monitor": bool(m.get("monitor", false)), "received": int(Time.get_unix_time_from_system() * 1000.0)})


func _play_next() -> void:
	_speaking = true
	# Mika and Luna are talking to each other: the show's own line waits for a pause in their exchange (at most
	# 6 s: the server gives a line up after ~20 s), a REPLY TO A VIEWER never waits - their next line holds instead
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() > _viewer_turn_until and main.get("mage_talk") and main.mage_talk.dialogue and main.mage_talk.dialogue.active \
			and main.voice and main.voice._busy and Time.get_ticks_msec() - tw < 6000:
		await get_tree().process_frame
	var item: Dictionary = _speech.pop_front()
	var tr: Dictionary = item.trace
	if not item.monitor:
		_send({"type": "audio-play-start", "display_text": {"text": item.text} if item.text != "" else null, "forwarded": true,
			"trace_id": tr.get("trace_id"), "sequence": tr.get("sequence"), "received_at_ms": item.received, "at_ms": int(Time.get_unix_time_from_system() * 1000.0)})
	var opts := {"wav": item.wav, "priority": 1}
	var waited := int(Time.get_unix_time_from_system() * 1000.0) - int(item.received)
	print("[livelink] show line %s after %d ms%s: %s" % [item.who, waited, " (viewer reply)" if Time.get_ticks_msec() < _viewer_turn_until else "", String(item.text).left(80)])
	await main.voice.say(String(item.who), String(item.text), opts)
	if not item.monitor and not tr.is_empty():
		_send({"type": "audio-play-end", "sequence": tr.get("sequence"), "trace_id": tr.get("trace_id"), "at_ms": int(Time.get_unix_time_from_system() * 1000.0)})
	_speaking = false
	_maybe_playback_complete()


func _maybe_playback_complete() -> void:
	if _synth_complete and not _speaking and _speech.is_empty():
		_synth_complete = false
		_viewer_turn_until = 0
		if main.voice:
			main.voice.hold_world(0)
		_send({"type": "frontend-playback-complete"})


## The viewer comment she is answering, as a card on screen (the comment card): @author, the message,
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
		"dance_session_start":
			return {"ok": true}           # one performance here holds the whole session (the server's next call starts it)
		"dance", "dance_routine", "repeat_dance", "dance_session":
			if main.performance == null:
				return {"ok": false, "reason": "no_dance_system"}
			var routine := String(args.get("routine", ""))
			var clip := String(ROUTINES.get(routine, ""))
			# she finishes (or drops) what she is doing first: her own planner is held while the show's dance runs
			var mb = main.mage_brains.get("mika")
			if mb:
				mb.hold = true
				mb.interrupt("the show asked for a dance")
			# an activity of Luna's that holds Mika (the pier at the lake, both sitting) ends too, or Mika sat on through
			# the show's dance and it was refused (20 October soak)
			# the others are held too until the dance has started (Luna, let go, sat down on the pier in the seconds
			# before it, and Mika danced alone beside her) - the dance holds its partner itself from then on
			var others_held := []
			for w in main.mage_brains:
				if w != "mika":
					if not main.mage_brains[w].hold:
						main.mage_brains[w].hold = true
						others_held.append(w)
					if not (main.mage_brains[w].current as Dictionary).is_empty():
						main.mage_brains[w].interrupt("the show asked for a dance")
			var release_others := func():
				for w in others_held:
					if main.mage_brains.has(w):
						main.mage_brains[w].hold = false
			var w0 := Time.get_ticks_msec()
			var mc: WorldCharacter = main.characters.get("mika")
			while mb and (not mb.current.is_empty() or (mc and mc.ground_pose != "")) and Time.get_ticks_msec() - w0 < 25000:
				mb.hold = true                        # (the other's activity releases her when it ends: kept held for the show)
				await get_tree().process_frame
			activity = "dance"
			# a dance already running (Luna celebrating on her own) gives way to the show's: before this the wait below
			# took HER dance for Mika's, Mika stood still to Luna's song, then danced when the song came round again
			if main.performance.busy() and String(main.performance.active.get("who", "")) != "mika":
				main.performance.interrupt("the show asked Mika to dance")
				var wi := Time.get_ticks_msec()
				while main.performance.busy() and Time.get_ticks_msec() - wi < 8000:
					await get_tree().process_frame
			var req := {"dance": clip, "partner_if_near": true, "why": "the show"}
			main.performance.request("mika", req)
			var t0 := Time.get_ticks_msec()
			while not (main.performance.busy() and String(main.performance.active.get("who", "")) == "mika") and Time.get_ticks_msec() - t0 < 45000:
				await get_tree().process_frame
			release_others.call()
			if not (main.performance.busy() and String(main.performance.active.get("who", "")) == "mika"):
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
	_leave_shared_walks()
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


## Mika leaves any walk she is on as Luna's companion before the show's activity starts: the follower kept steering
## her toward Luna every frame while the show walked her to its spot (2026-10-21 stream: back and forth 24 times).
func _leave_shared_walks() -> void:
	var mc: WorldCharacter = main.characters.get("mika")
	if mc == null or main.get("companionship") == null:
		return
	var led := false
	for n in main.companionship.get_children():
		if n is FollowCompanion and (n as FollowCompanion).follower == mc and not (n as FollowCompanion).released:
			(n as FollowCompanion).released = true
			led = true
	if led:
		mc.set_move_input(Vector3.ZERO, false)
		for w in main.mage_brains:
			if w != "mika" and String((main.mage_brains[w].current as Dictionary).get("kind", "")) == "together":
				main.mage_brains[w].interrupt("the show")


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


## Level, title, rank and the spells each mage can cast now: the one truth about her magic for every spoken
## line (Mika-Live's own lesson ladder is not used with this world). Refreshed every ~25 s.
func _mage_progress() -> Dictionary:
	if Time.get_ticks_msec() - _progress_at < 25000 and not _progress.is_empty():
		return _progress
	_progress_at = Time.get_ticks_msec()
	_progress = {}
	for who in WorldState.minds.keys():
		var d := Progression.describe(who)
		var spells: Array = []
		var learning: Array = []
		if main.get("magic"):
			for sp in main.magic.known_spells(who):
				if sp.castable:
					spells.append("%s (%s)" % [sp.name, sp.tier])
				elif learning.size() < 3:
					learning.append(sp.name)
		# Day 2: the level and the percent were in every line's facts, and she said them in nearly every line. Now the
		# level is a fact she keeps (title, rank) but only HIGHLIGHTED for a while after it changes or when the next one
		# is very close; otherwise the note says not to bring it up unprompted.
		var m := WorldState.mind(who)
		var lu := float(m.progress.get("leveled_unix", 0.0))
		var fresh := Time.get_unix_time_from_system() - lu < 600.0
		var e := {"title": d.title, "rank": WorldState.mage_rank(who), "canCast": spells, "notYet": learning}
		if fresh:
			e["level"] = d.level
			e["levelNews"] = "just reached Level %d - worth celebrating once" % d.level
		elif d.fraction >= 0.9:
			e["level"] = d.level
			e["levelNote"] = "very close to the next level (mention at most once)"
		else:
			e["levelNote"] = "Level %d; do not bring up the level or progress percentages unless a viewer asks" % d.level
		if who == "mika":
			e["somethingFreshToTalkAbout"] = _rotating_topic()
		_progress[who] = e
	return _progress


## Show-commentary topics that rotate (Day 2: "talk topics rotate"): each pick is a true, current fact from the world,
## never the same kind twice in a row and none of the last few again; the choice changes every ~2 minutes.
var _topic := ""
var _topic_at := -1000000
var _topic_kinds: Array = []


func _rotating_topic() -> String:
	if Time.get_ticks_msec() - _topic_at < 120000 and _topic != "":
		return _topic
	var mika := WorldState.mind("mika")
	var cands := []        # [kind, text]
	if main.get("story"):
		var obj := String(main.story.objective())
		if obj != "":
			cands.append(["story", "the mystery of the Heartstone - " + obj])
	var j: Array = mika.knowledge.get("journal", [])
	if not j.is_empty():
		cands.append(["journal", "what she wrote in her journal last: \"%s\"" % String(j.back().get("heading", ""))])
	var read: Array = []
	for k in mika.knowledge.keys():
		if String(k).begins_with("lore:") or String(k).begins_with("clue:"):
			read.append(String(k).get_slice(":", 1).replace("_", " "))
	if not read.is_empty():
		cands.append(["lore", "something she learned from her reading: %s" % read[randi() % read.size()]])
	var b = main.mage_brains.get("luna") if main.get("mage_brains") else null
	if b and b.get("current") is Dictionary and not (b.current as Dictionary).is_empty():
		cands.append(["luna", "what Luna is up to right now: %s" % String(b.current.get("label", ""))])
	if main.get("weather"):
		cands.append(["sky", "the sky and the weather: %s, %s" % [main.weather.kind(), WorldState.time_phrase()]])
	var area := String(main.streaming.current_id) if main.get("streaming") else ""
	if area != "":
		var locs: Array = WorldState.locations_in_area(area)
		var pname := String(WorldState.locations[locs[0]].get("name", area)) if not locs.is_empty() else area.replace("_", " ")
		cands.append(["place", "this place, the %s, and what she likes about it" % pname])
	var learning: Array = []
	if main.get("magic"):
		for sp in main.magic.known_spells("mika"):
			if not sp.castable:
				learning.append(sp.name)
	if not learning.is_empty():
		cands.append(["spell", "a spell she is still trying to learn: %s" % learning[randi() % learning.size()]])
	if mika.knowledge.keys().any(func(k): return String(k).begins_with("visited_unix:")):
		cands.append(["outing", "a walk they took lately around the home region (the library, the woods, the tower)"])
	cands.shuffle()
	cands.sort_custom(func(a, c): return _topic_kinds.find(a[0]) < _topic_kinds.find(c[0]))     # least recently used first
	var pick: Array = cands[0] if not cands.is_empty() else ["none", ""]
	_topic_kinds.erase(pick[0])
	_topic_kinds.append(pick[0])
	_topic = String(pick[1])
	_topic_at = Time.get_ticks_msec()
	return _topic


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
		"dance": {"busy": main.performance.busy() if main.performance else false, "qualityReady": true, "game": {"active": main.performance.busy() if main.performance else false, "enabledRoutines": ROUTINES.keys()}},
		"world": "a fantasy mage world (Godot): Mika and Luna, Level %d and %d" % [WorldState.mind("mika").level(), WorldState.mind("luna").level() if WorldState.minds.has("luna") else 1],
		"clock": WorldState.time_phrase(), "nightTime": WorldState.daylight() < 0.2, "mageProgress": _mage_progress(),
		"weather": ({"sky": main.weather.kind(), "raining": main.weather.raining(), "underCover": main.weather.sheltered_area()} if main.get("weather") else {})}
	# which characters are drawn here (the server's "Stage is loaded" check before it goes live)
	_send({"type": "vr-room-client-status", "loaded": main.characters.keys().filter(func(k): return (main.characters[k] as Node3D).visible), "failed": []})
	var payload := _snapshot()
	payload["type"] = "lifestyle-client-state"
	payload["supported_actions"] = CAPABILITIES
	payload["worldState"] = ws_state
	_send(payload)
