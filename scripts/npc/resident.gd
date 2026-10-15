class_name Resident
extends Node3D
## One person who LIVES in a town (TownLife, data/residents.json; docs/TOWN_LIFE.md). Their day comes from their
## schedule ([hour, activity, anchor]); they walk the navmesh between the places of their day (never jump), work
## with the clip of their trade, sit to eat, stand together on the square and talk, go in at their door for the
## night and come out in the morning. They notice the mages: turn, nod, and now and then say something in their
## own voice (once a day each, a shared cooldown so the town is not a chorus). Quaternius CC0 townsfolk rigs built by
## tools/models/build_rival.py --clipset townsfolk.

const LOOPS := ["idle", "idle_arms", "talk", "walk", "walk_formal", "run", "carry", "push", "sit", "sit_talk", "chop",
	"crouch", "lantern", "torch", "lean_rail", "dance", "cast_idle", "no", "flee"]
const WALK_SPEED := 1.15
const ANIM_WALK_SPEED := 1.25      # the walk clip's own ground speed (m/s): the playback rate follows the real pace

var id := ""
var data := {}
var town: Node                     # TownLife
var area: Node3D
var model: Node3D
var anim: AnimationPlayer
var def := {"radius": 0.3}          # the mages steer round residents ("avoid" group)
var state := "idle"                 # walking / at:<activity> / inside / greeting
var activity := ""
var anchor_key := ""
var block := -1
var log: Array = []                 # what they did today [{t, what}] (tests, observation)
var _clip := ""
var _path: PackedVector3Array = []
var _pi := 0
var _speed := WALK_SPEED
var _walk_clip := "walk"
var _face_yaw := INF
var _look_at: Node3D = null
var _look_until := 0.0
var _gen := 0                       # bumps when the plan changes (a running activity coroutine stops)
var _door := ""                     # the anchor of the door they went in by (they come out of the same one)
var rng := RandomNumberGenerator.new()
var _hangs := {}                     # clip -> a hanging tool kept upright under the fist (Grip.hang)
var tools := {}                     # clip -> the prop in their hand while they do it (an axe for chopping ...)


func setup(p_id: String, p_data: Dictionary, p_town: Node, p_area: Node3D) -> void:
	id = p_id
	data = p_data
	town = p_town
	area = p_area
	name = "Resident_" + id
	rng.seed = hash(id + str(WorldState.day()))
	model = (load(String(data.model)) as PackedScene).instantiate()
	add_child(model)
	var top := 0.0
	for skn in model.find_children("*", "Skeleton3D", true, false):
		var sk: Skeleton3D = skn
		for bi in sk.get_bone_count():
			top = maxf(top, (sk.global_transform * sk.get_bone_global_rest(bi)).origin.y - model.global_position.y)
	if top > 0.05:
		model.scale = Vector3.ONE * (float(data.get("height_m", 1.72)) * 0.93 / top)
	# their own colours (data "recolor": {material name prefix: [r, g, b]} multiplied over the outfit / hair):
	# the same tailor's pattern, a different person
	var rc: Dictionary = data.get("recolor", {})
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if rc.is_empty() or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if not (src is BaseMaterial3D):
				continue
			for pre in rc:
				if String(src.resource_name).begins_with(String(pre)):
					var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
					var cc: Array = rc[pre]
					mat.albedo_color = mat.albedo_color * Color(cc[0], cc[1], cc[2])
					m.set_surface_override_material(si, mat)
	anim = model.find_child("AnimationPlayer", true, false)
	if anim:
		for a in anim.get_animation_list():
			if String(a) in LOOPS:
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_make_tools()
	add_to_group("avoid")
	add_to_group("residents")
	_walk_clip = "walk_formal" if String(data.get("gait", "")) == "formal" or String(data.get("role", "")).contains("teacher") else "walk"


