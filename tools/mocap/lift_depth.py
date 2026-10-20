#!/usr/bin/env python3
# Move Library mocap, step 1b (2026-10-20, Selwyn's raw test: the girls stand upright with their arms in a T where the
# actor lunges with her sword arm straight out): MediaPipe's 3D world landmarks get the limbs' direction toward or away
# from the lens wrong (a bone's length swings up to 3x inside one clip, its direction across the image is 10 to 20 deg
# off what the camera sees), so a sword arm stretched across the frame comes out half pointed at the camera.
# This rebuilds every point from the 2D image instead, which the camera sees well:
#   across the image   the bone's direction and length as the image shows them (metres from one scale per clip)
#   toward the lens    only the length left over from the bone's fixed length, sqrt(L^2 - seen^2); its sign (toward
#                      or away) from MediaPipe's own depth, smoothed over time so it never flips frame to frame
#   fixed lengths      each bone one length per clip, the left and right sides equal
#   knees              a shin that would bend forward of the thigh takes the other depth sign
# Input: an extract_landmarks.py JSON that has "img" (re-extracted 2026-10-20). Output: the same JSON shape, hip-centred,
# in Godot's frame, so the bake reads it unchanged.
#   python3 -I tools/mocap/lift_depth.py <in.json> <out.json>
import json
import math
import sys

import numpy as np

# parent of each point (the chain the lengths hang on); -1 is the hips' middle
PARENT = {23: -1, 24: -1, 33: -1,                       # 33: the shoulders' middle (added)
          11: 33, 12: 33, 0: 33,
          13: 11, 15: 13, 17: 15, 19: 15, 21: 15,
          14: 12, 16: 14, 18: 16, 20: 16, 22: 16,
          25: 23, 27: 25, 29: 27, 31: 27,
          26: 24, 28: 26, 30: 28, 32: 28,
          1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 8: 0, 9: 0, 10: 0}
MIRROR = {11: 12, 13: 14, 15: 16, 17: 18, 19: 20, 21: 22, 23: 24, 25: 26, 27: 28, 29: 30, 31: 32, 1: 4, 2: 5, 3: 6,
          7: 8, 9: 10}
ORDER = [23, 24, 33, 11, 12, 0, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26, 27, 28, 29, 30, 31, 32,
         1, 2, 3, 4, 5, 6, 7, 8, 9, 10]


def gauss(x, sigma):
    """Gaussian over time (axis 0), edges held."""
    r = max(1, int(math.ceil(sigma * 3)))
    w = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    w /= w.sum()
    pad = np.concatenate([np.repeat(x[:1], r, 0), x, np.repeat(x[-1:], r, 0)], 0)
    return sum(w[i] * pad[i:i + len(x)] for i in range(2 * r + 1))


def with_mid(P):
    """33 points -> 34, the shoulders' middle appended."""
    return np.concatenate([P, (P[:, 11:12] + P[:, 12:13]) * 0.5], 1)


