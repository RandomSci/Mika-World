"""Original textures for Oriel, the Phoenix (both forms). Pure numpy, no source imagery.

  python3 tools/models/phoenix_textures.py assets/creatures/phoenix

Writes
  feather_atlas.png   4 x 2 cells (each 512 x 1024, the feather's length along v) of feather cards (RGBA).
                      Colour comes from VERTEX colours in the models; the atlas carries
                      R = luminance (barbs, shaft, engraving), G = shaft / metal mask, B = glow mask (flame
                      tips, rims), A = silhouette. Cells (column, row) in Blender UV space (v up, root at v=0):
                        (0,0) flight feather, flame-licked tip      (1,0) contour / scale feather, bright rim
                        (2,0) gold filigree covert (G = metal)      (3,0) flame tongue (additive cards)
                        (0,1) plume (hackle, crest)                 (1,1) tail streamer, wispy flame end
                        (2,1) down (soft, fluffy)                   (3,1) spark glint (particles)
  iris.png            the eyes both forms share: molten gold with a crimson ring and a dark pupil.
  fabric.png          a fine woven pattern for cloth detail (greyscale).

v3 (visual pass 2): the atlas is twice the resolution, the cells are long (1:2) so a feather's barbs keep
their detail, and the shapes are drawn as fire: separated barbs at the tips curl into flame licks.
"""
import os
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/creatures/phoenix"
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)
CW, CH = 512, 1024        # one cell: width (u) x height (v)
COLS, ROWS = 4, 2


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def blur_noise(shape, k=2):
    n = rng.random(shape)
    for _ in range(k):
        n = (n + np.roll(n, 1, 0) + np.roll(n, 1, 1) + np.roll(n, -1, 0) + np.roll(n, -1, 1)) / 5
    return (n - n.min()) / (n.max() - n.min() + 1e-9)


def value_noise(u, v, fu, fv, seed):
    """Smooth value noise sampled at (u*fu, v*fv)."""
    r = np.random.default_rng(seed)
    g = r.random((int(fv) + 3, int(fu) + 3))
    x = u * fu
    y = v * fv
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    tx = x - x0
    ty = y - y0
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    x0 = np.clip(x0, 0, g.shape[1] - 2)
    y0 = np.clip(y0, 0, g.shape[0] - 2)
    a = g[y0, x0] * (1 - tx) + g[y0, x0 + 1] * tx
    b = g[y0 + 1, x0] * (1 - tx) + g[y0 + 1, x0 + 1] * tx
    return a * (1 - ty) + b * ty


def grid():
    i, j = np.mgrid[0:CH, 0:CW]
    u = (j + 0.5) / CW
    v = 1.0 - (i + 0.5) / CH          # v = 0 root at the BOTTOM row of the cell
    return u, v


def barbs(v, d, ang, freq, fine_freq, u):
    b = v - np.abs(d) * ang
    stripes = 0.5 + 0.5 * np.sin(b * 2 * np.pi * freq)
    fine = 0.5 + 0.5 * np.sin(b * 2 * np.pi * fine_freq + np.sin(u * 40) * 1.5)
    return stripes, fine


def shaft_of(d, v, w0=0.012):
    sw = w0 * (1.0 - 0.75 * v) + 0.0025
    shaft = smooth(sw, sw * 0.45, np.abs(d))
    groove = smooth(sw * 2.0, sw, np.abs(d)) * (1 - shaft)
    return shaft, groove


def pack(lum, g, b, a):
    out = np.zeros(lum.shape + (4,), np.float32)
    out[..., 0] = np.clip(lum, 0, 1)
    out[..., 1] = np.clip(g, 0, 1)
    out[..., 2] = np.clip(b, 0, 1)
    out[..., 3] = np.clip(a, 0, 1)
    return out


def flame_lick(d, w, v, start, count, seed, depth=1.0):
    """Separated barbs at a feather's end: the vane splits into `count` wavy tongues that curl toward the
    tip like flame licks (an alpha cut that widens toward the end)."""
    rel = np.clip(d / np.maximum(w, 1e-3), -1.3, 1.3)
    t = smooth(start, 1.0, v)
    wob = value_noise(np.abs(rel) * 0.5 + 0.1, v, 5, 14, seed) - 0.5
    phase = rel * np.pi * count + (v - start) * 11.0 * np.sign(rel) + wob * 2.5
    tongues = 0.5 + 0.5 * np.cos(phase)
    width = 0.18 + 0.32 * t                    # gaps open wider toward the tip
    gap = smooth(width, width - 0.12, tongues) * smooth(0.0, 0.25, t) * depth * smooth(0.12, 0.4, np.abs(rel))
    return gap


