#!/usr/bin/env python3
"""Mika L1 v2 parts, step 1b (Selwyn 2026-10-20): rebuild MIKA_L1_panel as a thin two sided panel.

Meshy made the panel a hollow wedge (a thick gold left side, white on both faces). This keeps only its outline:
  1. the front view silhouette of the source mesh, cut into its 4 sides at the 4 corners,
  2. sides that are straight within 1 percent become exact lines, curved sides are smoothed along their length,
  3. the gold trim is one even width on every edge, measured from the source front (median band width),
     built as a quad strip between the outline and the mitred inset, on both faces,
  4. the inside is a regular Coons patch grid (good for spring bones), white on the front, navy on the back,
  5. front and back are THICK_MM apart, joined by a gold rim strip.
Writes <out>/MIKA_L1_panel.npz (V, F, lab, quads flag) in the source units and glTF axes.
  python3 tools/v2_panel.py <panel.glb> <out dir> [--size-cm 60]"""
import os, sys, json, argparse
import numpy as np, cv2
from shapely.geometry import Polygon
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v2lib import load_glb, labels_of, face_hist

THICK_MM = 1.6
GRID_MM = 12.0
RES = 2048


def silhouette(V, F, lab, front_only=False):
    lo = V[:, :2].min(0) - 0.02; hi = V[:, :2].max(0) + 0.02
    s = (RES - 1) / (hi - lo).max()
    P = ((V[:, :2] - lo) * s)
    P[:, 1] = RES - 1 - P[:, 1]                       # image rows go down
    mask = np.zeros((RES, RES), np.uint8); lbl = np.full((RES, RES), 255, np.uint8); zb = np.full((RES, RES), -9.0)
    pts = (P[F] * 16).round().astype(np.int32)
    for i in range(len(F)):
        cv2.fillConvexPoly(mask, pts[i], 1, shift=4)
    if front_only:                                     # front face colour: draw faces in z order, nearest +Z last
        n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
        z = V[F, 2].mean(1)
        for i in np.argsort(z):
            if n[i, 2] > 0:
                cv2.fillConvexPoly(lbl, pts[i], int(lab[i]), shift=4)
    return mask, lbl, lo, s


def to_xy(c, lo, s):
    c = np.asarray(c, float).copy()
    c[:, 1] = RES - 1 - c[:, 1]
    return c / s + lo


def resample(poly, n):
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    t = np.concatenate([[0], np.cumsum(seg)]); t /= t[-1]
    u = np.linspace(0, 1, n)
    return np.stack([np.interp(u, t, poly[:, 0]), np.interp(u, t, poly[:, 1])], 1)


def clean_side(side, n_fine=400):
    side = resample(side, n_fine)
    a, b = side[0], side[-1]
    d = b - a; L = np.linalg.norm(d); nrm = np.array([-d[1], d[0]]) / L
    dev = (side - a) @ nrm
    if np.abs(dev).max() < 0.01 * L:
        return np.stack([np.linspace(a[0], b[0], n_fine), np.linspace(a[1], b[1], n_fine)], 1), 'straight'
    k = cv2.getGaussianKernel(61, 12).ravel()
    pad = np.concatenate([np.repeat(dev[:1], 30), dev, np.repeat(dev[-1:], 30)])
    sm = np.convolve(pad, k, mode='valid')
    sm = sm - np.linspace(sm[0], sm[-1], len(sm))      # endpoints stay on the corners
    t = np.linspace(0, 1, n_fine)[:, None]
    return a + t * d + sm[:, None] * nrm, 'curved'


