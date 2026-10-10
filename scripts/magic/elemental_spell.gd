class_name ElementalSpell
extends Node3D
## One cast of a non-orb spell (wind, water, ember, rune, elemental charge). Each element has its own
## visual language; all share the timeline and the truthful flight:
##   activation (ground sign appears) -> rune (sign completes) -> gather (motes to the hand)
##   -> charge (core at full strength) -> release (projectile/beam leaves) -> impact -> dissipate
## Phases come from the caster's actual clip time (normalised per clip), and each phase is announced on
## MagicEvents so audio / camera stay in sync with the animation instead of fixed delays.
## Mastery adds detail (more arcs / rings / motes); LIVE_OPTIMIZED scales particle counts.

signal resolved(result: Dictionary)

const TIMING := {
	"magic_attack_1h": {"rune": 0.06, "gather": 0.12, "charge": 0.3, "release": 0.42, "end": 0.85},
	"spell_casting": {"rune": 0.06, "gather": 0.12, "charge": 0.3, "release": 0.6, "end": 0.92},
	"wide_arm_spell": {"rune": 0.08, "gather": 0.15, "charge": 0.35, "release": 0.6, "end": 0.92},
	"prepare_and_cast": {"rune": 0.06, "gather": 0.12, "charge": 0.4, "release": 0.66, "end": 0.92},
	"magic_attack_2h": {"rune": 0.04, "gather": 0.08, "charge": 0.18, "release": 0.45, "end": 0.9},
}
const SPELL_RADIUS := {"wind": 0.9, "water": 0.5, "fire": 0.4, "arcane": 0.3, "self": 0.0}

var caster: WorldCharacter
var clip := "spell_casting"
var spell_id := ""
var def := {}
var element := "arcane"
var style := ""               # wind | water | fire | rune | charge
var aim := Vector3.ZERO
var target: ReactiveElement
var power := 0.5
var tier := 0
var duration := 3.0
var t := 0.0
var _phase := ""
var _fired := {}
var _light_scale: float = RenderProfile.get_setting("magic_light_scale")

var ground: MeshInstance3D
var hand_fx: Node3D
var hand_light: OmniLight3D
var core: Node3D
var projectile: Node3D
var beam: MeshInstance3D
var _proj_pos := Vector3.ZERO
var _proj_vel := Vector3.ZERO
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
	style = {"wind": "wind", "water": "water", "fire": "fire", "self": "charge"}.get(element, "rune" if d.get("projectile", "") == "beam" else "rune")
	_build()


## called by WorldCharacter.cast_spell before configure()
func start(c: WorldCharacter, clip_name: String) -> void:
	caster = c
	clip = clip_name
	duration = caster.animation_length(clip)
	global_position = caster.global_position


func phase_time(name: String) -> float:
	return float(TIMING.get(clip, TIMING.spell_casting).get(name, 0.0)) * duration


func _announce(ph: String, pos: Vector3) -> void:
	_phase = ph
	MagicEvents.emit_phase(caster, spell_id, ph, element, pos)
	caster.cast_event.emit(ph)


# ------------------------------------------------------------------ build per element
func _build() -> void:
	var pal := FX.palette(element if style != "rune" else "rune")
	hand_fx = Node3D.new()
	add_child(hand_fx)
	hand_light = FX.light(pal[0], 0.0, 2.0)
	hand_fx.add_child(hand_light)
	match style:
		"wind":
			ground = FX.quad("res://shaders/magic/wind_arcs.gdshader", 3.4, {"color": pal[0], "arcs": 3 + tier, "intensity": 0.0, "draw_progress": 0.0})
			var sw := FX.particles(80 + 20 * tier, 1.2, FX.pm_motes("wind", "swirl"), FX.mote_mesh(0.07, true), true)
			sw.name = "Swirl"
			hand_fx.add_child(sw)
			sw.emitting = false
		"water":
			ground = FX.quad("res://shaders/magic/water_rings.gdshader", 2.6, {"color": pal[0], "rings": 2 + tier, "intensity": 0.0, "draw_progress": 0.0})
			core = _water_core()
		"fire":
			ground = null
			var rise := FX.particles(50 + 20 * tier, 1.4, FX.pm_motes("fire", "rise"), FX.mote_mesh(0.045))
			rise.name = "Rise"
			add_child(rise)
			rise.emitting = false
			core = FX.quad("res://shaders/magic/flame_billboard.gdshader", 0.32, {"noise_tex": FX.noise(), "heat": 0.4, "intensity": 0.0}, false)
		"rune":
			ground = FX.quad("res://shaders/magic/sigil.gdshader", 1.6, {"color": pal[0], "sides": 4, "intensity": 0.0, "draw_progress": 0.0, "spin": 0.15, "seed": 4.0})
			core = FX.quad("res://shaders/magic/sigil.gdshader", 0.55, {"color": pal[1], "sides": 4 + tier, "intensity": 0.0, "draw_progress": 0.0, "spin": -0.4, "seed": 9.0}, false)
		"charge":
			ground = FX.quad("res://shaders/magic/sigil.gdshader", 2.6, {"color": pal[0], "sides": 6, "intensity": 0.0, "draw_progress": 0.0, "spin": 0.2, "seed": 2.0})
			for i in 3:
				var ring := FX.quad("res://shaders/magic/sigil.gdshader", 1.4, {"color": [FX.palette("fire")[0], FX.palette("water")[0], FX.palette("wind")[0]][i],
					"sides": 3 + i, "intensity": 0.0, "draw_progress": 1.0, "spin": 0.5 - 0.3 * i, "seed": float(i) * 3.0})
				ring.name = "ChargeRing%d" % i
				add_child(ring)
	if ground:
		add_child(ground)
	if core:
		hand_fx.add_child(core)
	var gather := FX.particles(70 + 30 * tier, 0.8, FX.pm_motes(element if style != "rune" else "rune", "gather"), FX.mote_mesh(0.04), true)
	gather.name = "Gather"
	hand_fx.add_child(gather)
	gather.emitting = false


