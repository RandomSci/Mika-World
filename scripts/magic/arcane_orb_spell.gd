class_name ArcaneOrbSpell
extends Node3D
## "Arcane Orb": an original layered spell synchronised to the caster's animation clip.
##
## Phases (normalised clip time, per-clip table below):
##   awaken  – sigil circle draws itself under the caster, the dais runes wake outward
##   gather  – motes stream inward to the hands, hand glows build
##   form    – three geometric sigil rings draw around the forming orb
##   orb     – hot core + writhing shell + haze, comet trails orbit, light swells
##   release – orb launches forward and bursts: sparks, shockwave, light flash
##   resolve – everything decays cleanly, caster returns to idle

signal resolved(result: Dictionary)

const BLUE := Color(0.42, 0.66, 1.0)
const VIOLET := Color(0.74, 0.46, 1.0)

## clip -> {awaken, gather, form, orb, release, end} in normalised clip time
const TIMING := {
	"prepare_and_cast": {"awaken": 0.0, "gather": 0.10, "form": 0.30, "orb": 0.42, "release": 0.66, "end": 0.92},
	"spell_casting": {"awaken": 0.0, "gather": 0.08, "form": 0.25, "orb": 0.35, "release": 0.62, "end": 0.95},
	"wide_arm_spell": {"awaken": 0.0, "gather": 0.10, "form": 0.30, "orb": 0.40, "release": 0.62, "end": 0.95},
	"magic_attack_2h": {"awaken": 0.0, "gather": 0.05, "form": 0.15, "orb": 0.22, "release": 0.45, "end": 0.9},
}

var caster: WorldCharacter
var clip := "prepare_and_cast"
var timing: Dictionary
var duration := 4.0
var t := 0.0
var released := false
var burst_done := false
var _gather_sent := false
var _fired_rune := false
var _fired_charge := false
var _shadows: bool = RenderProfile.get_setting("magic_shadows")

var ground_sigil: MeshInstance3D
var orb_root: Node3D
var orb_core: MeshInstance3D
var orb_shell: MeshInstance3D
var orb_haze: MeshInstance3D
var rings: Array[MeshInstance3D] = []
var ring_axes: Array[Vector3] = []
var gather: GPUParticles3D
var rising: GPUParticles3D
var comets: Array[Node3D] = []
var hand_glow_l: OmniLight3D
var hand_glow_r: OmniLight3D
var hand_sprite_l: GPUParticles3D
var hand_sprite_r: GPUParticles3D
var orb_light: OmniLight3D
var shockwave: MeshInstance3D
var burst: GPUParticles3D
var _orb_pos := Vector3.ZERO
var _release_from := Vector3.ZERO
var _release_to := Vector3.ZERO
var _noise_tex: NoiseTexture2D
var aim_point = null            # Vector3 from MagicSystem (target-aware); null = straight ahead
var target_ref: ReactiveElement = null
var spell_id := "arcane_orb"
var _outcome := {}
var _flight_s := 0.45
var _prev_orb := Vector3.ZERO
var _light_scale: float = RenderProfile.get_setting("magic_light_scale")
## Milestone J: a SIGNATURE cast (SignatureCast) channels the same spell fully: a slower, fuller build-up,
## an outer formation on the ground and a vertical sigil drawn in front of her hands, a larger orb.
var signature := false
var _resolved_sent := false
var _sig_k := 1.0
var outer_sigil: MeshInstance3D
var formation: MeshInstance3D
## A light trail behind the orb in flight, so its path reads clearly on screen.
var _trail_mesh: ImmediateMesh
var _trail_node: MeshInstance3D
var _trail_pts: Array[Vector3] = []


func start(c: WorldCharacter, clip_name: String) -> void:
	caster = c
	clip = clip_name
	timing = TIMING.get(clip, TIMING["prepare_and_cast"])
	duration = caster.animation_length(clip)
	signature = caster.has_meta("signature")
	if signature:
		_sig_k = 1.4
		caster.set_gesture_speed(0.6)          # a deliberate, fuller channel on the decisive two-handed gesture
		duration /= 0.6
	global_position = caster.global_position
	_build()
	caster.cast_event.emit("awaken")
	_bus("activation", caster.global_position)