## The tools of their trade (data "tools": {clip: {model, bone, pos, rot, scale}}), held in the hand while that
## clip plays and put away otherwise (BoneAttachment3D: the hand carries it through the motion).
func _make_tools() -> void:
	var sk: Skeleton3D = null
	for n in model.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if sk == null:
		return
	var spec: Dictionary = data.get("tools", {})
	for clip in spec:
		var t: Dictionary = spec[clip]
		var bone := String(t.get("bone", "hand_r"))
		if sk.find_bone(bone) < 0:
			continue
		var ba := BoneAttachment3D.new()
		ba.bone_name = bone
		sk.add_child(ba)
		var holder := Node3D.new()
		ba.add_child(holder)
		var sc := float(t.get("scale", 1.0))
		Kit.place_prop_all(holder, String(t.model), Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3.ZERO))
		# held as a hand holds it (Grip): measured from the hand bones and from the prop itself
		var side := "l" if bone.ends_with("_l") else "r"
		var hand_grip := Grip.hand_frame(sk, side)
		var kind := String(t.get("grip", "hang" if (String(t.model).contains("lantern") or String(t.model).contains("bucket")) else "tool"))
		if hand_grip.basis == Basis() and hand_grip.origin == Vector3.ZERO:
			kind = "legacy"
		match kind:
			"tool":
				var tf := Grip.tool_frame(holder)
				if not tf.is_empty():
					holder.transform = hand_grip * (tf.xf as Transform3D).affine_inverse()
			"hang":
				holder.top_level = true
				_hangs[clip] = {"holder": holder, "hand": ba, "grip": hand_grip, "at": Grip.hang_point(holder)}
			_:
				var pp: Array = t.get("pos", [0, 0, 0])
				var rr: Array = t.get("rot", [0, 0, -90])
				holder.position = Vector3(pp[0], pp[1], pp[2])
				holder.rotation_degrees = Vector3(rr[0], rr[1], rr[2])
		holder.visible = false
		tools[clip] = holder


func play(clip: String, blend := 0.3, rate := 1.0) -> void:
	if anim == null:
		return
	for k in tools:
		(tools[k] as Node3D).visible = k == clip
		if k == clip and _hangs.has(k):
			var hh: Dictionary = _hangs[k]
			Grip.hang(hh.holder, hh.hand, hh.grip, hh.at, global_rotation.y)    # in her hand from the first frame
	if not anim.has_animation(clip):
		clip = "idle"
	if clip == _clip and rate == anim.speed_scale:
		return
	_clip = clip
	anim.play(clip, blend)
	anim.speed_scale = rate


func clip_len(clip: String) -> float:
	return anim.get_animation(clip).length if anim and anim.has_animation(clip) else 1.0


func _note(what: String) -> void:
	log.append({"t": WorldState.clock_text(), "what": what})
	if log.size() > 60:
		log.pop_front()


# ------------------------------------------------------------------ the day
## The schedule block for an hour: [index, activity, anchor key].
func block_at(h: float) -> Array:
	var sch: Array = data.get("schedule", [])
	var cur: Array = sch[sch.size() - 1] if not sch.is_empty() else [0, "idle", "home"]
	var idx := sch.size() - 1
	for i in sch.size():
		if float(sch[i][0]) <= h:
			cur = sch[i]
			idx = i
	return [idx, String(cur[1]), String(cur[2])]


func resolve_anchor(key: String) -> String:
	if key == "home":
		return String(data.get("home", "home:0"))
	if key == "work":
		return String(data.get("work", "square:0"))
	if key == "lamp":
		# the watch walks from lamp to lamp
		var lamps: Array = area.anchors.keys().filter(func(k): return String(k).begins_with("lamp:"))
		return String(lamps[rng.randi() % lamps.size()]) if not lamps.is_empty() else "square:0"
	return key


func anchor(key: String) -> Dictionary:
	return area.anchors.get(key, area.anchors.get("square:0", {"pos": global_position, "yaw": rotation.y, "inside": false}))


