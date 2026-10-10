class_name PondFish
extends Node3D
## Koi in the garden pond: slow loops just under the surface. Any magic touching the pond (or landing
## close to it) makes them dart outward and down, then settle back over ~8 s.

var model: Node3D
var anim: AnimationPlayer
var centre := Vector3.ZERO
var radius := 2.0
var depth := 0.18
var phase := 0.0
var speed := 0.35
var fleeing := 0.0
var _flee_dir := 1.0
var last_reaction := {}


func setup(glb: String, p_centre: Vector3, p_radius: float, seed_v: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	centre = p_centre
	radius = p_radius
	phase = r.randf() * TAU
	speed = r.randf_range(0.25, 0.45) * (1.0 if r.randf() < 0.5 else -1.0)
	depth = r.randf_range(0.12, 0.25)
	name = "Animal_koi_%d" % seed_v
	model = (load(glb) as PackedScene).instantiate()
	model.scale = Vector3.ONE * r.randf_range(0.07, 0.1)
	add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	for a in anim.get_animation_list():
		if String(a).ends_with("Swimming_Normal") or String(a).ends_with("Swimming_Fast"):
			anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_swim(false)
	MagicEvents.magic_event.connect(func(pos, el, _pw, eff, id):
		if id == "pond" or pos.distance_to(centre) < radius + 2.0:
			_scatter("%s magic on the pond (%s)" % [el, eff]))


func _swim(fast: bool) -> void:
	for a in anim.get_animation_list():
		if String(a).ends_with("Swimming_Fast" if fast else "Swimming_Normal"):
			anim.play(a, 0.2, 1.6 if fast else 1.0)
			return


func _scatter(why: String) -> void:
	fleeing = 8.0
	_flee_dir = 1.0 if randf() < 0.5 else -1.0
	_swim(true)
	last_reaction = {"t": snappedf(Time.get_ticks_msec() / 1000.0, 0.1), "reaction": "scattered", "why": why}
	if AudioDirector.instance:
		AudioDirector.instance.play3d("fish_plip", global_position, "Ambience", -8.0, "fish_scatter")


func _process(delta: float) -> void:
	var s := speed
	var r := radius
	var dep := depth
	if fleeing > 0.0:
		fleeing -= delta
		s = speed * 4.0 * _flee_dir
		r = radius * 1.25
		dep = depth + 0.15
		if fleeing <= 0.0:
			_swim(false)
	phase += s / maxf(r, 0.5) * delta
	var p := centre + Vector3(cos(phase) * r, -dep, sin(phase) * r * 0.8)
	var tangent := Vector3(-sin(phase), 0, cos(phase) * 0.8) * signf(s)
	global_position = p
	rotation.y = atan2(tangent.x, tangent.z)


func describe() -> Dictionary:
	return {"species": "koi", "state": "scattering" if fleeing > 0.0 else "swimming", "last_reaction": last_reaction}
