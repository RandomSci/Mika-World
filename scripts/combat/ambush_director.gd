class_name AmbushDirector
extends Node
## Road ambushes by human rivals (the developer: "adventurers or groups that tried to rob them ... assassins, sword
## techniques, different kinds of black magic, fast movements, like in real anime ... with some conversations ...
## thugs talking about them, trying to encircle them"). data/ambush.json; docs/AMBUSH.md.
##   watch     the band, in cover 20+ m away, talks about the girls and their storage rings (seen from behind them)
##   encircle  they step out and walk round the girls on foot, closing a ring; the leader makes his demand; the
##             girls turn back to back, answer, take their stance (staged camera: speaker-driven shots)
##   fight     each rival fights in his own way (Monster defs rival_*: sword waves, assassin blinks with
##             afterimages, thrown knives, hex bolts, curse circles); the girls fight with their own planners;
##             the trailer camera follows; short barks
##   break     the band breaks when the leader is badly hurt or two of them are down: the leader yields (kneels,
##             drops his blade), the others run; the Hexer always gets away with a threat (he comes back: rivals)
##   after     the girls check on each other and talk about it; the encounter is remembered (WorldState.rivals)
## Nobody teleports: rivals walk in from where they were hiding, and run off physically.

signal finished(result: Dictionary)

var main: Node
var cfg := {}
var busy := false
var rivals := {}                 # def id -> Monster
var rec := {}                    # what happened (tests, docs, the journal)
var _shot := {}                  # the staged camera's current shot spec
var _shot_t := 0.0
var _rng := RandomNumberGenerator.new()
var _band := {}


func setup(m: Node) -> void:
	main = m
	var f := FileAccess.open("res://data/ambush.json", FileAccess.READ)
	if f:
		cfg = JSON.parse_string(f.get_as_text())
	_rng.randomize()


