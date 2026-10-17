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
## ONE VOICE PER CHARACTER (2026-10-15, approved by the developer; docs/VOICES.md) - Mika and Luna have a locked
## voice IDENTITY (provider "gemini_identity"): Mika = Gemini "Leda", Luna = Gemini "Achernar", both +15 % pitch with
## formant preservation (ffmpeg rubberband) and the same loudness. Every line, laugh, gasp, cry and Latin incantation
## is rendered with the same model, prebuilt voice, persona and processing; the delivery changes only through a
## small fixed set of moods. Order: shipped clip (res://assets/voice/<speaker>) -> session cache
## (user://voice_cache/<identity>) -> one synthesis in her voice. There is NO cross-voice fallback (no Edge, no
## Kokoro) for them: if her own voice cannot be produced the line is a subtitle only and the result says so.

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
const LIVE_VOICES := {
	"mika": {"provider": "kokoro", "voice": "af_heart:0.6,jf_alpha:0.4", "gain": 0.7, "speed": 1.0, "note": "live: heart + alpha (developer's pick 2026-10-16)"},
	"luna": {"provider": "kokoro", "voice": "af_nicole", "gain": 0.7, "speed": 1.0, "note": "live: nicole (developer's pick 2026-10-16)"},
}
const GPU_PYTHON := "/home/selwyn/.cache/mika_qa/kokoro-gpu/bin/python"   # onnxruntime-gpu venv (optional)
const GEMINI_INTERACTIONS := "https://generativelanguage.googleapis.com/v1beta/interactions"
const IDENTITY_SHIPPED := "res://assets/voice"
const IDENTITY_CACHE := "user://voice_cache"
## Kokoro voices for travellers / NPCs only (Mika and Luna never use Kokoro: they have voice identities).
const VOICES := {
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
var _restarting := false       # a Kokoro restart is in progress (one at a time)
var _speakers := {}            # speaker id -> Node (WorldCharacter or NPC) for mouth movement
var _cache := {}               # speaker|text -> PackedByteArray (wav) or "pending" (prefetch)
var _cache_meta := {}          # speaker|text -> what synthesis reported (provider, identity, mood, cached ...)
var config := {}               # data/voices.json
var edge_available := false
var edge_status := "not started"
var _edge_pid := -1
var _reactions := {}           # speaker|kind -> PackedByteArray (generated once per session, cached by the service)
var _gemini_key := ""          # never leaves this process; never logged
var gemini_status := "not configured"
var gemini_stats := {"calls": 0, "cache_hits": 0, "shipped_hits": 0, "failures": 0, "retries": 0, "rejected": 0}
var _gemini_blocked_until := 0.0
var _identity_blocked := {}    # model -> unix time until which it is paused after a 429
var latency := {"lines": 0, "audio": 0, "prefetched": 0, "budget_drops": 0, "samples": []}   # V3 Part 9 (measured)
var identity_stats := {"shipped_hits": 0, "cache_hits": 0, "calls": 0, "alt_calls": 0, "failures": 0, "rejected": 0, "silent": 0}


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
	# the live show (developer's choice 2026-10-16, from the Kokoro voice picker): both mages speak with local Kokoro
	# voices - unlimited and ~0.2 s a line on the GPU (the Gemini identities allow ~200 new lines a day). Mika's is the
	# same voice Mika-Live speaks her chat answers with (room/characters/mika.yaml), so the stream has one Mika voice.
	# --live-voice=identity keeps their Gemini identities instead.
	if RenderProfile.options.has("live-link") and String(RenderProfile.options.get("live-voice", "kokoro")) == "kokoro":
		config.get_or_add("speakers", {})["mika"] = LIVE_VOICES.mika.duplicate()
		config.get_or_add("speakers", {})["luna"] = LIVE_VOICES.luna.duplicate()
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
	var args := ["-B", "-I", script, "--port", str(PORT), "--model", models + "/kokoro-v1.0.onnx",
		"--voices", models + "/voices-v1.0.bin", "--voice", VOICES.wandering_mage.voice, "--threads", "3", "--parent-pid", str(OS.get_process_id())]
	# the RTX GPU when its venv is there (onnxruntime-gpu): ~0.2 s a line instead of 3 s (idle CPU) to 25 s (busy CPU)
	var gpu_py := OS.get_environment("MIKA_DEV_KOKORO_GPU_PYTHON") if OS.get_environment("MIKA_DEV_KOKORO_GPU_PYTHON") != "" else GPU_PYTHON
	if FileAccess.file_exists(gpu_py) and not RenderProfile.options.has("kokoro-cpu"):
		py = gpu_py
		args.append_array(["--provider", "cuda"])
	_pid = OS.create_process(py, args)
	for i in 160:
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
	if provider == "gemini_identity":
		return true       # shipped / cached clips need no key; a missing line becomes a subtitle, never another voice
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
	var meta := {}
	var wav: PackedByteArray = await _synthesize(speaker, text, meta, opts)
	_cache_meta[key] = meta
	_cache[key] = wav


## A whole exchange known in advance (a conversation, a camp talk): every line after the first starts
## synthesising now, so each next line is ready while the one before it is still being spoken. lines: [{who/speaker,
## text, opts?}] with who already mapped to a voice id.
func prefetch_lines(lines: Array, skip_first := true) -> void:
	for i in lines.size():
		if i == 0 and skip_first:
			continue
		var l: Dictionary = lines[i]
		prefetch(String(l.get("speaker", l.get("who", ""))), String(l.text), l.get("opts", {}))


## p50 / p95 / max of the time from a line being asked for to its audio starting (ms), over this session.
func latency_report() -> Dictionary:
	var xs: Array = (latency.samples as Array).map(func(e): return int(e.tts_ms))
	xs.sort()
	var out := latency.duplicate()
	out.erase("samples")
	if not xs.is_empty():
		out["p50_ms"] = xs[int(xs.size() * 0.5)]
		out["p95_ms"] = xs[mini(xs.size() - 1, int(xs.size() * 0.95))]
		out["max_ms"] = xs[-1]
		out["by_source"] = {}
		for e in latency.samples:
			var k := String(e.src)
			var d: Dictionary = out.by_source.get_or_add(k, {"n": 0, "sum": 0})
			d.n += 1
			d.sum += int(e.tts_ms)
		for k in out.by_source:
			out.by_source[k]["avg_ms"] = int(out.by_source[k].sum / maxi(1, out.by_source[k].n))
	return out


static func _cache_key(speaker: String, text: String, opts: Dictionary) -> String:
	return "%s|%s|%s|%s" % [speaker, text, String(opts.get("form", "")), String(opts.get("mood", ""))]


func _synthesize(speaker: String, text: String, res: Dictionary, opts := {}) -> PackedByteArray:
	var ipa: String = pronunciations.get(_key(text), "")
	var cfg := _speaker_cfg(speaker)
	var provider := String(cfg.get("provider", ""))
	# Mika / Luna: their own voice identity, or nothing (never a different voice)
	if provider == "gemini_identity":
		return await _synthesize_identity(speaker, cfg, text, res, opts)
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
	var v: Dictionary = VOICES.get(speaker, VOICES.wandering_mage)
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
	http.timeout = 25.0
	add_child(http)
	var t_k := Time.get_ticks_msec()
	http.request("http://127.0.0.1:%d/synthesize" % PORT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	var r: Array = await http.request_completed
	http.queue_free()
	var k_ms := Time.get_ticks_msec() - t_k
	if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200:
		if k_ms > 4000:
			print("[voice] kokoro slow: %d ms for %s (%d chars)" % [k_ms, speaker, text.length()])
		return r[3]
	res["error"] = "tts failed (result %d, http %d)" % [r[0], r[1]]
	print("[voice] kokoro failed after %d ms for %s: %s (%s)" % [k_ms, speaker, res.error, text.left(60)])
	# nothing listening (the service died, or another app's service held the port and went away): start ours
	# again and try this line once more - a dead service must never turn speech into silent subtitles
	if r[0] == HTTPRequest.RESULT_CANT_CONNECT and not opts.get("_retried", false):
		if not _restarting:
			_restarting = true
			available = false
			await _start_service()
			_restarting = false
		else:
			while _restarting:
				await get_tree().create_timer(0.25).timeout
		var o2 := opts.duplicate()
		o2["_retried"] = true
		res.erase("error")
		return await _synthesize(speaker, text, res, o2)
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


## ---- Voice identities (Mika, Luna) ------------------------------------------------------------------
## Who has one, and what it is (for describe() / tests / docs).
func identities() -> Dictionary:
	var out := {}
	for k in config.get("speakers", {}):
		var c: Dictionary = config.speakers[k]
		if String(c.get("provider", "")) == "gemini_identity":
			out[k] = {"identity": c.identity, "voice": c.voice, "model": c.model, "post": c.post, "pitch": c.get("pitch", {})}
	return out


## The delivery for this line, from a small fixed set: an explicit mood, "latin" for an incantation, the
## speaker's current expression, else her neutral. Unknown moods fall back to neutral (never free text).
func identity_mood(speaker: String, cfg: Dictionary, text: String, opts: Dictionary) -> String:
	var moods: Dictionary = cfg.get("moods", {})
	var m := String(opts.get("mood", ""))
	if moods.has(m):
		return m
	if opts.get("latin", false) or pronunciations.has(_key(text)):
		return "latin"
	var who = _speakers.get(speaker)
	if who and is_instance_valid(who) and who.get("face") and who.face.has_method("dominant"):
		var e := String(who.face.dominant())
		var mapped := String((cfg.get("emotion_moods", {}) as Dictionary).get(e, ""))
		if moods.has(mapped):
			return mapped
	return "neutral"


static func identity_style(cfg: Dictionary, mood: String) -> String:
	var moods: Dictionary = cfg.get("moods", {})
	return "%s; %s" % [String(cfg.get("persona", "")), String(moods.get(mood, moods.get("neutral", "")))]


## The cache key of a line in a voice identity. tools/voice/voice_identity.py computes the same key for the
## shipped set: sha1("<identity>|<style>|<text>").
static func identity_key(cfg: Dictionary, style: String, text: String) -> String:
	return ("%s|%s|%s" % [String(cfg.get("identity", "")), style, text]).sha1_text()


## A line in her own voice. Never returns another voice: an empty result means "subtitle only".
func _synthesize_identity(speaker: String, cfg: Dictionary, text: String, res: Dictionary, opts: Dictionary) -> PackedByteArray:
	var mood := identity_mood(speaker, cfg, text, opts)
	var style := identity_style(cfg, mood)
	var key := identity_key(cfg, style, text)
	res["identity"] = String(cfg.identity)
	res["voice"] = String(cfg.voice)
	res["mood"] = mood
	var shipped := "%s/%s/%s.wav" % [IDENTITY_SHIPPED, speaker, key]
	var cached := "%s/%s/%s.wav" % [IDENTITY_CACHE, String(cfg.identity), key]
	for path in [shipped, cached]:
		if FileAccess.file_exists(path):
			var b := FileAccess.get_file_as_bytes(path)
			if b.size() > 44:
				res["provider"] = "gemini"
				res["cached"] = "shipped" if path == shipped else "session"
				identity_stats.shipped_hits += 1 if path == shipped else 0
				identity_stats.cache_hits += 1 if path == cached else 0
				return b
	if _gemini_key == "":
		res["error"] = "her voice is not available offline for this line (no key): subtitle only"
		identity_stats.silent += 1
		return PackedByteArray()
	var raw := await _identity_request(cfg, String(cfg.model), text, style, res)
	# the same voice on the second Gemini TTS model (its own daily quota) when the first is out of quota or unavailable
	if raw.is_empty() and String(cfg.get("alt_model", "")) != "" and (res.get("model_unavailable", false) or res.get("quota", false)):
		identity_stats.alt_calls += 1
		raw = await _identity_request(cfg, String(cfg.alt_model), text, style, res)
	if raw.is_empty():
		identity_stats.silent += 1
		return PackedByteArray()
	var model_used := String(res.get("model", cfg.model))
	var pitch := float((cfg.get("pitch", {}) as Dictionary).get(model_used, 1.15))
	var wav := await _post_process(raw, String(cfg.get("post", "")).replace("{pitch}", "%.3f" % pitch))
	res["pitch"] = pitch
	if wav.is_empty():
		res["error"] = "her voice processing (ffmpeg rubberband) failed: subtitle only"
		identity_stats.failures += 1
		identity_stats.silent += 1
		return PackedByteArray()
	var info := wav_info(wav)
	if info.seconds < 0.15 or info.seconds > maxf(5.0, 0.12 * text.length() + 3.0) or info.rms < 0.0025:   # a runaway TTS answer is babble
		res["error"] = "her synthesised audio failed validation (%.2f s, rms %.4f)" % [info.seconds, info.rms]
		identity_stats.rejected += 1
		identity_stats.silent += 1
		return PackedByteArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cached.get_base_dir()))
	var f := FileAccess.open(cached, FileAccess.WRITE)
	if f:
		f.store_buffer(wav)
		f.close()
	res["provider"] = "gemini"
	res["cached"] = "new"
	return wav


