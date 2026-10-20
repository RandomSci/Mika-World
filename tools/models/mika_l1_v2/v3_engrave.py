"""Mika L1 outfit v2 rework (Selwyn 2026-10-20): the engraved gold band (trim_sheet band 3) on the bodice's gold edges.
The bodice stays the baked Meshy part. Painting the band into the bake gave blotches (the trims are raised piping and
a texel's distance along a trim is noisy), so the trims get strip meshes like every other border; this finds them:
  - every gold trim of the clean high poly is a connected set of gold faces; for each of its vertices, d = distance to
    the trim's border, w = d over the local half width (0 at the edge, 1 on the centre line), s = distance along the
    trim from one of its ends (shortest path inside the trim, which runs along it);
  - the ridge of each trim (w > 0.75) becomes centre lines: a spanning tree cut into branches at ends and junctions,
    smoothed and resampled every 2 mm, with the trim's half width; v3_place.py lays an engraved strip along each.
Writes bake/bodice_trim_paths.json (Blender model axes of the Meshy part).
  python3 l1_v2/tools/v3_engrave.py"""
import json
import numpy as np, cv2
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components, dijkstra

V2 = '/home/selwyn/Downloads/Mika-Transformation-Lab/l1_v2'
N = 4096
h = np.load(V2 + '/clean_tx/MIKA_L1_bodice_core.npz'); HV, HF, HL = h['V'], h['F'], h['lab']
mm = (HV.max(0) - HV.min(0)).max() / 420.0                                # bodice is 42 cm
GOLD = 2
gf = np.nonzero(HL == GOLD)[0]
nv = len(HV)
in_gold = np.zeros(nv, bool); in_gold[HF[gf].ravel()] = True
in_other = np.zeros(nv, bool); in_other[HF[HL != GOLD].ravel()] = True
border = in_gold & in_other
# gold vertex graph (edges of gold faces), components
E = np.concatenate([HF[gf][:, [0, 1]], HF[gf][:, [1, 2]], HF[gf][:, [2, 0]]])
L = np.linalg.norm(HV[E[:, 0]] - HV[E[:, 1]], axis=1)
G = coo_matrix((np.r_[L, L], (np.r_[E[:, 0], E[:, 1]], np.r_[E[:, 1], E[:, 0]])), shape=(nv, nv)).tocsr()
ncomp, comp = connected_components(G, directed=False)
gv = np.nonzero(in_gold)[0]
S = np.zeros(nv); W = np.zeros(nv); HW = np.zeros(nv)
kept = 0
for c in np.unique(comp[gv]):
    vs = gv[comp[gv] == c]
    bv = vs[border[vs]]
    if len(vs) < 30 or len(bv) < 6: continue
    d, _ = cKDTree(HV[bv]).query(HV[vs])
    # local half width: the largest edge distance within 6 mm (the ridge height of this stretch of trim)
    t = cKDTree(HV[vs])
    hw = np.array([d[nb].max() for nb in t.query_ball_point(HV[vs], 6 * mm)])
    hw = np.maximum(hw, 0.5 * mm)
    sub = G[vs][:, vs]
    a = dijkstra(sub, indices=0, directed=False); a[np.isinf(a)] = 0
    end = int(np.argmax(a))                                              # one end of the trim (double sweep)
    s = dijkstra(sub, indices=end, directed=False); s[np.isinf(s)] = 0
    S[vs] = s; W[vs] = np.clip(d / hw, 0, 1); HW[vs] = np.median(hw)
    kept += 1
print('ENGRAVE trims', kept, 'gold verts', len(gv), 'median half width mm', round(float(np.median(HW[gv][HW[gv] > 0]) / mm), 2))

# centre lines: ridge vertices (w > 0.75), thinned to 1.5 mm, joined by a minimum spanning tree and cut into
# branches between ends and junctions; each branch smoothed and resampled every 2 mm. A branch whose ends meet
# (an armhole) is closed.
from scipy.sparse.csgraph import minimum_spanning_tree
paths = []
for c in np.unique(comp[gv]):
    vs = gv[(comp[gv] == c) & (HW[gv] > 0)]
    if len(vs) < 30: continue
    rid = vs[W[vs] > 0.75]
    if len(rid) < 10: continue
    q = HV[rid]
    key = np.round(q / (1.5 * mm)).astype(np.int64)
    _, first = np.unique(key, axis=0, return_index=True)
    q = q[first]; hwq = HW[rid][first]
    if len(q) < 6: continue
    tr = cKDTree(q)
    pairs = np.array(list(tr.query_pairs(4 * mm)))
    if len(pairs) == 0: continue
    dl = np.linalg.norm(q[pairs[:, 0]] - q[pairs[:, 1]], axis=1)
    g = coo_matrix((dl, (pairs[:, 0], pairs[:, 1])), shape=(len(q), len(q)))
    mst = minimum_spanning_tree(g).tocoo()
    adj = [[] for _ in range(len(q))]
    for i, j in zip(mst.row, mst.col): adj[i].append(j); adj[j].append(i)
    deg = np.array([len(x) for x in adj])
    nodes = set(np.nonzero(deg != 2)[0])
    seen = set()
    for n0 in nodes:
        for nb in adj[n0]:
            if (n0, nb) in seen: continue
            path = [n0, nb]; seen.add((n0, nb)); seen.add((nb, n0))
            while path[-1] not in nodes:
                cur = path[-1]; nxt = [x for x in adj[cur] if x != path[-2]]
                if not nxt: break
                path.append(nxt[0]); seen.add((cur, nxt[0])); seen.add((nxt[0], cur))
            pts = q[path]
            seg = np.linalg.norm(np.diff(pts, axis=0), axis=1); ln = seg.sum()
            if ln < 12 * mm: continue
            for _ in range(3):                                           # smooth, ends fixed
                pts[1:-1] = (pts[:-2] + 2 * pts[1:-1] + pts[2:]) / 4
            cl = np.linalg.norm(pts[0] - pts[-1]) < 6 * mm and ln > 60 * mm
            ac = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
            n = max(4, int(ac[-1] / (2 * mm)))
            rs = np.stack([np.interp(np.linspace(0, ac[-1], n), ac, pts[:, k]) for k in range(3)], 1)
            b = np.c_[rs[:, 0], -rs[:, 2], rs[:, 1]]                     # glTF to Blender model axes
            paths.append({'pts': b.round(6).tolist(), 'half_width': float(np.median(hwq[path])), 'closed': bool(cl)})
json.dump({'mm': mm, 'paths': paths}, open(V2 + '/bake/bodice_trim_paths.json', 'w'))
print('ENGRAVE paths', len(paths), 'closed', sum(p['closed'] for p in paths), 'total length cm',
      round(sum(np.linalg.norm(np.diff(np.array(p['pts']), axis=0), axis=1).sum() for p in paths) / mm / 10, 1))
