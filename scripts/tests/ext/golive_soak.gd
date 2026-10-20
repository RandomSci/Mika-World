extends RefCounted
## --mktest=golive_soak (2026-10-20, Selwyn: "a quick test of 30 minutes that includes a trip to the lake and the dance,
## then tell me stops, restarts, memory and fps"): the go live build (fights and transformations off) left to its own
## life in the stream profile, from the evening into the night. Watches only, except what the show would send over the
## live link: viewers' chat (chat cards, Luna answering when addressed, a lantern wish), a subscriber, and the show's
## dance request. The trip to the lake is theirs (the planner's night walk and the boat ritual); if they have not gone
## by minute 12 the longing for the lake is raised, as missed nights raise it in play.
## Every 10 s: fps, the worst frame, static and video memory, area, both activities. Checks that nothing fight related
## appeared (no creature, no duel, no transformation). Marks "[golive] ...".

const CHAT := [["Kai", "hi Mika! what are you doing tonight?"], ["Rin", "Luna, do you like the lake at night?"],
	["Mo", "I wish my exam goes well tomorrow"], ["Ana", "what clue did you find today?"], ["Tom", "Luna what is your favourite star?"],
	["Zed", "this place is so pretty"], ["Lia", "Mika can you dance for us later?"], ["Bo", "I wish my cat gets better"]]


