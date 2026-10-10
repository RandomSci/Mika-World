"""Blender (4.2) generator for the Arcane Sanctuary hero architecture.

Run:  blender --background --factory-startup --python tools/blender/build_sanctuary_architecture.py -- <out.glb>

Everything is modelled as discrete, bevelled stone pieces (blocks, drums, voussoirs, slabs)
so silhouettes and seams are real geometry. Surfaces are textured in Godot with triplanar
photogrammetry PBR (Poly Haven rock_surface / monastery_stone_floor + ambientCG moss),
so UVs are only needed for the rune floor.

Vertex colour channels (COLOR_0) per piece, read by stone_triplanar.gdshader:
  R = per-block tint variation (0..1)
  G = moss amount bias (0..1)
  B = edge wear / grime bias (0..1)

Blender is Z-up; the glTF exporter converts to Y-up so Blender +Y (north) == Godot -Z.
"""
import bpy, bmesh, math, random, sys
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/sanctuary_architecture.glb"
rng = random.Random(7071)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

MATS = {}
def mat(name, color):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.diffuse_color = color
        MATS[name] = m
    return MATS[name]

mat("stone_cut", (0.55, 0.53, 0.5, 1))
mat("stone_floor", (0.5, 0.5, 0.48, 1))
mat("rune_floor", (0.45, 0.45, 0.47, 1))
mat("gold_inlay", (0.8, 0.6, 0.2, 1))


class Builder:
    """Accumulates many pieces into one bmesh per (object, material) for low draw calls."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.mat_index = {}
        self.mats = []

    def _mi(self, material):
        if material not in self.mat_index:
            self.mat_index[material] = len(self.mats)
            self.mats.append(material)
        return self.mat_index[material]

    def add_bm(self, piece: bmesh.types.BMesh, material="stone_cut", color=None, matrix=None):
        if color is None:
            color = (rng.random(), rng.uniform(0.25, 1.0), rng.random(), 1.0)
        if matrix is not None:
            piece.transform(matrix)
        mi = self._mi(material)
        vmap = {}
        for v in piece.verts:
            vmap[v] = self.bm.verts.new(v.co)
        for f in piece.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = mi
            nf.smooth = f.smooth
            for loop in nf.loops:
                loop[self.col] = color
        piece.free()

    def finish(self, smooth_angle=0.65):
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(MATS[m])
        ob = bpy.data.objects.new(self.name, me)
        scene.collection.objects.link(ob)
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        try:
            bpy.ops.object.shade_smooth_by_angle(angle=smooth_angle)
        except Exception:
            bpy.ops.object.shade_smooth()
        ob.select_set(False)
        return ob


def bevelled(bm, width=0.03, segments=2):
    bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=width, segments=segments,
                    profile=0.6, affect="EDGES", clamp_overlap=True)
    return bm


def chip(bm, amount=0.012, seed=None):
    """Weather the piece: jitter vertices so edges aren't machine-perfect."""
    r = random.Random(seed if seed is not None else rng.random())
    for v in bm.verts:
        v.co += Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-1, 1))) * amount
    return bm


def box(sx, sy, sz, bevel=0.035, wear=0.012):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    # a few cuts so jitter can bend long faces a little
    bevelled(bm, bevel, 2)
    chip(bm, wear)
    for f in bm.faces:
        f.smooth = True
    return bm


