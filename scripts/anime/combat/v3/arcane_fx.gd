class_name ArcaneFX
extends Node3D
## Combat v3 magic, the reference language of Download(9) (studied frame by frame at 30 fps, brightness measured per
## frame): every spell is layered - a bright white core with a coloured edge, soft vapour wisps orbiting it, hundreds of
## tiny twinkling star motes that drift and linger, a horizontal lens streak at every flash, a rune sigil at the hand
## before it, shaped bodies (blades, a moon) that GROW, HOVER and BOB before they launch, and a soft white billow with
## long rays and a shock ring when it lands. Timing (measured): hits flare in 1-3 frames and die in 2-6; spells peak
## in 3-8 frames and fade over 10-26; big spells build 0.8-1.5 s and linger 2.3-3.7 s.

const PAL := CombatVFX.PAL

var vfx: CombatVFX
var svfx: SpellVFX
var _star: ArrayMesh
var _star_mat := {}
var _sh := {}
var stats := {"motes": 0, "wisps": 0, "sigils": 0, "billows": 0, "volleys": 0, "moons": 0, "streaks": 0}
var _follow: Array = []                     # [node, Callable -> world point]


static func make(host: Node, combat_vfx: CombatVFX, spell_vfx: SpellVFX) -> ArcaneFX:
	var a := ArcaneFX.new()
	a.name = "ArcaneFX"
	a.vfx = combat_vfx
	a.svfx = spell_vfx
	host.add_child(a)
	a._star = a._star_mesh()
	for n in ["sigil", "soft_puff", "moon"]:
		a._sh[n] = load("res://shaders/anime/combat/v3/%s.gdshader" % n)
	return a


func _col(who: String, key: String) -> Color:
	return PAL.get(who, PAL.mika)[key]


