#!/usr/bin/env python3
"""Needle-spray atlas for the realistic conifers (Celestial Highlands): thousands of drawn needles along forking
twigs, per-needle tone variation (new growth lighter, old needles darker and bluer), a waxy highlight down each
needle, and a matching tangent-space normal map (each needle a little cylinder: its normal tilts across its width).

  python3 tools/textures/needle_twigs.py <out_dir>
Writes <out_dir>/needles_albedo.png (RGBA) and needles_normal.png, 2x2 cells of 1024 px:
  cell 0: spruce spray (dense, needles all round the twig)   cell 1: spruce spray, sunlit tip growth
  cell 2: fir spray (flat, needles in two rows)              cell 3: sparse, old shaded spray (inner crown)
Drawn at 2x and downsampled (anti-aliased needles).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)
SS = 2
CELL = 1024 * SS
rnd = random.Random(23)

alb = Image.new("RGBA", (CELL * 2, CELL * 2), (0, 0, 0, 0))
nor = Image.new("RGB", (CELL * 2, CELL * 2), (128, 128, 255))
da = ImageDraw.Draw(alb)
dn = ImageDraw.Draw(nor)


def needle(x0, y0, ang, length, width, col, fresh):
    dx, dy = math.cos(ang), math.sin(ang)
    x1, y1 = x0 + dx * length, y0 + dy * length
    px, py = -dy, dx
    # body (two tones across: lit side / shaded side) + a waxy line
    for k, t in ((-0.5, 0.78), (0.0, 1.0), (0.5, 0.86)):
        c = tuple(int(min(255, ch * t)) for ch in col)
        ox, oy = px * width * k * 0.6, py * width * k * 0.6
        da.line([(x0 + ox, y0 + oy), (x1 + ox * 0.3, y1 + oy * 0.3)], fill=c + (255,), width=max(1, int(width * 0.55)))
    hl = tuple(int(min(255, ch * 1.25 + 18)) for ch in col)
    da.line([(x0 + px * width * 0.12, y0 + py * width * 0.12), (x0 + dx * length * 0.8, y0 + dy * length * 0.8)], fill=hl + (255,), width=max(1, int(width * 0.18)))
    # normal: across the needle the normal leans left/right (a cylinder), along it flat
    for k, side in ((-0.5, -1.0), (0.0, 0.0), (0.5, 1.0)):
        nx, ny = px * side * 0.55, py * side * 0.55
        n = (nx, ny, math.sqrt(max(0.0, 1.0 - nx * nx - ny * ny)))
        c = (int((n[0] * 0.5 + 0.5) * 255), int((-n[1] * 0.5 + 0.5) * 255), int((n[2] * 0.5 + 0.5) * 255))
        ox, oy = px * width * k * 0.6, py * width * k * 0.6
        dn.line([(x0 + ox, y0 + oy), (x1 + ox * 0.3, y1 + oy * 0.3)], fill=c, width=max(1, int(width * 0.55)))


def needle_col(fresh, old):
    if fresh:
        base = (rnd.randint(70, 95), rnd.randint(118, 140), rnd.randint(52, 70))
    elif old:
        base = (rnd.randint(22, 34), rnd.randint(46, 60), rnd.randint(40, 52))
    else:
        base = (rnd.randint(34, 50), rnd.randint(70, 88), rnd.randint(46, 60))
    return base


def twig(ox, oy, start, ang, length, width, kind, depth=0):
    """A twig from `start` at angle `ang`: needles along it; side twigs fork off."""
    x, y = start
    steps = int(length / (6 * SS))
    for i in range(steps):
        t = i / max(steps, 1)
        a = ang + math.sin(t * 3.0 + depth) * 0.08
        nx, ny = x + math.cos(a) * 6 * SS, y + math.sin(a) * 6 * SS
        bark = (rnd.randint(70, 95), rnd.randint(52, 66), rnd.randint(34, 44))
        da.line([(ox + x, oy + y), (ox + nx, oy + ny)], fill=bark + (255,), width=max(1, int(width * (1 - t * 0.6))))
        fresh = (kind == "fresh" and t > 0.45) or (kind != "old" and t > 0.8 and rnd.random() < 0.6)
        per = {"spruce": 7, "fresh": 7, "fir": 4, "old": 3}[kind]
        for k in range(per):
            if kind == "fir":
                side = 1 if k % 2 == 0 else -1
                na = a + side * rnd.uniform(1.15, 1.45)
                L = rnd.uniform(26, 34) * SS
            else:
                na = a + rnd.uniform(-1.9, 1.9) + (math.pi if rnd.random() < 0.15 else 0.0)
                L = rnd.uniform(16, 26) * SS * (0.75 + 0.25 * math.cos(na - a) ** 2)
            needle(ox + x, oy + y, na, L * (0.85 if kind == "old" else 1.0), 3.2 * SS, needle_col(fresh, kind == "old"), fresh)
        if depth < 2 and i > 2 and i % (5 if kind != "old" else 8) == 0 and rnd.random() < 0.85:
            side = 1 if (i // 5) % 2 == 0 else -1
            twig(ox, oy, (x, y), a + side * rnd.uniform(0.45, 0.8), length * rnd.uniform(0.35, 0.55) * (1 - t * 0.5), width * 0.6, kind, depth + 1)
        x, y = nx, ny


cells = [(0, 0, "spruce"), (CELL, 0, "fresh"), (0, CELL, "fir"), (CELL, CELL, "old")]
for ox, oy, kind in cells:
    # the spray grows from the bottom centre of its cell upward (the card's v axis)
    twig(ox, oy, (CELL * 0.5, CELL * 0.97), -math.pi / 2, CELL * 0.88, 9 * SS, kind)

alb = alb.resize((2048, 2048), Image.LANCZOS)
nor = nor.resize((2048, 2048), Image.LANCZOS)
# fill transparent texels with nearby needle colour (no dark fringes when mip-mapped)
a = np.asarray(alb).astype(np.float32)
rgb = a[..., :3]
alpha = a[..., 3:4] / 255.0
blur = np.asarray(Image.fromarray(np.uint8(rgb * alpha)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32)
wblur = np.asarray(Image.fromarray(np.uint8(alpha[..., 0] * 255)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32)[..., None] / 255.0
fill = np.where(wblur > 0.01, blur / np.maximum(wblur, 0.01), np.array([40, 70, 50], np.float32))
rgb = rgb * alpha + np.clip(fill, 0, 255) * (1 - alpha)
out = np.concatenate([rgb, a[..., 3:4]], axis=-1)
Image.fromarray(np.uint8(np.clip(out, 0, 255)), "RGBA").save(os.path.join(OUT, "needles_albedo.png"))
nor.save(os.path.join(OUT, "needles_normal.png"))
print("wrote", OUT)