## Run one ambush on the mages present in this area (awaitable). opts: {"bearing": radians (where the band hides,
## relative to the party's facing), "distance": m, "fight_s": max seconds of fighting}
func run(band_id := "road_thieves", opts := {}) -> Dictionary:
	if busy:
		return {"ok": false, "detail": "an ambush is already happening"}
	var band: Dictionary = cfg.get("bands", {}).get(band_id, {})
	var party := _party()
	if band.is_empty() or party.is_empty():
		return {"ok": false, "detail": "no band or nobody to ambush"}
	busy = true
	rivals = {}
	_band = band
	rec = {"band": band_id, "beats": [], "said": [], "spawned": [], "outcome": {}, "clock": WorldState.clock_text()}
	var met_before := int(WorldState.rivals.get(String(band.get("recurring", "")), {}).get("met", 0))
	for c in party:
		var b = main.mage_brains.get((c as WorldCharacter).character_id)
		if b:
			b.hold = true
	await _settle(party)
	var centre := _centre(party)
	var lead: WorldCharacter = party[0]
	var fwd := -lead.global_transform.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var bearing := float(opts.get("bearing", _rng.randf_range(-0.7, 0.7)))
	var hide_dir := fwd.rotated(Vector3.UP, bearing)
	var hide := centre + hide_dir * float(opts.get("distance", 22.0))
	# ---- the band, gathered in cover
	var roster: Array = band.get("roster", [])
	var i := 0
	for kind in roster:
		var off := Vector3(-hide_dir.z, 0, hide_dir.x) * ((i - (roster.size() - 1) * 0.5) * 1.3) + hide_dir * (0.6 if i % 2 else 0.0)
		var at: Vector3 = await main.snap_to_nav(hide + off)
		var mon: Monster = main.spawner.spawn(String(kind), at)
		i += 1
		if mon == null:
			continue
		mon.home = centre
		rivals[String(kind)] = mon
		rec.spawned.append(String(kind))
	if rivals.is_empty():
		return _end(party, {"ok": false, "detail": "the band could not be placed"})
	var leader: Monster = rivals.get(String(band.get("leader", "")), rivals.values()[0])
	for k in rivals:
		var m: Monster = rivals[k]
		m.script_to(m.global_position, 1.0, leader if m != leader else party[0], "talk" if m == leader else "alert")
	_beat("watch", "%d rivals in cover %.0f m away" % [rivals.size(), hide.distance_to(centre)])
	# ---- WATCH: over the band's shoulders onto the girls, far off; they talk about them
	main.director.begin_scene(_scene_shot)
	_set_shot({"kind": "watch", "from": leader, "at": centre})
	var lines: Array = band.get("again", []) if met_before > 0 and band.has("again") else []
	# the band's whole script is written: synthesise every exchange now (each is ready long before it is spoken)
	if main.voice:
		var all := []
		for ph in ["watch", "encircle", "yield", "after"]:
			all.append_array(band.get(ph, []))
		main.voice.prefetch_lines(all.map(func(ln): return {"speaker": String(ln[0]), "text": String(ln[1]),
			"opts": {"mood": String(ln[2])} if ln.size() > 2 and String(ln[2]) != "" else {}}), false)
	_prefetch(band.get("watch", []))
	for ln in band.get("watch", []):
		await _line(ln)
	# ---- ENCIRCLE: they step out and walk round the girls
	_beat("encircle", "")
	var ring_r := 6.5
	var n := rivals.size()
	var base := atan2((leader.global_position - centre).x, (leader.global_position - centre).z)
	var order: Array = rivals.keys()
	order.erase(leader_kind(band, leader))
	order.push_front(leader_kind(band, leader))
	var slots := {}
	for j in order.size():
		# the leader straight ahead of them, the others fanning round both sides until the ring closes behind
		var ang := base + floorf((j + 1) / 2.0) * (TAU / float(n)) * (1.0 if j % 2 == 1 else -1.0)
		var slot: Vector3 = await main.snap_to_nav(centre + Vector3(sin(ang), 0, cos(ang)) * ring_r)
		slots[order[j]] = slot
		var m2: Monster = rivals[order[j]]
		m2.script_to(slot, 2.3 + 0.15 * j, null, "alert")
	_set_shot({"kind": "orbit", "at": centre})
	# the girls notice: they turn to face them and move together, back to back
	var mika: WorldCharacter = main.characters.get("mika")
	var luna: WorldCharacter = main.characters.get("luna")
	if luna and luna.visible:
		luna.look_head_at(leader.global_position + Vector3(0, 1.5, 0))
	await _wait(1.6)
	for c in party:
		(c as WorldCharacter).set_combat_stance(true)
	if mika and luna and mika.visible and luna.visible:
		var axis := Vector3(leader.global_position.x - centre.x, 0, leader.global_position.z - centre.z).normalized()
		mika.navigate_to(await main.snap_to_nav(centre + axis * 0.55), false)
		luna.navigate_to(await main.snap_to_nav(centre - axis * 0.55), false)
	var t := 0.0
	while t < 18.0:
		var arrived := true
		for k in slots:
			var m3: Monster = rivals.get(k)
			if m3 and is_instance_valid(m3) and Vector2(m3.global_position.x - slots[k].x, m3.global_position.z - slots[k].z).length() > 0.6:
				arrived = false
		if arrived:
			break
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	rec["ring"] = _ring_spread(centre)
	for k in rivals:
		var m4_raw = rivals[k]
		if not is_instance_valid(m4_raw):
			continue
		var m4: Monster = m4_raw
		var tgt: WorldCharacter = main.characters.get(String(band.get("targets", {}).get(k, "mika")))
		m4.script_to(Vector3.INF, 1.0, tgt if tgt and tgt.visible else party[0], "alert" if m4 != leader else "talk")
	if mika and mika.visible:
		mika.look_at_point(leader.global_position)
	if luna and luna.visible and rivals.has("rival_hexer"):
		luna.look_at_point((rivals.rival_hexer as Monster).global_position)
	_beat("standoff", "ring closed, spread %.1f rad" % float(rec.ring))
	_prefetch((lines if not lines.is_empty() else []) + band.get("encircle", []))
	for ln in (lines if not lines.is_empty() else []):
		await _line(ln)
	for ln in band.get("encircle", []):
		await _line(ln)
	main.director.end_scene()
	# ---- FIGHT
	_beat("fight", "")
	for k in rivals:
		var m5_raw = rivals[k]
		if not is_instance_valid(m5_raw):
			continue
		var m5: Monster = m5_raw
		var tgt2: WorldCharacter = main.characters.get(String(band.get("targets", {}).get(k, "mika")))
		m5.release_script(tgt2 if tgt2 and tgt2.visible else party[0])
	var hunting := {}
	for c in party:
		_hunt_loop(c as WorldCharacter, hunting)
	var fight_s := float(opts.get("fight_s", 110.0))
	var ft := 0.0
	var bark_t := 3.0
	var broke := ""
	var recurring := String(band.get("recurring", ""))
	while ft < fight_s:
		await get_tree().physics_frame
		ft += get_physics_process_delta_time()
		bark_t -= get_physics_process_delta_time()
		if bark_t <= 0.0:
			bark_t = _rng.randf_range(5.5, 9.0)
			_bark(band)
		# the Hexer never stays to lose: badly hurt, he runs with a threat (he will be back)
		if recurring != "" and rivals.has(recurring):
			var hx_raw = rivals[recurring]
			if is_instance_valid(hx_raw):
				var hx: Monster = hx_raw
				if hx.alive() and hx.mstate != "fleeing" and hx.hp < hx.max_hp * 0.3:
					_flee(hx, recurring, band, centre)
		var down := 0
		for k in rivals:
			var m6_raw = rivals[k]
			if not is_instance_valid(m6_raw):
				down += 1                 # knocked out and already walked off
				continue
			var m6: Monster = m6_raw
			if not m6.alive() or m6.mstate in ["fleeing", "yielded"]:
				down += 1
		if down >= rivals.size():
			broke = "all down"
			break
		if is_instance_valid(leader) and leader.alive() and leader.hp < leader.max_hp * 0.35:
			broke = "the leader is beaten"
			break
		if down >= 2:
			broke = "two of them are down"
			break
	rec["fight_s"] = snappedf(ft, 0.1)
	rec["broke"] = broke if broke != "" else "time"
	_beat("break", String(rec.broke))
	# ---- BREAK: the leader yields, the others run
	for c in party:
		var b2 = main.mage_brains.get((c as WorldCharacter).character_id)
		if b2:
			b2.interrupt("the band yields")
	hunting["stop"] = true
	if is_instance_valid(leader) and leader.alive() and leader.mstate != "fleeing":
		leader.yield_fight()
		rec.outcome[leader_kind(band, leader)] = "yielded"
	for k in rivals:
		var m7_raw = rivals[k]
		if not is_instance_valid(m7_raw):
			rec.outcome[k] = rec.outcome.get(k, "knocked out")
			continue
		var m7: Monster = m7_raw
		if m7.alive() and not (m7.mstate in ["yielded", "fleeing"]):
			_flee(m7, k, band, centre)
		elif not m7.alive():
			rec.outcome[k] = rec.outcome.get(k, "knocked out")
	if leader and is_instance_valid(leader) and leader.mstate == "yielded":
		_set_shot({"kind": "two", "a": leader, "b": party[0]})
		main.director.begin_scene(_scene_shot)
		_prefetch(band.get("yield", []))
		for ln in band.get("yield", []):
			await _line(ln)
	await _wait(2.0)
	# ---- AFTER
	for c in party:
		(c as WorldCharacter).set_combat_stance(false)
	main.director.end_scene()
	if mika and luna and mika.visible and luna.visible:
		mika.navigate_to(await main.snap_to_nav(luna.global_position + (mika.global_position - luna.global_position).normalized() * 1.2), false)
		await _wait(2.5)
		mika.look_at_point(luna.global_position)
		luna.look_at_point(mika.global_position)
		main.director.focus_conversation(luna, 14.0)
		_prefetch(band.get("after", []))
		for ln in band.get("after", []):
			await _line(ln)
	# the yielded leader gets up and leaves on foot
	if leader and is_instance_valid(leader) and leader.mstate == "yielded":
		leader.flee(centre)
	# ---- remember it
	if recurring != "":
		var r: Dictionary = WorldState.rivals.get(recurring, {"met": 0})
		r["met"] = int(r.get("met", 0)) + 1
		r["last"] = String(rec.outcome.get(recurring, "fled"))
		r["last_clock"] = WorldState.clock_text()
		r["wants"] = "Luna's silver storage ring"
		r["name"] = String(rivals[recurring].def.get("name", recurring)) if rivals.has(recurring) and is_instance_valid(rivals[recurring]) else recurring
		WorldState.rivals[recurring] = r
	for c in party:
		WorldState.record_activity({"id": "ambush:%s:%d" % [band_id, met_before], "verb": "survive", "label": "Fought off %s on the road" % String(band.get("name", "a band"))},
			{"knowledge": {"rival:" + band_id: 1}}, (c as WorldCharacter).character_id)
	if main.get("journeys") and not WorldState.journey.is_empty() and main.journeys.has_method("note"):
		main.journeys.note("%s ambushed them; %s" % [String(band.get("name", "a band")), String(rec.broke)], "encounter")
	return _end(party, {"ok": true, "detail": String(rec.broke), "outcome": rec.outcome})


