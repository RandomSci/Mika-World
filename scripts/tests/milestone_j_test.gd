class_name MilestoneJTest
extends Node
## --mjtest=<mode>: Milestone J checks. Disposable saves only (user://test_regress_*.json); windowed runs
## also save screenshots to screenshots/mjtest/ (and can be recorded with Godot's --write-movie).
##   encounter  --who=mika --kind=emberwing|hollow_sentinel: a real fight through her own planner: the
##              creature telegraphs (windup -> strike -> recover), she makes tactical choices, dodges for
##              real, reacts when struck; the camera frames the fight (Mika-first); stats + FPS
##   signature  --who=mika: a signature cast (fixture: mastery at Adept in the DISPOSABLE save) at a creature:
##              validated, stronger, camera beats follow the cast phases, cooldown + first-use memory
##   awaken     --who=mika|luna: the full first awakening as a PREVIEW (no progress change): 10-12 s,
##              five stages reached in order (cover -> swap hidden -> reveal -> orbit lock -> pose)
##   policy     the stream camera stays with Mika while Luna lives her own life (incl. performing alone);
##              an explicit developer focus is respected and released back to Mika
##   voices     Mika / Luna speak through their confirmed Edge voices (fallback reported honestly);
##              Latin incantations use Kokoro IPA; laugh tokens become a reaction, never spoken text
##   aftermath  after a fight: music performance and dialogue still work (no stuck camera / audio)

var main: Node
var mode := ""
var checks: Array = []
var failed := false
var report := {}
var dir := ""
var _frame_ms: Array = []


func _ready() -> void:
	mode = String(RenderProfile.options.get("mjtest", ""))
	dir = RenderProfile.shots_dir + "/mjtest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_run.call_deferred()


var _game_t := 0.0


func _process(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	_game_t += delta


## Game-time milliseconds (identical in real time and in Movie Maker's fixed-step recording).
func _gms() -> int:
	return int(_game_t * 1000.0)


func _check(ok: bool, what: String, detail = "") -> void:
	checks.append({"ok": ok, "check": what, "detail": str(detail).left(400)})
	print("[mjtest]   %s %s %s" % ["ok  " if ok else "FAIL", what, ("(" + str(detail).left(220) + ")") if str(detail) != "" else ""])
	if not ok:
		failed = true


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless" or RenderProfile.options.has("noshots"):
		return
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png("%s/%s_%s.png" % [dir, mode, tag])


func _run() -> void:
	main.player.enabled = false
	main.player.set_process_unhandled_input(false)
	main.set_process_unhandled_input(false)
	if main.hud:
		main.hud.visible = false          # developer text off: the frames should look like the stream
	print("[mjtest] mode=%s save=%s persistent=%s mages=%s" % [mode, WorldState.save_path, WorldState.persistent, main.mages])
	if not WorldState.save_path.begins_with("user://test_regress_"):
		_check(false, "refusing to run: tests need a disposable user://test_regress_*.json save", WorldState.save_path)
		_finish()
		return
	await _wait(2.5)
	_frame_ms.clear()
	match mode:
		"encounter": await _encounter()
		"signature": await _signature()
		"awaken": await _awaken()
		"policy": await _policy()
		"voices": await _voices()
		"aftermath": await _aftermath()
		_: _check(false, "unknown mode " + mode)
	_finish()


func _fps_stats() -> Dictionary:
	if _frame_ms.is_empty():
		return {}
	var s: Array = _frame_ms.duplicate()
	s.sort()
	var total := 0.0
	for x in s:
		total += float(x)
	var hitches := s.filter(func(x): return float(x) > 50.0).size()
	return {"frames": s.size(), "avg_fps": snappedf(1000.0 * s.size() / maxf(total, 1.0), 0.1), "p50_ms": snappedf(float(s[s.size() / 2]), 0.1),
		"p95_ms": snappedf(float(s[int(s.size() * 0.95)]), 0.1), "p99_ms": snappedf(float(s[int(s.size() * 0.99)]), 0.1),
		"worst_ms": snappedf(float(s[s.size() - 1]), 0.1), "hitches_over_50ms": hitches}


func _finish() -> void:
	report["fps"] = _fps_stats()
	var f := FileAccess.open("%s/%s.json" % [dir, mode], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"mode": mode, "passed": not failed, "checks": checks, "report": report}, "  "))
		f.close()
	print("[mjtest] fps ", JSON.stringify(report.fps))
	print("[mjtest] %s %s" % ["FAIL" if failed else "PASS", mode])
	get_tree().quit(1 if failed else 0)


