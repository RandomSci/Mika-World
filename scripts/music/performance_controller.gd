class_name PerformanceController
extends Node
## Music performances inside the existing world (no separate stage, no generated images, no live music).
## Responsibilities are split:
##   * the PLANNER decides whether / which mode / when to stop (SanctuaryBrain "perform" activity);
##   * this CONTROLLER owns playback, timing, dance animation, lip movement, effects and the lifecycle;
##   * the CameraDirector frames it (performance shots, changed on musical phrases);
##   * the world stays authoritative for position, collision and memory.
## The MUSIC TIMELINE (AudioStreamPlayer playback position, latency-corrected) is the synchronisation source.
##
## Modes (data/performances.json):
##   casual  - 60..90 s TOTAL (intro remark + music + closing remark), wherever she is, subtle effects
##   special - same 60..90 s cap for now, at a designated existing location, opening/finishing pose,
##             cinematic camera profile, a little stronger (still bounded) effects, audience acknowledgement
## A performance ends at a musical close found in the song's timing (section end > phrase end), or with a
## short fade at a bar line; never mid-phrase if avoidable. Interruptions (a creature, a hit, the focus
## leaving) fade out within a second and are recorded as such. Previews (F8) change no memory or XP.
## Lip movement uses the song's ESTIMATED vocal activity (amplitude-style, from the mixed track).

signal started(entry: Dictionary)
signal ended(entry: Dictionary)

static var cfg := {}

var main: Node
var active := {}                 # the running performance (empty when none)
var log: Array = []
var player: AudioStreamPlayer
var rng := RandomNumberGenerator.new()
var _clip_period := {}           # dance clip -> seconds per bob (measured from the hips)
var _abort := ""
var _fx := {}                    # persistent beat emitters for the running performance (reused, not re-created)
var requests: Array = []         # dances asked for (viewers, celebrations), started when both mages can: [{who, with, dance, why}]


static func load_cfg() -> Dictionary:
	if cfg.is_empty():
		cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/performances.json"))
	return cfg


func setup(m: Node) -> void:
	main = m
	load_cfg()
	rng.seed = int(Time.get_unix_time_from_system())
	player = AudioStreamPlayer.new()
	player.name = "PerformanceMusic"
	player.bus = "Music"
	add_child(player)
	# a level gained is worth a dance (with the other mage when she is close)
	if main.get("progression") and main.progression.has_signal("leveled"):
		main.progression.leveled.connect(func(who: String, _lv: int): request(who, {"partner_if_near": true, "why": "celebrating"}))


## Ask for a dance (a viewer's request, a celebration): it starts as soon as the dancer (and her partner) are free,
## never cutting into combat, a cast, reading or a conversation. opts: {with, partner_if_near, dance, why}.
func request(who: String, opts := {}) -> void:
	if requests.size() >= 3:
		requests.pop_front()
	var r := opts.duplicate()
	r["who"] = who
	r["asked"] = Time.get_ticks_msec()
	requests.append(r)


func _process(_d: float) -> void:
	if requests.is_empty() or busy():
		return
	var r: Dictionary = requests[0]
	if Time.get_ticks_msec() - int(r.asked) > 180000:
		requests.pop_front()                        # asked too long ago: let it go
		return
	var who := String(r.who)
	# a celebration right after she has danced is dropped (she just did): only asked-for dances repeat soon
	if String(r.get("why", "")) == "celebrating" and Time.get_unix_time_from_system() - float(WorldState.mind(who).music.get("last_unix", 0)) < float(cfg.cooldown_s.casual):
		requests.pop_front()
		return
	if not available(who).ok:
		return
	requests.pop_front()
	var opts := {"dance": String(r.get("dance", "")), "why": String(r.get("why", ""))}
	var partner := String(r.get("with", ""))
	if partner == "" and bool(r.get("partner_if_near", false)):
		for other in main.characters:
			if other != who and (main.characters[other] as Node3D).visible and (main.characters[other] as Node3D).global_position.distance_to((main.characters[who] as Node3D).global_position) < 14.0:
				partner = other
	if partner != "":
		opts["with"] = partner
	perform(who, "casual", opts)