func _mat(shader: String, who: String, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _sh[shader]
	m.set_shader_parameter("core", _col(who, "core"))
	m.set_shader_parameter("edge", _col(who, "edge"))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("noise", vfx.noise)
	return m


## A tiny sparkle that reads as a star from any side: three crossed needle diamonds.
func _star_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 0.034
	var W := 0.0035
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		var a: Vector3 = axis
		var p := a.cross(Vector3.UP if absf(a.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		var q := a.cross(p).normalized()
		for side in [p, q, -p, -q]:
			var s2: Vector3 = side
			for tip in [a * L, -a * L]:
				var n := ((tip as Vector3) - s2 * W).cross(s2 * W).normalized()
				st.set_normal(n)
				st.add_vertex(Vector3.ZERO + s2 * W)
				st.add_vertex(tip)
				st.add_vertex(s2.cross(a).normalized() * W)
	return st.commit()


# ------------------------------------------------------------------------------------------------ light
## A real light that follows `src` (a world point or a Callable -> point: her hand, a shape in flight) in her colour:
## grows in over `rise`, holds, fades over `fade` (the gathering energy lights her face, her body and the ground).
func glow(src, who: String, energy := 3.0, rng := 3.0, dur := 1.0, rise := 0.2, fade := 0.35) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = _col(who, "edge").lerp(_col(who, "core"), 0.35)
	l.light_energy = 0.0
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.light_specular = 0.6
	l.shadow_enabled = false
	add_child(l)
	l.global_position = (src as Callable).call() if src is Callable else src
	if src is Callable:
		_follow.append([l, src])
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", energy, maxf(rise, 0.01)).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(dur - rise - fade, 0.0))
	tw.tween_property(l, "light_energy", 0.0, maxf(fade, 0.01)).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)
	return l


## The floor floods with her colour at a release or an impact (a broad low light over the ground point, as the
## reference's arena lights up in the caster's colour on every big cast): a fast rise and a slower fall.
func flood(at: Vector3, who: String, energy := 5.0, rng := 9.0, dur := 0.7) -> void:
	var l := OmniLight3D.new()
	l.light_color = _col(who, "edge")
	l.light_energy = 0.0
	l.omni_range = rng
	l.omni_attenuation = 0.8
	l.light_specular = 0.2
	l.shadow_enabled = false
	add_child(l)
	l.global_position = at + Vector3.UP * 1.2
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", energy, 0.06)
	tw.tween_property(l, "light_energy", 0.0, maxf(dur, 0.05)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.queue_free)


# ------------------------------------------------------------------------------------------------ motes
## Twinkling star motes. mode: "burst" (thrown out from the point, then drifting and slowly falling), "swirl" (orbiting
## round the point as they drift up), "gather" (pulled in toward the point), "drift" (a slow hanging cloud).
## `src` is a world point or a Callable -> point (it follows). Returns the emitter.
func motes(src, who: String, n := 120, life := 1.2, radius := 0.6, mode := "burst", speed := 2.0) -> GPUParticles3D:
	stats.motes += n
	var ps := GPUParticles3D.new()
	ps.amount = n
	ps.lifetime = life
	ps.explosiveness = 0.85 if mode == "burst" else 0.0
	ps.one_shot = mode == "burst"
	ps.local_coords = mode in ["swirl", "gather"]
	ps.randomness = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * (0.25 if mode == "burst" else 1.0)
	pm.gravity = Vector3(0, -0.6 if mode == "burst" else (0.25 if mode == "swirl" else 0.0), 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.5
	match mode:
		"burst":
			pm.direction = Vector3.UP
			pm.spread = 180.0
			pm.initial_velocity_min = speed * 0.3
			pm.initial_velocity_max = speed
		"swirl":
			pm.orbit_velocity_min = 0.35
			pm.orbit_velocity_max = 0.9
			pm.radial_accel_min = -0.4
			pm.radial_accel_max = 0.6
		"gather":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			pm.radial_accel_min = -speed * 3.0
			pm.radial_accel_max = -speed * 4.5
			pm.orbit_velocity_min = 0.2
			pm.orbit_velocity_max = 0.5
		"drift":
			pm.initial_velocity_min = 0.05
			pm.initial_velocity_max = 0.3
			pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.8
	pm.scale_max = 3.0
	# the twinkle: brightness flickers over the life, a few motes flash big
	var g := Gradient.new()
	var c := _col(who, "core")
	var e := _col(who, "edge")
	g.set_color(0, Color(c.r * 4.0, c.g * 4.0, c.b * 4.0, 1.0))
	g.add_point(0.15, Color(e.r * 2.2, e.g * 2.2, e.b * 2.2, 0.5))
	g.add_point(0.3, Color(c.r * 3.5, c.g * 3.5, c.b * 3.5, 1.0))
	g.add_point(0.5, Color(e.r * 1.8, e.g * 1.8, e.b * 1.8, 0.4))
	g.add_point(0.65, Color(c.r * 3.0, c.g * 3.0, c.b * 3.0, 0.9))
	g.set_color(g.get_point_count() - 1, Color(e.r, e.g, e.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(0.1, 1.0))
	sc.add_point(Vector2(0.7, 0.8))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	ps.process_material = pm
	ps.draw_pass_1 = _star
	ps.material_override = vfx._spark_material(who)
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)
	if src is Callable:
		ps.global_position = (src as Callable).call()
		_follow.append([ps, src])
	else:
		ps.global_position = src
	ps.emitting = true
	if mode == "burst":
		get_tree().create_timer(life + 0.4, true, false, false).timeout.connect(ps.queue_free)
	return ps


func stop(ps: GPUParticles3D, linger := 1.5) -> void:
	if not is_instance_valid(ps):
		return
	ps.emitting = false
	get_tree().create_timer(linger, true, false, false).timeout.connect(ps.queue_free)


# ------------------------------------------------------------------------------------------------ wisps
## Soft vapour ribbons orbiting a point for `dur` s (they keep turning, fade in fast, out slowly): wide translucent
## crescent smears with no hard edge, each on its own tilted orbit.
func wisps(center, who: String, radius := 1.0, dur := 1.0, n := 4, turn := 2.5) -> Node3D:
	stats.wisps += n
	var root := Node3D.new()
	add_child(root)
	root.global_position = center.call() if center is Callable else center
	if center is Callable:
		_follow.append([root, center])
	for i in n:
		var pivot := Node3D.new()
		root.add_child(pivot)
		pivot.basis = Basis(Vector3(randf_range(-1, 1), randf_range(0.6, 1.4), randf_range(-1, 1)).normalized(), randf() * TAU)
		var mi := MeshInstance3D.new()
		var r := radius * randf_range(0.7, 1.15)
		mi.mesh = svfx.sector(r * 0.45, r, randf_range(150.0, 250.0))
		var m := svfx.smear_mat(who, 2.0)
		m.set_shader_parameter("rim_gain", 0.15)
		m.set_shader_parameter("softness", 1.0)
		m.set_shader_parameter("tail", 1.0)
		m.set_shader_parameter("head", 1.0)
		m.set_shader_parameter("fade", 0.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
		var spin := turn * randf_range(0.7, 1.3) * (1.0 if i % 2 == 0 else -1.0)
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 0.0, 1.0, minf(0.15, dur * 0.3))
		tw.tween_interval(maxf(dur - 0.15 - dur * 0.45, 0.0))
		tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.45)
		var tw2 := pivot.create_tween()
		tw2.tween_property(pivot, "rotation", pivot.rotation + Vector3(0, spin * dur, 0), dur)
	get_tree().create_timer(dur + 0.05, true, false, false).timeout.connect(root.queue_free)
	return root


# ------------------------------------------------------------------------------------------------ lens streak, rays
## The horizontal anamorphic streak across a flash (Download(9) 0:52.5, 1:29.6, 2:58): a long thin needle laid across
## the camera, growing in 1-2 frames and gone in 4-6.
func lens_streak(at: Vector3, who: String, length := 3.0, dur := 0.18) -> void:
	stats.streaks += 1
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var right := cam.global_transform.basis.x.normalized()
	for sgn in [1.0, -1.0]:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.02
		cm.height = length * 0.5
		cm.radial_segments = 6
		cm.rings = 0
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		var gm := ShaderMaterial.new()
		gm.shader = vfx._glint_sh
		gm.set_shader_parameter("col", _col(who, "core").lerp(_col(who, "edge"), 0.35))
		gm.set_shader_parameter("energy", 4.0)
		mi.material_override = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var y: Vector3 = right * sgn
		var x := y.cross(cam.global_transform.basis.z).normalized()
		mi.global_transform = Transform3D(Basis(x, y, x.cross(y)), at + y * length * 0.25)
		mi.scale = Vector3(1, 0.2, 1)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(1, 1, 1), dur * 0.2)
		tw.parallel().tween_method(func(v: float): gm.set_shader_parameter("fade", v), 1.0, 0.0, dur).set_delay(dur * 0.15)
		tw.tween_callback(mi.queue_free)


## Long radial rays bursting from a point (the spikes of a light explosion), 2 frames in, 5 out.
func rays(at: Vector3, who: String, n := 14, length := 1.6, dur := 0.25) -> void:
	vfx._glints(at, Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)).normalized(), who, n, length)
	vfx._glints(at, Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)).normalized(), who, n / 2, length * 0.6)


