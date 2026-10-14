"""Oriel's painted face (humanoid form): eye and mouth frame atlases drawn procedurally (numpy; no source
imagery). The face is the stylized, painted kind the world's mages wear (smooth head, large expressive eyes),
and her eyes are the same molten gold with a crimson ring as her true form's.

  python3 tools/models/phoenix_face.py assets/characters/phoenix

  face_eyes.png   3x2 frames (each 256x256, RGBA): open, half, closed, happy, surprised, angry.
                  Drawn for her LEFT eye (outer corner on the right of the frame); the right eye mirrors U.
                  Each frame includes the brow.
  face_mouth.png  5x1 frames (256x128): closed, smile, aa, oh, ee.
"""
import os
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/characters/phoenix"
os.makedirs(OUT, exist_ok=True)
S = 256


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def grid():
    i, j = np.mgrid[0:S, 0:S]
    x = (j + 0.5) / S * 2 - 1          # -1 .. 1, outer corner at +x
    y = 1 - (i + 0.5) / S * 2          # -1 .. 1, up
    return x, y


def blend(dst, col, a):
    a = np.clip(a, 0, 1)[..., None]
    dst[..., :3] = dst[..., :3] * (1 - a) + np.array(col) * a
    dst[..., 3] = np.maximum(dst[..., 3], a[..., 0])


GOLD = (1.0, 0.78, 0.22)
AMBER = (0.95, 0.5, 0.08)
CRIM = (0.62, 0.06, 0.03)
LASH = (0.26, 0.03, 0.03)
BROW = (0.48, 0.07, 0.04)
WHITE = (0.99, 0.97, 0.94)
SKIN = (0.93, 0.78, 0.68)


def eye_frame(kind):
    x, y = grid()
    img = np.zeros((S, S, 4), np.float32)
    # almond: upper edge a high arc, lower edge a shallow arc; the outer corner (x>0) slightly higher
    cx, cy = -0.02, -0.12
    ex = (x - cx) / 0.78
    upper = cy + 0.46 * np.sqrt(np.clip(1 - ex * ex, 0, 1)) ** 0.8 + 0.06 * x
    lower = cy - 0.3 * np.sqrt(np.clip(1 - ex * ex, 0, 1)) ** 1.2 + 0.03 * x
    open_amt = {"open": 1.0, "half": 0.55, "closed": 0.0, "happy": 0.0, "surprised": 1.18, "angry": 0.8}[kind]
    lid = cy + (upper - cy) * open_amt
    if kind == "angry":
        lid = lid - 0.12 * smooth(0.6, -0.6, x) * 0.6            # the inner side pressed down
    inside = (np.abs(ex) < 1) & (y < lid) & (y > lower)
    if open_amt > 0.05:
        blend(img, WHITE, inside * 1.0)
        # iris: large, centred a little low; pupil; limbal ring; radial fibres
        icx, icy = -0.03, -0.1 if kind != "surprised" else -0.06
        ir = 0.3 if kind != "surprised" else 0.28
        r = np.sqrt((x - icx) ** 2 + (y - icy) ** 2) / ir
        ang = np.arctan2(y - icy, x - icx)
        fib = 0.5 + 0.5 * np.sin(ang * 36 + r * 8)
        iris = (r < 1) & inside
        col = np.array(GOLD)[None, None, :] * (1 - np.clip(r, 0, 1)[..., None] * 0.55) + np.array(AMBER)[None, None, :] * (np.clip(r, 0, 1)[..., None] * 0.55)
        col = col * (0.85 + 0.25 * fib[..., None])
        ring = smooth(0.8, 0.95, r)[..., None]
        col = col * (1 - ring) + np.array(CRIM) * ring
        a_iris = iris * smooth(1.02, 0.96, r)
        img[..., :3] = img[..., :3] * (1 - a_iris[..., None]) + col * a_iris[..., None]
        pr = 0.36 if kind != "surprised" else 0.3
        blend(img, (0.04, 0.01, 0.01), (r < pr) & inside)
        blend(img, (0.03, 0.005, 0.005), smooth(pr + 0.08, pr, r) * inside * 0.5)
        # highlights
        h1 = np.sqrt((x - (icx - 0.11)) ** 2 + (y - (icy + 0.12)) ** 2)
        h2 = np.sqrt((x - (icx + 0.09)) ** 2 + (y - (icy - 0.1)) ** 2)
        blend(img, (1.0, 1.0, 1.0), smooth(0.075, 0.045, h1) * inside)
        blend(img, (1.0, 0.98, 0.9), smooth(0.04, 0.02, h2) * inside * 0.8)
        # upper shadow (lid casts a soft shade on the eye)
        blend(img, (0.55, 0.38, 0.32), smooth(lid - 0.0, lid - 0.14, y) * inside * 0.35)
        # lower lid line (thin, soft)
        blend(img, (0.7, 0.35, 0.3), (np.abs(y - lower) < 0.025) * (np.abs(ex) < 0.98) * 0.6)
    # upper lash line: thick, with an outward flick
    if kind in ("closed", "happy"):
        if kind == "happy":
            curve = cy + 0.1 + 0.3 * np.sqrt(np.clip(1 - ex * ex, 0, 1)) ** 0.9 + 0.05 * x   # an arc ^
        else:
            curve = cy - 0.02 - 0.12 * np.sqrt(np.clip(1 - ex * ex, 0, 1)) ** 1.0 + 0.04 * x
        thick = 0.065 * (0.6 + 0.4 * np.sqrt(np.clip(1 - ex * ex, 0, 1)))
        line = (np.abs(y - curve) < thick) & (np.abs(ex) < 1.02)
        blend(img, LASH, line * 1.0)
    else:
        thick = 0.075 * (0.55 + 0.45 * np.sqrt(np.clip(1 - ex * ex, 0, 1)) ** 0.5) * (1 + 0.5 * smooth(0.3, 1.0, x))
        line = (y < lid + thick) & (y > lid - 0.015) & (np.abs(ex) < 1.02)
        blend(img, LASH, line * 1.0)
    # the flick at the outer corner and a short lash tuft
    flick_x = cx + 0.78 + 0.02
    fl = (x > flick_x - 0.05) & (x < flick_x + 0.16) & (np.abs(y - (lid.mean() if False else (cy + 0.2 * open_amt + 0.06)) - (x - flick_x) * 0.55) < 0.035)
    blend(img, LASH, fl * 0.9 * (1 if kind not in ("closed",) else 0.6))
    # brow: an arch above, tilted by the expression
    bx = (x + 0.02) / 0.85
    tilt = {"open": 0.0, "half": 0.0, "closed": 0.0, "happy": 0.03, "surprised": 0.09, "angry": -0.16}[kind]
    lift = {"surprised": 0.1}.get(kind, 0.0)
    bcur = 0.5 + lift + 0.12 * np.sqrt(np.clip(1 - bx * bx, 0, 1)) + tilt * (-x)
    bth = 0.05 * (0.5 + 0.7 * smooth(-1.0, 0.1, bx)) * (1 - 0.5 * smooth(0.5, 1.0, bx))
    brow = (np.abs(y - bcur) < bth) & (np.abs(bx) < 1.0)
    blend(img, BROW, brow * 1.0)
    # soft antialias: blur alpha and colour lightly
    rgba = img
    for _ in range(1):
        rgba = (rgba + np.roll(rgba, 1, 0) + np.roll(rgba, -1, 0) + np.roll(rgba, 1, 1) + np.roll(rgba, -1, 1)) / 5
    return rgba


