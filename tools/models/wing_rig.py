#!/usr/bin/env python3
"""Give a VRM's feathered wings a real bird-wing rig, in place in the GLB, so they can spread, bend and fold.

Before: each wing had a root, one arch bone and one tip bone, so it could only tilt as a rigid board. The sheet pose
is a folded wing: the arm rises from the shoulder blade to the arch (the elbow), the forearm and hand hang down from
there and the flight feathers run down that hanging blade. After, per wing:

  J_Sec_Wing{s}_0         shoulder (the existing root on the upper chest; keeps its colliders)
  J_Sec_Wing{s}_1         elbow (the existing arch bone; keeps its collider)
  J_Sec_Wing{s}_Wrist     WRIST_T of the way down the blade (forearm = arch -> wrist, hand = wrist -> tip)
  J_Sec_Wing{s}_HandTip   the primary tip (not weighted; gives the hand its direction)
  J_Sec_Wing{s}_F0..F9    flight-feather groups by where their base sits along the blade (F0 at the elbow ..
                          F9 near the tip): F0..F4 on the forearm (secondaries), F5..F9 on the hand (primaries)
  (J_Sec_Wing{s}_2, the old tip bone, stays as an unweighted child of the elbow)

The wing mesh is ~400-500 separate feather cards. Each card is classified from the rest geometry (its long axis,
which end is its base, where the base sits along shoulder -> arch -> tip) and skinned rigidly to one bone (coverts
on the arm to the shoulder or elbow, flight feathers to their group), so fanning and bending never stretches a
feather. The vertices near the root keep their original weights (the attachment on the upper chest). New bones have
identity world rotation; their inverse binds are written; the wing primitives get new 16-bit JOINTS_0 / float
WEIGHTS_0 accessors (the skin has more than 255 joints now). Nothing else changes.

  python3 tools/models/wing_rig.py <in.vrm> <out.vrm> [--plot dir]
"""
import argparse
import collections
import json
import struct

import numpy as np

exec(open(__file__.replace("wing_rig.py", "wing_repose.py")).read().split("def main():")[0])

N_GROUPS = 10
WRIST_T = 0.45


def append_view(j, binb, data: bytes, target=None):
    while len(binb) % 4:
        binb.append(0)
    off = len(binb)
    binb.extend(data)
    bv = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
    if target:
        bv["target"] = target
    j["bufferViews"].append(bv)
    return len(j["bufferViews"]) - 1


def append_accessor(j, binb, arr, ctype, atype, minmax=False):
    fmt = {5126: "f", 5123: "H"}[ctype]
    data = struct.pack("<" + fmt * arr.size, *arr.reshape(-1).tolist())
    bv = append_view(j, binb, data, 34962 if atype != "MAT4" else None)
    a = {"bufferView": bv, "componentType": ctype, "count": int(arr.shape[0]), "type": atype}
    if minmax:
        a["min"] = arr.min(axis=0).tolist()
        a["max"] = arr.max(axis=0).tolist()
    j["accessors"].append(a)
    return len(j["accessors"]) - 1


