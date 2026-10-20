#!/usr/bin/env python3
"""hold_twice_sheet.py <before_dir> <after_dir> <out.jpg>: the frame to frame state proof (Selwyn's step 1).

Each dir holds lab.mp4 + log.txt of `lab_render.sh bake_share_probe <dir> --held` (Luna holds moments of orb_gather
with her own bake, Mika's, then her own again; "[bakeshare] held <which> <t> at frame N ... right hand (..) left hand
(..)"). The sheet shows, for the same five moments, the first hold and the second hold of the SAME bake, before the fix
and after it, with the hand distance between the two holds printed on each pair. Movie frame = engine frame (checked:
the last mark lands within the movie)."""
import re, subprocess, sys, tempfile, os
from PIL import Image, ImageDraw, ImageFont

TIMES = ['0.7', '1.3', '1.9', '2.5', '3.1']
W, H = 260, 360
CROP = (500, 110, 760, 470)          # 1280x720 frame, Luna's upper body in the mid shot


def marks(d):
    out = {}
    for l in open(os.path.join(d, 'log.txt'), errors='replace'):
        m = re.search(r'held (\w+) ([\d.]+) at frame (\d+) .*right hand \(([^)]*)\) left hand \(([^)]*)\)', l)
        if m:
            out[(m[1], m[2])] = (int(m[3]), tuple(map(float, m[4].split(','))), tuple(map(float, m[5].split(','))))
    return out


def frame(d, n, tmp):
    p = os.path.join(tmp, 'f.png')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', os.path.join(d, 'lab.mp4'), '-vf',
                    'select=eq(n\\,%d),scale=1280:720' % n, '-frames:v', '1', p], check=True)
    return Image.open(p).crop(CROP)


def dist(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5 * 100


def main():
    before, after, out = sys.argv[1:4]
    font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 17)
    small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 15)
    rows = [(before, 'own', 'BEFORE  first hold'), (before, 'own2', 'BEFORE  second hold, same bake, same moment'),
            (after, 'own', 'AFTER  first hold'), (after, 'own2', 'AFTER  second hold, same bake, same moment')]
    sheet = Image.new('RGB', (W * len(TIMES), 40 + len(rows) * (H + 28)), 'black')
    d = ImageDraw.Draw(sheet)
    d.text((8, 10), 'Luna orb_gather, every pose layer on, the same clip frame held twice (step 1 proof)', fill='white', font=font)
    M = {before: marks(before), after: marks(after)}
    with tempfile.TemporaryDirectory() as tmp:
        for r, (dd, which, label) in enumerate(rows):
            y0 = 40 + r * (H + 28)
            d.text((8, y0 + 4), label, fill=(255, 220, 120), font=font)
            for c, t in enumerate(TIMES):
                f, rh, lh = M[dd][(which, t)]
                sheet.paste(frame(dd, f, tmp), (c * W, y0 + 26))
                txt = t + ' s'
                if which == 'own2':
                    a = M[dd][('own', t)]
                    txt += '   hands moved %.1f cm' % max(dist(rh, a[1]), dist(lh, a[2]))
                d.text((c * W + 6, y0 + 30), txt, fill='white', font=small)
    sheet.save(out, quality=90)
    print(out, sheet.size)


if __name__ == '__main__':
    main()
