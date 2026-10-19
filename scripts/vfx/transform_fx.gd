class_name TransformFX
extends Node3D
## The real-time transformation's effects (TransformationSequence), built from the spell system (SpellFX masks and
## element colours, data/elements.json) in the transforming mage's own two elements - Mika: wind + star (white,
## silver, periwinkle); Luna: moon + shadow (gold, violet, moonlight). Everything is built and drawn once before the
## scene starts (pipelines compiled, nothing created mid-scene); the sequence only switches parts on and off.
##   spiral    wind and petals spiralling round her, rising (build-up), stars in it
##   gather    light drawn into her hands and chest
##   mist      sparkling mist round her feet (magic_mist.gdshader)
##   rings     a ring of light round her waist and a second tilted one, star flowers orbiting her (body of light)
##   burst     a shockwave ring along the ground, petals and stars thrown outward (plus SpellFX.burst and its
##             impact frame)
##   sparkle   sparkles falling round her as she descends
## The body-of-light overlay (body_light.gdshader) and the old outfit's burn (burn_dissolve.gdshader) are materials
## made here too.

const BODY_LIGHT := preload("res://shaders/vfx/body_light.gdshader")
const BURN := preload("res://shaders/vfx/burn_dissolve.gdshader")
const MIST := preload("res://shaders/vfx/magic_mist.gdshader")

var who := ""
var el1 := {}             # her first element (main colour)
var el2 := {}             # her second (accent)
var light_mat: ShaderMaterial
var burn_mat: ShaderMaterial
var spiral: Array = []    # GPUParticles3D
var gather: Array = []
var mist: Array = []      # MeshInstance3D
var mist_root: Node3D
var ring_root: Node3D
var rings: Array = []
var flowers: Array = []
var shock: MeshInstance3D
var explode: Array = []
var sparkle: Array = []
var _spin := 0.0
var _ring_on := 0.0       # 0..1, how far the rings and star flowers have opened
var _ring_target := 0.0


static func elements_of(w: String) -> Array:
	var ord: Array = SpellFX.load_data().get("mages", {}).get(w, {}).get("elements", ["wind", "star"])
	return [String(ord[0]), String(ord[1] if ord.size() > 1 else ord[0])]


static func make(w: String) -> TransformFX:
	var t := TransformFX.new()
	t.name = "TransformFX_" + w
	t.who = w
	var els := elements_of(w)
	t.el1 = SpellFX.element(els[0])
	t.el2 = SpellFX.element(els[1])
	t._build()
	return t


func _pm(key: String, setup: Callable) -> ParticleProcessMaterial:
	return FX.process("tf_%s_%s" % [who, key], setup)


func _colors(e: Dictionary, a := 1.0) -> GradientTexture1D:
	return FX.ramp([Color(e.core, 0.0), Color(e.core, a), Color(e.body, a * 0.9), Color(e.edge, 0.0)], [0.0, 0.1, 0.55, 1.0])


func _parts(amount: int, life: float, pm: ParticleProcessMaterial, sprite: String, e: Dictionary, size: float, local := false) -> GPUParticles3D:
	var p := FX.particles(amount, life, pm, SpellFX.particle_mesh(String(e.id), sprite, size), local)
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-14, -4, -14), Vector3(28, 16, 28))
	add_child(p)
	return p