## Where they are when the area loads: at the place of the current block, already doing it (or inside).
func place_now() -> void:
	var b := block_at(WorldState.hour_f())
	block = int(b[0])
	activity = String(b[1])
	anchor_key = resolve_anchor(String(b[2]))
	var a := anchor(anchor_key)
	var p: Vector3 = town.spot_for(self, anchor_key, a)
	global_position = _ground(p)
	rotation.y = float(a.yaw)
	if activity == "sleep":
		_go_inside()
	else:
		visible = true
		state = "at:" + activity
		_face_yaw = float(a.yaw)
		_begin_activity()


## Never walk into something solid (a bench, a wall, a stall): a knee-high probe ahead; if it is blocked, the
## nearest free heading within 80 degrees (they slide round it), else they stop for this frame.
func _clear_step(dir: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var base := global_position + Vector3(0, 0.3, 0)
	for off: float in [0.0, 0.45, -0.45, 0.9, -0.9, 1.4, -1.4]:
		var d := dir.rotated(Vector3.UP, off)
		var q := PhysicsRayQueryParameters3D.create(base, base + d * 0.55, 1)
		if space.intersect_ray(q).is_empty():
			return d
	return Vector3.ZERO


func _ground(p: Vector3) -> Vector3:
	if area.has_method("ground_at"):
		p.y = float(area.ground_at(p.x, p.z))
	return p


func _process(delta: float) -> void:
	for hk in _hangs:
		var hh: Dictionary = _hangs[hk]
		if (hh.holder as Node3D).visible:
			Grip.hang(hh.holder, hh.hand, hh.grip, hh.at, global_rotation.y)
	if area == null or not is_instance_valid(area):
		return
	var b := block_at(WorldState.hour_f())
	if int(b[0]) != block:
		block = int(b[0])
		if _sheltering:
			_resume = [String(b[1]), resolve_anchor(String(b[2]))]     # the hour changed in the rain: go on with it after
		else:
			_change_to(String(b[1]), resolve_anchor(String(b[2])))
	_rain_check()
	if state == "walking":
		if not _follow(delta):
			_arrived()
	elif _face_yaw != INF and state != "inside":
		rotation.y = lerp_angle(rotation.y, _face_yaw, 1.0 - exp(-5.0 * delta))
	if _look_at and is_instance_valid(_look_at) and Time.get_ticks_msec() / 1000.0 < _look_until:
		var d := _look_at.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-6.0 * delta))


## Rain: whoever is out in it with no roof or awning over their place goes to the nearest doorstep (under its door
## hood) and waits it out; when it eases off they go back to what their hour holds. Indoors, asleep or already
## under cover, they carry on.
var _sheltering := false
var _resume: Array = []
var _rain_t := 0.0

func _rain_check() -> void:
	_rain_t += get_process_delta_time()
	if _rain_t < 1.0:
		return
	_rain_t = 0.0
	var wx = town.main.get("weather") if town and town.main else null
	if wx == null:
		return
	var raining: bool = float(wx.rain) > 0.45 and not wx.sheltered_area()
	if raining and not _sheltering and state != "inside" and activity != "sleep":
		var here: Vector3 = anchor(anchor_key).pos
		if wx.covered(here):
			return                       # a stall awning, a porch: dry where they are
		# home, if they have one here: indoors until it passes
		var home_key := String(data.get("home", ""))
		_sheltering = true
		_resume = [activity, anchor_key]
		if home_key != "" and area.anchors.has(home_key):
			_note("the rain: home, indoors (" + home_key + ")")
			_change_to("shelter_in", home_key)
			return
		# no home here: the nearest doorstep that is really covered and nobody else is standing at
		var best := ""
		var bd := INF
		for k in area.anchors:
			if not String(k).begins_with("home:") or not wx.covered(area.anchors[k].pos) or TownLife.shelter_taken(area, String(k), self):
				continue
			var d: float = (area.anchors[k].pos as Vector3).distance_to(global_position)
			if d < bd:
				bd = d
				best = String(k)
		if best == "":
			_sheltering = false
			_resume = []
			return
		_note("the rain: sheltering at " + best)
		_change_to("shelter", best)
	elif not raining and _sheltering:
		_sheltering = false
		var r := _resume
		_resume = []
		_note("the rain has eased: back to " + (String(r[0]) if not r.is_empty() else "the day"))
		if not r.is_empty():
			_change_to(String(r[0]), String(r[1]))
		else:
			block = -1


