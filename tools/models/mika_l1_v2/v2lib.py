"""Shared helpers for the Mika L1 v2 part cleanup (Selwyn 2026-10-20). Reads a Meshy GLB (one mesh, one base colour
texture snapped to the 4 colour palette), gives positions, uvs, triangles, the texture's palette labels, and per face
label histograms from a face id raster in UV space."""
import json, struct
import numpy as np, cv2

PAL_HEX = {'white': 'F4F4FA', 'navy': '1C2556', 'gold': 'D8B26A', 'sky': '6FA8E8'}
NAMES = list(PAL_HEX)
PAL = np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in PAL_HEX.values()], np.uint8)


def load_glb(path):
    b = open(path, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    J = json.loads(b[20:20 + n])
    B = b[20 + n + 8:]

    def acc(i):
        a = J['accessors'][i]; bv = J['bufferViews'][a['bufferView']]
        comp = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}[a['componentType']]
        k = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        st = bv.get('byteStride', 0) or k * np.dtype(comp).itemsize
        raw = np.frombuffer(B, np.uint8, count=a['count'] * st, offset=off).reshape(a['count'], st)
        return raw[:, :k * np.dtype(comp).itemsize].copy().view(comp).reshape(a['count'], k)
    p = J['meshes'][0]['primitives'][0]
    V = acc(p['attributes']['POSITION']).astype(np.float64)
    U = acc(p['attributes']['TEXCOORD_0']).astype(np.float64)
    F = acc(p['indices']).reshape(-1, 3).astype(np.int64)
    im = J['images'][0]; bv = J['bufferViews'][im['bufferView']]
    o = bv.get('byteOffset', 0)
    tex = cv2.imdecode(np.frombuffer(B[o:o + bv['byteLength']], np.uint8), cv2.IMREAD_COLOR)[..., ::-1]
    return V, U, F, tex


def labels_of(tex):
    d = ((tex[..., None, :].astype(np.int32) - PAL[None, None].astype(np.int32)) ** 2).sum(-1)
    return d.argmin(-1).astype(np.uint8)


def face_raster(U, F, n):
    """face id + 1 per texel (0 none), glTF uv (v down already in image rows)."""
    img = np.zeros((n, n, 3), np.uint8)
    P = (U * n * 16).round().astype(np.int32)             # 4 bit sub pixel precision
    for i, t in enumerate(F):
        k = i + 1
        cv2.fillConvexPoly(img, P[t], (k & 255, (k >> 8) & 255, (k >> 16) & 255), lineType=cv2.LINE_8, shift=4)
    return img[..., 0].astype(np.int64) | (img[..., 1].astype(np.int64) << 8) | (img[..., 2].astype(np.int64) << 16)


def face_hist(U, F, L):
    n = L.shape[0]
    fid = face_raster(U, F, n)
    m = fid > 0
    h = np.bincount((fid[m] - 1) * 4 + L[m], minlength=len(F) * 4).reshape(len(F), 4)
    c = (U[F].mean(1) * n).astype(int).clip(0, n - 1)        # faces too small for a texel: centroid sample
    empty = h.sum(1) == 0
    h[empty, L[c[empty, 1], c[empty, 0]]] = 1
    return h


def weld(V, tol=1e-5):
    key = np.round(V / tol).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return V[first], inv.ravel()


def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = map(np.asarray, (eye, target, up))
    f = target - eye; f = f / np.linalg.norm(f)
    r = np.cross(f, up); r = r / np.linalg.norm(r)
    u = np.cross(r, f)
    return np.stack([r, u, -f]), eye


def preview(V, F, face_rgb, eye, target, size=(800, 800), fov=None, ortho=1.0, light=(0.4, 0.7, 0.6), up=(0, 1, 0)):
    """CPU z-buffer preview: flat colour per face with a two tone shade (quick looks only)."""
    R, e = look_at(eye, target, up)
    P = (V - e) @ R.T
    W, H = size
    if fov:
        f = 0.5 * H / np.tan(np.radians(fov) / 2)
        xy = P[:, :2] / np.maximum(-P[:, 2:3], 1e-4) * f
    else:
        xy = P[:, :2] / ortho * (H / 2)
    xy = np.stack([xy[:, 0] + W / 2, H / 2 - xy[:, 1]], 1)
    z = -P[:, 2]
    n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    l = np.asarray(light, float); l = l / np.linalg.norm(l)
    shade = np.where(np.abs(n @ l) > 0.35, 1.0, 0.84)
    col = np.clip(face_rgb * shade[:, None], 0, 255)
    zb = np.full((H, W), np.inf); img = np.full((H, W, 3), 150.0)
    T = xy[F]; Z = z[F]
    lo = np.floor(T.min(1)).astype(int); hi = np.ceil(T.max(1)).astype(int)
    ok = (hi[:, 0] >= 0) & (lo[:, 0] < W) & (hi[:, 1] >= 0) & (lo[:, 1] < H) & (Z.min(1) > 0)
    for i in np.nonzero(ok)[0]:
        x0, y0 = max(lo[i, 0], 0), max(lo[i, 1], 0); x1, y1 = min(hi[i, 0], W - 1), min(hi[i, 1], H - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a, b, c = T[i]
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        w0 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        w1 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not m.any():
            continue
        zz = w0 * Z[i, 0] + w1 * Z[i, 1] + w2 * Z[i, 2]
        Y, X = ys[m].astype(int), xs[m].astype(int)
        nearer = zz[m] < zb[Y, X]
        zb[Y[nearer], X[nearer]] = zz[m][nearer]; img[Y[nearer], X[nearer]] = col[i]
    return img[..., ::-1].astype(np.uint8)