func _water_core() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.11
	sph.height = 0.22
	sph.radial_segments = 24
	sph.rings = 12
	mi.mesh = sph
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.5, 0.8, 1.0, 0.45)
	m.roughness = 0.02
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 0.8
	m.emission_enabled = true
	m.emission = Color(0.3, 0.6, 0.9)
	m.emission_energy_multiplier = 0.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * 0.01
	return mi


# ------------------------------------------------------------------ timeline
func _ramp(a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	if caster == null or def.is_empty():
		return
	t += delta
	var R := phase_time("rune"); var G := phase_time("gather"); var C := phase_time("charge")
	var L := phase_time("release"); var E := phase_time("end")
	var hand: Vector3 = caster.right_hand.global_position if style != "charge" else caster.chest.global_position
	if style == "water" or style == "rune":
		hand = (caster.left_hand.global_position + caster.right_hand.global_position) * 0.5
	var fwd := -caster.global_transform.basis.z
	hand_fx.global_position = hand + fwd * 0.12
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
		if hand_fx.has_node("Swirl"):
			(hand_fx.get_node("Swirl") as GPUParticles3D).emitting = true
		if has_node("Rise"):
			(get_node("Rise") as GPUParticles3D).emitting = true
	if t >= C and not _fired.has("charge"):
		_fired.charge = true
		_announce("charge", hand)
	var awaken := _ramp(0.0, R + 0.35)
	var build := _ramp(G, L)
	var fade := 1.0 - _ramp(E - 0.1, duration + 0.6)
	# ground sign under her feet
	if ground:
		ground.global_position = caster.global_position + Vector3(0, 0.035, 0)
		var gm: ShaderMaterial = ground.material_override
		gm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, awaken))
		gm.set_shader_parameter("intensity", (0.9 + 0.5 * build) * awaken * fade * (0.8 + 0.2 * tier) * (1.8 if style == "wind" else 1.0))
	# charging core / hand light
	hand_light.light_energy = (0.4 + 1.4 * build) * fade * _light_scale * (1.0 if not _flying else 0.3)
	match style:
		"water":
			if core and not _flying:
				core.scale = Vector3.ONE * maxf(0.01, smoothstep(0.0, 1.0, build) * (0.9 + 0.15 * sin(t * 9.0)))
				(core.material_override as StandardMaterial3D).emission_energy_multiplier = 0.6 * build
		"fire":
			if core and not _flying:
				var fm: ShaderMaterial = core.material_override
				fm.set_shader_parameter("intensity", 1.6 * build * fade)
				fm.set_shader_parameter("heat", 0.4 + build)
				core.scale = Vector3.ONE * (0.6 + 0.9 * build)
		"rune":
			if core and not _flying:
				core.global_position = hand + fwd * 0.45
				core.look_at(core.global_position + fwd, Vector3.UP)
				var rm: ShaderMaterial = core.material_override
				rm.set_shader_parameter("draw_progress", smoothstep(0.0, 1.0, _ramp(R, C + 0.2)))
				rm.set_shader_parameter("intensity", 2.0 * _ramp(R, C) * fade)
		"charge":
			for i in 3:
				var ring: MeshInstance3D = get_node("ChargeRing%d" % i)
				var rise := _ramp(G + i * 0.15, L)
				ring.global_position = caster.global_position + Vector3(0, 0.1 + rise * (0.7 + 0.35 * i), 0)
				ring.scale = Vector3.ONE * (1.3 - 0.5 * rise)
				(ring.material_override as ShaderMaterial).set_shader_parameter("intensity", 1.5 * sin(rise * PI) * fade)
	# release
	if t >= L and not _fired.has("release"):
		_fired.release = true
		_release(hand, fwd)
	if _flying:
		_fly(delta)
	if beam:
		var reach := _ramp(L, L + 0.25)
		(beam.material_override as ShaderMaterial).set_shader_parameter("reach", reach)
		(beam.material_override as ShaderMaterial).set_shader_parameter("intensity", 2.0 * (1.0 - _ramp(L + 0.5, L + 1.4)))
	# resolve: once the clip is over and the impact (if any) has happened
	if t > duration + 0.7 and not _fired.has("dissipate") and not _flying:
		_fired.dissipate = true
		_announce("dissipate", hand)
		caster.end_cast(true, "%s resolved (%s)" % [spell_id, _impact.get("outcome", "self")])
		if _impact.is_empty():
			_impact = {"outcome": "self", "point": [caster.global_position.x, caster.global_position.y, caster.global_position.z]}
		resolved.emit(_impact)
		_done_t = t
	if _done_t >= 0.0 and t > _done_t + 1.5:
		queue_free()