static func run(t) -> void:
	var main = t.main
	var mins := float(RenderProfile.options.get("soak-min", "30"))
	main.day_night.clear_override()
	WorldState.world_min = (WorldState.day() - 1) * 1440.0 + float(RenderProfile.options.get("soak-start", "20.0")) * 60.0
	main.director.enabled = true
	var mb: SanctuaryBrain = main.mage_brains["mika"]
	print("[golive] start: fights %s transformations %s, spawner enabled %s, %d min, clock %s" % [StreamFlags.fights(), StreamFlags.transformations(),
		main.spawner.enabled, mins, WorldState.clock_text()])
	# who is who in the review frames: a still with only Mika shown, then only Luna (same camera)
	var shot_dir0 := String(RenderProfile.options.get("shots", ""))
	if shot_dir0 != "":
		for who in ["mika", "luna"]:
			for w2 in ["mika", "luna"]:
				(main.characters[w2] as Node3D).visible = (w2 == who)
			await t.get_tree().process_frame
			await t.get_tree().process_frame
			var im: Image = t.get_viewport().get_texture().get_image()
			im.resize(960, 540, Image.INTERPOLATE_BILINEAR)
			im.save_jpg("%s/only_%s.jpg" % [shot_dir0, who], 0.85)
		for w2 in ["mika", "luna"]:
			(main.characters[w2] as Node3D).visible = true
	var t0: float = t._game_t
	var next_s := 0.0
	var worst := 0.0
	var frames := 0
	var acc := 0.0
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var vmem0 := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var samples := []
	var areas := {}
	var kinds := {}
	var chat_i := 0
	var next_chat := 60.0
	var danced := false
	var dance_res := {}
	var lake_push := false
	var subscribed := false
	var monsters_seen := 0
	var lake_at := -1.0
	var slow := 0
	var lake_who := false
	var tiny := 0                     # samples with Mika on screen but under a tenth of its height
	var lake_next := 0.0
	var off_cam := 0                  # samples with the camera on someone other than Mika
	var lone_music := 0               # samples with a song playing and no dancer dancing
	var shots := 0
	var shot_dir := String(RenderProfile.options.get("shots", ""))
	var next_shot := 0.0
	var cb := func(d): kinds[String(d.get("kind", ""))] = int(kinds.get(String(d.get("kind", "")), 0)) + 1
	mb.decided.connect(cb)
	var last_t := Time.get_ticks_usec()
	while t._game_t - t0 < mins * 60.0:
		await t.get_tree().process_frame
		var now_us := Time.get_ticks_usec()
		var dt := (now_us - last_t) / 1000.0
		last_t = now_us
		frames += 1
		acc += dt
		worst = maxf(worst, dt)
		if dt > 100.0:
			slow += 1
			print("[golive] slow frame %d ms at %.1fs, travel %s, area %s | mika: %s | luna: %s" % [int(dt), t._game_t - t0, main.streaming.state, main.streaming.current_id,
				String(mb.current.get("key", "-")), String(main.mage_brains.luna.current.get("key", "-"))])
		var el: float = t._game_t - t0
		# the show's side: chat, a subscriber, the dance request
		if el >= next_chat and main.live_link:
			next_chat += 75.0
			var c: Array = CHAT[chat_i % CHAT.size()]
			chat_i += 1
			main.live_link._on_message({"type": "youtube-live-selected-message", "active": true, "author": c[0], "message": c[1]})
			print("[golive] %4.0fs chat %s: %s" % [el, c[0], c[1]])
		if not subscribed and el >= 420.0 and main.live_link:
			subscribed = true
			main.live_link._on_message({"type": "youtube-live-subscriber", "author": "NightOwl"})
			print("[golive] %4.0fs subscriber NightOwl" % el)
		if el >= 60.0 and el >= lake_next and lake_at < 0.0 and main.streaming.current_id != "lantern_lake":
			lake_push = true
			lake_next = el + 60.0               # again each minute until they are there (a walk can fail: a stuck gate)
			mb.mind.knowledge["lake_night"] = SanctuaryBrain.night_id() - 3
			print("[golive] %4.0fs the lake's longing raised (they had not gone yet)" % el)
		if main.streaming.current_id == "lantern_lake" and lake_at < 0.0:
			lake_at = el
		# who is who at the lake (its night light makes both look violet): only Mika, then only Luna, 6 s after arriving
		if lake_at >= 0.0 and not lake_who and el - lake_at > 6.0 and shot_dir != "":
			lake_who = true
			for who in ["mika", "luna"]:
				for w2 in ["mika", "luna"]:
					(main.characters[w2] as Node3D).visible = (w2 == who)
				await t.get_tree().process_frame
				await t.get_tree().process_frame
				var im2: Image = t.get_viewport().get_texture().get_image()
				im2.resize(960, 540, Image.INTERPOLATE_BILINEAR)
				im2.save_jpg("%s/lake_only_%s.jpg" % [shot_dir, who], 0.85)
			for w2 in ["mika", "luna"]:
				(main.characters[w2] as Node3D).visible = true
			last_t = Time.get_ticks_usec()
		# the show's dance at the lake (a minute after they arrive), or wherever they are by minute 21
		if not danced and main.live_link and ((lake_at >= 0.0 and el - lake_at >= 60.0 and main.streaming.current_id == "lantern_lake") or el >= 1260.0):
			danced = true
			print("[golive] %4.0fs the show asks for a dance (in %s)" % [el, main.streaming.current_id])
			main.live_link._on_message({"type": "lifestyle-action", "id": "golive-dance", "action": "dance_session", "args": {"routine": ""}})
		if el >= next_s:
			next_s += 10.0
			var fps := frames / maxf(acc / 1000.0, 0.001)
			var mem := Performance.get_monitor(Performance.MEMORY_STATIC)
			var vmem := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
			var area := String(main.streaming.current_id)
			var subj := String(main.director.mika.character_id) if main.director and main.director.mika else "-"
			var music: bool = main.performance != null and main.performance.player.playing
			var pstage := String(main.performance.active.get("stage", "")) if main.performance else ""
			# what the viewer really sees: Mika's head in the picture, nobody between the lens and her, and not a speck
			var vcam: Camera3D = t.get_viewport().get_camera_3d()
			var mk: WorldCharacter = main.characters["mika"]
			if main.streaming.state == "idle" and mk.visible and vcam:
				var mhead := mk.global_position + Vector3(0, 1.35, 0)
				var vs: Vector2 = t.get_viewport().get_visible_rect().size
				var on: bool = not vcam.is_position_behind(mhead) and Rect2(Vector2.ZERO, vs).has_point(vcam.unproject_position(mhead))
				var blk: bool = main.director._mate_blocks(vcam.global_position, mhead)
				if not on or blk:
					off_cam += 1
					subj = "NOT-MIKA(%s %s, cam %.1f m from her)" % [String(main.director.mode), "off-screen" if not on else "behind Luna",
						vcam.global_position.distance_to(mhead)]
					if shot_dir != "":
						var im3: Image = t.get_viewport().get_texture().get_image()
						im3.resize(640, 360, Image.INTERPOLATE_BILINEAR)
						im3.save_jpg("%s/notmika_%05d.jpg" % [shot_dir, int(el)], 0.8)
				elif absf(vcam.unproject_position(mk.global_position).y - vcam.unproject_position(mhead + Vector3(0, 0.25, 0)).y) < vs.y * 0.1:
					tiny += 1
					subj = "mika-tiny"
			if music and pstage != "dancing" and pstage != "ending":
				lone_music += 1
			areas[area] = int(areas.get(area, 0)) + 1
			monsters_seen = maxi(monsters_seen, main.spawner.alive.size() if main.spawner.get("alive") != null else 0)
			samples.append({"t": snappedf(el, 1.0), "fps": snappedf(fps, 0.1), "worst_ms": snappedf(worst, 0.1), "mem_mb": snappedf(mem / 1048576.0, 1.0),
				"vmem_mb": snappedf(vmem / 1048576.0, 1.0), "area": area, "cam": subj, "music": music, "perf": pstage})
			print("[golive] %4.0fs %s %s fps %.1f worst %.0f ms mem %.0f MB vmem %.0f MB cam %s music %s %s | mika: %s | luna: %s" % [el, WorldState.clock_text().right(5), area, fps, worst,
				mem / 1048576.0, vmem / 1048576.0, subj, "on" if music else "off", pstage, String(mb.current.get("label", "-")).left(48), String(main.mage_brains.luna.current.get("label", "-")).left(48)])
			frames = 0
			acc = 0.0
			worst = 0.0
		# review frames (small jpgs): every 20 s, every 2 s at the lake and while a song plays
		if shot_dir != "" and el >= next_shot and main.streaming.state == "idle":
			var dense: bool = main.streaming.current_id == "lantern_lake" or (main.performance and main.performance.busy())
			next_shot = el + (2.0 if dense else 20.0)
			var img: Image = t.get_viewport().get_texture().get_image()
			img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
			img.save_jpg("%s/f_%05d.jpg" % [shot_dir, int(el * 10.0)], 0.8)
			shots += 1
	# the report
	var fps_all := samples.map(func(s): return float(s.fps))
	fps_all.sort()
	var worst_all: float = samples.reduce(func(a, s): return maxf(a, float(s.worst_ms)), 0.0)
	var mem_end := Performance.get_monitor(Performance.MEMORY_STATIC)
	var growth := (mem_end - mem0) / maxf(mem0, 1.0) * 100.0
	var perf_log: Array = main.performance.log if main.performance else []
	print("[golive] report fps median %.1f min %.1f, worst frame %.0f ms, memory %.0f -> %.0f MB (%+.1f%%), vmem %.0f -> %.0f MB" % [fps_all[fps_all.size() / 2],
		fps_all[0], worst_all, mem0 / 1048576.0, mem_end / 1048576.0, growth, vmem0 / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	print("[golive] areas %s" % JSON.stringify(areas))
	print("[golive] kinds %s" % JSON.stringify(kinds))
	print("[golive] dances %s" % JSON.stringify(perf_log.map(func(e): return {"who": e.get("who", ""), "ok": e.get("ok", false), "clips": e.get("clips", []),
		"detail": e.get("detail", ""), "partner": e.get("partner", "")})))
	print("[golive] slow frames over 100 ms %d, Mika tiny in %d samples" % [slow, tiny])
	print("[golive] lake: night %s, rituals %s" % [str(mb.mind.knowledge.get("lake_night", -1)), str(mb.mind.activity_counts.get("lakeboat", {}))])
	print("[golive] fights: creatures seen %d, duel %s, transformation %s" % [monsters_seen, str(FightHook.running), str(main.transformer.playing if main.transformer else "")])
	t._check(areas.has("lantern_lake"), "they went to Lantern Lake (%s)" % str(areas.keys()))
	t._check(perf_log.any(func(e): return bool(e.get("ok", false))), "the show's dance played")
	print("[golive] camera off Mika in %d samples, a song with nobody dancing in %d samples, %d review frames" % [off_cam, lone_music, shots])
	t._check(monsters_seen == 0, "no creature appeared")
	t._check(off_cam == 0, "the camera stayed on Mika (%d samples off)" % off_cam)
	t._check(lone_music == 0, "no song without a dancer (%d samples)" % lone_music)
	t._check(fps_all[fps_all.size() / 2] >= 29.0, "fps median %.1f" % fps_all[fps_all.size() / 2])
	t._check(growth < 10.0, "memory growth %.1f%%" % growth)
