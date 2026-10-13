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

signal line_started(speaker: String, text: String)
signal line_finished(speaker: String, result: Dictionary)

const PORT := 12471
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
	if enabled:
		_start_service()


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
	var v: Dictionary = VOICES.get(speaker, VOICES.mika)
	var body := {"text": text, "voice": v.voice, "lang": "en-us", "speed": v.speed, "gain": v.gain}
	var ipa: String = pronunciations.get(_key(text), "")
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


## Speak a line (awaitable). opts: {"priority": int, "subtitle": bool (true), "latin": bool}
func say(speaker: String, text: String, opts := {}) -> Dictionary:
	text = clean(text)
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
		"recent": log.slice(maxi(0, log.size() - 5))}