## A thin ring of light racing outward (a shock ring), in the plane with normal nrm.
func shock_ring(at: Vector3, nrm: Vector3, who: String, radius := 2.0, dur := 0.35) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = svfx.sector(0.92, 1.0, 360.0, 64)
	var m := svfx.smear_mat(who, 3.0)
	m.set_shader_parameter("head", 1.0)
	m.set_shader_parameter("tail", 1.0)
	m.set_shader_parameter("rim", 0.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var y := nrm.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x, y, x.cross(y)), at)
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------------------------------------ sigil
## A rune sigil at `at` facing `nrm` (or following callables): wiped in from the centre over `grow`, turning, held,
## faded. Returns the node.
func sigil(at, nrm, who: String, radius := 0.45, dur := 0.8, grow := 0.12, pts := 6.0) -> MeshInstance3D:
	stats.sigils += 1
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := _mat("sigil", who, 3.2)
	m.set_shader_parameter("reveal", 0.0)
	m.set_shader_parameter("points", pts)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var place := func():
		var p: Vector3 = at.call() if at is Callable else at
		var nn: Vector3 = nrm.call() if nrm is Callable else nrm
		var y := nn.normalized()
		var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		mi.global_transform = Transform3D(Basis(x, y, x.cross(y)), p)
	place.call()
	if at is Callable or nrm is Callable:
		_follow.append([mi, place])
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("reveal", v), 0.0, 1.0, grow).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("spin", v), 0.0, 3.0 * dur, dur)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.35).set_delay(dur * 0.65)
	tw.tween_callback(mi.queue_free)
	return mi