func _hold(b: SanctuaryBrain) -> void:
	b.hold = true
	var t0 := _gms()
	while not b.current.is_empty() and _gms() - t0 < 40000:
		await get_tree().process_frame


func _hold_all() -> void:
	for w in main.mage_brains:
		await _hold(main.mage_brains[w])


## Stand the mage outside the ward (east, training grounds) and spawn the creature `d` m in front of her.
func _stage_fight(who: String, kind: String, d: float) -> Monster:
	var c: WorldCharacter = main.characters[who]
	var map: RID = c.get_world_3d().navigation_map
	c.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(27, 0, 4)) + Vector3(0, 0.1, 0)
	c.rotation.y = atan2(-1.0, 0.0)            # facing +X (out toward the wild edge)
	for old in main.spawner.alive:
		if is_instance_valid(old):
			old.queue_free()
	await _wait(0.6)
	var at := NavigationServer3D.map_get_closest_point(map, c.global_position + Vector3(d, 0, 1.0))
	var mon: Monster = main.spawner.spawn(kind, at)
	return mon


## The other mage waits inside the ward (creatures never cross it): a one-on-one test fight.
func _park_others(who: String) -> void:
	for w in main.characters:
		if w != who and main.characters[w].visible:
			var oc: WorldCharacter = main.characters[w]
			oc.global_position = NavigationServer3D.map_get_closest_point(oc.get_world_3d().navigation_map, Vector3(-3, 0, 2)) + Vector3(0, 0.1, 0)


