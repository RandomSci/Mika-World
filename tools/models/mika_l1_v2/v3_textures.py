"""Mika L1 outfit v2 rework (Selwyn 2026-10-20, Mika_Trim_Kit_v1): the textures the procedural parts map onto.
  trim.png      trim_sheet at 4096 wide; the white gaps between the five bands are filled with each band's own edge
                rows, so mipmaps and linear filtering never pull white into a trim. Band rows are measured from the
                sheet itself (rows that are not near white), written to trim_bands.json as uv v ranges, plus a navy and
                a gold spot (flat colour for strip backs and rims).
  pattern.png   panel_pattern_tile as is (4096, seamless).
  decals.png    the six ornament decals cut from the white sheet into a 2 x 3 atlas (2048 x 3072), white kept where it
                is inside a decal; decals.json holds each decal's outline polygons (outer and holes, in atlas uv) for
                v3_place.py to build an opaque decal mesh shaped like the ornament (no alpha anywhere).
  ILMs          look prototype lightmaps for the three (gold specular, navy shading a little sooner), as v2_lookmaps.
  python3 l1_v2/tools/v3_textures.py"""
import os, json
import numpy as np, cv2

LAB = '/home/selwyn/Downloads/Mika-Transformation-Lab'
KIT = LAB + '/l1_v2/src/trim_kit'
OUT = LAB + '/l1_v2/tex3'
os.makedirs(OUT, exist_ok=True)
PAL = np.array([[0xF4, 0xF4, 0xFA], [0x1C, 0x25, 0x56], [0xD8, 0xB2, 0x6A], [0x6F, 0xA8, 0xE8], [0x9C, 0x7A, 0x3C]], np.int32)
# white, navy, gold, sky, dark gold line -> (ramp row, spec, spec size, threshold)
LUT = np.array([[s, th, z, (row + 0.5) / 16] for row, s, z, th in
                [(1, 0.0, 0.0, 0.5), (2, 0.0, 0.0, 0.42), (3, 1.0, 0.55, 0.5), (6, 0.0, 0.0, 0.5), (3, 0.7, 0.4, 0.45)]])


def labels(im):
    return ((im[..., None, :].astype(np.int32) - PAL[None, None]) ** 2).sum(-1).argmin(-1)


def ilm(im, name, max_side=2048):
    lab = labels(im[..., ::-1])
    f = max(1, int(np.ceil(max(lab.shape) / max_side)))
    out = (LUT[lab[::f, ::f]] * 255 + 0.5).astype(np.uint8)
    cv2.imwrite(f'{OUT}/{name}_ILM.png', cv2.cvtColor(out, cv2.COLOR_RGBA2BGRA))


# ---------------------------------------------------------------- trim sheet
t = cv2.imread(KIT + '/trim_sheet.webp')
H0, W0 = t.shape[:2]
white = (t.astype(int).sum(2) > 3 * 235).mean(1) > 0.98
rows = np.nonzero(~white)[0]
runs, s, p = [], rows[0], rows[0]
for r in rows[1:]:
    if r != p + 1: runs.append([s, p]); s = r
    p = r
runs.append([s, p])
# band 5 is two thin line runs and a dot row: merge runs closer than 60 px
bands = []
for a, b in runs:
    if bands and a - bands[-1][1] < 60: bands[-1][1] = b
    else: bands.append([a, b])
