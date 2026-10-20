#!/usr/bin/env python3
"""catalog_strips.py <catalog.json> <out dir> [per sheet]: the eye check of the action catalog's times.

Each clip's SOURCE video at 10 fps from its start_s to its end_s (at most 40 frames, two rows of 20), one clip per
band, several clips per sheet. Frames at release_s are framed red, contact_s yellow, the gather window blue, so each
entry's times can be confirmed or corrected by eye against what the actor does."""
import glob, json, os, sys
import cv2
import numpy as np

MOVES = '/home/selwyn/Downloads/Mika-Project/moves'
TW, TH = 96, 128


def src_of(cid):
    for p in glob.glob(os.path.join(MOVES, '*', 'clips', cid + '.mp4')):
        return p
    return None


def tile(img, label, colour):
    if img is None:
        t = np.full((TH, TW, 3), 40, np.uint8)
    else:
        h, w = img.shape[:2]
        cw = min(w, int(h * TW / TH))
        x0 = (w - cw) // 2
        t = cv2.resize(img[:, x0:x0 + cw], (TW, TH), interpolation=cv2.INTER_AREA)
    if colour is not None:
        cv2.rectangle(t, (0, 0), (TW - 1, TH - 1), colour, 3)
    cv2.putText(t, label, (3, 11), cv2.FONT_HERSHEY_SIMPLEX, 0.36, (255, 255, 255), 1, cv2.LINE_AA)
    return t


def band(e):
    p = src_of(e['id'])
    cap = cv2.VideoCapture(p) if p else None
    s0, s1 = float(e.get('start_s', 0.0)), float(e.get('end_s', 4.0))
    times = [round(s0 + 0.1 * k, 1) for k in range(int((s1 - s0) / 0.1) + 1)][:40]
    rel = [round(float(x), 1) for x in (e.get('release_s') or [])]
    ct = round(float(e['contact_s']), 1) if e.get('contact_s') is not None else None
    g = e.get('gather_s')
    tiles = []
    for t in times:
        img = None
        if cap:
            cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000.0)
            ok, img = cap.read()
            img = img if ok else None
        col = None
        if g and float(g[0]) <= t <= float(g[1]):
            col = (255, 140, 0)
        if ct is not None and abs(t - ct) < 0.051:
            col = (0, 220, 255)
        if any(abs(t - r) < 0.051 for r in rel):
            col = (0, 0, 255)
        tiles.append(tile(img, '%.1f' % t, col))
    while len(tiles) % 20:
        tiles.append(np.zeros((TH, TW, 3), np.uint8))
    rows = [np.hstack(tiles[i:i + 20]) for i in range(0, len(tiles), 20)]
    head = np.zeros((22, TW * 20, 3), np.uint8)
    txt = '%s  %s  lead %s  start %.2f end %.2f  gather %s release %s contact %s  (%s)' % (
        e['id'], e.get('behaviour'), e.get('lead_limb'), s0, s1, g, e.get('release_s'), e.get('contact_s'), e.get('timing_from'))
    cv2.putText(head, txt, (4, 15), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (120, 220, 255), 1, cv2.LINE_AA)
    return np.vstack([head] + rows)


def main():
    cat = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    per = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    os.makedirs(out, exist_ok=True)
    clips = cat['clips']
    for i in range(0, len(clips), per):
        bands = [band(e) for e in clips[i:i + per]]
        cv2.imwrite(os.path.join(out, 'sheet_%03d.jpg' % (i // per)), np.vstack(bands), [cv2.IMWRITE_JPEG_QUALITY, 82])
    print('sheets', (len(clips) + per - 1) // per)


if __name__ == '__main__':
    main()
