class_name TravelerNPC
extends Node3D
## A visiting traveller (Quaternius CC0 character rig). Arrives along a real route into the Sanctuary,
## walks the navmesh to its usual spot, idles with small gestures, turns to face whoever it talks to,
## gestures while speaking, and leaves the way it came. It remembers what it witnessed while present
## (real MagicEvents within sight), which is the only way it can comment on Mika's magic.

var id := ""
var data := {}
var model: Node3D
var anim: AnimationPlayer
var area: Node3D
var state := "arriving"        # arriving, idle, talking, leaving, gone
var path: PackedVector3Array = []
var path_i := 0
var speed := 1.25
var exit_point := Vector3.ZERO
var witnessed: Array = []      # [{effect, element, object, t}]
var talking := false
var talk_target: Node3D = null
var _clips := {}
var _current := ""
var _gesture_t := 6.0
var rng := RandomNumberGenerator.new()


func setup(p_id: String, p_data: Dictionary, p_area: Node3D, entry: Vector3, exit_p: Vector3) -> void:
	id = p_id
	data = p_data
	area = p_area
	exit_point = exit_p
	name = "Traveler_" + id
	rng.seed = hash(id)
	model = (load(String(data.model)) as PackedScene).instantiate()
	add_child(model)
	# scale to the authored height, measured from the rig's bones in world space (skinned AABBs are unreliable
	# for these GLBs; the armature carries its own rotation/scale)
	var top := 0.0
	for skn in model.find_children("*", "Skeleton3D", true, false):
		var sk: Skeleton3D = skn
		for bi in sk.get_bone_count():
			top = maxf(top, (sk.global_transform * sk.get_bone_global_rest(bi)).origin.y - model.global_position.y)
	if top > 0.05:
		model.scale = Vector3.ONE * (float(data.get("height_m", 1.65)) * 0.93 / top)
	print("[npcs] %s rig top %.2f m -> scale %.3f" % [id, top, model.scale.x])
	for hide in data.get("hide_meshes", []):
		for mi in model.find_children("*" + String(hide) + "*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = false
	anim = model.find_child("AnimationPlayer", true, false)
	for a in anim.get_animation_list():
		var short := String(a).get_slice("|", 1) if String(a).contains("|") else String(a)
		_clips[short] = a
		if short in ["Idle", "Idle_Neutral", "Walk", "Run"]:
			anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	global_position = entry
	MagicEvents.magic_event.connect(_on_magic)


func _play(clip: String, blend := 0.3) -> void:
	var real: String = _clips.get(clip, _clips.get("Idle", ""))
	if real != "" and _current != real:
		_current = real
		anim.play(real, blend)


func _on_magic(pos: Vector3, element: String, power: float, effect: String, object_id: String) -> void:
	if state in ["gone", "arriving"] or effect == "none":
		return
	if global_position.distance_to(pos) < 28.0:
		witnessed.append({"effect": effect, "element": element, "object": object_id, "power": snappedf(power, 0.01), "t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1)})


func walk_to(p: Vector3) -> bool:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	path = NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, global_position), NavigationServer3D.map_get_closest_point(map, p), true)
	path_i = 0
	return path.size() > 1


func leave() -> void:
	state = "leaving"
	talking = false
	walk_to(exit_point)


## VoiceService calls this from the speech envelope.
func set_talking(on: bool) -> void:
	talking = on


func face(p: Vector3) -> void:
	talk_target = null
	var d := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func _process(delta: float) -> void:
	match state:
		"arriving", "leaving":
			if _follow(delta):
				_play("Walk", 0.2)
			else:
				if state == "leaving":
					state = "gone"
					queue_free()
					return
				state = "idle"
		"idle":
			_gesture_t -= delta
			if _gesture_t <= 0.0:
				_gesture_t = rng.randf_range(6.0, 14.0)
				var g: String = ["Idle_Neutral", "Interact", "Idle"][rng.randi() % 3]
				_play(g, 0.4)
				if g == "Interact":
					get_tree().create_timer(2.0).timeout.connect(func(): if state == "idle": _play("Idle", 0.4))
			elif _current == "":
				_play("Idle")
		"talking":
			if talk_target and is_instance_valid(talk_target):
				var d := Vector3(talk_target.global_position.x - global_position.x, 0, talk_target.global_position.z - global_position.z)
				rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 1.0 - exp(-6.0 * delta))
			_play("Interact" if talking else "Idle", 0.35)


func _follow(delta: float) -> bool:
	if path_i >= path.size():
		return false
	var target := path[path_i]
	var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if to.length() < 0.25:
		path_i += 1
		return path_i < path.size()
	var p := global_position + to.normalized() * minf(speed * delta, to.length())
	p.y = area.ground_at(p.x, p.z) if area.has_method("ground_at") else target.y
	global_position = p
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))
	return true


func describe(from: Vector3) -> Dictionary:
	return {"id": id, "name": data.name, "role": data.role, "state": state, "distance": snappedf(from.distance_to(global_position), 0.1),
		"appearance": data.appearance, "witnessed": witnessed.slice(maxi(0, witnessed.size() - 4))}
