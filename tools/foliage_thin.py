#!/usr/bin/env python3
"""Foliage LOD for dense photogrammetry/hand-modelled trees (Poly Haven glTF).

Leaf primitives are thinned by *island* (a whole leaf / twig cluster is kept or dropped,
never cut in half), and kept islands are scaled up around their own centroid so the
canopy keeps its silhouette and coverage at a fraction of the triangle count.
Non-leaf primitives (trunk/branches) are passed through unchanged; decimate them
afterwards in Blender (tools/blender/decimate_bark.py).

usage: foliage_thin.py in.gltf out.gltf --keep 0.12 --grow 1.7 --seed 1 [--leaf-words leaves,twig]
"""
import argparse, json, os, struct
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("dst")
ap.add_argument("--keep", type=float, default=0.12)
ap.add_argument("--grow", type=float, default=1.7)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--leaf-words", default="leaf,leaves,twig,needle,foliage")
a = ap.parse_args()

g = json.load(open(a.src))
bin_path = os.path.join(os.path.dirname(a.src), g["buffers"][0]["uri"])
blob = np.fromfile(bin_path, dtype=np.uint8)


def read(acc_i):
    acc = g["accessors"][acc_i]
    bv = g["bufferViews"][acc["bufferView"]]
    n = NC[acc["type"]]
    dt = CT[acc["componentType"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    itemsize = np.dtype(dt).itemsize * n
    if stride and stride != itemsize:
        raw = np.lib.stride_tricks.as_strided(blob[off:], shape=(acc["count"], itemsize), strides=(stride, 1))
        return raw.copy().view(dt).reshape(acc["count"], n)
    return blob[off: off + acc["count"] * itemsize].view(dt).reshape(acc["count"], n) if n > 1 else \
        blob[off: off + acc["count"] * itemsize].view(dt).copy()


leaf_words = a.leaf_words.split(",")
rng = np.random.default_rng(a.seed)
out_bin = bytearray()
new_views, new_accs = [], []


def push(arr, target=None, kind="VEC3", ctype=5126):
    global out_bin
    arr = np.ascontiguousarray(arr)
    while len(out_bin) % 4:
        out_bin += b"\0"
    off = len(out_bin)
    out_bin += arr.tobytes()
    view = {"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes}
    if target:
        view["target"] = target
    new_views.append(view)
    acc = {"bufferView": len(new_views) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": kind}
    if kind == "VEC3" and ctype == 5126:
        acc["min"] = arr.min(0).tolist(); acc["max"] = arr.max(0).tolist()
    new_accs.append(acc)
    return len(new_accs) - 1


stats = []
for mesh in g["meshes"]:
    for prim in mesh["primitives"]:
        mat_name = g["materials"][prim["material"]]["name"].lower() if "material" in prim else ""
        attrs = {k: read(v) for k, v in prim["attributes"].items()}
        idx = read(prim["indices"]).astype(np.int64).reshape(-1, 3)
        is_leaf = any(w in mat_name for w in leaf_words)
        before = len(idx)
        if is_leaf:
            pos = attrs["POSITION"].astype(np.float64)
            q = np.round(pos * 2000.0).astype(np.int64)  # weld at 0.5 mm
            _, weld = np.unique(q, axis=0, return_inverse=True)
            weld = weld.reshape(-1)
            tv = weld[idx]
            nverts = weld.max() + 1
            rows = np.concatenate([tv[:, 0], tv[:, 1]])
            cols = np.concatenate([tv[:, 1], tv[:, 2]])
            graph = coo_matrix((np.ones(len(rows), dtype=np.int8), (rows, cols)), shape=(nverts, nverts))
            ncomp, lab = connected_components(graph, directed=False)
            tri_comp = lab[tv[:, 0]]
            keep_comp = rng.random(ncomp) < a.keep
            keep_tri = keep_comp[tri_comp]
            idx = idx[keep_tri]
            tri_comp = tri_comp[keep_tri]
            # grow each kept island about its centroid
            used = np.unique(idx)
            vcomp = np.full(len(pos), -1, dtype=np.int64)
            vcomp[idx.reshape(-1)] = np.repeat(tri_comp, 3)
            sums = np.zeros((ncomp, 3)); cnt = np.zeros(ncomp)
            np.add.at(sums, vcomp[used], pos[used]); np.add.at(cnt, vcomp[used], 1)
            cent = sums / np.maximum(cnt, 1)[:, None]
            pos[used] = cent[vcomp[used]] + (pos[used] - cent[vcomp[used]]) * a.grow
            attrs["POSITION"] = pos.astype(np.float32)
            stats.append((mesh.get("name"), mat_name, "leaf", ncomp, before, len(idx)))
        else:
            stats.append((mesh.get("name"), mat_name, "bark", 0, before, len(idx)))
        # compact vertices
        used, inv = np.unique(idx.reshape(-1), return_inverse=True)
        idx = inv.reshape(-1, 3).astype(np.uint32)
        new_attr = {}
        for k, arr in attrs.items():
            sub = arr[used] if arr.ndim > 1 else arr[used]
            kind = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[sub.shape[1] if sub.ndim > 1 else 1]
            new_attr[k] = push(sub.astype(np.float32), 34962, kind)
        prim["attributes"] = new_attr
        prim["indices"] = push(idx.reshape(-1), 34963, "SCALAR", 5125)

g["accessors"] = new_accs
g["bufferViews"] = new_views
bin_name = os.path.splitext(os.path.basename(a.dst))[0] + ".bin"
g["buffers"] = [{"uri": bin_name, "byteLength": len(out_bin)}]
os.makedirs(os.path.dirname(os.path.abspath(a.dst)), exist_ok=True)
open(os.path.join(os.path.dirname(os.path.abspath(a.dst)), bin_name), "wb").write(out_bin)
json.dump(g, open(a.dst, "w"))
for s in stats:
    print("%-24s %-28s %-4s islands=%-7d tris %d -> %d" % s)
