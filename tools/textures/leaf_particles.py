#!/usr/bin/env python3
"""Single real leaves for wind-blown leaf particles (the cinematic pass: gusts tear leaves from the crowns and blow
the litter): the six scanned beech/hazel leaves of ambientCG LeafSet009 (CC0), cut from its 3x2 sheet with their
opacity, into a 3x2 atlas (RGBA 1024x1024; colour bled under the transparent border so mipmaps have no dark fringe).

  python3 tools/textures/leaf_particles.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "assets", "ambientcg", "LeafSet009")
col = Image.open(os.path.join(SRC, "LeafSet009_2K-JPG_Color.jpg")).convert("RGB").resize((1024, 1024), Image.LANCZOS)
op = Image.open(os.path.join(SRC, "LeafSet009_2K-JPG_Opacity.jpg")).convert("L").resize((1024, 1024), Image.LANCZOS)
rgb = np.asarray(col).astype(np.float32)
a = np.asarray(op).astype(np.float32) / 255.0
a = np.clip((a - 0.35) / 0.3, 0.0, 1.0)            # crisp silhouettes for alpha scissor
# bleed leaf colour outward under the transparent border (no dark fringes when mipmapped)
from scipy import ndimage
mask = a > 0.5
idx = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
rgb = rgb[idx[0], idx[1]]
out = np.dstack([rgb, a * 255.0]).astype(np.uint8)
Image.fromarray(out).save(os.path.join(ROOT, "assets", "nature", "real", "leaf_particles.png"))
print("wrote leaf_particles.png")