# ------------------------------------------------------------------ encounter
func _encounter() -> void:
	var who := String(RenderProfile.options.get("who", "mika"))
	var kind := String(RenderProfile.options.get("kind", "emberwing"))
	var c: WorldCharacter = main.characters[who]
	var b: SanctuaryBrain = main.mage_brains[who]
	await _hold_all()
	await main.focus_mage(who)
	if main.director:
		main.director.enabled = true
	var mind := WorldState.mind(who)
	mind.vigor = 1.0
	_park_others(who)
	var mon := await _stage_fight(who, kind, 10.0)
	_check(mon != null and mon.creature != null, "a %s appeared with its animated body" % kind, mon.creature.get_class() if mon and mon.creature else "none")
	if mon == null:
		return
	await _wait(1.2)
	var opts := b.options().filter(func(o): return o.kind == "hunt" and o.monster == mon.id)
	_check(not opts.is_empty(), "%s can see it and her planner offers the fight" % who)
	if opts.is_empty():
		return
	var states := {}
	var seq: Array = []
	var hazards := {}
	var cam_modes := {}
	var stance_frames := 0
	var fight_frames := 0
	var focus_ok := 0
	var shots := {}
	var hp_prev := mon.hp
	var reacted := false
	var dodge_frames := 0
	var alive_frames := 0
	var combat_alive := 0
	var hit_reactions := 0
	var last_hit_t := -1.0
	var box := {"done": false, "res": {}}           # lambdas capture locals by value: share through a dictionary
	var scored: Dictionary = opts[0].merged(b.score(opts[0]))
	b.hold = true                                  # planner stays held: the test runs this one activity
	var runner := func():
		box.res = await b.run_activity(scored)
		box.done = true
	runner.call()
	var t0 := _gms()
	while not box.done and _gms() - t0 < 120000:
		await get_tree().process_frame
		fight_frames += 1
		if is_instance_valid(mon):
			report["state_history"] = mon.state_history.duplicate()
			states[mon.mstate] = int(states.get(mon.mstate, 0)) + 1
			if seq.is_empty() or seq[seq.size() - 1] != mon.mstate:
				seq.append(mon.mstate)
			if mon.hp < hp_prev:
				hp_prev = mon.hp
				reacted = true
				if not shots.has("creature_hit"):
					shots.creature_hit = true
					await _wait(0.12)
					_shot("creature_hit")
		for h in AttackHazard.active(main.world):
			var hz := h as AttackHazard
			var key := str(hz.get_instance_id())
			if not hazards.has(key):
				hazards[key] = hz.kind
				if hz.kind != "projectile" and not shots.has("telegraph"):
					shots.telegraph = true
					await _wait(0.35)
					_shot("telegraph")
				elif hz.kind == "projectile" and not shots.has("bolt"):
					shots.bolt = true
					await _wait(0.15)
					_shot("bolt_in_flight")
		if c.current_action == "dodge":
			dodge_frames += 1
			if dodge_frames == 8:
				_shot("dodge")
		if c.last_hit.has("t") and float(c.last_hit.t) != last_hit_t:
			last_hit_t = float(c.last_hit.t)
			hit_reactions += 1
			if not shots.has("mage_hit"):
				shots.mage_hit = true
				await _wait(0.15)
				_shot("mage_hit")
		if c.combat_stance:
			stance_frames += 1
		if is_instance_valid(mon) and mon.alive():
			alive_frames += 1
			if main.director and main.director.mode in ["combat", "signature"]:
				combat_alive += 1
		if main.director:
			cam_modes[main.director.mode] = int(cam_modes.get(main.director.mode, 0)) + 1
		if main.focus == who:
			focus_ok += 1
		if fight_frames % 150 == 75:
			_shot("fight_%03d" % (fight_frames / 150))
	var done: bool = box.done
	var res: Dictionary = box.res
	await _wait(1.5)
	_shot("after")
	report["planner_stage_at_end"] = b.current.duplicate() if not b.current.is_empty() else {}
	report["mage_action_at_end"] = [c.current_action, c.casting, c.action_detail]
	var tac: Dictionary = res.get("tactics", {})
	report["result"] = res
	report["creature_states"] = states
	report["creature_sequence"] = seq.slice(0, 60)
	report["hazards"] = hazards.values()
	report["camera_modes"] = cam_modes
	report["tactics_log"] = b.tactics_log.slice(maxi(0, b.tactics_log.size() - 30))
	report["hit_reactions"] = hit_reactions
	report["seconds"] = (_gms() - t0) / 1000.0
	report["spawner"] = main.spawner.describe()
	_check(done, "the fight came to an end", report.seconds)
	_check(states.has("windup") and states.has("strike"), "the creature telegraphed and executed attacks (windup -> strike)", states)
	if kind == "hollow_sentinel":
		_check(states.has("recover"), "the sentinel had a recovery window after a heavy attack", states)
		_check(hazards.values().has("area"), "its slam marked the ground before landing", hazards.values())
	if kind == "emberwing":
		_check(hazards.values().has("projectile"), "it spat real ember bolts (projectiles in flight)", hazards.values())
	var all_states: Array = (report.get("state_history", []) as Array).map(func(e): return e[1])
	_check(all_states.has("alert"), "it reacted on noticing her (alert)", all_states.slice(0, 6))
	_check(reacted, "spells landed and the creature reacted (hit / stagger)")
	_check(int(tac.get("dodges", 0)) >= 1, "she dodged at least once (real movement)", tac)
	_check(int(tac.get("dodged", 0)) >= 1, "at least one dodge really avoided the blow", tac)
	_check(tac.get("intents", {}).size() >= 3, "she used several tactical intentions", tac.get("intents", {}))
	_check(stance_frames > alive_frames * 0.6, "combat stance during the fight", [stance_frames, alive_frames])
	_check(combat_alive > alive_frames * 0.7, "the camera framed the fight while it lasted (combat / signature shots)", [combat_alive, alive_frames, cam_modes])
	_check(focus_ok == fight_frames, "the camera followed %s the whole fight" % who, [focus_ok, fight_frames])
	_check(not c.combat_stance, "back to her normal stance afterwards")


