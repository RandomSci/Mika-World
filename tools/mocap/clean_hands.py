# Move Library mocap, step 1c: the hand tracks made trustworthy before the bake (Selwyn, 2026-10-20, after the
# tremble root cause: swaps and flips while the hands overlap, snaps to the fallback when confidence drops).
#   1 swaps: each hand must stay closest to its OWN wrist track (where that hand was, moving as it moved). When the
#     two labels fit the other hand's track clearly better, they are exchanged for that frame.
#   2 unreliable frames: tracker confidence under 0.35, the two hands overlapping in the image (wrists closer than one
#     hand length, or their boxes intersecting by more than a third), or a palm that turns more than 45 degrees from
#     the last good frame in one frame (a flip).
#   3 holds: a run of unreliable frames up to 0.5 s between good frames is filled by interpolating each landmark in
#     the palm's own frame from the last good to the next good frame (the palm turned by slerp), weight kept at 1.
#   4 crossfades: longer runs fade to the bake's fallback hand shape over 0.2 s and back over 0.2 s (weight "w").
# Output <clip>.hands.clean.json beside the input: {"fps", "l", "r" (21 x [x,y,z] or null), "lw", "rw" (0..1),
# "stats"}. The One Euro filter on the baked finger rotations comes after, in MocapBake.clean.
#   python3 -I tools/mocap/clean_hands.py <clip.hands.json> [...]
import json
import math
import sys

import numpy as np

FADE_S = 0.2
HOLD_S = 0.5
QMIN = 0.35
FLIP_DEG = 45.0


def palm_frame(P):
    P = np.asarray(P)
    a = P[9] - P[0]
    c = P[5] - P[17]
    x = a / (np.linalg.norm(a) + 1e-9)
    z = c - x * np.dot(c, x)
    z /= np.linalg.norm(z) + 1e-9
    y = np.cross(z, x)
    return np.stack([x, y, z], 1)          # columns: palm axes


def rot_angle(A, B):
    R = A.T @ B
    return math.degrees(math.acos(max(-1.0, min(1.0, (np.trace(R) - 1) / 2))))


def slerp_mat(A, B, t):
    # rotation from A toward B by t (axis-angle on A^T B)
    R = A.T @ B
    ang = math.acos(max(-1.0, min(1.0, (np.trace(R) - 1) / 2)))
    if ang < 1e-6:
        return A
    ax = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * math.sin(ang))
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    a = ang * t
    Rt = np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K
    return A @ Rt


