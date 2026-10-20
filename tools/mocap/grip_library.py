#!/usr/bin/env python3
"""grip_library.py <dir of extract_grip.py json> <out grip_library.json>

Grip library, step 2 (2026-10-20, Grip_Library_v1): from the real hands, per grip
  fingers      each joint's flexion (deg, proximal / intermediate / distal; the thumb's metacarpal / proximal / distal),
               the median over the frames where the hand holds the weapon (MediaPipe hand world landmarks)
  blade_angle  where the weapon leaves the fist: 0 = straight out of the thumb side across the hand, 90 = along the
               fingers (the image: the weapon's straight edge through the fist against the knuckle line and the
               hand's length, median over frames)
  spread_m     two hands: the distance between the fists along the handle (palm widths from the image, 8 cm a palm)
  close        grip_sword_close: the curl from an open hand to the full grip, 0 to 1, frame by frame
"""
import glob
import json
import math
import os
import sys

import numpy as np

FING = {"Index": [5, 6, 7, 8], "Middle": [9, 10, 11, 12], "Ring": [13, 14, 15, 16], "Little": [17, 18, 19, 20], "Thumb": [1, 2, 3, 4]}
GRIPS = {"rapier": ["grip_rapier_side", "grip_rapier_thrust", "grip_rapier_cut"], "sword": ["grip_sword_front"],
         "staff": ["grip_staff_two", "grip_staff_spin"], "longsword": ["grip_longsword_two"]}
PALM_M = 0.08


def ang(a, b):
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    return math.degrees(math.acos(np.clip(np.dot(a, b) / (na * nb + 1e-9), -1, 1)))


def flex(W):
    out = {}
    for f, ids in FING.items():
        base = W[0]
        p = [W[i] for i in ids]
        out[f] = [ang(p[0] - base, p[1] - p[0]), ang(p[1] - p[0], p[2] - p[1]), ang(p[2] - p[1], p[3] - p[2])]
    return out


def blade_angle(img, lines, hsize):
    I = np.array(img)
    c = I[[0, 5, 9, 13, 17]].mean(0)
    k = I[5] - I[17]
    k /= np.linalg.norm(k) + 1e-9
    l = I[9] - I[0]
    l /= np.linalg.norm(l) + 1e-9
    best = None
    for x1, y1, x2, y2, L in lines:
        a = np.array([x1, y1]); b = np.array([x2, y2])
        u = (b - a) / (np.linalg.norm(b - a) + 1e-9)
        d = abs(u[0] * (c - a)[1] - u[1] * (c - a)[0])
        if d > hsize * 0.9:
            continue
        if best is None or L > best[1]:
            best = (u, L, a, b)
    if best is None:
        return None
    u, L, a, b = best
    # the blade side: the end of the edge farther from the fist
    if np.linalg.norm(a - c) > np.linalg.norm(b - c):
        u = -u
    a = math.degrees(math.atan2(np.dot(u, l), np.dot(u, k)))
    # (a staff or a long handle looks the same from both ends in the image: folded to the thumb side's half)
    if a > 90.0:
        a -= 180.0
    elif a < -90.0:
        a += 180.0
    return a


def main():
    src, out = sys.argv[1], sys.argv[2]
    data = {os.path.basename(p)[:-5]: json.load(open(p)) for p in glob.glob(src + "/grip_*.json")}
    lib = {}
    for g, clips in GRIPS.items():
        fl = {f: [] for f in FING}
        ba = []
        spread = []
        for cn in clips:
            for fr in data[cn]["frames"]:
                hs = [h for h in fr["hands"] if h["score"] > 0.7]
                for h in hs:
                    F = flex(np.array(h["world"]))
                    # (an open hand, the longsword clip's 1.5 s: proximal joints under 25 deg, skipped)
                    if np.mean([F[f][0] for f in ["Index", "Middle", "Ring", "Little"]]) < 25:
                        continue
                    for f in FING:
                        fl[f].append(F[f])
                    I = np.array(h["img"])
                    hsize = np.linalg.norm(I[5] - I[17])
                    a = blade_angle(h["img"], fr["lines"], hsize)
                    if a is not None:
                        ba.append(a)
                if len(hs) == 2:
                    I0, I1 = np.array(hs[0]["img"]), np.array(hs[1]["img"])
                    pw = (np.linalg.norm(I0[5] - I0[17]) + np.linalg.norm(I1[5] - I1[17])) * 0.5
                    c0, c1 = I0[[0, 5, 9, 13, 17]].mean(0), I1[[0, 5, 9, 13, 17]].mean(0)
                    spread.append(np.linalg.norm(c0 - c1) / max(pw, 1e-6) * PALM_M)
        e = {"fingers": {f: [round(float(v), 1) for v in np.median(np.array(fl[f]), 0)] for f in FING if fl[f]},
             "blade_angle": round(float(np.median(ba)), 1) if ba else None, "blade_angle_iqr": [round(float(np.percentile(ba, 25)), 1), round(float(np.percentile(ba, 75)), 1)] if ba else None,
             "samples": len(fl["Index"]), "angle_samples": len(ba)}
        if spread:
            e["spread_m"] = round(float(np.median(spread)), 3)
        lib[g] = e
        print(g, json.dumps(e))
    # the closing hand, open to full grip
    cl = []
    for fr in data["grip_sword_close"]["frames"]:
        hs = [h for h in fr["hands"] if h["score"] > 0.7]
        if hs:
            F = flex(np.array(hs[0]["world"]))
            cl.append(round(float(np.mean([F[f][0] + F[f][1] for f in ["Index", "Middle", "Ring", "Little"]])), 1))
    lib["close"] = {"fps": data["grip_sword_close"]["fps"], "curl_sum_deg": cl}
    lib["_note"] = "Grip_Library_v1 (2026-10-20): real hands, MediaPipe Hands; tools/mocap/extract_grip.py + grip_library.py"
    json.dump(lib, open(out, "w"), indent=1)


if __name__ == "__main__":
    main()
