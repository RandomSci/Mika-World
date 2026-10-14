class_name FamilySpell
extends Node3D
## Base of the two mages' own spell families (V3 Part XIII, K5/K6). The same truthful contract as
## ElementalSpell / CombatSpell - phases taken from the caster's REAL clip time and announced on MagicEvents
## (audio, camera, face stay in sync with the body), judged outcomes, `resolved` - with the visual language,
## timing and mechanics supplied by the subclass:
##   SylvanSpell   Mika: wind that curves and things that grow (spirals, leaves, roots, a ring of leaves)
##   UmbralSpell   Luna: precise shadow edged in gold (hex rifts, crystal spikes, a mirror pane)
## Styles (data "projectile"): "spiral" - a weaving projectile; "ground" - an eruption at the aimed point after
## a visible travel along the ground (judged when it erupts: a creature that has moved is not inside);
## "ward" - a defence that stays on the caster (a Ward node, judged when a bolt really crosses it).

signal resolved(result: Dictionary)

const TIMING := {
	"magic_attack_1h": {"rune": 0.06, "gather": 0.12, "charge": 0.3, "release": 0.42, "end": 0.85},
	"magic_attack_2h": {"rune": 0.04, "gather": 0.08, "charge": 0.2, "release": 0.46, "end": 0.9},
	"spell_casting": {"rune": 0.06, "gather": 0.12, "charge": 0.3, "release": 0.6, "end": 0.92},
	"wide_arm_spell": {"rune": 0.08, "gather": 0.15, "charge": 0.35, "release": 0.6, "end": 0.92},
	"prepare_and_cast": {"rune": 0.06, "gather": 0.12, "charge": 0.4, "release": 0.66, "end": 0.92},
	"brace": {"rune": 0.02, "gather": 0.05, "charge": 0.13, "release": 0.22, "end": 0.75},
	"cast_quick": {"rune": 0.03, "gather": 0.08, "charge": 0.2, "release": 0.35, "end": 0.85},
}

var caster: WorldCharacter
var clip := "spell_casting"
var spell_id := ""
var def := {}
var element := "wind"
var style := ""
var aim := Vector3.ZERO
var target: ReactiveElement
var power := 0.5
var tier := 0
var mastery := 0.0
var signature := false
var duration := 3.0
var t := 0.0
var _fired := {}
var _impact := {}
var _done_t := -1.0
var _flying := false
var _light_scale: float = RenderProfile.get_setting("magic_light_scale")
var hand_fx: Node3D
var hand_light: OmniLight3D
var ground: MeshInstance3D


func configure(id: String, d: Dictionary, p_aim: Vector3, p_target: ReactiveElement, p_power: float, p_mastery: float) -> void:
	spell_id = id
	def = d
	element = String(d.element)
	style = String(d.get("projectile", "spiral"))
	aim = p_aim
	target = p_target
	power = p_power
	mastery = p_mastery
	tier = clampi(int(p_mastery * 1.5), 0, 3)
	hand_fx = Node3D.new()
	add_child(hand_fx)
	hand_light = FX.light(FX.palette(element)[0], 0.0, 2.2)
	hand_fx.add_child(hand_light)
	_build()


## called by WorldCharacter.cast_spell before configure()
func start(c: WorldCharacter, clip_name: String) -> void:
	caster = c
	clip = clip_name
	duration = caster.animation_length(clip)
	signature = c.has_meta("signature")
	global_position = caster.global_position


func phase_time(name: String) -> float:
	return float(TIMING.get(clip, TIMING.spell_casting).get(name, 0.0)) * duration


func _announce(ph: String, pos: Vector3) -> void:
	MagicEvents.emit_phase(caster, spell_id, ph, element, pos)
	caster.cast_event.emit(ph)