## Can `partner` join a dance now (not fighting, casting, holding, seated, reading, transforming)?
## The nearest spot (on the navmesh, within ~4 m) with nothing solid around her at body height - and, with a
## partner, open floor on (nearly) every side, since the partner's place depends on where the camera is. Vector3.INF when even her own spot is as good as it gets.
func _open_floor(c: WorldCharacter, with_partner: bool) -> Vector3:
	var map := c.get_world_3d().navigation_map
	var here := c.global_position
	var best := Vector3.INF
	for ring in [0.0, 2.0, 3.0, 4.0]:
		for k in (1 if ring == 0.0 else 8):
			var a := TAU * k / 8.0
			var p := NavigationServer3D.map_get_closest_point(map, here + Vector3(cos(a), 0, sin(a)) * ring)
			if p.distance_to(here + Vector3(cos(a), 0, sin(a)) * ring) > 0.8 or absf(p.y - here.y) > 1.0:
				continue                 # off the walkable floor
			if not _clear_at(c, p):
				continue
			if with_partner:             # she turns to the camera later: open floor nearly all around her
				var open_sides := 0
				for j in 8:
					var side := p + Vector3(cos(TAU * j / 8.0), 0, sin(TAU * j / 8.0)) * 1.7
					var ps := NavigationServer3D.map_get_closest_point(map, side)
					if ps.distance_to(side) < 0.6 and _clear_at(c, ps):
						open_sides += 1
				if open_sides < 6:
					continue
			return p
	return best


func _clear_at(c: WorldCharacter, p: Vector3) -> bool:
	var sh := SphereShape3D.new()
	sh.radius = 0.85
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.05, 0))
	q.collision_mask = 1 | 4
	var ex: Array[RID] = []
	for o in main.characters.values():
		if o is CollisionObject3D:
			ex.append((o as CollisionObject3D).get_rid())
	q.exclude = ex
	return c.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _partner_free(partner: String) -> bool:
	var c2: WorldCharacter = main.characters.get(partner)
	if c2 == null or not c2.visible or c2.casting or c2.seated or (c2.handler and c2.handler.held != null):
		return false
	var b2 = main.mage_brains.get(partner)
	if b2 and b2.threat != null:
		return false
	if main.book_reader and main.book_reader.reading() and main.book_reader.current.get("reader", "") == partner:
		return false
	return true


func busy() -> bool:
	return not active.is_empty()


## The current song time in seconds (what everything synchronises to).
func music_time() -> float:
	if not player.playing:
		return -1.0
	return player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


## Can `who` start a performance right now? (never during combat, transformations, reading, conversations,
## object handling, or while someone else is performing / talking)
func available(who: String) -> Dictionary:
	var c: WorldCharacter = main.characters.get(who)
	if c == null or not c.visible:
		return {"ok": false, "why": "not in view"}
	if busy():
		return {"ok": false, "why": "someone is already performing"}
	if c.casting or c.seated or (c.handler and c.handler.held != null):
		return {"ok": false, "why": "busy with her hands / seated / casting"}
	if main.transformer and main.transformer.playing != "":
		return {"ok": false, "why": "a transformation is playing"}
	var b = main.mage_brains.get(who)
	if b and b.threat != null:
		return {"ok": false, "why": "a creature is on her"}
	if main.book_reader and main.book_reader.reading() and main.book_reader.current.get("reader", "") == who:
		return {"ok": false, "why": "reading"}
	if main.mage_talk and main.mage_talk.busy():
		return {"ok": false, "why": "a conversation is going on"}
	return {"ok": true}