def corners_of(poly):
    """the 4 sharpest turns of the closed outline."""
    n = len(poly)
    k = max(n // 60, 3)
    a = poly[(np.arange(n) - k) % n] - poly; b = poly[(np.arange(n) + k) % n] - poly
    cosang = (a * b).sum(1) / np.maximum(np.linalg.norm(a, axis=1) * np.linalg.norm(b, axis=1), 1e-12)
    sharp = cosang + 1                                 # 0 = straight line, larger = sharper
    picks = []
    for i in np.argsort(-sharp):
        if all(min(abs(i - j), n - abs(i - j)) > n // 12 for j in picks):
            picks.append(i)
        if len(picks) == 4:
            break
    return sorted(picks)


def offset_side(side, w):
    d = np.gradient(side, axis=0); d /= np.linalg.norm(d, axis=1, keepdims=True)
    return side + w * np.stack([-d[:, 1], d[:, 0]], 1)          # left normal = inward for a ccw outline


def seg_intersect(A, B):
    """first crossing of polyline A (searched from its end) with polyline B (from its start)."""
    best = None
    for i in range(len(A) - 2, max(len(A) - 200, -1), -1):
        p, r = A[i], A[i + 1] - A[i]
        for j in range(0, min(200, len(B) - 1)):
            q, s_ = B[j], B[j + 1] - B[j]
            den = r[0] * s_[1] - r[1] * s_[0]
            if abs(den) < 1e-15:
                continue
            t = ((q - p)[0] * s_[1] - (q - p)[1] * s_[0]) / den
            u = ((q - p)[0] * r[1] - (q - p)[1] * r[0]) / den
            if 0 <= t <= 1 and 0 <= u <= 1:
                return i, j, p + t * r
    return best


def extend(side, k=0.3):
    a, b = side[0], side[-1]
    d0 = side[1] - side[0]; d1 = side[-1] - side[-2]
    L = np.linalg.norm(b - a)
    return np.concatenate([[a - d0 / np.linalg.norm(d0) * L * k], side, [b + d1 / np.linalg.norm(d1) * L * k]])


def inset_sides(sides, w):
    """offset every side inward by w and cut them where neighbours meet: even width, clean mitred corners."""
    off = [extend(offset_side(sd, w)) for sd in sides]
    cut = []
    for k in range(4):
        A, B = off[k], off[(k + 1) % 4]
        cut.append(seg_intersect(A, B))
    out = []
    for k in range(4):
        i_end, _, p_end = cut[k]                 # where side k meets side k+1
        _, j_start, p_start = cut[k - 1]         # where side k-1 meets side k
        mid = off[k][j_start + 1:i_end + 1]
        out.append(np.concatenate([[p_start], mid, [p_end]]))
    return out


def coons(B, T, Lf, R):
    """B, T run left to right (nu points), Lf, R run bottom to top (nv points)."""
    nu, nv = len(B), len(Lf)
    u = np.linspace(0, 1, nu)[None, :, None]; v = np.linspace(0, 1, nv)[:, None, None]
    P = (1 - v) * B[None] + v * T[None] + (1 - u) * Lf[:, None] + u * R[:, None]
    P -= ((1 - u) * (1 - v) * B[0] + u * (1 - v) * B[-1] + (1 - u) * v * T[0] + u * v * T[-1])
    return P


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('glb'); ap.add_argument('out'); ap.add_argument('--size-cm', type=float, default=60.0)
    a = ap.parse_args()
    V, U, F, tex = load_glb(a.glb)
    lab = face_hist(U, F, labels_of(tex)).argmax(1)
    mm = (V.max(0) - V.min(0)).max() / (a.size_cm * 10)
    mask, lbl, lo, s = silhouette(V, F, lab, front_only=True)
    cs, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = max(cs, key=cv2.contourArea)[:, 0, :].astype(float)
    c = cv2.GaussianBlur(c[None], (1, 9), 0)[0] if len(c) > 20 else c
    outline_img = c
    # gold band width on the source front, in pixels -> units
    dt = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    white = (lbl == 0).astype(np.uint8)
    edge = white - cv2.erode(white, np.ones((3, 3), np.uint8))
    band_px = np.median(dt[edge > 0])
    w = band_px / s
    poly = to_xy(outline_img, lo, s)
    if Polygon(poly).exterior.is_ccw is False:
        poly = poly[::-1]
    ci = corners_of(poly)
    sides = []
    for k in range(4):
        i0, i1 = ci[k], ci[(k + 1) % 4]
        seg = poly[i0:i1 + 1] if i1 > i0 else np.concatenate([poly[i0:], poly[:i1 + 1]])
        sides.append(seg)
    cl = [clean_side(sd) for sd in sides]
    # name the corners: bottom left is the lowest of the left two etc; reorder sides as B, R, T, L (ccw from BL)
    cpts = np.array([sd[0][0] for sd in cl])
    bl = int(np.argmin(cpts[:, 0] + cpts[:, 1] * 0.5 + cpts[:, 1]))  # most left and low
    order = [(bl + k) % 4 for k in range(4)]
    Bs, Rs, Ts, Ls = [cl[i][0] for i in order]
    kinds = [cl[i][1] for i in order]
    outline = np.concatenate([Bs[:-1], Rs[:-1], Ts[:-1], Ls[:-1]])
    isides = inset_sides([Bs, Rs, Ts, Ls], w)
    g = GRID_MM * mm
    L = [np.linalg.norm(np.diff(sd, axis=0), axis=1).sum() for sd in isides]
    nu = max(int(np.ceil(max(L[0], L[2]) / g)), 2) + 1
    nv = max(int(np.ceil(max(L[1], L[3]) / g)), 2) + 1
    iB = resample(isides[0], nu); iR = resample(isides[1], nv); iT = resample(isides[2], nu)[::-1]; iL = resample(isides[3], nv)[::-1]
    oB = resample(Bs, nu); oR = resample(Rs, nv); oT = resample(Ts, nu)[::-1]; oL = resample(Ls, nv)[::-1]
    G = coons(iB, iT, iL, iR)                                           # (nv, nu, 2)
    # 2D vertex list: grid, then outline ring (ccw: B, R, T, L without repeats)
    verts = [G.reshape(-1, 2)]
    gid = np.arange(nv * nu).reshape(nv, nu)
    ring_in = np.concatenate([gid[0, :-1], gid[:-1, -1], gid[-1, ::-1][:-1], gid[::-1, 0][:-1]])
    ring_out_pts = np.concatenate([oB[:-1], oR[:-1], oT[::-1][:-1], oL[::-1][:-1]])
    base = nv * nu
    ring_out = base + np.arange(len(ring_out_pts))
    verts.append(ring_out_pts)
    P2 = np.concatenate(verts)
    quads, qlab = [], []
    for j in range(nv - 1):
        for i in range(nu - 1):
            quads.append((gid[j, i], gid[j, i + 1], gid[j + 1, i + 1], gid[j + 1, i])); qlab.append('in')
    n = len(ring_in)
    for k in range(n):
        quads.append((ring_out[k], ring_out[(k + 1) % n], ring_in[(k + 1) % n], ring_in[k])); qlab.append('band')
    quads = np.array(quads); qlab = np.array(qlab)
    t = THICK_MM * mm
    nP = len(P2)
    V3 = np.concatenate([np.c_[P2, np.full(nP, t / 2)], np.c_[P2, np.full(nP, -t / 2)]])
    WHITE, NAVY, GOLD = 0, 1, 2
    Fq, Lq = [], []
    for q, l in zip(quads, qlab):                         # front (+Z), ccw seen from +Z
        Fq.append(tuple(q)); Lq.append(WHITE if l == 'in' else GOLD)
    for q, l in zip(quads, qlab):                         # back (-Z), reversed winding
        Fq.append(tuple(nP + np.array(q[::-1]))); Lq.append(NAVY if l == 'in' else GOLD)
    for k in range(n):                                    # rim
        a0, a1 = ring_out[k], ring_out[(k + 1) % n]
        Fq.append((a1, a0, nP + a0, nP + a1)); Lq.append(GOLD)
    Fq = np.array(Fq); Lq = np.array(Lq)
    # check outward winding of the rim against the polygon orientation
    tri = np.concatenate([Fq[:, [0, 1, 2]], Fq[:, [0, 2, 3]]]); lab3 = np.concatenate([Lq, Lq])
    os.makedirs(a.out, exist_ok=True)
    np.savez_compressed(f'{a.out}/MIKA_L1_panel.npz', V=V3, F=tri, lab=lab3, Q=Fq, Qlab=Lq)
    st = {'trim_width_mm': round(float(w / mm), 2), 'thickness_mm': THICK_MM, 'grid': [int(nu), int(nv)],
          'sides_B_R_T_L': kinds, 'quads': int(len(Fq)), 'units_per_mm': float(mm)}
    json.dump(st, open(f'{a.out}/MIKA_L1_panel.json', 'w'), indent=1)
    print('PANEL', json.dumps(st))


if __name__ == '__main__':
    main()