func _release(hand: Vector3, fwd: Vector3) -> void:
	_announce("release", hand)
	(hand_fx.get_node("Gather") as GPUParticles3D).emitting = false
	if hand_fx.has_node("Swirl"):
		(hand_fx.get_node("Swirl") as GPUParticles3D).emitting = false
	if has_node("Rise"):
		(get_node("Rise") as GPUParticles3D).emitting = false
	if style == "charge":
		FX.burst(get_parent(), caster.chest.global_position, 60, 1.0, FX.pm_motes("self", "burst"), FX.mote_mesh(0.05))
		_impact = {"outcome": "self", "point": _v(caster.global_position)}
		return
	var start := hand + fwd * 0.3
	if style == "rune":
		# a beam: instant line to the aim point, then judged like a projectile that arrives at once
		var hit := MagicSystem.sweep(caster.get_world_3d(), start, aim + (aim - start).normalized() * 0.3, [caster.get_rid()])
		var end := aim
		var col: Object = null
		if not hit.is_empty():
			end = hit.position
			col = hit.collider
		beam = MeshInstance3D.new()
		var q := QuadMesh.new()
		var length := start.distance_to(end)
		q.size = Vector2(length, 0.16)
		beam.mesh = q
		var bm := ShaderMaterial.new()
		bm.shader = load("res://shaders/magic/beam.gdshader")
		bm.set_shader_parameter("color", FX.palette("rune")[0])
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_parent().add_child(beam)
		var mid := (start + end) * 0.5
		var dir := (end - start).normalized()
		var cam := get_viewport().get_camera_3d()
		var side := dir.cross((cam.global_position - mid).normalized() if cam else Vector3.UP).normalized()
		var up := side.cross(dir).normalized()
		beam.global_transform = Transform3D(Basis(dir, side, up), mid)
		get_tree().create_timer(1.6).timeout.connect(beam.queue_free)
		if core:
			core.visible = false
		_land(end, col)
		return
	projectile = Node3D.new()
	get_parent().add_child(projectile)
	_proj_pos = start
	projectile.global_position = start
	var speed := float(def.get("speed", 10.0))
	_proj_vel = (aim - start).normalized() * speed
	var trail_kind := "trail"
	var trail := FX.particles((60 if style != "wind" else 120) + 20 * tier, 0.5 if style != "wind" else 0.45, FX.pm_motes(element, trail_kind), FX.mote_mesh(0.05 if style != "wind" else 0.07))
	projectile.add_child(trail)
	trail.emitting = true
	var pl := FX.light(FX.palette(element)[0], 1.2 * _light_scale, 3.5)
	projectile.add_child(pl)
	if core:
		core.reparent(projectile, false)
		core.position = Vector3.ZERO
		if style == "fire":
			core.scale = Vector3.ONE * 1.4
	if style == "wind":
		for k in 2:
			var ring := FX.quad("res://shaders/magic/wind_arcs.gdshader", 1.5 - 0.5 * k, {"color": FX.palette("wind")[k], "arcs": 3 + tier, "intensity": 2.6, "spin": 5.0 - 2.0 * k}, false)
			projectile.add_child(ring)
			ring.basis = Basis.looking_at(_proj_vel.normalized(), Vector3.UP if absf(_proj_vel.normalized().y) < 0.95 else Vector3.FORWARD)
			ring.position = -_proj_vel.normalized() * 0.35 * k
		# the visible "body" of the gust: streaks flung forward along the path
		var streak := FX.particles(90, 0.45, FX.process("wind_streak", func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.35
			pm.spread = 12.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3.ZERO
			pm.particle_flag_align_y = true
			pm.scale_min = 0.8
			pm.scale_max = 1.6
			pm.color_ramp = FX.ramp([Color(0.8, 1.0, 0.9, 0.0), Color(0.85, 1.0, 0.92, 0.9), Color(0.7, 0.95, 0.85, 0.0)], [0.0, 0.25, 1.0])), FX.mote_mesh(0.06, true))
		streak.process_material = streak.process_material.duplicate()
		(streak.process_material as ParticleProcessMaterial).direction = _proj_vel.normalized()
		projectile.add_child(streak)
		streak.emitting = true
	_flying = true


