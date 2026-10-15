class_name StoneBuilder
extends RefCounted
## Hand-laid stonework for Milestone K ruins: every wall, pier, arch and stair is built from individual chamfered
## blocks with jittered size and angle, merged into ONE mesh per structure (one draw call). Vertex COLOR carries
## per-block data for shaders/nature/stylized_stone.gdshader: r = tone variation, g = moss bias (ruined tops,
## north faces), b = height within the structure (damp, darker bases). Ruins erode from the top: block courses
## go missing with height and noise, leaving the jagged silhouettes of the references. Colliders are a few
## simple boxes per structure, not per block.

var st := SurfaceTool.new()
var rng := RandomNumberGenerator.new()
var colliders: Array = []   # [Transform3D, Vector3 size]
var ground: Callable         # (x, z) -> y
var base_y := 0.0            # for the height channel
var top_y := 6.0
var blocks := 0


func _init(ground_fn: Callable, seed := 1) -> void:
	ground = ground_fn
	rng.seed = seed
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


# ------------------------------------------------------------------ primitive
## One chamfered block. `moss` biases moss (0..1).
func block(xf: Transform3D, size: Vector3, moss := 0.0, bevel := 0.06) -> void:
	size *= Vector3(rng.randf_range(0.97, 1.03), rng.randf_range(0.96, 1.04), rng.randf_range(0.97, 1.03))
	var h := size * 0.5
	var b := minf(bevel * rng.randf_range(0.5, 2.4), minf(h.x, minf(h.y, h.z)) * 0.45)
	var tone := rng.randf_range(-1.0, 1.0)
	var polys := []
	for a in 3:
		for s: float in [-1.0, 1.0]:
			var pts := []
			for c: Array in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var v := Vector3.ZERO
				v[a] = s * h[a]
				v[(a + 1) % 3] = c[0] * (h[(a + 1) % 3] - b)
				v[(a + 2) % 3] = c[1] * (h[(a + 2) % 3] - b)
				pts.append(v)
			polys.append(pts)
	for a in 3:
		var a2 := (a + 1) % 3
		var c2 := (a + 2) % 3
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var pts2 := []
				for sc: float in [-1.0, 1.0]:
					var p1 := Vector3.ZERO
					p1[a] = sa * h[a]; p1[a2] = sb * (h[a2] - b); p1[c2] = sc * (h[c2] - b)
					var p2 := Vector3.ZERO
					p2[a] = sa * (h[a] - b); p2[a2] = sb * h[a2]; p2[c2] = sc * (h[c2] - b)
					pts2.append(p1); pts2.append(p2)
				polys.append([pts2[0], pts2[1], pts2[3], pts2[2]])
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				polys.append([Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b)), Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b)), Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)])
	for poly in polys:
		_emit(poly, xf, tone, moss)
	blocks += 1


## A plain box (no chamfer, no jitter): fill that is meant to be seen only in the joints.
func _box(xf: Transform3D, size: Vector3, tone: float) -> void:
	var h := size * 0.5
	for a in 3:
		for s: float in [-1.0, 1.0]:
			var pts := []
			for c: Array in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var v := Vector3.ZERO
				v[a] = s * h[a]
				v[(a + 1) % 3] = c[0] * h[(a + 1) % 3]
				v[(a + 2) % 3] = c[1] * h[(a + 2) % 3]
				pts.append(v)
			_emit(pts, xf, tone, 0.0)


func _emit(pts: Array, xf: Transform3D, tone: float, moss: float) -> void:
	var cen := Vector3.ZERO
	for p in pts:
		cen += p
	cen /= pts.size()
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if n.dot(cen) < 0.0:
		pts = pts.duplicate()
		pts.reverse()
		n = -n
	var wn := (xf.basis * n).normalized()
	for i in range(1, pts.size() - 1):
		for v in [pts[0], pts[i + 1], pts[i]]:
			var wv: Vector3 = xf * v
			st.set_normal(wn)
			st.set_color(Color(tone * 0.5 + 0.5, moss, clampf((wv.y - base_y) / maxf(top_y - base_y, 0.1), 0.0, 1.0), 1.0))
			st.set_uv(Vector2(wv.x + wv.z, wv.y))
			st.add_vertex(wv)


func _jit(deg := 2.0) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(rng.randf_range(-deg, deg)), deg_to_rad(rng.randf_range(-deg * 2.0, deg * 2.0)), deg_to_rad(rng.randf_range(-deg, deg))))


func collider(xf: Transform3D, size: Vector3) -> void:
	colliders.append([xf, size])