## Run one performance. opts: {song, total, preview (no memory/XP), venue (special)}. Returns the record.
func perform(who: String, mode := "casual", opts := {}) -> Dictionary:
	var av := available(who)
	if not av.ok:
		return {"ok": false, "detail": "cannot perform now: " + String(av.why)}
	var mc: Dictionary = cfg.modes.get(mode, cfg.modes.casual)
	var c: WorldCharacter = main.characters[who]
	var m := WorldState.mind(who)
	var music := m.music
	var preview := bool(opts.get("preview", false))
	var song := String(opts.get("song", ""))
	if song == "":
		song = MusicLibrary.pick(who, mode, rng, music)
	if song == "" or MusicLibrary.song(song).is_empty():
		return {"ok": false, "detail": "no eligible song in the library"}
	var stream := MusicLibrary.stream(song)
	if stream == null:
		return {"ok": false, "detail": "the song's audio could not be loaded (%s)" % song}
	var total := float(opts.get("total", rng.randf_range(float(mc.total_s[0]), float(mc.total_s[1]))))
	total = clampf(total, float(cfg.limits.min_total_s), float(cfg.limits.max_total_s))
	var t_start := Time.get_ticks_msec()
	_abort = ""
	active = {"who": who, "mode": mode, "song": song, "title": String(MusicLibrary.song(song).get("title", song)), "planned_total": snappedf(total, 0.1),
		"preview": preview, "stage": "starting", "clips": [], "singing": false, "started_unix": int(Time.get_unix_time_from_system())}
	var brain = main.mage_brains.get(who)
	var voice_id := String(Progression.mages.get(who, {}).get("voice", who))
	var dir_was: bool = main.director.enabled if main.director else false
	# the camera films a performance only when it belongs to the stream's mage (Mika-first) or the shared
	# profile is on; a mage performing on her own elsewhere is never a cutaway (Milestone J)
	var films: bool = main.director != null and (String(main.get("stream_profile")) == "shared" or main.characters.get(main.get("focus")) == c)
	active["filmed"] = films
	if films:
		main.director.enabled = true
	# special: go to the venue, opening pose
	if mode == "special":
		active.stage = "walking to the venue"
		var venue: Array = opts.get("venue", mc.get("venue", [0, 0, 0]))
		var map := c.get_world_3d().navigation_map
		var spot := NavigationServer3D.map_get_closest_point(map, Vector3(venue[0], venue[1], venue[2]))
		# a clear spot: nobody else within 2.5 m (try a ring around the venue)
		for k in 9:
			var crowded := false
			for other in main.characters.values():
				if other != c and (other as Node3D).visible and (other as Node3D).global_position.distance_to(spot) < 2.5:
					crowded = true
			if not crowded:
				break
			var a := TAU * k / 8.0
			spot = NavigationServer3D.map_get_closest_point(map, Vector3(venue[0], venue[1], venue[2]) + Vector3(cos(a), 0, sin(a)) * 3.5)
		c.navigate_to(spot, false)
		while c.current_action == "navigate_to" and (Time.get_ticks_msec() - t_start) < 20000:
			await get_tree().process_frame
		if main.camera_rig and main.characters.get(main.get("focus")) == c:
			pass
	# room to dance: where she stands, or the nearest open floor a few steps away, with her partner's place beside
	# her clear too (a brazier or a column there hid her partner from the camera for the whole dance)
	var partner_wanted := String(opts.get("with", "")) != "" and String(opts.get("with", "")) != who
	var open := _open_floor(c, partner_wanted)
	if open != Vector3.INF and open.distance_to(c.global_position) > 0.6:
		active.stage = "finding room to dance"
		c.navigate_to(open, false)
		var tw := Time.get_ticks_msec()
		while c.current_action == "navigate_to" and Time.get_ticks_msec() - tw < 12000:
			await get_tree().process_frame
	# the dance is on: she turns to the camera FIRST, then the performance shot is set from her front (a shot set
	# before she turned filmed her back while her partner walked over)
	if films:
		var cam0 := get_viewport().get_camera_3d()
		if cam0:
			c.look_at_point(Vector3(cam0.global_position.x, c.global_position.y, cam0.global_position.z))
			var tt := Time.get_ticks_msec()
			while c.current_action == "look_at" and Time.get_ticks_msec() - tt < 1500:
				await get_tree().process_frame
		main.director.start_performance(c, mode)
	# a partner: she comes to stand beside the dancer (on foot), her own mind paused while they dance together
	var c2: WorldCharacter = null
	var b2 = null
	var partner := String(opts.get("with", ""))
	if partner != "" and partner != who and _partner_free(partner):
		c2 = main.characters[partner]
		b2 = main.mage_brains.get(partner)
		if b2:
			b2.hold = true
		var map2 := c.get_world_3d().navigation_map
		var side := NavigationServer3D.map_get_closest_point(map2, c.global_position + c.global_transform.basis.x * -1.7)
		if not _clear_at(c, side):       # her left is blocked (a brazier, a column): the right side
			var right := NavigationServer3D.map_get_closest_point(map2, c.global_position + c.global_transform.basis.x * 1.7)
			if _clear_at(c, right):
				side = right
		if c2.global_position.distance_to(side) > 0.8:
			c2.navigate_to(side, false)
			var tw0 := Time.get_ticks_msec()
			while c2.current_action == "navigate_to" and Time.get_ticks_msec() - tw0 < 15000:
				await get_tree().process_frame
		c2.look_at_point(c2.global_position - c.global_transform.basis.z * 4.0)
		active["partner"] = partner
		if films:
			main.director.set_performance_pair(c2)
	started.emit(active)
	# intro remark (her own voice), counted inside the total
	var intro := _line(who, "perform_intro_" + mode, music)
	active.stage = "intro"
	if mode == "special":
		c.play_gesture("spell_casting", 0.35, 0.5)
		_venue_fx(c, true)
	if intro != "":
		await main.voice.say(voice_id, intro)
	var intro_s := (Time.get_ticks_msec() - t_start) / 1000.0
	var outro_reserve := float(mc.outro_reserve_s)
	var music_s := maxf(20.0, total - intro_s - outro_reserve)
	var seg := MusicLibrary.plan_segment(song, music_s, rng, mode)
	if seg.is_empty():
		return _finish(c, brain, dir_was, {"ok": false, "detail": "the song has no timing"}, t_start)
	active["segment"] = seg
	var timing := MusicLibrary.timing(song)
	var beats: Array = timing.get("beats", [])
	var bars: Array = timing.get("downbeats", [])
	var beat_len := 60.0 / maxf(float(timing.get("bpm", 120.0)), 1.0)
	# music
	player.stream = stream
	player.volume_db = float(cfg.mix.music_db)
	# the song carries the dance: the Music bus comes up and the forest's ambience steps back while they dance
	# (at the everyday levels the ambience covered the song), both restored afterwards
	_bus_levels(true)
	player.play(float(seg.start))
	active.stage = "dancing"
	c.set_expression("happy", float(cfg.performers.get(who, {}).get("smile", 0.5)))
	# dancing: hair hangs from her upper body, not trailing in the world (no flinging over her head)
	c.set_hair_frame("UpperChest")
	if c2:
		c2.set_hair_frame("UpperChest")
	var clips := _dance_order(who, mode)
	var want_dance := String(opts.get("dance", ""))
	if want_dance != "" and cfg.dances.has(want_dance):
		clips.erase(want_dance)
		clips.push_front(want_dance)                     # what was asked for opens the dance
	if c2:
		c2.set_expression("happy", float(cfg.performers.get(partner, {}).get("smile", 0.5)))
	var phrase_bars := int(mc.phrase_bars)
	var next_bar_i := bars.find(bars.filter(func(b): return float(b) >= float(seg.start)).front()) if not bars.is_empty() else -1
	var bars_in_phrase := 0
	var clip_i := 0
	var next_beat_i := 0
	for i in beats.size():
		if float(beats[i]) >= float(seg.start):
			next_beat_i = i
			break
	_start_clip(c, clips[0], beat_len)
	if c2:
		_start_clip(c2, clips[0], beat_len)                # together: the same steps, on the same beat
	active.clips.append(clips[0])
	_make_fx(c, mode)
	var sing: bool = bool(MusicLibrary.song(song).get("has_vocals", false)) and rng.randf() < float(cfg.performers.get(who, {}).get("sing_chance", 0.6))
	active.singing = sing
	var glance_cd := rng.randf_range(8.0, 14.0)
	var t_music0 := Time.get_ticks_msec()
	var ending_started := false
	while true:
		await get_tree().process_frame
		var mt := music_time()
		var elapsed_total := (Time.get_ticks_msec() - t_start) / 1000.0
		if _abort == "" and brain and brain.threat != null:
			_abort = "a creature came close"
		if _abort == "" and not c.visible:
			_abort = "she left the view"
		if _abort != "":
			break
		if mt < 0.0 and (Time.get_ticks_msec() - t_music0) > 1500:
			break                                              # the song ended on its own
		# beat events: subtle sparkles on half-time beats
		while next_beat_i < beats.size() and mt >= float(beats[next_beat_i]):
			if next_beat_i % 4 == 0:
				_beat_fx(c, mode, next_beat_i % 16 == 0)      # bar downbeats only: sparse and cheap
			next_beat_i += 1
		# phrase changes on downbeats: next dance clip + a new camera shot
		if next_bar_i >= 0:
			while next_bar_i < bars.size() and mt >= float(bars[next_bar_i]):
				bars_in_phrase += 1
				next_bar_i += 1
				if bars_in_phrase >= phrase_bars and mt < float(seg.end) - 2.0 * beat_len * 4.0:
					bars_in_phrase = 0
					clip_i = (clip_i + 1) % clips.size()
					_start_clip(c, clips[clip_i], beat_len)
					if c2:
						_start_clip(c2, clips[clip_i], beat_len)
					if not active.clips.has(clips[clip_i]):
						active.clips.append(clips[clip_i])
					if main.director:
						main.director.performance_cut()
		# mouth: estimated vocal activity (amplitude-style), only if she is singing along
		if sing:
			c.set_expression("aa", clampf(MusicLibrary.vocal_at(song, mt) * 0.85, 0.0, 0.85))
		# occasional, brief eye contact with the camera (not constant)
		glance_cd -= get_process_delta_time()
		if glance_cd <= 0.0:
			glance_cd = rng.randf_range(10.0, 18.0)
			var cam := get_viewport().get_camera_3d()
			if cam:
				c.look_head_at(cam.global_position)
				get_tree().create_timer(rng.randf_range(1.4, 2.4)).timeout.connect(func(): if is_instance_valid(c): c.look_head_at(null))
		# planned ending: a musical close (or a short fade at a bar line)
		if not ending_started and mt >= float(seg.end) - maxf(float(seg.fade), 4.0 * beat_len * 2.0):
			ending_started = true
			active.stage = "ending"
			if main.director:
				main.director.performance_finale()
			if float(seg.fade) > 0.0:
				var tw := create_tween()
				tw.tween_interval(maxf(0.0, float(seg.end) - mt - float(seg.fade)))
				tw.tween_property(player, "volume_db", -40.0, float(seg.fade))
		if mt >= float(seg.end) or elapsed_total > minf(total, float(cfg.limits.max_total_s) - 2.0):
			break
	# stop: let the clip settle back to idle, close the mouth
	var interrupted := _abort != ""
	if player.playing:
		var tw2 := create_tween()
		tw2.tween_property(player, "volume_db", -40.0, 0.8 if interrupted else 0.25)
		await tw2.finished
		player.stop()
	_bus_levels(false)
	c.set_expression("aa", 0.0)
	_free_fx()
	c.end_gesture()
	c.set_gesture_speed(1.0)
	c.set_hair_frame("")
	if c2:
		c2.set_hair_frame("")
		c2.end_gesture()
		c2.set_gesture_speed(1.0)
		c2.set_expression("happy", 0.0)
	var music_played := (Time.get_ticks_msec() - t_music0) / 1000.0
	if mode == "special" and not interrupted:
		c.play_gesture("waving" if rng.randf() < 0.5 else "spell_casting", 0.3, 0.5)
		_venue_fx(c, false)
		await get_tree().create_timer(1.2).timeout
	c.set_expression("happy", 0.0)
	active.stage = "closing"
	var outro := _line(who, "perform_outro_" + ("interrupted" if interrupted else mode), music)
	# the closing remark only if it fits inside the hard cap (estimated speaking time ~2.6 words/s + margin)
	var left := float(cfg.limits.max_total_s) - (Time.get_ticks_msec() - t_start) / 1000.0
	if outro != "" and (interrupted or left > outro.split(" ").size() / 2.6 + 1.0):
		await main.voice.say(voice_id, outro)
	var res := {"ok": not interrupted, "who": who, "mode": mode, "song": song, "planned_total": snappedf(total, 0.1),
		"actual_total": snappedf((Time.get_ticks_msec() - t_start) / 1000.0, 0.1), "intro_s": snappedf(intro_s, 0.1),
		"music_s": snappedf(music_played, 0.1), "segment": seg, "ending": "interrupted: " + _abort if interrupted else String(seg.ending),
		"clips": active.clips, "singing": sing, "preview": preview, "partner": partner if c2 else "", "detail": ("performed %s" % active.title) if not interrupted else ("stopped: " + _abort)}
	var out := _finish(c, brain, dir_was, res, t_start)
	if b2:
		b2.hold = false               # only now: the duet is already in her memory, so she does not dance again at once
	return out


