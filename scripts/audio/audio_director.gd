class_name AudioDirector
extends Node
## Event-driven sound for the world. Nothing plays on a timer of its own: every sound answers a real event.
##  * Spells: MagicEvents.spell_phase -> per-element layer (activation chime, rune resonance, gathering hum
##    loop with rising pitch, charge pulse, release whoosh, impact, dissipating shimmer). The phases come
##    from the caster's actual clip time, so audio stays locked to the animation.
##  * Reactions: MagicEvents.magic_event -> smoke puff, steam hiss, crystal shatter, flare...
##  * Books / alchemy: page open / turn / close, pour, stir, bubbling, glow.
##  * Progress: trial completed, rank up, discoveries (clues, locations), portal travel.
##  * Footsteps: from detected foot plants in the animation (foot height minima while moving), with the
##    surface found by a downward ray (grass / stone path / wood / interior stone).
##  * Ambience: beds owned by the active area (positional where they have a source: pond, braziers,
##    Heartstone, watchpoint wind; global forest wind / library tone); birds by day, insects at night.
## All one-shots use a small pool of players; area-owned emitters are freed with the area.

const SYN := "res://assets/audio/synth/"
const KEN := "res://assets/audio/kenney/"

static var instance: AudioDirector

var main: Node
var log: Array = []                 # recent sounds: {t, sound, bus, event}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _streams := {}
var _gather := {}                   # caster id -> {player, start}
var _beds: Array[Node] = []
var _night_bed: AudioStreamPlayer
var _bird_timer := 4.0
var _feet := {}                     # character -> {l_prev, l_dir, r_prev, r_dir, cool}
var muted_categories := {}


func setup(m: Node) -> void:
	main = m
	instance = self
	AudioBuses.ensure()
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 4.0
		p.max_distance = 45.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	for i in 6:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "UI"
		add_child(p2)
		_pool2d.append(p2)
	_night_bed = AudioStreamPlayer.new()
	_night_bed.bus = "Ambience"
	_night_bed.stream = _loop(SYN + "amb_night_insects.ogg")
	_night_bed.volume_db = -8.0
	add_child(_night_bed)
	MagicEvents.spell_phase.connect(_on_phase)
	MagicEvents.magic_event.connect(_on_magic)
	WorldState.trial_completed.connect(func(_tr): play_progress("trial_complete", -2.0, "trial_completed"))
	WorldState.rank_changed.connect(func(_r): play_progress("rank_up", 0.0, "rank_changed"))
	WorldState.state_changed.connect(_on_state)
	WorldState.discovered.connect(func(kind, _id): if kind == "location": play_progress("discovery", -6.0, "discovered"))
	main.streaming.transition_started.connect(func(_a, _b): play2d("portal_whoosh", "UI", -4.0, "portal"))
	main.streaming.area_activated.connect(func(_a, _r): _build_beds())


# ------------------------------------------------------------------ streams
func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


func _loop(path: String) -> AudioStream:
	var s = _stream(path)
	if s is AudioStreamOggVorbis:
		s = (s as AudioStreamOggVorbis).duplicate()
		s.loop = true
	return s


func _path(name: String) -> String:
	if name.begins_with("k:"):
		return KEN + name.substr(2) + ".ogg"
	return SYN + name + ".ogg"


