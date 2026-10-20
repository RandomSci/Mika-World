#!/usr/bin/env python3
"""jitter_report.py <log.txt> [label]: how much each girl trembles in a fight (melee_exchange --jitter-log).

Per bone (its final rotation in skeleton space, so turning her whole body does not count) and for her root (position
and yaw), every rendered frame. A tremble is motion that reverses direction from one frame to the next: the bone
turns one way, then back. Per bone:
  rev%    share of frames where it turns more than 0.5 deg AND the turn reverses the previous one (dot < 0)
  jit     mean size of the second difference of its rotation (deg per frame): high when it shakes, low on a smooth arc
  peak    the 95th percentile of the same
Root: position second difference (cm) and yaw second difference (deg). Prints one table per girl and the worst bones."""
import re, sys
import numpy as np

BONES = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg",
         "RightLowerLeg", "RightFoot"]


def qmul(a, b):
    x1, y1, z1, w1 = a.T
    x2, y2, z2, w2 = b.T
    return np.stack([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2], axis=1)


def rotvec(q):
    q = q * np.sign(q[:, 3:4] + 1e-12)
    v = q[:, :3]
    s = np.linalg.norm(v, axis=1)
    ang = 2 * np.arctan2(s, q[:, 3])
    return v / np.maximum(s, 1e-9)[:, None] * ang[:, None]


def main():
    path = sys.argv[1]
    label = sys.argv[2] if len(sys.argv) > 2 else ''
    data = {}
    for l in open(path, errors='replace'):
        m = re.match(r'\[jit\] (\w+) (\d+) (.*)$', l.strip())
        if m:
            data.setdefault(m[1], {})[int(m[2])] = list(map(float, m[3].split()))
    out = {}
    for who, fr in data.items():
        ks = sorted(fr)
        A = np.array([fr[k] for k in ks])
        if len(A) < 20:
            continue
        pos, yaw = A[:, 0:3], A[:, 3]
        d2p = np.linalg.norm(pos[2:] - 2 * pos[1:-1] + pos[:-2], axis=1) * 100
        dy = np.diff(np.unwrap(yaw))
        d2y = np.degrees(np.abs(np.diff(dy)))
        rows = []
        for i, b in enumerate(BONES):
            q = A[:, 4 + 4 * i: 8 + 4 * i]
            q = q / np.linalg.norm(q, axis=1)[:, None]
            # (continuity: flip signs so consecutive quaternions agree)
            for k in range(1, len(q)):
                if np.dot(q[k], q[k - 1]) < 0:
                    q[k] = -q[k]
            inv = q[:-1] * np.array([-1, -1, -1, 1])
            w = rotvec(qmul(q[1:], inv))                    # per frame step (rad)
            ang = np.degrees(np.linalg.norm(w, axis=1))
            d2 = np.degrees(np.linalg.norm(w[1:] - w[:-1], axis=1))
            rev = ((ang[1:] > 0.5) & ((w[1:] * w[:-1]).sum(1) < 0)).mean() * 100
            rows.append((b, rev, d2.mean(), np.percentile(d2, 95), ang.mean()))
        out[who] = rows
        print('== %s %s  frames %d  root jitter %.2f cm (p95 %.2f)  yaw jitter %.2f deg (p95 %.2f)' % (
            who, label, len(A), d2p.mean(), np.percentile(d2p, 95), d2y.mean(), np.percentile(d2y, 95)))
        print('%-15s %6s %7s %7s %7s' % ('bone', 'rev%', 'jit', 'p95', 'speed'))
        for r in rows:
            print('%-15s %6.1f %7.2f %7.2f %7.2f' % r)
    tot = [r for rs in out.values() for r in rs]
    if tot:
        print('MEAN rev%% %.1f  jit %.2f deg  (%s)' % (np.mean([r[1] for r in tot]), np.mean([r[2] for r in tot]), label))


if __name__ == '__main__':
    main()
