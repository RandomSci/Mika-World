#!/usr/bin/env python3
"""Rebuild a VRM's feathered wings as anatomical bird wings, rigged for flight, from the wings' own feather art.

The design wing (L1_Wing_L / _R) is a static folded sculpture of ~450 small overlapping feather cards: it has no
flight feathers along the arm, so no rig can open it into a real wing. This tool keeps the art (each new feather is a
copy of one of those cards, with its shape, UVs and material) and lays the feathers out along a proper wing, in the
OPEN pose (the model's rest pose = the wing spread out to the side in the plane of her back):

  shoulder J_Sec_Wing{s}_0 (the existing root on the upper chest)
    -> elbow   J_Sec_Wing{s}_1 (the existing arch bone, moved; its hair/cape collider now runs along the forearm)
       -> wrist   J_Sec_Wing{s}_Wrist -> hand tip J_Sec_Wing{s}_HandTip
  feathers: 10 primaries J_Sec_Wing{s}_P0 (inner) .. P9 (outer tip) on the hand, 12 secondaries _S0 (at the body
  side) .. _S11 on the forearm, 3 tertials _T0.._T2 on the upper arm - one bone per feather, the card rigid on it
  coverts: 3 rows over the feather bases (greater, median, marginal) skinned smoothly to the arm bones (linear blends
  across the elbow and the wrist) and half to the feather under them, so the surface bends without tearing
  root: the innermost coverts blend into the upper chest

  python3 tools/models/wing_build.py <in.vrm> <out.vrm> [--plot dir]

The wing controller (WingLayer) closes it into the design-sheet pose at rest on the ground, folds it, beats it.
"""
import argparse
import collections
import math
import struct

import numpy as np

exec(open(__file__.replace("wing_build.py", "wing_repose.py")).read().split("def main():")[0])


def append_view(j, binb, data, target=None):
    while len(binb) % 4:
        binb.append(0)
    off = len(binb)
    binb.extend(data)
    bv = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
    if target:
        bv["target"] = target
    j["bufferViews"].append(bv)
    return len(j["bufferViews"]) - 1


