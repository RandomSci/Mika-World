class_name WorldFX
extends RefCounted
## Small real reactions of the world to the action player's contacts and spells (2026-10-20): leaves falling from a
## touched or kicked tree and the tree swaying, a flower bobbing and shedding petals, water splashing, dust off the
## ground, a glow gathering at her hand, and a visible result for each world spell (sprouts that grow, lights that
## rise, a ring of flowers, a rising stone, an ice spiral, rain, a gust of leaves, a water column, a drawn bridge of
## light, a built shape). Everything fades and frees itself. CPU particles and plain meshes (cheap on stream).


static func _particles(host: Node, at: Vector3, n: int, life: float, col: Color, size: float, vel: Vector3, spread: float, grav: Vector3, quad := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = maxi(n, 1)
	p.lifetime = life
	p.explosiveness = 0.85
	p.direction = vel.normalized() if vel.length() > 0.0 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vel.length() * 0.6
	p.initial_velocity_max = vel.length() * 1.2
	p.gravity = grav
	p.damping_min = 0.2
	p.damping_max = 0.8
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	var m: PrimitiveMesh = QuadMesh.new() if quad else SphereMesh.new()
	if quad:
		(m as QuadMesh).size = Vector2(1, 1)
	else:
		(m as SphereMesh).radius = 0.5
		(m as SphereMesh).height = 1.0
		(m as SphereMesh).radial_segments = 6
		(m as SphereMesh).rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if col.a < 0.99 or not quad else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if quad else BaseMaterial3D.BILLBOARD_DISABLED
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	host.add_child(p)
	p.global_position = at
	p.emitting = true
	host.get_tree().create_timer(life + 0.5).timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	return p


static func leaves(host: Node, crown: Vector3, n: int, spread_r: float) -> void:
	var p := _particles(host, crown, n, 3.2, Color(0.82, 0.55, 0.18), 0.09, Vector3(0, -0.4, 0), 70.0, Vector3(0, -1.1, 0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread_r
	p.explosiveness = 0.5


static func sway(n: Node3D, amp: float, dur: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	var base := n.rotation
	var tw := n.create_tween()
	tw.tween_method(func(k: float): n.rotation = base + Vector3(sin(k * TAU * 2.0) * amp * (1.0 - k), 0, cos(k * TAU * 2.0) * amp * 0.6 * (1.0 - k)), 0.0, 1.0, dur)
	tw.tween_callback(func(): n.rotation = base)


static func bob(n: Node3D, dur: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	var base := n.scale
	var tw := n.create_tween()
	tw.tween_method(func(k: float): n.scale = base * Vector3(1.0 + 0.12 * sin(k * TAU * 2.0) * (1.0 - k), 1.0 - 0.1 * sin(k * TAU * 2.0) * (1.0 - k), 1.0 + 0.12 * sin(k * TAU * 2.0) * (1.0 - k)), 0.0, 1.0, dur)
	tw.tween_callback(func(): n.scale = base)


static func petals(host: Node, at: Vector3, n: int) -> void:
	_particles(host, at, n, 2.0, Color(1.0, 0.72, 0.85), 0.04, Vector3(0, 0.8, 0), 60.0, Vector3(0, -0.6, 0))


static func splash(host: Node, at: Vector3, size: float) -> void:
	_particles(host, at, 36, 0.9, Color(0.75, 0.9, 1.0, 0.8), 0.035 * size * 2.0, Vector3(0, 2.4 * size, 0), 35.0, Vector3(0, -9.0, 0), false)
	ring(host, at + Vector3(0, 0.01, 0), Color(0.85, 0.95, 1.0, 0.7), 0.1, 0.7 * size, 0.8)


static func dust(host: Node, at: Vector3, n: int) -> void:
	_particles(host, at, n, 0.8, Color(0.7, 0.62, 0.5, 0.6), 0.06, Vector3(0, 0.5, 0), 80.0, Vector3(0, -0.5, 0))


static func ring(host: Node, at: Vector3, col: Color, r0: float, r1: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = mat
	mi.mesh = tm
	host.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3(r0, 0.3, r0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(r1, 0.3, r1), dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


## Light gathering at her hand for `dur` seconds (follows the hand).
static func glow_hand(host: Node, hand: Node3D, col: Color, dur: float) -> void:
	if hand == null:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = 1.2
	l.light_energy = 0.0
	hand.add_child(l)
	var p := _particles(host, hand.global_position, 24, 0.8, Color(col, 0.9), 0.025, Vector3(0, 0.15, 0), 180.0, Vector3.ZERO, false)
	p.one_shot = false
	p.reparent(hand)
	p.position = Vector3.ZERO
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 2.2, dur * 0.7)
	tw.tween_property(l, "light_energy", 0.0, 0.25)
	tw.tween_callback(func():
		l.queue_free()
		if is_instance_valid(p):
			p.emitting = false
			p.get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free()))


## The visible result of a world spell at `at` (the ground in front of her).
static func magic_result(host: Node, id: String, at: Vector3, col: Color) -> void:
	if id.contains("grow_plants") or id.contains("flower_ring"):
		var n := 7 if id.contains("grow") else 12
		for i in n:
			var a := TAU * float(i) / float(n)
			var r := 0.5 if id.contains("grow") else 1.1
			_sprout(host, at + Vector3(cos(a) * r * (0.4 + 0.6 * float(i % 2)), 0, sin(a) * r), Color(1.0, 0.75, 0.85) if id.contains("flower") else Color(0.45, 0.85, 0.35), float(i) * 0.12)
	elif id.contains("orbs") or id.contains("fireflies"):
		var p := _particles(host, at + Vector3(0, 1.0, 0), 60, 6.0, Color(1.0, 0.9, 0.55, 0.95), 0.05, Vector3(0, 0.6, 0), 160.0, Vector3(0, 0.05, 0), false)
		p.explosiveness = 0.3
	elif id.contains("rain"):
		var p2 := _particles(host, at + Vector3(0, 4.0, 0), 160, 1.2, Color(0.7, 0.85, 1.0, 0.7), 0.02, Vector3(0, -4.0, 0), 8.0, Vector3(0, -6.0, 0), false)
		p2.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p2.emission_box_extents = Vector3(1.6, 0.1, 1.6)
		p2.explosiveness = 0.0
	elif id.contains("wind"):
		leaves(host, at + Vector3(0, 1.0, 0), 30, 0.6)
	elif id.contains("water"):
		_column(host, at, Color(0.55, 0.8, 1.0, 0.55), 1.6, 0.35)
		splash(host, at, 0.8)
	elif id.contains("stone"):
		_rise(host, at, Color(0.55, 0.52, 0.5), 0.35, 0.9)
	elif id.contains("ice"):
		for i in 10:
			var a2 := float(i) * 0.7
			_rise(host, at + Vector3(cos(a2) * 0.05 * i, 0.15 * i, sin(a2) * 0.05 * i), Color(0.75, 0.92, 1.0, 0.85), 0.08, 0.0)
	elif id.contains("bridge"):
		_bar(host, at, col, 3.0)
	else:
		_rise(host, at + Vector3(0, 0.8, 0), Color(col, 0.8), 0.3, 0.0)
	ring(host, at + Vector3(0, 0.02, 0), Color(col, 0.6), 0.2, 1.4, 1.2)


static func _mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = Color(col.r, col.g, col.b)
	mat.emission_energy_multiplier = 0.6
	if col.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


static func _fade_free(n: Node3D, mat: StandardMaterial3D, after: float) -> void:
	var tw := n.create_tween()
	tw.tween_interval(after)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.2)
	tw.tween_callback(n.queue_free)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


static func _sprout(host: Node, at: Vector3, col: Color, delay: float) -> void:
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.012
	cm.bottom_radius = 0.018
	cm.height = 0.35
	var mat := _mat(Color(0.35, 0.7, 0.3))
	cm.material = mat
	stem.mesh = cm
	host.add_child(stem)
	stem.global_position = at + Vector3(0, 0.175, 0)
	var bloom := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.1
	var bm := _mat(col)
	sm.material = bm
	bloom.mesh = sm
	stem.add_child(bloom)
	bloom.position = Vector3(0, 0.2, 0)
	stem.scale = Vector3(1, 0.01, 1)
	var tw := stem.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(stem, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fade_free(stem, mat, 7.0 + delay)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


static func _column(host: Node, at: Vector3, col: Color, h: float, r: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.6
	cm.bottom_radius = r
	cm.height = h
	var mat := _mat(col)
	cm.material = mat
	mi.mesh = cm
	host.add_child(mi)
	mi.global_position = at + Vector3(0, h * 0.5, 0)
	mi.scale = Vector3(1, 0.01, 1)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.6).set_ease(Tween.EASE_OUT)
	_fade_free(mi, mat, 2.5)


static func _rise(host: Node, at: Vector3, col: Color, r: float, lift: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.6
	var mat := _mat(col)
	sm.material = mat
	mi.mesh = sm
	host.add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", at + Vector3(0, lift, 0), 1.4).set_trans(Tween.TRANS_SINE)
	_fade_free(mi, mat, 4.0)


static func _bar(host: Node, at: Vector3, col: Color, length: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.04, length)
	var mat := _mat(Color(col, 0.75))
	bm.material = mat
	mi.mesh = bm
	host.add_child(mi)
	mi.global_position = at + Vector3(0, 0.05, 0)
	mi.scale = Vector3(1, 1, 0.01)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 1.0)
	_fade_free(mi, mat, 4.0)