def seg_param(p, poly, cum):
    """Arc-length parameter and distance of p's closest point on the polyline."""
    best = (1e9, 0.0)
    for k in range(len(poly) - 1):
        a, b = poly[k], poly[k + 1]
        ab = b - a
        t = np.clip(np.dot(p - a, ab) / np.dot(ab, ab), 0, 1)
        d = np.linalg.norm(p - (a + ab * t))
        if d < best[0]:
            best = (d, cum[k] + t * np.linalg.norm(ab))
    return best[1], best[0]


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
    assert "J_Sec_WingL_Wrist" not in idx and "J_Sec_WingL_Elbow" not in idx, "already rigged"
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}

    def world(i):
        M = local(nodes[i])
        while i in parent:
            i = parent[i]
            M = local(nodes[i]) @ M
        return M

    skin = j["skins"][0]
    joints = list(skin["joints"])
    ibm = read(j, binb, skin["inverseBindMatrices"])
    new_ibm = [m for m in ibm]
    plots = []
    for side in ("L", "R"):
        b0, b1, b2 = (idx[f"J_Sec_Wing{side}_{k}"] for k in range(3))
        S = world(b0)[:3, 3]
        W = world(b1)[:3, 3]
        mi = idx[f"L1_Wing_{side}"]
        pr = j["meshes"][nodes[mi]["mesh"]]["primitives"][0]
        P = read(j, binb, pr["attributes"]["POSITION"])
        I = read(j, binb, pr["indices"]).astype(int).reshape(-1, 3)
        aJ, cJ, szJ, kJ, offJ, stJ = acc_view(j, pr["attributes"]["JOINTS_0"])
        J0 = np.array([struct.unpack_from("<" + cJ * 4, binb, offJ + stJ * t) for t in range(aJ["count"])], dtype=int)
        W0 = read(j, binb, pr["attributes"]["WEIGHTS_0"])
        # the arch (elbow) and the primary tip: the vertex farthest from the arch
        A = W
        H = P[np.argmax(np.linalg.norm(P - A, axis=1))]
        Wr = A + (H - A) * WRIST_T
        poly = [S, A, H]
        cum = [0.0, np.linalg.norm(A - S), np.linalg.norm(A - S) + np.linalg.norm(H - A)]
        sA = cum[1]
        blade_dir = (H - A) / np.linalg.norm(H - A)
        # feather cards (connected components)
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
        cards = collections.defaultdict(list)
        for i, c in enumerate(comp):
            cards[c].append(i)
        info = {}
        for c, vs in cards.items():
            q = P[vs]
            m = q.mean(0)
            ax = np.linalg.svd(q - m, full_matrices=False)[2][0] if len(vs) >= 3 else blade_dir
            L = (q - m) @ ax
            ea, eb = m + ax * L.min(), m + ax * L.max()
            sa, da = seg_param(ea, poly, cum)
            sb, db = seg_param(eb, poly, cum)
            # flight feathers run down the blade: their base is the end nearer the arch
            base, sbase = (ea, sa) if sa < sb else (eb, sb)
            info[c] = {"base": base, "s": sbase, "d": seg_param(base, poly, cum)[1], "len": np.linalg.norm(eb - ea)}
        cov, fl = [], []
        for c, d in info.items():
            (cov if d["s"] < sA - 0.03 else fl).append(c)
        # groups by the base's position down the blade (0 = the arch .. 1 = the tip)
        tpos = {c: np.clip((info[c]["s"] - sA) / (cum[2] - sA), 0, 1) for c in fl}
        order = sorted(fl, key=lambda c: tpos[c])
        groups = [order[k * len(order) // N_GROUPS:(k + 1) * len(order) // N_GROUPS] for k in range(N_GROUPS)]
        new = []          # (name, parent node index or name, pos)
        new.append((f"J_Sec_Wing{side}_Wrist", b1, Wr))
        new.append((f"J_Sec_Wing{side}_HandTip", f"J_Sec_Wing{side}_Wrist", H))
        for k, g in enumerate(groups):
            pos = np.mean([info[c]["base"] for c in g], axis=0) if g else Wr
            on_hand = (np.mean([tpos[c] for c in g]) if g else 1.0) >= WRIST_T
            new.append((f"J_Sec_Wing{side}_F{k}", f"J_Sec_Wing{side}_Wrist" if on_hand else b1, pos))
        worldM = {}
        for nm, pnode, pos in new:
            nodes.append({"name": nm})
            ni = len(nodes) - 1
            idx[nm] = ni
            names.append(nm)
            M = np.eye(4)
            M[:3, 3] = pos
            worldM[ni] = M
        for nm, pnode, pos in new:
            pi = pnode if isinstance(pnode, int) else idx[pnode]
            nodes[pi].setdefault("children", []).append(idx[nm])
        par_of = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
        for ni, M in worldM.items():
            pi = par_of[ni]
            PW = worldM[pi] if pi in worldM else world(pi)
            Lm = np.linalg.inv(PW) @ M
            nodes[ni]["translation"] = Lm[:3, 3].tolist()
            nodes[ni]["rotation"] = quat(Lm[:3, :3])
        jslot = {}
        for ni, M in worldM.items():
            joints.append(ni)
            new_ibm.append(np.linalg.inv(M).T.reshape(16))
            jslot[ni] = len(joints) - 1
        slot = {jn: k for k, jn in enumerate(joints)}
        JN = np.zeros((len(P), 4), dtype=int)
        WN = np.zeros((len(P), 4), dtype=float)
        bone_of = {}
        for c in cov:
            bone_of[c] = b0 if info[c]["s"] < sA * 0.55 else b1
        for k, g in enumerate(groups):
            for c in g:
                bone_of[c] = idx[f"J_Sec_Wing{side}_F{k}"]
        keep = np.linalg.norm(P - S, axis=1) < 0.10
        for c, vs in cards.items():
            b = slot[bone_of.get(c, b0)]
            for v in vs:
                if keep[v]:
                    JN[v] = J0[v]
                    WN[v] = W0[v]
                else:
                    JN[v] = [b, 0, 0, 0]
                    WN[v] = [1.0, 0, 0, 0]
        pr["attributes"]["JOINTS_0"] = append_accessor(j, binb, JN.astype(np.uint16), 5123, "VEC4")
        pr["attributes"]["WEIGHTS_0"] = append_accessor(j, binb, WN.astype(np.float32), 5126, "VEC4")
        E = A
        cnt = collections.Counter(names[bone_of.get(c, b0)] for c in cards)
        print(side, "cards", len(cards), "flight", len(fl), "coverts", len(cov), "kept root verts", int(keep.sum()))
        print("   shoulder", np.round(S, 3), "elbow", np.round(A, 3), "wrist", np.round(Wr, 3), "tip", np.round(H, 3), "wing length", round(cum[2], 2))
        print("   cards per bone", dict(sorted(cnt.items())))
        plots.append((side, P, comp, bone_of, names, [S, A, Wr, H], {nm: worldM[idx[nm]][:3, 3] for nm, _, _ in new}))
    skin["joints"] = joints
    skin["inverseBindMatrices"] = append_accessor(j, binb, np.array(new_ibm, dtype=np.float32), 5126, "MAT4")
    j["buffers"][0]["byteLength"] = len(binb)
    save(a.dst, j, binb)
    print("wrote", a.dst, "joints", len(joints))
    if a.plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        fig, axs = plt.subplots(1, 2, figsize=(18, 9))
        for ax, (side, P, comp, bone_of, nm, chain, nb) in zip(axs, plots):
            keys = sorted(set(bone_of.values()))
            cmap = plt.cm.tab20(np.linspace(0, 1, len(keys)))
            col = {k: cmap[i] for i, k in enumerate(keys)}
            ax.scatter(P[:, 0], P[:, 1], s=0.4, c=[col.get(bone_of.get(c), (0.6, 0.6, 0.6, 1)) for c in comp])
            ch = np.array(chain)
            ax.plot(ch[:, 0], ch[:, 1], "k-o", lw=2)
            for k, v in nb.items():
                ax.annotate(k.split("_")[-1], (v[0], v[1]), fontsize=9)
            ax.set_aspect("equal")
            ax.set_title(f"wing {side}: cards coloured by bone (front view, x right)")
        plt.savefig(a.plot + "/wing_rig.png", dpi=60, bbox_inches="tight")


main()
