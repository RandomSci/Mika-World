#!/usr/bin/env python3
"""Luna's ORIGINAL face, cleaned (Day 3, step 6), in the spirit of the Transformation Lab's Mika face v2 cleanup but
keeping her eye shape and face exactly as they are: nothing is moved or resized, only removed, softened or recoloured.

  skin   the painted nose-bridge line, the lower-lash ticks (and the lower lid line they hang from) and the outlined
         eyelid crease are inpainted with the surrounding skin; the lips keep their shape but are softened to a gentle
         pink (no dark outline)
  lashes the near-black red liner and lashes become a warm dark brown (the material colour is set neutral at runtime)
  iris   her amber made brighter and more luminous (same pattern, same size)

usage: make_luna_face_clean.py <dir with her original face textures (mktest facetex)> <output dir>
No reference image is used; the VRM is never modified (FaceStyle swaps these in at runtime).
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

SRC, OUT = sys.argv[1], sys.argv[2]


def load(n):
    return np.asarray(Image.open(f"{SRC}/{n}.png").convert("RGBA")).astype(np.float32) / 255.0


def save(a, n):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(f"{OUT}/{n}.png", optimize=True)


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def inpaint(rgb, mask, sigma):
    keep = (~mask).astype(np.float32)
    num = np.stack([ndimage.gaussian_filter(rgb[..., i] * keep, sigma) for i in range(3)], -1)
    den = ndimage.gaussian_filter(keep, sigma)[..., None]
    fill = num / np.maximum(den, 1e-4)
    soft = np.clip(ndimage.gaussian_filter(mask.astype(np.float32), 0.8) * 1.6, 0, 1)[..., None]
    return rgb * (1 - soft) + fill * soft


# ---------------------------------------------------------------- skin
sk = load("Luna_Face_00_SKIN")
rgb = sk[..., :3].copy()
L = lum(rgb)
bg = ndimage.median_filter(L, size=13)
dark = (bg - L) > 0.035                              # thin painted lines are darker than the skin around them
H, W = L.shape
yy, xx = np.mgrid[0:H, 0:W]
zones = np.zeros_like(dark)
for x0, x1 in ((265, 450), (574, 760)):
    zones[468:560, x0:x1] = True                     # eyelid crease outline
    zones[575:650, x0:x1] = True                     # lower-lash ticks and the lower lid line
zones[565:688, 488:522] = True                       # the nose-bridge line (the nostril marks below stay)
nose = np.zeros_like(dark)
nose[565:688, 488:522] = True
lines = (dark & zones) | (((bg - L) > 0.012) & nose)          # the nose line is fainter than the others
lines = ndimage.binary_dilation(lines, iterations=1)
nose_line = ndimage.binary_dilation(lines & nose, structure=np.ones((3, 7), bool))   # its pale edge too
nose_line[675:, :] = False                                                           # (stop above the nose tip)
lines |= nose_line
rgb = inpaint(rgb, lines, 4.0)
print("skin: inpainted", int(lines.sum()), "line pixels")

# lips: same shape, softened - a gentle pink, the dark contour and centre line lifted, edges a touch softer
R, G = rgb[..., 0], rgb[..., 1]
lipm = np.zeros((H, W), bool)
lipm[735:810, 405:620] = ((R - G) > 0.18)[735:810, 405:620]
lipm = ndimage.binary_closing(lipm, iterations=2)
lip_a = np.clip(ndimage.gaussian_filter(lipm.astype(np.float32), 1.4), 0, 1)
skin_fill = inpaint(rgb, ndimage.binary_dilation(lipm, iterations=4), 10.0)
Ll = lum(rgb)
mean_l = Ll[lipm].mean()
detail = np.clip(1.0 + 0.45 * (Ll - mean_l), 0.85, 1.15)[..., None]           # keep its gloss, flatten the contour
pink = np.array([0.94, 0.62, 0.66]) * detail
new_lips = skin_fill * 0.25 + pink * 0.75
rgb = rgb * (1 - lip_a[..., None]) + new_lips * lip_a[..., None]
sk[..., :3] = rgb
save(sk, "Luna_Face_00_SKIN")

# ---------------------------------------------------------------- lashes and liner: warm dark brown, not near-black red
TARGET = np.array([0.30, 0.17, 0.14])
for n in ("Luna_FaceEyelash_00_FACE", "Luna_FaceEyeline_00_FACE"):
    t = load(n)
    m = t[..., 3] > 0.3
    l = lum(t[..., :3])
    rel = np.clip(l / max(l[m].mean(), 1e-4), 0.6, 1.5)[..., None]
    t[..., :3] = np.clip(TARGET * rel, 0, 1)
    save(t, n)

# ---------------------------------------------------------------- iris: brighter, more luminous amber
ir = load("Luna_EyeIris_00_EYE")
c = ir[..., :3]
c = 1 - (1 - c) ** 1.45                               # lift (darks stay dark: the pupil and the ring keep their weight)
g = lum(c)[..., None]
c = np.clip(g + (c - g) * 1.18, 0, 1)                 # a little more saturation
H, W = ir.shape[:2]
yy, xx = np.mgrid[0:H, 0:W]
for x0, x1 in ((0, W // 2), (W // 2, W)):              # a soft luminous lower crescent per eye
    a = ir[:, x0:x1, 3] > 0.5
    ys, xs = np.nonzero(a)
    cy, ry = ys.mean(), (ys.max() - ys.min()) / 2
    cx, rx = xs.mean() + x0, (xs.max() - xs.min()) / 2
    v = (yy[:, x0:x1] - cy) / ry
    r = np.sqrt(((xx[:, x0:x1] - cx) / rx) ** 2 + v ** 2)
    glow = np.clip((v - 0.15) / 0.6, 0, 1) * np.clip((r - 0.42) / 0.15, 0, 1) * np.clip((0.95 - r) / 0.15, 0, 1)
    c[:, x0:x1] = c[:, x0:x1] + (np.array([1.0, 0.92, 0.6]) - c[:, x0:x1]) * (0.35 * glow)[..., None]
ir[..., :3] = c
save(ir, "Luna_EyeIris_00_EYE")
print("wrote", OUT)
