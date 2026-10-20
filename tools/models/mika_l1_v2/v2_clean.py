#!/usr/bin/env python3
"""Mika L1 v2 parts, step 1a (Selwyn 2026-10-20): even colours with no texture.

For each Meshy part (one 4K texture already snapped to white F4F4FA, navy 1C2556, gold D8B26A, sky 6FA8E8):
  1. weld the seam split vertices so the mesh is one surface,
  2. refine (red green, conforming, no T junctions) every face that holds a colour border until its edges are
     about 4 texels long, so trim borders narrower than a face are kept,
  3. sample the palette label under every vertex (from each face corner, nudged 1.5 texels inside its own UV
     island) as a soft one hot vector, and smooth it on the mesh (not in the fragmented UV atlas),
  4. cut the faces exactly along the borders of the smoothed colour regions (marching triangles on
     h_k = f_k - max other f), so borders are straight lines of new edges instead of saw teeth,
  5. give every face the colour of its region, fold specks smaller than SPECK_MM2 into their neighbour.
Writes <out>/<part>.npz (V, F, label, corner uv) and a stats line. Blender (v2_build.py) turns it into materials.

  python3 tools/v2_clean.py <part.glb> <out dir> [--size-cm 40]"""
import os, sys, json, argparse
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from v2lib import load_glb, labels_of, face_hist, weld, NAMES

TARGET_TEX = 4.0        # refine border faces until edges are about this many texels
TARGET_MM = 0.5         # and no finer than this in real millimetres
SMOOTH_MM = 0.0         # gaussian radius of the border smoothing, in real millimetres (0 = off)
SPECK_MM2 = 6.0         # colour islands smaller than this (at the part's real size) are noise


def edges_of(F):
    return np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])


def sample_corners(CU, L):
    """label under each face corner, nudged toward the face centre by 1.5 texels."""
    n = L.shape[0]
    c = CU.mean(1, keepdims=True)
    d = np.linalg.norm((c - CU) * n, axis=-1, keepdims=True)
    k = np.minimum(0.3, 1.5 / np.maximum(d, 1e-6))
    P = CU + (c - CU) * k
    ij = np.clip((P * n).astype(int), 0, n - 1)
    return L[ij[..., 1], ij[..., 0]]


def border_distance(L, U0, F0):
    """distance in texels to the nearest colour border inside the same UV island (borders between two
    islands packed side by side in the atlas are not colour borders)."""
    import scipy.sparse as sp, scipy.sparse.csgraph as cg
    from v2lib import face_raster
    nv = int(F0.max()) + 1
    A = sp.coo_matrix((np.ones(len(F0) * 3), (F0.ravel(), np.roll(F0, 1, 1).ravel())), shape=(nv, nv))
    _, vis = cg.connected_components(A, directed=False)
    isl = np.concatenate([[-1], vis[F0[:, 0]]])[face_raster(U0, F0, L.shape[0])]
    b = np.zeros(L.shape, bool)
    for ax in (0, 1):
        d = (np.diff(L.astype(np.int16), axis=ax) != 0) & (np.diff(isl, axis=ax) == 0) & (np.take(isl, range(L.shape[ax] - 1), axis=ax) >= 0)
        if ax == 0:
            b[:-1] |= d; b[1:] |= d
        else:
            b[:, :-1] |= d; b[:, 1:] |= d
    dist = cv2.distanceTransform((~b).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    return np.maximum(dist - 0.5, 0)                 # both pixels next to a border are marked: centre the zero


def bilinear(img, P):
    n = img.shape[0]
    x = np.clip(P[..., 0] * n - 0.5, 0, n - 1.001); y = np.clip(P[..., 1] * n - 0.5, 0, n - 1.001)
    x0 = x.astype(int); y0 = y.astype(int); fx = x - x0; fy = y - y0
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy) +
            img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def vertex_field(nv, F, CU, L, D):
    """signed distance per colour: +texels inside that colour, -texels outside, averaged over a vertex's corners
    (each sampled half a texel inside its own face, so it reads its own island)."""
    n = L.shape[0]
    c = CU.mean(1, keepdims=True)
    d = np.linalg.norm((c - CU) * n, axis=-1, keepdims=True)
    P = CU + (c - CU) * np.minimum(0.3, 2.0 / np.maximum(d, 1e-6))
    ij = np.clip((P * n).astype(int), 0, n - 1)
    lab = L[ij[..., 1], ij[..., 0]].ravel()
    dist = bilinear(D, P).ravel()
    vid = F.ravel()
    # one corner per vertex: the one deepest inside its colour. A corner on a seam that reads the thin rim of
    # wrong colour Meshy leaves along island edges is always close to a border, so it loses.
    o = np.lexsort((-dist, vid))
    first = np.ones(len(o), bool); first[1:] = vid[o][1:] != vid[o][:-1]
    pick = o[first]
    f = np.zeros((nv, 4))
    f[vid[pick]] = -dist[pick, None]
    f[vid[pick], lab[pick]] = dist[pick]
    # a colour border that runs along a UV seam is invisible to the distance map (it only sees borders inside
    # one island). A vertex whose corners read two colours with confidence sits on such a border: put it on
    # the cut line for those colours.
    conf = dist > 1.5
    seen = np.zeros((nv, 4), bool)
    seen[vid[conf], lab[conf]] = True
    on = seen.sum(1) > 1
    f[on] = np.where(seen[on], 0.0, -np.abs(f[on]).max(1, keepdims=True) - 1)
    return f