func _build() -> void:
	var e1 := el1
	var e2 := el2
	# --- the body of light and the burn (shared by her old and new outfit meshes)
	light_mat = ShaderMaterial.new()
	light_mat.shader = BODY_LIGHT
	light_mat.set_shader_parameter("core_color", Color(1, 1, 1))
	light_mat.set_shader_parameter("body_color", Color(e1.body).lerp(Color.WHITE, 0.45))
	light_mat.set_shader_parameter("rim_color", Color(e2.body))
	light_mat.set_shader_parameter("glow", 2.3)
	light_mat.set_shader_parameter("flow", FX.noise())
	light_mat.set_shader_parameter("cover", 0.0)
	light_mat.render_priority = 1
	burn_mat = ShaderMaterial.new()
	burn_mat.shader = BURN
	burn_mat.set_shader_parameter("core_color", Color(1, 1, 1))
	burn_mat.set_shader_parameter("body_color", Color(e1.body).lerp(Color.WHITE, 0.45))
	burn_mat.set_shader_parameter("burn_color", Color(e2.body))
	burn_mat.set_shader_parameter("dissolve_texture", FX.noise())
	burn_mat.set_shader_parameter("dissolve_amount", 0.0)
	burn_mat.render_priority = 2
	# --- spiral: petals and wind round her, rising and turning (tangential acceleration turns about gravity's axis)
	var spiral_pm := func(radius: float, up: float) -> Callable:
		return func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = radius
			pm.emission_ring_inner_radius = radius * 0.7
			pm.emission_ring_height = 1.4                  # the whole column of her body, not the ground
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 10.0
			pm.initial_velocity_min = up * 0.7
			pm.initial_velocity_max = up
			pm.gravity = Vector3(0, 0.9, 0)               # (also the axis the tangential spin turns about)
			pm.tangential_accel_min = 4.0
			pm.tangential_accel_max = 6.5
			pm.radial_accel_min = -0.5
			pm.radial_accel_max = 0.1
			pm.damping_min = 0.3
			pm.damping_max = 0.8
			pm.scale_min = 0.6
			pm.scale_max = 1.4
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -160.0
			pm.angular_velocity_max = 160.0
			pm.color_ramp = _colors(e1)
	spiral.append(_parts(150, 2.2, _pm("spiral_petal2", spiral_pm.call(1.1, 2.0)), "petal", e1, 0.2, true))
	spiral.append(_parts(110, 1.8, _pm("spiral_glint2", spiral_pm.call(0.85, 2.4)), String(e2.particle), e2, 0.16, true))
	spiral.append(_parts(40, 1.5, _pm("spiral_wisp2", spiral_pm.call(1.3, 1.4)), "wisp", e1, 0.6, true))
	# --- gather: light streaming into her chest from all round
	var gpm := _pm("gather", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
		pm.emission_sphere_radius = 2.4
		pm.gravity = Vector3(0, 0.1, 0)
		pm.radial_accel_min = -10.0
		pm.radial_accel_max = -7.0
		pm.tangential_accel_min = 1.5
		pm.tangential_accel_max = 3.0
		pm.scale_min = 0.5
		pm.scale_max = 1.2
		pm.color_ramp = _colors(e2))
	gather.append(_parts(90, 0.9, gpm, "glint", e2, 0.14, true))
	gather.append(_parts(40, 0.9, gpm, String(e1.particle), e1, 0.16, true))
	# --- mist round her feet
	mist_root = Node3D.new()
	mist_root.name = "Mist"
	add_child(mist_root)
	var mm := ShaderMaterial.new()
	mm.shader = MIST
	mm.set_shader_parameter("noise_tex", FX.noise())
	mm.set_shader_parameter("mist_color", Color(e1.body).lerp(Color(e2.body), 0.4))
	mm.set_shader_parameter("sparkle_color", Color(e1.core))
	mm.set_shader_parameter("strength", 0.38)
	for i in 9:
		var q := MeshInstance3D.new()
		q.mesh = SpellFX.quad_mesh(Vector2(2.6, 1.7))
		q.material_override = mm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / 9.0
		q.position = Vector3(cos(a) * 0.95, 0.6, sin(a) * 0.95)
		q.set_instance_shader_parameter("seed", float(i) * 0.37)
		q.set_instance_shader_parameter("alpha", 0.0)
		mist_root.add_child(q)
		mist.append(q)
	# --- rings of light and orbiting star flowers (the body of light)
	ring_root = Node3D.new()
	ring_root.name = "Rings"
	add_child(ring_root)
	for spec in [[3.4, Vector3.ZERO, String(e1.circle), e1], [2.6, Vector3(0.5, 0.0, 0.32), "ring", e2], [4.4, Vector3(-0.35, 0, -0.2), "ring", e1]]:
		var r := MeshInstance3D.new()
		r.mesh = SpellFX.quad_mesh(Vector2(spec[0], spec[0]))
		r.material_override = SpellFX.ramp_material(String((spec[3] as Dictionary).id), String(spec[2]), false, 0.9, 1.9)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pivot := Node3D.new()
		pivot.rotation = spec[1]
		ring_root.add_child(pivot)
		pivot.add_child(r)
		r.rotation = Vector3(-PI * 0.5, 0, 0)
		r.set_instance_shader_parameter("alpha", 0.0)
		rings.append(r)
	for i in 8:
		var f := MeshInstance3D.new()
		f.mesh = SpellFX.quad_mesh(Vector2(0.62, 0.62))
		f.material_override = SpellFX.ramp_material(String(e2.id), "starflower", true, 2.5, 2.4)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.set_instance_shader_parameter("alpha", 0.0)
		ring_root.add_child(f)
		flowers.append(f)
	# --- the burst: a shockwave along the ground, petals and stars thrown out
	shock = MeshInstance3D.new()
	shock.mesh = SpellFX.quad_mesh(Vector2(2.0, 2.0))
	shock.material_override = SpellFX.ramp_material(String(e1.id), "ring", false, 0.0, 2.6)
	shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shock.rotation = Vector3(-PI * 0.5, 0, 0)
	shock.set_instance_shader_parameter("alpha", 0.0)
	add_child(shock)
	var epm := func(vmin: float, vmax: float, e: Dictionary) -> Callable:
		return func(pm: ParticleProcessMaterial):
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.4
			pm.direction = Vector3(0, 0.15, 0)
			pm.spread = 180.0
			pm.initial_velocity_min = vmin
			pm.initial_velocity_max = vmax
			pm.damping_min = 3.0
			pm.damping_max = 5.5
			pm.gravity = Vector3(0, -0.9, 0)
			pm.scale_min = 0.6
			pm.scale_max = 1.5
			pm.angle_min = -180.0
			pm.angle_max = 180.0
			pm.angular_velocity_min = -220.0
			pm.angular_velocity_max = 220.0
			pm.color_ramp = _colors(e)
	for spec in [[220, 2.4, "petal", e1, 0.22, 7.0, 15.0], [160, 1.8, String(e2.particle), e2, 0.2, 9.0, 18.0], [90, 1.2, "glint", e2, 0.3, 12.0, 22.0]]:
		var p := _parts(int(spec[0]), float(spec[1]), _pm("explode_%s_%s" % [spec[2], (spec[3] as Dictionary).id], epm.call(spec[5], spec[6], spec[3])), String(spec[2]), spec[3], float(spec[4]))
		p.one_shot = true
		p.explosiveness = 0.95
		explode.append(p)
	# --- sparkles falling round her as she comes down
	var spm := _pm("sparkle", func(pm: ParticleProcessMaterial):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(1.1, 0.9, 1.1)
		pm.direction = Vector3(0, -1, 0)
		pm.spread = 30.0
		pm.initial_velocity_min = 0.15
		pm.initial_velocity_max = 0.5
		pm.gravity = Vector3(0, -0.25, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		pm.color_ramp = _colors(e2))
	sparkle.append(_parts(110, 2.4, spm, "glint", e2, 0.13))
	sparkle.append(_parts(60, 2.8, spm, "petal", e1, 0.17))


## Every part drawn for a few frames, out of sight under the ground at `hidden_at` (still in the lens' frustum, so each
## pipeline compiles now - not when the scene first shows it).
func prewarm(hidden_at: Vector3) -> void:
	global_position = hidden_at
	for p in spiral + gather + explode + sparkle:
		(p as GPUParticles3D).amount_ratio = 0.05
		(p as GPUParticles3D).emitting = true
	for q in mist + rings + flowers + [shock]:
		(q as GeometryInstance3D).set_instance_shader_parameter("alpha", 0.01)
	for i in 4:
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		else:
			await get_tree().process_frame
	for p in spiral + gather + explode + sparkle:
		(p as GPUParticles3D).emitting = false
		(p as GPUParticles3D).amount_ratio = 1.0
	for q in mist + rings + flowers + [shock]:
		(q as GeometryInstance3D).set_instance_shader_parameter("alpha", 0.0)


func emit(list: Array, on: bool) -> void:
	for p in list:
		var gp := p as GPUParticles3D
		if on:
			gp.restart()
		gp.emitting = on


## The parts that ride on her (spiral, gather, rings, sparkles) follow `c` each frame; the mist and the shockwave stay
## on the ground where she started.
var follow: Node3D
var ground := Vector3.ZERO


func _process(delta: float) -> void:
	if follow and is_instance_valid(follow):
		var fp := follow.global_position
		for p in spiral:
			(p as Node3D).global_position = fp + Vector3(0, 0.85, 0)
		for p in gather:
			(p as Node3D).global_position = fp + Vector3(0, 1.25, 0)
		for p in sparkle:
			(p as Node3D).global_position = fp + Vector3(0, 1.9, 0)
		ring_root.global_position = fp + Vector3(0, 1.05, 0)
	mist_root.global_position = ground
	_spin += delta
	_ring_on = move_toward(_ring_on, _ring_target, delta * 1.6)
	for i in rings.size():
		var r: MeshInstance3D = rings[i]
		var k: float = ease(_ring_on, 0.4)
		(r.get_parent() as Node3D).rotation.y = _spin * (1.4 if i % 2 == 0 else -1.0)
		r.scale = Vector3.ONE * (0.3 + 0.7 * k)
		r.set_instance_shader_parameter("alpha", k * (0.85 if i < 2 else 0.5))
	for i in flowers.size():
		var f: MeshInstance3D = flowers[i]
		var a := TAU * i / flowers.size() + _spin * 1.7
		var rad := 1.0 + 0.55 * ease(_ring_on, 0.5)
		f.position = Vector3(cos(a) * rad, sin(_spin * 2.0 + i) * 0.5, sin(a) * rad)
		f.set_instance_shader_parameter("alpha", ease(_ring_on, 0.5))


func set_rings(on: bool) -> void:
	_ring_target = 1.0 if on else 0.0


func set_mist(a: float, dur: float) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	var from := float(mist[0].get_instance_shader_parameter("alpha")) if not mist.is_empty() else 0.0
	tw.tween_method(func(v: float):
		for q in mist:
			(q as GeometryInstance3D).set_instance_shader_parameter("alpha", v), from, a, dur)


## The shockwave: a ring of light racing out along the ground to ~11 m, fading.
func shockwave(at: Vector3) -> void:
	shock.global_position = at + Vector3(0, 0.08, 0)
	shock.scale = Vector3.ONE * 0.5
	shock.set_instance_shader_parameter("alpha", 1.0)
	var tw := create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(shock, "scale", Vector3.ONE * 11.0, 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): shock.set_instance_shader_parameter("alpha", v), 1.0, 0.0, 1.0).set_delay(0.15)


func explode_at(at: Vector3) -> void:
	for p in explode:
		(p as Node3D).global_position = at
	emit(explode, true)


## The body-of-light overlay on every mesh of an avatar (or off).
func light_on(avatar: Node, on: bool) -> void:
	if avatar == null:
		return
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = light_mat if on else null


## Her old outfit as burning light: its frozen last pose with the burn material in place of its own.
func burn_on(avatar: Node) -> void:
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = null
		(mi as MeshInstance3D).material_override = burn_mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
