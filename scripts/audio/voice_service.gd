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
## V3 Part X - the Phoenix (Oriel) speaks with Google Gemini TTS voice "Kore" (provider "gemini", confirmed by
## the developer): the key is read from the project .env (GEMINI_API_KEY only; never logged, printed or
## reported), each distinct line is synthesised at most once ever (shipped lines in res://assets/voice/phoenix,
## session lines in user://voice_cache/gemini), requests are asynchronous with a timeout, one retry on a
## transient failure, audio validation (format, length, loudness), quota awareness (a 429 pauses cloud use for
## ten minutes) and a local Kokoro fallback blend that is neither Mika's nor Luna's. Her true form speaks
## through the "VoicePhoenix" bus (a subtle resonance), her humanoid form through "Voice".

signal line_started(speaker: String, text: String)
signal line_finished(speaker: String, result: Dictionary)

const PORT := 12471
const EDGE_PORT := 12472
const GEMINI_URL := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
const GEMINI_CACHE := "user://voice_cache/gemini"
const GEMINI_SHIPPED := "res://assets/voice/phoenix"
const GEMINI_TIMEOUT := 28.0
const GEMINI_QUOTA_PAUSE_S := 600.0
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
var _gemini_key := ""          # never leaves this process; never logged
var gemini_status := "not configured"
var gemini_stats := {"calls": 0, "cache_hits": 0, "shipped_hits": 0, "failures": 0, "retries": 0, "rejected": 0}
var _gemini_blocked_until := 0.0


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
	_load_gemini_key()
	if enabled:
		_start_service()
		if _uses_edge():
			_start_edge()


## GEMINI_API_KEY from the process environment or the project .env (that one line only; every other line of
## the file is skipped and never held). The value is kept private to this node.
func _load_gemini_key() -> void:
	_gemini_key = OS.get_environment("GEMINI_API_KEY")
	if _gemini_key == "":
		_gemini_key = String(LLMClient._read_env_file(ProjectSettings.globalize_path("res://.env"), ["GEMINI_API_KEY"]).get("GEMINI_API_KEY", ""))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEMINI_CACHE))
	if _gemini_key == "":
		gemini_status = "unavailable: GEMINI_API_KEY not configured (shipped lines + Kokoro fallback only)"
	else:
		gemini_status = "configured (key present, %d chars)" % _gemini_key.length()


func gemini_configured() -> bool:
	return _gemini_key != ""


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


## A speaker can be voiced when its own provider is usable (the cloud voices do not need the Kokoro service).
func _can_synthesize(speaker: String) -> bool:
	if available:
		return true
	var provider := String(_speaker_cfg(speaker).get("provider", ""))
	return (provider == "gemini" and _gemini_key != "") or (provider == "edge" and edge_available)


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
func prefetch(speaker: String, text: String, opts := {}) -> void:
	text = clean(text)
	var key := _cache_key(speaker, text, opts)
	if not enabled or not _can_synthesize(speaker) or _cache.has(key):
		return
	_cache[key] = "pending"
	var wav: PackedByteArray = await _synthesize(speaker, text, {}, opts)
	_cache[key] = wav


static func _cache_key(speaker: String, text: String, opts: Dictionary) -> String:
	return "%s|%s|%s|%s" % [speaker, text, String(opts.get("form", "")), String(opts.get("mood", ""))]


func _synthesize(speaker: String, text: String, res: Dictionary, opts := {}) -> PackedByteArray:
	var ipa: String = pronunciations.get(_key(text), "")
	var cfg := _speaker_cfg(speaker)
	var provider := String(cfg.get("provider", ""))
	# the Phoenix: her confirmed cloud voice (Kore), cached forever per line; Kokoro only when it is unavailable
	if provider == "gemini":
		var wav_g: PackedByteArray = await _synthesize_gemini(cfg, text, res, opts)
		if wav_g.size() > 44:
			res["provider"] = "gemini"
			res["voice"] = String(cfg.voice)
			return wav_g
		res["gemini_error"] = res.get("error", "gemini failed")
		res.erase("error")
	# the confirmed character voice (Edge) unless this is an IPA line; Kokoro is the per-line fallback
	if provider == "edge" and ipa == "" and edge_available:
		var wav_e: PackedByteArray = await _synthesize_edge(cfg, text, res)
		if wav_e.size() > 44:
			res["provider"] = "edge"
			res["voice"] = String(cfg.voice)
			return wav_e
		res["edge_error"] = res.get("error", "edge failed")
		res.erase("error")
	var v: Dictionary = VOICES.get(speaker, VOICES.mika)
	var fb: Dictionary = cfg.get("fallback", {}) if provider in ["edge", "gemini"] else cfg
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


## ---- Google Gemini TTS (the Phoenix) ----------------------------------------------------------------
static func _gemini_key_for(cfg: Dictionary, text: String, style: String) -> String:
	return ("%s|%s|%s|%s" % [String(cfg.get("model", "")), String(cfg.get("voice", "")), style, text]).sha1_text()