def vertex_normals(V, F):
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    vn = np.zeros_like(V)
    for k in range(3):
        np.add.at(vn, F[:, k], n)
    return vn / np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)


def repair_outliers(F, f, it=3):
    """a vertex whose colour disagrees with nearly all its neighbours read the wrong UV island at a seam: give it
    the mean of its neighbours. Straight borders are untouched (border vertices have about half their
    neighbours on each side)."""
    E = np.unique(np.sort(edges_of(F), 1), axis=0)
    deg = np.bincount(E.ravel(), minlength=len(f))
    fixed = 0
    for _ in range(it):
        lab = f.argmax(1)
        same = np.zeros(len(f)); acc = np.zeros_like(f)
        for a, b in ((E[:, 0], E[:, 1]), (E[:, 1], E[:, 0])):
            np.add.at(same, a, lab[a] == lab[b]); np.add.at(acc, a, f[b])
        bad = (deg > 0) & (same / np.maximum(deg, 1) < 0.25)
        if not bad.any():
            break
        f = f.copy(); f[bad] = acc[bad] / deg[bad, None]; fixed += int(bad.sum())
    return f, fixed


def smooth(V, F, f, sigma):
    """gaussian average of the label field over a fixed real radius (independent of face size), only across
    surfaces facing the same way, so the inside and outside of a thick shell never mix."""
    from scipy.spatial import cKDTree
    vn = vertex_normals(V, F)
    pure = f.max(1) > 0.999
    lv = f.argmax(1)
    tree = cKDTree(V)
    near = np.zeros(len(V), bool)
    imp = np.nonzero(~pure)[0]
    for lst in tree.query_ball_point(V[imp], 3 * sigma):
        near[lst] = True
    # vertices whose ball holds more than one colour
    todo = np.nonzero(near)[0]
    out = f.copy()
    for i, lst in zip(todo, tree.query_ball_point(V[todo], 2.5 * sigma)):
        lst = np.asarray(lst)
        w = np.exp(-0.5 * (np.linalg.norm(V[lst] - V[i], axis=1) / sigma) ** 2) * np.clip(vn[lst] @ vn[i], 0, 1) ** 2
        out[i] = (f[lst] * w[:, None]).sum(0) / max(w.sum(), 1e-12)
    return out


def refine(V, F, CU, mark):
    """red green split: every edge of a marked face is halved; neighbours are split to stay conforming."""
    E = np.sort(edges_of(F[mark]), 1)
    E = np.unique(E, axis=0)
    key = {tuple(e): len(V) + i for i, e in enumerate(E)}
    Vn = np.concatenate([V, (V[E[:, 0]] + V[E[:, 1]]) / 2])
    outF, outU = [], []
    for fi in range(len(F)):
        a, b, c = F[fi]; ua, ub, uc = CU[fi]
        mab = key.get((min(a, b), max(a, b))); mbc = key.get((min(b, c), max(b, c))); mca = key.get((min(c, a), max(c, a)))
        s = (mab is not None) + (mbc is not None) + (mca is not None)
        if s == 0:
            outF.append((a, b, c)); outU.append((ua, ub, uc)); continue
        uab, ubc, uca = (ua + ub) / 2, (ub + uc) / 2, (uc + ua) / 2
        if s == 3:
            outF += [(a, mab, mca), (mab, b, mbc), (mca, mbc, c), (mab, mbc, mca)]
            outU += [(ua, uab, uca), (uab, ub, ubc), (uca, ubc, uc), (uab, ubc, uca)]
            continue
        # rotate so the pattern starts at a fixed edge
        tri = [(a, ua), (b, ub), (c, uc)]; mids = [(mab, uab), (mbc, ubc), (mca, uca)]
        for r in range(3):
            if s == 1 and mids[0][0] is not None:
                break
            if s == 2 and mids[0][0] is not None and mids[1][0] is not None:
                break
            tri = tri[1:] + tri[:1]; mids = mids[1:] + mids[:1]
        (p, up), (q, uq), (t, ut) = tri
        if s == 1:
            (m, um) = mids[0]
            outF += [(p, m, t), (m, q, t)]; outU += [(up, um, ut), (um, uq, ut)]
        else:
            (m1, u1), (m2, u2) = mids[0], mids[1]
            outF += [(p, m1, t), (m1, q, m2), (m1, m2, t)]; outU += [(up, u1, ut), (u1, uq, u2), (u1, u2, ut)]
    return Vn, np.array(outF, np.int64), np.array(outU)


