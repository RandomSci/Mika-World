"""Hair refinement for the Level 1-10 looks (the developer: "Their hair looks so messy! Fix it ... Use blender if
possible. Just to make them more natural."). Runs on a READ-ONLY source .blend from a character lab (never saved
back) and exports a new DEV VRM; the hairstyle (every clump's shape, colour, ornaments) is unchanged.

Why it looked messy: the lab's strand clumps carry 'volume' normals that are only 75 % head-sphere / body-cylinder
and 25 % the clump's own faceted surface; under MToon's sharp toon ramp that leftover per-clump variation breaks
into hard-edged light/dark shards (and overlapping clumps cut jagged boundaries into each other).

What this does (anime hair practice - shade the hairdo as ONE soft mass):
  1. an ENVELOPE of the whole hairdo: the hair mesh voxel-remeshed (closing the gaps between clumps) and smoothed
     heavily, so it follows the real silhouette (Mika's long straight fall, Luna's big curls) without the clumps;
  2. its normals transferred onto every hair vertex (Data Transfer, custom normals, nearest-face interpolated),
     mixed with a little of the strand's own relief (`--keep` 0..1) so locks still read as locks;
  3. the strand mesh itself relaxed a touch along the hair (roots pinned via the 'ht' attribute) to round off
     saw-tooth clump edges;
then the VRM is exported exactly as the lab's s13_export does (same addon, same armature).

  blender -b <lab>/blend/<Name>_export_ready.blend --python tools/models/refine_hair.py -- <out.vrm> [--voxel 0.014]
      [--smooth 40] [--keep 0.12] [--relax 0.35]
"""
import sys

import bpy
import bmesh
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
CELL = float(argv[argv.index("--cell") + 1]) if "--cell" in argv else 0.02
BLUR = int(argv[argv.index("--blur") + 1]) if "--blur" in argv else 4
KEEP = float(argv[argv.index("--keep") + 1]) if "--keep" in argv else 0.1
RELAX = float(argv[argv.index("--relax") + 1]) if "--relax" in argv else 0.35
SHELL = float(argv[argv.index("--shell") + 1]) if "--shell" in argv else 0.0     # voxel size (m); 0 = no shell
SHRINK = float(argv[argv.index("--shrink") + 1]) if "--shrink" in argv else 0.006

hair = bpy.data.objects.get("Hair")
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
assert hair is not None, "no Hair object"
print("hair", len(hair.data.vertices), "verts; modifiers", [(m.name, m.type) for m in hair.modifiers])


def ctx(active, sel=()):
	for o in bpy.context.view_layer.objects:
		o.select_set(o in sel or o == active)
	bpy.context.view_layer.objects.active = active


# ---- 1. relax the strand surfaces a little (roots pinned) to round off saw-tooth clump edges
arm.data.pose_position = 'REST'
if RELAX > 0.0:
	me = hair.data
	ht = me.attributes.get("ht")
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.verts.ensure_lookup_table()
	tvals = [0.0] * len(bm.verts)
	if ht:
		for i, d in enumerate(ht.data):
			tvals[i] = d.value
	orig = [v.co.copy() for v in bm.verts]
	for v in bm.verts:
		nb = [e.other_vert(v) for e in v.link_edges]
		if not nb:
			continue
		avg = sum((orig[n.index] for n in nb), orig[v.index] * 0.0) / len(nb)
		v.co = orig[v.index].lerp(avg, RELAX * min(1.0, tvals[v.index] * 4.0))
	bm.to_mesh(me)
	bm.free()
	me.update()

# ---- 2. one soft normal field for the whole hairdo: the hair's own (volume) normals averaged into a 3D grid,
# blurred, and sampled back trilinearly at every vertex - neighbouring clumps then shade alike (no shards), the big
# forms (crown, fall, curls) keep their light and shade
me = hair.data
nv = len(me.vertices)
P = np.empty(nv * 3, np.float32)
me.vertices.foreach_get("co", P)
P = P.reshape(-1, 3)
cn = np.empty(len(me.loops) * 3, np.float32)
me.corner_normals.foreach_get("vector", cn) if hasattr(me, "corner_normals") else me.loops.foreach_get("normal", cn)
cn = cn.reshape(-1, 3)
lv = np.empty(len(me.loops), np.int32)
me.loops.foreach_get("vertex_index", lv)
N0 = np.zeros((nv, 3), np.float64)
np.add.at(N0, lv, cn)
N0 /= np.maximum(np.linalg.norm(N0, axis=1, keepdims=True), 1e-9)


def coherence(N):
	# mean disagreement with the 8 nearest vertices (grid-hashed approximation: same-cell neighbours)
	key = np.floor(P / 0.01).astype(np.int64)
	h = key[:, 0] * 73856093 ^ key[:, 1] * 19349663 ^ key[:, 2] * 83492791
	order = np.argsort(h)
	hs = h[order]
	same = hs[1:] == hs[:-1]
	a, b = order[1:][same], order[:-1][same]
	return float(1.0 - (N[a] * N[b]).sum(1).mean()) if len(a) else 0.0