# ------------------------------------------------------------------ signature
func _signature() -> void:
	var who := String(RenderProfile.options.get("who", "mika"))
	var c: WorldCharacter = main.characters[who]
	await _hold_all()
	await main.focus_mage(who)
	main.director.enabled = true
	var sid := SignatureCast.spell_for(who)
	var mind := WorldState.mind(who)
	var m0 := float(mind.skills.get(sid, 0.0))
	_park_others(who)
	var mon := await _stage_fight(who, "emberwing", 8.0)
	_check(mon != null, "a creature to aim at")
	if mon == null:
		return
	mon.set_physics_process(false)              # it holds still for this cinematic test
	await _wait(0.8)
	# honest refusal first if she has not mastered it
	if m0 < 1.5:
		var chk := SignatureCast.can(main, who, mon)
		_check(not chk.ok, "refused before Adept mastery (nothing is granted)", chk)
	# fixture (DISPOSABLE save only): she has reached Adept with her signature spell
	mind.skills[sid] = maxf(m0, 1.55)
	mind.vigor = 1.0
	var c_chk := SignatureCast.can(main, who, mon)
	_check(c_chk.ok, "allowed once mastered", c_chk)
	var beats := []
	var beat_t := {}
	var hp0 := mon.hp
	var box := {"done": false, "res": {}}
	var t0 := _gms()
	var runner := func():
		box.res = await SignatureCast.perform(main, c, mon)
		box.done = true
	runner.call()
	while not box.done and _gms() - t0 < 20000:
		await get_tree().process_frame
		var bt: String = String(main.director._sig.get("beat", "")) if not main.director._sig.is_empty() else ""
		if bt != "" and (beats.is_empty() or beats[beats.size() - 1] != bt):
			beats.append(bt)
			beat_t[bt] = snappedf((_gms() - t0) / 1000.0, 0.01)
			await _wait(0.45 if bt != "impact" else 0.25)
			_shot("beat_%s" % bt)
	var res: Dictionary = box.res
	await _wait(1.5)
	_shot("after")
	report["result"] = res
	report["beats"] = beats
	report["beat_t"] = beat_t
	report["damage"] = snappedf(hp0 - (mon.hp if is_instance_valid(mon) else 0.0), 0.1)
	report["seconds"] = (_gms() - t0) / 1000.0
	_check(res.get("ok", false) and res.get("signature", false), "the signature cast resolved through the spell pipeline", res.get("outcome", ""))
	_check(res.get("outcome", "") == "hit", "it hit the creature", res.get("outcome", ""))
	_check(beats.size() >= 3 and beats[0] == "awaken" and beats.has("release"), "camera beats followed the cast (stance -> build-up -> release -> impact)", beats)
	_check(float(report.seconds) < 9.0, "a short cinematic (does not stop the stream)", report.seconds)
	var again := SignatureCast.can(main, who, mon) if is_instance_valid(mon) and mon.alive() else {"ok": false, "reason": "cooling down (creature gone)"}
	_check(not again.ok, "cooldown after use", again)
	_check(mind.knowledge.has("signature:" + sid), "her first signature cast is in her memory")
	_check(main.director.mode != "signature", "the camera left the signature shots afterwards", main.director.mode)