def append_accessor(j, binb, arr, ctype, atype, minmax=False, target=34962):
    fmt = {5126: "f", 5123: "H", 5125: "I"}[ctype]
    data = struct.pack("<" + fmt * arr.size, *arr.reshape(-1).tolist())
    bv = append_view(j, binb, data, target)
    a = {"bufferView": bv, "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
    if minmax:
        a["min"] = arr.min(axis=0).tolist()
        a["max"] = arr.max(axis=0).tolist()
    j["accessors"].append(a)
    return len(j["accessors"]) - 1


# ---------------------------------------------------------------------------------------------- the layout (left)
# metres, VRM space (she faces +Z, her left is +X). The wing plane is a little behind her back.
Z0 = -0.175
SHOULDER = np.array([0.10, 1.30, -0.155])
ELBOW = np.array([0.53, 1.40, Z0])
WRIST = np.array([0.93, 1.43, Z0])
TIP = np.array([1.17, 1.42, Z0])
N_PRIM, N_SEC, N_TERT = 10, 12, 3


def ang(deg):
    a = math.radians(deg)
    return np.array([math.cos(a), math.sin(a), 0.0])


def layout():
    """[(kind, index, base, direction, length, bone name, z offset)] for one (left) wing, open."""
    f = []
    # primaries: on the hand, P0 at the wrist (pointing down-out) .. P9 at the tip (pointing out, a little up)
    for i in range(N_PRIM):
        t = i / (N_PRIM - 1)
        base = WRIST + (TIP - WRIST) * (0.05 + 0.9 * t)
        f.append(("P", i, base, ang(-78 + 82 * t ** 0.85), 0.44 + 0.13 * t, "P%d" % i, 0.000 + 0.0015 * i))
    # secondaries: along the forearm, hanging down and a little out
    for i in range(N_SEC):
        t = i / (N_SEC - 1)
        base = ELBOW + (WRIST - ELBOW) * (0.02 + 0.98 * t)
        f.append(("S", i, base, ang(-96 + 10 * t), 0.44, "S%d" % i, -0.0015 * i))
    # tertials: on the upper arm next to the body, hanging down
    for i in range(N_TERT):
        t = i / max(N_TERT - 1, 1)
        base = SHOULDER + (ELBOW - SHOULDER) * (0.35 + 0.55 * t)
        base[2] = Z0 + 0.004
        f.append(("T", i, base, ang(-104 + 4 * t), 0.37 - 0.04 * (1 - t), "T%d" % i, 0.004))
    # coverts: greater (over the flight feathers' bases), median, marginal (the leading edge) - along shoulder -> tip
    line = [SHOULDER, ELBOW, WRIST, TIP]
    seglen = [np.linalg.norm(line[k + 1] - line[k]) for k in range(3)]
    total = sum(seglen)

    def along(s):
        for k in range(3):
            if s <= seglen[k] or k == 2:
                return line[k] + (line[k + 1] - line[k]) * min(s / seglen[k], 1.0), k
            s -= seglen[k]
    rows = [("G", 20, 0.09, 0.21, -0.010, -90), ("M", 24, 0.045, 0.13, -0.018, -78), ("L", 28, 0.012, 0.08, -0.026, -60)]
    for kind, n, drop, length, dz, d0 in rows:
        for i in range(n):
            s = total * (0.04 + 0.94 * i / (n - 1))
            p, k = along(s)
            base = p + np.array([0, -drop, 0])
            base[2] = Z0 + dz
            # the coverts lie along their feathers: down near the body, out towards the tip
            dirdeg = d0 + (90 + d0) * 0.0 + (60 if kind != "L" else 40) * (s / total) ** 1.5
            f.append((kind, i, base, ang(dirdeg), length * (1.0 - 0.25 * (s / total)), None, dz))
    return f


def covert_weights(p, bones):
    """Smooth arm weights for a covert at p (x along the arm): shoulder / elbow / wrist with linear blends."""
    x = p[0]
    sh, el, wr = bones
    w = {}
    blend = 0.08
    if x < ELBOW[0] - blend:
        w[sh] = 1.0
    elif x < ELBOW[0] + blend:
        t = (x - (ELBOW[0] - blend)) / (2 * blend)
        w[sh] = 1 - t
        w[el] = t
    elif x < WRIST[0] - blend:
        w[el] = 1.0
    elif x < WRIST[0] + blend:
        t = (x - (WRIST[0] - blend)) / (2 * blend)
        w[el] = 1 - t
        w[wr] = t
    else:
        w[wr] = 1.0
    return w


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--plot", default="")
    a = ap.parse_args()
    j, binb = load(a.src)
    nodes = j["nodes"]
    names = [n.get("name", "") for n in nodes]
    idx = {n: i for i, n in enumerate(names)}
    assert "J_Sec_WingL_Wrist" not in idx, "already built"
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}

    def world(i):
        M = local(nodes[i])
        while i in parent:
            i = parent[i]
            M = local(nodes[i]) @ M
        return M

    skin = j["skins"][0]
    joints = list(skin["joints"])
    ibm = [m for m in read(j, binb, skin["inverseBindMatrices"])]
    chest = idx["J_Bip_C_UpperChest"]
    plots = []
    rng = np.random.default_rng(7)
    for side, sx in (("L", 1.0), ("R", -1.0)):
        mir = np.diag([sx, 1.0, 1.0])
        b0, b1, b2 = (idx[f"J_Sec_Wing{side}_{k}"] for k in range(3))
        mi = idx[f"L1_Wing_{side}"]
        pr = j["meshes"][nodes[mi]["mesh"]]["primitives"][0]
        P = read(j, binb, pr["attributes"]["POSITION"])
        N = read(j, binb, pr["attributes"]["NORMAL"])
        UV = read(j, binb, pr["attributes"]["TEXCOORD_0"])
        I = read(j, binb, pr["indices"]).astype(int).reshape(-1, 3)
        # the feather cards of the design wing, each with its own frame: along (base -> tip), across, normal
        par = list(range(len(P)))

        def f(x):
            while par[x] != x:
                par[x] = par[par[x]]
                x = par[x]
            return x
        for t0, t1, t2 in I:
            for u, v in ((t0, t1), (t1, t2)):
                ru, rv = f(u), f(v)
                if ru != rv:
                    par[ru] = rv
        comp = np.array([f(i) for i in range(len(P))])
        tri_of = collections.defaultdict(list)
        for t in I:
            tri_of[comp[t[0]]].append(t)
        cards = []
        for c, tris in tri_of.items():
            vs = np.unique(np.array(tris).reshape(-1))
            q = P[vs]
            m = q.mean(0)
            _, sv, vt = np.linalg.svd(q - m, full_matrices=False)
            ax, ac, an = vt[0], vt[1], vt[2]
            L = (q - m) @ ax
            # the quill end: the one nearer the arch (the design wing hangs from its arch)
            hi_end = m + ax * L.max()
            lo_end = m + ax * L.min()
            if hi_end[1] < lo_end[1]:
                ax = -ax
                L = -L
            base = m + ax * L.min()
            ln = L.max() - L.min()
            wd = np.ptp((q - m) @ ac)
            if np.dot(np.cross(ax, ac), an) < 0:
                an = -an
            remap = {v: k for k, v in enumerate(vs)}
            loc = np.stack([(q - base) @ ax, (q - base) @ ac, (q - base) @ an], axis=1)
            nl = np.stack([N[vs] @ ax, N[vs] @ ac, N[vs] @ an], axis=1)
            cards.append({"len": ln, "wd": wd, "loc": loc, "nl": nl, "uv": UV[vs], "tri": np.array([[remap[x] for x in t] for t in tris])})
        long_ = sorted([c for c in cards if c["len"] > 0.22 and c["wd"] < 0.15], key=lambda c: -c["len"])
        mid = [c for c in cards if 0.12 < c["len"] <= 0.30 and c["wd"] < 0.14]
        short = [c for c in cards if 0.05 < c["len"] <= 0.14]
        print(side, "templates: long", len(long_), "mid", len(mid), "short", len(short))
        # bones (world, open pose): elbow = the old arch bone moved; wrist, hand tip and one per feather new
        lay = layout()
        newb = []
        newb.append((f"J_Sec_Wing{side}_Wrist", b1, mir @ WRIST))
        newb.append((f"J_Sec_Wing{side}_HandTip", f"J_Sec_Wing{side}_Wrist", mir @ TIP))
        for kind, i, base, d, ln, bname, dz in lay:
            if bname:
                par_b = {"P": f"J_Sec_Wing{side}_Wrist", "S": b1, "T": b0}[kind]
                newb.append((f"J_Sec_Wing{side}_{bname}", par_b, mir @ base))
        worldM = {}
        # the shoulder keeps its rest; the elbow (old arch bone) moves to the elbow, +Y along the forearm (its collider)
        fdir = mir @ (TIP - ELBOW)
        fdir /= np.linalg.norm(fdir)
        yx = fdir
        zx = np.array([0, 0, 1.0])
        xx = np.cross(yx, zx)
        xx /= np.linalg.norm(xx)
        zx = np.cross(xx, yx)
        Me = np.eye(4)
        Me[:3, :3] = np.stack([xx, yx, zx], axis=1)
        Me[:3, 3] = mir @ ELBOW
        worldM[b1] = Me
        Mw = np.eye(4)
        Mw[:3, :3] = Me[:3, :3]
        Mw[:3, 3] = mir @ WRIST
        worldM[b2] = Mw
        for nm, pnode, pos in newb:
            nodes.append({"name": nm})
            ni = len(nodes) - 1
            idx[nm] = ni
            names.append(nm)
            M = np.eye(4)
            M[:3, 3] = pos
            worldM[ni] = M
        # hierarchy: _1 under _0 (already), _2 under _1 (already), new bones under their parents
        for nm, pnode, pos in newb:
            pi = pnode if isinstance(pnode, int) else idx[pnode]
            nodes[pi].setdefault("children", []).append(idx[nm])
        par_of = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
        for ni, M in worldM.items():
            pi = par_of[ni]
            PW = worldM[pi] if pi in worldM else world(pi)
            Lm = np.linalg.inv(PW) @ M
            nodes[ni].pop("matrix", None)
            nodes[ni].pop("scale", None)
            nodes[ni]["translation"] = Lm[:3, 3].tolist()
            nodes[ni]["rotation"] = quat(Lm[:3, :3] / np.linalg.norm(Lm[:3, :3], axis=0))
        slot = {jn: k for k, jn in enumerate(joints)}
        for ni, M in worldM.items():
            if ni in slot:
                ibm[slot[ni]] = np.linalg.inv(M).T.reshape(16)
            else:
                joints.append(ni)
                ibm.append(np.linalg.inv(M).T.reshape(16))
                slot[ni] = len(joints) - 1
        wrist = idx[f"J_Sec_Wing{side}_Wrist"]
        # geometry
        VP, VN, VU, VJ, VW, IDX = [], [], [], [], [], []
        used = collections.Counter()

        def pick(pool, ln):
            # the template closest in length, preferring ones used least (variety)
            best = min(range(len(pool)), key=lambda k: abs(pool[k]["len"] - ln) / ln + 0.08 * used[(id(pool), k)] + rng.random() * 0.05)
            used[(id(pool), best)] += 1
            return pool[best]
        wing_n = np.array([0, 0, -1.0])               # the open wing's back (dorsal) side faces away from her back
        for kind, i, base, d, ln, bname, dz in lay:
            pool = long_ if kind == "P" else (mid if kind in "STG" else short)
            if kind == "G":
                pool = mid if len(mid) > 10 else short
            c = pick(pool, ln)
            sc = ln / c["len"]
            across = np.cross(wing_n, d)
            across /= np.linalg.norm(across)
            R = np.stack([d, across, wing_n], axis=1)       # columns: along, across, normal
            loc = c["loc"] * np.array([sc, sc * (1.0 if kind in "PST" else 1.15), 0.6])
            pts = loc @ R.T + base
            nrm = c["nl"] @ R.T
            pts = pts @ mir.T
            nrm = nrm @ mir.T
            start = len(VP)
            VP.extend(pts)
            VN.extend(nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6))
            VU.extend(c["uv"])
            tri = c["tri"] + start
            if sx < 0:
                tri = tri[:, [0, 2, 1]]
            IDX.extend(tri)
            if bname:
                fb = slot[idx[f"J_Sec_Wing{side}_{bname}"]]
                for p in pts:
                    VJ.append([fb, 0, 0, 0])
                    VW.append([1.0, 0, 0, 0])
            else:
                # covert: smooth along the arm; half on the flight feather under it (so fans keep them covered)
                for p in pts:
                    pl = mir @ p
                    w = covert_weights(pl, (slot[b0], slot[b1], slot[wrist]))
                    if kind == "G":
                        under = min((e for e in lay if e[5]), key=lambda e: np.linalg.norm(e[2] - pl))
                        fb = slot[idx[f"J_Sec_Wing{side}_{under[5]}"]]
                        w = {k: v * 0.5 for k, v in w.items()}
                        w[fb] = w.get(fb, 0) + 0.5
                    if np.linalg.norm(pl - SHOULDER) < 0.09:
                        k = 1.0 - np.linalg.norm(pl - SHOULDER) / 0.09
                        w = {kk: v * (1 - 0.6 * k) for kk, v in w.items()}
                        w[slot[chest]] = w.get(slot[chest], 0) + 0.6 * k
                    items = sorted(w.items(), key=lambda kv: -kv[1])[:4]
                    tot = sum(v for _, v in items)
                    VJ.append([k for k, _ in items] + [0] * (4 - len(items)))
                    VW.append([v / tot for _, v in items] + [0.0] * (4 - len(items)))
        VP = np.array(VP, dtype=np.float32)
        newp = {
            "attributes": {
                "POSITION": append_accessor(j, binb, VP, 5126, "VEC3", minmax=True),
                "NORMAL": append_accessor(j, binb, np.array(VN, dtype=np.float32), 5126, "VEC3"),
                "TEXCOORD_0": append_accessor(j, binb, np.array(VU, dtype=np.float32), 5126, "VEC2"),
                "JOINTS_0": append_accessor(j, binb, np.array(VJ, dtype=np.uint16), 5123, "VEC4"),
                "WEIGHTS_0": append_accessor(j, binb, np.array(VW, dtype=np.float32), 5126, "VEC4"),
            },
            "indices": append_accessor(j, binb, np.array(IDX, dtype=np.uint32).reshape(-1), 5125, "SCALAR", target=34963),
            "material": pr["material"],
            "mode": 4,
        }
        j["meshes"][nodes[mi]["mesh"]]["primitives"] = [newp]
        print(side, "feathers", len(lay), "verts", len(VP), "tris", len(IDX), "span to tip", round(float(abs(VP[:, 0]).max()), 2))
        plots.append((side, VP, np.array(VJ)[:, 0]))
    skin["joints"] = joints
    skin["inverseBindMatrices"] = append_accessor(j, binb, np.array(ibm, dtype=np.float32), 5126, "MAT4", target=None)
    j["buffers"][0]["byteLength"] = len(binb)
    save(a.dst, j, binb)
    print("wrote", a.dst, "joints", len(joints))
    if a.plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(2, 1, figsize=(16, 10))
        for side, VP, J in plots:
            ax[0].scatter(VP[:, 0], VP[:, 1], s=0.5, c=J % 20, cmap="tab20")
            ax[1].scatter(VP[:, 0], VP[:, 2], s=0.5, c=J % 20, cmap="tab20")
        for x in ax:
            x.set_aspect("equal")
            x.grid(alpha=0.3)
        ax[0].set_title("rebuilt wings, open (rest) - front view")
        ax[1].set_title("top view (z up = her front)")
        plt.savefig(a.plot + "/wing_build.png", dpi=60, bbox_inches="tight")


main()
