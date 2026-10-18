class_name DanceFX
extends Node3D
## Real 3D dance effects attached to her body (2026-10-19; Selwyn rejected the flat overlays, then gave three target
## frames: T1 spin, T2 pose, T3 finale). GPUParticles3D, light ribbons and the Brackeys CC0 particle textures, all HDR
## and additive so the bloom makes them shine; no screen wash, no blur:
##  - light ribbons behind both hands and the dress hem, and spiral() - ribbons coiling round her through a spin, each
##    shedding sparkle dust;
##  - arc(): one gold arc following a raised arm, with star glints at the hand;
##  - warm motes, violet glints and petals drifting round her all the time;
##  - rings(): glowing ripple rings on the lake under her feet (each touchdown, and while she spins or stands);
##  - finale(): a ring of star dust and light rays bursting outward, a glowing water splash crown round her feet, and
##    the stage's lanterns lifting and brightening.
## Bone positions come from a probe modifier at the end of her skeleton's stack, so they include the held poses and
## the dress simulation.

const TEX := "res://assets/vfx/brackeys/particles/alpha/"
const VIOLET := Color(0.7, 0.5, 1.0)
const GOLD := Color(1.0, 0.76, 0.4)
const ICE := Color(0.62, 0.84, 1.0)
const PETAL := Color(1.0, 0.62, 0.78)

var c: WorldCharacter
var water_y := -INF
var stage: DanceStage
var spin_dir := 1.0                     # +1 = her yaw increasing
var ripple_every := 0.0                 # seconds between rings under her standing foot (0 = off)
var ring_colors := [GOLD, VIOLET]
var ambient := true                     # the motes, glints and petals (one dancer carries them in a duet)
var level := 0.5                        # how much is going on (the music's energy): 0.2 a quiet verse .. 1.2 a chorus
var ring_scale := 1.0                   # ripple size (smaller in a duet, so the two sets don't tile the lake)
var _aura: Array = []                   # the light ribbons that coil round her the whole dance
var _ambient_nodes: Array = []
var _probe: DanceProbe
var _trails: Array = []                 # {src, hist, im, mat, w, len, live, temp}
var _hands := {}                        # bone -> {trail, dust, prev}
var _hem: Array = []
var _spirals: Array = []                # {t0, dur, phase, r, hf, trail, dust}
var _feet := {}
var _since_ring := 0.0
var _now := 0.0


class DanceProbe extends SkeletonModifier3D:
	var names: Array = []
	var pos := {}
	var _ids: Array = []

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		if _ids.is_empty():
			for n in names:
				_ids.append(sk.find_bone(n))
		var g := sk.global_transform
		for i in _ids.size():
			if int(_ids[i]) >= 0:
				pos[names[i]] = g * sk.get_bone_global_pose(int(_ids[i])).origin


static func attach(ch: WorldCharacter, water := -INF, stage_node: DanceStage = null, ambient := true) -> DanceFX:
	var d := DanceFX.new()
	d.name = "DanceFX"
	d.c = ch
	d.water_y = water
	d.stage = stage_node
	d.ambient = ambient
	ch.get_parent().add_child(d)
	d._build()
	return d


func bone(n: String) -> Vector3:
	if _probe and _probe.pos.has(n):
		return _probe.pos[n]
	var sk := c.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n)).origin