# ------------------------------------------------------------------ awakening
func _awaken() -> void:
	var who := String(RenderProfile.options.get("who", "mika"))
	var c: WorldCharacter = main.characters[who]
	await _hold_all()
	await main.focus_mage(who)
	var m := WorldState.mind(who)
	var before := {"xp": m.progress.xp, "level": m.level(), "appearance": TransformationDirector.appearance(who), "know": m.knowledge.size()}
	var base := c.avatar_path
	var v: Dictionary = TransformationDirector.data.versions.full
	var st: Dictionary = v.stages
	var marks := {}
	var per_sec := {}
	var blocked := 0
	var frames := 0
	main.transformer.play(who, "full", true)
	var t0 := _gms()
	var started := -1.0
	var shots := {}
	while main.transformer.playing == who or (_gms() - t0 < 1500 and main.transformer.playing == ""):
		await get_tree().process_frame
		var s: float = main.transformer.seq_t
		if s < 0.0:
			continue
		if started < 0.0:
			started = _gms() / 1000.0
		frames += 1
		var sec_k := str(int(s))
		var pb: Array = per_sec.get_or_add(sec_k, [0, 0.0, 0.0])
		pb[0] += 1
		pb[1] += get_process_delta_time() * 1000.0
		pb[2] = maxf(pb[2], get_process_delta_time() * 1000.0)
		var cam: Camera3D = main.transformer.cam
		var q := PhysicsRayQueryParameters3D.create(main.transformer._look_point(c, "chest"), cam.global_position)
		q.collision_mask = 1
		q.exclude = main.characters.values().map(func(x): return (x as CollisionObject3D).get_rid())
		if not c.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			blocked += 1
		var awk := c.get_parent().find_child("Animated_Awakening", false, false) as AwakeningFX
		if awk:
			var cv: float = (awk._cocoon_mat.get_shader_parameter("cover") as float)
			var rl: float = (awk._cocoon_mat.get_shader_parameter("reveal_line") as float)
			if cv > 0.95 and not marks.has("covered"):
				marks.covered = snappedf(s, 0.01)
			if c.avatar_path != base and not marks.has("swapped"):
				marks.swapped = snappedf(s, 0.01)
				marks.cover_at_swap = snappedf(cv, 0.01)
				marks.seal_at_swap = snappedf(awk._cocoon_mat.get_shader_parameter("seal") as float, 0.01)
			if rl < 0.0 and not marks.has("revealed"):
				marks.revealed = snappedf(s, 0.01)
			if awk._locked and not marks.has("orbit_locked"):
				marks.orbit_locked = snappedf(s, 0.01)
		for beat in [["1_awakening", 1.0], ["2_buildup", 3.3], ["3a_cocoon", 5.2], ["3b_reveal", 6.6], ["4_orbit", 8.6], ["5_pose", 10.4]]:
			if s >= float(beat[1]) and not shots.has(beat[0]):
				shots[beat[0]] = true
				if not RenderProfile.options.has("noshots"):
					_shot("%s_%s" % [who, beat[0]])
	var total := _gms() / 1000.0 - started
	await _wait(2.0)
	var last: Dictionary = main.transformer.log[main.transformer.log.size() - 1] if not main.transformer.log.is_empty() else {}
	report["marks"] = marks
	report["per_second"] = per_sec
	report["seconds"] = snappedf(total, 0.01)
	report["blocked_frames"] = blocked
	report["frames"] = frames
	report["result"] = last
	_check(total >= 10.0 and total <= 12.5, "the first awakening lasts 10-12 s", total)
	_check(marks.has("covered") and marks.has("swapped") and float(marks.covered) <= float(marks.swapped), "the cocoon closed before the form changed", marks)
	_check(float(marks.get("cover_at_swap", 0.0)) > 0.95 and float(marks.get("seal_at_swap", 0.0)) > 0.85, "the change happened hidden inside the sealed cocoon (not an abrupt swap)", marks)
	_check(marks.has("revealed") and float(marks.revealed) > float(marks.get("swapped", 99.0)) + 1.0, "the new outfit was revealed progressively afterwards", marks)
	_check(marks.has("orbit_locked") and float(marks.orbit_locked) > float(marks.get("revealed", 0.0)), "the Aether Orbit assembled after the reveal", marks)
	_check(blocked <= frames * 0.03, "the camera kept her in view", [blocked, frames])
	_check(last.get("preview", false) and last.get("reverted", false), "preview: back to her previous appearance", last)
	_check(m.progress.xp == before.xp and m.level() == before.level and TransformationDirector.appearance(who) == before.appearance, "preview changed no progress", before)


# ------------------------------------------------------------------ camera policy
func _policy() -> void:
	_check(main.stream_profile == "mika", "default stream profile is Mika-first", main.stream_profile)
	main.director.enabled = true
	for w in main.mage_brains:
		main.mage_brains[w].hold = false
		main.mage_brains[w].set_enabled(true)
	var frames := 0
	var mika_frames := 0
	var luna_perf_frames := 0
	var t0 := _gms()
	var secs := float(RenderProfile.options.get("seconds", "90"))
	var forced_luna := false
	# Luna performs on her own (the stream must stay with Mika)
	if main.performance and main.characters.has("luna"):
		var lb: SanctuaryBrain = main.mage_brains["luna"]
		await _hold(lb)
		main.performance.perform("luna", "casual", {})
	while _gms() - t0 < secs * 1000.0:
		await get_tree().process_frame
		frames += 1
		if main.focus == "mika":
			mika_frames += 1
		if main.performance and main.performance.busy() and String(main.performance.active.get("who", "")) == "luna":
			luna_perf_frames += 1
		if frames % 300 == 150:
			_shot("t%03d" % (frames / 300))
	report["frames"] = frames
	report["mika_frames"] = mika_frames
	report["luna_performance_frames"] = luna_perf_frames
	_check(mika_frames == frames, "the camera stayed with Mika (Luna-only activities never took it)", [mika_frames, frames])
	_check(luna_perf_frames > 0, "Luna really performed meanwhile (off Mika's camera)", luna_perf_frames)
	# a developer's explicit choice is respected, and released back to Mika
	await main.focus_mage("luna", true)
	await _wait(3.0)
	_check(main.focus == "luna", "explicit developer focus on Luna is respected", main.focus)
	main.focus_locked = false
	await _wait(4.0)
	_check(main.focus == "mika", "released: the stream returns to Mika", main.focus)