func _gemini_style(cfg: Dictionary, opts: Dictionary) -> String:
	var styles: Dictionary = cfg.get("styles", {})
	var form := String(opts.get("form", "humanoid"))
	var mood := String(opts.get("mood", ""))
	var s := String(styles.get(form, styles.get("humanoid", "")))
	if mood != "" and styles.has("moods") and (styles.moods as Dictionary).has(mood):
		s += " " + String(styles.moods[mood])
	return s


## A line in her Kore voice. Order: shipped file -> session cache -> one cloud request (+ one retry on a
## transient failure). Never more than one cloud call per distinct line; a 429 pauses cloud use.
func _synthesize_gemini(cfg: Dictionary, text: String, res: Dictionary, opts: Dictionary) -> PackedByteArray:
	var style := _gemini_style(cfg, opts)
	var key := _gemini_key_for(cfg, text, style)
	for dir_path in [GEMINI_SHIPPED, GEMINI_CACHE]:
		var path := "%s/%s.wav" % [dir_path, key]
		if FileAccess.file_exists(path):
			var cached := FileAccess.get_file_as_bytes(path)
			if cached.size() > 44:
				if dir_path == GEMINI_SHIPPED:
					gemini_stats.shipped_hits += 1
				else:
					gemini_stats.cache_hits += 1
				res["cached"] = "shipped" if dir_path == GEMINI_SHIPPED else "session"
				return cached
	if _gemini_key == "":
		res["error"] = "gemini unavailable: no key"
		return PackedByteArray()
	var now := Time.get_unix_time_from_system()
	if now < _gemini_blocked_until:
		res["error"] = "gemini paused after a quota answer (%d s left)" % int(_gemini_blocked_until - now)
		return PackedByteArray()
	var prompt := text if style == "" else "%s\n\n%s" % [style, text]
	var body := {"contents": [{"parts": [{"text": prompt}]}],
		"generationConfig": {"responseModalities": ["AUDIO"],
			"speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": String(cfg.get("voice", "Kore"))}}}}}
	var url := GEMINI_URL % String(cfg.get("model", "gemini-2.5-flash-preview-tts"))
	var wav := PackedByteArray()
	for attempt in 2:
		if attempt == 1:
			gemini_stats.retries += 1
			await get_tree().create_timer(0.8).timeout
		gemini_stats.calls += 1
		var started := Time.get_ticks_msec()
		var http := HTTPRequest.new()
		http.timeout = GEMINI_TIMEOUT
		add_child(http)
		var err := http.request(url, ["Content-Type: application/json", "x-goog-api-key: " + _gemini_key], HTTPClient.METHOD_POST, JSON.stringify(body))
		if err != OK:
			http.queue_free()
			res["error"] = "gemini request could not start (%d)" % err
			gemini_stats.failures += 1
			continue
		var r: Array = await http.request_completed
		http.queue_free()
		var code := int(r[1])
		res["gemini_ms"] = Time.get_ticks_msec() - started
		if r[0] != HTTPRequest.RESULT_SUCCESS:
			res["error"] = "gemini transport failure (result %d%s)" % [r[0], ", timeout" if r[0] == HTTPRequest.RESULT_TIMEOUT else ""]
			gemini_stats.failures += 1
			continue
		if code == 429:
			_gemini_blocked_until = Time.get_unix_time_from_system() + GEMINI_QUOTA_PAUSE_S
			res["error"] = "gemini quota exhausted (429): cloud synthesis paused for %d s" % int(GEMINI_QUOTA_PAUSE_S)
			gemini_stats.failures += 1
			break
		if code >= 500:
			res["error"] = "gemini server error (http %d)" % code
			gemini_stats.failures += 1
			continue
		if code != 200:
			res["error"] = "gemini refused (http %d)" % code
			gemini_stats.failures += 1
			break
		wav = _gemini_wav_from_response(r[3], float(cfg.get("gain", 0.9)), res)
		if wav.size() > 44:
			break
		gemini_stats.rejected += 1
	if wav.size() > 44:
		var f := FileAccess.open("%s/%s.wav" % [GEMINI_CACHE, key], FileAccess.WRITE)
		if f:
			f.store_buffer(wav)
			f.close()
		res["cached"] = "new"
	return wav


