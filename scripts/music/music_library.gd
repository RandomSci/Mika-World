class_name MusicLibrary
extends RefCounted
## The shared local song library (assets/audio/music/). Songs are listed in music_catalog.json AND discovered
## from library/<id>/metadata.json folders, so adding a song is: drop its folder in, run
## tools/audio/analyze_song.py on it. Nothing here is per-mage: who played what, favourites and familiarity
## live in each mage's own mind (mind.music). Loading or playing a cached song never calls any API.

const ROOT := "res://assets/audio/music/"

static var _songs := {}          # id -> metadata (+ "dir")
static var _timing := {}         # id -> timing.json contents


static func reload() -> void:
	_songs.clear()
	_timing.clear()
	var listed := {}
	if FileAccess.file_exists(ROOT + "music_catalog.json"):
		var cat = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "music_catalog.json"))
		if cat is Dictionary:
			for e in cat.get("songs", []):
				listed[String(e.id)] = ROOT + String(e.path)
	var d := DirAccess.open(ROOT + "library")
	if d:
		for sub in d.get_directories():
			listed.get_or_add(sub, ROOT + "library/" + sub)
	for id in listed:
		var mp: String = listed[id] + "/metadata.json"
		if not FileAccess.file_exists(mp):
			continue
		var m = JSON.parse_string(FileAccess.get_file_as_string(mp))
		if not m is Dictionary:
			continue
		m["dir"] = listed[id]
		m["audio_path"] = listed[id] + "/" + String(m.get("file", "original.mp3"))
		if not FileAccess.file_exists(m.audio_path) and not ResourceLoader.exists(m.audio_path):
			push_warning("[music] %s: audio file missing (%s) - skipped" % [id, m.audio_path])
			continue
		_songs[id] = m


static func songs() -> Dictionary:
	if _songs.is_empty():
		reload()
	return _songs


static func song(id: String) -> Dictionary:
	return songs().get(id, {})


static func timing(id: String) -> Dictionary:
	if not _timing.has(id):
		var p := String(song(id).get("dir", "")) + "/timing.json"
		var t = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		_timing[id] = t if t is Dictionary else {}
	return _timing[id]


## The song's audio as a stream (imported resource when available, else decoded from the file bytes).
static func stream(id: String) -> AudioStream:
	var path := String(song(id).get("audio_path", ""))
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is AudioStream:
			return r
	if FileAccess.file_exists(path) and path.ends_with(".mp3"):
		var s := AudioStreamMP3.new()
		s.data = FileAccess.get_file_as_bytes(path)
		return s
	return null


## Songs this performer may use in this mode (casual / special).
static func eligible(who: String, mode: String) -> Array:
	var out := []
	for id in songs():
		var m: Dictionary = songs()[id]
		if not (m.get("performers", [who]) as Array).has(who):
			continue
		if not bool(m.get(mode + "_eligible", true)):
			continue
		out.append(id)
	return out


## Pick a song for `who`: favourites and familiar songs are preferred, anything she played in her last few
## performances is avoided when there is an alternative.
static func pick(who: String, mode: String, rng: RandomNumberGenerator, music: Dictionary) -> String:
	var ids := eligible(who, mode)
	if ids.is_empty():
		return ""
	var hist: Array = music.get("history", [])
	var recent := hist.slice(maxi(0, hist.size() - 3)).map(func(h): return String(h.get("song", "")))
	var w := {}
	var total := 0.0
	for id in ids:
		var v := 1.0 + 0.6 * float((music.get("favorites", []) as Array).has(id)) + 0.3 * float(music.get("familiarity", {}).get(id, 0.0))
		if recent.has(id) and ids.size() > 1:
			v *= 0.15
		w[id] = v
		total += v
	var r := rng.randf() * total
	for id in ids:
		r -= float(w[id])
		if r <= 0.0:
			return id
	return ids[-1]


## Choose WHICH part of the song fits a performance with `music_s` seconds of music, ending at a musical
## close when possible:  section_end > phrase_end (from timing.endings) > fade at a bar line > natural end.
## Returns {start, end, ending, fade}.
static func plan_segment(id: String, music_s: float, rng: RandomNumberGenerator, mode := "casual") -> Dictionary:
	var t := timing(id)
	var dur := float(song(id).get("duration", t.get("duration", 0.0)))
	if dur <= 0.0:
		return {}
	if dur <= music_s + 1.0:
		return {"start": 0.0, "end": dur, "ending": "natural_end", "fade": 0.0}
	var ends: Array = t.get("endings", [])
	var sec: Array = t.get("sections", [])
	var starts := [0.0]
	for s in sec:
		starts.append(float(s.start))
	# special performances prefer the loudest sections (a fuller sound); casual ones anything that fits
	var best := {}
	var best_score := -1e9
	for st in starts:
		for e in ends:
			var L := float(e) - float(st)
			if L < music_s - 6.0 or L > music_s + 2.0:
				continue
			var score := -absf(L - music_s) + rng.randf() * 2.0
			if mode == "special":
				for s in sec:
					if absf(float(s.start) - float(st)) < 0.1:
						score += (float(s.loudness_db) + 20.0) * 0.4
			if score > best_score:
				best_score = score
				best = {"start": float(st), "end": float(e), "ending": "section_end" if sec.any(func(s): return absf(float(s.end) - float(e)) < 0.1) else "phrase_end", "fade": 0.6}
	if not best.is_empty():
		return best
	# no musical close fits: start at a section, stop at the nearest bar line and fade
	var st2: float = starts[rng.randi() % starts.size()]
	if st2 + music_s > dur:
		st2 = maxf(0.0, dur - music_s)
	var target := st2 + music_s
	var bar_t := target
	for b in t.get("downbeats", []):
		if absf(float(b) - target) < absf(bar_t - target) or bar_t == target:
			bar_t = float(b) if absf(float(b) - target) < 2.0 else bar_t
	return {"start": st2, "end": minf(bar_t, dur), "ending": "fade", "fade": 2.5}


## Estimated vocal activity (0..1) at song time `t` (amplitude-style; see timing.json "vocal").
static func vocal_at(id: String, t: float) -> float:
	var v: Dictionary = timing(id).get("vocal", {})
	var env: Array = v.get("envelope", [])
	if env.is_empty():
		return 0.0
	var i := clampi(int(t * float(v.get("rate", 25))), 0, env.size() - 1)
	var on := false
	for s in v.get("segments", []):
		if t >= float(s[0]) and t <= float(s[1]):
			on = true
			break
	return float(env[i]) if on else 0.0
