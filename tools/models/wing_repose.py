#!/usr/bin/env python3
"""Re-pose a VRM's feathered wings in their rest pose (mesh + wing bones + inverse binds), in place in the GLB.

The wings (meshes named *Wing_L / *Wing_R, bones J_Sec_WingL_0..2 / J_Sec_WingR_0..2 on the upper chest) are moved
rigidly about their root bone: a roll in the back view (arch up and outward), a sweep back behind her, then the root
is placed at a new point (the shoulder blades). Everything else is untouched: the wing bones keep their chain, the
colliders on them ride along, the other meshes are not moved, and the vertices partly weighted to the upper chest
(the attachment) stay consistent because the wing joints' inverse bind matrices are updated with the same transform.

  python3 tools/models/wing_repose.py <in.vrm> --info
  python3 tools/models/wing_repose.py <in.vrm> <out.vrm> --roll 28 --sweep 15 --root 0.11,1.31,-0.15

--roll / --sweep are degrees for her LEFT wing (+X; VRM faces +Z); the right wing is mirrored. --root is the new
left root position (metres, VRM space); the right one is mirrored. --bend rotates the outer wing (bone 1 onwards)
about the arch, in the back view, after the roll (+ = tips further in towards her legs).
"""
import argparse
import json
import math
import struct

import numpy as np


def load(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF"
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    bl = struct.unpack("<I", b[off:off + 4])[0]
    assert b[off + 4:off + 8] == b"BIN\x00"
    return j, bytearray(b[off + 8:off + 8 + bl])


def save(path, j, binb):
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binb = bytes(binb) + b"\x00" * ((4 - len(binb) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binb)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, total))
        f.write(struct.pack("<I", len(js)) + b"JSON" + js)
        f.write(struct.pack("<I", len(binb)) + b"BIN\x00" + binb)