func _change_to(act: String, key: String) -> void:
	_gen += 1
	activity = act
	var was_inside := state == "inside"
	anchor_key = key
	if was_inside:
		# out of the door first
		var door := anchor(_door if _door != "" else String(data.get("home", "home:0")))
		global_position = _ground(door.pos)
		rotation.y = float(door.yaw)
		visible = true
		_note("came out of the house")
	var a := anchor(key)
	var to: Vector3 = town.spot_for(self, key, a)
	_note("walks to %s (%s)" % [key, act])
	if global_position.distance_to(to) < 0.6:
		_arrived()
		return
	_walk_to(to)


func _walk_to(p: Vector3) -> void:
	var map := get_world_3d().navigation_map
	_path = NavQuery.path(map, NavigationServer3D.map_get_closest_point(map, global_position), NavigationServer3D.map_get_closest_point(map, p), true)
	_pi = 1
	if _path.size() < 2:
		_path = PackedVector3Array([global_position, p])
	state = "walking"
	_speed = WALK_SPEED * (0.85 if _walk_clip == "walk_formal" else 1.0) * (0.85 if activity == "draw_water" else 1.0)
	play(_walk_clip, 0.3, _speed / ANIM_WALK_SPEED)
	_face_yaw = INF


func _follow(delta: float) -> bool:
	if _pi >= _path.size():
		return false
	var target := _path[_pi]
	var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if to.length() < 0.3:
		_pi += 1
		return _pi < _path.size()
	# keep out of the mages' way (and of each other's): a little sidestep, never through them
	var dir := to.normalized()
	for n in get_tree().get_nodes_in_group("avoid"):
		if n == self or not (n as Node3D).is_visible_in_tree():
			continue
		var away := global_position - (n as Node3D).global_position
		away.y = 0
		var d := away.length()
		if d > 0.01 and d < 1.2:
			dir = (dir + away.normalized() * (1.2 - d) * 1.5).normalized()
	dir = _clear_step(dir)
	global_position = _ground(global_position + dir * minf(_speed * delta, to.length()))
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * delta))
	return true


func _arrived() -> void:
	state = "at:" + activity
	var a := anchor(anchor_key)
	_face_yaw = float(a.yaw)
	if bool(a.get("inside", false)) and activity in ["sleep", "study", "work", "shelter_in"]:
		_go_inside()
		return
	_begin_activity()


func _go_inside() -> void:
	state = "inside"
	_door = anchor_key if bool(anchor(anchor_key).get("inside", false)) else String(data.get("home", "home:0"))
	visible = false
	_note("went inside (%s)" % activity)


# ------------------------------------------------------------------ activities
func _begin_activity() -> void:
	_gen += 1
	_note(activity + " at " + anchor_key)
	_run(_gen)


