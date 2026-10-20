#!/usr/bin/env python3
"""catalog_fill.py <catalog in> <catalog out>: fill every action catalog entry's times from the mocap.

Times are read off the clip's own landmarks (assets/animations/movelib/<id>.json, MediaPipe pose at the source's fps):
  start_s / end_s   where the motion starts and settles (limb speed above a quarter of the clip's busy level),
                    the actor's idle lead-in and settle cut; for the 38 gestures and ultimates GestureBook's from / to
                    (read off the sources at 10 fps on 20 October) are used instead
  gather_s          [a, b] casts and ultimates, from GestureBook
  release_s         casts and ultimates from GestureBook; strikes the fastest limb's speed peak
  contact_s         strikes: that limb's furthest reach within 0.25 s after the peak; contact behaviours: the leading
                    hand's stillest moment while reaching out (the hand resting on the target)
  lead_limb         the limb that strikes or touches (lh, rh, lf, rf)
Each filled entry gets "timing_from": "mocap" or "gesture_book". Status is left to the eye check and the scanner.
"""
import json, os, re, sys
import numpy as np

ROOT = '/home/selwyn/Downloads/Mika-Godot-Dev-Combat/'
LIMBS = {'lh': 15, 'rh': 16, 'lf': 27, 'rf': 28}


def gesture_book():
    src = open(ROOT + 'scripts/anime/combat/v3/gesture_book.gd').read()
    out = {}
    for m in re.finditer(r'"(\w+)": \{"from": ([\d.]+), "to": ([\d.]+), "speed": ([\d.]+), "gather": \[([\d.]+), ([\d.]+)\], "release": \[([\d., ]+)\], "hand": "(\w+)"', src):
        out[m.group(1)] = {'from': float(m.group(2)), 'to': float(m.group(3)), 'speed': float(m.group(4)),
                           'gather': [float(m.group(5)), float(m.group(6))], 'release': [float(x) for x in m.group(7).split(',')],
                           'hand': m.group(8)}
    return out


def fill(e, G):
    cid = e['id']
    p = ROOT + 'assets/animations/movelib/%s.json' % cid
    if not os.path.exists(p):
        e['timing_note'] = 'no mocap file'
        return
    d = json.load(open(p))
    P = np.array(d['frames'], dtype=float)
    fps = float(d['fps'])
    n = len(P)
    hips = (P[:, 23] + P[:, 24]) / 2
    sp = {k: np.linalg.norm(np.gradient(P[:, i], axis=0), axis=1) * fps for k, i in LIMBS.items()}
    energy = sum(sp.values())
    busy = np.percentile(energy, 90)
    on = np.where(energy > 0.25 * busy)[0]
    s0 = max(0.0, (on[0] / fps - 0.1)) if len(on) else 0.0
    s1 = min(n / fps, (on[-1] / fps + 0.15)) if len(on) else n / fps
    if cid in G:
        g = G[cid]
        e.update({'start_s': g['from'], 'end_s': g['to'], 'gather_s': g['gather'], 'release_s': g['release'],
                  'lead_limb': g['hand'], 'timing_from': 'gesture_book'})
        return
    e['start_s'] = round(s0, 2)
    e['end_s'] = round(s1, 2)
    e['timing_from'] = 'mocap'
    b = e.get('behaviour', '')
    i0, i1 = int(s0 * fps), max(int(s1 * fps), int(s0 * fps) + 1)
    if b in ('strike', 'strike_aerial', 'mischief_partner', 'partner') or e.get('contact') == 'opponent_hurtbox':
        # (a dash or a step makes the feet fastest: only kicks, stomps and sweeps strike with a foot)
        legs = any(w in cid for w in ('kick', 'stomp', 'sweep', 'knee'))
        cand = list(LIMBS) if legs else ['lh', 'rh']
        lead = max(cand, key=lambda k: sp[k][i0:i1].max())
        pk = i0 + int(np.argmax(sp[lead][i0:i1]))
        reach = np.linalg.norm(P[:, LIMBS[lead]] - hips, axis=1)
        w1 = min(n - 1, pk + int(0.25 * fps))
        ct = pk + int(np.argmax(reach[pk:w1 + 1]))
        e.update({'lead_limb': lead, 'release_s': [round(pk / fps, 2)], 'contact_s': round(ct / fps, 2)})
    elif b in ('contact_world', 'world_magic', 'social', 'mischief', 'prop', 'pose_loop', 'cast_hold'):
        hands = ['lh', 'rh']
        reach = {k: np.linalg.norm(P[:, LIMBS[k]] - hips, axis=1) for k in hands}
        lead = max(hands, key=lambda k: reach[k][i0:i1].max())
        r = reach[lead]
        ok = [i for i in range(i0, i1) if r[i] > 0.7 * r[i0:i1].max()]
        if ok:
            ct = min(ok, key=lambda i: sp[lead][i])
            e.update({'lead_limb': lead, 'contact_s': round(ct / fps, 2)})


def main():
    src, out = sys.argv[1:3]
    cat = json.load(open(src))
    G = gesture_book()
    for e in cat['clips']:
        fill(e, G)
    json.dump(cat, open(out, 'w'), indent=1)
    filled = sum(1 for e in cat['clips'] if 'timing_from' in e)
    print('filled %d of %d (%d from GestureBook)' % (filled, len(cat['clips']), sum(1 for e in cat['clips'] if e.get('timing_from') == 'gesture_book')))


if __name__ == '__main__':
    main()