def mouth_frame(kind):
    i, j = np.mgrid[0:S // 2, 0:S]
    x = (j + 0.5) / S * 2 - 1
    y = 1 - (i + 0.5) / (S // 2) * 2
    img = np.zeros((S // 2, S, 4), np.float32)
    LIPC = (0.84, 0.36, 0.34)
    DARK = (0.18, 0.04, 0.05)
    if kind == "closed":
        cur = -0.05 + 0.1 * x * x
        line = (np.abs(y - cur) < 0.055) & (np.abs(x) < 0.5)
        blend(img, (0.6, 0.22, 0.22), line * 0.9)
        lip = (y > cur - 0.2) & (y < cur + 0.18) & (np.abs(x) < 0.48 * (1 - 0.3 * (y - cur) ** 2))
        blend(img, LIPC, lip * 0.35)
    elif kind == "smile":
        cur = -0.1 + 0.35 * x * x
        line = (np.abs(y - cur) < 0.06) & (np.abs(x) < 0.58)
        blend(img, (0.6, 0.22, 0.22), line * 0.95)
        blend(img, LIPC, ((y > cur - 0.16) & (y < cur + 0.12) & (np.abs(x) < 0.5)) * 0.35)
    elif kind == "aa":
        rr = np.sqrt((x / 0.42) ** 2 + ((y + 0.1) / 0.48) ** 2)
        blend(img, DARK, (rr < 1) * 1.0)
        blend(img, (0.95, 0.92, 0.9), ((rr < 0.98) & (y > 0.12) & (y < 0.24)) * 1.0)       # teeth
        blend(img, LIPC, (smooth(1.25, 1.0, rr) * (rr >= 0.98)) * 0.9)
    elif kind == "oh":
        rr = np.sqrt((x / 0.22) ** 2 + ((y + 0.1) / 0.32) ** 2)
        blend(img, DARK, (rr < 1) * 1.0)
        blend(img, LIPC, (smooth(1.45, 1.0, rr) * (rr >= 0.98)) * 0.9)
    else:  # ee
        rr = np.sqrt((x / 0.6) ** 2 + ((y + 0.05) / 0.2) ** 2)
        blend(img, DARK, (rr < 1) * 1.0)
        blend(img, (0.95, 0.92, 0.9), ((rr < 0.98) & (y > -0.02) & (y < 0.12)) * 1.0)
        blend(img, LIPC, (smooth(1.3, 1.0, rr) * (rr >= 0.98)) * 0.9)
    rgba = img
    rgba = (rgba + np.roll(rgba, 1, 0) + np.roll(rgba, -1, 0) + np.roll(rgba, 1, 1) + np.roll(rgba, -1, 1)) / 5
    return rgba


eyes = np.zeros((2 * S, 3 * S, 4), np.float32)
for k, kind in enumerate(["open", "half", "closed", "happy", "surprised", "angry"]):
    r, c = divmod(k, 3)
    eyes[r * S:(r + 1) * S, c * S:(c + 1) * S] = eye_frame(kind)
Image.fromarray((np.clip(eyes, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "face_eyes.png"))
mouth = np.zeros((S // 2, 5 * S, 4), np.float32)
for k, kind in enumerate(["closed", "smile", "aa", "oh", "ee"]):
    mouth[:, k * S:(k + 1) * S] = mouth_frame(kind)
Image.fromarray((np.clip(mouth, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "face_mouth.png"))
print("wrote", OUT, "face_eyes.png face_mouth.png")