def cut(V, F, CU, fld, g, eps=1e-7):
    """split faces along g = 0 (g per vertex), new vertices shared between faces."""
    g = np.where(np.abs(g) < eps, 0.0, g)
    s = np.sign(g)
    newV, newf = [], []
    key = {}

    def mid(a, b):
        k = (a, b) if a < b else (b, a)
        if k not in key:
            t = g[k[0]] / (g[k[0]] - g[k[1]])
            key[k] = len(V) + len(newV)
            newV.append(V[k[0]] * (1 - t) + V[k[1]] * t); newf.append(fld[k[0]] * (1 - t) + fld[k[1]] * t)
        return key[k]

    def ut(ua, ub, a, b):
        t = g[a] / (g[a] - g[b])
        return ua * (1 - t) + ub * t
    outF, outU = [], []
    S = s[F]
    cross = (S.max(1) > 0) & (S.min(1) < 0)
    for fi in np.nonzero(~cross)[0]:
        outF.append(tuple(F[fi])); outU.append(tuple(CU[fi]))
    for fi in np.nonzero(cross)[0]:
        idx = list(F[fi]); uv = list(CU[fi]); ss = list(S[fi])
        if 0 in ss:                                     # one vertex on the line, the other two on opposite sides
            r = ss.index(0)
            idx = idx[r:] + idx[:r]; uv = uv[r:] + uv[:r]
            z, a, b = idx; uz, ua, ub = uv
            m = mid(a, b); um = ut(ua, ub, a, b)
            outF += [(z, a, m), (z, m, b)]; outU += [(uz, ua, um), (uz, um, ub)]
            continue
        for r in range(3):                              # the vertex alone on its side goes first
            if ss[r] != ss[(r + 1) % 3] and ss[r] != ss[(r + 2) % 3]:
                break
        idx = idx[r:] + idx[:r]; uv = uv[r:] + uv[:r]
        a, b, c = idx; ua, ub, uc = uv
        mab, mca = mid(a, b), mid(c, a)
        uab, uca = ut(ua, ub, a, b), ut(uc, ua, c, a)
        outF += [(a, mab, mca), (mab, b, c), (mab, c, mca)]
        outU += [(ua, uab, uca), (uab, ub, uc), (uab, uc, uca)]
    if newV:
        V = np.concatenate([V, np.array(newV)]); fld = np.concatenate([fld, np.array(newf)])
    return V, np.array(outF, np.int64), np.array(outU), fld


def face_areas(V, F):
    return 0.5 * np.linalg.norm(np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]]), axis=1)


def despeckle(V, F, lab, min_area):
    import scipy.sparse as sp, scipy.sparse.csgraph as cg
    E = edges_of(F); fid = np.tile(np.arange(len(F)), 3)
    Es = np.sort(E, 1)
    o = np.lexsort((Es[:, 1], Es[:, 0])); Es, fid = Es[o], fid[o]
    same = np.all(Es[1:] == Es[:-1], axis=1)
    pa, pb = fid[:-1][same], fid[1:][same]
    area = face_areas(V, F)
    changed = 0
    for _ in range(4):
        keep = lab[pa] == lab[pb]
        A = sp.coo_matrix((np.ones(keep.sum()), (pa[keep], pb[keep])), shape=(len(F), len(F)))
        nc, comp = cg.connected_components(A, directed=False)
        carea = np.bincount(comp, area, nc)
        share = np.bincount(lab, area, 4) / area.sum()
        small = (carea[comp] < min_area) | (share[lab] < 0.001)      # a colour under 0.1 percent is noise
        if not small.any():
            break
        # neighbour vote across the component's border
        border = lab[pa] != lab[pb]
        votes = np.zeros((nc, 4))
        for x, y in ((pa, pb), (pb, pa)):
            m = border & small[x]
            np.add.at(votes, (comp[x[m]], lab[y[m]]), 1)
        cs = np.unique(comp[small])
        new = votes[cs].argmax(1); ok = votes[cs].sum(1) > 0
        mp = dict(zip(cs[ok], new[ok]))
        for fi in np.nonzero(small)[0]:
            if comp[fi] in mp:
                lab[fi] = mp[comp[fi]]; changed += 1
    return lab, changed