def lathe(profile, segments=48, radial=None, smooth=True, cap_bottom=True, cap_top=True):
    """Surface of revolution around Z. profile = [(r, z), ...] bottom->top.
    radial(theta, r, z) -> r' lets us carve flutes / octagons."""
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        ring = []
        for i in range(segments):
            t = 2 * math.pi * i / segments
            rr = radial(t, r, z) if radial else r
            ring.append(bm.verts.new((rr * math.cos(t), rr * math.sin(t), z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.smooth = smooth
    if cap_bottom and profile[0][0] > 1e-4:
        f = bm.faces.new(list(reversed(rings[0])))
        f.smooth = False
    if cap_top and profile[-1][0] > 1e-4:
        f = bm.faces.new(rings[-1])
        f.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def annular_sector(r0, r1, a0, a1, z0, z1, steps=6, bevel=0.025):
    """A curved slab between radii r0..r1, angles a0..a1, heights z0..z1."""
    bm = bmesh.new()
    inner_b, outer_b, inner_t, outer_t = [], [], [], []
    for i in range(steps + 1):
        t = a0 + (a1 - a0) * i / steps
        c, s = math.cos(t), math.sin(t)
        inner_b.append(bm.verts.new((r0 * c, r0 * s, z0)))
        outer_b.append(bm.verts.new((r1 * c, r1 * s, z0)))
        inner_t.append(bm.verts.new((r0 * c, r0 * s, z1)))
        outer_t.append(bm.verts.new((r1 * c, r1 * s, z1)))
    for i in range(steps):
        bm.faces.new((inner_t[i], outer_t[i], outer_t[i + 1], inner_t[i + 1]))  # top
        bm.faces.new((inner_b[i + 1], outer_b[i + 1], outer_b[i], inner_b[i]))  # bottom
        bm.faces.new((outer_b[i], outer_b[i + 1], outer_t[i + 1], outer_t[i]))  # outer
        bm.faces.new((inner_b[i + 1], inner_b[i], inner_t[i], inner_t[i + 1]))  # inner
    bm.faces.new((inner_b[0], outer_b[0], outer_t[0], inner_t[0]))
    bm.faces.new((outer_b[-1], inner_b[-1], inner_t[-1], outer_t[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bevelled(bm, bevel, 2)
    chip(bm, 0.006)
    for f in bm.faces:
        f.smooth = True
    return bm


def wedge(corners, bevel=0.03):
    """Hexahedron from 8 corners: bottom quad (0..3) then top quad (4..7)."""
    bm = bmesh.new()
    v = [bm.verts.new(c) for c in corners]
    for idx in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([v[i] for i in idx])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bevelled(bm, bevel, 2)
    chip(bm, 0.01)
    for f in bm.faces:
        f.smooth = True
    return bm


def M(loc=(0, 0, 0), rot_z=0.0, rot=(0, 0, 0)):
    m = Matrix.Translation(Vector(loc)) @ Matrix.Rotation(rot_z, 4, "Z")
    if rot != (0, 0, 0):
        m = m @ Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(rot[1], 4, "Y")
    return m


# ---------------------------------------------------------------- Ritual dais
DAIS_TIERS = [  # (r_inner, r_outer, top_z, segments)
    (6.8, 7.7, 0.2, 28),
    (5.9, 6.8, 0.4, 24),
    (4.3, 5.9, 0.6, 20),
]
RUNE_R = 4.3
DAIS_TOP = 0.6


def build_dais():
    b = Builder("RitualDais")
    for (r0, r1, top, n) in DAIS_TIERS:
        off = rng.uniform(0, 1)
        for i in range(n):
            a0 = 2 * math.pi * (i + off) / n + 0.004
            a1 = 2 * math.pi * (i + 1 + off) / n - 0.004
            z1 = top + rng.uniform(-0.012, 0.008)
            piece = annular_sector(r0 + 0.01, r1 - 0.01, a0, a1, -0.35, z1, steps=5)
            # slight settle/tilt of old slabs
            tilt = Matrix.Rotation(rng.uniform(-0.012, 0.012), 4, "X") @ Matrix.Rotation(rng.uniform(-0.012, 0.012), 4, "Y")
            b.add_bm(piece, "stone_floor", matrix=tilt)
    # gold inlay ring between the rune floor and slab ring
    # closed rectangular profile, NO caps (caps would fill the whole circle and hide the rune floor)
    ring = lathe([(RUNE_R + 0.02, DAIS_TOP - 0.01), (RUNE_R + 0.09, DAIS_TOP - 0.01),
                  (RUNE_R + 0.09, DAIS_TOP + 0.012), (RUNE_R + 0.02, DAIS_TOP + 0.012),
                  (RUNE_R + 0.02, DAIS_TOP - 0.01)], 128, cap_bottom=False, cap_top=False)
    b.add_bm(ring, "gold_inlay", color=(0.5, 0.0, 0.3, 1))
    ob = b.finish()

    # rune floor disc: single surface with planar UV covering the disc (0..1)
    rb = bmesh.new()
    uv = rb.loops.layers.uv.new("UVMap")
    col = rb.loops.layers.color.new("Col")
    rings_n, segs = 24, 96
    center = rb.verts.new((0, 0, DAIS_TOP))
    prev = None
    rows = []
    for ri in range(1, rings_n + 1):
        r = RUNE_R * ri / rings_n
        row = [rb.verts.new((r * math.cos(2 * math.pi * s / segs), r * math.sin(2 * math.pi * s / segs), DAIS_TOP + rng.uniform(-0.002, 0.002) * (ri < rings_n)))
               for s in range(segs)]
        rows.append(row)
    for s in range(segs):
        f = rb.faces.new((center, rows[0][s], rows[0][(s + 1) % segs]))
    for a, c in zip(rows, rows[1:]):
        for s in range(segs):
            rb.faces.new((a[s], c[s], c[(s + 1) % segs], a[(s + 1) % segs]))
    # skirt down so the disc edge isn't paper thin
    low = [rb.verts.new((v.co.x, v.co.y, -0.35)) for v in rows[-1]]
    for s in range(segs):
        rb.faces.new((rows[-1][s], low[s], low[(s + 1) % segs], rows[-1][(s + 1) % segs]))
    bmesh.ops.recalc_face_normals(rb, faces=rb.faces)
    for f in rb.faces:
        f.smooth = True
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.x / (2 * RUNE_R) + 0.5, co.y / (2 * RUNE_R) + 0.5)
            loop[col] = (0.5, 0.2, 0.4, 1)
    me = bpy.data.meshes.new("RuneFloor")
    rb.to_mesh(me)
    rb.free()
    me.materials.append(MATS["rune_floor"])
    o = bpy.data.objects.new("RuneFloor", me)
    scene.collection.objects.link(o)

    # entrance steps on the south side (Blender -Y)
    st = Builder("DaisSteps")
    for k in range(4):
        y = -(7.7 + 0.45 * (3 - k)) + 0.2
        z = 0.05 * k
        piece = box(2.6 - 0.1 * k, 0.5, 0.12 + 0.05 * k * 0 + 0.1, 0.03, 0.008)
        st.add_bm(piece, "stone_floor", matrix=M((rng.uniform(-0.03, 0.03), y, z)))
    st.finish()


# ---------------------------------------------------------------- Columns
FLUTES = 16


def fluted(t, r, z):
    # concave flutes separated by thin fillets; depth fades near drum ends
    g = 0.5 + 0.5 * math.cos(FLUTES * t)
    return r - 0.035 * (g ** 3)


def column(b: Builder, x, y, height=5.6, broken_at=None, lean=0.0, rot=0.0):
    base_m = M((x, y, DAIS_TOP if math.hypot(x, y) < 7.7 else 0.0), rot)
    # plinth
    b.add_bm(box(1.25, 1.25, 0.32, 0.04), "stone_cut", matrix=base_m @ M((0, 0, 0.16)))
    # attic base mouldings (torus - scotia - torus)
    prof = [(0.6, 0.32), (0.62, 0.36), (0.62, 0.42), (0.58, 0.47), (0.52, 0.5), (0.5, 0.56), (0.55, 0.6), (0.56, 0.64), (0.5, 0.68)]
    b.add_bm(lathe(prof, 56), "stone_cut", matrix=base_m)
    # shaft in drums with entasis
    shaft_top = height - 0.7
    z = 0.68
    drum_h = 0.95
    top_limit = broken_at if broken_at else shaft_top
    di = 0
    while z < top_limit - 0.05:
        z1 = min(z + drum_h + rng.uniform(-0.1, 0.1), top_limit)
        f0 = (z - 0.68) / (shaft_top - 0.68)
        f1 = (z1 - 0.68) / (shaft_top - 0.68)
        r0 = 0.46 - 0.06 * f0 ** 1.4
        r1 = 0.46 - 0.06 * f1 ** 1.4
        last = broken_at and z1 >= top_limit - 1e-4
        prof = [(r0 - 0.012, z + 0.004), (r0, z + 0.02)]
        steps = 6
        for k in range(1, steps):
            fz = z + (z1 - z) * k / steps
            ff = (fz - 0.68) / (shaft_top - 0.68)
            prof.append((0.46 - 0.06 * ff ** 1.4, fz))
        prof += [(r1, z1 - 0.02), (r1 - 0.012, z1 - 0.004)]
        piece = lathe(prof, 64, radial=fluted)
        if last:
            # jagged broken top: displace the top cap verts
            for v in piece.verts:
                if v.co.z > z1 - 0.03:
                    v.co.z += rng.uniform(-0.28, 0.12)
                    v.co.x *= rng.uniform(0.9, 1.0)
                    v.co.y *= rng.uniform(0.9, 1.0)
        chip(piece, 0.004)
        drum_rot = M((0, 0, 0), rng.uniform(-0.02, 0.02))
        b.add_bm(piece, "stone_cut", matrix=base_m @ Matrix.Rotation(lean * (di + 1), 4, "X") @ drum_rot)
        z = z1
        di += 1
    if broken_at:
        return
    # capital: necking, echinus, abacus
    prof = [(0.41, shaft_top), (0.44, shaft_top + 0.05), (0.43, shaft_top + 0.1), (0.48, shaft_top + 0.16),
            (0.6, shaft_top + 0.3), (0.66, shaft_top + 0.36), (0.66, shaft_top + 0.4)]
    b.add_bm(lathe(prof, 56), "stone_cut", matrix=base_m)
    b.add_bm(box(1.45, 1.45, 0.3, 0.04), "stone_cut", matrix=base_m @ M((0, 0, shaft_top + 0.55)))


def build_columns():
    b = Builder("Colonnade")
    R = 9.2
    n = 8
    broken = {2: 2.4, 5: 3.4, 6: 1.3}
    for i in range(n):
        a = 2 * math.pi * i / n + math.pi / 8  # keep N/S axis open for the arch view and entry
        x, y = R * math.cos(a), R * math.sin(a)
        column(b, x, y, 5.6, broken.get(i), lean=0.0, rot=a)
    # lintels on two intact pairs to create a strong silhouette
    def lintel(i, j):
        a, c = 2 * math.pi * i / n + math.pi / 8, 2 * math.pi * j / n + math.pi / 8
        p0 = Vector((R * math.cos(a), R * math.sin(a)))
        p1 = Vector((R * math.cos(c), R * math.sin(c)))
        mid = (p0 + p1) / 2
        L = (p1 - p0).length + 1.3
        ang = math.atan2(p1.y - p0.y, p1.x - p0.x)
        b.add_bm(box(L, 1.0, 0.75, 0.05, 0.015), "stone_cut", matrix=M((mid.x, mid.y, 5.6 + 0.07 + 0.375), ang))
        # cornice
        b.add_bm(box(L + 0.2, 1.2, 0.18, 0.03), "stone_cut", matrix=M((mid.x, mid.y, 5.6 + 0.82 + 0.09), ang))
    lintel(0, 1)
    lintel(3, 4)
    b.finish()

    # fallen drums and a broken capital lying on the ground near broken columns
    f = Builder("FallenStones")
    for (i, h) in broken.items():
        a = 2 * math.pi * i / n + math.pi / 8
        x, y = (R + 1.8) * math.cos(a), (R + 1.8) * math.sin(a)
        for k in range(2 if h > 2 else 3):
            piece = lathe([(0.0, 0), (0.44, 0.0), (0.45, 0.85), (0.0, 0.85)], 48, radial=fluted, cap_bottom=False, cap_top=False)
            bmesh.ops.triangulate(piece, faces=piece.faces)
            chip(piece, 0.01)
            m = M((x + rng.uniform(-1.2, 1.2) + k * 0.6 * math.cos(a), y + rng.uniform(-1.2, 1.2) + k * 0.6 * math.sin(a), 0.42),
                  rng.uniform(0, 6.28), (math.pi / 2, 0, 0))
            f.add_bm(piece, "stone_cut", matrix=m @ M((0, 0, -0.42)))
    f.finish()


# ---------------------------------------------------------------- Arch gateway (north)
def build_arch(cx=0.0, cy=17.0):
    b = Builder("ArchGateway")
    span_half = 2.3
    pier_w, depth = 1.5, 1.4
    pier_h = 4.2
    for side in (-1, 1):
        px = cx + side * (span_half + pier_w / 2)
        z = 0
        course = 0
        # plinth
        b.add_bm(box(pier_w + 0.35, depth + 0.35, 0.4, 0.04), "stone_cut", matrix=M((px, cy, 0.2)))
        z = 0.4
        while z < pier_h - 0.05:
            h = min(rng.uniform(0.48, 0.6), pier_h - z)
            if course % 2 == 0:
                b.add_bm(box(pier_w, depth, h - 0.012, 0.035), "stone_cut", matrix=M((px + rng.uniform(-0.015, 0.015), cy, z + h / 2)))
            else:
                for k in (-1, 1):
                    b.add_bm(box(pier_w, depth / 2 - 0.006, h - 0.012, 0.035), "stone_cut",
                             matrix=M((px + rng.uniform(-0.015, 0.015), cy + k * depth / 4, z + h / 2)))
            z += h
            course += 1
        # impost moulding
        b.add_bm(box(pier_w + 0.3, depth + 0.3, 0.22, 0.05), "stone_cut", matrix=M((px, cy, pier_h + 0.11)))
    # voussoirs
    ri, ro = span_half, span_half + 1.05
    spring = pier_h + 0.22
    n = 13
    for i in range(n):
        a0 = math.pi * i / n + 0.003
        a1 = math.pi * (i + 1) / n - 0.003
        key = i == n // 2
        ext = 0.25 if key else 0.0
        corners = []
        for yy in (-depth / 2 - (0.08 if key else 0), depth / 2 + (0.08 if key else 0)):
            pass
        y0, y1 = cy - depth / 2 - (0.08 if key else 0), cy + depth / 2 + (0.08 if key else 0)
        def P(r, a, y):
            return (cx + r * math.cos(a), y, spring + r * math.sin(a))
        corners = [P(ri, a0, y0), P(ro + ext, a0, y0), P(ro + ext, a1, y0), P(ri, a1, y0),
                   P(ri, a0, y1), P(ro + ext, a0, y1), P(ro + ext, a1, y1), P(ri, a1, y1)]
        # wedge() expects bottom quad then top quad; reorder into consistent hexahedron
        c = corners
        b.add_bm(wedge([c[0], c[1], c[5], c[4], c[3], c[2], c[6], c[7]], 0.03), "stone_cut",
                 color=(rng.random(), 0.9 if not key else 0.4, rng.random(), 1))
    # spandrel masonry above the arch to give a solid gate silhouette
    top = spring + ro + 0.15
    for side in (-1, 1):
        for row in range(4):
            z0 = spring + row * 0.55
            x_in = math.sqrt(max(0.0, (ro + 0.02) ** 2 - (z0 + 0.275 - spring) ** 2))
            x_out = span_half + pier_w
            if x_out - x_in < 0.25:
                continue
            w = x_out - x_in
            b.add_bm(box(w, depth - 0.05, 0.53, 0.035), "stone_cut", matrix=M((cx + side * (x_in + w / 2), cy, z0 + 0.275)))
    # crown course (partially ruined: missing blocks)
    x = -(span_half + pier_w)
    while x < span_half + pier_w - 0.2:
        w = rng.uniform(0.7, 1.2)
        if rng.random() > 0.22:
            b.add_bm(box(min(w, span_half + pier_w - x) - 0.02, depth + 0.1, 0.45, 0.04), "stone_cut",
                     matrix=M((cx + x + w / 2, cy, spring + ro + 0.15 + 0.225)))
        x += w
    b.finish()


# ---------------------------------------------------------------- Ruined walls
def wall_run(b: Builder, p0, p1, courses=5, height_profile=None, depth=0.75):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length
    ang = math.atan2(d.y, d.x)
    z = 0.0
    for c in range(courses):
        h = rng.uniform(0.42, 0.52)
        t = rng.uniform(0, 0.5) if c % 2 else 0.0
        s = -t
        while s < L:
            w = rng.uniform(0.65, 1.25)
            s0, s1 = max(0.0, s), min(L, s + w)
            if s1 - s0 > 0.18:
                mid = (s0 + s1) / 2
                hp = height_profile(mid / L) if height_profile else 1.0
                if c < courses * hp:
                    p = p0 + d.normalized() * mid
                    b.add_bm(box(s1 - s0 - 0.025, depth + rng.uniform(-0.05, 0.05), h - 0.02, 0.04, 0.014), "stone_cut",
                             color=(rng.random(), min(1.0, 0.4 + c * 0.15), rng.random(), 1),
                             matrix=M((p.x, p.y, z + h / 2), ang + rng.uniform(-0.02, 0.02)))
            s += w
        z += h


def build_walls():
    b = Builder("RuinWalls")
    # curved west ruin
    pts = [(-14.5 * math.cos(a), 14.5 * math.sin(a)) for a in [math.radians(x) for x in range(-35, 70, 15)]]
    for i, (pa, pb) in enumerate(zip(pts, pts[1:])):
        prof = lambda t, i=i: 0.35 + 0.65 * abs(math.sin((i + t) * 0.9))
        wall_run(b, pa, pb, 7, prof)
    # east ruin with a window gap
    pts = [(14.5 * math.cos(a), 14.5 * math.sin(a)) for a in [math.radians(x) for x in range(-10, 75, 17)]]
    for i, (pa, pb) in enumerate(zip(pts, pts[1:])):
        prof = lambda t, i=i: 0.25 + 0.75 * (1 - abs(math.sin((i * 1.7 + t))))
        wall_run(b, pa, pb, 8, prof)
    # low wall flanking the arch
    wall_run(b, (-8.8, 17.4), (-3.9, 17.2), 4, lambda t: 0.4 + 0.6 * t)
    wall_run(b, (3.9, 17.2), (8.8, 17.4), 4, lambda t: 1.0 - 0.7 * t)
    b.finish()


# ---------------------------------------------------------------- Altar / spell pedestal
def octagon(t, r, z):
    seg = math.pi / 4
    k = math.cos(seg / 2) / math.cos(((t + seg / 2) % seg) - seg / 2)
    return r * k


def build_altar(cx=0.0, cy=2.6):
    b = Builder("SpellAltar")
    z0 = DAIS_TOP
    prof = [(0.95, z0), (0.95, z0 + 0.18), (0.82, z0 + 0.2), (0.82, z0 + 0.36), (0.6, z0 + 0.38), (0.58, z0 + 0.44)]
    b.add_bm(lathe(prof, 8, radial=None, smooth=False), "stone_cut", matrix=M((cx, cy, 0), math.pi / 8))
    # shaft with carved bands
    s0 = z0 + 0.44
    prof = [(0.44, s0), (0.42, s0 + 0.1), (0.4, s0 + 0.12), (0.4, s0 + 0.2), (0.43, s0 + 0.22), (0.43, s0 + 0.26),
            (0.37, s0 + 0.28), (0.36, s0 + 0.62), (0.4, s0 + 0.64), (0.4, s0 + 0.68), (0.36, s0 + 0.7), (0.36, s0 + 0.74)]
    b.add_bm(lathe(prof, 8, smooth=False), "stone_cut", matrix=M((cx, cy, 0), math.pi / 8))
    # gold bands
    for zz in (s0 + 0.16, s0 + 0.66):
        b.add_bm(lathe([(0.405, zz - 0.02), (0.418, zz - 0.02), (0.418, zz + 0.02), (0.405, zz + 0.02), (0.405, zz - 0.02)], 8,
                       smooth=False, cap_bottom=False, cap_top=False),
                 "gold_inlay", color=(0.5, 0, 0.2, 1), matrix=M((cx, cy, 0), math.pi / 8))
    # table top with chamfer
    t0 = s0 + 0.74
    prof = [(0.42, t0), (0.62, t0 + 0.08), (0.66, t0 + 0.1), (0.66, t0 + 0.17), (0.6, t0 + 0.19)]
    b.add_bm(lathe(prof, 8, smooth=False), "stone_cut", matrix=M((cx, cy, 0), math.pi / 8))
    # four flanking crystal sockets / small obelisks
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        ox, oy = cx + 1.35 * math.cos(a), cy + 1.35 * math.sin(a)
        prof = [(0.22, z0), (0.22, z0 + 0.12), (0.15, z0 + 0.14), (0.13, z0 + 0.9), (0.0, z0 + 1.15)]
        b.add_bm(lathe(prof, 4, smooth=False), "stone_cut", matrix=M((ox, oy, 0), a + math.pi / 4))
    b.finish()


# ---------------------------------------------------------------- Braziers
def build_braziers():
    b = Builder("Braziers")
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        x, y = 6.35 * math.cos(a), 6.35 * math.sin(a)
        z = 0.4
        prof = [(0.32, z), (0.32, z + 0.08), (0.2, z + 0.12), (0.15, z + 0.5), (0.18, z + 0.6), (0.38, z + 0.78),
                (0.42, z + 0.86), (0.36, z + 0.86), (0.3, z + 0.76), (0.0, z + 0.74)]
        b.add_bm(lathe(prof, 32), "stone_cut", matrix=M((x, y, 0)))
    b.finish()


build_dais()
build_columns()
build_arch()
build_walls()
build_altar()
build_braziers()

for ob in scene.collection.objects:
    ob.select_set(True)
kw = dict(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, use_selection=False,
          export_normals=True, export_tangents=False, export_materials="EXPORT")
try:
    bpy.ops.export_scene.gltf(**kw, export_vertex_color="ACTIVE")
except TypeError:
    bpy.ops.export_scene.gltf(**kw, export_colors=True)
tri = 0
for ob in scene.collection.objects:
    ob.data.calc_loop_triangles()
    tri += len(ob.data.loop_triangles)
    print("OBJ", ob.name, "tris", len(ob.data.loop_triangles))
print("TOTAL_TRIS", tri, "->", OUT)
