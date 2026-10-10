class_name ShaderPrewarm
extends Node3D
## Draws every effect material once (tiny, in front of the camera) while the travel card still
## masks the screen, so their render pipelines compile up-front instead of stalling the first cast.

static func run(camera: Camera3D, host: Node) -> void:
	var root := ShaderPrewarm.new()
	host.add_child(root)
	var cam_xf := camera.global_transform
	var noise := Kit.noise()
	var mats: Array[Material] = []
	for mode in 3:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/magic/orb_shell.gdshader")
		m.set_shader_parameter("layer_mode", mode)
		m.set_shader_parameter("noise_tex", noise)
		mats.append(m)
	for path in ["res://shaders/magic/sigil.gdshader", "res://shaders/magic/energy_mote.gdshader", "res://shaders/magic/elemental_blade.gdshader",
			"res://shaders/crystal.gdshader", "res://shaders/water.gdshader", "res://shaders/waterfall.gdshader", "res://shaders/rune_floor.gdshader"]:
		var m := ShaderMaterial.new()
		m.shader = load(path)
		mats.append(m)
	var i := 0
	for m in mats:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.02
		s.height = 0.04
		mi.mesh = s
		mi.material_override = m
		mi.global_transform = Transform3D(Basis.IDENTITY, cam_xf.origin - cam_xf.basis.z * 1.0 + cam_xf.basis.x * (i * 0.03 - 0.15))
		root.add_child(mi)
		i += 1
	# a real particle system with the mote material (particle shaders compile separately)
	var p := GPUParticles3D.new()
	p.amount = 4
	p.process_material = ParticleProcessMaterial.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	q.material = mats[4]
	p.draw_pass_1 = q
	p.global_transform = Transform3D(Basis.IDENTITY, cam_xf.origin - cam_xf.basis.z * 1.0)
	root.add_child(p)
	for f in 4:
		await host.get_tree().process_frame
	root.queue_free()