func _ramp(a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	if caster == null or def.is_empty():
		return
	t += delta
	var R := phase_time("rune"); var G := phase_time("gather"); var C := phase_time("charge")
	var L := phase_time("release"); var E := phase_time("end")
	var hand := _hand_point()
	var fwd := -caster.global_transform.basis.z
	hand_fx.global_position = hand + fwd * 0.1
	if not _fired.has("activation"):
		_fired.activation = true
		_announce("activation", caster.global_position)
	if t >= R and not _fired.has("rune"):
		_fired.rune = true
		_announce("rune", caster.global_position)
	if t >= G and not _fired.has("gather"):
		_fired.gather = true
		_announce("gather", hand)
		_on_gather()
	if t >= C and not _fired.has("charge"):
		_fired.charge = true
		_announce("charge", hand)
	var awaken := _ramp(0.0, R + 0.3)
	var build := _ramp(G, L)
	var fade := 1.0 - _ramp(E - 0.1, duration + 0.6)
	if ground:
		ground.global_position = caster.global_position + Vector3(0, 0.035, 0)
	var released := _fired.has("release")
	hand_light.light_energy = (0.3 + 1.2 * build) * fade * _light_scale * (0.3 if released else 1.0)
	_update(awaken, build, fade, hand, fwd, delta)
	if t >= L and not released:
		_fired.release = true
		if style == "ground" and target and is_instance_valid(target):
			# a ground technique is aimed at the moment it leaves: where the creature is NOW, led by the motion
			# she can see for the time the seam takes (her own aim error stays)
			var lead := Vector3.ZERO
			var mv = target.get("move_vel")
			if mv is Vector3:
				lead = Vector3((mv as Vector3).x, 0, (mv as Vector3).z) * _travel_time(target.aim_point())
			aim = target.aim_point() + lead + (get_meta("aim_err", Vector3.ZERO) as Vector3)
		var dir := fwd
		if aim != Vector3.ZERO and style != "ward":
			dir = (aim - hand).normalized()
		_release(hand, dir)
	if _flying:
		_fly(delta)
	if t > duration + 0.5 and not _fired.has("dissipate_fx"):
		_fired.dissipate_fx = true
		_announce("dissipate", hand)
	if t > duration + 0.5 and not _fired.has("dissipate") and not _flying and not _pending():
		if _impact.is_empty():
			_impact = {"outcome": "missed", "point": _v(aim)}
		_resolve(_impact)
	if _done_t >= 0.0 and t > _done_t + 1.5 and not _pending():
		queue_free()


## The outcome is known: tell the caster and whoever awaits the cast (the visuals fade on their own).
func _resolve(outcome: Dictionary) -> void:
	_impact = outcome
	if _fired.has("dissipate"):
		return
	_fired.dissipate = true
	caster.end_cast(true, "%s resolved (%s)" % [spell_id, _impact.get("outcome", "none")])
	resolved.emit(_impact)
	_done_t = t


# ------------------------------------------------------------------ hooks for the families
func _build() -> void:
	pass


func _on_gather() -> void:
	for n in hand_fx.get_children():
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = true


func _hand_point() -> Vector3:
	return caster.right_hand.global_position


func _update(_awaken: float, _build: float, _fade: float, _hand: Vector3, _fwd: Vector3, _delta: float) -> void:
	pass


func _release(_hand: Vector3, _dir: Vector3) -> void:
	pass


func _fly(_delta: float) -> void:
	pass


## A ground spell still travelling or about to erupt (the outcome is not known yet).
func _pending() -> bool:
	return false


## Seconds a ground technique takes to reach a point (for leading a moving creature).
func _travel_time(_p: Vector3) -> float:
	return 0.4


func _stop_hand_particles() -> void:
	for n in hand_fx.get_children():
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = false


## Ground height under a point (the area's terrain, else the aim's own height).
func _ground(p: Vector3) -> Vector3:
	var w = caster.world
	if w and w.has_method("ground_at"):
		return Vector3(p.x, float(w.ground_at(p.x, p.z)), p.z)
	return Vector3(p.x, caster.global_position.y, p.z)


func _sfx(name: String, pos: Vector3, db := -6.0) -> void:
	if AudioDirector.instance:
		AudioDirector.instance.play3d(name, pos, "SFX", db, spell_id)


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