lo = P.min(0) - CELL * 6
dims = np.ceil((P.max(0) + CELL * 6 - lo) / CELL).astype(int) + 1
g = (P - lo) / CELL
dens = np.zeros(tuple(dims), np.float64)
grid = np.zeros(tuple(dims) + (3,), np.float64)
i0 = np.floor(g).astype(int)
f = g - i0
W = []
for dx in (0, 1):
	for dy in (0, 1):
		for dz in (0, 1):
			w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
			W.append((dx, dy, dz, w))
			np.add.at(dens, (i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz), w)
			np.add.at(grid, (i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz), N0 * w[:, None])
for _ in range(BLUR):
	for ax in range(3):
		dens = (np.roll(dens, 1, ax) + 2 * dens + np.roll(dens, -1, ax)) * 0.25
		grid = (np.roll(grid, 1, ax) + 2 * grid + np.roll(grid, -1, ax)) * 0.25
# outward from the hair MASS: minus the gradient of the blurred density (well defined everywhere on the surface of
# the hairdo, never cancels like averaged normals do where clumps face opposite ways)
grad = np.stack(np.gradient(dens), -1)
NS = np.zeros_like(N0)
NA = np.zeros_like(N0)
for dx, dy, dz, w in W:
	NS -= grad[i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz] * w[:, None]
	NA += grid[i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz] * w[:, None]
gl = np.linalg.norm(NS, axis=1, keepdims=True)
NS = NS / np.maximum(gl, 1e-12)
NA = NA / np.maximum(np.linalg.norm(NA, axis=1, keepdims=True), 1e-9)
# deep inside the mass the gradient is weak: lean on the averaged field there
conf = np.clip(gl / (np.percentile(gl, 60) + 1e-12), 0.0, 1.0)
NS = NS * conf + NA * (1.0 - conf)
NS /= np.maximum(np.linalg.norm(NS, axis=1, keepdims=True), 1e-9)
N1 = NS * (1.0 - KEEP) + N0 * KEEP
N1 /= np.maximum(np.linalg.norm(N1, axis=1, keepdims=True), 1e-9)
print("normal disagreement before %.4f after %.4f" % (coherence(N0), coherence(N1)))
me.normals_split_custom_set_from_vertices([tuple(n) for n in N1])
me.update()

# ---- 3. a smooth inner SHELL of the hairdo under the clumps: the gaps between offset clump tubes (curl "staircases",
# parted locks) show hair, not background or shadow. The hair volume voxel-remeshed, smoothed, shrunk under the
# clumps, skinned to the same bones as the nearest strands (so it moves with the springs), hair-under material.
if SHELL > 0.0:
	sh_me = hair.data.copy()
	shell = bpy.data.objects.new("HairShell", sh_me)
	bpy.context.scene.collection.objects.link(shell)
	shell.matrix_world = hair.matrix_world.copy()
	shell.parent = hair.parent
	shell.matrix_parent_inverse = hair.matrix_parent_inverse.copy()
	for vg in list(shell.vertex_groups):
		shell.vertex_groups.remove(vg)
	ctx(shell, [shell])
	r = shell.modifiers.new("remesh", 'REMESH')
	r.mode = 'VOXEL'
	r.voxel_size = SHELL
	bpy.ops.object.modifier_apply(modifier=r.name)
	smo = shell.modifiers.new("smooth", 'SMOOTH')
	smo.factor = 0.7
	smo.iterations = 12
	bpy.ops.object.modifier_apply(modifier=smo.name)
	dec = shell.modifiers.new("dec", 'DECIMATE')
	dec.ratio = 0.5
	bpy.ops.object.modifier_apply(modifier=dec.name)
	# shrink under the clumps
	sm2 = shell.data
	for v in sm2.vertices:
		v.co = v.co - v.normal * SHRINK
	sm2.update()
	for poly in sm2.polygons:
		poly.use_smooth = True
	# material: the hair's under layer
	sm2.materials.clear()
	under = next((m for m in hair.data.materials if m and m.name.endswith("HairUnder")), hair.data.materials[0])
	sm2.materials.append(under)
	# skin weights from the nearest strands
	for vg in hair.vertex_groups:
		shell.vertex_groups.new(name=vg.name)
	dtw = shell.modifiers.new("weights", 'DATA_TRANSFER')
	dtw.object = hair
	dtw.use_vert_data = True
	dtw.data_types_verts = {'VGROUP_WEIGHTS'}
	dtw.vert_mapping = 'POLYINTERP_NEAREST'
	dtw.layers_vgroup_select_src = 'ALL'
	dtw.layers_vgroup_select_dst = 'NAME'
	bpy.ops.object.datalayout_transfer(modifier=dtw.name)
	bpy.ops.object.modifier_apply(modifier=dtw.name)
	am = shell.modifiers.new("Armature", 'ARMATURE')
	am.object = arm
	print("shell", len(sm2.vertices), "verts")

# ---- export like the lab's s13_export
arm.data.pose_position = 'POSE'
ctx(arm, [arm])
r = bpy.ops.export_scene.vrm(filepath=OUT, armature_object_name=arm.name)
print("vrm export", r, OUT)
