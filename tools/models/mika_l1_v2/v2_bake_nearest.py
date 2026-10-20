"""Mika L1 v2 parts, face budget (Selwyn 2026-10-20): nearest surface bake of the clean high poly flat colours onto
the low poly. The low poly is the Meshy shape and lies on the high poly within hundredths of a mm, so every texel
centre is mapped to its 3D point and takes the colour of the nearest point on the high poly (Blender BVH). No rays, so
creases and Meshy's sliver triangles can no longer send a texel to the neighbouring surface (the Cycles ray bake left
white combs in the gold there). Writes the raw palette bake for v2_snap.py, which fills the padding.
Runs in plain python (texel points with OpenCV), then calls Blender on itself for the BVH lookups.
  python3 tools/v2_bake_nearest.py <uv.npz> <high.glb> <out.png> <size cm>"""
import sys, os, time, subprocess
import numpy as np

N = 4096
PAL = {'white': 'F4F4FA', 'navy': '1C2556', 'gold': 'D8B26A', 'sky': '6FA8E8'}
NAMES = list(PAL)


def blender_side():
    import bpy
    from mathutils.bvhtree import BVHTree
    argv = sys.argv[sys.argv.index('--') + 1:]
    pts, high, labs = argv[:3]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=high)
    verts, polys, plab = [], [], []
    for o in [o for o in bpy.data.objects if o.type == 'MESH']:
        m = o.data; mw = o.matrix_world; base = len(verts)
        verts += [mw @ v.co for v in m.vertices]
        for p in m.polygons:
            polys.append([base + i for i in p.vertices])
            plab.append(NAMES.index(m.materials[p.material_index].name.replace('MIKA_L1_', '').split('.')[0]))
    plab = np.array(plab, np.uint8)
    fn = BVHTree.FromPolygons(verts, polys).find_nearest
    X = np.load(pts)['X']
    lab = np.zeros(len(X), np.uint8); dist = np.zeros(len(X), np.float32)
    t0 = time.time()
    for i, x in enumerate(X.tolist()):
        r = fn(x)
        lab[i] = plab[r[2]]; dist[i] = r[3]
    np.savez(labs, lab=lab, dist=dist)
    print(f'BVH {len(X)} lookups in {time.time() - t0:.0f} s')


def python_side():
    import cv2
    uvnpz, high, out_png, size_cm = sys.argv[1:5]
    d = np.load(uvnpz); UV, LV, LF = d['UV'], d['V'], d['F']
    img = np.zeros((N, N, 3), np.uint8)
    P = np.round(np.c_[UV[..., 0].ravel(), 1 - UV[..., 1].ravel()] * N * 16 - 8).astype(np.int32).reshape(-1, 3, 2)
    for t in range(len(LF)):                                             # triangle id per texel centre
        v = t + 1
        cv2.fillConvexPoly(img, P[t], (v & 255, (v >> 8) & 255, v >> 16), lineType=cv2.LINE_8, shift=4)
    fid = (img[..., 0].astype(np.int64) | img[..., 1].astype(np.int64) << 8 | img[..., 2].astype(np.int64) << 16) - 1
    ys, xs = np.nonzero(fid >= 0); t = fid[ys, xs]
    p = np.c_[(xs + 0.5) / N, 1 - (ys + 0.5) / N]
    a, b, c = UV[t, 0], UV[t, 1], UV[t, 2]
    v0, v1, v2 = b - a, c - a, p - a
    den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
    den = np.where(np.abs(den) < 1e-20, 1e-20, den)
    w1 = np.clip((v2[:, 0] * v1[:, 1] - v1[:, 0] * v2[:, 1]) / den, 0, 1)    # clamped, edge texels stay on the face
    w2 = np.clip((v0[:, 0] * v2[:, 1] - v2[:, 0] * v0[:, 1]) / den, 0, 1 - w1)
    w0 = 1 - w1 - w2
    X = w0[:, None] * LV[LF[t, 0]] + w1[:, None] * LV[LF[t, 1]] + w2[:, None] * LV[LF[t, 2]]
    tmp = out_png[:-4]
    np.savez(tmp + '_pts.npz', X=X)
    subprocess.run(['blender', '-b', '--factory-startup', '-P', os.path.abspath(__file__), '--',
                    tmp + '_pts.npz', high, tmp + '_lab.npz'], check=True, stdout=subprocess.DEVNULL)
    r = np.load(tmp + '_lab.npz'); lab, dist = r['lab'], r['dist']
    os.remove(tmp + '_pts.npz'); os.remove(tmp + '_lab.npz')
    mm = (LV.max(0) - LV.min(0)).max() / (float(size_cm) * 10)
    dist = dist / mm
    PALC = np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in PAL.values()], np.uint8)
    out = np.zeros((N, N, 3), np.uint8)                                  # black = not baked, v2_snap fills it
    out[ys, xs] = PALC[lab]
    cv2.imwrite(out_png, out[..., ::-1])
    print(f'BAKED_NEAREST {os.path.basename(out_png)} texels {len(X)} distance to high poly mm p50 '
          f'{np.percentile(dist, 50):.3f} p99 {np.percentile(dist, 99):.3f} p99.9 {np.percentile(dist, 99.9):.3f} max {dist.max():.3f}')


if 'bpy' in sys.modules or '--' in sys.argv:
    blender_side()
else:
    python_side()