func _note(sound: String, bus: String, event: String) -> void:
	log.append({"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.001), "sound": sound, "bus": bus, "event": event})
	if log.size() > 400:
		log.pop_front()


func play3d(name: String, pos: Vector3, bus := "SFX", db := 0.0, event := "", pitch := 1.0) -> AudioStreamPlayer3D:
	var s := _stream(_path(name))
	if s == null:
		return null
	var p: AudioStreamPlayer3D = null
	for q in _pool3d:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _pool3d[0]
		_pool3d.push_back(_pool3d.pop_front())
	p.stream = s
	p.bus = bus
	p.volume_db = db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()
	_note(name, bus, event)
	return p


## Progress moments (trial, rank, discovery, level): at most one cue every PROGRESS_GAP_S, so a burst of
## achievements never becomes a string of notification sounds (Milestone J). Returns null when skipped.
const PROGRESS_GAP_S := 4.0
var _last_progress := -100.0

func play_progress(name: String, db := 0.0, event := "") -> AudioStreamPlayer:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_progress < PROGRESS_GAP_S:
		return null
	_last_progress = now
	return play2d(name, "UI", db, event)


func play2d(name: String, bus := "UI", db := 0.0, event := "") -> AudioStreamPlayer:
	var s := _stream(_path(name))
	if s == null:
		return null
	var p: AudioStreamPlayer = null
	for q in _pool2d:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _pool2d[0]
	p.stream = s
	p.bus = bus
	p.volume_db = db
	p.play()
	_note(name, bus, event)
	return p


# ------------------------------------------------------------------ spells, reactions, books
func _palette(spell_id: String, element: String) -> String:
	match spell_id:
		"rune_activation": return "rune"
		"elemental_charge": return "self"
		"mist_veil": return "mist"
	return element if element in ["arcane", "wind", "water", "fire", "mist", "umbral"] else "arcane"


func _on_phase(caster: Node, spell_id: String, phase: String, element: String, pos: Vector3) -> void:
	if spell_id == "book":
		match phase:
			"book_open": play3d("k:bookOpen", pos, "SFX", -4.0, phase)
			"page_turn": play3d("k:bookFlip%d" % (1 + randi() % 3), pos, "SFX", -3.0, phase)
			"book_close": play3d("k:bookClose", pos, "SFX", -4.0, phase)
		return
	if spell_id == "portal":
		if phase == "arrive":
			play3d("portal_whoosh", pos + Vector3(0, 1.0, 0), "SFX", -10.0, "portal_arrive", 1.2)
		return
	if spell_id == "alchemy":
		match phase:
			"pour": play3d("pour_liquid", pos, "SFX", -6.0, phase)
			"stir": play3d("alchemy_bubble", pos, "SFX", -6.0, phase)
		return
	var pal := _palette(spell_id, element)
	var key := str(caster.get_instance_id()) if caster else "x"
	match phase:
		"activation":
			play3d("spell_%s_activation" % pal, pos + Vector3(0, 1.2, 0), "SFX", -8.0, phase)
		"rune":
			play3d("spell_%s_rune" % pal, pos + Vector3(0, 1.0, 0), "SFX", -9.0, phase)
		"gather":
			var p := play3d("spell_%s_gather_loop" % pal, pos, "SFX", -14.0, phase, 0.9)
			if p:
				_gather[key] = {"player": p, "start": Time.get_ticks_msec(), "caster": caster}
		"charge":
			play3d("spell_%s_charge" % pal, pos, "SFX", -6.0, phase)
		"release":
			_stop_gather(key)
			play3d("spell_%s_release" % pal, pos, "SFX", -5.0, phase)
		"impact":
			play3d("spell_%s_impact" % pal, pos, "SFX", -3.0, phase)
		"blocked", "missed":
			play3d("spell_%s_impact" % pal, pos, "SFX", -10.0, phase, 0.85)
		"dissipate":
			_stop_gather(key)
			play3d("spell_%s_dissipate" % pal, pos + Vector3(0, 1.0, 0), "SFX", -10.0, phase)


func _stop_gather(key: String) -> void:
	if _gather.has(key):
		var g: Dictionary = _gather[key]
		var p: AudioStreamPlayer3D = g.player
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -40.0, 0.25)
		tw.tween_callback(p.stop)
		_gather.erase(key)


func _on_magic(pos: Vector3, _element: String, _power: float, effect: String, _id: String) -> void:
	match effect:
		"extinguished", "doused":
			play3d("smoke_puff", pos, "SFX", -4.0, effect)
		"steam", "misted_steam", "misted_doused":
			play3d("steam_hiss", pos, "SFX", -6.0, effect)
		"shattered":
			play3d("crystal_shatter", pos, "SFX", -2.0, effect)
		"flare", "relit":
			play3d("spell_fire_release", pos, "SFX", -6.0, effect, 0.8)
		"surge", "ripple", "ruffled":
			play3d("spell_water_impact", pos, "SFX", -9.0, effect, 1.1)
		"resonance":
			play3d("spell_arcane_charge", pos, "SFX", -4.0, effect, 0.6)
		"revealed":
			play3d("discovery", pos, "SFX", -2.0, effect)
		"rang":
			play3d("k:impactGlass_light_00%d" % (randi() % 3), pos, "SFX", -6.0, effect)


func _on_state(entry: Dictionary) -> void:
	var ch: Dictionary = entry.get("changes", {})
	for k in ch:
		if String(k).begins_with("knowledge.clue:"):
			play_progress("discovery", -6.0, "clue")
			return
		if String(k) == "inventory.luminous_draught":
			play2d("alchemy_glow", "UI", -6.0, "crafted")
			return


# ------------------------------------------------------------------ interactions
func on_interaction(it: Node, phase: String, c: Node) -> void:
	if it == null or c == null:
		return
	var pos: Vector3 = (c as Node3D).global_position + Vector3(0, 0.8, 0)
	if phase == "start" and String(it.get("gesture")) == "sit":
		play3d("cloth_settle", pos, "SFX", -6.0, "sit")
	elif phase == "grasp":
		play3d("k:handleSmallLeather", pos + Vector3(0, 0.3, 0), "SFX", -8.0, "pick_up")
	elif phase == "place":
		play3d("k:impactGlass_light_00%d" % (randi() % 3), pos, "SFX", -10.0, "place")


# ------------------------------------------------------------------ footsteps (from the animation)
func _footsteps(c: WorldCharacter, delta: float) -> void:
	var speed := Vector2(c.velocity.x, c.velocity.z).length()
	var st: Dictionary = _feet.get_or_add(c, {"l": 0.0, "ld": 0.0, "r": 0.0, "rd": 0.0, "cool_l": 0.0, "cool_r": 0.0})
	st.cool_l -= delta
	st.cool_r -= delta
	if speed < 0.25 or not c.is_on_floor():
		return
	for side in ["l", "r"]:
		var bone := "LeftFoot" if side == "l" else "RightFoot"
		var idx := c.skeleton.find_bone(bone)
		var y := (c.skeleton.global_transform * c.skeleton.get_bone_global_pose(idx)).origin.y - c.global_position.y
		var dy: float = y - float(st[side])
		# a plant = the foot stops descending (local minimum) near the ground
		if float(st[side + "d"]) < -0.0005 and dy >= 0.0 and y < 0.16 and float(st["cool_" + side]) <= 0.0:
			_step(c, speed)
			st["cool_" + side] = 0.22
		st[side + "d"] = dy
		st[side] = y


func _step(c: WorldCharacter, speed: float) -> void:
	if speed > 3.2 and main.get("spawner"):
		main.spawner.hear(c.global_position, 8.0, "steps")   # running is loud enough for a creature to notice
	var space := c.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(c.global_position + Vector3(0, 0.3, 0), c.global_position - Vector3(0, 0.5, 0))
	q.exclude = [c.get_rid()]
	var hit := space.intersect_ray(q)
	var surface := "concrete"
	if not hit.is_empty():
		var col = hit.collider
		var n := String((col as Node).name) if col is Node else ""
		if n == "Terrain" or n.begins_with("Terrain"):
			surface = "grass"
			if main.world.has_method("sub_area_at") and SanctuaryTerrain.dist_to_paths(Vector2(c.global_position.x, c.global_position.z)) < 1.3:
				surface = "dirt"
			if WorldState.areas.get(main.streaming.current_id, {}).get("interior", false):
				surface = "concrete"
		elif col is Node and (col as Node).get_parent() and String((col as Node).get_parent().name).to_lower().contains("wood"):
			surface = "wood"
	var name := ("k:footstep0%d" % (randi() % 10)) if surface == "dirt" else "k:footstep_%s_00%d" % [surface, randi() % 5]
	play3d(name, c.global_position, "SFX", (-16.0 if speed < 2.0 else -12.0), "footstep_" + surface, randf_range(0.92, 1.08))


# ------------------------------------------------------------------ ambience
func _bed(parent: Node, name: String, pos, db: float, max_d := 30.0) -> void:
	var s := _loop(SYN + name + ".ogg")
	if s == null:
		return
	if pos == null:
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "Ambience"
		p.volume_db = db
		p.autoplay = true
		parent.add_child(p)
		_beds.append(p)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = s
		p3.bus = "Ambience"
		p3.volume_db = db
		p3.unit_size = 5.0
		p3.max_distance = max_d
		p3.autoplay = true
		parent.add_child(p3)
		p3.global_position = pos
		_beds.append(p3)


func _build_beds() -> void:
	_beds = _beds.filter(func(b): return is_instance_valid(b))
	var w: Node3D = main.world
	if w == null:
		return
	var interior: bool = WorldState.areas.get(main.streaming.current_id, {}).get("interior", false)
	var holder := Node.new()
	holder.name = "AmbienceBeds"
	w.add_child(holder)   # owned by the area: freed when it unloads
	if interior:
		_bed(holder, "amb_library", null, -6.0)
	else:
		_bed(holder, "amb_forest_wind", null, -10.0)
	if w is Sanctuary:
		_bed(holder, "amb_pond", Vector3(SanctuaryTerrain.POND.x, 0.2, SanctuaryTerrain.POND.y), -4.0, 22.0)
		for b in w.find_children("brazier_*", "Brazier", true, false):
			_bed(holder, "amb_fire_crackle", (b as Node3D).global_position + Vector3(0, 0.4, 0), -6.0, 12.0)
		_bed(holder, "amb_heartstone", Vector3(SanctuaryTerrain.CHAMBER.x - 2.6, 1.8, SanctuaryTerrain.CHAMBER.y), -6.0, 11.0)
		_bed(holder, "amb_watchpoint_wind", Vector3(SanctuaryTerrain.WATCH.x, 3.0, SanctuaryTerrain.WATCH.y), -4.0, 18.0)
	elif w is WhisperingWoods:
		var ww: WhisperingWoods = w
		# the falls roar (heard from the viewpoint and the bridge), the river babbling along its course,
		# the hidden pond, and the den's slow cave breath
		_bed(holder, "amb_waterfall", Vector3(ww.FALLS.x, ww.pool_water_y() + 4.0, ww.FALLS.y + 2.0), 0.0, 60.0)
		var z := -110.0
		while z < 130.0:
			if absf(z - ww.FALLS.y) > 14.0:
				_bed(holder, "amb_stream", Vector3(ww.river_x(z), ww.height(ww.river_x(z), z) + 1.5, z), -5.0, 22.0)
			z += 30.0
		_bed(holder, "amb_pond", Vector3(ww.POND.x, ww.height(ww.POND.x, ww.POND.y) + 1.8, ww.POND.y), -4.0, 26.0)
		var cave := ww.DEN_MOUTH - ww.DEN_FACE * 3.0
		_bed(holder, "amb_den", Vector3(cave.x, ww.height(cave.x, cave.y) + 1.5, cave.y), -2.0, 24.0)


func _process(delta: float) -> void:
	if main == null or main.world == null:
		return
	# rising gathering hum: pitch climbs as the spell gathers power
	for k in _gather.keys():
		var g: Dictionary = _gather[k]
		var p: AudioStreamPlayer3D = g.player
		var age := (Time.get_ticks_msec() - int(g.start)) / 1000.0
		p.pitch_scale = 0.9 + minf(age * 0.18, 0.45)
		p.volume_db = minf(-14.0 + age * 4.0, -7.0)
		if is_instance_valid(g.caster):
			p.global_position = (g.caster as Node3D).global_position + Vector3(0, 1.2, 0)
		if age > 8.0:
			_stop_gather(k)
	for c in main.characters.values():
		_footsteps(c, delta)
	var outdoor: bool = not WorldState.areas.get(main.streaming.current_id, {}).get("interior", false)
	var want_night := WorldState.night and outdoor
	if want_night != _night_bed.playing:
		if want_night:
			_night_bed.play()
		else:
			_night_bed.stop()
	if outdoor and not WorldState.night:
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			_bird_timer = randf_range(3.0, 11.0)
			var m: Node3D = main.characters["mika"]
			var a := randf() * TAU
			play3d("bird_chirp_%d" % (randi() % 6), m.global_position + Vector3(cos(a) * randf_range(12, 26), randf_range(5, 11), sin(a) * randf_range(12, 26)), "Ambience", -6.0, "bird")


func describe() -> Dictionary:
	return {"buses": AudioBuses.describe(), "beds": _beds.filter(func(b): return is_instance_valid(b)).size(), "recent": log.slice(maxi(0, log.size() - 12))}
