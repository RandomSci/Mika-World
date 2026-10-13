class_name CreatureBody
extends Node3D
## The visible, animated body of a Milestone J creature. The Monster script owns the behaviour (state,
## timing, damage); the body only SHOWS it: idle / move / alert / windup / strike / recover / hit / defeat.
## Two implementations share this API:
##   SentinelRig - the Hollow Sentinel: an original articulated stone golem (tools/models/build_sentinel.py),
##                 animated by authored joint poses + procedural weight (heavy gait, footfalls, slam)
##   ClipRig     - an animated GLB with its own clips (the Emberwing, Quaternius CC0 Dragon), plus
##                 procedural flight (bob, bank, rear-back) layered on the model root

signal footfall(at: Vector3, weight: float)

var state := "idle"
var state_t := 0.0                 # seconds in the current state
var move_speed := 0.0              # current ground/air speed (m/s), set by the monster
var glow_color := Color(0.5, 0.85, 1.0)
var glow_level := 1.0              # 1 = calm; the monster raises it while charging an attack
var _glow_mats: Array[StandardMaterial3D] = []


func play(s: String) -> void:
	if s == state:
		return
	state = s
	state_t = 0.0
	_entered(s)


func _entered(_s: String) -> void:
	pass


## Where a spell is aimed (the creature's heart / centre of mass), in world space.
func aim_point() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)


## Brief flash where something struck it.
func flash(_strength := 1.0) -> void:
	pass


func _glow_material(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_glow_mats.append(m)
	return m


func _update_glow(delta: float, base: float) -> void:
	for m in _glow_mats:
		m.emission_energy_multiplier = lerpf(m.emission_energy_multiplier, base * glow_level, 1.0 - exp(-10.0 * delta))