func _run(gen: int) -> void:
	var w := 0.0
	while gen == _gen and is_inside_tree():
		match activity:
			"work":
				var clips: Array = data.get("work_clips", ["interact"])
				var c := String(clips[rng.randi() % clips.size()])
				play(c, 0.35)
				w = clip_len(c) * (rng.randi_range(2, 4) if c in LOOPS else 1.0)
			"vend":
				play(["idle", "interact", "idle_arms", "pickup"][rng.randi() % 4], 0.4)
				w = rng.randf_range(4.0, 9.0)
			"shop":
				play(["talk", "idle", "pickup"][rng.randi() % 3], 0.4)
				w = rng.randf_range(4.0, 8.0)
			"draw_water":
				play("interact", 0.3)
				w = clip_len("interact") + 1.0
				if gen == _gen:
					await get_tree().create_timer(w).timeout
					if gen != _gen:
						return
					# carry it home
					_walk_clip = "carry"
					_change_to("carry_home", String(data.get("home", "home:0")))
					_walk_clip = "walk"
					return
			"eat", "attend":
				play("sit_enter", 0.3)
				await get_tree().create_timer(clip_len("sit_enter") * 0.95).timeout
				while gen == _gen:
					play("sit_talk" if (activity == "eat" and town.someone_near(self, 3.0)) or rng.randf() < 0.12 else "sit", 0.4)
					await get_tree().create_timer(rng.randf_range(5.0, 10.0)).timeout
				return
			"socialize":
				var other: Node3D = town.someone_near(self, 3.5)
				if other:
					_face_yaw = atan2(other.global_position.x - global_position.x, other.global_position.z - global_position.z)
				play("talk" if other and rng.randf() < 0.6 else ["idle", "idle_arms", "yes"][rng.randi() % 3], 0.4)
				w = rng.randf_range(3.0, 7.0)
			"patrol":
				play("lantern" if WorldState.night else "idle_arms", 0.4)
				w = rng.randf_range(20.0, 40.0)
				await get_tree().create_timer(w).timeout
				if gen == _gen:
					_change_to("patrol", resolve_anchor("lamp"))
				return
			"watch", "stroll":
				play(["idle_arms", "idle", "lean_rail" if activity == "watch" else "idle"][rng.randi() % 3], 0.4)
				w = rng.randf_range(6.0, 12.0)
			"teach":
				play(["talk", "talk", "cast_enter", "idle_arms"][rng.randi() % 4], 0.4)
				w = rng.randf_range(4.0, 8.0)
				if _clip == "cast_enter" and gen == _gen:
					await get_tree().create_timer(clip_len("cast_enter")).timeout
					play("cast", 0.2)
					town.spell_spark(self)
					w = clip_len("cast")
			"practice":
				play("cast_enter", 0.3)
				await get_tree().create_timer(clip_len("cast_enter")).timeout
				if gen != _gen:
					return
				play("cast_idle", 0.2)
				await get_tree().create_timer(rng.randf_range(0.8, 2.0)).timeout
				if gen != _gen:
					return
				play("cast", 0.15)
				town.spell_spark(self)
				await get_tree().create_timer(clip_len("cast")).timeout
				if gen != _gen:
					return
				play("cast_exit", 0.2)
				w = clip_len("cast_exit") + rng.randf_range(1.5, 4.0)
				if rng.randf() < 0.3:
					play("no" if rng.randf() < 0.5 else "yes", 0.3)
			"carry_home":
				_go_inside()
				return
			"shelter":
				# waiting out the rain under a door hood: arms folded, a glance up at the sky now and then
				play("idle_arms" if anim and anim.has_animation("idle_arms") else "idle", 0.5)
				w = rng.randf_range(6.0, 11.0)
			_:
				play("idle", 0.4)
				w = rng.randf_range(4.0, 8.0)
		await get_tree().create_timer(maxf(w, 0.5)).timeout


# ------------------------------------------------------------------ the mages
## Called by TownLife when a mage comes close: turn to her, nod, perhaps speak (TownLife decides who may speak).
func notice(mage: Node3D, speak: bool) -> void:
	_look_at = mage
	_look_until = Time.get_ticks_msec() / 1000.0 + 3.0
	if state == "walking" or activity in ["eat", "attend"]:
		return
	var prev := _clip
	play("yes", 0.25)
	get_tree().create_timer(clip_len("yes")).timeout.connect(func(): if _clip == "yes": play(prev, 0.35))
	if speak:
		var pool: Array = data.get("lines", {}).get("night" if WorldState.night and data.get("lines", {}).has("night") else ("teach" if activity == "teach" else "greet"), [])
		if not pool.is_empty() and town.main.get("voice"):
			town.main.voice.say(String(data.get("voice", id)), String(pool[rng.randi() % pool.size()]), {"max_wait": 3.0})
		_note("spoke to " + String(mage.get("character_id")))


func describe(from: Vector3) -> Dictionary:
	return {"id": id, "name": data.get("name", id), "role": data.get("role", ""), "doing": activity, "state": state,
		"distance": snappedf(from.distance_to(global_position), 0.1), "visible": visible}