def clean(path, size_cm=40.0, verbose=True):
    V0, U0, F0, tex = load_glb(path)
    L = labels_of(tex); n = L.shape[0]
    D = border_distance(L, U0, F0)
    V, inv = weld(V0)
    F = inv[F0]; CU = U0[F0]
    ext = (V.max(0) - V.min(0)).max()
    mm = ext / (size_cm * 10.0)                                  # model units per millimetre at real size
    for level in range(4):
        fid_hist = face_hist_cu(CU, L)
        maj = fid_hist.max(1) / np.maximum(fid_hist.sum(1), 1)
        fv = vertex_field(len(V), F, CU, L, D).argmax(1)
        lv = fv[F]
        mixed = (maj < 0.995) | (lv.min(1) != lv.max(1)) | (lv[:, 0] != fid_hist.argmax(1))
        etex = np.max(np.linalg.norm((CU - np.roll(CU, 1, 1)) * n, axis=-1), axis=1)
        if level == 0:                                           # one ring of neighbours too, so the smoothed
            ring = np.zeros(len(V), bool); ring[F[mixed].ravel()] = True   # border always runs through fine faces
            mixed = ring[F].any(1)
        emm = np.max(np.linalg.norm(V[F] - V[np.roll(F, 1, 1)], axis=-1), axis=1) / mm
        mark = mixed & (etex > TARGET_TEX) & (emm > TARGET_MM)
        if verbose:
            print(f'  level {level} faces {len(F)} mixed {mixed.sum()} to split {mark.sum()}', flush=True)
        if not mark.any():
            break
        V, F, CU = refine(V, F, CU, mark)
    fld = vertex_field(len(V), F, CU, L, D)
    fld, nfix = repair_outliers(F, fld)
    if SMOOTH_MM > 0:
        fld = smooth(V, F, fld, SMOOTH_MM * mm)
    for k in range(4):
        if fld[:, k].max() <= 0:
            continue
        others = np.delete(fld, k, axis=1).max(1)
        V, F, CU, fld = cut(V, F, CU, fld, fld[:, k] - others)
    cen = fld[F].mean(1)
    lab = cen.argmax(1)
    # each face then takes the colour most of its own texels show (what the texture draws there), where it
    # covers enough texels to say; this removes the few places where a seam put the cut a little off
    hst = face_hist_cu(CU, L)
    tot = hst.sum(1); share = hst.max(1) / np.maximum(tot, 1)
    sure = (tot >= 4) & (share >= 0.6)
    ij = np.clip((CU.mean(1) * n).astype(int), 0, n - 1)
    cen_tex = L[ij[:, 1], ij[:, 0]]                      # faces under 4 texels: the texel at their centre
    new = np.where(sure, hst.argmax(1), np.where(tot < 4, cen_tex, lab))
    relabel = int((new != lab).sum())
    lab = new
    lab, changed = despeckle(V, F, lab, SPECK_MM2 * mm * mm)
    area = face_areas(V, F)
    stats = {'faces_in': int(len(F0)), 'faces_out': int(len(F)), 'verts_out': int(len(V)), 'despeckled_faces': int(changed), 'repaired_vertices': nfix, 'relabelled_by_texels': relabel,
             'area_share': {NAMES[k]: round(float(area[lab == k].sum() / area.sum()) * 100, 2) for k in range(4)},
             'units_per_mm': float(mm)}
    return V, F, CU, lab, stats