assert len(bands) == 5, bands
sc = 4096 / W0
tt = cv2.resize(t, (4096, int(round(H0 * sc / 4)) * 4), interpolation=cv2.INTER_AREA)
H = tt.shape[0]
B = [[int(np.ceil(a * sc)) + 1, int(np.floor((b + 1) * sc)) - 2] for a, b in bands]     # inside each band, 1 px in
fill = tt.copy()
edges = [0] + [((B[i][1] + B[i + 1][0]) // 2) for i in range(4)] + [H]
for i, (a, b) in enumerate(B):                                          # extend the band's edge rows into the gaps
    fill[edges[i]:a] = tt[a]
    fill[b + 1:edges[i + 1]] = tt[b]
cv2.imwrite(OUT + '/trim.png', fill)
names = ['filigree', 'stars', 'engraved', 'clouds', 'lines']
info = {'size': [4096, H], 'bands': {n: {'v0': 1 - (b + 1) / H, 'v1': 1 - a / H, 'rows': [a, b],
                                        'aspect': 4096 / (b - a + 1)} for n, (a, b) in zip(names, B)}}
lab = labels(fill[..., ::-1])
for k, nm in ((1, 'navy'), (2, 'gold')):                                 # a flat spot of each: 9 x 9 all one label
    m = (lab == k).astype(np.uint8)
    er = cv2.erode(m, np.ones((9, 9), np.uint8))
    ys, xs = np.nonzero(er)
    i = len(ys) // 2
    info[nm] = [(xs[i] + 0.5) / 4096, 1 - (ys[i] + 0.5) / H]
json.dump(info, open(OUT + '/trim_bands.json', 'w'), indent=1)
ilm(fill, 'trim')
print('TRIM', tt.shape, 'bands', B)

# ---------------------------------------------------------------- pattern
pt = cv2.imread(KIT + '/panel_pattern_tile.webp')
cv2.imwrite(OUT + '/pattern.png', pt)
ilm(pt, 'pattern')

# ---------------------------------------------------------------- decals
d = cv2.imread(KIT + '/ornament_decals.webp')
ink = (np.abs(d.astype(int) - [0xFA, 0xF4, 0xF4]).max(2) > 40).astype(np.uint8)
n, cc, st, _ = cv2.connectedComponentsWithStats(cv2.dilate(ink, np.ones((151, 151), np.uint8)))
comps = sorted([i for i in range(1, n) if st[i, 4] > 20000], key=lambda i: (round(st[i, 1] / 1365), st[i, 0]))
assert len(comps) == 6, len(comps)
DN = ['star8', 'moon', 'blossom', 'corner', 'crest', 'star4']                # reading order of the sheet
atlas = np.full((3072, 2048, 3), 255, np.uint8)
dec = {}
for k, i in enumerate(comps):
    x, y, w, h = st[i, :4]
    cell = (k // 2, k % 2)
    crop = d[y:y + h, x:x + w]; cm = ink[y:y + h, x:x + w]
    s_ = min(960 / w, 960 / h)
    cw, ch = int(w * s_), int(h * s_)
    ox, oy = cell[1] * 1024 + (1024 - cw) // 2, cell[0] * 1024 + (1024 - ch) // 2
    atlas[oy:oy + ch, ox:ox + cw] = cv2.resize(crop, (cw, ch), interpolation=cv2.INTER_AREA)
    mk = cv2.resize(cm * 255, (cw, ch), interpolation=cv2.INTER_LINEAR)
    mk = cv2.morphologyEx((mk > 100).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    cs, hier = cv2.findContours(mk, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    polys = []
    for ci, c in enumerate(cs):
        if cv2.contourArea(c) < 60: continue
        a_ = cv2.approxPolyDP(c, 1.2, True)[:, 0, :].astype(float)
        uv = np.c_[(a_[:, 0] + ox) / 2048, 1 - (a_[:, 1] + oy) / 3072]
        polys.append({'hole': bool(hier[0, ci, 3] >= 0), 'uv': uv.round(6).tolist()})
    dec[DN[k]] = {'size_px': [cw, ch], 'polys': polys,
                  'centre_uv': [(ox + cw / 2) / 2048, 1 - (oy + ch / 2) / 3072], 'wh_uv': [cw / 2048, ch / 3072]}
    print('DECAL', DN[k], 'outlines', len(polys), 'points', sum(len(p['uv']) for p in polys))
cv2.imwrite(OUT + '/decals.png', atlas)
json.dump(dec, open(OUT + '/decals.json', 'w'))
ilm(atlas, 'decals')
