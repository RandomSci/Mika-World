#!/usr/bin/env python3
"""Oriel's humanoid form, restyled from the developer's own Zahra VRM (visual pass 2).

The developer asked for Zahra_DesertDancer.vrm (Mika-New-Character-Lab, author: the developer) to be COPIED into
the project as Oriel's human body and restyled "to match her style". The VRM file is never modified (its meta
marks modification prohibited for third parties; the restyle is applied at runtime as material overrides, the way
the Character Lab hair fix works). This script reads the VRM's own textures and writes Oriel's recoloured set:

  hood   violet -> deep crimson (the gold edge strips stay gold)
  veil   lavender -> a translucent flame veil (gold at the top burning down to crimson)
  top    cream -> warm ivory-gold (the woven wave pattern kept)
  collar gold filigree -> richer, warmer gold
  skirt  violet pleats -> crimson pleats burning to ember-orange at the hem (her feathers' colours)
  hair   near-black -> deep auburn-crimson with ember lights (the phoenix's red)
  iris   amber -> molten gold with an ember ring (her true form's eyes)

  python3 tools/textures/oriel_zahra_recolor.py assets/characters/phoenix/oriel_zahra_tex
Writes PNGs named after the VRM material they replace; PhoenixHuman swaps them in at runtime.
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets/characters/phoenix/Zahra_DesertDancer.vrm")
OUT = sys.argv[1] if len(sys.argv) > 1 else "oriel_zahra_tex"
os.makedirs(OUT, exist_ok=True)

data = open(SRC, "rb").read()
clen, = struct.unpack("<I", data[12:16])
j = json.loads(data[20:20 + clen])
binchunk = data[20 + clen + 8:]


def image_of(material_name):
    for m in j["materials"]:
        if m["name"] == material_name or m["name"].startswith(material_name):
            t = m["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            ii = j["textures"][t]["source"]
            bv = j["bufferViews"][j["images"][ii]["bufferView"]]
            o = bv.get("byteOffset", 0)
            return np.asarray(Image.open(io.BytesIO(binchunk[o:o + bv["byteLength"]])).convert("RGBA"), dtype=np.float32) / 255.0
    raise KeyError(material_name)


def rgb_to_hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = np.max(a[..., :3], axis=-1)
    mn = np.min(a[..., :3], axis=-1)
    d = mx - mn + 1e-9
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    s = np.where(mx > 1e-6, (mx - mn) / (mx + 1e-9), 0)
    return h, s, mx


def lum(a):
    return a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11


def save(arr, name):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
    print("wrote", name, arr.shape)


def ramp(t, stops):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        m = (t >= t0) & (t <= t1)
        k = ((t - t0) / max(t1 - t0, 1e-6))[..., None]
        out[m] = (np.array(c0) * (1 - k) + np.array(c1) * k)[m]
    return out


# hood: violet cloth -> deep crimson; the gold strips (warm, saturated, bright) stay
a = image_of("NC_Zahra_Hood")
h, s, v = rgb_to_hsv(a)
violet = (h > 0.6) & (h < 0.9)
L = lum(a)
crimson = np.stack([0.5 + 0.9 * L, 0.04 + 0.12 * L, 0.05 + 0.1 * L], -1)
a[..., :3] = np.where(violet[..., None], np.clip(crimson, 0, 1), a[..., :3])
save(a, "NC_Zahra_Hood")

# veil: a translucent flame (gold at the top -> ember -> crimson at the hem), alpha kept
a = image_of("NC_Zahra_Veil")
H = a.shape[0]
y = (np.arange(H) / max(H - 1, 1))[:, None] * np.ones((1, a.shape[1]))
col = ramp(y, [(0.0, (1.0, 0.78, 0.36)), (0.45, (1.0, 0.45, 0.12)), (1.0, (0.75, 0.08, 0.06))])
a[..., :3] = col * (0.75 + 0.35 * lum(a)[..., None])
save(a, "NC_Zahra_Veil")

# top: warm ivory-gold (keep the woven waves)
a = image_of("NC_Zahra_Top")
L = lum(a)
a[..., :3] = np.clip(np.stack([L * 1.04, L * 0.86, L * 0.62], -1), 0, 1)
save(a, "NC_Zahra_Top")

# collar: richer gold
a = image_of("NC_Zahra_Collar")
L = lum(a)
a[..., :3] = np.clip(np.stack([0.25 + L * 0.95, 0.12 + L * 0.66, 0.02 + L * 0.2], -1), 0, 1)
save(a, "NC_Zahra_Collar")

# skirt: crimson pleats burning to ember-orange at the hem (v of this texture runs down the pleats)
a = image_of("NC_Zahra_Skirt")
H = a.shape[0]
y = (np.arange(H) / max(H - 1, 1))[:, None] * np.ones((1, a.shape[1]))
L = lum(a)
Ln = L / max(L.max(), 1e-6)
col = ramp(y, [(0.0, (0.42, 0.03, 0.05)), (0.55, (0.7, 0.05, 0.05)), (0.85, (0.95, 0.24, 0.05)), (1.0, (1.0, 0.55, 0.12))])
a[..., :3] = np.clip(col * (0.55 + 0.6 * Ln[..., None]), 0, 1)
save(a, "NC_Zahra_Skirt")

# hair: deep auburn-crimson, ember lights where the texture is brightest
a = image_of("NC_Zahra_Hair")
L = lum(a)
Ln = (L - L.min()) / max(L.max() - L.min(), 1e-6)
base = np.array([0.34, 0.05, 0.04])          # uniform: the texture's orientation (roots/tips) is not assumed
light = np.array([0.95, 0.32, 0.12])
a[..., :3] = np.clip(base * (0.55 + 0.9 * Ln[..., None]) + light * (Ln[..., None] ** 3) * 0.3, 0, 1)
save(a, "NC_Zahra_Hair")

# iris: molten gold with an ember ring (warm hues only)
a = image_of("F00_000_00_EyeIris_00_EYE")
h, s, v = rgb_to_hsv(a)
warm = s > 0.12
r = np.clip(v, 0, 1)
col = ramp(r, [(0.0, (0.25, 0.05, 0.02)), (0.35, (0.75, 0.22, 0.04)), (0.7, (1.0, 0.62, 0.14)), (1.0, (1.0, 0.86, 0.45))])
a[..., :3] = np.where(warm[..., None], col, a[..., :3])
save(a, "F00_000_00_EyeIris_00_EYE")

# body: the dark arm-warmers painted on the skin texture become deep crimson silk with a gold sheen (skin untouched)
a = image_of("F00_002_02_Body_00_SKIN")
h, s_, v = rgb_to_hsv(a)
L = lum(a)
dark = (L < 0.32) & (s_ < 0.45)
silk = np.stack([0.32 + 0.7 * L, 0.03 + 0.14 * L, 0.04 + 0.08 * L], -1)
a[..., :3] = np.where(dark[..., None], np.clip(silk, 0, 1), a[..., :3])
save(a, "F00_002_02_Body_00_SKIN")