var _saved_bus := {}


func _bus_levels(on: bool) -> void:
	var want := {"Music": float(cfg.mix.get("music_bus_db", -3.0)), "Ambience": float(cfg.mix.get("ambience_bus_db", -24.0))}
	for b in want:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		if on:
			if not _saved_bus.has(b):
				_saved_bus[b] = AudioServer.get_bus_volume_db(i)
			AudioServer.set_bus_volume_db(i, want[b])
		elif _saved_bus.has(b):
			AudioServer.set_bus_volume_db(i, float(_saved_bus[b]))
	if not on:
		_saved_bus.clear()


func _finish(c: WorldCharacter, brain, dir_was: bool, res: Dictionary, _t0: int) -> Dictionary:
	_bus_levels(false)
	if main.director and bool(active.get("filmed", true)):
		main.director.end_performance()
		main.director.enabled = dir_was
	var who := String(res.get("who", active.get("who", "")))
	if not bool(res.get("preview", true)) and who != "":
		_remember(who, res)
		if String(res.get("partner", "")) != "":
			_remember(String(res.partner), res)
	active = {}
	log.append(res)
	if log.size() > 30:
		log.pop_front()
	ended.emit(res)
	return res


## Her own performance memory: history, familiarity (practice), favourites. Never shared; no XP.
func _remember(who: String, res: Dictionary) -> void:
	var m := WorldState.mind(who)
	var mu := m.music
	var hist: Array = mu.get_or_add("history", [])
	hist.append({"song": res.song, "mode": res.mode, "unix": int(Time.get_unix_time_from_system()), "planned_total": res.planned_total,
		"actual_total": res.actual_total, "music_s": res.music_s, "ending": res.ending, "clips": res.clips, "singing": res.singing, "completed": res.ok})
	if hist.size() > 60:
		hist.pop_front()
	var fam: Dictionary = mu.get_or_add("familiarity", {})
	var gain := 0.1 * clampf(float(res.music_s) / 60.0, 0.0, 1.0) * (1.0 if res.ok else 0.3)
	fam[res.song] = snappedf(float(fam.get(res.song, 0.0)) + gain, 0.001)
	var dfam: Dictionary = mu.get_or_add("dance_familiarity", {})
	for clip in res.clips:
		dfam[clip] = snappedf(float(dfam.get(clip, 0.0)) + gain / maxf(res.clips.size(), 1), 0.001)
	# a favourite is a song she has completed at least three times and knows well
	var favs: Array = mu.get_or_add("favorites", [])
	var done := hist.filter(func(h): return h.song == res.song and h.completed).size()
	if done >= 3 and float(fam[res.song]) >= 0.25 and not favs.has(res.song):
		favs.append(res.song)
	mu["last_unix"] = int(Time.get_unix_time_from_system())
	WorldState.record_activity({"id": "perform:" + res.song, "verb": "perform", "label": "Danced to %s" % MusicLibrary.song(res.song).get("title", res.song), "mode": res.mode},
		{"knowledge": {"song:" + res.song: 1}}, who)