func _tex_mat(tex: String, col: Color, energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/dance/glow_sprite.gdshader")
	m.set_shader_parameter("tex", load(TEX + tex))
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	return m


func _quad(size: Vector2, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	return q


func _fade_ramp(a := 0.1, b := 0.6) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, a, b, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _shrink_curve() -> CurveTexture:
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(1, 0.25))
	var ct := CurveTexture.new()
	ct.curve = cv
	return ct


func _particles(amount: int, life: float, pm: ParticleProcessMaterial, mesh: Mesh, one_shot := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.one_shot = one_shot
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	if one_shot:
		p.explosiveness = 0.9
		p.emitting = true
		get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)
	return p


func _trail(src: Callable, glow: Color, w: float, length: int, core := Color(1.0, 0.94, 0.82), energy := 3.0) -> Dictionary:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/dance/ribbon.gdshader")
	m.set_shader_parameter("color", glow)
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("energy", energy)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.extra_cull_margin = 16.0
	add_child(mi)
	var t := {"src": src, "hist": PackedVector3Array(), "mi": mi, "im": im, "mat": m, "w": w, "len": length, "live": true, "temp": false, "arc": false}
	_trails.append(t)
	return t


## Sparkle dust shed along a moving point (a spiral head, a hand): it lingers where the ribbon passed.
func _dust(col: Color, amount := 90) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.gravity = Vector3(0, -0.12, 0)
	pm.scale_min = 0.35
	pm.scale_max = 1.2
	pm.color_ramp = _fade_ramp(0.05, 0.5)
	pm.scale_curve = _shrink_curve()
	return _particles(amount, 1.3, pm, _quad(Vector2(0.04, 0.04), _tex_mat("star_04_a.png", col.lerp(Color.WHITE, 0.35), 3.0)))


func _build() -> void:
	var sk := c.skeleton
	_probe = DanceProbe.new()
	_probe.name = "DanceProbe"
	_probe.names = ["Hips", "Chest", "Head", "RightHand", "LeftHand", "LeftToes", "RightToes", "LeftFoot", "RightFoot",
		"J_Sec_Skirt06_7", "J_Sec_Skirt09_7"]
	sk.add_child(_probe)                  # last: after the poses, the dress sim and the drape
	# hands: a ribbon and its dust each
	for hb in ["RightHand", "LeftHand"]:
		if sk.find_bone(hb) < 0:
			continue
		var t := _trail(bone.bind(hb), VIOLET, 0.032, 24, Color(1.0, 0.94, 0.82), 2.0)
		var d := _dust(VIOLET, 70)
		d.amount_ratio = 0.0
		_hands[hb] = {"trail": t, "dust": d, "prev": Vector3.INF, "vis": 0.0}
	# the hem: two long back panels' tips, only through spins
	for hb in ["J_Sec_Skirt06_7", "J_Sec_Skirt09_7"]:
		if sk.find_bone(hb) >= 0:
			var t := _trail(bone.bind(hb), VIOLET.lerp(GOLD, 0.3), 0.026, 18, Color(1.0, 0.94, 0.82), 1.8)
			t.live = false
			_hem.append(t)
	# always on: warm bokeh motes, small violet glints, petals - round her and across the frame
	if not ambient:
		print("[dancefx] %d ribbons, dust (no ambient)" % _trails.size())
		return
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.6, 1.6, 1.6)
	pm.emission_shape_offset = Vector3(0, 0, -0.8)
	pm.gravity = Vector3(0, 0.05, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.1
	pm.spread = 180.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.color_ramp = _fade_ramp(0.2, 0.75)
	var motes := _particles(110, 6.0, pm, _quad(Vector2(0.09, 0.09), _tex_mat("flare_01_a.png", GOLD, 2.4)))
	motes.preprocess = 6.0
	motes.name = "Motes"
	var pg := pm.duplicate() as ParticleProcessMaterial
	pg.emission_box_extents = Vector3(2.2, 1.3, 1.8)
	pg.scale_min = 0.4
	pg.scale_max = 1.0
	var glints := _particles(70, 3.0, pg, _quad(Vector2(0.05, 0.05), _tex_mat("star_04_a.png", VIOLET.lerp(Color.WHITE, 0.3), 2.6)))
	glints.preprocess = 3.0
	glints.name = "Glints"
	var pp := ParticleProcessMaterial.new()
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pp.emission_box_extents = Vector3(3.4, 1.4, 1.3)
	pp.emission_shape_offset = Vector3(0, 0, -0.9)     # (kept back from the lens: no big flat petals in its face)
	pp.gravity = Vector3(0, -0.1, 0)
	pp.initial_velocity_min = 0.05
	pp.initial_velocity_max = 0.22
	pp.direction = Vector3(1, 0, 0)
	pp.spread = 60.0
	pp.angular_velocity_min = -80.0
	pp.angular_velocity_max = 80.0
	pp.angle_min = -180.0
	pp.angle_max = 180.0
	pp.turbulence_enabled = true
	pp.turbulence_noise_strength = 0.5
	pp.color_ramp = _fade_ramp(0.15, 0.8)
	pp.scale_min = 0.7
	pp.scale_max = 1.3
	var petal_m := ShaderMaterial.new()
	petal_m.shader = load("res://shaders/anime/dance/petal.gdshader")
	petal_m.set_shader_parameter("color", PETAL)
	petal_m.set_shader_parameter("glow", 1.0)
	var petals := _particles(60, 8.0, pp, _quad(Vector2(0.075, 0.075), petal_m))
	petals.preprocess = 8.0
	petals.name = "Petals"
	for p in [motes, glints, petals]:
		p.set_meta("follow", true)
	_ambient_nodes = [motes, glints, petals]
	print("[dancefx] %d ribbons, dust, motes, glints, petals" % _trails.size())


## Ribbons coiling round her through a spin (T1): `n` heads orbit her at waist-to-shoulder heights, turning with her
## and a little faster, each drawing a long light ribbon and shedding sparkle dust; the hem ribbons join in.
func spiral(dur: float, n := 3, radius := 0.62) -> void:
	for k in n:
		var s := {"t0": _now, "dur": dur, "phase": TAU * k / n, "r": radius * randf_range(0.85, 1.12), "hf": randf_range(2.6, 3.4),
			"lo": [0.35, 0.6, 0.9][k % 3], "hi": [1.15, 1.5, 0.5][k % 3]}
		var col: Color = [GOLD, VIOLET, GOLD.lerp(VIOLET, 0.5)][k % 3]
		s["trail"] = _trail(_spiral_point.bind(s), col, 0.034, 40, Color(1.0, 0.95, 0.85), 2.1)
		s["dust"] = _dust(col, 120)
		_spirals.append(s)
	for t in _hem:
		t.live = true
	get_tree().create_timer(dur).timeout.connect(func():
		for t in _hem:
			t.live = false)


## The light ribbons that coil round her through the whole dance (n of them): slow and faint in a verse, fast and
## bright on a chorus (level).
func aura(n := 2) -> void:
	for k in n:
		var s := {"t0": _now, "dur": 1.0e9, "phase": TAU * k / n + 0.7, "r": 0.58 + 0.08 * k, "hf": 1.3 + 0.5 * k,
			"lo": [0.45, 0.85][k % 2], "hi": [1.3, 0.35][k % 2], "aura": true, "ang": 0.0}
		var col: Color = [VIOLET, GOLD][k % 2]
		s["trail"] = _trail(_spiral_point.bind(s), col, 0.03, 34, Color(1.0, 0.95, 0.85), 2.0)
		s["dust"] = _dust(col, 90)
		_aura.append(s)


func set_level(v: float) -> void:
	level = v
	for n in _ambient_nodes:
		(n as GPUParticles3D).amount_ratio = clampf(0.45 + 0.55 * v, 0.2, 1.0)
	for s in _aura:
		((s.trail as Dictionary).mat as ShaderMaterial).set_shader_parameter("fade_all", clampf(0.25 + 0.75 * v, 0.15, 1.3))
		(s.dust as GPUParticles3D).amount_ratio = clampf(0.15 + 0.85 * v, 0.1, 1.0)


func _spiral_point(s: Dictionary) -> Vector3:
	var t := _now - float(s.t0)
	var grow := smoothstep(0.0, 0.5, t) * (1.0 - 0.35 * smoothstep(float(s.dur) - 0.6, float(s.dur), t))
	if s.has("aura"):
		s.ang = float(s.ang) + spin_dir * get_process_delta_time() * lerpf(1.6, 6.0, clampf(level, 0.0, 1.2) / 1.2)
		var ra := float(s.r) * (1.0 + 0.1 * sin(t * 1.7 + float(s.phase)))
		var ha := lerpf(float(s.lo), float(s.hi), 0.5 + 0.5 * sin(t * float(s.hf) + float(s.phase)))
		var aa := float(s.phase) + float(s.ang)
		return c.global_position + Vector3(cos(aa) * ra, ha, -sin(aa) * ra)
	var a := float(s.phase) + spin_dir * t * 7.2
	var r := float(s.r) * (0.35 + 0.65 * grow) * (1.0 + 0.12 * sin(t * 2.1 + float(s.phase)))
	var h := lerpf(float(s.lo), float(s.hi), 0.5 + 0.5 * sin(t * float(s.hf) + float(s.phase)))
	return c.global_position + Vector3(cos(a) * r, h, -sin(a) * r)


## One gold arc following the raised arm (T2): that hand's ribbon turns gold, long and wide while the arm sweeps up,
## then star glints twinkle at the fingertips.
func arc(hand := "RightHand", dur := 1.4) -> void:
	if not _hands.has(hand):
		return
	var t: Dictionary = _hands[hand].trail
	t.len = 46
	t.w = 0.045
	t.arc = true
	(t.mat as ShaderMaterial).set_shader_parameter("color", GOLD)
	(t.mat as ShaderMaterial).set_shader_parameter("energy", 2.4)
	get_tree().create_timer(dur).timeout.connect(func():
		t.len = 24
		t.w = 0.032
		t.arc = false
		(t.mat as ShaderMaterial).set_shader_parameter("color", VIOLET)
		(t.mat as ShaderMaterial).set_shader_parameter("energy", 2.0))
	get_tree().create_timer(dur * 0.6).timeout.connect(twinkle.bind(hand))


## A few four-point star glints round a hand, drifting a little and fading.
func twinkle(hand := "RightHand") -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.16
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.gravity = Vector3(0, -0.15, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = _fade_ramp(0.08, 0.55)
	var p := _particles(9, 1.8, pm, _quad(Vector2(0.16, 0.16), _tex_mat("star_07_a.png", GOLD.lerp(Color.WHITE, 0.3), 6.0)), true)
	p.explosiveness = 0.55
	p.global_position = bone(hand)


## Glowing ripple rings on the water at p: `n` rings staggered, each widening to `size` m and fading.
func rings(p: Vector3, size := 1.2, n := 3, cols: Array = []) -> void:
	if water_y == -INF:
		return
	var use: Array = cols if not cols.is_empty() else ring_colors
	for i in n:
		get_tree().create_timer(i * 0.2).timeout.connect(_one_ring.bind(p, size * (1.0 - i * 0.12), use[i % use.size()]))
	# a few droplets and glints thrown up where the foot met the water
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.12
	pm.emission_ring_inner_radius = 0.05
	pm.emission_ring_height = 0.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0, -4.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _fade_ramp(0.05, 0.6)
	var s := _particles(int(12 * size), 0.8, pm, _quad(Vector2(0.04, 0.04), _tex_mat("star_04_a.png", ICE.lerp(Color.WHITE, 0.4), 3.0)), true)
	s.global_position = Vector3(p.x, water_y + 0.02, p.z)


func _one_ring(p: Vector3, size: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(2.0, 2.0) * size
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/anime/dance/ripple.gdshader")
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", 1.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(p.x, water_y + 0.012, p.z)
	var tw := create_tween()
	tw.tween_method(func(v): m.set_shader_parameter("t", v), 0.0, 1.0, 2.2)
	tw.tween_callback(mi.queue_free)


## Points round a ring (axes a, b; radius r0..r1) with outward normals tipped by `lift` toward `up` - for the
## directed-point emitters (the burst ring, the splash crown).
func _ring_tex(n: int, r0: float, r1: float, a: Vector3, b: Vector3, lift := 0.0, up := Vector3.UP, jitter := 0.0) -> Array:
	var ip := Image.create(n, 1, false, Image.FORMAT_RGBF)
	var inn := Image.create(n, 1, false, Image.FORMAT_RGBF)
	for i in n:
		var ang := TAU * (i + randf() * 0.8) / n
		var d := a * cos(ang) + b * sin(ang)
		var p := d * randf_range(r0, r1)
		var nn := (d + up * (lift + randf_range(-jitter, jitter))).normalized()
		ip.set_pixel(i, 0, Color(p.x, p.y, p.z))
		inn.set_pixel(i, 0, Color(nn.x, nn.y, nn.z))
	return [ImageTexture.create_from_image(ip), ImageTexture.create_from_image(inn)]


func _directed(tex: Array, n: int, vmin: float, vmax: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
	pm.emission_point_texture = tex[0]
	pm.emission_normal_texture = tex[1]
	pm.emission_point_count = n
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 6.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3.ZERO
	return pm


## A small sparkle burst round her chest (the end of a spin, a pose).
func burst(size := 1.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var p := bone("Chest")
	var fwd := (cam.global_position - p).normalized() if cam else Vector3.BACK
	var a := fwd.cross(Vector3.UP).normalized()
	var b := a.cross(fwd).normalized()
	var tx := _ring_tex(64, 0.15, 0.3, a, b, 0.0, fwd, 0.3)
	var pm := _directed(tx, 64, 1.2 * size, 2.6 * size)
	pm.damping_min = 2.0
	pm.damping_max = 3.5
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = _fade_ramp(0.05, 0.5)
	pm.scale_curve = _shrink_curve()
	var s := _particles(int(26 * size), 1.4, pm, _quad(Vector2(0.14, 0.14), _tex_mat("star_07_a.png", GOLD.lerp(Color.WHITE, 0.25), 4.0)), true)
	s.global_position = p
	var d := _particles(int(70 * size), 1.6, pm, _quad(Vector2(0.035, 0.035), _tex_mat("flare_01_a.png", VIOLET.lerp(Color.WHITE, 0.3), 3.5)), true)
	d.global_position = p
	_flash(p, GOLD.lerp(VIOLET, 0.4), 1.2 * size, 0.8)
	if stage:
		stage.flare(0.6 * size)


func _flash(p: Vector3, col: Color, energy: float, dur: float) -> void:
	var l := OmniLight3D.new()
	add_child(l)
	l.global_position = p
	l.light_color = col
	l.omni_range = 5.0
	l.light_energy = energy
	l.shadow_enabled = false
	var tl := create_tween()
	tl.tween_property(l, "light_energy", 0.0, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tl.tween_callback(l.queue_free)


## The finale (T3): star dust and light rays burst outward in a ring round her, a glowing water splash crown rises
## round her feet in two waves, rings race out over the lake, and every lantern lifts and brightens.
func finale() -> void:
	var cam := get_viewport().get_camera_3d()
	var p := bone("Chest") + Vector3(0, 0.15, 0)
	var fwd := (cam.global_position - p) if cam else Vector3.BACK
	fwd.y = 0.0
	fwd = fwd.normalized()
	var a := fwd.cross(Vector3.UP).normalized()
	var b := Vector3.UP
	# rays: long gold and ice streaks flying out in the picture plane
	for spec in [[GOLD, 56, 5.0, 9.5, 0.95], [ICE, 30, 4.0, 8.0, 0.75]]:
		var tx := _ring_tex(int(spec[1]), 0.35, 0.6, a, b, 0.0, fwd, 0.15)
		var pm := _directed(tx, int(spec[1]), float(spec[2]), float(spec[3]))
		pm.damping_min = 5.0
		pm.damping_max = 7.0
		pm.color_ramp = _fade_ramp(0.03, 0.45)
		pm.scale_curve = _shrink_curve()
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/anime/dance/streak.gdshader")
		sm.set_shader_parameter("color", spec[0])
		sm.set_shader_parameter("energy", 3.2)
		var r := _particles(int(spec[1]), 1.2, pm, _quad(Vector2(0.05, float(spec[4])), sm), true)
		r.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		r.explosiveness = 0.97
		r.global_position = p
	# stars: big four-point gold and ice stars thrown out to a wide ring
	for spec in [["star_07_a.png", GOLD, 40, 0.26], ["star_06_a.png", ICE, 26, 0.22]]:
		var tx := _ring_tex(int(spec[2]), 0.3, 0.6, a, b, 0.0, fwd, 0.2)
		var pm := _directed(tx, int(spec[2]), 2.4, 5.0)
		pm.damping_min = 3.0
		pm.damping_max = 4.5
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		pm.color_ramp = _fade_ramp(0.04, 0.6)
		pm.scale_curve = _shrink_curve()
		var s := _particles(int(spec[2]), 2.0, pm, _quad(Vector2(spec[3], spec[3]), _tex_mat(String(spec[0]), (spec[1] as Color).lerp(Color.WHITE, 0.3), 4.5)), true)
		s.global_position = p
	# the gold dust halo: a ring of fine glittering dust that drifts slowly outward and hangs round her
	var hx := _ring_tex(400, 0.8, 1.3, a, b, 0.0, fwd, 0.1)
	var hp := _directed(hx, 400, 0.1, 0.7)
	hp.damping_min = 0.3
	hp.damping_max = 0.8
	hp.gravity = Vector3(0, -0.05, 0)
	hp.scale_min = 0.4
	hp.scale_max = 1.2
	hp.color_ramp = _fade_ramp(0.06, 0.65)
	var halo := _particles(400, 2.8, hp, _quad(Vector2(0.035, 0.035), _tex_mat("flare_01_a.png", GOLD.lerp(Color.WHITE, 0.2), 3.5)), true)
	halo.explosiveness = 0.7
	halo.global_position = p
	# the splash crown at her feet, two waves
	var feet := (bone("LeftToes") + bone("RightToes")) * 0.5
	feet.y = water_y if water_y != -INF else feet.y
	_splash(feet, 1.0)
	get_tree().create_timer(0.35).timeout.connect(_splash.bind(feet, 0.75))
	rings(feet, 2.4, 3, [GOLD, ICE, VIOLET])
	get_tree().create_timer(0.6).timeout.connect(rings.bind(feet, 3.4, 2, [ICE, GOLD]))
	_flash(p, GOLD, 2.6, 1.4)
	_flash(feet + Vector3(0, 0.4, 0), ICE, 1.0, 1.2)
	if stage:
		stage.lift()


func _splash(at: Vector3, k: float) -> void:
	var tx := _ring_tex(160, 0.3, 0.6, Vector3.RIGHT, Vector3.BACK, 1.9, Vector3.UP, 0.6)
	for spec in [[ICE.lerp(Color.WHITE, 0.2), int(200 * k), 0.06, 0.24, 2.2], [GOLD, int(80 * k), 0.05, 0.2, 2.2]]:
		var pm := _directed(tx, 160, 2.4 * k, 4.4 * k)
		pm.gravity = Vector3(0, -7.5, 0)
		pm.damping_min = 0.4
		pm.damping_max = 1.0
		pm.color_ramp = _fade_ramp(0.03, 0.55)
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/anime/dance/streak.gdshader")
		sm.set_shader_parameter("color", spec[0])
		sm.set_shader_parameter("energy", float(spec[4]))
		var s := _particles(int(spec[1]), 1.0, pm, _quad(Vector2(spec[2], spec[3]), sm), true)
		s.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		s.explosiveness = 0.85
		s.global_position = at
	# soft water blobs and glints in the crown
	var pm2 := _directed(tx, 160, 1.4 * k, 3.4 * k)
	pm2.gravity = Vector3(0, -7.0, 0)
	pm2.scale_min = 0.5
	pm2.scale_max = 1.4
	pm2.color_ramp = _fade_ramp(0.04, 0.5)
	var bl := _particles(int(110 * k), 0.9, pm2, _quad(Vector2(0.09, 0.09), _tex_mat("flare_01_a.png", ICE.lerp(Color.WHITE, 0.25), 1.4)), true)
	bl.global_position = at


func _process(delta: float) -> void:
	if c == null or not is_instance_valid(c):
		return
	_now += delta
	var cam := get_viewport().get_camera_3d()
	var hips := bone("Hips")
	for n in get_children():
		if n.has_meta("follow"):
			(n as Node3D).global_position = hips + Vector3(0, 0.55, 0)
		elif n.has_meta("follow_cam") and cam:
			(n as Node3D).global_position = cam.global_position - cam.global_basis.z * 1.6
	# hands: dust in proportion to how fast the hand moves
	for hb in _hands:
		var h: Dictionary = _hands[hb]
		var p := bone(hb)
		var spd := 0.0 if h.prev == Vector3.INF else (p - (h.prev as Vector3)).length() / maxf(delta, 0.001)
		h.prev = p
		(h.dust as GPUParticles3D).global_position = p
		(h.dust as GPUParticles3D).amount_ratio = maxf(clampf((spd - 0.4) / 2.5, 0.0, 1.0), 0.3 * level)
		(h.dust as GPUParticles3D).emitting = true
		var vis := maxf(clampf((spd - 0.6) / 1.6, 0.0, 1.0), clampf(0.2 + 0.5 * level, 0.0, 0.8))
		h.vis = lerpf(float(h.get("vis", 0.0)), vis, 0.12 if vis < float(h.get("vis", 0.0)) else 0.5)
		((h.trail as Dictionary).mat as ShaderMaterial).set_shader_parameter("fade_all", float(h.vis) if not (h.trail as Dictionary).get("arc", false) else 1.0)
	# spirals: their dust follows their heads; finished ones stop and let the ribbon run out
	for s in _aura:
		(s.dust as GPUParticles3D).global_position = _spiral_point(s)
	for s in _spirals.duplicate():
		var head := _spiral_point(s)
		(s.dust as GPUParticles3D).global_position = head
		if _now - float(s.t0) > float(s.dur):
			s.trail.live = false
			s.trail.temp = true
			(s.dust as GPUParticles3D).emitting = false
			get_tree().create_timer(1.5).timeout.connect((s.dust as GPUParticles3D).queue_free)
			_spirals.erase(s)
	for t in _trails.duplicate():
		_draw_trail(t, cam)
	# the lake: a ring under each foot as it touches down, and steady rings under her while she spins or stands
	if water_y != -INF:
		for fb in ["LeftToes", "RightToes"]:
			var fp := bone(fb)
			var down := fp.y - water_y < 0.07
			if down and not bool(_feet.get(fb, true)):
				rings(fp, 0.9 * ring_scale, 2)
			_feet[fb] = down
		if ripple_every > 0.0:
			_since_ring += delta
			if _since_ring >= ripple_every:
				_since_ring = 0.0
				var lo := bone("LeftToes")
				var ro := bone("RightToes")
				rings(lo if lo.y < ro.y else ro, 1.3 * ring_scale, 1)


func _draw_trail(t: Dictionary, cam: Camera3D) -> void:
	var hist: PackedVector3Array = t.hist
	if t.live:
		hist.insert(0, (t.src as Callable).call())
		if hist.size() > int(t.len):
			hist.resize(int(t.len))
	elif hist.size() > 0:
		hist.resize(maxi(0, hist.size() - 2))
	t.hist = hist
	var im: ImmediateMesh = t.im
	im.clear_surfaces()
	if hist.size() < 3 or cam == null:
		if t.temp and hist.size() == 0:
			(t.mi as Node).queue_free()
			_trails.erase(t)
		return
	# a smooth curve through the history (Catmull-Rom, 3 steps per frame) so fast turns stay round
	var pts := PackedVector3Array()
	for i in hist.size() - 1:
		var p0 := hist[maxi(i - 1, 0)]
		var p1 := hist[i]
		var p2 := hist[i + 1]
		var p3 := hist[mini(i + 2, hist.size() - 1)]
		for s in 3:
			var u := s / 3.0
			var u2 := u * u
			var u3 := u2 * u
			pts.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	pts.append(hist[hist.size() - 1])
	var full := float(int(t.len) * 3)
	var w: float = t.w
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var a := pts[i]
		var dir := (pts[i] - pts[i + 1]) if i < pts.size() - 1 else (pts[i - 1] - pts[i])
		if dir.length() < 0.00001:
			dir = Vector3.UP * 0.001
		var view := (cam.global_position - a).normalized()
		var side := dir.cross(view)
		side = side.normalized() * w if side.length() > 0.000001 else Vector3.ZERO
		var u := float(i) / full
		im.surface_set_uv(Vector2(u, 0.0))
		im.surface_add_vertex(a + side)
		im.surface_set_uv(Vector2(u, 1.0))
		im.surface_add_vertex(a - side)
	im.surface_end()


## Petals swirling round the lens (the MV): a few big soft petals just in front of the camera, circling it.
func camera_petals() -> GPUParticles3D:
	var pp := ParticleProcessMaterial.new()
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pp.emission_sphere_radius = 1.4
	pp.gravity = Vector3(0, -0.15, 0)
	pp.initial_velocity_min = 0.1
	pp.initial_velocity_max = 0.35
	pp.spread = 180.0
	pp.tangential_accel_min = 0.6
	pp.tangential_accel_max = 1.2
	pp.radial_accel_min = -0.3
	pp.radial_accel_max = -0.1
	pp.angular_velocity_min = -90.0
	pp.angular_velocity_max = 90.0
	pp.angle_min = -180.0
	pp.angle_max = 180.0
	pp.turbulence_enabled = true
	pp.turbulence_noise_strength = 0.6
	pp.color_ramp = _fade_ramp(0.15, 0.75)
	pp.scale_min = 0.7
	pp.scale_max = 1.4
	var petal_m := ShaderMaterial.new()
	petal_m.shader = load("res://shaders/anime/dance/petal.gdshader")
	petal_m.set_shader_parameter("color", PETAL)
	petal_m.set_shader_parameter("glow", 0.95)
	var p := _particles(26, 5.0, pp, _quad(Vector2(0.05, 0.05), petal_m))
	p.preprocess = 5.0
	p.set_meta("follow_cam", true)
	p.name = "CameraPetals"
	return p
