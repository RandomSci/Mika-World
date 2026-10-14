#!/usr/bin/env python3
"""A painted 360-degree backdrop for the Whispering Woods (visual quality pass): layered mountain ranges with
aerial perspective, sunlit and shadowed flanks, snow on the far peaks, forested foothills and valley mist -
the distant world as a matte painting rather than flat ridges. Pure numpy (original; no source imagery).

  python3 tools/textures/paint_backdrop.py assets/nature/hero/backdrop.png [width]

Wraps horizontally (u = azimuth). Top = sky (transparent), bottom = opaque haze band. The light comes from the
image's left (the Woods' day sun side), so left-facing flanks are lit.
"""
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "backdrop.png"
W = int(sys.argv[2]) if len(sys.argv) > 2 else 8192
H = W // 4
X = np.arange(W) / W
Y = np.arange(H)[:, None] / H


def smooth1(v, k):
    """Circular box blur (wraps)."""
    if k <= 1:
        return v
    c = np.cumsum(np.concatenate([v[-k:], v, v[:k]]))
    out = (c[2 * k:] - c[:-2 * k]) / (2 * k)
    return out[:len(v)]


def peaks(seed, n, wmin, wmax, hmin, hmax, sharp):
    r = np.random.default_rng(seed)
    prof = np.zeros(W)
    for i in range(n):
        c = r.uniform(0, 1)
        w = r.uniform(wmin, wmax)
        h = r.uniform(hmin, hmax)
        d = np.abs(((X - c + 0.5) % 1.0) - 0.5) / w
        prof = np.maximum(prof, h * np.clip(1 - d, 0, 1) ** sharp)
    # ridged detail along the crest
    det = np.zeros(W)
    amp, freq = 1.0, 24
    for o in range(6):
        ph = r.uniform(0, 2 * np.pi, 3)
        det += amp * (1 - np.abs(np.sin(2 * np.pi * freq * X + ph[0]) * np.sin(2 * np.pi * freq * 1.7 * X + ph[1])))
        amp *= 0.5
        freq *= 2.1
    det = det / det.max()
    return prof + 0.045 * det * (0.4 + prof)


def noise2(seed, sx, sy):
    """Smooth 2-D value noise, wraps in x; sx, sy = cells across the image."""
    r = np.random.default_rng(seed)
    g = r.random((sy + 3, sx))
    g = np.concatenate([g, g[:, :1]], axis=1)
    im = Image.fromarray((g * 255).astype(np.uint8)).resize((W + W // sx, H + 3 * H // sy), Image.BICUBIC)
    a = np.asarray(im, dtype=np.float32)[:H, :W] / 255.0
    return a - 0.5


HAZE = np.array([0.76, 0.86, 0.94])
img = np.zeros((H, W, 4), np.float32)
#            base  seed  n   wmin  wmax   hmin  hmax sharp  lit                       shadow                    haze  snow  forest
layers = [(0.60, 11, 18, 0.03, 0.08, 0.20, 0.42, 1.6, (0.80, 0.82, 0.92), (0.55, 0.60, 0.76), 0.40, True, False),
          (0.70, 23, 24, 0.025, 0.07, 0.10, 0.26, 1.5, (0.58, 0.68, 0.78), (0.38, 0.47, 0.62), 0.30, True, False),
          (0.80, 37, 30, 0.025, 0.06, 0.06, 0.16, 1.4, (0.36, 0.50, 0.44), (0.20, 0.31, 0.34), 0.18, False, True),
          (0.89, 41, 40, 0.015, 0.04, 0.03, 0.09, 1.3, (0.24, 0.40, 0.25), (0.11, 0.22, 0.17), 0.08, False, True)]
for li, (base, seed, n, wmin, wmax, hmin, hmax, sharp, lit, shade, haze, snow, forest) in enumerate(layers):
    prof = peaks(seed, n, wmin, wmax, hmin, hmax, sharp)
    top = base - prof                                          # ridge line, fraction from the top
    # flank lighting from the crest's slope (smoothed: no per-column flicker); light from the left
    sm = smooth1(smooth1(prof, max(2, W // 260)), max(2, W // 400))
    slope = np.gradient(sm) * W
    lit_amt = np.clip(0.5 - 0.5 * np.tanh(slope * 0.7), 0.0, 1.0)
    # spurs: valleys run down from each saddle (where the crest is low), so the flanks are carved, not flat
    below = np.clip((Y - top[None, :]) / 0.18, 0.0, 1.0)
    rock = noise2(100 + li, 160 + li * 40, 24) + 0.5 * noise2(200 + li, 420, 70)
    lit2 = lit_amt[None, :] * (1 - 0.6 * below) + 0.5 * (0.6 * below)
    shade_mix = np.clip(lit2 + 0.3 * rock - 0.15 * below, 0, 1)
    col = np.array(shade)[None, None, :] + (np.array(lit) - np.array(shade))[None, None, :] * shade_mix[..., None]
    if snow:
        snow_line = top[None, :] + (0.03 + 0.05 * (prof[None, :] / (hmax + 0.05)))
        sn = np.clip((snow_line - Y) / 0.012 + 0.6 * rock, 0, 1) * (prof[None, :] > hmax * 0.45)
        snowc = np.array([0.97, 0.98, 1.0]) * (0.78 + 0.22 * shade_mix[..., None])
        col = col * (1 - sn[..., None]) + snowc * sn[..., None]
    if forest:
        canopy = noise2(300 + li, 900, 120) + 0.6 * noise2(310 + li, 2200, 300)
        trees = np.clip((canopy + 0.15) * 3.0, 0, 1) * np.clip((Y - top[None, :]) / 0.01, 0, 1)
        dark = np.array([0.10, 0.20, 0.12]) if li == 3 else np.array([0.18, 0.30, 0.27])
        col = col * (1 - 0.45 * trees[..., None]) + dark * (0.45 * trees[..., None])
    # aerial perspective + valley mist pooling at each layer's foot
    mist = np.clip((Y - (base - 0.02)) / 0.06, 0, 1) * (0.55 + 0.45 * np.clip(noise2(400 + li, 60, 10) * 3 + 0.5, 0, 1))
    h = np.clip(haze + 0.5 * mist * (1.0 - 0.18 * li), 0, 0.9)
    col = col * (1 - h[..., None]) + HAZE * h[..., None]
    edge = np.clip((Y - top[None, :]) * H / 1.4, 0, 1)
    img[..., :3] = img[..., :3] * (1 - edge[..., None]) + col * edge[..., None]
    img[..., 3] = np.maximum(img[..., 3], edge)
bot = np.clip((Y - 0.93) / 0.07, 0, 1)
img[..., :3] = img[..., :3] * (1 - bot[..., None]) + HAZE * bot[..., None]
img[..., 3] = np.maximum(img[..., 3], np.broadcast_to(bot, (H, W)))
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(OUT)
print("wrote", OUT, W, H)