COMP = {5126: ("f", 4), 5123: ("H", 2), 5121: ("B", 1), 5125: ("I", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def acc_view(j, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    c, sz = COMP[a["componentType"]]
    k = NCOMP[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or k * sz
    return a, c, sz, k, off, stride


def read(j, binb, i):
    a, c, sz, k, off, stride = acc_view(j, i)
    return np.array([struct.unpack_from("<" + c * k, binb, off + stride * t) for t in range(a["count"])], dtype=float)


def write(j, binb, i, arr):
    a, c, sz, k, off, stride = acc_view(j, i)
    assert c == "f"
    for t in range(a["count"]):
        struct.pack_into("<" + c * k, binb, off + stride * t, *arr[t])
    if "min" in a:
        a["min"] = arr.min(axis=0).tolist()
        a["max"] = arr.max(axis=0).tolist()


def local(nd):
    if "matrix" in nd:
        return np.array(nd["matrix"]).reshape(4, 4).T
    t = nd.get("translation", [0, 0, 0])
    x, y, z, w = nd.get("rotation", [0, 0, 0, 1])
    s = nd.get("scale", [1, 1, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4)
    M[:3, :3] = R * np.array(s)
    M[:3, 3] = t
    return M


def quat(R):
    tr = R[0, 0] + R[1, 1] + R[2, 2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        return [(R[2, 1] - R[1, 2]) / s, (R[0, 2] - R[2, 0]) / s, (R[1, 0] - R[0, 1]) / s, 0.25 * s]
    i = int(np.argmax([R[0, 0], R[1, 1], R[2, 2]]))
    if i == 0:
        s = math.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        return [0.25 * s, (R[0, 1] + R[1, 0]) / s, (R[0, 2] + R[2, 0]) / s, (R[2, 1] - R[1, 2]) / s]
    if i == 1:
        s = math.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        return [(R[0, 1] + R[1, 0]) / s, 0.25 * s, (R[1, 2] + R[2, 1]) / s, (R[0, 2] - R[2, 0]) / s]
    s = math.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
    return [(R[0, 2] + R[2, 0]) / s, (R[1, 2] + R[2, 1]) / s, 0.25 * s, (R[1, 0] - R[0, 1]) / s]


def rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    x, y, z = axis
    R = np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                  [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                  [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])
    M = np.eye(4)
    M[:3, :3] = R
    return M


def trans(v):
    M = np.eye(4)
    M[:3, 3] = v
    return M


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--info", action="store_true")
    ap.add_argument("--roll", type=float, default=0.0)
    ap.add_argument("--sweep", type=float, default=0.0)
    ap.add_argument("--bend", type=float, default=0.0)
    ap.add_argument("--root", default="")
    a = ap.parse_args()
    j, binb = load(a.src)
    nodes = j["nodes"]
    names = [n.get("name", "") for n in nodes]
    parent = {}
    for i, n in enumerate(nodes):
        for ch in n.get("children", []):
            parent[ch] = i

    def world(i):
        M = local(nodes[i])
        while i in parent:
            i = parent[i]
            M = local(nodes[i]) @ M
        return M

    idx = {n: i for i, n in enumerate(names)}
    for nm in ["J_Bip_C_UpperChest", "J_Bip_C_Neck", "J_Bip_C_Head", "J_Bip_L_Shoulder", "J_Bip_L_UpperArm", "J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg",
               "J_Sec_WingL_0", "J_Sec_WingL_1", "J_Sec_WingL_2"]:
        if nm in idx:
            print(f"{nm:22s}", np.round(world(idx[nm])[:3, 3], 3))
    if a.info:
        for nm in ("Body", "L1_Armor", "L1_UnderArmor", "L1_Cape"):
            if nm in idx and "mesh" in nodes[idx[nm]]:
                P = read(j, binb, j["meshes"][nodes[idx[nm]]["mesh"]]["primitives"][0]["attributes"]["POSITION"])
                for lo, hi in ((1.18, 1.26), (1.26, 1.34), (1.34, 1.42)):
                    q = P[(P[:, 1] > lo) & (P[:, 1] < hi) & (np.abs(P[:, 0]) > 0.06) & (np.abs(P[:, 0]) < 0.16)]
                    if len(q):
                        print(f"{nm:14s} y {lo}-{hi}: back z {q[:, 2].min():.3f}")
        return
    skin = j["skins"][0]
    ibm = read(j, binb, skin["inverseBindMatrices"])
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        b0, b1 = idx[f"J_Sec_Wing{side}_0"], idx[f"J_Sec_Wing{side}_1"]
        W0 = world(b0)
        r0 = W0[:3, 3].copy()
        new_root = r0.copy()
        if a.root:
            x, y, z = (float(v) for v in a.root.split(","))
            new_root = np.array([x * sgn, y, z])
        # roll in the back view about +Z (VRM faces +Z): her left wing's top goes outward (+X) for a positive roll
        T = trans(new_root) @ rot((0, 1, 0), a.sweep * sgn) @ rot((0, 0, 1), -a.roll * sgn) @ trans(-r0)
        # the outer wing (bone 1 and its vertices' share) bends about the arch
        arch = world(b1)[:3, 3]
        Tb = trans(arch) @ rot((0, 0, 1), a.bend * sgn) @ trans(-arch) if a.bend else np.eye(4)
        wing_joints = [idx[f"J_Sec_Wing{side}_{k}"] for k in range(3)]
        outer = [idx[f"J_Sec_Wing{side}_1"], idx[f"J_Sec_Wing{side}_2"]]
        jpos = {jn: k for k, jn in enumerate(skin["joints"])}
        # vertices of the wing mesh: rigid T, plus the bend weighted by their share on the outer bones
        mi = idx[f"L1_Wing_{side}"]
        pr = j["meshes"][nodes[mi]["mesh"]]["primitives"][0]
        P = read(j, binb, pr["attributes"]["POSITION"])
        N = read(j, binb, pr["attributes"]["NORMAL"]) if "NORMAL" in pr["attributes"] else None
        Jn = read(j, binb, pr["attributes"]["JOINTS_0"]).astype(int) if False else None
        JA = j["accessors"][pr["attributes"]["JOINTS_0"]]
        jc = COMP[JA["componentType"]][0]
        aJ, cJ, szJ, kJ, offJ, stJ = acc_view(j, pr["attributes"]["JOINTS_0"])
        J = np.array([struct.unpack_from("<" + cJ * 4, binb, offJ + stJ * t) for t in range(aJ["count"])], dtype=int)
        aW, cW, szW, kW, offW, stW = acc_view(j, pr["attributes"]["WEIGHTS_0"])
        Wt = np.array([struct.unpack_from("<" + cW * 4, binb, offW + stW * t) for t in range(aW["count"])], dtype=float)
        if cW != "f":
            Wt /= 255.0 if cW == "B" else 65535.0
        outer_slots = {jpos[o] for o in outer}
        share = np.array([sum(w for jj, w in zip(Jr, Wr) if jj in outer_slots) for Jr, Wr in zip(J, Wt)])
        Pn = np.empty_like(P)
        Nn = np.empty_like(N) if N is not None else None
        for t in range(len(P)):
            M = T @ (np.eye(4) * (1 - share[t]) + Tb * share[t]) if a.bend else T
            Pn[t] = (M @ np.append(P[t], 1.0))[:3]
            if N is not None:
                v = M[:3, :3] @ N[t]
                Nn[t] = v / (np.linalg.norm(v) or 1.0)
        write(j, binb, pr["attributes"]["POSITION"], Pn)
        if N is not None:
            write(j, binb, pr["attributes"]["NORMAL"], Nn)
        # bones: root's local from its (unmoved) parent; the outer bones get the bend on top of T
        newW = {b0: T @ W0}
        newW[b1] = T @ Tb @ world(b1)
        b2 = idx[f"J_Sec_Wing{side}_2"]
        newW[b2] = T @ Tb @ world(b2)
        for bi in wing_joints:
            pw = world(parent[bi]) if parent[bi] not in newW else newW[parent[bi]]
            L = np.linalg.inv(pw) @ newW[bi]
            nodes[bi].pop("matrix", None)
            nodes[bi]["translation"] = L[:3, 3].tolist()
            nodes[bi]["rotation"] = quat(L[:3, :3] / np.linalg.norm(L[:3, :3], axis=0))
            nodes[bi].pop("scale", None)
            k = jpos[bi]
            ibm[k] = np.linalg.inv(newW[bi]).T.reshape(16)        # column-major
        print(side, "root", np.round(r0, 3), "->", np.round(newW[b0][:3, 3], 3), "arch", np.round(newW[b1][:3, 3], 3), "tip", np.round(newW[b2][:3, 3], 3))
        print("   mesh x", Pn[:, 0].min().round(3), Pn[:, 0].max().round(3), "y", Pn[:, 1].min().round(3), Pn[:, 1].max().round(3), "z", Pn[:, 2].min().round(3), Pn[:, 2].max().round(3))
    write(j, binb, skin["inverseBindMatrices"], ibm)
    save(a.dst, j, binb)
    print("wrote", a.dst)


main()
