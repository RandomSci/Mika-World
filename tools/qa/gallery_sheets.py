#!/usr/bin/env python3
"""gallery_sheets.py <gallery run dir> <out dir> [per sheet]: the effect gallery as inspection sheets.

Reads "[gallery] <pack>/<name> dur D from frame A to frame B" from log.txt and lab.mp4 (movie frame = engine frame);
each effect becomes one row of four frames (15, 40, 65 and 90 percent of its time), its name on the row."""
import os, re, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

run, out = sys.argv[1:3]
per = int(sys.argv[3]) if len(sys.argv) > 3 else 8
os.makedirs(out, exist_ok=True)
rows = []
for l in open(os.path.join(run, 'log.txt'), errors='replace'):
    m = re.search(r'\[gallery\] (\S+) dur ([\d.]+) from frame (\d+) to frame (\d+)', l)
    if m:
        rows.append((m[1], int(m[3]), int(m[4])))
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 15)
W, H = 320, 180
with tempfile.TemporaryDirectory() as tmp:
    for si in range(0, len(rows), per):
        chunk = rows[si:si + per]
        sheet = Image.new('RGB', (W * 4, (H + 20) * len(chunk)), 'black')
        d = ImageDraw.Draw(sheet)
        for ri, (name, a, b) in enumerate(chunk):
            y = ri * (H + 20)
            d.text((4, y + 2), name, fill=(255, 220, 120), font=font)
            for ci, f in enumerate([0.15, 0.4, 0.65, 0.9]):
                n = int(a + (b - a) * f)
                p = os.path.join(tmp, 'f.png')
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', os.path.join(run, 'lab.mp4'), '-vf',
                                'select=eq(n\\,%d),scale=%d:%d' % (n, W, H), '-frames:v', '1', p], check=True)
                sheet.paste(Image.open(p), (ci * W, y + 20))
        sheet.save(os.path.join(out, 'gallery_%02d.jpg' % (si // per)), quality=85)
print(len(rows), 'effects', (len(rows) + per - 1) // per, 'sheets')
