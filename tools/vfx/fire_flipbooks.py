"""Simulated fire, explosion, smoke and fire-vortex FLIPBOOKS for Oriel's fire (the cinematic pass, 2026-10-14:
"the attack looks so simple ... not cinematic"). Every sprite is a real gas simulation (Blender Mantaflow: fuel,
heat, buoyancy, vorticity, turbulence, smoke that dissolves) rendered volumetrically (Cycles, the fire lighting
its own smoke), the way film/game VFX flipbooks are made - no hand-drawn or noise-only fire.

  blender -b --factory-startup --python tools/vfx/fire_flipbooks.py -- <kind> <work_dir> [--test]

kinds: explosion, flame, burst, smoke, vortex. Writes <work_dir>/<kind>/e_####.png (the fire's light / 4), s_####.png
(the lit smoke, premultiplied) and a_####.png (coverage) - all linear 16-bit. tools/vfx/pack_flipbooks.py packs
them into the game atlases.
"""
import math
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
KIND = argv[0]
WORK = os.path.abspath(argv[1])
TEST = "--test" in argv
OVR = {k[4:]: float(argv[i + 1]) for i, k in enumerate(argv) if k.startswith("--k_")}   # look tuning: --k_dens 6 --k_flame 4

# kind: domain size (x, y, z) m, domain centre, resolution, noise upres, sim frames, rendered frame range,
# camera centre z, camera ortho size (w, h), cell pixels (w, h)
SPEC = {
	"explosion": dict(size=(8.0, 8.0, 10.0), centre=(0, 0, 5.0), res=96, noise=2, frames=74, render=(3, 66), cam_z=4.6, ortho=(8.0, 8.0), px=(384, 384)),
	"flame": dict(size=(2.4, 2.4, 4.8), centre=(0, 0, 2.4), res=112, noise=2, frames=124, render=(62, 119), cam_z=2.0, ortho=(2.0, 4.0), px=(256, 512)),
	"burst": dict(size=(3.2, 3.2, 3.6), centre=(0, 0, 1.8), res=80, noise=2, frames=38, render=(2, 33), cam_z=1.7, ortho=(3.2, 3.2), px=(256, 256)),
	"smoke": dict(size=(6.0, 6.0, 6.0), centre=(0, 0, 3.0), res=80, noise=2, frames=70, render=(3, 66), cam_z=3.0, ortho=(6.0, 6.0), px=(256, 256)),
	"vortex": dict(size=(6.0, 6.0, 9.0), centre=(0, 0, 4.5), res=104, noise=2, frames=150, render=(84, 141), cam_z=4.5, ortho=(6.0, 9.0), px=(256, 384)),
}[KIND]
if TEST:
	SPEC["res"] = int(OVR.get("res", 48))
	SPEC["noise"] = 0
	SPEC["px"] = (SPEC["px"][0] // 2, SPEC["px"][1] // 2)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = SPEC["frames"]
scene.render.fps = 30
CACHE = os.path.join(WORK, "_cache_" + KIND)
OUT = os.path.join(WORK, KIND)
os.makedirs(OUT, exist_ok=True)


def obj_mesh(op, **kw):
	op(**kw)
	return bpy.context.active_object


def key(owner, prop, frame, value):
	setattr(owner, prop, value)
	owner.keyframe_insert(prop, frame=frame)


def cloud_tex(name, scale):
	t = bpy.data.textures.new(name, 'CLOUDS')
	t.noise_scale = scale
	t.noise_depth = 3
	return t


flows = []
DP = {}


def flow(o, ftype, behaviour="INFLOW"):
	m = o.modifiers.new("Fluid", 'FLUID')
	m.fluid_type = 'FLOW'
	fs = m.flow_settings
	fs.flow_type = ftype
	fs.flow_behavior = behaviour
	fs.flow_source = 'MESH'
	fs.volume_density = 1.0
	fs.surface_distance = 1.2
	fs.subframes = 2
	o.hide_render = True
	flows.append(o)
	return fs


def turbulence(loc, strength, size, flow_amt=0.0):
	bpy.ops.object.effector_add(type='TURBULENCE', location=loc)
	e = bpy.context.active_object
	e.field.strength = strength
	e.field.size = size
	e.field.flow = flow_amt
	e.field.noise = 0.0
	return e


smoke_col = (0.42, 0.4, 0.38)
dens_k, flame_k, flame_pow = 6.0, 7.0, 1.35

if KIND == "explosion":
	DP["alpha"] = 0.2
	DP["beta"] = 2.4
	DP["vorticity"] = 0.12
	DP["burning_rate"] = 0.28
	DP["flame_smoke"] = 2.4
	DP["flame_vorticity"] = 0.35
	DP["flame_ignition"] = 1.25
	DP["flame_max_temp"] = 3.4
	DP["flame_smoke_color"] = (0.5, 0.47, 0.45)
	DP["use_dissolve_smoke"] = True
	DP["dissolve_speed"] = 70
	DP["use_dissolve_smoke_log"] = True
	# the blast: five lumps of burning fuel, each swelling for a few frames (staggered, so the fireball is lumpy, not
	# a sphere), thrown outward; the fire rolls over into dark smoke that rises
	blobs = [((0.0, 0.0, 3.3), 1.0, 1, 7, 1.2), ((0.95, 0.35, 3.65), 0.62, 2, 7, 0.85), ((-0.85, -0.2, 3.1), 0.66, 2, 8, 0.9),
		((0.2, -0.55, 4.15), 0.55, 3, 8, 0.8), ((-0.35, 0.6, 2.75), 0.5, 3, 7, 0.75)]
	for bi, (loc, rad, f0, f1, grow) in enumerate(blobs):
		em = obj_mesh(bpy.ops.mesh.primitive_ico_sphere_add, subdivisions=4, radius=rad, location=loc)
		fs = flow(em, 'BOTH')
		fs.fuel_amount = 2.4
		fs.temperature = 3.2
		fs.density = 0.25
		fs.smoke_color = (0.16, 0.15, 0.14)
		fs.use_initial_velocity = True
		fs.velocity_normal = 1.8
		fs.velocity_random = 0.0
		fs.use_texture = True
		fs.noise_texture = cloud_tex("ex%d" % bi, 0.32)
		fs.texture_map_type = 'AUTO'
		fs.texture_size = 1.0
		fs.texture_offset = bi * 1.7
		if f0 > 1:
			key(fs, "use_inflow", 1, False)
		key(fs, "use_inflow", f0, True)
		key(fs, "use_inflow", f1, False)
		em.scale = (0.5, 0.5, 0.5)
		em.keyframe_insert("scale", frame=f0)
		em.scale = (grow, grow, grow * 0.92)
		em.keyframe_insert("scale", frame=f1)
	# the blast's push: a radial force from the heart of it for the first frames (even in every direction)
	bpy.ops.object.effector_add(type='FORCE', location=(0, 0, 3.4))
	fx = bpy.context.active_object
	fx.field.strength = 0.0
	fx.field.keyframe_insert("strength", frame=1)
	fx.field.strength = 9.0
	fx.field.keyframe_insert("strength", frame=2)
	fx.field.strength = 6.0
	fx.field.keyframe_insert("strength", frame=6)
	fx.field.strength = 0.0
	fx.field.keyframe_insert("strength", frame=10)
	fx.field.falloff_type = 'SPHERE'
	fx.field.use_max_distance = True
	fx.field.distance_max = 3.5
	turbulence((0, 0, 3.8), 0.9, 1.8)
	smoke_col = (0.16, 0.15, 0.14)
	dens_k, flame_k, flame_pow = 10.0, 4.5, 1.7
elif KIND == "flame":
	DP["alpha"] = 0.4
	DP["beta"] = 2.5
	DP["vorticity"] = 0.18
	DP["burning_rate"] = 0.42
	DP["flame_smoke"] = 0.3
	DP["flame_vorticity"] = 0.6
	DP["flame_ignition"] = 1.25
	DP["flame_max_temp"] = 2.6
	DP["flame_smoke_color"] = (0.5, 0.48, 0.46)
	DP["use_dissolve_smoke"] = True
	DP["dissolve_speed"] = 14
	DP["use_dissolve_smoke_log"] = True
	em = obj_mesh(bpy.ops.mesh.primitive_ico_sphere_add, subdivisions=3, radius=0.26, location=(0, 0, 0.32))
	em.scale = (1.0, 1.0, 0.6)
	fs = flow(em, 'FIRE')
	fs.fuel_amount = 1.3
	fs.temperature = 1.8
	fs.use_initial_velocity = True
	fs.velocity_coord = (0.0, 0.0, 1.2)
	fs.use_texture = True
	tx = cloud_tex("fl", 0.2)
	fs.noise_texture = tx
	fs.texture_map_type = 'AUTO'
	fs.texture_size = 1.0
	key(fs, "texture_offset", 1, 0.0)
	key(fs, "texture_offset", SPEC["frames"], 6.0)
	turbulence((0, 0, 1.6), 0.35, 0.3, 0.0)
	dens_k, flame_k, flame_pow = 3.0, 4.5, 1.6
elif KIND == "burst":
	DP["alpha"] = 0.3
	DP["beta"] = 1.8
	DP["vorticity"] = 0.15
	DP["burning_rate"] = 0.5
	DP["flame_smoke"] = 1.4
	DP["flame_vorticity"] = 0.4
	DP["flame_ignition"] = 1.3
	DP["flame_max_temp"] = 2.8
	DP["use_dissolve_smoke"] = True
	DP["dissolve_speed"] = 30
	DP["use_dissolve_smoke_log"] = True
	em = obj_mesh(bpy.ops.mesh.primitive_ico_sphere_add, subdivisions=3, radius=0.4, location=(0, 0, 1.3))
	fs = flow(em, 'BOTH')
	fs.fuel_amount = 2.0
	fs.temperature = 2.6
	fs.density = 0.2
	fs.smoke_color = (0.16, 0.15, 0.14)
	fs.use_initial_velocity = True
	fs.velocity_normal = 2.4
	fs.use_texture = True
	fs.noise_texture = cloud_tex("bu", 0.25)
	fs.texture_map_type = 'AUTO'
	key(fs, "use_inflow", 1, True)
	key(fs, "use_inflow", 5, False)
	em.scale = (0.6, 0.6, 0.6)
	em.keyframe_insert("scale", frame=1)
	em.scale = (1.5, 1.5, 1.4)
	em.keyframe_insert("scale", frame=5)
	turbulence((0, 0, 1.4), 1.2, 0.6)
	smoke_col = (0.16, 0.15, 0.14)
	dens_k, flame_k, flame_pow = 9.0, 3.2, 2.0
elif KIND == "smoke":
	DP["alpha"] = 0.25
	DP["beta"] = 0.5
	DP["vorticity"] = 0.5
	DP["use_dissolve_smoke"] = True
	DP["dissolve_speed"] = 44
	DP["use_dissolve_smoke_log"] = True
	em = obj_mesh(bpy.ops.mesh.primitive_ico_sphere_add, subdivisions=3, radius=0.7, location=(0, 0, 2.2))
	fs = flow(em, 'SMOKE')
	fs.temperature = 0.35
	fs.density = 1.0
	fs.smoke_color = (0.85, 0.84, 0.82)
	fs.use_initial_velocity = True
	fs.velocity_normal = 3.6
	fs.velocity_random = 0.6
	fs.use_texture = True
	fs.noise_texture = cloud_tex("sm", 0.4)
	fs.texture_map_type = 'AUTO'
	key(fs, "use_inflow", 1, True)
	key(fs, "use_inflow", 4, False)
	turbulence((0, 0, 2.6), 2.0, 0.6)
	smoke_col = (0.85, 0.84, 0.82)
	dens_k, flame_k = 5.0, 0.0
elif KIND == "vortex":
	DP["alpha"] = 0.15
	DP["beta"] = 2.4
	DP["vorticity"] = 0.38
	DP["burning_rate"] = 0.68
	DP["flame_smoke"] = 0.3
	DP["flame_vorticity"] = 0.8
	DP["flame_ignition"] = 1.2
	DP["flame_max_temp"] = 2.8
	DP["use_dissolve_smoke"] = True
	DP["dissolve_speed"] = 16
	DP["use_dissolve_smoke_log"] = True
	em = obj_mesh(bpy.ops.mesh.primitive_torus_add, major_radius=1.45, minor_radius=0.2, location=(0, 0, 0.35))
	fs = flow(em, 'FIRE')
	fs.fuel_amount = 0.9
	fs.temperature = 1.8
	fs.use_initial_velocity = True
	fs.velocity_coord = (0.0, 0.0, 1.4)
	fs.use_texture = True
	tx = cloud_tex("vx", 0.3)
	fs.noise_texture = tx
	fs.texture_map_type = 'AUTO'
	key(fs, "texture_offset", 1, 0.0)
	key(fs, "texture_offset", SPEC["frames"], 8.0)
	bpy.ops.object.effector_add(type='VORTEX', location=(0, 0, 0))
	vx = bpy.context.active_object
	vx.field.strength = 9.0
	vx.field.falloff_type = 'TUBE'
	vx.field.use_max_distance = True
	vx.field.distance_max = 3.2
	turbulence((0, 0, 4.0), 2.2, 0.5)
	dens_k, flame_k, flame_pow = 3.0, 2.4, 1.8

# ---------------------------------------------------------------- domain
dom = obj_mesh(bpy.ops.mesh.primitive_cube_add, size=1.0, location=SPEC["centre"])
dom.scale = SPEC["size"]
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
dmod = dom.modifiers.new("Fluid", 'FLUID')
dmod.fluid_type = 'DOMAIN'
ds = dmod.domain_settings
ds.domain_type = 'GAS'
ds.resolution_max = SPEC["res"]
ds.cache_type = 'ALL'
ds.cache_directory = CACHE
ds.cache_frame_start = 1
ds.cache_frame_end = SPEC["frames"]
ds.use_adaptive_domain = False
for side in ("top", "bottom", "left", "right", "front", "back"):
	setattr(ds, "use_collision_border_" + side, side == "bottom")
for k, v in DP.items():
	setattr(ds, k, v)
ds.use_noise = SPEC["noise"] > 0
if ds.use_noise:
	ds.noise_scale = SPEC["noise"]
	ds.noise_strength = 1.4
	ds.noise_pos_scale = 2.0
	ds.noise_time_anim = 0.15


bpy.ops.object.select_all(action='DESELECT')
dom.select_set(True)
bpy.context.view_layer.objects.active = dom
print("BAKE", KIND, "res", SPEC["res"], "noise", SPEC["noise"], flush=True)
with bpy.context.temp_override(scene=scene, active_object=dom, object=dom, selected_objects=[dom]):
	bpy.ops.fluid.bake_all()
print("BAKED", KIND, flush=True)

# ---------------------------------------------------------------- the volume material: soot that the fire lights
mat = bpy.data.materials.new("fire_" + KIND)
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
	nt.nodes.remove(n)
out = nt.nodes.new("ShaderNodeOutputMaterial")
pv = nt.nodes.new("ShaderNodeVolumePrincipled")
pv.inputs["Density"].default_value = dens_k
pv.inputs["Color"].default_value = (*smoke_col, 1.0)
pv.inputs["Anisotropy"].default_value = 0.25
pv.inputs["Blackbody Intensity"].default_value = 0.0
if flame_k > 0.0:
	fl = nt.nodes.new("ShaderNodeAttribute")
	fl.attribute_name = "flame"
	ramp = nt.nodes.new("ShaderNodeValToRGB")
	cr = ramp.color_ramp
	cr.interpolation = 'B_SPLINE'
	stops = [(0.0, (0.0, 0.0, 0.0)), (0.05, (0.25, 0.02, 0.0)), (0.18, (0.85, 0.12, 0.01)), (0.35, (1.0, 0.32, 0.03)),
		(0.55, (1.0, 0.55, 0.1)), (0.8, (1.0, 0.78, 0.35)), (1.0, (1.0, 0.95, 0.8))]
	cr.elements[0].position, cr.elements[0].color = stops[0][0], (*stops[0][1], 1.0)
	cr.elements[1].position, cr.elements[1].color = stops[-1][0], (*stops[-1][1], 1.0)
	for p, c in stops[1:-1]:
		e = cr.elements.new(p)
		e.color = (*c, 1.0)
	pw = nt.nodes.new("ShaderNodeMath")
	pw.operation = 'POWER'
	pw.inputs[1].default_value = flame_pow
	mul = nt.nodes.new("ShaderNodeMath")
	mul.operation = 'MULTIPLY'
	mul.inputs[1].default_value = flame_k
	nt.links.new(fl.outputs["Fac"], ramp.inputs["Fac"])
	nt.links.new(fl.outputs["Fac"], pw.inputs[0])
	nt.links.new(pw.outputs[0], mul.inputs[0])
	nt.links.new(ramp.outputs["Color"], pv.inputs["Emission Color"])
	nt.links.new(mul.outputs[0], pv.inputs["Emission Strength"])
dens_k = OVR.get("dens", dens_k)
flame_pow = OVR.get("pow", flame_pow)
if flame_k > 0.0:
	pw.inputs[1].default_value = flame_pow
flame_k = OVR.get("flame", flame_k)
pv.inputs["Density"].default_value = dens_k
if flame_k > 0.0:
	mul.inputs[1].default_value = flame_k
nt.links.new(pv.outputs["Volume"], out.inputs["Volume"])
dom.data.materials.append(mat)

# ---------------------------------------------------------------- light, camera, render
sun_d = bpy.data.lights.new("sun", 'SUN')
sun_d.energy = 3.2
sun_d.angle = math.radians(8)
sun = bpy.data.objects.new("sun", sun_d)
sun.rotation_euler = (math.radians(38), math.radians(-28), math.radians(18))
scene.collection.objects.link(sun)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.3, 0.33, 0.38, 1.0)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
scene.world = world
cd = bpy.data.cameras.new("cam")
cd.type = 'ORTHO'
cd.ortho_scale = max(SPEC["ortho"])
cam = bpy.data.objects.new("cam", cd)
cam.location = (0.0, -30.0, SPEC["cam_z"])
cam.rotation_euler = (math.radians(90), 0.0, 0.0)
scene.collection.objects.link(cam)
scene.camera = cam
r = scene.render
r.engine = 'CYCLES'
r.resolution_x, r.resolution_y = SPEC["px"]
r.resolution_percentage = 100
r.film_transparent = True
r.filepath = os.path.join(CACHE, "main_")
cy = scene.cycles
cy.device = 'CPU'
if "--gpu" in argv:
	# the RTX (OptiX, else CUDA) renders the volumes; the sim itself always bakes on the CPU
	cp = bpy.context.preferences.addons["cycles"].preferences
	for kind in ("OPTIX", "CUDA"):
		try:
			cp.compute_device_type = kind
			cp.get_devices()
			gpus = [d for d in cp.devices if d.type == kind]
			if gpus:
				for d in cp.devices:
					d.use = d.type == kind
				cy.device = 'GPU'
				print("CYCLES GPU", kind, [d.name for d in gpus], flush=True)
				break
		except Exception as e:
			print("no", kind, e, flush=True)
