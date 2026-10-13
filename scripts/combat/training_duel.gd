class_name TrainingDuel
extends Node
## A friendly magical sparring match between the two mages (Milestone K). Only through an invitation both of them
## accepted (Companionship.invite -> "train_together"; strenuous, so a tired mage declines). Real gameplay:
##   * they walk to the training grounds together, take their marks ~9 m apart, bow, then spar
##   * each beat each duelist decides from what SHE perceives: a training bolt coming at her -> dodge (real
##     movement) or brace (a ward); otherwise cast a spar bolt when she has breath and her cooldown is over;
##     otherwise reposition (circle to a new angle)
##   * spar bolts are real projectiles (AttackHazard, nonlethal "training" style, the caster's own colours); a
##     hit is a TOUCH (light flinch, tiny vigor cost) — never a defeat
##   * training breath (stamina) drains with casting and dodging and refills slowly: energy management matters
##   * it stops safely: first to 3 touches, someone runs out of breath (yields), 70 s, or a creature shows up
## Progress is earned only by what really happened: spell practice for touches landed, "dodged in training" for
## real dodges, a sparring record for both — through the normal decaying-repeat XP rules.

signal finished(result: Dictionary)

const TOUCHES_TO_WIN := 3
const MAX_S := 70.0
const BOLT_COST := 0.16
const DODGE_COST := 0.10
const BOLT_CD := 2.4
## Training bolts are deliberately readable (slower than combat spells): sparring is about reacting.
const STYLE := {"mika": {"color": [0.55, 1.0, 0.75], "speed": 7.5, "element": "wind"}, "luna": {"color": [0.72, 0.45, 1.0], "speed": 8.5, "element": "umbral"}}

var main: Node
var active := {}
var _clock := 0.0   # game seconds (real time is unreliable under Movie Maker recording)                  # {a, b, t0, touches{}, stamina{}, cd{}, dodges{}, dodged{}, braced{}, casts{}}
var log: Array = []
var _rng := RandomNumberGenerator.new()


func setup(m: Node) -> void:
	main = m
	_rng.seed = 7171


func busy() -> bool:
	return not active.is_empty()


func _duelists_ok(a: SanctuaryBrain, b: SanctuaryBrain) -> bool:
	return a.me.visible and b.me.visible and a.mind.vigor > 0.25 and b.mind.vigor > 0.25


func run(a: SanctuaryBrain, b: SanctuaryBrain) -> Dictionary:
	if busy():
		return {"ok": false, "detail": "already sparring"}
	var ca := a.me
	var cb := b.me
	var map := ca.get_world_3d().navigation_map
	# the training grounds: an open spot, both walk there together
	var center := _open_ground(ca, SanctuaryTerrain.TRAINING_CENTER_3D)
	var f := FollowCompanion.new()
	f.leader = ca
	f.follower = cb
	main.companionship.add_child(f)
	await main.companionship.walk_together(ca, f, center, 40.0)
	f.queue_free()
	var axis := Vector3(1, 0, 0.25).normalized()
	var spot_a := NavigationServer3D.map_get_closest_point(map, center - axis * 4.5)
	var spot_b := NavigationServer3D.map_get_closest_point(map, center + axis * 4.5)
	ca.navigate_to(spot_a, false)
	cb.navigate_to(spot_b, false)
	var t0 := int(_clock * 1000.0)
	while (ca.current_action == "navigate_to" or cb.current_action == "navigate_to") and int(_clock * 1000.0) - t0 < 12000:
		await get_tree().process_frame
	ca.look_at_point(cb.global_position)
	cb.look_at_point(ca.global_position)
	await get_tree().create_timer(0.8).timeout
	active = {"a": a, "b": b, "t0": _clock, "touches": {}, "stamina": {}, "cd": {}, "dodges": {}, "dodged": {}, "braced": {}, "casts": {},
		"center": center, "events": []}
	for br in [a, b]:
		active.touches[br.agent_id] = 0
		active.stamina[br.agent_id] = clampf(0.6 + br.mind.vigor * 0.4, 0.6, 1.0)
		active.cd[br.agent_id] = _rng.randf_range(0.8, 1.8)
		active.dodges[br.agent_id] = 0
		active.dodged[br.agent_id] = 0
		active.braced[br.agent_id] = 0
		active.casts[br.agent_id] = 0
	# a bow (respect before sparring) and the stances
	for br in [a, b]:
		br.me.play_gesture("brace", 0.3, 0.6)
	await main.companionship._say(a.agent_id, main.companionship.line(a.agent_id, "duel_start") if main.companionship.line(a.agent_id, "duel_start") != "" else "Ready?")
	await main.companionship._say(b.agent_id, main.companionship.line(b.agent_id, "duel_reply") if main.companionship.line(b.agent_id, "duel_reply") != "" else "Ready.")
	for br in [a, b]:
		br.me.set_combat_stance(true)
	# both duelists run their own decision loops at once
	var box := {"stop": "", "done": 0}
	_duelist(a, b, box)
	_duelist(b, a, box)
	while box.done < 2:
		await get_tree().process_frame
		var el := _clock - float(active.t0)
		if box.stop == "":
			if el > MAX_S:
				box.stop = "time"
			for w in active.touches:
				if int(active.touches[w]) >= TOUCHES_TO_WIN:
					box.stop = "touches:" + w
			for w in active.stamina:
				if float(active.stamina[w]) < 0.08:
					box.stop = "yield:" + w
			if main.spawner:
				for m in main.spawner.alive:
					if is_instance_valid(m) and m.alive() and m.global_position.distance_to(center) < 18.0:
						box.stop = "creature"
			if not _duelists_ok(a, b):
				box.stop = "unwell"
	for br in [a, b]:
		br.me.set_combat_stance(false)
		br.me.set_move_input(Vector3.ZERO, false)
	for h in AttackHazard.active(main.world):
		if (h as AttackHazard).owner_mage in [ca, cb]:
			(h as AttackHazard).done = true
			h.queue_free()
	var res := _conclude(a, b, String(box.stop))
	await _aftermath(a, b, res)
	log.append(res)
	active = {}
	finished.emit(res)
	return res


