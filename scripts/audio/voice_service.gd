class_name VoiceService
extends Node
## DEV-isolated speech for Mika and the travellers.
## * Local Kokoro-82M (the production voice model and Mika's voice blend) through a DEV instance of the
##   speech service on 127.0.0.1:12471 (never the production port 12460). Started on demand with
##   --parent-pid so it exits with the game; nothing in the production project is modified.
## * Non-blocking: synthesis runs in the service process; Godot keeps rendering. One line at a time per
##   queue; lines wait their turn. Speech is played on the "Voice" bus (the world ducks under it).
## * Sync: the subtitle appears on the first audio frame and leaves when the audio ends; a precomputed
##   loudness envelope drives the speaker's mouth (VRM "aa") or an NPC's talking flag.
## * Latin: incantations are spoken from fixed IPA (phoneme mode) so they don't come out as English guesses.
## * Failure: if the service is unavailable or slow, the line is shown as a subtitle for its reading time
##   and the result says "fallback": true. Nothing pretends audio was played.
## Speech vs. thought: callers decide what is spoken; private reasoning is never passed here.
## Milestone J - character voice PROVIDERS (data/voices.json):
##   * Mika and Luna use the voices confirmed in Mika-Voice-Lab: Microsoft Edge neural voices through the
##     DEV service tools/voice/edge_service.py (127.0.0.1:12472, cached on disk). Each line falls back to
##     her Kokoro blend if the Edge service is unreachable or fails, and IPA lines (Latin incantations)
##     always use Kokoro (Edge has no phoneme input) - the result says which provider spoke.
##   * Laughter is never read out as text: laugh tokens ("hehe", "haha", "*giggles*") are removed from the
##     line and a short reaction clip in HER voice plays instead, with a happy expression.

signal line_started(speaker: String, text: String)
signal line_finished(speaker: String, result: Dictionary)

const PORT := 12471
const EDGE_PORT := 12472
const DEFAULT_PYTHON := "/home/selwyn/Documents/Mika-Live/tools/kokoro/.venv/bin/python"
const DEFAULT_MODELS := "/home/selwyn/Documents/Mika-Live/models/kokoro"
const VOICES := {
	"mika": {"voice": "af_bella:0.6,jf_alpha:0.4", "gain": 0.7, "speed": 1.0},
	# Luna: youthful, confident, a little cooler than Mika (Kokoro blend; distinct from every other speaker)
	"luna": {"voice": "af_kore:0.6,af_sky:0.4", "gain": 0.75, "speed": 0.97},
	"wandering_mage": {"voice": "bf_isabella", "gain": 0.8, "speed": 0.95},
	"travelling_scholar": {"voice": "bf_emma", "gain": 0.8, "speed": 0.95},
	"wandering_merchant": {"voice": "bm_george", "gain": 0.8, "speed": 1.05},
}

static var instance: VoiceService

var main: Node
var enabled := true
var available := false
var status := "not started"
var log: Array = []
var pronunciations := {}
var _queue: Array = []
var _busy := false
var _player: AudioStreamPlayer
var _pid := -1
var _speakers := {}            # speaker id -> Node (WorldCharacter or NPC) for mouth movement
var _cache := {}               # speaker|text -> PackedByteArray (wav) or "pending" (prefetch)
var config := {}               # data/voices.json
var edge_available := false
var edge_status := "not started"
var _edge_pid := -1
var _reactions := {}           # speaker|kind -> PackedByteArray (generated once per session, cached by the service)


func setup(m: Node) -> void:
	main = m
	instance = self
	enabled = not RenderProfile.options.has("no-voice")
	AudioBuses.ensure()
	_player = AudioStreamPlayer.new()
	_player.bus = "Voice"
	add_child(_player)
	var f := FileAccess.open("res://data/pronunciations.json", FileAccess.READ)
	if f:
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		for k in d.get("lines", {}):
			pronunciations[_key(k)] = d.lines[k]
	var vf := FileAccess.open("res://data/voices.json", FileAccess.READ)
	if vf:
		config = JSON.parse_string(vf.get_as_text())
	if enabled:
		_start_service()
		if _uses_edge():
			_start_edge()


func register_speaker(id: String, node: Node) -> void:
	_speakers[id] = node


static func _key(t: String) -> String:
	return t.strip_edges().to_lower()


## Removes em/en dashes from anything shown or spoken as dialogue (house style for Mika's lines).
static func clean(t: String) -> String:
	var s := t.replace(" — ", ", ").replace("—", ", ").replace(" – ", ", ").replace("–", "-")
	return s.replace(",,", ",").strip_edges()