func interrupt(reason: String) -> void:
	if busy():
		_abort = reason


# ------------------------------------------------------------------ dance
## Dance order for this performance: her familiar clips first, then the rest, without repeating the
## previous performance's opening clip when there is a choice.
func _dance_order(who: String, mode: String) -> Array:
	var pool: Array = cfg.performers.get(who, {}).get("dances", cfg.dances.keys())
	var dfam: Dictionary = WorldState.mind(who).music.get("dance_familiarity", {})
	var hist: Array = WorldState.mind(who).music.get("history", [])
	var last_first := String(hist[-1].clips[0]) if not hist.is_empty() and not (hist[-1].get("clips", []) as Array).is_empty() else ""
	var key := {}
	for d in pool:
		key[d] = float(dfam.get(d, 0.0)) + rng.randf() * 0.2      # computed once: a comparator must be consistent
	var order := pool.duplicate()
	order.sort_custom(func(a, b): return float(key[a]) > float(key[b]))
	if order.size() > 1 and order[0] == last_first:
		order.push_back(order.pop_front())
	return order


## Play a looping dance clip, tempo-matched to the song: the clip's own bob period (measured from its hips)
## is scaled to the nearest whole-number multiple of the song's beat, within 0.8x..1.25x.
func _start_clip(c: WorldCharacter, clip: String, beat_len: float) -> void:
	var period := _period(c, clip)
	var speed := 1.0
	if period > 0.0:
		var best := 1.0
		var best_err := 1e9
		for mult in [0.5, 1.0, 2.0]:
			var s: float = period / (beat_len * float(mult))
			if s >= 0.8 and s <= 1.25 and absf(s - 1.0) < best_err:
				best_err = absf(s - 1.0)
				best = s
		speed = best
	c.play_gesture(clip, 0.5, 0.6)
	c.set_gesture_speed(speed)
	if active:
		active["speed"] = snappedf(speed, 0.01)