def clean(path):
    H = json.load(open(path))
    fps = float(H.get("fps", 30.0))
    n = int(H["total"])
    L = {s: list(H[s]) for s in "lr"}
    L2 = {s: list(H[s + "2d"]) for s in "lr"}
    Q = {s: list(H[s + "q"]) for s in "lr"}
    stats = {"swaps": 0, "unreliable": {"l": 0, "r": 0}, "held": {"l": 0, "r": 0}, "faded": {"l": 0, "r": 0}}
    # 1 swaps against each hand's own wrist track (a constant-velocity guess from the last two frames that had it)
    track = {"l": [], "r": []}
    for i in range(n):
        pred = {}
        for s in "lr":
            t = track[s]
            if len(t) >= 2:
                (i1, p1), (i2, p2) = t[-2], t[-1]
                v = (np.array(p2) - np.array(p1)) / max(i2 - i1, 1)
                pred[s] = np.array(p2) + v * min(i - i2, 3)
            elif t:
                pred[s] = np.array(t[-1][1])
        wl = np.array(L2["l"][i][0]) if L2["l"][i] else None
        wr = np.array(L2["r"][i][0]) if L2["r"][i] else None
        if wl is not None and wr is not None and "l" in pred and "r" in pred:
            keep = np.linalg.norm(wl - pred["l"]) + np.linalg.norm(wr - pred["r"])
            swap = np.linalg.norm(wl - pred["r"]) + np.linalg.norm(wr - pred["l"])
            if swap < keep * 0.6:
                for D in (L, L2, Q):
                    D["l"][i], D["r"][i] = D["r"][i], D["l"][i]
                stats["swaps"] += 1
        for s in "lr":
            if L2[s][i]:
                track[s].append((i, L2[s][i][0]))
    # 2 reliability per frame
    good = {s: [False] * n for s in "lr"}
    for i in range(n):
        over = False
        if L2["l"][i] and L2["r"][i]:
            pl, pr = np.array(L2["l"][i]), np.array(L2["r"][i])
            hand_len = max(np.linalg.norm(pl[0] - pl[12]), np.linalg.norm(pr[0] - pr[12]), 1.0)
            d = np.linalg.norm(pl[0] - pr[0])
            bl = (pl.min(0), pl.max(0))
            br = (pr.min(0), pr.max(0))
            inter = np.clip(np.minimum(bl[1], br[1]) - np.maximum(bl[0], br[0]), 0, None).prod()
            area = min((bl[1] - bl[0]).prod(), (br[1] - br[0]).prod()) + 1e-6
            over = d < hand_len or inter / area > 0.33
        for s in "lr":
            good[s][i] = L[s][i] is not None and float(Q[s][i]) >= QMIN and not over
    for s in "lr":
        last = None
        for i in range(n):
            if not good[s][i]:
                continue
            F = palm_frame(L[s][i])
            if last is not None and rot_angle(last[1], F) > FLIP_DEG * max(1, i - last[0]) ** 0.5:
                good[s][i] = False
                continue
            last = (i, F)
        stats["unreliable"][s] = n - sum(good[s])
    # 3 holds and 4 crossfades
    out = {"fps": fps, "src": H.get("src", ""), "total": n}
    hold_n = int(round(HOLD_S * fps))
    fade_n = max(1, int(round(FADE_S * fps)))
    for s in "lr":
        P = [np.array(p) if p is not None else None for p in L[s]]
        g = good[s]
        w = np.array([1.0 if g[i] else 0.0 for i in range(n)])
        res = [P[i] if g[i] else None for i in range(n)]
        i = 0
        while i < n:
            if g[i]:
                i += 1
                continue
            j = i
            while j < n and not g[j]:
                j += 1
            a, b = i - 1, j                      # last good before, next good after
            if a >= 0 and b < n and (j - i) <= hold_n:
                Fa, Fb = palm_frame(P[a]), palm_frame(P[b])
                La = (P[a] - P[a][0]) @ Fa           # landmarks in the palm's own frame
                Lb = (P[b] - P[b][0]) @ Fb
                for k in range(i, j):
                    t = (k - a) / float(b - a)
                    F = slerp_mat(Fa, Fb, t)
                    loc = La * (1 - t) + Lb * t
                    wrist = P[a][0] * (1 - t) + P[b][0] * t
                    res[k] = wrist + loc @ F.T
                    w[k] = 1.0
                stats["held"][s] += j - i
            else:
                # a long gap (or at the clip's ends): hold the nearest good pose for the shape, fade the weight out over
                # FADE_S after the last good frame and back in over FADE_S before the next one
                for k in range(i, j):
                    near = a if (a >= 0 and (b >= n or k - a <= b - k)) else b
                    res[k] = P[near] if (near is not None and 0 <= near < n and P[near] is not None) else None
                    wa = max(0.0, 1.0 - (k - a) / fade_n) if a >= 0 else 0.0
                    wb = max(0.0, 1.0 - (b - k) / fade_n) if b < n else 0.0
                    w[k] = max(wa, wb)
                    if res[k] is None:
                        w[k] = 0.0
                stats["faded"][s] += j - i
            i = j
        out[s] = [r.round(5).tolist() if r is not None else None for r in res]
        out[s + "w"] = [round(float(x), 3) for x in w]
    out["stats"] = stats
    dst = path.replace(".hands.json", ".hands.clean.json")
    json.dump(out, open(dst, "w"))
    return dst, stats


if __name__ == "__main__":
    for p in sys.argv[1:]:
        dst, st = clean(p)
        print("[clean_hands]", dst.split("/")[-1], json.dumps(st))
