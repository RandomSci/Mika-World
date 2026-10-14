#!/usr/bin/env python3
"""Force VRAM compression + mipmaps on all material textures (Godot can't auto-detect 3D use
for textures assigned from code). Normal maps -> RGTC normal-map mode. HDRIs untouched."""
import glob, os, re, sys
root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
n = 0
# optional sub-folders of assets/ to limit it to (it rewrites import settings: never run it wider than intended)
dirs = sys.argv[1:] or ["."]
imports = []
for d in dirs:
    imports += glob.glob(os.path.join(root, "assets", d, "**", "*.import"), recursive=True)
for imp in imports:
    src = imp[:-7]
    if not src.lower().endswith((".jpg", ".jpeg", ".png")):
        continue
    s = open(imp).read()
    if 'importer="texture"' not in s:
        continue
    is_normal = "nor_gl" in src or "NormalGL" in src or "_normal" in src.lower()
    rep = {"compress/mode": "2", "mipmaps/generate": "true", "compress/high_quality": "false",
           "compress/normal_map": "1" if is_normal else "2", "detect_3d/compress_to": "0"}
    if "/assets/vfx/" in src:
        # flipbooks: colour is premultiplied by coverage - never bleed colour into transparent texels
        rep["process/fix_alpha_border"] = "false"
        rep["process/premult_alpha"] = "false"
    for k, v in rep.items():
        s, c = re.subn(rf"^{re.escape(k)}=.*$", f"{k}={v}", s, flags=re.M)
        if c == 0:
            s = s.replace("[params]\n", f"[params]\n\n{k}={v}\n", 1)
    open(imp, "w").write(s)
    n += 1
print("updated", n, "texture import files")
