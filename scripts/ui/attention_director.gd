class_name AttentionDirector
extends Node
## Where the mages look and what their faces do, from observable events only.
##   * camera awareness: the FOLLOWED mage, when idle-ish and the camera is in front of her and close,
##     occasionally meets its eye for 1-2 s (cooldown 35-80 s, never constant, never mid-cast / reading /
##     conversation / performance), with a small personality-specific expression;
##   * social awareness: a mage notices the other mage nearby with a brief glance (cooldown);
##   * event expressions: level-up / victory / discovery / hit / retreat / fusion -> a short expression that
##     fades back (Mika brighter, Luna more reserved; data/mages.json "expressions").
## Blinking, gaze while reading and lip movement while speaking already exist in WorldCharacter / VoiceService.
## StreamContext (stream_context.gd) reports the honest stream state used here: DEV mode, no livestream.

var main: Node
var log: Array = []
var _cd := {}                     # who -> seconds until she may glance at the camera again
var _social_cd := {}
var _until := {}                  # who -> {expr, t_end}
var _rng := RandomNumberGenerator.new()
var _acc := 0.0


func setup(m: Node) -> void:
	main = m
	_rng.seed = 4242
	WorldState.mage_event.connect(_on_mage_event)
	if main.progression:
		main.progression.leveled.connect(func(w, _l): react(w, "level_up"))
	if main.spawner:
		main.spawner.mage_hit.connect(func(mage, _m, _a): react(mage.character_id, "hit"))
		main.spawner.monster_defeated.connect(func(_m, by): if by != "": react(by, "victory"))
	if main.magic and main.magic.fusion:
		main.magic.fusion.fused.connect(func(f): for w in f.mages: react(w, "fusion"))


func _on_mage_event(who: String, kind: String, data) -> void:
	if kind == "trial":
		react(who, "discovery")
	elif kind == "activity":
		for k in (data.get("changes", {}) as Dictionary):
			if String(k).begins_with("knowledge.clue:") or String(k).begins_with("knowledge.reaction:") and data.changes[k][0] == 0:
				react(who, "discovery")
				break


## A short expression for an observed event, in her own style; fades back after `secs`.
func react(who: String, event: String) -> void:
	var c: WorldCharacter = main.characters.get(who)
	if c == null or not c.visible:
		return
	var table: Dictionary = Progression.mages.get(who, {}).get("expressions", {})
	var e: Array = table.get(event, [])
	if e.is_empty():
		return
	c.set_expression(String(e[0]), float(e[1]))
	_until[who] = {"expr": String(e[0]), "t_end": Time.get_ticks_msec() / 1000.0 + float(e[2])}
	log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "who": who, "event": event, "expression": e[0]})
	if log.size() > 60:
		log.pop_front()


func _idle_enough(who: String) -> bool:
	var c: WorldCharacter = main.characters[who]
	if c.casting or c.seated or not c.visible:
		return false
	var b = main.mage_brains.get(who)
	var kind := String(b.current.get("kind", "")) if b else ""
	if kind in ["hunt", "research", "meet", "converse", "alchemy", "perform", "attune"]:
		return false
	if main.performance and main.performance.busy():
		return false
	if main.voice and main.voice.busy():
		return false
	return true


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for who in _until.keys():
		if now > float(_until[who].t_end):
			var c0: WorldCharacter = main.characters.get(who)
			if c0:
				c0.set_expression(String(_until[who].expr), 0.0)
			_until.erase(who)
	_acc += delta
	if _acc < 0.5:
		return
	_acc = 0.0
	var cam := get_viewport().get_camera_3d()
	for who in main.characters:
		_cd[who] = float(_cd.get(who, _rng.randf_range(20.0, 40.0))) - 0.5
		_social_cd[who] = float(_social_cd.get(who, 25.0)) - 0.5
		var c: WorldCharacter = main.characters[who]
		if not c.visible:
			continue
		# camera: only the followed mage, only when it makes sense
		if who == String(main.get("focus")) and cam and _cd[who] <= 0.0 and _idle_enough(who):
			var to_cam := cam.global_position - c.global_position
			var fwd := -c.global_transform.basis.z
			if to_cam.length() < 16.0 and fwd.dot(Vector3(to_cam.x, 0, to_cam.z).normalized()) > 0.0 and _rng.randf() < 0.6:
				glance_camera(who)
				_cd[who] = _rng.randf_range(40.0, 90.0)
			else:
				_cd[who] = _rng.randf_range(6.0, 12.0)      # not a good moment: look again a little later
		# the other mage nearby: a brief look
		if _social_cd[who] <= 0.0 and _idle_enough(who):
			for other in main.characters:
				var oc: WorldCharacter = main.characters[other]
				if other != who and oc.visible and oc.global_position.distance_to(c.global_position) < 9.0:
					c.look_head_at(oc.global_position + Vector3(0, 1.45, 0))
					get_tree().create_timer(_rng.randf_range(1.2, 2.0)).timeout.connect(func(): if is_instance_valid(c) and _idle_enough(who): c.look_head_at(null))
					log.append({"t": snappedf(now, 0.1), "who": who, "event": "glance_at", "at": other})
					break
			_social_cd[who] = _rng.randf_range(30.0, 60.0)


## Meet the camera's eye for a moment (used for idle awareness and when answering a viewer).
func glance_camera(who: String, seconds := -1.0, expression := true) -> void:
	var c: WorldCharacter = main.characters.get(who)
	var cam := get_viewport().get_camera_3d()
	if c == null or cam == null:
		return
	c.look_head_at(cam.global_position)
	var secs := seconds if seconds > 0.0 else _rng.randf_range(1.2, 2.2)
	if expression:
		react(who, "camera")
	log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "who": who, "event": "camera_glance", "seconds": snappedf(secs, 0.1)})
	get_tree().create_timer(secs).timeout.connect(func(): if is_instance_valid(c): c.look_head_at(null))


func describe() -> Dictionary:
	return {"recent": log.slice(maxi(0, log.size() - 8)), "cooldowns": _cd.duplicate()}
