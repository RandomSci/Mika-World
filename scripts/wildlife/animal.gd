class_name Animal
extends Node3D
## A lightweight, deterministic wild animal (no physics body, no AI model): Quaternius CC0 rig + clips.
## States: wander (walk to a nearby point on the navmesh), rest, forage (eat), observe (stop and watch),
## flee (gallop away from a disturbance), investigate (fox: approach a calm Mika), return (go home).
## Reacts only to real events: MagicEvents.magic_event / spell_phase near it, and Mika's distance and pace.
## Moves along navmesh paths so it never walks through walls; it is skipped entirely when far from the
## camera (bounded simulation cost).

var species := "deer"
var model: Node3D
var anim: AnimationPlayer
var area: Node3D
var home := Vector3.ZERO
var home_radius := 10.0
var walk_speed := 0.9
var run_speed := 5.0
var skittish := 6.0             # flee if Mika comes this close while moving fast
var curious := false            # fox
var state := "rest"
var state_t := 0.0
var path: PackedVector3Array = []
var path_i := 0
var flee_from := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var last_reaction := {}
var _clips := {}
var _current := ""
var _sound_cd := 0.0


func setup(p_species: String, glb: String, p_area: Node3D, p_home: Vector3, scale_m: float, seed_v: int) -> void:
	species = p_species
	area = p_area
	home = p_home
	rng.seed = seed_v
	name = "Animal_" + species + "_" + str(seed_v)
	model = (load(glb) as PackedScene).instantiate()
	model.scale = Vector3.ONE * scale_m
	add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 70.0
	anim = model.find_child("AnimationPlayer", true, false)
	for a in anim.get_animation_list():
		var short := String(a).get_slice("|", 1) if String(a).contains("|") else String(a)
		_clips[short] = a
		var res := anim.get_animation(a)
		if short in ["Idle", "Idle_2", "Idle_Headlow", "Idle_2_HeadLow", "Walk", "Gallop", "Eating", "Swimming_Normal", "Swimming_Fast"]:
			res.loop_mode = Animation.LOOP_LINEAR
	match species:
		"fox":
			walk_speed = 1.1
			run_speed = 5.5
			skittish = 4.0
			curious = true
		"stag":
			skittish = 9.0
	MagicEvents.magic_event.connect(_on_magic)
	MagicEvents.spell_phase.connect(_on_phase)
	_play("Idle")


func _play(clip: String, blend := 0.3, speed := 1.0) -> void:
	var real: String = _clips.get(clip, _clips.get("Idle", ""))
	if real == "" or _current == real:
		return
	_current = real
	anim.play(real, blend, speed)


func _ground(p: Vector3) -> float:
	if area and area.has_method("ground_at"):
		return area.ground_at(p.x, p.z)
	return p.y


func _set_state(s: String, dur: float) -> void:
	state = s
	state_t = dur


func _goto(target: Vector3) -> bool:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	path = NavQuery.path(map, NavigationServer3D.map_get_closest_point(map, global_position), NavigationServer3D.map_get_closest_point(map, target), true)
	path_i = 0
	return path.size() > 1


func _mika() -> Node3D:
	var m = get_tree().get_first_node_in_group("player_character")
	return m


## Something magical happened nearby: decide from distance and power, not from a script.
func _on_magic(pos: Vector3, element: String, power: float, effect: String, _id: String) -> void:
	var d := global_position.distance_to(pos)
	var reach := 6.0 + 10.0 * power + (6.0 if effect in ["shattered", "extinguished", "surge"] else 0.0)
	if d < reach:
		_startle(pos, "magic: %s (%s) %.1f m away" % [element, effect, d])


func _on_phase(_c, _sid: String, phase: String, _el: String, pos: Vector3) -> void:
	if phase in ["release", "impact"] and global_position.distance_to(pos) < 7.0:
		_startle(pos, "spell %s %.1f m away" % [phase, global_position.distance_to(pos)])


func _startle(from: Vector3, why: String) -> void:
	if state == "flee":
		return
	flee_from = from
	var away := global_position - from
	away.y = 0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	var dest := global_position + away.normalized() * rng.randf_range(10.0, 16.0)
	_goto(dest)
	_set_state("flee", 6.0)
	last_reaction = {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "reaction": "fled", "why": why}
	if AudioDirector.instance and _sound_cd <= 0.0:
		_sound_cd = 4.0
		AudioDirector.instance.play3d("fox_yip" if species == "fox" else "k:footstep_grass_00%d" % rng.randi_range(0, 4), global_position, "Ambience", -6.0, species + "_flee", 0.8)


func _think() -> void:
	var m := _mika()
	var md := global_position.distance_to(m.global_position) if m else 99.0
	var mika_fast := m != null and Vector2(m.velocity.x, m.velocity.z).length() > 2.5
	var mika_calm: bool = m != null and Vector2(m.velocity.x, m.velocity.z).length() < 0.2 and not m.casting
	if md < skittish and mika_fast:
		_startle(m.global_position, "Mika ran close (%.1f m)" % md)
		return
	if curious and mika_calm and md < 14.0 and md > 3.5 and rng.randf() < 0.35:
		var to := m.global_position + (global_position - m.global_position).normalized() * 3.2
		if _goto(to):
			_set_state("investigate", 12.0)
			last_reaction = {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "reaction": "investigating Mika", "why": "she is calm and still"}
			return
	if md < skittish * 1.6 and rng.randf() < 0.5:
		_set_state("observe", rng.randf_range(2.0, 4.0))
		return
	var r := rng.randf()
	if global_position.distance_to(home) > home_radius * 1.4:
		_goto(home)
		_set_state("return", 20.0)
	elif r < 0.45:
		var a := rng.randf() * TAU
		if _goto(home + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.0, home_radius)):
			_set_state("wander", 25.0)
	elif r < 0.75:
		_set_state("forage", rng.randf_range(5.0, 11.0))
	else:
		_set_state("rest", rng.randf_range(4.0, 9.0))


func _process(delta: float) -> void:
	_sound_cd -= delta
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) > 80.0:
		return   # far away: no simulation, no animation cost
	state_t -= delta
	match state:
		"wander", "return", "flee", "investigate":
			var moving := _follow(delta, run_speed if state == "flee" else walk_speed)
			if state == "flee":
				_play("Gallop", 0.15)
			elif moving:
				_play("Walk")
			if not moving or state_t <= 0.0:
				if state == "investigate":
					_set_state("observe", 5.0)
				else:
					_think()
		"forage":
			_play("Eating")
			if state_t <= 0.0:
				_think()
		"observe":
			_play("Idle_2" if species == "fox" else "Idle_Headlow")
			var m := _mika()
			if m:
				_face(m.global_position, delta)
			if state_t <= 0.0:
				_think()
		_:
			_play("Idle")
			if state_t <= 0.0:
				_think()


func _follow(delta: float, speed: float) -> bool:
	if path_i >= path.size():
		return false
	var target := path[path_i]
	var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if to.length() < 0.3:
		path_i += 1
		return path_i < path.size()
	var step := to.normalized() * minf(speed * delta, to.length())
	var p := global_position + step
	p.y = _ground(p)
	global_position = p
	_face(global_position + to, delta)
	return true


func _face(target: Vector3, delta: float) -> void:
	var d := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if d.length() < 0.01:
		return
	var yaw := atan2(d.x, d.z)   # Quaternius animals face +Z
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-6.0 * delta))


func describe() -> Dictionary:
	return {"species": species, "state": state, "position": [snappedf(global_position.x, 0.1), snappedf(global_position.y, 0.1), snappedf(global_position.z, 0.1)],
		"last_reaction": last_reaction}
