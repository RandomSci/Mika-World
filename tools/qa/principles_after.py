#!/usr/bin/env python3
"""principles_after.py <gesture_table run dir> [before metrics txt]: the animation principles check on the AFTER body.

The before baseline (Mika-Project review Before_20261020_principles) measured the source mocap landmarks. This one
measures her final pose in the game (gesture_table --trace: both hands' world positions and finger curl every frame,
each standing cast played through the gesture director with its trim, pace and blends), with the same five tests:
  anticipation   the hand draws back before it drives out at the release (2 cm or more against the release direction
                 within 1.2 s before it)
  ease in / out  the hand's speed in the first and last 0.1 s of the gesture under 0.6 m/s
  held sign      after the (last) release the hand holds still (under 0.15 m/s) at least 0.25 s
  fingers alive  the casting hand's fingers move: their summed curl changes by more than 2 deg within 0.3 s on at least
                 half of the gesture's frames
  timing         her pace 0.85 to 1.15 of the source (ultimates exactly the source)
Prints a table (one row per clip and girl) and the before verdicts beside it when the before file is given."""
import json, re, sys, os
import numpy as np


def load(run):
    tr, rows = {}, {}
    cur = {}
    for l in open(os.path.join(run, 'log.txt'), errors='replace'):
        m = re.match(r'\[gtrace\] (\S+) ([\d.\-]+) (.*)$', l.strip())
        if m:
            vals = list(map(float, m[3].split()))
            tr.setdefault(m[1], []).append([float(m[2])] + vals)
            continue
        m = re.search(r'\[gesture\] (\{.*\})', l)
        if m:
            r = json.loads(m[1])
            rows.setdefault(r['clip'], []).append(r)
    return tr, rows


def gesture_book():
    src = open('/home/selwyn/Downloads/Mika-Godot-Dev-Combat/scripts/anime/combat/v3/gesture_book.gd').read()
    G = {}
    for m in re.finditer(r'"(\w+)": \{"from": ([\d.]+), "to": ([\d.]+), "speed": ([\d.]+), "gather": \[([\d.]+), ([\d.]+)\], "release": \[([\d., ]+)\], "hand": "(\w+)"', src):
        G[m[1]] = dict(fr=float(m[2]), to=float(m[3]), sp=float(m[4]), rel=[float(x) for x in m[7].split(',')], hand=m[8])
    return G


def before(path):
    out = {}
    if not path or not os.path.exists(path):
        return out
    for l in open(path):
        p = l.split()
        if len(p) > 6 and p[0] != 'gesture':
            out[p[0]] = ' '.join(p[7:])
    return out


def main():
    run = sys.argv[1]
    B = before(sys.argv[2] if len(sys.argv) > 2 else '')
    tr, rows = load(run)
    G = gesture_book()
    print('%-26s %5s %6s %6s %6s %6s %6s  %-40s | before' % ('gesture', 'antic', 'in m/s', 'out', 'hold s', 'fing%', 'pace', 'fails'))
    total = fails_n = 0
    for clip, T in tr.items():
        if clip not in G:
            continue
        g = G[clip]
        A = np.array(T)
        t = A[:, 0]
        L, R = A[:, 1:4], A[:, 4:7]
        cl, cr = A[:, 7], A[:, 8]
        hand = (L + R) / 2 if g['hand'] == 'both' else (L if g['hand'] == 'lh' else R)
        curl = (cl + cr) / 2 if g['hand'] == 'both' else (cl if g['hand'] == 'lh' else cr)
        dt = np.gradient(t)
        dt[dt <= 1e-4] = 1e-4
        spd = np.linalg.norm(np.gradient(hand, axis=0), axis=1) / dt
        rr = rows.get(clip, [{}])[0]
        pace = float(rr.get('pace', g['sp']))
        k = g['sp'] / pace
        lead = float(rr.get('face_wait', 0.0)) + float(rr.get('plant_wait', 0.0))
        L_g = (g['to'] - g['fr']) / g['sp'] * k
        t0, t1 = lead, lead + L_g
        rel = lead + (g['rel'][-1] - g['fr']) / g['sp'] * k
        win = (t >= t0) & (t <= t1)
        if win.sum() < 6:
            continue
        ir = int(np.argmin(np.abs(t - rel)))
        a = int(np.argmin(np.abs(t - (rel - 0.3))))
        dvec = hand[ir] - hand[a]
        dvec = dvec / (np.linalg.norm(dvec) + 1e-6)
        proj = hand @ dvec
        back = proj[(t >= rel - 1.2) & (t <= rel - 0.3)]
        antic = len(back) > 3 and back.min() < proj[a] - 0.02
        sin = spd[(t >= t0) & (t <= t0 + 0.1)].mean()
        sout = spd[(t >= t1 - 0.1) & (t <= t1)].mean()
        run_, best = 0, 0
        for v, tt in zip(spd, t):
            if tt < rel or tt > t1:
                continue
            run_ = run_ + 1 if v < 0.15 else 0
            best = max(best, run_)
        hold = best * float(np.median(dt))
        alive = 0
        idx = np.where(win)[0]
        for i in idx:
            j = int(np.argmin(np.abs(t - (t[i] + 0.3))))
            if abs(curl[j] - curl[i]) > 2.0:
                alive += 1
        fing = 100.0 * alive / max(len(idx), 1)
        f = []
        if not antic: f.append('anticipation')
        if sin > 0.6 or sout > 0.6: f.append('ease in/out')
        if hold < 0.25: f.append('held final sign')
        if fing < 50: f.append('fingers frozen')
        ult = clip.startswith('ult_')
        if (ult and abs(pace - g['sp']) > 1e-3) or (not ult and not (0.85 <= pace <= 1.15)): f.append('timing')
        total += 1
        fails_n += 1 if f else 0
        print('%-26s %5s %6.2f %6.2f %6.2f %6.0f %6.2f  %-40s | %s' % (clip, 'yes' if antic else 'no', sin, sout, hold, fing, pace, ', '.join(f) or 'pass', B.get(clip, '')))
    print('%d gestures, %d pass every principle' % (total, total - fails_n))


if __name__ == '__main__':
    main()
