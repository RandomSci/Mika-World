class_name CombatSpell
extends Node3D
## A combat "lance" spell (Umbral Lance): same truthful contract as ElementalSpell (phases from the real
## clip time, announced on MagicEvents; a swept projectile judged hit / blocked / missed; `resolved`),
## with a distinct, physical visual language:
##   activation - a five-point sigil opens under her feet (gold on violet)
##   gather     - shadow motes spiral into the casting hand; the hand light dims (shadow, not light)
##   charge     - the lance forms: a dark crystal shaft with a hot gold rim, growing from the palm
##   release    - it leaves fast; the caster recoils a step; a gold ribbon and violet sparks trail it
##   impact     - ImpactFX (shockwave, sparks, dust, light pulse, camera jolt) on creatures; a smaller
##                gold splinter burst elsewhere
## Mastery adds detail and speed; the render profile scales particle counts.

signal resolved(result: Dictionary)

const TIMING := {
	"magic_attack_1h": {"rune": 0.05, "gather": 0.1, "charge": 0.25, "release": 0.42, "end": 0.85},
	"magic_attack_2h": {"rune": 0.04, "gather": 0.08, "charge": 0.18, "release": 0.45, "end": 0.9},
	"spell_casting": {"rune": 0.06, "gather": 0.12, "charge": 0.3, "release": 0.6, "end": 0.92},
}

var caster: WorldCharacter
var clip := "magic_attack_1h"
var spell_id := ""
var def := {}
var element := "umbral"
var aim := Vector3.ZERO
var target: ReactiveElement
var power := 0.5
var tier := 0
var duration := 2.0
var t := 0.0
var _fired := {}
var _light_scale: float = RenderProfile.get_setting("magic_light_scale")

var ground: MeshInstance3D
var hand_fx: Node3D
var hand_light: OmniLight3D
var lance: MeshInstance3D
var _lance_mat: ShaderMaterial
var projectile: Node3D
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _flying := false
var _travelled := 0.0
var _impact := {}
var _done_t := -1.0


func configure(id: String, d: Dictionary, p_aim: Vector3, p_target: ReactiveElement, p_power: float, p_mastery: float) -> void:
	spell_id = id
	def = d
	element = String(d.element)
	aim = p_aim
	target = p_target
	power = p_power
	tier = clampi(int(p_mastery * 1.5), 0, 3)
	_build()


func start(c: WorldCharacter, clip_name: String) -> void:
	caster = c
	clip = clip_name
	duration = caster.animation_length(clip)
	global_position = caster.global_position


func phase_time(name: String) -> float:
	return float(TIMING.get(clip, TIMING.magic_attack_1h).get(name, 0.0)) * duration


func _announce(ph: String, pos: Vector3) -> void:
	MagicEvents.emit_phase(caster, spell_id, ph, element, pos)
	caster.cast_event.emit(ph)


func _build() -> void:
	var pal := FX.palette(element)
	ground = FX.quad("res://shaders/magic/sigil.gdshader", 2.2, {"color": pal[0], "sides": 5, "intensity": 0.0, "draw_progress": 0.0, "spin": -0.25, "seed": 11.0})
	add_child(ground)
	var under := FX.quad("res://shaders/magic/shockwave.gdshader", 2.6, {"color": pal[1], "thickness": 0.12, "intensity": 0.0})
	under.name = "Under"
	add_child(under)
	hand_fx = Node3D.new()
	add_child(hand_fx)
	hand_light = FX.light(pal[0], 0.0, 2.5)
	hand_fx.add_child(hand_light)
	var gather := FX.particles(70 + 25 * tier, 0.7, FX.pm_motes(element, "gather"), FX.mote_mesh(0.045), true)
	gather.name = "Gather"
	gather.emitting = false
	hand_fx.add_child(gather)
	var swirl := FX.particles(40 + 15 * tier, 1.0, FX.pm_motes(element, "swirl"), FX.mote_mesh(0.05, true), true)
	swirl.name = "Swirl"
	swirl.emitting = false
	hand_fx.add_child(swirl)
	# the lance: a long six-sided crystal with sharp ends
	lance = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 6
	cm.rings = 1
	cm.top_radius = 0.0
	cm.bottom_radius = 0.07
	cm.height = 1.1
	lance.mesh = cm
	_lance_mat = ShaderMaterial.new()
	_lance_mat.shader = load("res://shaders/magic/umbral_core.gdshader")
	_lance_mat.set_shader_parameter("rim_color", pal[0])
	_lance_mat.set_shader_parameter("vein_color", pal[1])
	_lance_mat.set_shader_parameter("intensity", 0.0)
	lance.material_override = _lance_mat
	lance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lance.scale = Vector3.ONE * 0.01
	hand_fx.add_child(lance)