func _fly(delta: float) -> void:
	var next := _proj_pos + _proj_vel * delta
	var hit := MagicSystem.sweep(caster.get_world_3d(), _proj_pos, next, [caster.get_rid()])
	if not hit.is_empty():
		_land(hit.position, hit.collider)
		return
	# air targets (flame, crystal, water surface) have no collider of their own: judge the closest approach
	if target:
		var tp := target.aim_point()
		var seg := next - _proj_pos
		var tt := clampf((tp - _proj_pos).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var closest := _proj_pos + seg * tt
		if closest.distance_to(tp) <= target.aim_radius + float(SPELL_RADIUS.get(element, 0.3)) * 0.6 and tt < 1.0:
			_land(closest, null, true)
			return
		if target.kind == "water" and next.y <= tp.y + 0.02:
			_land(Vector3(next.x, tp.y, next.z), null, true)
			return
	_proj_pos = next
	_travelled += (_proj_vel * delta).length()
	projectile.global_position = _proj_pos
	if _travelled > float(def.get("range", 10.0)) + 3.0:
		_land(_proj_pos, null)


func _land(point: Vector3, collider: Object, on_target := false) -> void:
	_flying = false
	var outcome := "hit" if on_target else MagicSystem.judge(target, point, collider, float(SPELL_RADIUS.get(element, 0.3)))
	_impact = {"outcome": outcome, "point": _v(point), "distance_from_target_m": snappedf(point.distance_to(target.aim_point()), 0.01) if target else -1.0}
	if collider is Node and outcome != "hit":
		_impact["blocked_by"] = String((collider as Node).name)
	_announce("impact" if outcome == "hit" else outcome, point)
	_impact_fx(point, outcome)
	if projectile:
		for c in projectile.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
			elif c is OmniLight3D or c is MeshInstance3D:
				c.visible = false
		get_tree().create_timer(0.8).timeout.connect(projectile.queue_free)


func _impact_fx(point: Vector3, outcome: String) -> void:
	var host := get_parent()
	var big := outcome == "hit"
	match style:
		"wind":
			FX.burst(host, point, 26 if big else 14, 1.4, FX.pm_puff("dust"), FX.puff_mesh(0.5))
			FX.burst(host, point, 40, 0.6, FX.pm_motes("wind", "burst"), FX.mote_mesh(0.04, true))
		"water":
			FX.burst(host, point, 50 if big else 25, 1.1, FX.pm_motes("water", "splash"), FX.mote_mesh(0.05))
		"fire":
			FX.burst(host, point, 50 if big else 25, 0.9, FX.pm_motes("fire", "burst"), FX.mote_mesh(0.05))
		"rune":
			var g := FX.quad("res://shaders/magic/sigil.gdshader", 0.8, {"color": FX.palette("rune")[1], "sides": 4, "intensity": 2.5, "draw_progress": 1.0, "spin": 0.6}, false)
			host.add_child(g)
			g.global_position = point
			var cam := get_viewport().get_camera_3d()
			if cam:
				g.look_at(cam.global_position, Vector3.UP)
			var tw := g.create_tween()
			tw.tween_method(func(v: float): (g.material_override as ShaderMaterial).set_shader_parameter("intensity", v), 2.5, 0.0, 1.0)
			tw.tween_callback(g.queue_free)
	var flash := FX.light(FX.palette(element if style != "rune" else "rune")[0], (2.2 if big else 1.2) * _light_scale, 4.0)
	host.add_child(flash)
	flash.global_position = point + Vector3(0, 0.3, 0)
	var tw2 := flash.create_tween()
	tw2.tween_property(flash, "light_energy", 0.0, 0.6)
	tw2.tween_callback(flash.queue_free)


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
