#!/usr/bin/env python3
"""Oriel's humanoid textures (visual pass): her human form is built on the developer's own VRoid base body
(assets/characters/luna/forms/Luna_Level01.vrm - read, never modified), re-dressed in her identity: the gown
re-dyed deep crimson with ember-gold where it was pale (the gold embroidery and sash kept), the hair crimson at
the roots burning to gold at the tips, the iris molten gold, brows dark crimson, the sandals gold.

  python3 tools/textures/oriel_recolor.py assets/characters/phoenix/oriel_tex
Writes PNGs named after the VRM material they replace (VoiceService-free; PhoenixHuman swaps them at runtime).
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets/characters/luna/forms/Luna_Level01.vrm")
OUT = sys.argv[1] if len(sys.argv) > 1 else "oriel_tex"
os.makedirs(OUT, exist_ok=True)

data = open(SRC, "rb").read()
clen, = struct.unpack("<I", data[12:16])
j = json.loads(data[20:20 + clen])
binchunk = data[20 + clen + 8:]


def image_of(material_prefix):
    for m in j["materials"]:
        if m["name"].startswith(material_prefix):
            t = m["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            ii = j["textures"][t]["source"]
            bv = j["bufferViews"][j["images"][ii]["bufferView"]]
            o = bv.get("byteOffset", 0)
            return Image.open(io.BytesIO(binchunk[o:o + bv["byteLength"]])).convert("RGBA")
    raise KeyError(material_prefix)


def rgb_to_hsv(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = np.max(a[..., :3], axis=-1)
    mn = np.min(a[..., :3], axis=-1)
    d = mx - mn + 1e-9
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    s = np.where(mx > 1e-6, (mx - mn) / (mx + 1e-9), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m, 0], out[m, 1], out[m, 2] = a[m], b[m], c[m]
    return out


def save(img_arr, name):
    Image.fromarray((np.clip(img_arr, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


def redye_gown(prefix, name):
    a = np.asarray(image_of(prefix), dtype=np.float32) / 255.0
    h, s, v = rgb_to_hsv(a)
    blue = ((h > 0.52) & (h < 0.86) & (s > 0.12)) | ((s < 0.18) & (v > 0.45) & (v < 0.97))   # navy, violet and the pale lace
    # dark navy -> deep crimson; pale lace -> ember gold (light value rises toward gold)
    nh = np.where(v > 0.62, 0.08 - 0.06 * np.clip((v - 0.62) / 0.35, 0, 1), 0.985)
    ns = np.clip(np.where(v > 0.62, 0.55 + 0.2 * s, 0.82 + 0.1 * s), 0, 1)
    nv = np.where(v > 0.62, 0.55 + 0.45 * v, np.clip(v * 1.65 + 0.06, 0, 0.9))
    rgb = hsv_to_rgb(np.where(blue, nh, h), np.where(blue, ns, s), np.where(blue, nv, v))
    a[..., :3] = rgb
    save(a, name)


def hair(prefix, name, roots=(0.45, 0.04, 0.05), mid=(0.8, 0.16, 0.06), tips=(1.0, 0.68, 0.24)):
    a = np.asarray(image_of(prefix), dtype=np.float32) / 255.0
    H = a.shape[0]
    y = (np.arange(H) / (H - 1))[:, None]
    lum = (a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11)
    lum = lum / max(lum.max(), 1e-6)
    t = np.clip(y, 0, 1)
    c = np.where(t[..., None] < 0.55, np.array(roots) + (np.array(mid) - np.array(roots)) * (t / 0.55)[..., None],
                 np.array(mid) + (np.array(tips) - np.array(mid)) * ((t - 0.55) / 0.45)[..., None])
    a[..., :3] = c * (0.55 + 0.75 * lum[..., None])
    save(a, name)


def iris(prefix, name):
    a = np.asarray(image_of(prefix), dtype=np.float32) / 255.0
    h, s, v = rgb_to_hsv(a)
    warm = s > 0.15
    nh = np.where(v > 0.5, 0.115, np.where(v > 0.25, 0.07, 0.99))       # gold core, amber, a crimson outer ring
    rgb = hsv_to_rgb(np.where(warm, nh, h), np.where(warm, np.clip(s * 1.15, 0, 1), s), np.where(warm, np.clip(v * 1.3, 0, 1), v))
    a[..., :3] = rgb
    save(a, name)


def tint(prefix, name, color, strength=0.85):
    a = np.asarray(image_of(prefix), dtype=np.float32) / 255.0
    lum = a[..., 0] * 0.3 + a[..., 1] * 0.59 + a[..., 2] * 0.11
    a[..., :3] = a[..., :3] * (1 - strength) + (np.array(color) * (0.4 + 1.0 * lum[..., None])) * strength
    save(a, name)


redye_gown("N00_002_03_Tops_01_CLOTH_02", "Tops_01_CLOTH_02")
redye_gown("N00_002_03_Tops_01_CLOTH_03", "Tops_01_CLOTH_03")
redye_gown("N00_008_01_Shoes_01_CLOTH_01", "Shoes_01_CLOTH_01")
redye_gown("N00_008_01_Shoes_01_CLOTH_02", "Shoes_01_CLOTH_02")
hair("N00_000_Hair_00_HAIR", "Hair_00_HAIR")
hair("N00_000_00_HairBack_00_HAIR", "HairBack_00_HAIR", tips=(0.85, 0.22, 0.07))
iris("N00_000_00_EyeIris_00_EYE", "EyeIris_00_EYE")
tint("N00_000_00_FaceBrow_00_FACE", "FaceBrow_00_FACE", (0.42, 0.06, 0.05))