func leader_kind(band: Dictionary, leader: Monster) -> String:
	for k in rivals:
		if rivals[k] == leader:
			return k
	return String(band.get("leader", ""))


func _end(party: Array, res: Dictionary) -> Dictionary:
	for c in party:
		var b = main.mage_brains.get((c as WorldCharacter).character_id)
		if b:
			b.hold = false
	main.director.end_scene()
	busy = false
	rec["result"] = res
	finished.emit(res)
	return res


func _party() -> Array:
	var out := []
	for who in ["mika", "luna"]:
		var c: WorldCharacter = main.characters.get(who)
		if c and c.visible and c.is_inside_tree():
			out.append(c)
	return out


func _centre(party: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in party:
		c += (p as Node3D).global_position
	return c / float(party.size())


func _settle(party: Array) -> void:
	var t := 0.0
	while t < 20.0:
		var idle := true
		for c in party:
			var b = main.mage_brains.get((c as WorldCharacter).character_id)
			if b and not b.current.is_empty():
				idle = false
		if idle:
			return
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _wait(s: float) -> void:
	var t := 0.0
	while t < s and is_inside_tree():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _beat(what: String, detail: String) -> void:
	var e := {"clock": WorldState.clock_text(), "beat": what, "detail": detail}
	(rec.beats as Array).append(e)
	print("[ambush] %s  %s%s" % [e.clock, what, (": " + detail) if detail != "" else ""])


## One line of the scene: [speaker, text, mood]. The camera favours the speaker.
## The whole exchange is written: every line after the first synthesises while the one before it is spoken.
func _prefetch(lines: Array) -> void:
	if main.voice:
		main.voice.prefetch_lines(lines.map(func(ln): return {"speaker": String(ln[0]), "text": String(ln[1]),
			"opts": {"mood": String(ln[2])} if ln.size() > 2 and String(ln[2]) != "" else {}}))


func _line(ln: Array) -> void:
	var who := String(ln[0])
	var text := String(ln[1])
	var mood := String(ln[2]) if ln.size() > 2 else ""
	var cand = rivals.get(who) if rivals.has(who) else main.characters.get(who)
	if cand == null or not is_instance_valid(cand):
		return
	var node: Node3D = cand
	if rivals.has(who):
		(rivals[who] as Monster).script_anim = "talk"
	(rec.said as Array).append({"who": who, "text": text})
	if _shot.get("kind", "") != "watch":
		_set_shot({"kind": "speaker", "who": node, "listener": _listener(who)})
	var opts := {}
	if mood != "":
		opts["mood"] = mood
	await main.voice.say(who, text, opts)
	if rivals.has(who) and is_instance_valid(rivals[who]):
		(rivals[who] as Monster).script_anim = "alert"
	await _wait(0.25)


func _listener(who: String) -> Node3D:
	if rivals.has(who):
		var band_targets: Dictionary = _band.get("targets", {})
		var c: WorldCharacter = main.characters.get(String(band_targets.get(who, "mika")))
		return c if c and c.visible else main.characters.get("mika")
	# a mage answers the leader (or the Hexer when Luna speaks)
	if who == "luna" and rivals.has("rival_hexer") and is_instance_valid(rivals.rival_hexer):
		return rivals.rival_hexer
	for k in rivals:
		if is_instance_valid(rivals[k]):
			return rivals[k]
	return null


func _bark(band: Dictionary) -> void:
	if main.voice.busy():
		return
	var who := ""
	var pool := []
	var keys: Array = rivals.keys().filter(func(k): return is_instance_valid(rivals[k]) and (rivals[k] as Monster).alive() and (rivals[k] as Monster).mstate != "fleeing")
	if _rng.randf() < 0.3:
		keys = ["mika", "luna"]
	if keys.is_empty():
		return
	who = String(keys[_rng.randi() % keys.size()])
	pool = band.get("barks", {}).get(who, [])
	if pool.is_empty():
		return
	var text := String(pool[_rng.randi() % pool.size()])
	(rec.said as Array).append({"who": who, "text": text, "bark": true})
	main.voice.say(who, text, {"mood": "determined", "max_wait": 1.2} if who in ["mika", "luna"] else {"max_wait": 1.2})


func _flee(m: Monster, kind: String, band: Dictionary, from: Vector3) -> void:
	var line := String(band.get("flee", {}).get(kind, ""))
	m.flee(from)
	rec.outcome[kind] = "fled"
	_beat("flees", kind)
	if line != "":
		(rec.said as Array).append({"who": kind, "text": line})
		main.voice.say(kind, line, {"priority": 1, "max_wait": 1.2})


## Her side of the fight: her own planner hunts the nearest rival still fighting, one after another.
func _hunt_loop(c: WorldCharacter, state: Dictionary) -> void:
	var b = main.mage_brains.get(c.character_id)
	if b == null:
		return
	while not state.get("stop", false) and is_inside_tree():
		var tgt: Monster = null
		var bd := INF
		for k in rivals:
			var mr = rivals[k]
			if not is_instance_valid(mr):
				continue
			var m: Monster = mr
			if m.alive() and not (m.mstate in ["fleeing", "yielded", "scripted"]):
				var d := m.global_position.distance_to(c.global_position)
				if d < bd:
					bd = d
					tgt = m
		if tgt == null:
			break
		b.current = {"kind": "hunt", "monster": tgt.id, "label": "fight off the band"}
		var t0 := Time.get_ticks_msec()
		var tkind: String = tgt.kind
		var rr: Dictionary = await b.run_activity({"kind": "hunt", "key": "hunt:" + tgt.id, "monster": tgt.id, "monster_kind": tkind, "tier": tgt.tier(), "label": "fight off the band"})
		b.current = {}
		if not is_instance_valid(c):
			break
		(rec.get_or_add("hunts", []) as Array).append({"who": c.character_id, "target": tkind, "detail": str(rr.get("detail", "")).left(120)})
		# a hunt that ended at once (refused, target out of reach) must not spin: give the fight a moment
		await get_tree().physics_frame
		if Time.get_ticks_msec() - t0 < 300:
			await _wait(0.6)


func _ring_spread(centre: Vector3) -> float:
	var angs := []
	for k in rivals:
		var mr = rivals[k]
		if not is_instance_valid(mr):
			continue
		var m: Monster = mr
		angs.append(atan2(m.global_position.x - centre.x, m.global_position.z - centre.z))
	angs.sort()
	var biggest_gap := 0.0
	for j in angs.size():
		var a0: float = angs[j]
		var a1: float = angs[(j + 1) % angs.size()] + (TAU if j == angs.size() - 1 else 0.0)
		biggest_gap = maxf(biggest_gap, a1 - a0)
	return TAU - biggest_gap        # how much of the circle round them the band covers


# ------------------------------------------------------------------ the staged camera
## Nothing solid between the lens and the subject, and no other person standing in the way.
func _view_clear(cam: Vector3, at: Vector3, ignore: Array) -> bool:
	var q := PhysicsRayQueryParameters3D.create(at, cam)
	q.collision_mask = 1
	if not get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty():
		return false
	var people: Array = rivals.values() + _party()
	for pnode in people:
		if pnode in ignore or not is_instance_valid(pnode):
			continue
		var c := (pnode as Node3D).global_position + Vector3(0, 1.1, 0)
		var seg := Geometry3D.get_closest_point_to_segment(c, cam, at)
		if seg.distance_to(c) < 0.55:
			return false
	return true


## The lens never inside or behind scenery: pulled in front of whatever blocks the view, and above the ground.
func _safe(sh: Dictionary) -> Dictionary:
	var pos: Vector3 = sh.pos
	var look: Vector3 = sh.look
	var q := PhysicsRayQueryParameters3D.create(look, pos)
	q.collision_mask = 1
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = (hit.position as Vector3) + (look - (hit.position as Vector3)).normalized() * 0.35
	if main.world and main.world.has_method("ground_at"):
		pos.y = maxf(pos.y, float(main.world.ground_at(pos.x, pos.z)) + 0.4)
	sh["pos"] = pos
	return sh


func _set_shot(s: Dictionary) -> void:
	s["cut"] = true
	_shot = s
	_shot_t = 0.0


func _scene_shot(delta: float) -> Dictionary:
	_shot_t += delta
	var cut: bool = _shot.get("cut", false)
	_shot["cut"] = false
	var mika: WorldCharacter = main.characters.get("mika")
	match String(_shot.get("kind", "")):
		"watch":
			# from behind the leader's shoulder, low, a long lens onto the girls far down the road (being watched)
			var from = _shot.get("from")
			var at: Vector3 = _shot.get("at")
			if is_instance_valid(from):
				var axis := Vector3(at.x - (from as Node3D).global_position.x, 0, at.z - (from as Node3D).global_position.z).normalized()
				var side := Vector3(-axis.z, 0, axis.x)
				return {"pos": (from as Node3D).global_position - axis * 1.4 + side * 0.55 + Vector3(0, 1.55, 0), "look": at + Vector3(0, 1.0, 0),
					"fov": 30.0, "rate": 4.0, "cut": cut}
		"orbit":
			var c: Vector3 = _shot.get("at")
			var a := _shot_t * 0.18
			return _safe({"pos": c + Vector3(sin(a), 0, cos(a)) * 8.5 + Vector3(0, 2.6, 0), "look": c + Vector3(0, 1.0, 0), "fov": 50.0, "rate": 2.5, "cut": cut})
		"speaker":
			var who = _shot.get("who")
			var lis = _shot.get("listener")
			if is_instance_valid(who) and is_instance_valid(lis):
				var hp := (who as Node3D).global_position + Vector3(0, 1.55, 0)
				var lp := (lis as Node3D).global_position + Vector3(0, 1.45, 0)
				var axis2 := Vector3(hp.x - lp.x, 0, hp.z - lp.z).normalized()
				var side2 := Vector3(-axis2.z, 0, axis2.x)
				# over the listener's shoulder onto the speaker's face: the first candidate (shoulder side, distance)
				# with a clear view - no wall, rock or third person between the lens and the face
				if cut or not _shot.has("pick"):
					# over the listener's shoulder but well clear of her (long hair, ears): never inside or right behind her
					_shot["pick"] = [1.0, 2.2]
					for cand in [[1.0, 2.2], [-1.0, 2.2], [1.0, 2.9], [-1.0, 2.9], [1.0, 1.7], [-1.0, 1.7]]:
						var cp := lp - axis2 * float(cand[1]) + side2 * 0.85 * float(cand[0]) + Vector3(0, 0.15, 0)
						if _view_clear(cp, hp, [who, lis]):
							_shot["pick"] = cand
							break
				var pk: Array = _shot.pick
				return _safe({"pos": lp - axis2 * float(pk[1]) + side2 * 0.85 * float(pk[0]) + Vector3(0, 0.15, 0), "look": hp - Vector3(0, 0.05, 0),
					"fov": 38.0, "rate": 5.0, "cut": cut})
		"two":
			var a2 = _shot.get("a")
			var b2 = _shot.get("b")
			if is_instance_valid(a2) and is_instance_valid(b2):
				var mid := ((a2 as Node3D).global_position + (b2 as Node3D).global_position) * 0.5
				var ax := Vector3((b2 as Node3D).global_position.x - (a2 as Node3D).global_position.x, 0, (b2 as Node3D).global_position.z - (a2 as Node3D).global_position.z).normalized()
				return _safe({"pos": mid + Vector3(-ax.z, 0, ax.x) * 4.0 + Vector3(0, 1.4, 0), "look": mid + Vector3(0, 0.9, 0), "fov": 46.0, "rate": 3.0, "cut": cut})
	if mika:
		return {"pos": mika.global_position + Vector3(0, 2.0, 4.0), "look": mika.global_position + Vector3(0, 1.0, 0), "fov": 50.0, "rate": 3.0, "cut": cut}
	return {}
