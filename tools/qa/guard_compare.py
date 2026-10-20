#!/usr/bin/env python3
"""guard_compare.py <raw_dir> <guard_dir> <out_dir>: the body guard's before and after (Selwyn's step 6 shape).

Both dirs are `lab_render.sh guard_scan <dir> --girl=.. --clips=.. --framing=mid [--raw]` (lab.mp4 + log.txt with
"[guardscan] clip {json}"). Writes:
  table.md        per clip and rule, failing frames and worst value, raw against guarded
  <clip>.jpg      the clip's worst raw moment (its worst rule) at 10 fps, 0.3 s either side: raw on top, guarded below,
                  at the same clip times (movie frame = engine frame; a clip starts at its from_frame in each run)
"""
import json, os, re, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

CROP = (430, 60, 850, 640)


def load(d):
    out = {}
    for l in open(os.path.join(d, 'log.txt'), errors='replace'):
        m = re.search(r'\[guardscan\] clip (\{.*\})\s*$', l)
        if m:
            r = json.loads(m[1])
            out[r['clip']] = r
    return out


def frame(d, n, tmp):
    p = os.path.join(tmp, 'f.png')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', os.path.join(d, 'lab.mp4'), '-vf',
                    'select=eq(n\\,%d),scale=1280:720' % n, '-frames:v', '1', p], check=True)
    return Image.open(p).crop(CROP)


def main():
    raw_d, g_d, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    A, B = load(raw_d), load(g_d)
    rules = sorted({r for c in list(A.values()) + list(B.values()) for r in c['rules']})
    lines = ['| clip | rule | raw frames failing | raw worst | guarded frames failing | guarded worst |', '|---|---|---|---|---|---|']
    tot = [0, 0, 0, 0]
    for clip in A:
        a, b = A[clip], B.get(clip, {'rules': {}, 'frames': 0, 'failing': 0})
        tot[0] += a['failing']; tot[1] += a['frames']; tot[2] += b['failing']; tot[3] += b['frames']
        lines.append('| %s | all rules | %d of %d | | %d of %d | |' % (clip, a['failing'], a['frames'], b['failing'], b['frames']))
        for r in rules:
            ra, rb = a['rules'].get(r), b['rules'].get(r)
            if not ra and not rb:
                continue
            fmt = lambda x: ('%d' % x['n'], '%.3f m%s' % (x['worst'], (' into ' + x['into']) if x.get('into') else '') if r == 'penetration' else '%.0f deg' % x['worst']) if x else ('0', '')
            fa, fb = fmt(ra), fmt(rb)
            lines.append('| | %s | %s | %s | %s | %s |' % (r, fa[0], fa[1], fb[0], fb[1]))
    lines.append('| TOTAL | | %d of %d | | %d of %d | |' % tuple(tot))
    open(os.path.join(out, 'table.md'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 16)
    with tempfile.TemporaryDirectory() as tmp:
        for clip, a in A.items():
            if not a['rules'] or clip not in B:
                continue
            # the worst rule: penetration in cm counts as 10 deg per cm against the angles
            def score(kv):
                k, v = kv
                return v['worst'] * 1000 if k == 'penetration' else v['worst']
            rule, w = max(a['rules'].items(), key=score)
            t0 = w.get('t', 0.0)
            times = [round(t0 + k * 0.1, 1) for k in range(-3, 4)]
            cw, ch = CROP[2] - CROP[0], CROP[3] - CROP[1]
            sheet = Image.new('RGB', (cw * len(times), 2 * ch + 70), 'black')
            d = ImageDraw.Draw(sheet)
            d.text((6, 4), '%s  worst raw %s %.3f%s at %.1f s (10 fps)' % (clip, rule, w['worst'], ' m' if rule == 'penetration' else ' deg', t0), fill='white', font=font)
            for row, (dd, rec, lab) in enumerate([(raw_d, a, 'RAW, the clip as baked'), (g_d, B[clip], 'GUARDED, the full pose stack')]):
                y0 = 28 + row * (ch + 22)
                d.text((6, y0), lab, fill=(255, 220, 120), font=font)
                for c, tt in enumerate(times):
                    n = int(rec['from_frame'] + round(tt * 30))
                    if tt < 0 or n >= rec['to_frame']:
                        continue
                    sheet.paste(frame(dd, n, tmp), (c * cw, y0 + 20))
                    d.text((c * cw + 6, y0 + 24), '%.1f s' % tt, fill='white', font=font)
            sheet.save(os.path.join(out, clip + '.jpg'), quality=88)
            print('sheet', clip)


if __name__ == '__main__':
    main()