func _ramp(a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	if caster == null or def.is_empty():
		return
	t += delta
	var R := phase_time("rune"); var G := phase_time("gather"); var C := phase_time("charge")
	var L := phase_time("release"); var E := phase_time("end")
	var hand: Vector3 = caster.right_hand.global_position
	var fwd := -caster.global_transform.basis.z
	var to_aim := (aim - hand).normalized() if aim != Vector3.ZERO else fwd
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
		(hand_fx.get_node("Gather") as GPUParticles3D).emitting = true
		(hand_fx.get_node("Swirl") as GPUParticles3D).emitting = true
	if t >= C and not _fired.has("charge"):
		_fired.charge = true
		_announce("charge", hand)
	var awaken := _ramp(0.0, R + 0.3)
	var build := _ramp(G, L)
	var fade := 1.0 - _ramp(E - 0.1, duration + 0.6)
	ground.global_position = caster.global_position + Vector3(0, 0.035, 0)
	var gm: ShaderMaterial = ground.material_override
	gm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, awaken))
	gm.set_shader_parameter("intensity", (1.0 + 0.8 * build) * awaken * fade * (0.85 + 0.15 * tier))
	var under: MeshInstance3D = get_node("Under")
	under.global_position = caster.global_position + Vector3(0, 0.03, 0)
	(under.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.8 * build * fade)
	under.scale = Vector3.ONE * (1.0 - 0.35 * build)        # the ring contracts as the power is drawn in
	hand_light.light_energy = (0.25 + 0.9 * build) * fade * _light_scale
	if not _flying and not _fired.has("release"):
		# the lance grows from the palm, pointed at the aim
		var grow := smoothstep(0.0, 1.0, _ramp(C - 0.1, L))
		lance.scale = Vector3.ONE * maxf(0.01, grow) * (0.9 + 0.1 * tier)
		lance.global_position = hand + to_aim * (0.25 + 0.3 * grow)
		lance.global_basis = Basis.looking_at(to_aim, Vector3.UP if absf(to_aim.y) < 0.95 else Vector3.FORWARD) * Basis(Vector3.RIGHT, -PI * 0.5)
		_lance_mat.set_shader_parameter("intensity", 0.4 + 0.8 * grow)
	if t >= L and not _fired.has("release"):
		_fired.release = true
		_release(hand, to_aim)
	if _flying:
		_fly(delta)
	if t > duration + 0.5 and not _fired.has("dissipate") and not _flying:
		_fired.dissipate = true
		_announce("dissipate", hand)
		caster.end_cast(true, "%s resolved (%s)" % [spell_id, _impact.get("outcome", "none")])
		if _impact.is_empty():
			_impact = {"outcome": "missed", "point": ElementalSpell._v(aim)}
		resolved.emit(_impact)
		_done_t = t
	if _done_t >= 0.0 and t > _done_t + 1.2:
		queue_free()


func _release(hand: Vector3, dir: Vector3) -> void:
	_announce("release", hand)
	(hand_fx.get_node("Gather") as GPUParticles3D).emitting = false
	(hand_fx.get_node("Swirl") as GPUParticles3D).emitting = false
	# a small physical recoil: the caster's body answers the release
	caster.velocity -= Vector3(dir.x, 0, dir.z) * 1.4
	FX.burst(get_parent(), hand + dir * 0.3, 24, 0.4, FX.pm_motes(element, "burst"), FX.mote_mesh(0.04))
	projectile = Node3D.new()
	get_parent().add_child(projectile)
	_pos = hand + dir * 0.45
	projectile.global_position = _pos
	_vel = dir * float(def.get("speed", 24.0)) * (1.0 + 0.1 * tier)
	lance.reparent(projectile, false)
	lance.position = Vector3.ZERO
	lance.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD) * Basis(Vector3.RIGHT, -PI * 0.5)
	lance.scale = Vector3(1.0, 1.5, 1.0)
	_lance_mat.set_shader_parameter("intensity", 1.4)
	var trail := FX.particles(80 + 20 * tier, 0.35, FX.pm_motes(element, "trail"), FX.mote_mesh(0.05, true))
	trail.emitting = true
	projectile.add_child(trail)
	projectile.add_child(FX.light(FX.palette(element)[0], 1.5 * _light_scale, 4.0))
	_flying = true


func _fly(delta: float) -> void:
	var next := _pos + _vel * delta
	var hit := MagicSystem.sweep(caster.get_world_3d(), _pos, next, [caster.get_rid()])
	if not hit.is_empty():
		_land(hit.position, hit.collider)
		return
	if target:
		var tp := target.aim_point()
		var seg := next - _pos
		var tt := clampf((tp - _pos).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		if (_pos + seg * tt).distance_to(tp) <= target.aim_radius + 0.15 and tt < 1.0:
			_land(_pos + seg * tt, null, true)
			return
	_pos = next
	_travelled += (_vel * delta).length()
	projectile.global_position = _pos
	if _travelled > float(def.get("range", 14.0)) + 3.0:
		_land(_pos, null)


func _land(point: Vector3, collider: Object, on_target := false) -> void:
	_flying = false
	var outcome := "hit" if on_target else MagicSystem.judge(target, point, collider, 0.15)
	_impact = {"outcome": outcome, "point": ElementalSpell._v(point), "distance_from_target_m": snappedf(point.distance_to(target.aim_point()), 0.01) if target else -1.0}
	if collider is Node and outcome != "hit":
		_impact["blocked_by"] = String((collider as Node).name)
	_announce("impact" if outcome == "hit" else outcome, point)
	if not (target is Monster and outcome == "hit"):      # creature hits get ImpactFX from MagicSystem
		FX.burst(get_parent(), point, 34 if outcome == "hit" else 18, 0.6, FX.pm_motes(element, "burst"), FX.mote_mesh(0.05, true))
		ImpactFX.shockwave(get_parent(), point, FX.palette(element)[0], 0.9 if outcome == "hit" else 0.5)
	if projectile:
		for c in projectile.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
			elif c is OmniLight3D or c is MeshInstance3D:
				c.visible = false
		get_tree().create_timer(0.6).timeout.connect(projectile.queue_free)