func _health() -> bool:
	var http := HTTPRequest.new()
	http.timeout = 1.0
	add_child(http)
	var err := http.request("http://127.0.0.1:%d/health" % PORT)
	if err != OK:
		http.queue_free()
		return false
	var res: Array = await http.request_completed
	http.queue_free()
	return res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200


func _start_service() -> void:
	status = "starting"
	if await _health():
		available = true
		status = "ready (already running on %d)" % PORT
		return
	var py := OS.get_environment("MIKA_DEV_KOKORO_PYTHON") if OS.get_environment("MIKA_DEV_KOKORO_PYTHON") != "" else DEFAULT_PYTHON
	var models := OS.get_environment("MIKA_DEV_KOKORO_MODELS") if OS.get_environment("MIKA_DEV_KOKORO_MODELS") != "" else DEFAULT_MODELS
	var script := ProjectSettings.globalize_path("res://tools/voice/kokoro_service.py")
	if not FileAccess.file_exists(py) or not FileAccess.file_exists(models + "/kokoro-v1.0.onnx"):
		status = "unavailable: Kokoro python/models not found (%s)" % py
		return
	_pid = OS.create_process(py, ["-B", "-I", script, "--port", str(PORT), "--model", models + "/kokoro-v1.0.onnx",
		"--voices", models + "/voices-v1.0.bin", "--voice", VOICES.mika.voice, "--threads", "3", "--parent-pid", str(OS.get_process_id())])
	for i in 60:
		await get_tree().create_timer(0.5).timeout
		if await _health():
			available = true
			status = "ready (DEV service pid %d on %d)" % [_pid, PORT]
			print("[voice] ", status)
			return
	status = "unavailable: DEV speech service did not become ready"
	push_warning("[voice] " + status)


func _speaker_cfg(speaker: String) -> Dictionary:
	return config.get("speakers", {}).get(speaker, {})


func _uses_edge() -> bool:
	for k in config.get("speakers", {}):
		if String(config.speakers[k].get("provider", "")) == "edge":
			return true
	return false


func _edge_health() -> bool:
	var http := HTTPRequest.new()
	http.timeout = 1.0
	add_child(http)
	if http.request("http://127.0.0.1:%d/health" % EDGE_PORT) != OK:
		http.queue_free()
		return false
	var res: Array = await http.request_completed
	http.queue_free()
	return res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200


func _start_edge() -> void:
	edge_status = "starting"
	if await _edge_health():
		edge_available = true
		edge_status = "ready (already running on %d)" % EDGE_PORT
		return
	var py := OS.get_environment("MIKA_DEV_EDGE_PYTHON")
	if py == "":
		py = ProjectSettings.globalize_path("res://.venv-voice/bin/python")
	var script := ProjectSettings.globalize_path("res://tools/voice/edge_service.py")
	if not FileAccess.file_exists(py):
		edge_status = "unavailable: %s missing (python3 -m venv .venv-voice && .venv-voice/bin/pip install edge-tts)" % py
		push_warning("[voice] " + edge_status)
		return
	_edge_pid = OS.create_process(py, ["-B", script, "--port", str(EDGE_PORT), "--parent-pid", str(OS.get_process_id())])
	for i in 30:
		await get_tree().create_timer(0.3).timeout
		if await _edge_health():
			edge_available = true
			edge_status = "ready (DEV edge service pid %d on %d)" % [_edge_pid, EDGE_PORT]
			print("[voice] ", edge_status)
			return
	edge_status = "unavailable: edge service did not become ready"
	push_warning("[voice] " + edge_status)


## Start synthesising a line now so it is ready when it should be spoken (reading, scripted beats).
func prefetch(speaker: String, text: String) -> void:
	text = clean(text)
	var key := speaker + "|" + text
	if not enabled or not available or _cache.has(key):
		return
	_cache[key] = "pending"
	var wav: PackedByteArray = await _synthesize(speaker, text, {})
	_cache[key] = wav


