#!/usr/bin/env python3
"""Leaf-clump atlas for the hero trees: 4 cells (2x2, 512 px each) of many painted leaves composed from the CC0
nature kit's leaf sprites (assets/nature/snm/Leaves.png) - lighter on top, darker beneath, leaves radiating
from the clump's centre.   python3 tools/textures/leaf_clumps.py assets/nature/hero/leaf_clumps.png"""
import math
import os
import random
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
def build_clumps(path):
    from PIL import Image
    src = Image.open(os.path.join(ROOT, "assets/nature/snm/Leaves.png")).convert("RGBA")
    W, H = src.size
    sprites = {"round": (0.80, 0.06, 0.177, 0.21), "heart": (0.80, 0.29, 0.177, 0.26), "broad": (0.33, 0.59, 0.24, 0.39), "thin": (0.058, 0.04, 0.137, 0.39)}
    crops = {k: src.crop((int(r[0] * W), int(r[1] * H), int((r[0] + r[2]) * W), int((r[1] + r[3]) * H))) for k, r in sprites.items()}
    rnd = random.Random(5)
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    cells = [((0, 0), ["round", "heart"], 150), ((512, 0), ["heart", "round", "broad"], 120), ((0, 512), ["thin", "round"], 130), ((512, 512), ["broad", "heart"], 90)]
    for (ox, oy), kinds, count in cells:
        cell = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        for i in range(count):
            # leaves concentrate toward the middle of the card (a clump), lighter on top, darker beneath
            a = rnd.uniform(0, math.tau)
            rr = 200 * math.sqrt(rnd.random()) * (0.85 if i < count * 0.7 else 1.0)
            cx, cy = 256 + math.cos(a) * rr, 256 + math.sin(a) * rr * 0.92
            k = rnd.choice(kinds)
            sp = crops[k]
            s = rnd.uniform(0.32, 0.6) * (1.25 if k == "broad" else 1.0)
            sp = sp.resize((max(4, int(sp.width * s)), max(4, int(sp.height * s))))
            ang = math.degrees(math.atan2(cy - 256, cx - 256)) - 90 + rnd.uniform(-40, 40)
            sp = sp.rotate(-ang, expand=True)
            shade = 0.72 + 0.4 * (1 - (cy / 512)) + rnd.uniform(-0.1, 0.1)
            px = sp.load()
            for yy in range(sp.height):
                for xx in range(sp.width):
                    r_, g_, b_, a_ = px[xx, yy]
                    if a_:
                        px[xx, yy] = (min(255, int(r_ * shade)), min(255, int(g_ * shade)), min(255, int(b_ * shade)), a_)
            cell.alpha_composite(sp, (int(cx - sp.width / 2), int(cy - sp.height / 2)))
        atlas.alpha_composite(cell, (ox, oy))
    atlas.save(path)






if __name__ == "__main__":
    build_clumps(sys.argv[1] if len(sys.argv) > 1 else "leaf_clumps.png")
    print("wrote", sys.argv[1] if len(sys.argv) > 1 else "leaf_clumps.png")
