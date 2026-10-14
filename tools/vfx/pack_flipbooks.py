#!/usr/bin/env python3
"""Pack the simulated fire/smoke frames (tools/vfx/fire_flipbooks.py) into the game's flipbook atlases.

For each kind: <kind>_fire.png (RGB: the fire's own light / 4, sRGB-encoded) and <kind>_smoke.png (RGB: the lit smoke,
premultiplied by its coverage, sRGB-encoded; A: coverage, linear), frames left-to-right, top-to-bottom. Looping kinds
(flame, vortex) are made seamless by crossfading the frames that follow the loop into its first frames. Every cell
is faded to nothing at its border (no hard sprite edges ever). flipbooks.json records the grid, the size in metres
and the pivot (where the emitter was, so the game can stand the sprite on it).

  python3 tools/vfx/pack_flipbooks.py <work_dir> [kinds...]
"""
import json
import os
import sys

import cv2
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORK = os.path.abspath(sys.argv[1])
OUT = os.path.join(ROOT, "assets", "vfx", "fire")
# kind: grid (cols, rows), loop crossfade frames (0 = one-shot), size in metres (w, h), pivot (x, y from the top-left, 0..1)
SPEC = {
	"explosion": dict(cols=8, rows=8, loop=0, size=(8.0, 8.0), pivot=(0.5, 0.65)),
	"burst": dict(cols=8, rows=4, loop=0, size=(3.2, 3.2), pivot=(0.5, 0.625)),
	"smoke": dict(cols=8, rows=8, loop=0, size=(6.0, 6.0), pivot=(0.5, 0.633)),
	"flame": dict(cols=8, rows=6, loop=10, size=(2.0, 4.0), pivot=(0.5, 0.95)),
	"vortex": dict(cols=8, rows=6, loop=10, size=(6.0, 9.0), pivot=(0.5, 0.98)),
}


def read(path, channels):
	im = cv2.imread(path, cv2.IMREAD_UNCHANGED)
	if im is None:
		raise SystemExit("missing " + path)
	im = im.astype(np.float32) / (65535.0 if im.dtype == np.uint16 else 255.0)
	if channels == 3:
		return im[..., ::-1] if im.ndim == 3 else np.dstack([im] * 3)
	return im if im.ndim == 2 else im[..., 0]


def srgb(x):
	x = np.clip(x, 0.0, 1.0)
	return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def radial_mask(h, w, pivot):
	"""Round falloff about the sim's emitter for blasts and puffs (a box fade still shows straight edges when dense
	smoke reaches the cell border)."""
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	cy, cx = pivot[1] * h, pivot[0] * w
	ry = max(cy, h - cy)
	r = np.sqrt(((xx - cx) / (w * 0.5)) ** 2 + ((yy - cy) / ry) ** 2)
	m = 1.0 - np.clip((r - 0.62) / 0.36, 0.0, 1.0)
	return m * m * (3.0 - 2.0 * m)


def edge_mask(h, w, frac=0.07):
	yy = np.minimum(np.arange(h), np.arange(h)[::-1]) / (h * frac)
	xx = np.minimum(np.arange(w), np.arange(w)[::-1]) / (w * frac)
	m = np.clip(np.minimum(yy[:, None], xx[None, :]), 0.0, 1.0)
	return m * m * (3.0 - 2.0 * m)


meta_path = os.path.join(OUT, "flipbooks.json")
meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
os.makedirs(OUT, exist_ok=True)
for kind in (sys.argv[2:] or list(SPEC)):
	sp = SPEC[kind]
	d = os.path.join(WORK, kind)
	names = sorted(f for f in os.listdir(d) if f.startswith("a_") and f.endswith(".png"))
	ids = [n[2:-4] for n in names]
	E = [read(os.path.join(d, "e_%s.png" % i), 3) for i in ids]
	S = [read(os.path.join(d, "s_%s.png" % i), 3) for i in ids]
	A = [read(os.path.join(d, "a_%s.png" % i), 1) for i in ids]
	n = sp["cols"] * sp["rows"]
	if sp["loop"]:
		x = sp["loop"]
		if len(A) < n + x:
			raise SystemExit("%s: %d frames, need %d for the loop" % (kind, len(A), n + x))
		def looped(L):
			out = [f.copy() for f in L[:n]]
			for j in range(x):
				k = j / float(x)
				out[j] = L[n + j] * (1.0 - k) + L[j] * k
			return out
		E, S, A = looped(E), looped(S), looped(A)
	else:
		E, S, A = E[:n], S[:n], A[:n]
	h, w = A[0].shape
	m = edge_mask(h, w) if sp["loop"] else edge_mask(h, w) * radial_mask(h, w, sp["pivot"])
	fire = np.zeros((h * sp["rows"], w * sp["cols"], 3), np.float32)
	smoke = np.zeros((h * sp["rows"], w * sp["cols"], 4), np.float32)
	peak_e = 0.0
	for i in range(len(A)):
		r, c = divmod(i, sp["cols"])
		ys, xs = slice(r * h, (r + 1) * h), slice(c * w, (c + 1) * w)
		fire[ys, xs] = E[i] * m[..., None]
		smoke[ys, xs, :3] = S[i] * m[..., None]
		smoke[ys, xs, 3] = A[i] * m
		peak_e = max(peak_e, float(E[i].max()))
	has_fire = peak_e > 0.004
	if has_fire:
		cv2.imwrite(os.path.join(OUT, kind + "_fire.png"), (srgb(fire)[..., ::-1] * 255.0 + 0.5).astype(np.uint8))
	sm = np.dstack([srgb(smoke[..., :3]), np.clip(smoke[..., 3:], 0, 1)])
	bgra = np.dstack([sm[..., 2], sm[..., 1], sm[..., 0], sm[..., 3]])
	cv2.imwrite(os.path.join(OUT, kind + "_smoke.png"), (bgra * 255.0 + 0.5).astype(np.uint8))
	meta[kind] = {"cols": sp["cols"], "rows": sp["rows"], "frames": len(A), "cell_px": [w, h], "size_m": list(sp["size"]),
		"pivot": list(sp["pivot"]), "loop": bool(sp["loop"]), "fps": 30, "fire": has_fire, "fire_scale": 4.0}
	print("%-10s %2d frames  cell %dx%d  atlas %dx%d  fire peak %.2f" % (kind, len(A), w, h, w * sp["cols"], h * sp["rows"], peak_e * 4.0))
json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)