# ------------------------------------------------------------------ structures
## A dry-stone wall from a to b (ground points; y ignored). ruin 0 = intact .. 1 = mostly fallen.
func wall(a: Vector3, b: Vector3, height: float, thick: float, ruin := 0.0, course := 0.5, y_from := 0.0, base_y_abs := INF) -> void:
	# y_from: the first course starts this high (masonry above an opening); base_y_abs: a level base instead of
	# following the ground (a house's floor)
	var dir := Vector3(b.x - a.x, 0, b.z - a.z)
	var L := dir.length()
	dir /= L
	var yaw := atan2(-dir.z, dir.x)
	var basis := Basis(Vector3.UP, yaw)
	var n_courses := int(ceil(height / course))
	var phase := rng.randf() * 10.0
	var max_h := 0.0
	for c in n_courses:
		var t := 0.0 if c % 2 == 0 else -rng.randf_range(0.3, 0.6)
		while t < L:
			var bl := rng.randf_range(0.7, 1.25)
			var t0 := maxf(t, 0.0)
			var t1 := minf(t + bl, L)
			t += bl + 0.02
			if t1 - t0 < 0.25:
				continue
			var mid := (t0 + t1) * 0.5
			# erosion profile: a ragged top that dips where the wall collapsed
			var limit := height * (1.0 - ruin * (0.5 + 0.5 * sin(mid * 0.9 + phase) * sin(mid * 0.37 + phase * 2.0)))
			limit -= ruin * rng.randf() * course * 1.5
			var y0 := c * course
			if y0 + course * 0.5 > limit:
				continue
			if y0 + course * 0.5 < y_from:
				continue
			if ruin > 0.0 and c > 0 and rng.randf() < ruin * 0.18 * float(c) / n_courses:
				continue
			var p := a + dir * mid
			var gy: float = ground.call(p.x, p.z) if base_y_abs == INF else base_y_abs + 0.18
			var ch := course * rng.randf_range(0.9, 1.04)
			var size := Vector3(t1 - t0 - 0.04, ch, thick * rng.randf_range(0.92, 1.05))
			var top := y0 + course >= limit - course or c == n_courses - 1
			var centre := Vector3(p.x, gy - 0.18 + y0 + ch * 0.5, p.z) + basis * Vector3(0, 0, rng.randf_range(-0.04, 0.04))
			block(Transform3D(basis * _jit(1.2), centre), size, 0.75 if top else rng.randf() * 0.25)
			max_h = maxf(max_h, y0 + ch)
	# the wall's core: a recessed fill behind the stones, so a joint is a deep dark joint and never a hole to the
	# sky (an intact wall is solid; a ruin keeps its gaps)
	if ruin < 0.15 and max_h > y_from + 0.2:
		var g0: float = minf(float(ground.call(a.x, a.z)), float(ground.call(b.x, b.z))) if base_y_abs == INF else base_y_abs + 0.18
		var y_lo := g0 - 0.18 + y_from + 0.02
		var y_hi := g0 - 0.18 + max_h - 0.06
		if base_y_abs == INF:
			y_hi = minf(float(ground.call(a.x, a.z)), float(ground.call(b.x, b.z))) - 0.18 + max_h - 0.06
		var mid3 := (a + b) * 0.5
		_box(Transform3D(basis, Vector3(mid3.x, (y_lo + y_hi) * 0.5, mid3.z)), Vector3(L - 0.06, maxf(y_hi - y_lo, 0.1), thick * 0.62), -1.0)
	# collider: the standing part of the wall (average height)
	if max_h > 0.6 and y_from < 0.01:
		var gm: float = ground.call((a.x + b.x) * 0.5, (a.z + b.z) * 0.5) if base_y_abs == INF else base_y_abs + 0.18
		var hh := maxf(max_h * (1.0 - ruin * 0.4), 0.8)
		collider(Transform3D(basis, Vector3((a.x + b.x) * 0.5, gm + hh * 0.5 - 0.2, (a.z + b.z) * 0.5)), Vector3(L, hh, thick))


## A square pier of stacked blocks, standing on the ground at p.
func pier(p: Vector3, w: float, h: float, yaw := 0.0, moss_top := 0.6) -> float:
	var gy: float = ground.call(p.x, p.z) - 0.2
	var y := 0.0
	var basis := Basis(Vector3.UP, yaw)
	var c := 0
	while y < h - 0.05:
		var ch := minf(rng.randf_range(0.45, 0.65), h - y)
		var ww := w * (1.08 if c == 0 else rng.randf_range(0.97, 1.02))
		block(Transform3D(basis * _jit(0.8), Vector3(p.x, gy + y + ch * 0.5, p.z)), Vector3(ww, ch, ww), moss_top if y + ch >= h - 0.05 else 0.08)
		y += ch + 0.015
		c += 1
	collider(Transform3D(basis, Vector3(p.x, gy + h * 0.5, p.z)), Vector3(w, h, w))
	return gy + y