def smooth_borders(V, F, lab, it=8, lam=0.5):
    """straighten the texel stairs: every vertex on a colour border that sits on exactly two border edges moves
    toward the middle of its two border neighbours, along the surface only (its normal part is removed), never
    more than a third of its shortest edge per pass. Junctions of three colours and open mesh edges stay put."""
    E = edges_of(F); fid = np.tile(np.arange(len(F)), 3)
    Es = np.sort(E, 1)
    o = np.lexsort((Es[:, 1], Es[:, 0])); Es, fid = Es[o], fid[o]
    same = np.all(Es[1:] == Es[:-1], axis=1)
    key, cnt = np.unique(Es, axis=0, return_counts=True)
    openv = np.zeros(len(V), bool); openv[key[cnt == 1].ravel()] = True
    bd = Es[1:][same & (lab[fid[:-1]] != lab[fid[1:]])]
    bd = np.unique(bd, axis=0)
    deg = np.bincount(bd.ravel(), minlength=len(V))
    nb = [[] for _ in range(len(V))]
    for a, b in bd:
        nb[a].append(b); nb[b].append(a)
    mov = np.nonzero((deg == 2) & ~openv)[0]
    if len(mov) == 0:
        return V, 0
    allE = np.unique(Es, axis=0)
    elen = np.linalg.norm(V[allE[:, 0]] - V[allE[:, 1]], axis=1)
    emin = np.full(len(V), np.inf)
    np.minimum.at(emin, allE[:, 0], elen); np.minimum.at(emin, allE[:, 1], elen)
    vn = vertex_normals(V, F)
    A = np.array([nb[v][0] for v in mov]); B = np.array([nb[v][1] for v in mov])
    V = V.copy()
    for _ in range(it):
        d = lam * ((V[A] + V[B]) / 2 - V[mov])
        d -= (d * vn[mov]).sum(1, keepdims=True) * vn[mov]
        ln = np.linalg.norm(d, axis=1, keepdims=True)
        d *= np.minimum(1, emin[mov, None] / 3 / np.maximum(ln, 1e-12))
        V[mov] += d
    return V, len(mov)


def clean_texel(path, size_cm=40.0, max_tex=3.0, verbose=True):
    """texel exact route: refine border faces to max_tex texel edges, colour each face from its own texels,
    then smooth the borders along the surface."""
    V0, U0, F0, tex = load_glb(path)
    L = labels_of(tex); n = L.shape[0]
    V, inv = weld(V0)
    F = inv[F0]; CU = U0[F0]
    mm = (V.max(0) - V.min(0)).max() / (size_cm * 10.0)
    for level in range(8):
        h = face_hist_cu(CU, L)
        maj = h.max(1) / np.maximum(h.sum(1), 1)
        ij = np.clip((CU * n).astype(int), 0, n - 1)
        cl = L[ij[..., 1], ij[..., 0]]
        mixed = (maj < 0.999) | (cl.min(1) != cl.max(1))
        if level == 0:
            ring = np.zeros(len(V), bool); ring[F[mixed].ravel()] = True
            mixed = ring[F].any(1)
        etex = np.max(np.linalg.norm((CU - np.roll(CU, 1, 1)) * n, axis=-1), axis=1)
        mark = mixed & (etex > max_tex)
        if verbose:
            print(f'  level {level} faces {len(F)} mixed {mixed.sum()} to split {mark.sum()}', flush=True)
        if not mark.any():
            break
        V, F, CU = refine(V, F, CU, mark)
    h = face_hist_cu(CU, L); tot = h.sum(1)
    ij = np.clip((CU.mean(1) * n).astype(int), 0, n - 1)
    lab = np.where(tot >= 4, h.argmax(1), L[ij[:, 1], ij[:, 0]])
    lab, changed = despeckle(V, F, lab, SPECK_MM2 * mm * mm)
    V, nmov = smooth_borders(V, F, lab)
    area = face_areas(V, F)
    stats = {'route': 'texel', 'faces_in': int(len(F0)), 'faces_out': int(len(F)), 'verts_out': int(len(V)),
             'despeckled_faces': int(changed), 'border_vertices_smoothed': int(nmov),
             'area_share': {NAMES[k]: round(float(area[lab == k].sum() / area.sum()) * 100, 2) for k in range(4)},
             'units_per_mm': float(mm)}
    return V, F, CU, lab, stats


def face_hist_cu(CU, L):
    """per face label histogram from corner uvs (faces given directly as corner arrays)."""
    m = len(CU)
    U = CU.reshape(-1, 2); F = np.arange(m * 3).reshape(m, 3)
    return face_hist(U, F, L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('glb'); ap.add_argument('out'); ap.add_argument('--size-cm', type=float, default=40.0)
    ap.add_argument('--route', default='texel', choices=['texel', 'sdf'])
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    name = os.path.basename(a.glb)[:-4]
    print(name, flush=True)
    V, F, CU, lab, st = (clean_texel if a.route == 'texel' else clean)(a.glb, a.size_cm)
    np.savez_compressed(f'{a.out}/{name}.npz', V=V, F=F, CU=CU, lab=lab)
    json.dump(st, open(f'{a.out}/{name}.json', 'w'), indent=1)
    print(name, json.dumps(st), flush=True)


if __name__ == '__main__':
    main()