def flight():
    u, v = grid()
    uc = 0.46 + 0.05 * np.sin(v * np.pi * 1.1) * v * v                    # the tip sweeps aside
    d = u - uc
    w = 0.46 * smooth(0.02, 0.3, v) ** 0.6                                  # a short quill, then a broad full vane
    w = np.where(v > 0.66, w * (1 - (v - 0.66) / 0.34) ** 0.9, w)          # a full, rounded-pointed end
    w = np.maximum(w, 0.006 * (1 - v))                                       # the bare calamus
    w = w * np.where(d < 0, 0.66, 1.0)                                      # narrow outer vane
    notch = np.where(d > 0, 1.0 - 0.25 * np.exp(-((v - 0.6) / 0.05) ** 2), 1.0)
    w = w * notch
    edge = smooth(w + 0.004, w - 0.008, np.abs(d))
    gap = flame_lick(d, w, v, 0.74, 2.5, 11, 0.55)
    stripes, fine = barbs(v, d, 0.5, 58, 210, u)
    nz = blur_noise((CH, CW))
    lum = 0.66 + 0.16 * stripes + 0.08 * fine + 0.06 * (nz - 0.5)
    lum += 0.16 * smooth(0.0, 1.0, v)                       # tips lighter
    lum -= 0.18 * (1 - smooth(0.0, 0.35, v))                # dark base
    rim = smooth(0.55, 1.0, np.abs(d) / np.maximum(w, 1e-3)) * smooth(0.2, 0.9, v)
    lum += 0.12 * rim
    shaft, groove = shaft_of(d, v)
    lum = lum * (1 - 0.4 * shaft) + 0.98 * shaft - 0.12 * groove
    alpha = np.clip(edge - gap, 0, 1)
    glow = smooth(0.45, 1.0, v) ** 1.3 + 0.35 * rim
    return pack(lum, shaft, glow, alpha)


def contour():
    u, v = grid()
    d = u - 0.5
    w = 0.47 * np.sin(np.pi * np.clip(v, 0, 1) ** 0.62) ** 0.45
    cap = np.sqrt(np.clip(1 - ((v - 0.78) / 0.22) ** 2, 0, 1)) * 0.47
    w = np.where(v > 0.78, np.minimum(w, cap), w)
    edge = smooth(w + 0.004, w - 0.01, np.abs(d))
    stripes, fine = barbs(v, d, 0.8, 30, 120, u)
    rel = np.clip(np.abs(d) / np.maximum(w, 1e-3), 0, 1)
    outline = np.maximum(rel, smooth(0.7, 1.0, v / np.maximum(0.78 + 0.22 * np.sqrt(1 - rel ** 2), 1e-3)))
    rim = smooth(0.62, 0.95, outline)
    nz = blur_noise((CH, CW))
    lum = 0.5 + 0.1 * stripes + 0.05 * fine + 0.06 * (nz - 0.5) + 0.42 * rim
    lum -= 0.15 * (1 - smooth(0.0, 0.45, v))
    shaft, groove = shaft_of(d, v, 0.008)
    shaft *= 1 - smooth(0.55, 0.8, v)
    lum = lum * (1 - 0.3 * shaft) + 0.8 * shaft
    return pack(lum, shaft * 0.6, rim * smooth(0.2, 0.8, v), edge)


def gold():
    """An ornate gold covert: a pointed-arch scale with a raised rim, a central rib, a pair of volutes
    (filigree scrolls) and a small inset of crimson enamel (G = 0 there: the vertex colour shows)."""
    u, v = grid()
    d = u - 0.5
    base = 0.47 * np.sin(np.pi * np.clip(v, 0, 1) ** 0.62) ** 0.45
    ogee = 0.47 * np.clip((1.0 - v) / 0.32, 0, 1) ** 0.8
    w = np.where(v > 0.68, np.minimum(base, ogee), base)
    lobes = 0.012 * (0.5 + 0.5 * np.cos(v * np.pi * 22))
    w = w - lobes * smooth(0.1, 0.3, v)
    edge = smooth(w + 0.004, w - 0.01, np.abs(d))
    rel = np.clip(np.abs(d) / np.maximum(w, 1e-3), 0, 1)
    rim = smooth(0.78, 0.9, rel) * (1 - smooth(0.96, 1.0, rel))
    groove_rim = smooth(0.7, 0.78, rel) * (1 - smooth(0.78, 0.84, rel))
    rib = smooth(0.02, 0.0, np.abs(d)) * smooth(0.1, 0.3, v) * (1 - smooth(0.82, 0.9, v))
    # volutes: two log spirals either side of the rib
    lum = np.full(u.shape, 0.78)
    eng = np.zeros(u.shape)
    for sx in (-1.0, 1.0):
        cx, cy = 0.5 + sx * 0.17, 0.42
        x = (u - cx) / 0.5
        y = (v - cy) / 1.0 * 2.0
        r = np.sqrt(x * x + y * y) + 1e-6
        th = np.arctan2(y, x * sx)
        sp = np.sin(th * 1.0 - np.log(r) * 7.0)
        line = smooth(0.82, 0.97, sp) * smooth(0.36, 0.05, r)
        eng = np.maximum(eng, line)
    dots = smooth(0.55, 0.9, np.cos(v * np.pi * 26) * np.cos(d * np.pi * 26)) * smooth(0.75, 0.6, rel) * smooth(0.55, 0.7, v)
    inset = smooth(0.11, 0.08, np.sqrt((d / 0.7) ** 2 + ((v - 0.66) / 1.4) ** 2))   # the enamel teardrop
    nz = blur_noise((CH, CW), 1)
    lum = lum + 0.22 * rim - 0.4 * groove_rim + 0.18 * rib - 0.45 * eng + 0.15 * dots + 0.05 * (nz - 0.5)
    lum = lum * (1 - inset) + 0.62 * inset
    metal = (1 - inset) * edge
    glow = rim * 0.7 + inset * 0.5 + rib * 0.2
    return pack(lum, metal, glow, edge)