func _bus(ph: String, pos: Vector3) -> void:
	MagicEvents.emit_phase(caster, spell_id, ph, "arcane", pos)


func phase(name: String) -> float:
	return timing[name] * duration


func _build() -> void:
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.seamless = true
	_noise_tex.width = 256
	_noise_tex.height = 256
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 3
	_noise_tex.noise = fn

	# ground sigil
	ground_sigil = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(3.6, 3.6)
	ground_sigil.mesh = q
	ground_sigil.material_override = _sigil_mat(8, BLUE, 1.7)
	ground_sigil.position = Vector3(0, 0.03, 0)
	ground_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground_sigil)

	rising = _particles(90, 1.6, _mote_process(ParticleProcessMaterial.EMISSION_SHAPE_RING, Vector3.UP, 0.4, 1.1, 0.0), 0.06)
	var rp: ParticleProcessMaterial = rising.process_material
	rp.emission_ring_radius = 1.5
	rp.emission_ring_inner_radius = 1.2
	rp.emission_ring_height = 0.05
	rp.emission_ring_axis = Vector3.UP
	rising.emitting = false
	add_child(rising)

	# orb assembly
	orb_root = Node3D.new()
	add_child(orb_root)
	orb_core = _sphere(0.09, 0)
	orb_shell = _sphere(0.19, 1)
	orb_haze = _sphere(0.42, 2)
	for m in [orb_core, orb_shell, orb_haze]:
		orb_root.add_child(m)
	orb_root.scale = Vector3.ONE * 0.001

	for i in 3:
		var r := MeshInstance3D.new()
		var rq := QuadMesh.new()
		rq.size = Vector2.ONE * [0.62, 0.8, 1.0][i]
		r.mesh = rq
		r.material_override = _sigil_mat([6, 5, 3][i], [BLUE, VIOLET, BLUE.lerp(VIOLET, 0.5)][i], 0.0)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb_root.add_child(r)
		rings.append(r)
	ring_axes = [Vector3(1, 0.3, 0).normalized(), Vector3(0.2, 1, 0.4).normalized(), Vector3(0, 0.4, 1).normalized()]

	gather = _particles(170, 0.85, _mote_process(ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE, Vector3.ZERO, 0.0, 0.0, -7.5), 0.045)
	(gather.process_material as ParticleProcessMaterial).emission_sphere_radius = 1.5
	gather.local_coords = true
	gather.emitting = false
	add_child(gather)

	for i in 4:
		var comet := Node3D.new()
		orb_root.add_child(comet)
		var trail := _particles(70, 0.55, _mote_process(ParticleProcessMaterial.EMISSION_SHAPE_POINT, Vector3.ZERO, 0.0, 0.05, 0.0), 0.05)
		trail.local_coords = false
		trail.emitting = false
		comet.add_child(trail)
		comets.append(comet)

	hand_glow_l = _light(BLUE, 0.0, 1.6, false)
	hand_glow_r = _light(VIOLET, 0.0, 1.6, false)
	caster.left_hand.add_child(hand_glow_l)
	caster.right_hand.add_child(hand_glow_r)
	hand_sprite_l = _particles(30, 0.4, _mote_process(ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, Vector3.UP, 0.05, 0.25, 0.0), 0.06)
	hand_sprite_r = _particles(30, 0.4, _mote_process(ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, Vector3.UP, 0.05, 0.25, 0.0), 0.06)
	for hs in [hand_sprite_l, hand_sprite_r]:
		(hs.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.06
		hs.local_coords = false
		hs.emitting = false
	caster.left_hand.add_child(hand_sprite_l)
	caster.right_hand.add_child(hand_sprite_r)

	orb_light = _light(BLUE.lerp(Color.WHITE, 0.15), 0.0, 7.0, _shadows)
	orb_root.add_child(orb_light)

	if signature:
		outer_sigil = MeshInstance3D.new()
		var oq := PlaneMesh.new()
		oq.size = Vector2(6.2, 6.2)
		outer_sigil.mesh = oq
		outer_sigil.material_override = _sigil_mat(12, VIOLET, 0.0)
		outer_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(outer_sigil)
		formation = MeshInstance3D.new()
		var fq := QuadMesh.new()
		fq.size = Vector2(1.15, 1.15)
		formation.mesh = fq
		formation.material_override = _sigil_mat(7, BLUE.lerp(VIOLET, 0.35), 0.0)
		formation.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(formation)
		(gather.process_material as ParticleProcessMaterial).emission_sphere_radius = 2.4
		gather.amount = int(gather.amount * 1.5)
	_trail_mesh = ImmediateMesh.new()
	_trail_node = MeshInstance3D.new()
	_trail_node.mesh = _trail_mesh
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.vertex_color_use_as_albedo = true
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_node.material_override = tm
	_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_node.top_level = true
	add_child(_trail_node)

	shockwave = MeshInstance3D.new()
	var sq := PlaneMesh.new()
	sq.size = Vector2(1, 1)
	shockwave.mesh = sq
	shockwave.material_override = _sigil_mat(12, Color(0.6, 0.8, 1.0), 0.0)
	shockwave.visible = false
	add_child(shockwave)

	var bp := _mote_process(ParticleProcessMaterial.EMISSION_SHAPE_SPHERE, Vector3.ZERO, 3.0, 8.5, 0.0)
	bp.spread = 180.0
	bp.gravity = Vector3(0, -2.5, 0)
	bp.damping_min = 2.0
	bp.damping_max = 4.0
	burst = _particles(220, 1.4, bp, 0.07)
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.emitting = false
	burst.local_coords = false
	add_child(burst)


# ------------------------------------------------------------------ builders
func _sigil_mat(sides: int, col: Color, intensity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/magic/sigil.gdshader")
	m.set_shader_parameter("sides", sides)
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("seed", randf() * 100.0)
	m.set_shader_parameter("draw_progress", 0.0)
	m.set_shader_parameter("spin", 0.35 if sides % 2 == 0 else -0.5)
	return m


func _sphere(radius: float, mode: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 48
	s.rings = 24
	mi.mesh = s
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/magic/orb_shell.gdshader")
	m.set_shader_parameter("layer_mode", mode)
	m.set_shader_parameter("color_a", BLUE)
	m.set_shader_parameter("color_b", VIOLET)
	m.set_shader_parameter("noise_tex", _noise_tex)
	if mode == 2:
		m.set_shader_parameter("intensity", 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _mote_process(shape: int, dir: Vector3, vmin: float, vmax: float, radial: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = shape
	pm.direction = dir if dir != Vector3.ZERO else Vector3.UP
	pm.spread = 25.0 if dir != Vector3.ZERO else 180.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3.ZERO
	pm.radial_accel_min = radial
	pm.radial_accel_max = radial * 1.3
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	grad.colors = PackedColorArray([Color(VIOLET, 0.0), Color(BLUE.lerp(Color.WHITE, 0.3), 1.0), Color(VIOLET, 0.7), Color(BLUE, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	return pm


func _particles(amount: int, lifetime: float, pm: ParticleProcessMaterial, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/magic/energy_mote.gdshader")
	sm.set_shader_parameter("hdr_boost", 5.0)
	quad.material = sm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _light(col: Color, energy: float, rng: float, shadows: bool) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	l.light_volumetric_fog_energy = 1.5
	l.light_specular = 0.6
	return l


# ------------------------------------------------------------------ timeline
func _ramp(a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	if caster == null:
		queue_free()
		return
	t += delta
	var A := phase("awaken"); var G := phase("gather"); var F := phase("form")
	var O := phase("orb"); var R := phase("release"); var E := phase("end")
	var hands := (caster.left_hand.global_position + caster.right_hand.global_position) * 0.5
	var fwd := -caster.global_transform.basis.z
	var chest_front := caster.chest.global_position + fwd * 0.62 + Vector3(0, 0.02, 0)

	# --- awaken: ground sigil + dais runes
	var awaken := _ramp(A, G + 0.4)
	var fade_out := 1.0 - _ramp(E - 0.2, duration + 0.6)
	var gm: ShaderMaterial = ground_sigil.material_override
	gm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, awaken))
	gm.set_shader_parameter("intensity", 1.6 * awaken * fade_out + (1.2 * _pulse(R, 0.5)))
	ground_sigil.global_position = caster.global_position + Vector3(0, 0.03, 0)
	rising.emitting = t > A + 0.2 and t < R + 0.3
	rising.global_position = caster.global_position + Vector3(0, 0.05, 0)
	if signature:
		var om: ShaderMaterial = outer_sigil.material_override
		om.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, _ramp(A + 0.2, G + 0.9)))
		om.set_shader_parameter("intensity", 1.2 * _ramp(A + 0.2, G + 0.9) * fade_out + 1.0 * _pulse(R, 0.6))
		outer_sigil.global_position = caster.global_position + Vector3(0, 0.035, 0)
		outer_sigil.rotation.y = -t * 0.35
		# the formation: drawn upright in front of her hands, facing where she will release
		var fm: ShaderMaterial = formation.material_override
		var fk := _ramp(G, O + 0.2) * (1.0 - _ramp(R, R + 0.35))
		fm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, _ramp(G, O)))
		fm.set_shader_parameter("intensity", 1.5 * fk)
		var fwd0 := -caster.global_transform.basis.z
		formation.global_position = hands + fwd0 * 0.75 + Vector3(0, 0.08, 0)
		formation.look_at(formation.global_position + fwd0, Vector3.UP)
		formation.rotate_object_local(Vector3(0, 0, 1), t * 0.8)

	# --- gather: motes converge to the hands, hand glow
	var gather_amt := _ramp(G, O) * (1.0 - _ramp(R, R + 0.2))
	gather.emitting = t > G and t < R - 0.1
	gather.global_position = hands
	hand_sprite_l.emitting = t > G and t < R
	hand_sprite_r.emitting = hand_sprite_l.emitting
	hand_glow_l.light_energy = 1.2 * gather_amt * _light_scale
	hand_glow_r.light_energy = 1.2 * gather_amt * _light_scale
	if t > G and not _gather_sent:
		_gather_sent = true
		caster.cast_event.emit("gather")
		_bus("gather", hands)
		caster.set_expression("relaxed", 0.6)

	# --- orb position follows the hands while forming, then launches
	if not released:
		var anchor := (hands + fwd * 0.25).lerp(chest_front, 0.6)
		_orb_pos = anchor if _orb_pos == Vector3.ZERO else _orb_pos.lerp(anchor, 1.0 - exp(-10.0 * delta))
	var form_amt := _ramp(F, O + 0.3)
	var orb_amt := _ramp(O, R) * fade_out
	var pulse := 1.0 + 0.08 * sin(t * 14.0) + 0.05 * sin(t * 23.0)
	if t >= F and not _fired_rune:
		_fired_rune = true
		_bus("rune", caster.global_position)
	if t >= O and not _fired_charge:
		_fired_charge = true
		_bus("charge", _orb_pos)
	if t >= R and not released:
		released = true
		_release_from = _orb_pos
		_release_to = _orb_pos + fwd * 4.5 + Vector3(0, 1.6, 0)
		if aim_point != null:
			_release_to = aim_point
		if target_ref and is_instance_valid(target_ref):
			_release_to = MagicSystem.lead_aim(target_ref, _release_from, 11.0, float(get_meta("mastery", 0.0)), get_meta("aim_err", Vector3.ZERO))
		_flight_s = clampf(_release_from.distance_to(_release_to) / 11.0, 0.25, 1.6)
		_prev_orb = _release_from
		caster.cast_event.emit("release")
		_bus("release", _orb_pos)
		caster.set_expression("happy", 0.0)
		caster.set_expression("surprised", 0.35)
	var flight := _ramp(R, R + _flight_s)
	if released and _outcome.is_empty():
		var fk2 := 1.0 - pow(1.0 - flight, 2.2)
		_orb_pos = _release_from.lerp(_release_to, fk2) + Vector3(0, sin(fk2 * PI) * minf(0.6, _release_from.distance_to(_release_to) * 0.05), 0)
		# real flight: anything solid between the last and this frame stops the orb there
		var hit := MagicSystem.sweep(caster.get_world_3d(), _prev_orb, _orb_pos, [caster.get_rid()])
		if not hit.is_empty():
			_orb_pos = hit.position
			_release_to = hit.position
			_outcome = {"outcome": MagicSystem.judge(target_ref, hit.position, hit.collider, 0.6), "point": [snappedf(_orb_pos.x, 0.01), snappedf(_orb_pos.y, 0.01), snappedf(_orb_pos.z, 0.01)]}
			if hit.collider is Node and _outcome.outcome != "hit":
				_outcome["blocked_by"] = String((hit.collider as Node).name)
			flight = 1.0
			t = maxf(t, R + _flight_s)
		elif flight >= 1.0:
			_outcome = {"outcome": MagicSystem.judge(target_ref, _orb_pos, null, 0.6) if target_ref else "released", "point": [snappedf(_orb_pos.x, 0.01), snappedf(_orb_pos.y, 0.01), snappedf(_orb_pos.z, 0.01)]}
		if target_ref and not _outcome.is_empty():
			_outcome["distance_from_target_m"] = snappedf(_orb_pos.distance_to(target_ref.aim_point()), 0.01)
		_prev_orb = _orb_pos
	orb_root.global_position = _orb_pos
	var s := (0.25 + 0.75 * smoothstep(0.0, 1.0, orb_amt)) * pulse * (1.0 - flight * 0.6) * _sig_k
	if t < O:
		s = 0.25 * smoothstep(0.0, 1.0, form_amt)
	if flight >= 1.0:
		s = 0.001
	orb_root.scale = Vector3.ONE * maxf(s, 0.001)
	if fwd.length() > 0.1:
		orb_root.look_at(orb_root.global_position + fwd, Vector3.UP)

	# --- sigil rings draw themselves and spin on different axes
	for i in rings.size():
		var rm: ShaderMaterial = rings[i].material_override
		var ri := _ramp(F + i * 0.18, F + 0.7 + i * 0.18)
		rm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, ri))
		rm.set_shader_parameter("intensity", 1.4 * ri * (1.0 - flight))
		rings[i].transform = Transform3D(Basis(ring_axes[i], t * (0.9 + i * 0.55)) * Basis(Vector3.RIGHT, PI * 0.5 * i), Vector3.ZERO).scaled(Vector3.ONE * (1.05 + i * 0.12))

	# --- comet trails orbiting the orb
	for i in comets.size():
		var ang := t * (3.4 + i * 0.6) + i * TAU / comets.size()
		var axis := Basis(Vector3(0.3 * i, 1, 0.2).normalized(), i * 0.9)
		comets[i].position = axis * (Vector3(cos(ang), 0.25 * sin(ang * 2.0), sin(ang)) * 0.42)
		var trail: GPUParticles3D = comets[i].get_child(0)
		trail.emitting = t > O and not (flight >= 1.0)

	# --- orb light and stone bounce
	var flash := _pulse(R + _flight_s, 0.6)
	orb_light.light_energy = (2.8 * orb_amt * pulse * _light_scale + 5.0 * flash) * fade_out
	orb_light.omni_range = 6.0 + 4.0 * flash
	var bounce := orb_amt * 0.9 + flash * 1.6
	if caster.world:
		caster.world.call("set_magic_bounce", orb_root.global_position, bounce * fade_out, BLUE)
		var charge := (0.35 * awaken + 0.65 * orb_amt + 0.8 * flash) * fade_out
		caster.world.call("set_rune_charge", charge, clampf(awaken * 1.3, 0.0, 1.0))

	# --- light trail behind the orb in flight (fades along its length)
	if released and flight < 1.0:
		_trail_pts.append(_orb_pos)
		if _trail_pts.size() > 14:
			_trail_pts.pop_front()
	elif _trail_pts.size() > 0 and flight >= 1.0:
		_trail_pts.pop_front()
	_draw_trail()

	# --- burst + ground ripple on impact
	if flight >= 1.0 and not burst_done:
		burst_done = true
		burst.global_position = _release_to
		burst.restart()
		burst.emitting = true
		shockwave.visible = true
		caster.cast_event.emit("burst")
		_bus("impact" if _outcome.get("outcome", "") in ["hit", "released"] else String(_outcome.get("outcome", "impact")), _release_to)
		# the outcome is known now: the world reacts at the moment of impact (the light fades on its own)
		if not _resolved_sent:
			_resolved_sent = true
			if signature:
				caster.set_gesture_speed(1.0)
			caster.end_cast(true, "arcane_orb resolved")
			resolved.emit(_outcome)
	if burst_done:
		# a ripple across the GROUND under the impact (not a disc facing the camera); skipped when the
		# impact is high in the air
		var sw := _ramp(R + _flight_s, R + _flight_s + 0.85)
		var gy := _release_to.y - 0.5
		if caster.world and caster.world.has_method("ground_at"):
			gy = float(caster.world.ground_at(_release_to.x, _release_to.z))
		shockwave.visible = _release_to.y - gy < 1.8
		shockwave.global_position = Vector3(_release_to.x, gy + 0.04, _release_to.z)
		shockwave.rotation = Vector3.ZERO
		shockwave.scale = Vector3.ONE * (0.5 + sw * (5.0 if not signature else 8.0))
		var swm: ShaderMaterial = shockwave.material_override
		swm.set_shader_parameter("draw_progress", 1.0)
		swm.set_shader_parameter("intensity", 1.8 * (1.0 - sw))
		orb_light.global_position = _release_to

	# --- resolve
	if t > duration + 0.9:
		if caster.world:
			caster.world.call("set_magic_bounce", Vector3(0, -100, 0), 0.0, BLUE)
			caster.world.call("set_rune_charge", 0.0, 1.0)
		caster.cast_event.emit("resolved")
		_bus("dissipate", _release_to)
		if not _resolved_sent:
			if signature:
				caster.set_gesture_speed(1.0)
			caster.end_cast(true, "arcane_orb resolved")
			if _outcome.is_empty():
				_outcome = {"outcome": "released", "point": [snappedf(_release_to.x, 0.01), snappedf(_release_to.y, 0.01), snappedf(_release_to.z, 0.01)]}
			resolved.emit(_outcome)
		hand_glow_l.queue_free()
		hand_glow_r.queue_free()
		hand_sprite_l.queue_free()
		hand_sprite_r.queue_free()
		queue_free()


func _draw_trail() -> void:
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _trail_pts.size()
	for i in n:
		var p: Vector3 = _trail_pts[i]
		var nxt: Vector3 = _trail_pts[mini(i + 1, n - 1)]
		var prv: Vector3 = _trail_pts[maxi(i - 1, 0)]
		var tangent := (nxt - prv).normalized()
		var side := tangent.cross(cam.global_position - p).normalized()
		var k := float(i) / float(n - 1)                    # 0 = tail, 1 = head
		var w := 0.03 + 0.11 * k * _sig_k
		var c := BLUE.lerp(VIOLET, 1.0 - k)
		c.a = k * k
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(p + side * w)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(p - side * w)
	_trail_mesh.surface_end()


func _pulse(start: float, length: float) -> float:
	if t < start or t > start + length:
		return 0.0
	var x := (t - start) / length
	return sin(x * PI) * (1.0 - x * 0.5)