# ------------------------------------------------------------------------------------------------ billow
## A light explosion: overlapping soft billows swelling out (ease-out) and thinning, long rays, a shock ring, a lens
## streak, a flash of light, and a cloud of motes thrown out to drift and twinkle down.
func billow(at: Vector3, who: String, radius := 1.0, dur := 0.6, motes_n := 160) -> void:
	stats.billows += 1
	for i in 6:
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 20
		sm.rings = 10
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		var m := _mat("soft_puff", who, 1.1 if i > 0 else 1.7)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var off := Vector3(randf_range(-1, 1), randf_range(-0.4, 1), randf_range(-1, 1)).normalized() * radius * (0.0 if i == 0 else randf_range(0.2, 0.45))
		mi.global_position = at + off
		mi.scale = Vector3.ONE * radius * 0.15
		var target := radius * (0.7 if i == 0 else randf_range(0.45, 0.65))
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3.ONE * target, dur * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(mi, "global_position", at + off * 1.6 + Vector3.UP * radius * 0.15, dur)
		tw.parallel().tween_method(func(v: float): m.set_shader_parameter("life", v), 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	rays(at, who, 16, radius * 1.6, dur * 0.4)
	shock_ring(at, Vector3.UP, who, radius * 2.4, dur * 0.6)
	lens_streak(at, who, radius * 5.0, 0.2)
	vfx._light(at, _col(who, "core"), 4.0, dur * 0.7)
	motes(at, who, motes_n, 1.6, radius * 0.5, "burst", radius * 2.5)


# ------------------------------------------------------------------------------------------------ volley
## A fan of shaped blades (Mika: star daggers - thin crystals; Luna: small crescents) bursting out of a sigil over her
## raised hand, spreading into an arc behind her shoulders (`anchor` = her feet, k = her scale; 0.13 s, ease-out), hovering and bobbing with her and turning
## to face the target, then launching one after another (`stagger`) along curved paths. on_hit(i, pos) per blade.
func volley(sigil_at: Callable, anchor: Callable, facing: Callable, who: String, n: int, hold: float, target: Callable,
		on_hit: Callable, speed := 26.0, stagger := 0.04, k := 1.0) -> void:
	stats.volleys += 1
	var start: Vector3 = sigil_at.call()
	sigil(sigil_at, func() -> Vector3: return (facing.call() as Vector3) * -1.0, who, 0.35, 0.5, 0.1)
	vfx._light(start, _col(who, "core"), 2.0, 0.3)
	var blades := []
	for i in n:
		var mesh: Mesh = svfx.crystal(0.5, 0.045, 4, 0.3) if who != "luna" else svfx.crescent_mesh(0.22, 0.05, 140.0)
		var mi := svfx.body(mesh, who, 3.4)
		# a soft halo round each blade (it glows into the air, Download(9) 0:01)
		var halo := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.16
		hs.height = 0.32
		hs.radial_segments = 12
		hs.rings = 6
		halo.mesh = hs
		var hm := _mat("soft_puff", who, 0.6)
		hm.set_shader_parameter("life", 0.25)
		halo.material_override = hm
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(halo)
		halo.position = Vector3(0, 0.22, 0)
		mi.global_position = start
		var u := float(i) / maxf(n - 1, 1)
		var ang := lerpf(-1.25, 1.25, u)
		var h := {"mi": mi, "ang": ang, "t": 0.0, "phase": randf() * TAU, "state": "form", "slot": Vector3.ZERO, "trail": {}}
		blades.append(h)
		motes(func() -> Vector3: return mi.global_position if is_instance_valid(mi) else Vector3.INF, who, 10, 0.5, 0.05, "drift")
	var fan_light := OmniLight3D.new()
	fan_light.light_color = _col(who, "edge").lightened(0.3)
	fan_light.light_energy = 0.5
	fan_light.omni_range = 2.0
	fan_light.shadow_enabled = false
	add_child(fan_light)
	_follow.append([fan_light, func() -> Vector3: return (anchor.call() as Vector3) + Vector3.UP * 1.6 * k + (facing.call() as Vector3) * 0.9])
	get_tree().create_timer(hold + 0.6, true, false, false).timeout.connect(fan_light.queue_free)
	var data := {"blades": blades, "anchor": anchor, "facing": facing, "target": target, "t": 0.0, "hold": hold, "n": n, "k": k,
		"on_hit": on_hit, "speed": speed, "stagger": stagger, "who": who}
	_volleys.append(data)


var _volleys: Array = []


func _volley_step(v: Dictionary, delta: float) -> bool:
	v.t = float(v.t) + delta
	var anchor: Vector3 = (v.anchor as Callable).call()
	var fwd: Vector3 = (v.facing as Callable).call()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var alive := false
	for i in (v.blades as Array).size():
		var b: Dictionary = v.blades[i]
		if not is_instance_valid(b.mi):
			continue
		var mi: MeshInstance3D = b.mi
		alive = true
		b.t = float(b.t) + delta
		# its place in the fan: an arc behind / above her shoulders
		var slot := anchor + Vector3.UP * (1.3 * float(v.k) + 0.4 * cos(float(b.ang))) + right * sin(float(b.ang)) * 1.1 - fwd * 0.35
		slot += Vector3.UP * sin(float(b.phase) + float(v.t) * 5.0) * 0.03            # (hovering: a gentle bob)
		var launch_at := float(v.hold) + float(v.stagger) * i
		if String(b.state) == "form":
			var u := clampf(float(b.t) / 0.13, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - u, 3.0)
			mi.global_position = (mi.global_position as Vector3).lerp(slot, e if u < 1.0 else 1.0)
			_aim(mi, (v.target as Callable).call() - mi.global_position)
			if u >= 1.0:
				b.state = "hover"
		elif String(b.state) == "hover":
			mi.global_position = (mi.global_position as Vector3).lerp(slot, minf(delta * 14.0, 1.0))
			_aim(mi, (v.target as Callable).call() - mi.global_position)
			if float(v.t) >= launch_at:
				b.state = "fly"
				b.from = mi.global_position
				b.to = (v.target as Callable).call() + Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.2), randf_range(-0.15, 0.15))
				b.ft = 0.0
				b.dur = (b.from as Vector3).distance_to(b.to) / float(v.speed)
				b.bend = (Vector3.UP * randf_range(0.2, 0.6) + right * randf_range(-0.6, 0.6))
				var bs := b
				b.trail = vfx.trail(func() -> Array:
					var p: Vector3 = bs.mi.global_position if is_instance_valid(bs.mi) else Vector3.ZERO
					var dv: Vector3 = bs.get("dir", Vector3.UP)
					var side := dv.cross(Vector3.UP).normalized() * 0.025
					return [p - side, p + side], String(v.who), float(b.dur) + 0.02, 3.2, 1.0)
				b.trail.hist_max = 10
		elif String(b.state) == "fly":
			b.ft = float(b.ft) + delta
			var u2 := clampf(float(b.ft) / maxf(float(b.dur), 0.01), 0.0, 1.0)
			var a: Vector3 = b.from
			var c: Vector3 = b.to
			var mid := (a + c) * 0.5 + (b.bend as Vector3)
			var p := a.lerp(mid, u2).lerp(mid.lerp(c, u2), u2)
			var dv := p - mi.global_position
			if dv.length() > 0.0001:
				b.dir = dv.normalized()
				_aim(mi, dv)
			mi.global_position = p
			if u2 >= 1.0:
				(v.on_hit as Callable).call(i, p)
				mi.queue_free()
	return alive