func _period(c: WorldCharacter, clip: String) -> float:
	if _clip_period.has(clip):
		return _clip_period[clip]
	var p := 0.0
	var anim: Animation = c.body_player.get_animation("mx/" + clip) if c.body_player.has_animation("mx/" + clip) else null
	if anim:
		for ti in anim.get_track_count():
			if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D and String(anim.track_get_path(ti)).ends_with(":Hips"):
				var n := 240
				var ys := PackedFloat32Array()
				for k in n:
					ys.append((anim.position_track_interpolate(ti, anim.length * k / n) as Vector3).y)
				var mean := 0.0
				for v in ys:
					mean += v
				mean /= n
				var best_lag := 0
				var best_v := -1e9
				for lag in range(int(n * 0.25 / anim.length) + 1, int(n * 1.5 / anim.length)):
					var acc := 0.0
					for k in n - lag:
						acc += (ys[k] - mean) * (ys[k + lag] - mean)
					if acc > best_v:
						best_v = acc
						best_lag = lag
				p = anim.length * best_lag / n if best_lag > 0 else 0.0
				break
	_clip_period[clip] = p
	return p


# ------------------------------------------------------------------ effects (subtle, budgeted)
## Two small one-shot emitters attached to her hands (and one at her feet for special performances), created
## once per performance and restarted on beats: no per-beat node creation, bounded particle counts.
func _make_fx(c: WorldCharacter, mode: String) -> void:
	_free_fx()
	if String(RenderProfile.options.get("music-fx", "on")) == "off":
		return
	var pal := String(cfg.performers.get(c.character_id, {}).get("fx_palette", "arcane"))
	for side in ["r"]:
		var p := FX.particles(6 if mode == "casual" else 10, 0.6, FX.pm_motes(pal, "burst"), FX.mote_mesh(0.03))
		p.one_shot = true
		p.explosiveness = 0.9
		p.emitting = false
		(c.left_hand if side == "l" else c.right_hand).add_child(p)
		_fx[side] = p
	if mode == "special":
		var f := FX.particles(14, 1.0, FX.pm_motes(pal, "rise"), FX.mote_mesh(0.035))
		f.one_shot = true
		f.explosiveness = 0.8
		f.emitting = false
		c.add_child(f)
		f.position = Vector3(0, 0.1, 0)
		_fx["feet"] = f