def main():
    src, out = sys.argv[1], sys.argv[2]
    d = json.load(open(src))
    if "img" not in d:
        sys.exit("no image landmarks in %s (re-extract with extract_landmarks.py)" % src)
    # both in MediaPipe's axes: x to the image right, y down, z away from the lens (the JSON's world is Godot's frame)
    W = np.array(d["frames"], float) * np.array([1.0, -1.0, -1.0])
    I = np.array(d["img"], float)
    W, I = with_mid(W), with_mid(I)
    n = len(W)
    root_w = (W[:, 23] + W[:, 24]) * 0.5
    root_i = (I[:, 23] + I[:, 24]) * 0.5
    # image -> metres: one scale per clip (a still camera, the actor about as far away all clip), MediaPipe's world
    # lengths over the big bones' longest views (a bone seen side on shows its whole length)
    seen = {}
    for c, p in PARENT.items():
        a = I[:, p, :2] if p >= 0 else root_i[:, :2]
        seen[c] = np.linalg.norm(I[:, c, :2] - a, axis=1)
    big = [25, 26, 27, 28, 13, 14, 15, 16, 33]
    ratios = []
    for c in big:
        p = PARENT[c]
        a = W[:, p] if p >= 0 else root_w
        ratios.append(float(np.percentile(np.linalg.norm(W[:, c] - a, axis=1), 75)) / max(float(np.percentile(seen[c], 97)), 1e-6))
    k = float(np.median(ratios))
    # fixed bone lengths (metres): each bone's longest view in the image (93rd percentile, so a few bad frames do not
    # set it), or MediaPipe's own length if the image never shows the bone side on; left and right the longer of the two
    L = {}
    for c, p in PARENT.items():
        a = W[:, p] if p >= 0 else root_w
        L[c] = max(float(np.percentile(seen[c], 93)) * k, float(np.percentile(np.linalg.norm(W[:, c] - a, axis=1), 50)))
    for a, b in MIRROR.items():
        L[a] = L[b] = max(L[a], L[b])
    # the depth sign of each bone: MediaPipe's world depth and its image depth together, smoothed over time. Where it
    # is unsure (its depth under a third of the bone), a forearm or shin takes its parent's sign: the straighter limb
    # (a near-straight arm otherwise bent 30 to 40 deg at the elbow by two noisy signs)
    sign, conf = {}, {}
    for c, p in PARENT.items():
        aw = W[:, p] if p >= 0 else root_w
        ai = I[:, p] if p >= 0 else root_i
        est = gauss(((W[:, c, 2] - aw[:, 2]) + 0.5 * k * (I[:, c, 2] - ai[:, 2]))[:, None], 3.0)[:, 0]
        sign[c] = np.where(est >= 0.0, 1.0, -1.0)
        conf[c] = np.abs(est) / L[c]
    for c in (15, 16, 27, 28):
        p = PARENT[c]
        sign[c] = np.where(conf[c] < 0.33, sign[p], sign[c])
    # a limb the image shows straight: the camera cannot tell where along the line its elbow / knee is (MediaPipe put
    # the sword arm's elbow a third of the way too near the shoulder, so the upper arm read short, took depth the
    # forearm did not, and a straight arm baked bent 40 deg). From 150 deg on (2D) the joint slides onto the line at the
    # bones' own ratio and both bones take the whole limb's depth sign: a straight limb stays straight
    straight = 0
    for a, j, b in [(11, 13, 15), (12, 14, 16), (23, 25, 27), (24, 26, 28)]:
        u = I[:, a, :2] - I[:, j, :2]
        v = I[:, b, :2] - I[:, j, :2]
        cosang = (u * v).sum(1) / (np.linalg.norm(u, axis=1) * np.linalg.norm(v, axis=1) + 1e-9)
        ang = np.degrees(np.arccos(np.clip(cosang, -1.0, 1.0)))
        w = np.clip((ang - 150.0) / 15.0, 0.0, 1.0)
        # (a knee bent toward the lens also looks straight in 2D: only when the image span is near the limb's whole
        # length, or MediaPipe's own 3D also calls it fairly straight)
        span = np.linalg.norm(I[:, b, :2] - I[:, a, :2], axis=1) * k / (L[j] + L[b])
        u3 = W[:, a] - W[:, j]
        v3 = W[:, b] - W[:, j]
        ang3 = np.degrees(np.arccos(np.clip((u3 * v3).sum(1) / (np.linalg.norm(u3, axis=1) * np.linalg.norm(v3, axis=1) + 1e-9), -1.0, 1.0)))
        w = w * np.maximum(np.clip((span - 0.85) / 0.1, 0.0, 1.0), np.clip((ang3 - 130.0) / 20.0, 0.0, 1.0))
        w = w * w * (3.0 - 2.0 * w)
        on_line = I[:, a, :2] + (I[:, b, :2] - I[:, a, :2]) * (L[j] / (L[j] + L[b]))
        I[:, j, :2] = I[:, j, :2] * (1.0 - w[:, None]) + on_line * w[:, None]
        whole = np.where(gauss(((W[:, b, 2] - W[:, a, 2]) + 0.5 * k * (I[:, b, 2] - I[:, a, 2]))[:, None], 3.0)[:, 0] >= 0.0, 1.0, -1.0)
        sign[j] = np.where(w > 0.5, whole, sign[j])
        sign[b] = np.where(w > 0.5, whole, sign[b])
        straight += int((w > 0.5).sum())
    out_p = np.zeros((n, 34, 3))
    over = 0
    for f in range(n):
        for c in ORDER:
            p = PARENT[c]
            base = out_p[f, p] if p >= 0 else np.zeros(3)
            ai = I[f, p, :2] if p >= 0 else root_i[f, :2]
            v = (I[f, c, :2] - ai) * k
            s = np.linalg.norm(v)
            if s > L[c]:
                over += 1
                v *= L[c] / s
                s = L[c]
            dz = math.sqrt(max(L[c] ** 2 - s ** 2, 0.0)) * sign[c][f]
            # a bone the image shows nearly whole lies nearly flat: its last 15 percent of length is 2D noise, not depth
            fr = s / L[c]
            if fr > 0.85:
                dz *= max(1.0 - fr, 0.0) / 0.15
            out_p[f, c] = base + np.array([v[0], v[1], dz])
    # knees: a shin bent forward of its thigh (seen from the hips' forward) takes the other depth sign
    flips = 0
    for f in range(n):
        hip_axis = out_p[f, 23] - out_p[f, 24]                  # her right -> left hip (MediaPipe: image right = her left)
        up = out_p[f, 33]
        fwd = np.cross(hip_axis, up)                            # her forward in MediaPipe's axes (toward the lens is -z)
        fwd /= np.linalg.norm(fwd) + 1e-9
        for hip, knee, ank, kids in [(23, 25, 27, (29, 31)), (24, 26, 28, (30, 32))]:
            th = out_p[f, knee] - out_p[f, hip]
            sh = out_p[f, ank] - out_p[f, knee]
            bend = sh / (np.linalg.norm(sh) + 1e-9) - th / (np.linalg.norm(th) + 1e-9)
            if np.dot(bend, fwd) > 0.15:
                alt = sh.copy()
                alt[2] = -alt[2]
                bend2 = alt / (np.linalg.norm(alt) + 1e-9) - th / (np.linalg.norm(th) + 1e-9)
                if np.dot(bend2, fwd) < np.dot(bend, fwd):
                    delta = alt - sh
                    out_p[f, ank] += delta
                    for kk in kids:
                        out_p[f, kk] += delta
                    flips += 1
    out_p = gauss(out_p, 1.2)
    frames = (out_p[:, :33] * np.array([1.0, -1.0, -1.0])).round(5).tolist()
    res = dict(d)
    res.pop("img", None)
    res["frames"] = frames
    res["lift"] = {"scale_m_per_img": round(k, 4), "clamped": over, "knee_flips": flips, "straight_limb_frames": straight,
                   "lengths": {str(c): round(v, 3) for c, v in L.items()}}
    json.dump(res, open(out, "w"))
    print("[lift] %s -> %s  scale %.3f m per image height, %d bones clamped, %d knee flips" % (src, out, k, over, flips))


if __name__ == "__main__":
    main()