# ------------------------------------------------------------------ voices
func _voices() -> void:
	var vs: VoiceService = main.voice
	_check(vs != null and vs.enabled, "voice service enabled")
	if vs == null:
		return
	var t0 := _gms()
	while (not vs.available or vs.edge_status in ["starting", "not started"]) and _gms() - t0 < 40000:
		await get_tree().process_frame
	report["edge"] = vs.edge_status
	report["kokoro"] = vs.status
	_check(vs.edge_available, "Edge provider is up (confirmed voices)", vs.edge_status)
	var out := {}
	for who in ["mika", "luna"]:
		var cfg: Dictionary = vs.config.speakers[who]
		var r: Dictionary = await vs.say(who, "The ward is holding. Stay close to the circle.", {})
		out[who] = r
		_check(r.get("audio", false) and r.get("provider", "") == "edge" and r.get("voice", "") == String(cfg.voice), "%s spoke with %s (%s, %s)" % [who, cfg.voice, cfg.pitch, cfg.rate], r)
	var latin: Dictionary = await vs.say("mika", "Orbis lucis.", {"latin": true})
	out["latin"] = latin
	_check(latin.get("provider", "") == "kokoro" and latin.get("phonemes", false), "Latin incantation spoken from IPA through Kokoro", latin)
	var lf: Dictionary = vs.split_laughter("Hehe. Again later, maybe.")
	_check(lf.lead and not String(lf.text).to_lower().contains("hehe"), "laugh token removed from the spoken text", lf)
	var r2: Dictionary = await vs.say("luna", "Haha, that was close!", {})
	out["laugh"] = r2
	_check(r2.has("laughter") and not String(r2.get("text", "")).to_lower().contains("haha"), "a laugh plays as a reaction, the words without it", r2)
	report["lines"] = out
	report["voice_log"] = vs.log.slice(maxi(0, vs.log.size() - 10))


# ------------------------------------------------------------------ after a fight
func _aftermath() -> void:
	var who := "mika"
	main.spawner.enabled = false                 # one isolated fight: no new creatures wander in afterwards
	await _hold_all()
	_park_others(who)
	await main.focus_mage(who)
	main.director.enabled = true
	var mon := await _stage_fight(who, "emberwing", 9.0)
	if mon:
		mon.hp = 1.0                                  # a short fight: one spell ends it
	var b: SanctuaryBrain = main.mage_brains[who]
	await _wait(1.0)
	var opts := b.options().filter(func(o): return o.kind == "hunt")
	if not opts.is_empty():
		await b.run_activity(opts[0].merged(b.score(opts[0])))
	for m in main.spawner.alive:
		if is_instance_valid(m):
			m.queue_free()
	await _wait(4.0)
	_check(main.director.mode != "combat" and main.director.mode != "signature", "camera left combat framing after the fight", main.director.mode)
	_check(AttackHazard.active(main.world).is_empty(), "no attack hazards left behind")
	var c: WorldCharacter = main.characters[who]
	_check(not c.combat_stance and not c.casting, "she is out of her combat stance", [c.combat_stance, c.casting])
	if main.performance:
		var pr: Dictionary = await main.performance.perform(who, "casual", {"total": 62.0})
		report["performance"] = pr
		_check(pr.get("ok", false), "a music performance after combat works", pr.get("detail", ""))
	if main.voice:
		var r: Dictionary = await main.voice.say(who, "That was a good fight. Now, back to my studies.", {})
		report["voice"] = r
		_check(r.get("seconds", 0.0) > 0.5, "dialogue after combat works", r)