def flame():
    """A flame tongue for additive cards: R = intensity, G = white-hot core, B = height (colour ramp)."""
    u, v = grid()
    uc = 0.5 + 0.06 * np.sin(v * np.pi * 2.3 + 0.4) * v
    d = u - uc
    w = 0.44 * smooth(0.0, 0.1, v) ** 0.5 * (1 - v) ** 0.7
    wob = value_noise(u, v, 4, 10, 3) - 0.5
    w = w * (1 + 0.3 * wob)
    rel = np.abs(d) / np.maximum(w, 1e-3)
    body = smooth(1.0, 0.25, rel)
    licks = flame_lick(d, w, v, 0.45, 1.5, 5)
    inten = body * (1 - licks) * (1 - smooth(0.85, 1.0, v)) * (0.55 + 0.45 * (1 - v))
    core = smooth(0.5, 0.0, rel) * (1 - smooth(0.15, 0.6, v))
    return pack(inten, core, v, inten)


def plume():
    u, v = grid()
    uc = 0.5 + 0.02 * np.sin(v * np.pi * 2.0)
    d = u - uc
    w = 0.4 * np.sin(np.pi * np.clip(v, 0, 1) ** 0.6) ** 0.5
    w = np.where(v > 0.75, w * (1 - (v - 0.75) / 0.25) ** 0.7, w)
    edge = smooth(w + 0.004, w - 0.01, np.abs(d))
    rel = np.abs(d) / np.maximum(w, 1e-3)
    # long separated barbs all along the edges (a hackle's fringe)
    comb = 0.5 + 0.5 * np.sin((v - np.abs(d) * 0.9) * 2 * np.pi * 26 + value_noise(u, v, 4, 30, 9) * 4)
    fringe = smooth(0.4, 0.75, rel) * smooth(0.6, 0.35, comb)
    gap = flame_lick(d, w, v, 0.55, 2.0, 13)
    stripes, fine = barbs(v, d, 0.9, 40, 150, u)
    lum = 0.66 + 0.14 * stripes + 0.07 * fine + 0.2 * smooth(0.2, 1.0, v)
    shaft, groove = shaft_of(d, v, 0.009)
    lum = lum * (1 - 0.35 * shaft) + 0.95 * shaft - 0.1 * groove
    alpha = np.clip(edge - fringe - gap, 0, 1)
    return pack(lum, shaft, smooth(0.4, 1.0, v) ** 1.4 + 0.25 * smooth(0.6, 1.0, rel), alpha)


def streamer():
    u, v = grid()
    d = u - 0.5
    w = 0.2 + 0.24 * smooth(0.05, 0.7, v) - 0.06 * smooth(0.75, 1.0, v)
    w = np.where(v > 0.9, w * (1 - (v - 0.9) / 0.1) ** 0.7, w)
    w = np.where(v < 0.04, w * smooth(0.0, 0.04, v), w)
    edge = smooth(w + 0.004, w - 0.01, np.abs(d))
    rel = np.abs(d) / np.maximum(w, 1e-3)
    comb = 0.5 + 0.5 * np.sin((v - np.abs(d) * 1.6) * 2 * np.pi * 22 + value_noise(u, v, 4, 24, 21) * 5)
    fringe = smooth(0.3, 0.7, rel) * smooth(0.62, 0.38, comb)
    gap = flame_lick(d, w, v, 0.6, 3.0, 17)
    stripes, fine = barbs(v, d, 1.3, 36, 140, u)
    lum = 0.6 + 0.16 * stripes + 0.08 * fine + 0.25 * smooth(0.3, 1.0, v)
    shaft, groove = shaft_of(d, v, 0.01)
    lum = lum * (1 - 0.35 * shaft) + 0.95 * shaft - 0.1 * groove
    alpha = np.clip(edge - fringe - gap, 0, 1)
    return pack(lum, shaft, smooth(0.5, 1.0, v) ** 1.2 + 0.2 * rel, alpha)


