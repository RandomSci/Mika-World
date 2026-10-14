class_name PhoenixFlare
extends Node3D
## Oriel's fire magic: a SUNFLARE - a knot of burning feathers that leaves her chest (true form) or her hand
## (humanoid form), flies to its mark trailing embers, and bursts. Whatever stands there answers with its own
## `react("fire", ...)` (a creature takes fire damage through its resistances; a brazier is lit or flares);
## nothing is video-only. Usable both as a WorldCharacter spell node (`start(caster, clip)`) and directly
## (`launch(from, target, power)`).

signal resolved(outcome: Dictionary)

const SPEED := 13.0
const RELEASE := {"magic_attack_1h": 0.95, "spell_casting": 1.25, "prepare_and_cast": 1.6, "cast_quick": 0.3}

var target: Node3D
var target_point := Vector3.ZERO
var power := 0.9
var caster: Node
var clip := ""
var owner_id := "phoenix"
static var main_ref: Node          # set by Phoenix.setup (audio, world)
var _flying := false
var _t := 0.0
var _mesh: MeshInstance3D
var _light: OmniLight3D
var _trail: GPUParticles3D
var _done := false
var _prev_pos := Vector3.ZERO


## WorldCharacter.cast_spell path: wait for the clip's release, then launch from the right hand.
func start(c: Node, p_clip: String) -> void:
	caster = c
	clip = p_clip
	var tgt = c.get_meta("flare_target") if c.has_meta("flare_target") else null
	if tgt is Node3D:
		target = tgt
	elif tgt is Vector3:
		target_point = tgt
	power = float(c.get_meta("flare_power")) if c.has_meta("flare_power") else 0.9
	var wait: float = RELEASE.get(p_clip, 1.0)
	await get_tree().create_timer(wait).timeout
	if not is_inside_tree():
		return
	var from: Vector3 = c.right_hand.global_position if c.get("right_hand") else c.global_position + Vector3(0, 1.3, 0)
	launch(from, target if target else target_point, power)
	if caster and caster.has_method("end_cast"):
		resolved.connect(func(o): caster.end_cast(true, String(o.get("detail", "sunflare"))))


func launch(from: Vector3, tgt, p_power := 0.9) -> void:
	power = p_power
	if tgt is Node3D:
		target = tgt
		target_point = _aim(tgt)
	else:
		target_point = tgt
	global_position = from
	_prev_pos = from
	_build()
	_flying = true
	if main_ref and main_ref.get("audio"):
		main_ref.audio.play_big("phoenix_flare_cast", from, -2.0, "phoenix flare")


static func _aim(n: Node3D) -> Vector3:
	if n.has_method("aim_point"):
		return n.aim_point()
	return n.global_position + Vector3(0, 0.8, 0)


func _build() -> void:
	_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	_mesh.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.7, 0.3, 0.9)
	m.albedo_texture = FX.noise()
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.15)
	m.emission_energy_multiplier = 4.0
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light = FX.light(Color(1.0, 0.6, 0.2), 2.2 * float(RenderProfile.get_setting("magic_light_scale")), 6.0)
	add_child(_light)
	_trail = FX.particles(40, 0.7, FX.process("phoenix_flare_trail", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.16
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 1.2
		pm.gravity = Vector3(0, 0.8, 0)
		pm.damping_min = 1.0
		pm.damping_max = 2.0
		pm.scale_min = 0.5
		pm.scale_max = 1.1
		pm.color_ramp = FX.ramp([Color(1, 0.9, 0.6, 1), Color(1, 0.5, 0.12, 0.9), Color(0.8, 0.2, 0.03, 0.5), Color(0.2, 0.03, 0, 0)], [0.0, 0.25, 0.7, 1.0])), FX.leaf_mesh(0.14, "heart"))
	_trail.emitting = true
	add_child(_trail)


func _process(delta: float) -> void:
	if not _flying or _done:
		return
	_t += delta
	if target and is_instance_valid(target):
		target_point = _aim(target)
	var to := target_point - global_position
	var d := to.length()
	if d < 0.45 or _t > 6.0:
		_arrive()
		return
	var step := minf(SPEED * delta, d)
	# a lazy arc: a little lift in the first half of the flight
	var up := Vector3.UP * (0.6 * sin(clampf(_t * 1.8, 0.0, PI)) * delta)
	global_position += to.normalized() * step + up
	_mesh.scale = Vector3.ONE * (1.0 + 0.15 * sin(_t * 22.0))


func _arrive() -> void:
	_done = true
	_flying = false
	var at := global_position
	var outcome := {"ok": true, "effect": "burst", "detail": "the sunflare burst in the air", "target": ""}
	if target and is_instance_valid(target) and target.has_method("react"):
		var r: Dictionary = target.react("fire", power, at, "phoenix_flare")
		outcome = {"ok": true, "effect": String(r.get("effect", "")), "detail": String(r.get("detail", "")), "target": String(target.get("id") if target.get("id") != null else target.name), "reaction": r}
	ImpactFX.play(get_parent(), at, "fire", power)
	if main_ref and main_ref.get("audio"):
		main_ref.audio.play_big("phoenix_flare_impact", at, 0.0, "phoenix flare impact")
	MagicEvents.magic_event.emit(at, "fire", power, String(outcome.effect), String(outcome.target))
	if _trail:
		_trail.emitting = false
	if _mesh:
		_mesh.visible = false
	resolved.emit(outcome)
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 0.0, 0.5)
	tw.tween_callback(queue_free)