func _aim(mi: Node3D, dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x, y, x.cross(y)), mi.global_position)


# ------------------------------------------------------------------------------------------------ moon
## Luna's moon (Download(9) 1:27-1:30): a moon grows out of her raised hand (0.3 s), haloed by a turning ring of
## light, soft wisps and a hanging cloud of twinkling motes; flown at the target it bursts into a white billow. Returns
## a handle; call moon_fly(h, to, dur, on_arrive).
func moon(center: Callable, who: String, radius := 0.45) -> Dictionary:
	stats.moons += 1
	var root := Node3D.new()
	add_child(root)
	root.global_position = center.call()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	var body := MeshInstance3D.new()
	body.mesh = sm
	var m := _mat("moon", who, 1.8)
	m.set_shader_parameter("dissolve", 1.0)
	body.material_override = m
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	body.scale = Vector3.ONE * radius * 0.1
	var ring_pivot := Node3D.new()
	root.add_child(ring_pivot)
	ring_pivot.basis = Basis(Vector3(1, 0, 0.3).normalized(), 0.45)
	var ring := MeshInstance3D.new()
	ring.mesh = svfx.sector(0.86, 1.0, 360.0, 96)
	var rm := svfx.smear_mat(who, 2.8)
	rm.set_shader_parameter("head", 1.0)
	rm.set_shader_parameter("tail", 1.0)
	rm.set_shader_parameter("rim", 0.35)
	rm.set_shader_parameter("fade", 0.0)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_pivot.add_child(ring)
	ring.scale = Vector3.ONE * radius * 2.2
	var tw := root.create_tween()
	tw.tween_property(body, "scale", Vector3.ONE * radius, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("dissolve", v), 1.0, 0.0, 0.3)
	tw.parallel().tween_method(func(v: float): rm.set_shader_parameter("fade", v), 0.0, 1.0, 0.25).set_delay(0.15)
	var w := wisps(func() -> Vector3: return root.global_position if is_instance_valid(root) else Vector3.INF, who, radius * 2.6, 3.0, 4, 3.0)
	var mt := motes(func() -> Vector3: return root.global_position if is_instance_valid(root) else Vector3.INF, who, 140, 1.4, radius * 2.0, "swirl")
	var h := {"root": root, "body": body, "ring": ring_pivot, "follow": center, "flying": false, "wisps": w, "motes": mt, "who": who, "r": radius}
	_moons.append(h)
	return h