cy.samples = 16 if TEST else 28
cy.use_denoising = True
cy.denoiser = 'OPENIMAGEDENOISE'
cy.volume_step_rate = 1.2
cy.volume_max_steps = 512
cy.volume_bounces = 1
cy.max_bounces = 4
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0.0

# three linear layers per frame, so the game controls fire and smoke independently (HDR fire, relit/tinted smoke):
#   e_  the fire's own light (Emission pass) x 1/4, so up to 4.0 fits      s_  the smoke as the sun and the fire lit
#   it (combined - emission; premultiplied by its coverage)               a_  coverage
scene.view_layers[0].use_pass_emit = True
scene.use_nodes = True
ct = scene.node_tree
for n in list(ct.nodes):
	ct.nodes.remove(n)
rl = ct.nodes.new('CompositorNodeRLayers')
comp = ct.nodes.new('CompositorNodeComposite')
ct.links.new(rl.outputs['Image'], comp.inputs['Image'])
emit_scale = ct.nodes.new('CompositorNodeMixRGB')
emit_scale.blend_type = 'MULTIPLY'
emit_scale.inputs[0].default_value = 1.0
emit_scale.inputs[2].default_value = (0.25, 0.25, 0.25, 1.0)
ct.links.new(rl.outputs['Emit'], emit_scale.inputs[1])
smoke = ct.nodes.new('CompositorNodeMixRGB')
smoke.blend_type = 'SUBTRACT'
smoke.inputs[0].default_value = 1.0
ct.links.new(rl.outputs['Image'], smoke.inputs[1])
ct.links.new(rl.outputs['Emit'], smoke.inputs[2])
fo = ct.nodes.new('CompositorNodeOutputFile')
fo.base_path = OUT
fo.file_slots[0].path = "e_"
fo.file_slots.new("s_")
fo.file_slots.new("a_")
for name, mode in (("e_", 'RGB'), ("s_", 'RGB'), ("a_", 'BW')):
	sl = fo.file_slots[name]
	sl.use_node_format = False
	sl.format.file_format = 'PNG'
	sl.format.color_mode = mode
	sl.format.color_depth = '16'
	sl.format.color_management = 'OVERRIDE'
	sl.format.view_settings.view_transform = 'Raw'
ct.links.new(emit_scale.outputs[0], fo.inputs[0])
ct.links.new(smoke.outputs[0], fo.inputs[1])
ct.links.new(rl.outputs['Alpha'], fo.inputs[2])

a, b = SPEC["render"]
every = int(argv[argv.index("--every") + 1]) if "--every" in argv else 1
for f in range(a, b + 1, every):
	scene.frame_set(f)
	bpy.ops.render.render(write_still=False)
	print("FRAME", KIND, f, flush=True)
print("DONE", KIND, flush=True)
