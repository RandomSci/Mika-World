#!/usr/bin/env python3
"""Luna's Day 3 face style: new face textures painted procedurally from her own originals (no reference image is used
or embedded). Direction from the developer: a goddess of beauty, elegant and cute - big round eyes, gradient golden
irises with strong anime sparkle and 2-3 catchlights, thicker darker lashes, fuller soft brows, a smaller soft pink
mouth with a light gloss, a soft blush. Identity unchanged (both eyes golden).

usage: make_luna_face.py <dir with the avatar's dumped face textures (mktest facetex)> <output dir>
The VRM is never modified: FaceStyle (scripts/characters/face_style.gd) swaps these in at runtime.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

SRC, OUT = sys.argv[1], sys.argv[2]
rng = np.random.default_rng(7)


def load(n):
    return np.asarray(Image.open(f"{SRC}/{n}.png").convert("RGBA")).astype(np.float32) / 255.0


def save(a, n):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(f"{OUT}/{n}.png", optimize=True)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t[..., None]


def blend(base, col, alpha):
    """paint col (rgb) over base (rgba) with alpha (HxW)"""
    base[..., :3] = lerp(base[..., :3], np.broadcast_to(np.asarray(col, np.float32), base[..., :3].shape), alpha)


def eye_axes(alpha, x0, x1):
    ys, xs = np.nonzero(alpha[:, x0:x1] > 0.5)
    return xs.mean() + x0, ys.mean(), (xs.max() - xs.min()) / 2, (ys.max() - ys.min()) / 2


# ---------------------------------------------------------------- iris: bigger, gradient gold, sparkling
IRIS_SCALE, PUPIL = 1.25, 0.40
iris0 = load("Luna_EyeIris_00_EYE")
H, W = iris0.shape[:2]
iris = np.zeros_like(iris0)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
sparkles = [(rng.uniform(-0.75, 0.75), rng.uniform(0.15, 0.8), rng.uniform(0.018, 0.04)) for _ in range(16)]
for x0, x1 in [(0, W // 2), (W // 2, W)]:
    cx, cy, ax, ay = eye_axes(iris0[..., 3], x0, x1)
    mirror = -1.0 if x0 > 0 else 1.0
    ax, ay = ax * IRIS_SCALE, ay * IRIS_SCALE
    dx, dy = (xx - cx) / ax, (yy - cy) / ay
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx * mirror)
    v = np.clip((dy + 1) / 2, 0, 1)                            # 0 top .. 1 bottom
    # base: deep amber at the top, warm gold in the middle, luminous yellow-gold at the bottom
    top, mid, bot = np.array([0.16, 0.07, 0.02]), np.array([0.62, 0.34, 0.07]), np.array([1.0, 0.82, 0.34])
    col = np.where(v[..., None] < 0.58, lerp(top, mid, sstep(0.18, 0.58, v)), lerp(mid, bot, sstep(0.58, 0.95, v)))
    # fine radial fibres
    fib = sum(np.sin(ang * k + p) * w for k, p, w in [(23, 0.3, 0.5), (41, 1.7, 0.3), (67, 2.9, 0.2)])
    col *= (1 + 0.08 * fib * sstep(0.35, 0.6, r) * (1 - sstep(0.85, 1.0, r)))[..., None]
    # a bright ring around the pupil, then the dark limbal ring
    col = lerp(col, np.array([1.0, 0.82, 0.38]), 0.35 * sstep(PUPIL, PUPIL + 0.08, r) * (1 - sstep(PUPIL + 0.1, PUPIL + 0.3, r)))
    col = lerp(col, np.array([0.18, 0.08, 0.03]), 0.85 * sstep(0.84, 0.99, r))
    # the upper lid's shadow over the top of the iris
    col *= (1 - 0.55 * (1 - sstep(0.2, 0.5, v)))[..., None]
    # the anime under-glow: a soft bright crescent in the lower iris
    glow = sstep(0.62, 0.86, v) * sstep(0.45, 0.62, r) * (1 - sstep(0.8, 0.93, r))
    col = lerp(col, np.array([1.0, 0.95, 0.68]), 0.55 * glow)
    # pupil: deep warm brown, soft edge, a touch lighter at the bottom
    pup = 1 - sstep(PUPIL - 0.04, PUPIL + 0.02, r)
    col = lerp(col, lerp(np.array([0.09, 0.04, 0.02]), np.array([0.2, 0.1, 0.04]), sstep(0.3, 0.8, v)), pup)
    # sparkles in the lower half (mirrored between the eyes)
    for sx, sy, sr in sparkles:
        px, py = cx + sx * ax * mirror, cy + sy * ay
        if ((px - cx) / ax) ** 2 + ((py - cy) / ay) ** 2 > 0.8 ** 2:
            continue
        d = np.sqrt((xx - px) ** 2 + (yy - py) ** 2) / (sr * ax * 2)
        col = lerp(col, np.array([1.0, 0.98, 0.85]), 0.95 * (1 - sstep(0.4, 1.0, d)))
    inside = 1 - sstep(0.985, 1.0, r)
    m = (xx >= x0) & (xx < x1)
    iris[m, :3] = col[m]
    iris[m, 3] = inside[m]
save(iris, "Luna_EyeIris_00_EYE")

# ---------------------------------------------------------------- catchlights: one big oval, a small round, a tiny dot
hl0 = load("Luna_EyeHighlight_00_EYE")
hl = np.zeros_like(hl0)
hl[..., :3] = 1.0
for x0, x1 in [(0, W // 2), (W // 2, W)]:
    cx, cy, ax, ay = eye_axes(iris0[..., 3], x0, x1)
    ax, ay = ax * IRIS_SCALE, ay * IRIS_SCALE
    a = np.zeros((H, W), np.float32)
    for ox, oy, rx, ry, rot in [(-0.30, -0.14, 0.27, 0.22, -0.5), (0.30, 0.34, 0.12, 0.12, 0.0), (0.40, -0.06, 0.06, 0.06, 0.0)]:
        px, py = cx + ox * ax, cy + oy * ay
        c, s = np.cos(rot), np.sin(rot)
        u, w = (xx - px) * c + (yy - py) * s, -(xx - px) * s + (yy - py) * c
        d = np.sqrt((u / (rx * ax)) ** 2 + (w / (ry * ax)) ** 2)
        a = np.maximum(a, 1 - sstep(0.8, 1.0, d))
    m = (xx >= x0) & (xx < x1)
    hl[m, 3] = a[m]
save(hl, "Luna_EyeHighlight_00_EYE")


# ---------------------------------------------------------------- lashes and the lid line: thicker, near-black
def thicken(n, grow, rgb):
    t = load(n)
    a = t[..., 3]
    big = ndimage.grey_dilation(a, size=(grow, grow))
    big = ndimage.gaussian_filter(big, 0.8)
    t[..., 3] = np.clip(np.maximum(a, big * 0.92), 0, 1)
    t[..., :3] = rgb
    save(t, n)


thicken("Luna_FaceEyelash_00_FACE", 9, (0.07, 0.035, 0.035))
thicken("Luna_FaceEyeline_00_FACE", 9, (0.07, 0.035, 0.035))

# ---------------------------------------------------------------- brows: slightly fuller, soft-edged, warm brown
b = load("Luna_FaceBrow_00_FACE")
a = b[..., 3]
full = ndimage.gaussian_filter(ndimage.grey_dilation(a, size=(5, 3)), 1.6)
b[..., 3] = np.clip(np.maximum(a * 0.85, full * 0.6), 0, 1)
b[..., :3] = (0.4, 0.22, 0.15)
save(b, "Luna_FaceBrow_00_FACE")

# ---------------------------------------------------------------- skin: the old lips out, a small soft glossy pink mouth in, a soft blush
sk = load("Luna_Face_00_SKIN")
rgb = sk[..., :3]
R, G = rgb[..., 0], rgb[..., 1]
lips = np.zeros(R.shape, bool)
lips[730:815, 410:615] = (R - G > 0.2)[730:815, 410:615]
lips = ndimage.binary_dilation(lips, iterations=6)
keep = (~lips).astype(np.float32)
# fill the hole with the surrounding skin (normalised convolution: a smooth gradient there)
num = np.stack([ndimage.gaussian_filter(rgb[..., i] * keep, 14) for i in range(3)], -1)
den = ndimage.gaussian_filter(keep, 14)[..., None]
fill = num / np.maximum(den, 1e-4)
soft = ndimage.gaussian_filter(lips.astype(np.float32), 2.5)
rgb[:] = lerp(rgb, fill, soft)
# the new mouth: about 60 % of the old width, centred on the mouth line
cx, cy, half = 512.0, 771.0, 52.0
u = (np.mgrid[0:sk.shape[0], 0:sk.shape[1]][1] - cx) / half
yv = np.mgrid[0:sk.shape[0], 0:sk.shape[1]][0].astype(np.float32) - cy
w = np.clip(1 - u * u, 0, 1)
upper_h = 9.0 * w ** 0.7 * (1 - 0.35 * np.exp(-(u * 7) ** 2))        # a gentle cupid's bow
lower_h = 14.0 * w ** 0.6
upper = sstep(-upper_h - 1.5, -upper_h + 1.5, yv) * (1 - sstep(-1.0, 0.5, yv))
lower = sstep(-0.5, 1.0, yv) * (1 - sstep(lower_h - 2.0, lower_h + 1.5, yv))
edge = sstep(1.0, 0.82, np.abs(u))                                       # fade at the corners
lip_a = np.clip(np.maximum(upper * 0.85, lower * 0.9) * edge * (np.abs(u) < 1), 0, 1)
pink = lerp(np.array([0.96, 0.6, 0.64]), np.array([0.93, 0.5, 0.56]), sstep(-6, 8, yv))
rgb[:] = lerp(rgb, pink, lip_a)
line = np.exp(-(yv / 1.1) ** 2) * sstep(1.0, 0.7, np.abs(u))
rgb[:] = lerp(rgb, np.array([0.78, 0.38, 0.44]), 0.55 * line)
gloss = np.exp(-((u / 0.32) ** 2 + ((yv - lower_h * 0.45) / 2.6) ** 2))
rgb[:] = lerp(rgb, np.array([1.0, 0.95, 0.95]), 0.75 * gloss)
gloss2 = np.exp(-(((u + 0.22) / 0.12) ** 2 + ((yv + upper_h * 0.55) / 1.6) ** 2))
rgb[:] = lerp(rgb, np.array([1.0, 0.92, 0.92]), 0.4 * gloss2)
# a soft standing blush under each eye with fine diagonal hatching
for bx in (360.0, 664.0):
    e = np.exp(-(((np.mgrid[0:1024, 0:1024][1] - bx) / 58) ** 2 + ((np.mgrid[0:1024, 0:1024][0] - 676) / 26) ** 2))
    rgb[:] = lerp(rgb, np.array([0.98, 0.62, 0.66]), 0.32 * e)
    xg, yg = np.mgrid[0:1024, 0:1024][1], np.mgrid[0:1024, 0:1024][0]
    hatch = (np.mod(xg + yg * 0.6, 9.0) < 1.6) * np.exp(-(((xg - bx) / 34) ** 2 + ((yg - 674) / 13) ** 2))
    rgb[:] = lerp(rgb, np.array([0.92, 0.5, 0.56]), 0.35 * hatch)
save(sk, "Luna_Face_00_SKIN")
print("wrote", OUT)