func _synthesize(speaker: String, text: String, res: Dictionary) -> PackedByteArray:
	var ipa: String = pronunciations.get(_key(text), "")
	var cfg := _speaker_cfg(speaker)
	# the confirmed character voice (Edge) unless this is an IPA line; Kokoro is the per-line fallback
	if String(cfg.get("provider", "")) == "edge" and ipa == "" and edge_available:
		var wav_e: PackedByteArray = await _synthesize_edge(cfg, text, res)
		if wav_e.size() > 44:
			res["provider"] = "edge"
			res["voice"] = String(cfg.voice)
			return wav_e
		res["edge_error"] = res.get("error", "edge failed")
		res.erase("error")
	var v: Dictionary = VOICES.get(speaker, VOICES.mika)
	var fb: Dictionary = cfg.get("fallback", {}) if String(cfg.get("provider", "")) == "edge" else cfg
	if String(fb.get("provider", "kokoro")) == "kokoro" and fb.has("voice"):
		v = {"voice": fb.voice, "gain": float(fb.get("gain", 0.75)), "speed": float(fb.get("speed", 1.0))}
	res["provider"] = "kokoro"
	res["voice"] = String(v.voice)
	var body := {"text": text, "voice": v.voice, "lang": "en-us", "speed": v.speed, "gain": v.gain}
	if ipa != "":
		body["phonemes"] = ipa
		res["phonemes"] = true
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request("http://127.0.0.1:%d/synthesize" % PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200:
		return r[3]
	res["error"] = "tts failed (result %d, http %d)" % [r[0], r[1]]
	return PackedByteArray()


func _synthesize_edge(cfg: Dictionary, text: String, res: Dictionary) -> PackedByteArray:
	var body := {"text": text, "voice": cfg.voice, "pitch": cfg.get("pitch", "+0Hz"), "rate": cfg.get("rate", "+0%"), "gain": float(cfg.get("gain", 0.85))}
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request("http://127.0.0.1:%d/synthesize" % EDGE_PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200:
		return r[3]
	res["error"] = "edge tts failed (result %d, http %d)" % [r[0], r[1]]
	return PackedByteArray()


## Laugh tokens at the start / end of a line: removed from the spoken text (returned separately).
func split_laughter(text: String) -> Dictionary:
	var tokens: Array = config.get("reactions", {}).get("tokens", [])
	var lead := false
	var trail := false
	var words := text.strip_edges().split(" ", false)
	var norm := func(w: String) -> String: return w.to_lower().strip_edges().rstrip(".!?,~").lstrip("(")
	while words.size() > 0 and tokens.has(norm.call(words[0])):
		words.remove_at(0)
		lead = true
	while words.size() > 0 and tokens.has(norm.call(words[words.size() - 1])):
		words.remove_at(words.size() - 1)
		trail = true
	var rest := " ".join(words).strip_edges()
	if lead and rest != "":
		rest = rest.left(1).to_upper() + rest.substr(1)
	return {"text": rest, "lead": lead, "trail": trail}


## A short laugh/giggle in the speaker's own voice (no words), with a happy expression and mouth movement.
func react(speaker: String, kind := "laugh") -> Dictionary:
	var res := {"speaker": speaker, "reaction": kind, "audio": false}
	var cfg := _speaker_cfg(speaker)
	var who = _speakers.get(speaker)
	if who and is_instance_valid(who) and who.has_method("set_expression"):
		who.set_expression("happy", 0.8)
	var texts: Dictionary = config.get("reactions", {}).get("clips", {}).get(kind, {})
	var key := speaker + "|" + kind
	if enabled and edge_available and String(cfg.get("provider", "")) == "edge" and texts.has(speaker):
		if not _reactions.has(key):
			var r2 := {}
			_reactions[key] = await _synthesize_edge(cfg, String(texts[speaker]), r2)
		var wav: PackedByteArray = _reactions[key]
		if wav.size() > 44:
			var stream := AudioStreamWAV.load_from_buffer(wav)
			var env := _envelope(wav)
			var p := AudioStreamPlayer.new()
			p.bus = "Voice"
			p.stream = stream
			add_child(p)
			p.play()
			var t0 := Time.get_ticks_msec()
			while p.playing:
				await get_tree().process_frame
				var idx := int((Time.get_ticks_msec() - t0) / 1000.0 * 30.0)
				_mouth(who, (env[idx] if idx < env.size() else 0.0) * 0.7)
			_mouth(who, 0.0)
			p.queue_free()
			res["audio"] = true
			res["seconds"] = snappedf(stream.get_length(), 0.01)
	else:
		await get_tree().create_timer(0.8).timeout
	if who and is_instance_valid(who) and who.has_method("set_expression"):
		who.set_expression("happy", 0.0)
	log.append(res)
	return res


## Speak a line (awaitable). opts: {"priority": int, "subtitle": bool (true), "latin": bool}
func say(speaker: String, text: String, opts := {}) -> Dictionary:
	text = clean(text)
	if not opts.get("latin", false):
		var lf := split_laughter(text)
		if lf.lead or lf.trail:
			if lf.lead:
				await react(speaker, "laugh")
			var r := {}
			if String(lf.text) != "":
				r = await say(speaker, String(lf.text), opts)
			if lf.trail:
				await react(speaker, "giggle")
			r["laughter"] = {"lead": lf.lead, "trail": lf.trail}
			return r
	var job := {"speaker": speaker, "text": text, "opts": opts, "done": false, "result": {}}
	if int(opts.get("priority", 0)) > 0:
		_queue.push_front(job)
	else:
		_queue.append(job)
	if not _busy:
		_pump()
	while not job.done:
		await get_tree().process_frame
	return job.result


func busy() -> bool:
	return _busy or not _queue.is_empty()


func _pump() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		job.result = await _speak(job.speaker, job.text, job.opts)
		job.done = true
	_busy = false


func _speak(speaker: String, text: String, opts: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	var res := {"speaker": speaker, "text": text, "audio": false, "fallback": true}
	var wav := PackedByteArray()
	if enabled and available:
		var key := speaker + "|" + text
		if _cache.has(key):
			while typeof(_cache[key]) == TYPE_STRING:   # prefetch still in flight
				await get_tree().process_frame
			wav = _cache[key]
			_cache.erase(key)
			res["prefetched"] = true
			if pronunciations.has(_key(text)):
				res["phonemes"] = true
		if wav.is_empty():
			wav = await _synthesize(speaker, text, res)
	res["tts_ms"] = Time.get_ticks_msec() - started
	var subtitle: bool = opts.get("subtitle", true)
	if wav.size() > 44:
		var stream := AudioStreamWAV.load_from_buffer(wav)
		var env := _envelope(wav)
		_player.stream = stream
		_player.play()
		res["audio"] = true
		res["fallback"] = false
		res["seconds"] = snappedf(stream.get_length(), 0.01)
		line_started.emit(speaker, text)
		if subtitle and main:
			main.show_subtitle(_caption(speaker, text), stream.get_length() + 0.4)
		var t0 := Time.get_ticks_msec()
		var who = _speakers.get(speaker)
		while _player.playing:
			await get_tree().process_frame
			var idx := int((Time.get_ticks_msec() - t0) / 1000.0 * 30.0)
			var amp: float = env[idx] if idx < env.size() else 0.0
			_mouth(who, amp)
		_mouth(who, 0.0)
	else:
		var secs := clampf(text.split(" ").size() / 2.6, 1.5, 9.0)
		res["seconds"] = snappedf(secs, 0.01)
		line_started.emit(speaker, text)
		if subtitle and main:
			main.show_subtitle(_caption(speaker, text), secs)
		await get_tree().create_timer(secs).timeout
	res["total_ms"] = Time.get_ticks_msec() - started
	log.append(res)
	if log.size() > 50:
		log.pop_front()
	line_finished.emit(speaker, res)
	return res


func _caption(speaker: String, text: String) -> String:
	var names := {"mika": "Mika", "wandering_mage": "Ysolde", "travelling_scholar": "Elowen", "wandering_merchant": "Tobias"}
	return "%s: %s" % [names.get(speaker, speaker.capitalize()), text]


func _mouth(who, amp: float) -> void:
	if who == null or not is_instance_valid(who):
		return
	if who.has_method("set_expression"):
		who.set_expression("aa", clampf(amp * 1.6, 0.0, 0.85))
	elif who.has_method("set_talking"):
		who.set_talking(amp > 0.08)


## Loudness envelope at 30 Hz from 16-bit PCM WAV bytes (normalised 0..1).
static func _envelope(wav: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if wav.size() < 44:
		return out
	var rate := wav.decode_u32(24)
	var data_off := 44
	var i := 12
	while i < wav.size() - 8:
		if wav.slice(i, i + 4).get_string_from_ascii() == "data":
			data_off = i + 8
			break
		i += 8 + wav.decode_u32(i + 4)
	var per := maxi(1, int(rate / 30))
	var n := (wav.size() - data_off) / 2
	var peak := 0.001
	var k := 0
	while k < n:
		var s := 0.0
		var cnt := 0
		for j in range(k, mini(k + per, n), 4):
			var v := float(wav.decode_s16(data_off + j * 2)) / 32768.0
			s += v * v
			cnt += 1
		var rms := sqrt(s / maxi(cnt, 1))
		peak = maxf(peak, rms)
		out.append(rms)
		k += per
	for j in out.size():
		out[j] = out[j] / peak
	return out


func describe() -> Dictionary:
	return {"enabled": enabled, "available": available, "status": status, "port": PORT, "queue": _queue.size(), "busy": _busy,
		"edge": {"available": edge_available, "status": edge_status, "port": EDGE_PORT},
		"recent": log.slice(maxi(0, log.size() - 5))}
