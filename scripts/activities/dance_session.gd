class_name DanceSession
extends Node
## A dance in progress, resumable (2026-10-19): the small wrapper round the dancers' DanceDecks (scripts/anime/
## dance_deck.gd) that keeps the song position and drives a routine - [[song_t, who | "both", clip, start s, speed,
## fade s], ...] - so a restart picks the dance up at the same clip, the same clip time and the same place in the song.
## In group "persistent_activity" (ScenePersist): persist_key / snapshot / restore.
##
## The song itself is mixed outside the engine (the MV cut is timed to it); song_t is its clock here.

var dancers := {}                 # who -> {c: WorldCharacter, deck: DanceDeck}
var routine: Array = []
var song_t := 0.0
var song_to := -1.0               # stop here (< 0: no end)
var playing := false
var tag := "dance"
var _done := {}                   # routine step index -> true


## Start a dance: each dancer gets her dance stack (deck + softness + cords), the routine plays from `from_t`.
static func begin(parent: Node, chars: Array, p_routine: Array, from_t := 0.0, to_t := -1.0, p_tag := "dance") -> DanceSession:
	var s := DanceSession.new()
	s.name = "DanceSession"
	s.tag = p_tag
	s.routine = p_routine.duplicate(true)
	s.song_t = from_t
	s.song_to = to_t
	parent.add_child(s)
	for c in chars:
		s.add_dancer(c)
	s.playing = true
	s._apply_routine(true)
	return s


func _ready() -> void:
	add_to_group("persistent_activity")


## Her dance stack (made once: the deck first in her modifiers, then BodyLife, SoftArms, TasselSway).
func add_dancer(c: WorldCharacter) -> DanceDeck:
	var deck: DanceDeck = null
	for n in c.skeleton.get_children():
		if n is DanceDeck:
			deck = n
	if deck == null:
		deck = DanceDeck.make(c.skeleton)
		var life := BodyLife.make(c.skeleton, 1)
		deck.set_meta("life", life)
		SoftArms.make(c.skeleton, 2)
		TasselSway.make(c.skeleton, 3)
	dancers[c.character_id] = {"c": c, "deck": deck}
	c.set_meta("persist_activity", persist_key())      # (others leave a dancer on her mark)
	return deck


func deck_of(who: String) -> DanceDeck:
	return dancers.get(who, {}).get("deck")


## [clip, clip time, speed] the routine has `who` dancing at song time t ([] before her first step).
func expected(who: String, t: float) -> Array:
	var best: Array = []
	for st in routine:
		if float(st[0]) <= t and (String(st[1]) == "both" or String(st[1]) == who):
			best = st
	if best.is_empty():
		return []
	return [String(best[2]), float(best[3]) + (t - float(best[0])) * float(best[4]), float(best[4])]


func _process(delta: float) -> void:
	if not playing:
		return
	song_t += delta / maxf(Engine.time_scale, 0.001)     # (the song keeps its pace through a slow-motion moment)
	_apply_routine(false)
	if song_to >= 0.0 and song_t >= song_to:
		playing = false
		for who in dancers:
			if is_instance_valid(dancers[who].c):
				(dancers[who].c as Node).remove_meta("persist_activity")


func _apply_routine(jump: bool) -> void:
	for i in routine.size():
		var st: Array = routine[i]
		if _done.has(i) or song_t < float(st[0]):
			continue
		_done[i] = true
		if jump:
			continue
		for who in dancers:
			if String(st[1]) == "both" or String(st[1]) == who:
				var d: DanceDeck = dancers[who].deck
				if d.influence < 1.0:
					create_tween().tween_property(d, "influence", 1.0, float(st[5]))
				d.play(String(st[2]), float(st[3]), float(st[4]), float(st[5]))
	if jump:
		for who in dancers:
			var ex := expected(who, song_t)
			if not ex.is_empty():
				var d: DanceDeck = dancers[who].deck
				d.influence = 1.0
				d.play(String(ex[0]), float(ex[1]), float(ex[2]), 0.01)


# ------------------------------------------------------------------------------------------------- persistence
func persist_key() -> String:
	return "dance:" + tag


func persist_step() -> String:
	var parts := ["playing" if playing else "stopped", "step %d" % _done.size()]
	for who in dancers:
		var d: DanceDeck = dancers[who].deck
		if is_instance_valid(d):
			parts.append("%s=%s" % [who, d.current()])
	return ",".join(parts)


func snapshot() -> Dictionary:
	var ds := {}
	for who in dancers:
		var c: WorldCharacter = dancers[who].c
		var d: DanceDeck = dancers[who].deck
		if not is_instance_valid(c) or not is_instance_valid(d):
			continue
		var cur: Dictionary = d.get("_cur")
		ds[who] = {"clip": String(cur.get("clip", "")), "t": snappedf(float(cur.get("t", 0.0)), 0.0001), "speed": float(cur.get("speed", 1.0)),
			"influence": snappedf(d.influence, 0.001), "pos": [c.global_position.x, c.global_position.y, c.global_position.z],
			"yaw": c.global_rotation.y, "physics": c.is_physics_processing()}
	if ds.is_empty():
		return {}
	return {"kind": "dance", "step": persist_step(), "tag": tag, "song_t": snappedf(song_t, 0.0001), "song_to": song_to, "playing": playing,
		"routine": routine, "done": _done.keys(), "dancers": ds, "participants": ds.keys()}


## Back on her mark, the same clip at the same clip time, the song where it was.
func restore(d: Dictionary) -> void:
	tag = String(d.get("tag", tag))
	name = "DanceSession"
	routine = (d.get("routine", []) as Array).duplicate(true)
	song_t = float(d.get("song_t", 0.0))
	song_to = float(d.get("song_to", -1.0))
	_done.clear()
	for i in (d.get("done", []) as Array):
		_done[int(i)] = true
	var m := get_tree().current_scene
	var guard = m.get("teleport_guard") if m else null
	var chars := {}
	for c in get_tree().get_nodes_in_group("mage"):
		chars[String(c.get("character_id"))] = c
	var ds: Dictionary = d.get("dancers", {})
	for who in ds:
		var c: WorldCharacter = chars.get(who)
		if c == null:
			continue
		var e: Dictionary = ds[who]
		if guard:
			guard.allow(c)
		c.stop_action()
		c.set_physics_process(bool(e.get("physics", false)))
		c.velocity = Vector3.ZERO
		c.visible = true
		var p: Array = e.get("pos", [])
		if p.size() == 3:
			c.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		c.global_rotation.y = float(e.get("yaw", c.global_rotation.y))
		var dk := add_dancer(c)
		dk.influence = float(e.get("influence", 1.0))
		dk.play(String(e.get("clip", "dancing_a")), float(e.get("t", 0.0)), float(e.get("speed", 1.0)), 0.01)
	playing = bool(d.get("playing", true))