## The response carries base64 PCM (audio/L16, mono, 24 kHz). Validated: a sane length and not silence.
static func _gemini_wav_from_response(raw: PackedByteArray, gain: float, res: Dictionary) -> PackedByteArray:
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("candidates"):
		res["error"] = "gemini answer had no candidates"
		return PackedByteArray()
	var cands: Array = parsed.candidates
	if cands.is_empty():
		res["error"] = "gemini answer was empty"
		return PackedByteArray()
	var parts: Array = (cands[0] as Dictionary).get("content", {}).get("parts", [])
	var inline := {}
	for p in parts:
		if (p as Dictionary).has("inlineData"):
			inline = p.inlineData
			break
	if inline.is_empty():
		res["error"] = "gemini answer carried no audio"
		return PackedByteArray()
	var mime := String(inline.get("mimeType", ""))
	var rate := 24000
	if mime.contains("rate="):
		rate = int(mime.get_slice("rate=", 1).get_slice(";", 0))
	if not (mime.begins_with("audio/L16") or mime.contains("pcm")):
		res["error"] = "gemini audio in an unexpected format: " + mime
		return PackedByteArray()
	var pcm := Marshalls.base64_to_raw(String(inline.get("data", "")))
	var n := pcm.size() / 2
	if n < rate * 0.15:
		res["error"] = "gemini audio too short (%.2f s)" % (float(n) / rate)
		return PackedByteArray()
	if n > rate * 60:
		res["error"] = "gemini audio implausibly long (%.1f s)" % (float(n) / rate)
		return PackedByteArray()
	var acc := 0.0
	var cnt := 0
	var g := clampf(gain, 0.1, 1.5)
	for i in range(0, n, 1):
		var v := float(pcm.decode_s16(i * 2)) / 32768.0
		if i % 7 == 0:
			acc += v * v
			cnt += 1
		if g != 1.0:
			pcm.encode_s16(i * 2, int(clampf(v * g, -1.0, 1.0) * 32767.0))
	var rms := sqrt(acc / maxf(cnt, 1))
	if rms < 0.0025:
		res["error"] = "gemini audio was silence (rms %.4f)" % rms
		return PackedByteArray()
	res["rms"] = snappedf(rms, 0.001)
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.resize(4)
	out.resize(8)
	out.encode_u32(4, 36 + pcm.size())
	out.append_array("WAVE".to_ascii_buffer())
	out.append_array("fmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 1)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * 2)
	fmt.encode_u16(16, 2)
	fmt.encode_u16(18, 16)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	var sz := PackedByteArray()
	sz.resize(4)
	sz.encode_u32(0, pcm.size())
	out.append_array(sz)
	out.append_array(pcm)
	return out


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
	var smiles := kind in ["laugh", "giggle"]
	if who and is_instance_valid(who) and who.has_method("set_expression"):
		if kind in ["gasp", "startle"]:
			who.set_expression("surprised", 0.85)
		elif smiles:
			who.set_expression("happy", 0.85)
	var texts: Dictionary = config.get("reactions", {}).get("clips", {}).get(kind, {})
	var key := speaker + "|" + kind
	var provider := String(cfg.get("provider", ""))
	var can := (provider == "edge" and edge_available) or (provider == "gemini")
	if enabled and can and texts.has(speaker):
		if not _reactions.has(key):
			var r2 := {}
			if provider == "gemini":
				_reactions[key] = await _synthesize_gemini(cfg, String(texts[speaker]), r2, {})
			else:
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
	if smiles and who and is_instance_valid(who) and who.has_method("set_expression"):
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
	if enabled and _can_synthesize(speaker):
		var key := _cache_key(speaker, text, opts)
		if _cache.has(key):
			while typeof(_cache[key]) == TYPE_STRING:   # prefetch still in flight
				await get_tree().process_frame
			wav = _cache[key]
			_cache.erase(key)
			res["prefetched"] = true
			if pronunciations.has(_key(text)):
				res["phonemes"] = true
		if wav.is_empty():
			wav = await _synthesize(speaker, text, res, opts)
	res["tts_ms"] = Time.get_ticks_msec() - started
	var subtitle: bool = opts.get("subtitle", true)
	if wav.size() > 44:
		var stream := AudioStreamWAV.load_from_buffer(wav)
		var env := _envelope(wav)
		_player.stream = stream
		var bus := String(opts.get("bus", "Voice"))
		_player.bus = bus if AudioServer.get_bus_index(bus) != -1 else "Voice"
		_player.play()
		res["audio"] = true
		res["fallback"] = false
		res["seconds"] = snappedf(stream.get_length(), 0.01)
		res["bus"] = _player.bus
		line_started.emit(speaker, text)
		if subtitle and main:
			main.show_subtitle(_caption(speaker, text), stream.get_length() + 0.4)
		var who = _speakers.get(speaker)
		while _player.playing:
			await get_tree().process_frame
			# the mouth follows the audio's own clock (a Movie Maker recording runs slower than real time)
			var idx := int(_player.get_playback_position() * 30.0)
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
	var names := {"mika": "Mika", "luna": "Luna", "phoenix": "Oriel", "wandering_mage": "Ysolde", "travelling_scholar": "Elowen", "wandering_merchant": "Tobias"}
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
		"gemini": {"configured": _gemini_key != "", "status": gemini_status, "stats": gemini_stats,
			"paused_s": maxi(0, int(_gemini_blocked_until - Time.get_unix_time_from_system()))},
		"recent": log.slice(maxi(0, log.size() - 5))}