var _moons: Array = []


func moon_fly(h: Dictionary, to: Vector3, dur: float, on_arrive: Callable) -> void:
	h.flying = true
	h.from = (h.root as Node3D).global_position
	h.to = to
	h.ft = 0.0
	h.fdur = dur
	h.on_arrive = on_arrive


func _moon_step(h: Dictionary, delta: float) -> bool:
	if not is_instance_valid(h.root):
		return false
	var root: Node3D = h.root
	(h.ring as Node3D).rotate_object_local(Vector3.UP, delta * 4.0)
	(h.body as Node3D).rotate_object_local(Vector3.UP, delta * 0.6)
	if not h.flying:
		root.global_position = root.global_position.lerp((h.follow as Callable).call(), minf(delta * 12.0, 1.0))
		return true
	h.ft = float(h.ft) + delta
	var u := clampf(float(h.ft) / float(h.fdur), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	root.global_position = (h.from as Vector3).lerp(h.to, e)
	if u >= 1.0:
		billow(root.global_position, String(h.who), float(h.r) * 3.0, 0.9, 220)
		if (h.on_arrive as Callable).is_valid():
			(h.on_arrive as Callable).call(root.global_position)
		stop(h.motes, 1.4)
		root.queue_free()
		return false
	return true


# ------------------------------------------------------------------------------------------------ light blade
## A blade of light extending from a weapon for `dur` s (Download(9) 0:52.0-0.4): a bright core along base -> tip with
## a soft sheath, feathered glints streaming off it, a lens streak where it starts.
func light_blade(base: Callable, tip: Callable, who: String, dur := 0.5, width := 1.0) -> void:
	var h := svfx.beam(base, tip, who, dur, 0.6 * width)
	lens_streak(base.call(), who, 2.2, 0.18)
	motes(tip, who, 40, 0.5, 0.15, "drift")


func _process(delta: float) -> void:
	var keep := []
	for f in _follow:
		if not is_instance_valid(f[0]):
			continue
		var n: Node3D = f[0]
		var src = f[1]
		if src is Callable:
			var r = (src as Callable).call()
			if r is Vector3:
				if r == Vector3.INF:
					# its source is gone: an emitter stops and lingers out, anything else is let go
					if n is GPUParticles3D:
						stop(n, 1.2)
					continue
				n.global_position = r
		keep.append(f)
	_follow = keep
	var kv := []
	for v in _volleys:
		if _volley_step(v, delta):
			kv.append(v)
	_volleys = kv
	var km := []
	for h in _moons:
		if _moon_step(h, delta):
			km.append(h)
	_moons = km