## A gate/arch over the path: two piers and voussoirs. Opening faces local Z (yaw). pointed = Gothic.
## broken 0..1 drops voussoirs from one side (a collapsed arch).
func arch(center: Vector3, yaw: float, span: float, pier_h: float, pier_w: float, depth: float, pointed := false, broken := 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var right := basis * Vector3.RIGHT
	var lx := center - right * (span * 0.5 + pier_w * 0.5)
	var rx := center + right * (span * 0.5 + pier_w * 0.5)
	var ytop_l := pier(lx, pier_w, pier_h, yaw)
	var ytop_r := pier(rx, pier_w, pier_h, yaw)
	var spring := minf(ytop_l, ytop_r)
	var r := span * 0.5 + pier_w * 0.5          # voussoir centreline radius
	var thick := pier_w * 0.9
	var pieces := 11
	for i in pieces:
		var t := (i + 0.5) / pieces          # 0..1 from the left springing to the right
		if broken > 0.0 and t > 1.0 - broken and rng.randf() < 0.85:
			continue
		var pos: Vector3
		var ang: float
		if pointed:
			# two arcs, each centred on the opposite side (equilateral-ish Gothic arch)
			var R := r * 1.45
			var off := R - r
			var side := -1.0 if t < 0.5 else 1.0
			var u := t * 2.0 if t < 0.5 else (1.0 - t) * 2.0     # 0 at springing .. 1 at the apex
			var theta_max := acos(off / R)
			var theta := lerpf(0.0, theta_max, u)
			var cxv := -side * off
			var lx2 := cxv + side * R * cos(theta)
			var ly := R * sin(theta)
			pos = center + right * lx2 + Vector3(0, spring - center.y + ly, 0)
			ang = -side * (PI * 0.5 - theta)
		else:
			var a2 := PI * (1.0 - t)
			pos = center + right * (cos(a2) * r) + Vector3(0, spring - center.y + sin(a2) * r, 0)
			ang = a2 - PI * 0.5
		var seg := (PI * r / pieces) * (1.12 if pointed else 1.0) - 0.03
		var bb := basis * Basis(Vector3.FORWARD, -ang)
		block(Transform3D(bb * _jit(0.6), pos), Vector3(seg, thick, depth * rng.randf_range(0.96, 1.04)), 0.7)
	# a keystone a little proud of the ring
	if broken < 0.5:
		var apex := spring + (r * 1.45 * sin(acos((r * 0.45) / (r * 1.45))) if pointed else r)
		block(Transform3D(basis, center + Vector3(0, apex - center.y + thick * 0.25, 0)), Vector3(thick * 0.55, thick * 1.2, depth * 1.08), 0.8)


## A semicircular voussoir ring (no piers): centre = springing-line midpoint, opening along local Z (yaw).
func ring(center: Vector3, yaw: float, r: float, thick: float, depth: float, pieces := 13) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var right := basis * Vector3.RIGHT
	for i in pieces:
		var a2 := PI * (1.0 - (i + 0.5) / pieces)
		var rc := r + thick * 0.5
		var pos := center + right * (cos(a2) * rc) + Vector3(0, sin(a2) * rc, 0)
		var seg := PI * rc / pieces - 0.03
		block(Transform3D(basis * Basis(Vector3.FORWARD, -(a2 - PI * 0.5)) * _jit(0.5), pos), Vector3(seg, thick, depth * rng.randf_range(0.97, 1.03)), 0.55)


## A round column (n-sided drums). broken: height ratio left standing.
func column(p: Vector3, radius: float, h: float, sides := 10) -> void:
	var gy: float = ground.call(p.x, p.z) - 0.15
	# plinth
	block(Transform3D(_jit(0.5), Vector3(p.x, gy + 0.2, p.z)), Vector3(radius * 2.6, 0.4, radius * 2.6), 0.4)
	var y := 0.4
	while y < h - 0.05:
		var dh := minf(rng.randf_range(0.7, 1.1), h - y)
		_drum(Vector3(p.x, gy + y, p.z), radius * rng.randf_range(0.97, 1.0), dh - 0.02, sides, rng.randf() * TAU, 0.6 if y + dh >= h - 0.05 else 0.05)
		y += dh
	if h >= 3.0:
		# a flared capital and a square abacus
		_drum(Vector3(p.x, gy + y - 0.02, p.z), radius * 1.3, 0.26, sides, 0.0, 0.3)
		block(Transform3D(_jit(0.4), Vector3(p.x, gy + y + 0.34, p.z)), Vector3(radius * 3.0, 0.22, radius * 3.0), 0.7)
	collider(Transform3D(Basis.IDENTITY, Vector3(p.x, gy + h * 0.5, p.z)), Vector3(radius * 2.0, h, radius * 2.0))


func _drum(base: Vector3, r: float, h: float, sides: int, rot: float, moss: float) -> void:
	var tone := rng.randf_range(-1.0, 1.0)
	var tilt := _jit(0.7)
	var ring := []
	for i in sides + 1:
		var a := rot + TAU * i / sides
		ring.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for i in sides:
		var a0: Vector3 = ring[i]
		var a1: Vector3 = ring[i + 1]
		var quad := [a0, a1, a1 + Vector3(0, h, 0), a0 + Vector3(0, h, 0)]
		var xf := Transform3D(tilt, base)
		# side faces: emit with outward normal
		_emit_side(quad, xf, tone, moss * 0.3)
		_emit([Vector3(0, h, 0), a0 + Vector3(0, h, 0), a1 + Vector3(0, h, 0)], Transform3D(tilt, base), tone, moss)
	blocks += 1


func _emit_side(quad: Array, xf: Transform3D, tone: float, moss: float) -> void:
	var mid: Vector3 = (quad[0] + quad[1]) * 0.5
	var n := Vector3(mid.x, 0, mid.z).normalized()
	var wn := (xf.basis * n).normalized()
	for idx in [0, 2, 1, 0, 3, 2]:
		var wv: Vector3 = xf * (quad[idx] as Vector3)
		st.set_normal(wn)
		st.set_color(Color(tone * 0.5 + 0.5, moss, clampf((wv.y - base_y) / maxf(top_y - base_y, 0.1), 0.0, 1.0), 1.0))
		st.set_uv(Vector2(wv.x + wv.z, wv.y))
		st.add_vertex(wv)


## Worn steps from `a` to `b` (ground points), each tread set on the terrain (the terrain ramp is the walking
## surface; treads rise at most `lip` above it). Side kerbs optional.
func steps(a: Vector3, b: Vector3, width: float, run := 0.5, lip := 0.16, kerb := 0.0) -> void:
	var dir := Vector3(b.x - a.x, 0, b.z - a.z)
	var L := dir.length()
	dir /= L
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x) - PI * 0.5)
	var right := dir.cross(Vector3.UP).normalized()
	var k := 0.0
	while k < L:
		var p := a + dir * (k + run * 0.5)
		var gy_front: float = ground.call(p.x - dir.x * run * 0.5, p.z - dir.z * run * 0.5)
		var gy_back: float = ground.call(p.x + dir.x * run * 0.5, p.z + dir.z * run * 0.5)
		var top := maxf(gy_front, gy_back) + lip * 0.5
		var depth := 0.9
		# each tread: 2-3 slabs across its width (worn, slightly uneven)
		var parts := 2 if width < 3.0 else 3
		var pw := width / parts
		for j in parts:
			if rng.randf() < 0.04:
				continue   # a missing slab, grass fills it
			var off := -width * 0.5 + pw * (j + 0.5)
			var c := p + right * off
			block(Transform3D(basis * _jit(0.8), Vector3(c.x, top - depth * 0.5 + rng.randf_range(-0.02, 0.02), c.z)), Vector3(pw - 0.05, depth, run + 0.04), rng.randf() * 0.35, 0.05)
		if kerb > 0.0:
			for s: float in [-1.0, 1.0]:
				var kc := p + right * s * (width * 0.5 + 0.22)
				block(Transform3D(basis * _jit(0.6), Vector3(kc.x, top + kerb * 0.5 - 0.3, kc.z)), Vector3(0.42, kerb + 0.6, run + 0.05), 0.5)
		k += run


# ------------------------------------------------------------------ output
func finish(parent: Node3D, mat: Material, name := "Stone", shadow := true) -> MeshInstance3D:
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = name + "Body"
		for c in colliders:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = c[1]
			cs.shape = bs
			cs.transform = c[0]
			body.add_child(cs)
		parent.add_child(body)
	return mi
