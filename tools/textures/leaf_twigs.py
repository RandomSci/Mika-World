#!/usr/bin/env python3
"""Photoreal leaf-twig atlas for the realistic forest: real scanned leaves (ambientCG LeafSet009 beech/hazel,
LeafSet010 maple; CC0) arranged alternately along thin twigs, front leaves lit, back leaves darker, with a
matching tangent-space normal map (each leaf's scanned normals rotated with the leaf).

  python3 tools/textures/leaf_twigs.py <out_dir>
Writes <out_dir>/twigs_albedo.png (RGBA, alpha = leaf silhouettes) and twigs_normal.png, 2x2 cells of 1024 px:
  cell 0, 1: beech twigs (dense, sunlit outer canopy)   cell 2: beech twig, sparser (inner, shade)
  cell 3: maple twig (accent species)
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(19)


def load_set(name, cols, rows):
    d = os.path.join(ROOT, "assets/ambientcg", name)
    col = Image.open(os.path.join(d, f"{name}_2K-JPG_Color.jpg")).convert("RGB")
    opa = Image.open(os.path.join(d, f"{name}_2K-JPG_Opacity.jpg")).convert("L")
    nor = Image.open(os.path.join(d, f"{name}_2K-JPG_NormalGL.jpg")).convert("RGB")
    W, H = col.size
    leaves = []
    a = np.asarray(opa)
    for r in range(rows):
        for c in range(cols):
            x0, x1 = int(c * W / cols), int((c + 1) * W / cols)
            y0, y1 = int(r * H / rows), int((r + 1) * H / rows)
            sub = a[y0:y1, x0:x1] > 128
            ys, xs = np.nonzero(sub)
            if len(xs) == 0:
                continue
            box = (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1)
            leaves.append((col.crop(box), opa.crop(box), nor.crop(box)))
    return leaves


beech = load_set("LeafSet009", 3, 2)
maple = load_set("LeafSet010", 2, 2)


def rotate_normals(nimg, ang_deg):
    """Rotate an RGB normal map image by ang (counter-clockwise, degrees), rotating the XY vectors too."""
    rot = nimg.rotate(ang_deg, resample=Image.BICUBIC, expand=True, fillcolor=(128, 128, 255))
    n = np.asarray(rot, dtype=np.float32) / 255.0 * 2.0 - 1.0
    a = math.radians(ang_deg)
    # image y points down, GL normals' y points up: rotating the image CCW rotates vectors CCW in GL space
    x, y = n[..., 0], n[..., 1]
    xr = x * math.cos(a) - y * math.sin(a)
    yr = x * math.sin(a) + y * math.cos(a)
    out = np.stack([xr, yr, n[..., 2]], axis=-1)
    return Image.fromarray(((out * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8))


def paste_leaf(alb, nrm, leaf, cx, cy, length_px, ang_deg, shade):
    col, opa, nor = leaf
    s = length_px / max(col.height, 1)
    w, h = max(4, int(col.width * s)), max(4, int(col.height * s))
    col = col.resize((w, h), Image.LANCZOS)
    opa = opa.resize((w, h), Image.LANCZOS)
    nor = nor.resize((w, h), Image.LANCZOS)
    # the scanned leaf points UP (petiole at the bottom); rotate so it points along ang (0 = up, + = CCW)
    col = col.rotate(ang_deg, resample=Image.BICUBIC, expand=True)
    opa = opa.rotate(ang_deg, resample=Image.BICUBIC, expand=True)
    nor = rotate_normals(nor, ang_deg)
    c = np.asarray(col, dtype=np.float32) * shade
    col = Image.fromarray(c.clip(0, 255).astype(np.uint8))
    # the petiole end sits at (cx, cy): the leaf's bottom centre before rotation
    a = math.radians(ang_deg)
    off = (h * 0.5)
    px = cx - math.sin(a) * off * -1.0
    py = cy - math.cos(a) * off
    x0 = int(px - col.width / 2)
    y0 = int(py - col.height / 2)
    rgba = col.convert("RGBA")
    rgba.putalpha(opa)
    alb.alpha_composite(rgba, (x0, y0))
    nrm.paste(nor, (x0, y0), opa)


def twig(cell_img, cell_nrm, leaves, density, size_range, seed, curl=0.25):
    r = random.Random(seed)
    S = cell_img.size[0]
    d = ImageDraw.Draw(cell_img)
    # a main twig from the bottom centre upward, with two side twigs
    stems = []
    for k, (x0, y0, ang, L) in enumerate([(S * 0.5, S * 0.98, 0.0, S * 0.9), (S * 0.5, S * 0.62, -38.0, S * 0.42), (S * 0.5, S * 0.45, 34.0, S * 0.38)]):
        pts = [(x0, y0)]
        a = math.radians(ang)
        for i in range(12):
            a += r.uniform(-0.06, 0.06) + curl * 0.02 * (1 if ang >= 0 else -1)
            x, y = pts[-1]
            pts.append((x + math.sin(a) * L / 12, y - math.cos(a) * L / 12))
        stems.append(pts)
        d.line(pts, fill=(78, 58, 40, 255), width=max(2, int(S * (0.008 if k == 0 else 0.005))))
    # leaves: back layer (darker, smaller) then front layer
    for layer, shade, scale in ((0, 0.62, 0.85), (1, 1.0, 1.0)):
        for pts in stems:
            n = int(len(pts) * density)
            for i in range(n):
                t = r.uniform(0.08, 1.0)
                j = min(int(t * (len(pts) - 1)), len(pts) - 2)
                x, y = pts[j]
                dx, dy = pts[j + 1][0] - x, pts[j + 1][1] - y
                stem_ang = math.degrees(math.atan2(dx, -dy))
                side = 1 if (i % 2 == 0) else -1
                ang = -(stem_ang + side * r.uniform(35, 70))
                L = r.uniform(*size_range) * S * scale * (0.75 + 0.35 * (1 - t))
                lf = leaves[r.randrange(len(leaves))]
                paste_leaf(cell_img, cell_nrm, lf, x, y, L, ang, shade * r.uniform(0.86, 1.08))


C = 1024
alb = Image.new("RGBA", (2 * C, 2 * C), (0, 0, 0, 0))
nrm = Image.new("RGB", (2 * C, 2 * C), (128, 128, 255))
specs = [(beech, 3.6, (0.075, 0.115), 1), (beech, 3.2, (0.08, 0.12), 2), (beech, 2.2, (0.085, 0.125), 3), (maple, 2.4, (0.1, 0.15), 4)]
for k, (leaves, dens, sizes, seed) in enumerate(specs):
    ca = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    cn = Image.new("RGB", (C, C), (128, 128, 255))
    twig(ca, cn, leaves, dens, sizes, seed)
    ox, oy = (k % 2) * C, (k // 2) * C
    alb.alpha_composite(ca, (ox, oy))
    nrm.paste(cn, (ox, oy))
# dilate colour into transparent texels (mip-mapping without dark halos)
a = np.asarray(alb, dtype=np.float32)
rgb, al = a[..., :3], a[..., 3:4] / 255.0
acc, w = rgb * al, al.copy()
for _ in range(6):
    acc = (acc + np.roll(acc, 1, 0) + np.roll(acc, -1, 0) + np.roll(acc, 1, 1) + np.roll(acc, -1, 1))
    w = (w + np.roll(w, 1, 0) + np.roll(w, -1, 0) + np.roll(w, 1, 1) + np.roll(w, -1, 1))
fill = acc / np.maximum(w, 1e-4)
rgb = np.where(al > 0.5, rgb, fill)
out = np.concatenate([rgb, a[..., 3:4]], axis=-1).clip(0, 255).astype(np.uint8)
Image.fromarray(out).save(os.path.join(OUT, "twigs_albedo.png"))
nrm.save(os.path.join(OUT, "twigs_normal.png"))
print("wrote", OUT)