## The most open patch of walkable ground near `near`: horizontal ray fans at chest height, fewest / farthest
## obstacles wins (no dummies, stones or walls inside the sparring lane).
func _open_ground(c: WorldCharacter, near: Vector3) -> Vector3:
	var map := c.get_world_3d().navigation_map
	var space := c.get_world_3d().direct_space_state
	var best := NavigationServer3D.map_get_closest_point(map, near)
	var best_sc := -INF
	for i in 24:
		var a := TAU * i / 24.0
		for r in [0.0, 5.0, 9.0, 13.0]:
			var p := NavigationServer3D.map_get_closest_point(map, near + Vector3(cos(a), 0, sin(a)) * r)
			if p.distance_to(near + Vector3(cos(a), 0, sin(a)) * r) > 1.5:
				continue
			var sc := 0.0
			for k in 12:
				var d := Vector3(cos(TAU * k / 12.0), 0, sin(TAU * k / 12.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 7.0)
				q.collision_mask = 1
				var hit := space.intersect_ray(q)
				sc += 7.0 if hit.is_empty() else p.distance_to(hit.position)
			sc -= p.distance_to(near) * 0.3
			if sc > best_sc:
				best_sc = sc
				best = p
			if r == 0.0:
				break
	return best


## One duelist's loop: perceive, decide, act.
func _duelist(me_b: SanctuaryBrain, opp_b: SanctuaryBrain, box: Dictionary) -> void:
	var me := me_b.me
	var opp := opp_b.me
	var who := me_b.agent_id
	var strafe := 1.0 if _rng.randf() < 0.5 else -1.0
	while box.stop == "":
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		active.stamina[who] = clampf(float(active.stamina[who]) + dt * 0.035, 0.0, 1.0)
		active.cd[who] = maxf(0.0, float(active.cd[who]) - dt)
		if me.current_action == "dodge" or me.casting:
			continue
		# 1) a bolt coming at her that she can see
		var hz := CombatTactics.incoming(me, main.world)
		if hz and hz.owner_mage == opp:
			var tt := hz.time_to(me.global_position)
			# she only reacts once she has really registered it: a reaction time per bolt, slower when tired
			if not hz.has_meta("rt_" + who):
				var tired := 1.0 - float(active.stamina[who])
				hz.set_meta("rt_" + who, _rng.randf_range(0.22, 0.55) + tired * 0.35)
			var rt := float(hz.get_meta("rt_" + who))
			if hz.age < rt:
				continue
			if tt > 0.18 and float(active.stamina[who]) > DODGE_COST:
				var to := CombatTactics.dodge_target(me, hz)
				if to != Vector3.INF:
					active.stamina[who] = float(active.stamina[who]) - DODGE_COST
					active.dodges[who] = int(active.dodges[who]) + 1
					if not hz.resolved.is_connected(_on_bolt_resolved):
						hz.resolved.connect(_on_bolt_resolved)
					hz.set_meta("dodger", who)
					await me.dodge(to, 0.5)
					me.look_at_point(opp.global_position)
					continue
			# no time / no breath: a ward (brace) halves nothing — it just reads as defence; the bolt decides
			active.braced[who] = int(active.braced[who]) + 1
			me.play_gesture("brace", 0.06, 0.3)
			await get_tree().create_timer(0.45).timeout
			continue
		# 2) cast when ready
		if float(active.cd[who]) <= 0.0 and float(active.stamina[who]) > BOLT_COST + 0.05:
			active.stamina[who] = float(active.stamina[who]) - BOLT_COST
			active.cd[who] = BOLT_CD * _rng.randf_range(0.85, 1.25) * (1.0 if float(active.stamina[who]) > 0.4 else 1.5)
			await _cast_bolt(me_b, opp)
			continue
		# 3) reposition: circle a few metres around the middle, facing her opponent
		if _rng.randf() < 0.012:
			strafe = -strafe
		var axis := Vector3(opp.global_position.x - me.global_position.x, 0, opp.global_position.z - me.global_position.z)
		var dist := axis.length()
		axis = axis.normalized() if dist > 0.1 else Vector3.FORWARD
		var side := Vector3(-axis.z, 0, axis.x) * strafe
		var want := side * 0.6 + axis * clampf((dist - 8.5) * 0.3, -0.6, 0.6)
		me.pace = 0.75
		me.set_move_input(me._steer_around(want.normalized()) * 0.6, false)
		me.rotation.y = lerp_angle(me.rotation.y, atan2(-axis.x, -axis.z), 1.0 - exp(-8.0 * dt))
	me.pace = 1.0
	me.set_move_input(Vector3.ZERO, false)
	box.done += 1


## A spar bolt: face, gesture (quick cast), release from her hand along a slightly led aim; real projectile.
func _cast_bolt(me_b: SanctuaryBrain, opp: WorldCharacter) -> void:
	var me := me_b.me
	var who := me_b.agent_id
	me.set_move_input(Vector3.ZERO, false)
	me.look_at_point(opp.global_position)
	var t0 := int(_clock * 1000.0)
	while me.current_action == "look_at" and int(_clock * 1000.0) - t0 < 600:
		await get_tree().physics_frame
	me.play_gesture("cast_quick", 0.12, 0.3)
	await get_tree().create_timer(0.18).timeout
	if not busy():
		return
	var st: Dictionary = STYLE.get(who, STYLE.mika)
	var from := me.right_hand.global_position + (-me.global_transform.basis.z) * 0.3 if me.right_hand else me.global_position + Vector3(0, 1.3, 0)
	var vel := Vector3(opp.velocity.x, 0, opp.velocity.z)
	# a light lead on her movement plus the caster's own aim error (mastery-scaled): a still target gets hit,
	# a moving one often does not
	var err := MagicSystem.aim_error(SignatureCast.spell_for(who), who) if SignatureCast.spell_for(who) != "" else 0.4
	var aim := opp.global_position + Vector3(0, 1.0, 0) + vel * (from.distance_to(opp.global_position) / float(st.speed)) * 0.35
	aim += Vector3(-h_dir_z(from, aim), 0, h_dir_x(from, aim)) * _rng.randf_range(-err, err)
	var h := AttackHazard.new()
	h.kind = "projectile"
	h.owner_mage = me
	h.center = from
	h.dir = (aim - from).normalized()
	h.speed = float(st.speed)
	h.max_range = 16.0
	h.vigor = 0.02
	h.style = "spar_" + who
	var c: Array = st.color
	h.color = Color(c[0], c[1], c[2])
	h.resolved.connect(_on_bolt_resolved)
	h.set_meta("caster", who)
	main.world.add_child(h)
	h.set_exclude([me.get_rid()])
	active.casts[who] = int(active.casts[who]) + 1
	MagicEvents.emit_phase(me, "spar_bolt", "release", String(st.element), from)


static func h_dir_x(a: Vector3, b: Vector3) -> float:
	return Vector3(b.x - a.x, 0, b.z - a.z).normalized().x


static func h_dir_z(a: Vector3, b: Vector3) -> float:
	return Vector3(b.x - a.x, 0, b.z - a.z).normalized().z


func _on_bolt_resolved(h: AttackHazard, struck: Array) -> void:
	if active.is_empty():
		return
	var caster := String(h.get_meta("caster", ""))
	if struck.is_empty():
		var d := String(h.get_meta("dodger", ""))
		if d != "":
			active.dodged[d] = int(active.dodged[d]) + 1
		return
	for c in struck:
		var wc := c as WorldCharacter
		if wc == null or caster == "" or wc.character_id == caster:
			continue
		active.touches[caster] = int(active.touches[caster]) + 1
		active.events.append({"t": snappedf(_clock - float(active.t0), 0.1), "touch": caster, "on": wc.character_id})
		wc.take_hit(h.center, false)
		var m := WorldState.mind(wc.character_id)
		m.vigor = clampf(m.vigor - h.vigor, 0.0, 1.0)
		if main.get("affect"):
			main.affect.react(wc.character_id, "struck", 0.6)
			main.affect.react(caster, "spell_hit")


func _conclude(a: SanctuaryBrain, b: SanctuaryBrain, stop: String) -> Dictionary:
	var ta := int(active.touches[a.agent_id])
	var tb := int(active.touches[b.agent_id])
	var winner := ""
	if ta != tb:
		winner = a.agent_id if ta > tb else b.agent_id
	if stop.begins_with("yield:") and ta == tb:
		winner = b.agent_id if stop.trim_prefix("yield:") == a.agent_id else a.agent_id   # level on touches: the one still standing
	var res := {"ok": true, "stop": stop, "winner": winner, "touches": active.touches.duplicate(), "dodges": active.dodges.duplicate(),
		"dodged": active.dodged.duplicate(), "braced": active.braced.duplicate(), "casts": active.casts.duplicate(),
		"seconds": snappedf(_clock - float(active.t0), 0.1), "events": active.events.duplicate()}
	res["detail"] = "sparred %.0f s: %s %d - %d %s (%s)" % [res.seconds, MagicSystem.display_name(a.agent_id), ta, tb, MagicSystem.display_name(b.agent_id), stop]
	# what each really earned: practice from touches landed, a record of real dodges, the bout itself
	for pair in [[a, b], [b, a]]:
		var me_b: SanctuaryBrain = pair[0]
		var who := me_b.agent_id
		var other := (pair[1] as SanctuaryBrain).agent_id
		var know := {"sparred:" + other: 1}
		if int(active.dodged[who]) > 0:
			know["training:dodged"] = 1
		var skills := {}
		var sig := SignatureCast.spell_for(who)
		if int(active.touches[who]) > 0 and sig != "" and main.magic.can_cast(sig, who).ok:
			skills[sig] = 0.02 * int(active.touches[who]) / (1.0 + MagicSystem.mastery(sig, who) * 0.8)
		var outcome := "won" if winner == who else ("drew" if winner == "" else "lost")
		WorldState.record_activity({"id": "spar:" + other, "verb": "spar", "label": "Sparred with %s (%s, %d touch%s, %d dodge%s)" % [MagicSystem.display_name(other), outcome,
			int(active.touches[who]), "" if int(active.touches[who]) == 1 else "es", int(active.dodged[who]), "" if int(active.dodged[who]) == 1 else "s"]},
			{"knowledge": know, "skills": skills}, who)
		res["memory_" + who] = "sparred at the training grounds (I %s, %d-%d)" % [outcome, int(active.touches[who]), int(active.touches[other])]
	res["memory"] = "sparred at the training grounds"
	return res


func _aftermath(a: SanctuaryBrain, b: SanctuaryBrain, res: Dictionary) -> void:
	var ca := a.me
	var cb := b.me
	ca.look_at_point(cb.global_position)
	cb.look_at_point(ca.global_position)
	await get_tree().create_timer(0.8).timeout
	for br in [a, b]:
		var w: String = br.agent_id
		var key := "duel_won" if String(res.winner) == w else ("duel_draw" if String(res.winner) == "" else "duel_lost")
		if main.get("affect"):
			main.affect.react(w, "victory" if key == "duel_won" else "camera")
	var first: SanctuaryBrain = a if String(res.winner) != b.agent_id else b
	var second: SanctuaryBrain = b if first == a else a
	for br in [first, second]:
		var w2: String = br.agent_id
		var key2 := "duel_won" if String(res.winner) == w2 else ("duel_draw" if String(res.winner) == "" else "duel_lost")
		await main.companionship._say(w2, main.companionship.line(w2, key2))
		await get_tree().create_timer(0.3).timeout
	if String(res.winner) != "":
		var wc: WorldCharacter = ca if String(res.winner) == a.agent_id else cb
		wc.play_gesture("victory_nod", 0.3, 0.5)


func _process(delta: float) -> void:
	_clock += delta