## One synthesis request for an identity (no retries beyond one on a transient failure; a 429 pauses that
## model for ten minutes). Returns raw WAV bytes (unprocessed) or empty.
func _identity_request(cfg: Dictionary, model: String, text: String, style: String, res: Dictionary) -> PackedByteArray:
	var now := Time.get_unix_time_from_system()
	if now < float(_identity_blocked.get(model, 0.0)):
		res["error"] = "%s paused after a quota answer (%d s left)" % [model, int(float(_identity_blocked[model]) - now)]
		res["quota"] = true
		return PackedByteArray()
	var interactions := model == String(cfg.model) and String(cfg.get("api", "")) == "interactions"
	var url := GEMINI_INTERACTIONS if interactions else GEMINI_URL % model
	var body := {}
	if interactions:
		body = {"model": model, "input": [{"type": "user_input", "content": [{"type": "text", "text": text,
			"annotations": [{"type": "speech_metadata", "style": style}]}]}], "response_format": {"type": "audio"},
			"generation_config": {"speech_config": [{"voice": String(cfg.voice)}]}}
	else:
		body = {"contents": [{"parts": [{"text": "Say this %s: %s" % [style, text]}]}],
			"generationConfig": {"responseModalities": ["AUDIO"],
				"speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": String(cfg.voice)}}}}}
	for attempt in 2:
		if attempt == 1:
			await get_tree().create_timer(0.8).timeout
		identity_stats.calls += 1
		var started := Time.get_ticks_msec()
		var http := HTTPRequest.new()
		http.timeout = GEMINI_TIMEOUT
		add_child(http)
		var err := http.request(url, ["Content-Type: application/json", "x-goog-api-key: " + _gemini_key], HTTPClient.METHOD_POST, JSON.stringify(body))
		if err != OK:
			http.queue_free()
			res["error"] = "request could not start (%d)" % err
			identity_stats.failures += 1
			continue
		var r: Array = await http.request_completed
		http.queue_free()
		var code := int(r[1])
		res["gemini_ms"] = Time.get_ticks_msec() - started
		res["model"] = model
		if r[0] != HTTPRequest.RESULT_SUCCESS or code >= 500:
			res["error"] = "transport/server failure (result %d, http %d)" % [r[0], code]
			identity_stats.failures += 1
			continue
		if code == 429:
			_identity_blocked[model] = Time.get_unix_time_from_system() + GEMINI_QUOTA_PAUSE_S
			res["error"] = "%s quota exhausted (429): paused for %d s" % [model, int(GEMINI_QUOTA_PAUSE_S)]
			res["quota"] = true
			identity_stats.failures += 1
			return PackedByteArray()
		if code == 400 or code == 404:
			res["model_unavailable"] = true
		if code != 200:
			res["error"] = "%s refused (http %d)" % [model, code]
			identity_stats.failures += 1
			return PackedByteArray()
		if interactions:
			var wav := _interactions_audio(r[3], res)
			if not wav.is_empty():
				return wav
		else:
			var wav2 := _gemini_wav_from_response(r[3], 1.0, res)
			if wav2.size() > 44:
				return wav2
		identity_stats.rejected += 1
	return PackedByteArray()