func _free_fx() -> void:
	for k in _fx:
		if is_instance_valid(_fx[k]):
			(_fx[k] as Node).queue_free()
	_fx.clear()


func _beat_fx(_c: WorldCharacter, mode: String, strong: bool) -> void:
	var side := "r"
	if _fx.has(side) and is_instance_valid(_fx[side]):
		(_fx[side] as GPUParticles3D).restart()
	if strong and mode == "special" and _fx.has("feet") and is_instance_valid(_fx.feet):
		(_fx.feet as GPUParticles3D).restart()


func _venue_fx(c: WorldCharacter, opening: bool) -> void:
	var pal := String(cfg.performers.get(c.character_id, {}).get("fx_palette", "arcane"))
	ImpactFX.shockwave(c.get_parent(), c.global_position + Vector3(0, 0.05, 0), FX.palette(pal)[0], 2.6 if opening else 3.4)


# ------------------------------------------------------------------ remarks (cheap, varied, no LLM)
func _line(who: String, key: String, music: Dictionary) -> String:
	var lines: Array = cfg.performers.get(who, {}).get("lines", {}).get(key, [])
	if lines.is_empty():
		return ""
	var used: Array = music.get_or_add("recent_lines", [])
	var fresh := lines.filter(func(l): return not used.has(l))
	var pick: String = (fresh if not fresh.is_empty() else lines)[rng.randi() % (fresh if not fresh.is_empty() else lines).size()]
	used.append(pick)
	if used.size() > 6:
		used.pop_front()
	return pick


func describe() -> Dictionary:
	var d := active.duplicate()
	if not d.is_empty():
		d["music_time"] = snappedf(music_time(), 0.01)
		d["volume_db"] = snappedf(player.volume_db, 0.1)
	return {"active": d, "recent": log.slice(maxi(0, log.size() - 3))}