def down():
    u, v = grid()
    d = u - 0.5
    r = np.sqrt((d / 0.48) ** 2 + ((v - 0.42) / 0.55) ** 2)
    ang = np.arctan2(v - 0.05, d)
    fib = 0.5 + 0.5 * np.sin(ang * 90 + value_noise(u, v, 6, 12, 31) * 6)
    soft = smooth(1.0, 0.55, r)
    alpha = soft * (0.55 + 0.45 * fib) * smooth(0.0, 0.06, v)
    lum = 0.7 + 0.2 * fib + 0.1 * smooth(0.6, 0.0, r)
    return pack(lum, np.zeros_like(u), smooth(0.9, 0.4, r) * 0.3, alpha)


def spark():
    u, v = grid()
    x = (u - 0.5) * 2
    y = (v - 0.5) * 4          # the cell is twice as tall: keep the star round
    r = np.sqrt(x * x + y * y)
    rays = np.exp(-np.abs(x) * 26) * np.exp(-np.abs(y) * 2.2) + np.exp(-np.abs(y) * 26) * np.exp(-np.abs(x) * 2.2)
    diag = (np.exp(-np.abs(x - y) * 30) + np.exp(-np.abs(x + y) * 30)) * np.exp(-r * 4.0) * 0.5
    halo = np.exp(-r * 5.5)
    core = np.exp(-r * 22)
    inten = np.clip(rays * 0.9 + diag + halo * 0.55 + core, 0, 1)
    return pack(inten, core, inten, inten)


CELLS = {(0, 0): flight, (1, 0): contour, (2, 0): gold, (3, 0): flame,
         (0, 1): plume, (1, 1): streamer, (2, 1): down, (3, 1): spark}
atlas = np.zeros((ROWS * CH, COLS * CW, 4), np.float32)
for (cx, cy), fn in CELLS.items():
    y0 = (ROWS - 1 - cy) * CH        # image rows grow downward; UV row 0 is the bottom of the image
    atlas[y0:y0 + CH, cx * CW:(cx + 1) * CW] = fn()
    print("cell", cx, cy, fn.__name__)
Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "feather_atlas.png"))

# ---- iris (shared by both forms): molten gold, crimson limbal ring, radial fibres, dark pupil
M = 256
i, j = np.mgrid[0:M, 0:M]
x = (j + 0.5) / M * 2 - 1
y = (i + 0.5) / M * 2 - 1
r = np.sqrt(x * x + y * y)
ang = np.arctan2(y, x)
fib = 0.5 + 0.5 * np.sin(ang * 46 + r * 9) * (0.6 + 0.4 * np.sin(ang * 13 + 2))
gold_c = np.array([0.82, 0.46, 0.07])
amber = np.array([0.42, 0.13, 0.02])
crim = np.array([0.62, 0.06, 0.03])
white = np.array([0.98, 0.95, 0.9])
t = np.clip((r - 0.25) / 0.6, 0, 1)[..., None]
img = gold_c * (1 - t) + amber * t
img = img * (0.82 + 0.25 * fib[..., None])
ring = smooth(0.72, 0.84, r)[..., None]
img = img * (1 - ring) + crim * ring
sclera = smooth(0.9, 0.98, r)[..., None]
img = img * (1 - sclera) + np.array([0.12, 0.03, 0.02]) * sclera      # a bird's eye: dark rim, no white
pupil = smooth(0.3, 0.2, r)[..., None]
img = img * (1 - pupil) + np.array([0.03, 0.01, 0.01]) * pupil
spark_ = smooth(0.1, 0.0, np.sqrt((x + 0.28) ** 2 + (y + 0.3) ** 2))[..., None]
img = img * (1 - spark_) + white * spark_
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "iris.png"))

# ---- fabric detail (greyscale): a fine herringbone weave with a soft shimmer
F = 256
i, j = np.mgrid[0:F, 0:F]
wv = 0.5 + 0.5 * np.sin(j / F * 2 * np.pi * 48 + np.sign(np.sin(i / F * 2 * np.pi * 12)) * (i / F * 2 * np.pi * 48))
wh = 0.5 + 0.5 * np.sin(i / F * 2 * np.pi * 48)
fab = 0.62 + 0.22 * wv * 0.5 + 0.16 * wh * 0.5 + 0.06 * (rng.random((F, F)) - 0.5)
Image.fromarray((np.clip(fab, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, "fabric.png"))
print("wrote", OUT, "feather_atlas.png iris.png fabric.png")