static func _interactions_audio(raw: PackedByteArray, res: Dictionary) -> PackedByteArray:
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		res["error"] = "unreadable answer"
		return PackedByteArray()
	for st in (parsed as Dictionary).get("steps", []):
		if String((st as Dictionary).get("type", "")) != "model_output":
			continue
		for c in (st as Dictionary).get("content", []):
			if String((c as Dictionary).get("type", "")) == "audio" and (c as Dictionary).has("data"):
				var b := Marshalls.base64_to_raw(String(c.data))
				if b.size() > 4 and b.slice(0, 4).get_string_from_ascii() == "RIFF":
					return b
				return pcm_wav(b, 24000)
	res["error"] = "answer carried no audio"
	return PackedByteArray()


## The identity's processing chain (formant-preserving pitch, loudness) through ffmpeg in a worker thread, so
## the game keeps rendering. Returns the processed WAV or empty.
func _post_process(raw: PackedByteArray, filt: String) -> PackedByteArray:
	if filt == "":
		return raw
	var dir := ProjectSettings.globalize_path(IDENTITY_CACHE + "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	var stem := "%s/%d_%d" % [dir, Time.get_ticks_usec(), randi() % 100000]
	var inp := stem + "_in.wav"
	var outp := stem + "_out.wav"
	var f := FileAccess.open(inp, FileAccess.WRITE)
	if f == null:
		return PackedByteArray()
	f.store_buffer(raw)
	f.close()
	var th := Thread.new()
	th.start(func() -> int:
		return OS.execute("ffmpeg", ["-v", "error", "-y", "-i", inp, "-af", filt, "-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", outp], [], true))
	while th.is_alive():
		await get_tree().process_frame
	var code: int = th.wait_to_finish()
	var out := FileAccess.get_file_as_bytes(outp) if code == 0 and FileAccess.file_exists(outp) else PackedByteArray()
	DirAccess.remove_absolute(inp)
	DirAccess.remove_absolute(outp)
	return out


## {rate, seconds, rms} of 16-bit mono PCM WAV bytes.
static func wav_info(wav: PackedByteArray) -> Dictionary:
	if wav.size() < 44:
		return {"rate": 0, "seconds": 0.0, "rms": 0.0}
	var rate := wav.decode_u32(24)
	var off := 44
	var i := 12
	while i < wav.size() - 8:
		if wav.slice(i, i + 4).get_string_from_ascii() == "data":
			off = i + 8
			break
		i += 8 + wav.decode_u32(i + 4)
	var n := (wav.size() - off) / 2
	var acc := 0.0
	var cnt := 0
	for k in range(0, n, 7):
		var v := float(wav.decode_s16(off + k * 2)) / 32768.0
		acc += v * v
		cnt += 1
	return {"rate": rate, "seconds": float(n) / maxf(rate, 1), "rms": sqrt(acc / maxf(cnt, 1))}


static func pcm_wav(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(44)
	out.encode_u32(0, 0x46464952)      # "RIFF"
	out.encode_u32(4, 36 + pcm.size())
	out.encode_u32(8, 0x45564157)      # "WAVE"
	out.encode_u32(12, 0x20746d66)     # "fmt "
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)
	out.encode_u16(22, 1)
	out.encode_u32(24, rate)
	out.encode_u32(28, rate * 2)
	out.encode_u16(32, 2)
	out.encode_u16(34, 16)
	out.encode_u32(36, 0x61746164)     # "data"
	out.encode_u32(40, pcm.size())
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
	var can := (provider == "edge" and edge_available) or (provider == "gemini") or (provider == "gemini_identity")
	if provider == "gemini_identity":
		res["provider"] = "gemini"
		res["identity"] = String(cfg.get("identity", ""))
	if enabled and can and texts.has(speaker):
		if not _reactions.has(key):
			var r2 := {}
			if provider == "gemini_identity":
				_reactions[key] = await _synthesize_identity(speaker, cfg, String(texts[speaker]), r2, {"mood": kind})
			elif provider == "gemini":
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
			var hear_r := hearing(speaker)
			if hear_r <= 0.0:
				res["out_of_earshot"] = true
				return res
			p.volume_db = linear_to_db(hear_r)
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


const HEAR_FULL_M := 8.0     # within this distance of the camera a voice is at full level
const HEAR_MAX_M := 30.0     # beyond this she is out of earshot (not heard, no subtitle)


## 0..1: how loud `speaker` is where the camera is (1 within HEAR_FULL_M, fading to -24 dB at HEAR_MAX_M, 0 past
## it). A speaker with no body in the world (a narrator, the show) is always 1.
func hearing(speaker: String) -> float:
	var who = _speakers.get(speaker)
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if who == null or not is_instance_valid(who) or not (who is Node3D) or cam == null:
		return 1.0
	if (who as Node3D).has_method("is_visible_in_tree") and not (who as Node3D).is_visible_in_tree():
		return 0.0                   # in another area / not in this world right now
	var d := cam.global_position.distance_to((who as Node3D).global_position + Vector3(0, 1.4, 0))
	if d <= HEAR_FULL_M:
		return 1.0
	if d >= HEAR_MAX_M:
		return 0.0
	return db_to_linear(-24.0 * (d - HEAR_FULL_M) / (HEAR_MAX_M - HEAR_FULL_M))


func busy() -> bool:
	return _busy or not _queue.is_empty()


## Stop speaking now and drop what is queued (the live show interrupted her).
func stop() -> void:
	for job in _queue:
		job.done = true
	_queue.clear()
	if _player and _player.playing:
		_player.stop()


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
	if opts.get("wav") is PackedByteArray and (opts.wav as PackedByteArray).size() > 44:
		wav = opts.wav                          # already spoken elsewhere (Mika-Live's own voices over the live link)
		res["external"] = true
	elif enabled and _can_synthesize(speaker):
		var key := _cache_key(speaker, text, opts)
		if _cache.has(key) and (typeof(_cache[key]) != TYPE_STRING or float(opts.get("max_wait", 0.0)) <= 0.0):
			while typeof(_cache[key]) == TYPE_STRING:   # prefetch still in flight
				await get_tree().process_frame
			wav = _cache[key]
			_cache.erase(key)
			res.merge(_cache_meta.get(key, {}))
			_cache_meta.erase(key)
			res["prefetched"] = true
			if pronunciations.has(_key(text)):
				res["phonemes"] = true
		if wav.is_empty() and float(opts.get("max_wait", 0.0)) > 0.0:
			# a latency budget (combat barks): the line is synthesised in the background; if it is not ready in
			# time it is shown, not spoken, and the voice lands in the cache for the next time she says it
			prefetch(speaker, text, opts)
			var t_end := Time.get_ticks_msec() + int(float(opts.max_wait) * 1000.0)
			while _cache.has(key) and typeof(_cache[key]) == TYPE_STRING and Time.get_ticks_msec() < t_end:
				await get_tree().process_frame
			if _cache.has(key) and typeof(_cache[key]) != TYPE_STRING:
				wav = _cache[key]
				_cache.erase(key)
				res.merge(_cache_meta.get(key, {}))
				_cache_meta.erase(key)
			else:
				res["budget_drop"] = true
				latency.budget_drops += 1
		elif wav.is_empty():
			wav = await _synthesize(speaker, text, res, opts)
	res["tts_ms"] = Time.get_ticks_msec() - started
	latency.lines += 1
	latency.prefetched += 1 if res.get("prefetched", false) else 0
	latency.samples.append({"tts_ms": res.tts_ms, "src": "prefetch" if res.get("prefetched", false) else String(res.get("cached", "budget_drop" if res.get("budget_drop", false) else "synth"))})
	if latency.samples.size() > 400:
		latency.samples.pop_front()
	var subtitle: bool = opts.get("subtitle", true)
	# where she is: a mage far from the camera is heard faintly, or not at all (her incantation across the valley
	# was as loud as one beside the lens). Mika-Live's own lines (the host talking to chat) always carry.
	var hear := 1.0 if res.get("external", false) else hearing(speaker)
	res["hearing"] = snappedf(hear, 0.01)
	if hear <= 0.0:
		var secs_far := clampf(text.split(" ").size() / 2.6, 1.0, 9.0)
		await get_tree().create_timer(secs_far).timeout
		res["audio"] = false
		res["out_of_earshot"] = true
		res["total_ms"] = Time.get_ticks_msec() - started
		line_finished.emit(speaker, res)
		return res
	if wav.size() > 44:
		var stream := AudioStreamWAV.load_from_buffer(wav)
		var env := _envelope(wav)
		_player.stream = stream
		var bus := String(opts.get("bus", "Voice"))
		_player.bus = bus if AudioServer.get_bus_index(bus) != -1 else "Voice"
		_player.volume_db = linear_to_db(hear)
		_player.play()
		res["audio"] = true
		res["fallback"] = false
		latency.audio += 1
		res["seconds"] = snappedf(stream.get_length(), 0.01)
		res["bus"] = _player.bus
		line_started.emit(speaker, text)
		if subtitle and main:
			main.show_subtitle(_caption(speaker, text), stream.get_length() + 0.4)
		var who = _speakers.get(speaker)
		# her body talks along: hands and forearms beat with the voice; a longer line while standing gets a
		# conversational gesture
		if who and is_instance_valid(who) and who.get("body_language") and is_instance_valid(who.body_language):
			who.body_language.speaking = true
			if stream.get_length() > 3.2 and who.has_method("play_gesture") and not who.seated and who.ground_pose == "" and not who.combat_stance \
					and Vector2(who.velocity.x, who.velocity.z).length() < 0.3 and randf() < 0.55:
				who.play_gesture("idle_talk", 0.5, 0.7)
		var talk_seq: int = int(who.get("gesture_seq")) if who and is_instance_valid(who) and who.get("gesture_seq") != null else -1
		while _player.playing:
			await get_tree().process_frame
			# the mouth follows the audio's own clock (a Movie Maker recording runs slower than real time)
			var idx := int(_player.get_playback_position() * 30.0)
			var amp: float = env[idx] if idx < env.size() else 0.0
			_mouth(who, amp)
		_mouth(who, 0.0)
		if who and is_instance_valid(who) and who.get("body_language") and is_instance_valid(who.body_language):
			who.body_language.speaking = false
		# the talking idle LOOPS: ended with the line (left on, it held her whole body - she slid away from a talk with
		# no walk cycle, 2026-10-17 stream), unless another gesture took over meanwhile
		if talk_seq >= 0 and is_instance_valid(who) and int(who.get("gesture_seq")) == talk_seq and String(who.get("current_gesture")) == "idle_talk":
			who.end_gesture()
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
	return "%s: %s" % [names.get(speaker, String(_speaker_cfg(speaker).get("caption", speaker.capitalize()))), text]


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
		"identities": identities(), "identity_stats": identity_stats, "latency": latency_report(),
		"recent": log.slice(maxi(0, log.size() - 5))}
