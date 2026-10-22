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
			"res://shaders/crystal.gdshader", "res://shaders/water.gdshader", "res://shaders/waterfall.gdshader", "res://shaders/rune_floor.gdshader",
			"res://shaders/magic/wind_arcs.gdshader", "res://shaders/magic/water_rings.gdshader", "res://shaders/magic/flame_billboard.gdshader",
			"res://shaders/magic/beam.gdshader", "res://shaders/magic/smoke_puff.gdshader", "res://shaders/light_shaft.gdshader",
			"res://shaders/magic/shockwave.gdshader", "res://shaders/magic/umbral_core.gdshader", "res://shaders/magic/aura_column.gdshader",
			"res://shaders/magic/orbit_ring.gdshader", "res://shaders/telegraph.gdshader", "res://shaders/ribbon_light.gdshader",
			"res://shaders/creature_stone.gdshader", "res://shaders/ambient_creature.gdshader", "res://shaders/cocoon.gdshader"]:
		var m := ShaderMaterial.new()
		m.shader = load(path)
		mats.append(m)
	# every other spatial effect shader in the effect folders (new effects are covered without editing this list:
	# crescent waves, afterimages, fire flipbooks, heat haze, crystals, wards, the phoenix ...)
	var listed := {}
	for m in mats:
		listed[(m as ShaderMaterial).shader.resource_path] = true
	for dir in ["res://shaders/fx", "res://shaders/magic", "res://shaders/vfx", "res://shaders/world", "res://shaders/phoenix", "res://shaders/nature"]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for fname in da.get_files():
			var path: String = String(dir) + "/" + String(fname).trim_suffix(".remap")
			if not path.ends_with(".gdshader") or listed.has(path):
				continue
			var sh := load(path) as Shader
			if sh == null or sh.get_mode() != Shader.MODE_SPATIAL:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = sh
			mats.append(sm)
			listed[path] = true
	var i := 0
	for m in mats:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.02
		s.height = 0.04
		mi.mesh = s
		mi.material_override = m
		mi.global_transform = Transform3D(Basis.IDENTITY, cam_xf.origin - cam_xf.basis.z * 1.0 + cam_xf.basis.x * ((i % 12) * 0.03 - 0.15) + cam_xf.basis.y * (int(i / 12.0) * 0.03 - 0.1))
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
	# every elemental particle preset the spells and reactions use (each process material variant compiles
	# its own particle shader; trail/round/puff draw meshes compile their own pipelines)
	var k := 0
	var combos := []
	for el in ["arcane", "wind", "water", "fire", "rune", "self", "mist", "umbral", "eclipse", "bloom"]:
		for kind in ["gather", "swirl", "trail", "burst", "rise", "splash"]:
			combos.append([FX.pm_motes(el, kind), FX.mote_mesh(0.05)])
	for kind in ["steam", "smoke", "dust", "mist"]:
		combos.append([FX.pm_puff(kind), FX.puff_mesh(0.5)])
	combos.append([FX.pm_motes("wind", "trail"), FX.mote_mesh(0.06, true)])
	for c in combos:
		var pp := GPUParticles3D.new()
		pp.amount = 2
		pp.lifetime = 0.2
		pp.process_material = c[0]
		pp.draw_pass_1 = c[1]
		pp.global_transform = Transform3D(Basis.IDENTITY, cam_xf.origin - cam_xf.basis.z * 1.0 + cam_xf.basis.y * (k * 0.002))
		root.add_child(pp)
		k += 1
	for f in 6:
		await host.get_tree().process_frame
	root.queue_free()


## An area's own look behind the travel card (2026-10-20, Lantern Lake: 130 ms frames on screen while the place and
## its boat compiled): a camera of its own turns once round where she arrives, level and looking down a little, so
## every material of the place is drawn once, and the shader folders of what plays there later (the boat, the dance
## glows) are drawn on tiny spheres in front of it.
static func area(camera: Camera3D, host: Node, dirs: Array) -> void:
	var root := ShaderPrewarm.new()
	host.add_child(root)
	var xf := camera.global_transform
	var cam := Camera3D.new()
	cam.fov = camera.fov
	cam.near = camera.near
	cam.far = camera.far
	cam.cull_mask = camera.cull_mask
	cam.environment = camera.environment
	root.add_child(cam)
	cam.global_transform = xf
	cam.current = true
	var i := 0
	for dir in dirs:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for fname in da.get_files():
			var path: String = String(dir) + "/" + String(fname).trim_suffix(".remap")
			if not path.ends_with(".gdshader"):
				continue
			var sh := load(path) as Shader
			if sh == null or sh.get_mode() != Shader.MODE_SPATIAL:
				continue
			var sm := ShaderMaterial.new()
			sm.shader = sh
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.02
			s.height = 0.04
			mi.mesh = s
			mi.material_override = sm
			root.add_child(mi)
			mi.global_transform = Transform3D(Basis.IDENTITY, xf.origin - xf.basis.z * 1.0 + xf.basis.x * ((i % 12) * 0.03 - 0.15) + xf.basis.y * (int(i / 12.0) * 0.03 - 0.1))
			i += 1
			await host.get_tree().process_frame       # one shader per frame (all of them at once was a 170 ms frame)
	var yaw0 := xf.basis.get_euler().y
	for k in 16:
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.4 if k >= 8 else 0.0, yaw0 + TAU * float(k % 8) / 8.0, 0.0)), xf.origin)
		await host.get_tree().process_frame
	cam.current = false
	camera.current = true
	root.queue_free()


## Every sky shader drawn once in a tiny hidden view at the stage's start: a new area's sky compiled on first sight
## and held one frame for 0.7 s inside the Mentor's Tower's build (2026-10-22). Returns how many were drawn.
static func skies(host: Node) -> int:
	var paths := []
	for dir in ["res://shaders", "res://shaders/nature", "res://shaders/world", "res://shaders/sky", "res://shaders/fx"]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for fname in da.get_files():
			var path: String = String(dir) + "/" + String(fname).trim_suffix(".remap")
			if not path.ends_with(".gdshader"):
				continue
			var sh := load(path) as Shader
			if sh != null and sh.get_mode() == Shader.MODE_SKY:
				paths.append(path)
	if paths.is_empty():
		return 0
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_aerial_perspective = 0.5
	we.environment = env
	vp.add_child(we)
	for p in paths:
		for night in [0.0, 1.0]:
			var sm := ShaderMaterial.new()
			sm.shader = load(p)
			sm.set_shader_parameter("night", night)
			var sky := Sky.new()
			sky.sky_material = sm
			sky.radiance_size = Sky.RADIANCE_SIZE_128
			sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
			env.sky = sky
			await host.get_tree().process_frame
			await host.get_tree().process_frame
	vp.queue_free()
	return paths.size()
