class_name WoodsLandmarks
extends RefCounted
## Built landmarks of the Whispering Woods' main route (Milestone K), all original stonework from StoneBuilder:
##   * the ENTRY ARCH where the trail leaves the Sanctuary's lands (a mossy round arch + a low boundary wall),
##   * the CROSSROADS waymarker (a carved stele and a stone lantern that glows after dark),
##   * the FORKED STAIRWAY up the escarpment: a lower flight, a landing, the main flight under three pointed
##     arches (one fallen in), and a narrow left fork climbing to the hidden alcove,
##   * the FORGOTTEN RUINS on the plateau: a round gate arch, collapsed enclosure walls, a colonnade of broken
##     columns, a toppled drum, the INSCRIPTION stone (runes glow faintly at night) and a tree grown into a wall,
##   * the VIEWPOINT terrace on the escarpment edge, looking over the falls,
##   * the WATERFALL: the river leaps the escarpment into a plunge pool (three cascades, mist, churning foam),
##   * the MONSTER DEN in the east: a mossy rock outcrop with a dark cave mouth facing the trail, framed by
##     boulders, fronds hanging over the lip,
##   * the HIDDEN POND: lily pads, lotus flowers (they glow softly after dark), reeds along the shore,
##   * the OLD BRIDGE just below the pool: three stone arches and a humped deck (walkable), the west arch
##     spanning a dry bank path that runs under it to the pool.

var a: WhisperingWoods
var stone: ShaderMaterial
var stats := {}
var walls: Array = []            # [a, b, height, thick] of every wall built (ivy, vines hang off them)
var arches: Array = []           # [centre at the springing line, span, crown y, yaw]
var ruin_tree := Transform3D.IDENTITY


## Wall / arch wrappers that remember what was built (the features pass grows ivy and vines on them).
func _wall(sb: StoneBuilder, p0: Vector3, p1: Vector3, h: float, t: float, ruin := 0.0, course := 0.5) -> void:
	walls.append([p0, p1, h, t])
	sb.wall(p0, p1, h, t, ruin, course)


func _arch(sb: StoneBuilder, c: Vector3, yaw: float, span: float, pier_h: float, pier_w: float, depth: float, pointed := false, broken := 0.0) -> void:
	arches.append([c + Vector3(0, pier_h, 0), span, c.y + pier_h + span * 0.5 * (1.3 if pointed else 1.0), yaw])
	sb.arch(c, yaw, span, pier_h, pier_w, depth, pointed, broken)


func _init(area: WhisperingWoods) -> void:
	a = area


func _mat() -> ShaderMaterial:
	if stone == null and RealKit.enabled():
		stone = RealKit.stone_mat("mossy_stone_wall")
	if stone == null:
		stone = Kit.shader_mat("res://shaders/nature/stylized_stone.gdshader", {"grain_tex": load(Kit.tex_set("rock_wall_10", "1k")[0]),
			"noise_tex": Kit.noise()})
	return stone


func _g(x: float, z: float) -> float:
	return a.height(x, z)


func _v(p: Vector2) -> Vector3:
	return Vector3(p.x, a.height(p.x, p.y), p.y)


func _builder(seed: int, base_y: float, top_y: float) -> StoneBuilder:
	var sb := StoneBuilder.new(_g, seed)
	sb.base_y = base_y
	sb.top_y = top_y
	return sb


func build() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	a.add_child(root)
	# one landmark per slice: all nine in one go held a 263 ms frame (22 Oct world trip)
	for f in [_entry, _crossroads, _stairway, _ruins, _viewpoint, _bridge, _falls, _pond, _den]:
		f.call(root)
		await a._build_slice()


# ------------------------------------------------------------------ entry
func _entry(root: Node3D) -> void:
	var c := _v(Vector2(0, 121))
	var sb := _builder(11, c.y - 0.3, c.y + 6.0)
	_arch(sb, c, 0.0, 4.4, 4.2, 1.1, 1.1, false, 0.0)
	# the old boundary wall running off into the trees on both sides, mostly fallen
	_wall(sb, _v(Vector2(-3.4, 121)), _v(Vector2(-16, 123)), 1.9, 0.75, 0.55)
	_wall(sb, _v(Vector2(-16.5, 123)), _v(Vector2(-27, 128)), 1.4, 0.75, 0.8)
	_wall(sb, _v(Vector2(3.4, 121)), _v(Vector2(15, 119.5)), 2.1, 0.75, 0.5)
	_wall(sb, _v(Vector2(15.5, 119.5)), _v(Vector2(25, 115)), 1.2, 0.75, 0.85)
	sb.finish(root, _mat(), "EntryArch")
	stats.entry_blocks = sb.blocks


# ------------------------------------------------------------------ crossroads
func _crossroads(root: Node3D) -> void:
	var p := a.CROSS + Vector2(4.2, 3.0)
	var g := _g(p.x, p.y)
	var sb := _builder(21, g - 0.2, g + 2.4)
	# a carved stele, slightly leaning, on a plinth
	sb.block(Transform3D(Basis(Vector3.UP, 0.4), Vector3(p.x, g + 0.12, p.y)), Vector3(1.1, 0.5, 0.8), 0.6)
	sb.block(Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.05), Vector3(p.x, g + 1.25, p.y)), Vector3(0.62, 1.9, 0.32), 0.35, 0.05)
	sb.block(Transform3D(Basis(Vector3.UP, 0.4), Vector3(p.x, g + 2.28, p.y)), Vector3(0.78, 0.2, 0.44), 0.8)
	sb.collider(Transform3D(Basis(Vector3.UP, 0.4), Vector3(p.x, g + 1.0, p.y)), Vector3(1.0, 2.2, 0.7))
	# a stone lantern on the other side of the junction
	var q := a.CROSS + Vector2(-4.0, -3.4)
	var gq := _g(q.x, q.y)
	sb.block(Transform3D(Basis.IDENTITY, Vector3(q.x, gq + 0.1, q.y)), Vector3(0.9, 0.35, 0.9), 0.5)
	sb.block(Transform3D(Basis(Vector3.UP, 0.785), Vector3(q.x, gq + 0.75, q.y)), Vector3(0.36, 1.0, 0.36), 0.1)
	sb.block(Transform3D(Basis.IDENTITY, Vector3(q.x, gq + 1.32, q.y)), Vector3(0.7, 0.14, 0.7), 0.3)
	for k in 4:
		var o := Vector3(0.24, 0, 0.24).rotated(Vector3.UP, k * PI * 0.5)
		sb.block(Transform3D(Basis.IDENTITY, Vector3(q.x, gq + 1.6, q.y) + o), Vector3(0.12, 0.42, 0.12), 0.0)
	sb.block(Transform3D(Basis(Vector3.UP, 0.785), Vector3(q.x, gq + 1.9, q.y)), Vector3(0.8, 0.18, 0.8), 0.9)
	sb.block(Transform3D(Basis(Vector3.UP, 0.785), Vector3(q.x, gq + 2.08, q.y)), Vector3(0.36, 0.2, 0.36), 0.9)
	sb.collider(Transform3D(Basis.IDENTITY, Vector3(q.x, gq + 1.0, q.y)), Vector3(0.8, 2.1, 0.8))
	sb.finish(root, _mat(), "Crossroads")
	var glow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	glow.mesh = sm
	glow.material_override = Kit.emissive(Color(1.0, 0.78, 0.45), 4.0, true)
	glow.position = Vector3(q.x, gq + 1.6, q.y)
	root.add_child(glow)
	var l := Kit.omni(root, Vector3(q.x, gq + 1.65, q.y), Color(1.0, 0.75, 0.45), 1.6, 9.0)
	a.night_only(l)
	a.night_only(glow)


# ------------------------------------------------------------------ stairway
func _stairway(root: Node3D) -> void:
	var base := _v(a.STAIR_BASE + Vector2(0, 2.5))
	var sb := _builder(31, base.y - 0.4, base.y + 14.0)
	# lower flight, landing, main flight (the terrain ramp underneath is the walking surface)
	sb.steps(_v(a.STAIR_BASE + Vector2(0, 2.5)), _v(a.STAIR_LANDING + Vector2(0, 2.0)), 4.6, 0.48, 0.16, 0.5)
	sb.steps(_v(a.STAIR_LANDING + Vector2(0, 2.0)), _v(a.STAIR_LANDING + Vector2(0, -2.0)), 5.6, 1.0, 0.1)   # broad landing slabs
	sb.steps(_v(a.STAIR_LANDING + Vector2(0, -2.0)), _v(Vector2(0, -29.0)), 4.2, 0.46, 0.16, 0.5)
	# the left fork: a narrow worn flight up the shelf to the alcove
	sb.steps(_v(a.STAIR_LANDING + Vector2(-3.0, -0.5)), _v(a.ALCOVE + Vector2(3.5, 2.5)), 1.8, 0.55, 0.14)
	# three pointed arches over the main flight; the middle one has partly fallen
	_arch(sb, _v(Vector2(0, -1.5)), 0.0, 5.4, 3.6, 0.95, 1.0, true, 0.0)
	_arch(sb, _v(Vector2(0, -14.0)), 0.0, 5.4, 3.4, 0.95, 1.0, true, 0.45)
	_arch(sb, _v(Vector2(0, -24.0)), 0.0, 5.4, 3.2, 0.95, 1.0, true, 0.0)
	# low retaining walls flanking the upper flight
	for s: float in [-1.0, 1.0]:
		_wall(sb, _v(Vector2(s * 3.9, -16.0)), _v(Vector2(s * 3.9, -22.5)), 1.3, 0.6, 0.45)
		_wall(sb, _v(Vector2(s * 3.9, 0.5)), _v(Vector2(s * 3.9, -5.5)), 1.1, 0.6, 0.5)
	# fallen voussoirs lying beside the broken arch
	for k in 3:
		sb.block(Transform3D(Basis.from_euler(Vector3(0.3 * k, 0.9 * k, 1.2)), _v(Vector2(4.8 + k * 0.7, -13.0 - k * 0.9)) + Vector3(0, 0.2, 0)), Vector3(0.9, 0.85, 0.95), 0.7)
	sb.finish(root, _mat(), "Stairway")
	stats.stair_blocks = sb.blocks


# ------------------------------------------------------------------ ruins
func _ruins(root: Node3D) -> void:
	var gate := _v(a.RUIN_GATE)
	var sb := _builder(41, gate.y - 0.4, gate.y + 7.0)
	_arch(sb, gate, 0.0, 4.0, 4.6, 1.3, 1.4, false, 0.0)
	# the enclosure: a rectangle of collapsed walls (gaps where it has fallen completely)
	var x0 := -16.0
	var x1 := 16.0
	var z0 := a.RUIN_GATE.y
	var z1 := a.RUIN_GATE.y - 27.0
	var wall_h := 3.6
	_wall(sb, _v(Vector2(-3.3, z0)), _v(Vector2(-9.5, z0)), wall_h, 0.9, 0.35)
	_wall(sb, _v(Vector2(-11.5, z0)), _v(Vector2(x0, z0 + 0.3)), wall_h, 0.9, 0.7)
	_wall(sb, _v(Vector2(3.3, z0)), _v(Vector2(x1, z0 - 0.2)), wall_h, 0.9, 0.5)
	_wall(sb, _v(Vector2(x0, z0 + 0.3)), _v(Vector2(x0 - 0.3, z0 - 11.0)), wall_h, 0.9, 0.6)
	_wall(sb, _v(Vector2(x0 - 0.4, z0 - 15.5)), _v(Vector2(x0, z1)), wall_h, 0.9, 0.75)   # gap: the frontier road leaves west
	_wall(sb, _v(Vector2(x1, z0 - 0.2)), _v(Vector2(x1, z0 - 8.0)), wall_h, 0.9, 0.4)
	_wall(sb, _v(Vector2(x1 + 0.2, z0 - 12.5)), _v(Vector2(x1, z1)), wall_h * 0.8, 0.9, 0.85)  # gap: the viewpoint path
	_wall(sb, _v(Vector2(x0, z1)), _v(Vector2(-4.0, z1 - 0.4)), wall_h * 1.25, 0.9, 0.3)
	_wall(sb, _v(Vector2(2.0, z1 - 0.4)), _v(Vector2(x1, z1)), wall_h * 1.1, 0.9, 0.55)
	# a pointed arch standing alone at the back (the old sanctum's doorway)
	_arch(sb, _v(Vector2(-1.0, z1 - 0.2)), 0.0, 3.4, 4.4, 1.0, 1.2, true, 0.0)
	# colonnade: two rows of columns, most broken
	var heights := [4.6, 2.1, 3.4, 1.2, 4.2, 2.8, 0.9, 3.9]
	for i in 4:
		var z := z0 - 5.0 - i * 4.6
		sb.column(_v(Vector2(-7.0, z)), 0.42, heights[i * 2])
		sb.column(_v(Vector2(7.0, z)), 0.42, heights[i * 2 + 1])
	# a toppled column: drums lying in the grass
	for k in 3:
		var p := Vector2(9.5 + k * 1.05, z0 - 15.0 - k * 0.35)
		sb.block(Transform3D(Basis.from_euler(Vector3(0, 0.25, PI * 0.5 + k * 0.1)), _v(p) + Vector3(0, 0.3, 0)), Vector3(1.0, 0.84, 0.84), 0.6, 0.12)
	# the inscription stone: a broad stele on a step, facing the gate
	var ins := _v(a.INSCRIPTION)
	sb.block(Transform3D(Basis.IDENTITY, ins + Vector3(0, 0.15, 0)), Vector3(3.0, 0.5, 1.8), 0.4)
	sb.block(Transform3D(Basis(Vector3.RIGHT, -0.04), ins + Vector3(0, 1.45, -0.2)), Vector3(2.0, 2.3, 0.5), 0.25, 0.05)
	sb.block(Transform3D(Basis.IDENTITY, ins + Vector3(0, 2.7, -0.2)), Vector3(2.3, 0.26, 0.7), 0.9)
	sb.collider(Transform3D(Basis.IDENTITY, ins + Vector3(0, 1.2, -0.2)), Vector3(2.4, 2.6, 1.0))
	sb.finish(root, _mat(), "Ruins")
	stats.ruin_blocks = sb.blocks
	_runes(root, ins + Vector3(0, 1.55, 0.07))
	# a great tree has grown up inside the enclosure, its crown over the wall
	var tp := Vector2(-11.5, z0 - 6.5)
	var tx := Transform3D(Basis(Vector3.UP, 2.2).scaled(Vector3.ONE * 1.0), _v(tp) - Vector3(0, 0.2, 0))
	NatureKit.scatter(root, NatureKit.mesh("TwistedTree_3"), [tx], {"shadow": true, "vis_end": 200.0, "name": "RuinTree"})
	NatureKit.trunk_colliders(root, [tx], 0.7)
	ruin_tree = tx


## Faint runes carved on the stele: a glowing band (night) + carved marks.
func _runes(root: Node3D, at: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.text = "ᛚᛁᚷᚺᛏ · ᛒᛖᚤᛟᚾᛞ\n· ᚲᚱᛁᛋᛏᚨᛚ · ᚹᚨᛚᛖ ·"
	lbl.font_size = 64
	lbl.pixel_size = 0.0042
	lbl.modulate = Color(0.32, 0.36, 0.3, 0.9)
	lbl.outline_size = 0
	lbl.shaded = true
	lbl.double_sided = false
	lbl.position = at
	root.add_child(lbl)
	var glow := lbl.duplicate() as Label3D
	glow.modulate = Color(0.45, 0.95, 0.85, 1.0)
	glow.shaded = false
	glow.position = at + Vector3(0, 0, 0.005)
	root.add_child(glow)
	a.night_only(glow)


# ------------------------------------------------------------------ viewpoint
func _viewpoint(root: Node3D) -> void:
	var c := _v(a.VIEWPOINT)
	var level := c.y + 0.12                      # one level platform (the edge of the escarpment falls away below it)
	var sb := _builder(51, level - 6.0, level + 1.2)
	# paved half-round terrace: radial slabs, all at one level, on a coursed retaining wall where the ground drops
	for ring in 3:
		var r := 1.6 + ring * 1.7
		var n := 6 + ring * 5
		for i in n:
			var ang := -PI * 0.5 + PI * (i + 0.5) / n
			var p := Vector2(a.VIEWPOINT.x + cos(ang) * r, a.VIEWPOINT.y + sin(ang) * r)
			var size := Vector3(1.6, 0.36, PI * r / n * 1.95)
			var bb := Basis(Vector3.UP, -ang)
			sb.block(Transform3D(bb * sb._jit(0.4), Vector3(p.x, level - 0.18, p.y)), size, 0.2, 0.05)
			sb.collider(Transform3D(bb, Vector3(p.x, level - 0.2, p.y)), Vector3(1.7, 0.4, size.z + 0.1))
	# the centre stone (a round slab with a carved ring)
	sb._drum(Vector3(a.VIEWPOINT.x, level - 0.36, a.VIEWPOINT.y), 0.85, 0.36, 12, 0.0, 0.1)
	# the west half (towards the ruins) is a flat landing on the same level
	for i in 5:
		for j in 3:
			var p2 := a.VIEWPOINT + Vector2(-1.2 - j * 1.6, -3.6 + i * 1.8)
			sb.block(Transform3D(sb._jit(0.4), Vector3(p2.x, level - 0.18, p2.y)), Vector3(1.55, 0.36, 1.75), 0.2, 0.05)
			sb.collider(Transform3D(Basis.IDENTITY, Vector3(p2.x, level - 0.2, p2.y)), Vector3(1.6, 0.4, 1.8))
	# retaining wall under the outer arc, from the ground up to the paving
	var R := 6.1
	for i in 18:
		var ang2 := -PI * 0.5 + PI * (i + 0.5) / 18.0
		var p3 := Vector2(a.VIEWPOINT.x + cos(ang2) * R, a.VIEWPOINT.y + sin(ang2) * R)
		var gy := _g(p3.x, p3.y) - 0.3
		var y := gy
		var bb2 := Basis(Vector3.UP, -ang2)
		while y < level - 0.36:
			var ch := minf(0.5, level - 0.36 - y)
			sb.block(Transform3D(bb2 * sb._jit(0.8), Vector3(p3.x, y + ch * 0.5, p3.y)), Vector3(0.9, ch, PI * R / 18.0 * 1.0), 0.05)
			y += ch + 0.01
		# fill under the paving between the wall and the slope (hidden mass)
		var inner := Vector2(a.VIEWPOINT.x + cos(ang2) * 3.4, a.VIEWPOINT.y + sin(ang2) * 3.4)
		var gi := _g(inner.x, inner.y)
		if level - gi > 0.5:
			sb.block(Transform3D(bb2, Vector3(inner.x, (gi + level - 0.36) * 0.5, inner.y)), Vector3(4.6, level - 0.36 - gi, PI * 3.4 / 18.0 * 2.0), 0.0)
	# parapet on the outer arc (a gap where it fell into the valley)
	for i in 7:
		if i == 3:
			continue
		var a0 := -PI * 0.5 + PI * i / 7.0
		var a1 := -PI * 0.5 + PI * (i + 1) / 7.0
		var q0 := a.VIEWPOINT + Vector2(cos(a0), sin(a0)) * (R - 0.2)
		var q1 := a.VIEWPOINT + Vector2(cos(a1), sin(a1)) * (R - 0.2)
		var dirv := (q1 - q0)
		var mid := (q0 + q1) * 0.5
		var yaw := atan2(-dirv.y, dirv.x)
		var L := dirv.length()
		var k := 0.0
		while k < L - 0.1:
			var bl := minf(sb.rng.randf_range(0.55, 0.85), L - k)
			var pc := q0 + dirv.normalized() * (k + bl * 0.5)
			sb.block(Transform3D(Basis(Vector3.UP, yaw) * sb._jit(1.0), Vector3(pc.x, level + 0.26, pc.y)), Vector3(bl - 0.04, 0.5, 0.42), 0.6)
			k += bl
		sb.collider(Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, level + 0.5, mid.y)), Vector3(L, 1.0, 0.42))
	sb.column(Vector3(a.VIEWPOINT.x - 1.5, level, a.VIEWPOINT.y - 6.0), 0.36, 2.2)
	sb.column(Vector3(a.VIEWPOINT.x - 1.5, level, a.VIEWPOINT.y + 6.0), 0.36, 3.1)
	# the benchmark terrace: older, mossier, warmer stone than the rest (visual quality pass)
	var vmat: ShaderMaterial = _mat().duplicate()
	if RealKit.enabled():
		vmat.set_shader_parameter("moss_amount", 0.5)      # worn paving: moss in patches, not a green cap on every block
	if not WoodsHero.off():
		vmat.set_shader_parameter("moss_amount", 1.25)
		vmat.set_shader_parameter("stone_a", Color(0.78, 0.73, 0.64))
		vmat.set_shader_parameter("stone_warm", Color(0.74, 0.62, 0.47))
		vmat.set_shader_parameter("moss_b", Color(0.46, 0.56, 0.24))
		vmat.set_shader_parameter("grain_strength", 1.15)
	sb.finish(root, vmat, "Viewpoint")
	stats.viewpoint_blocks = sb.blocks
	# the Keepers' fire bowls on the two columns, cold for three hundred years (V3 Part X: the Phoenix lights them)
	# on top of their columns: a column stands on the real ground (StoneBuilder.column: ground - 0.15 + height, plus
	# its capital and abacus when 3 m or taller), which on this slope is well below the terrace level
	var cn := Vector2(a.VIEWPOINT.x - 1.5, a.VIEWPOINT.y - 6.0)
	var cs := Vector2(a.VIEWPOINT.x - 1.5, a.VIEWPOINT.y + 6.0)
	_fire_bowl(root, Vector3(cn.x, _g(cn.x, cn.y) - 0.15 + 2.2, cn.y), "viewpoint_bowl_n", "the north fire bowl at the viewpoint")
	_fire_bowl(root, Vector3(cs.x, _g(cs.x, cs.y) - 0.15 + 3.1 + 0.45, cs.y), "viewpoint_bowl_s", "the south fire bowl at the viewpoint")


func _fire_bowl(root: Node3D, top: Vector3, id: String, label: String) -> void:
	var br := Brazier.new()
	br.name = id
	br.position = top + Vector3(0, 0.15, 0)        # the bowl's foot rests on the column top
	root.add_child(br)
	var bowl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.26
	cm.height = 0.3
	cm.radial_segments = 14
	bowl.mesh = cm
	var im := StandardMaterial3D.new()
	im.albedo_color = Color(0.42, 0.33, 0.24)       # old weathered bronze (it read as a black lump)
	im.metallic = 0.35
	im.roughness = 0.72
	bowl.material_override = im
	bowl.position = Vector3(0, -0.08, 0)
	br.add_child(bowl)
	var coals := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.2
	coals.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.3, 0.28, 0.26)      # cold grey ash: unlit for three hundred years (no red glow)
	cmat.roughness = 0.95
	coals.material_override = cmat
	coals.position = Vector3(0, 0.0, 0)
	br.add_child(coals)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.26)
	l.light_energy = 1.4
	l.omni_range = 9.0
	l.shadow_enabled = false
	l.position = Vector3(0, 0.4, 0)
	br.add_child(l)
	var fp := _fire_particles()
	br.add_child(fp)
	br.setup(id, label, fp, l)
	br.start_unlit()


## The same flame the Sanctuary's braziers use (its builder is inside the Sanctuary script).
static func _fire_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.3))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1, 0.0))
	curve.curve = c
	pm.scale_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.44)
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/magic/energy_mote.gdshader")
	smat.set_shader_parameter("hdr_boost", 4.0)
	quad.material = smat
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
	return p


# ------------------------------------------------------------------ bridge
func _deck_y(x: float, base: float) -> float:
	var w0 := a.BRIDGE_W
	var w1 := a.BRIDGE_E
	var top := base + 1.9
	if x < w0:
		return lerpf(_g(w0 - 6.0, a.BRIDGE.y) - 0.05, top, clampf((x - (w0 - 6.0)) / 6.0, 0.0, 1.0))
	if x > w1:
		return lerpf(top, _g(w1 + 6.0, a.BRIDGE.y) - 0.05, clampf((x - w1) / 6.0, 0.0, 1.0))
	return top + 1.6 * sin(PI * (x - w0) / (w1 - w0))


func _bridge(root: Node3D) -> void:
	var z := a.BRIDGE.y
	var base := maxf(_g(a.BRIDGE_W - 6.0, z), _g(a.BRIDGE_E + 6.0, z))
	var sb := _builder(61, base - 3.5, base + 4.0)
	var depth := 3.6
	# arches: [centre x, radius, springing y]
	var arches := [[52.725, 2.725, base - 1.0], [60.0, 3.45, base - 1.5], [67.275, 2.725, base - 1.0]]
	var thick := 0.6
	for ar in arches:
		sb.ring(Vector3(ar[0], ar[2], z), 0.0, ar[1], thick, depth, 11 if ar[1] < 3.0 else 13)
	# piers in the river (with upstream cutwaters) and abutments
	for px: float in [56.0, 64.0]:
		var bed := _g(px, z) - 0.6
		var y := bed
		while y < base - 1.0:
			var ch := minf(0.55, base - 1.0 - y)
			sb.block(Transform3D(sb._jit(0.6), Vector3(px, y + ch * 0.5, z)), Vector3(1.1, ch, depth), 0.1)
			sb.block(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(px, y + ch * 0.5, z - depth * 0.5)), Vector3(0.78, ch, 0.78), 0.1)
			y += ch + 0.01
		sb.collider(Transform3D(Basis.IDENTITY, Vector3(px, (bed + base - 1.0) * 0.5, z)), Vector3(1.1, base - 1.0 - bed, depth))
	for ab in [[a.BRIDGE_W - 0.75, -1.0], [a.BRIDGE_E + 0.75, 1.0]]:
		var ax: float = ab[0]
		var gy := _g(ax, z) - 0.4
		var top := _deck_y(ax, base) - 0.3
		var y2 := gy
		while y2 < top - 0.05:
			var ch2 := minf(0.5, top - y2)
			sb.block(Transform3D(sb._jit(0.6), Vector3(ax, y2 + ch2 * 0.5, z)), Vector3(1.5, ch2, depth + 0.2), 0.15)
			y2 += ch2 + 0.01
	# spandrels: fill between the arch rings and the deck
	var x := a.BRIDGE_W
	while x < a.BRIDGE_E - 0.01:
		var xm := x + 0.45
		var yt := -INF
		for ar in arches:
			var dx: float = xm - float(ar[0])
			var ro: float = float(ar[1]) + thick
			if absf(dx) < ro:
				yt = maxf(yt, float(ar[2]) + sqrt(ro * ro - dx * dx) - 0.15)
		if absf(xm - 56.0) < 0.6 or absf(xm - 64.0) < 0.6:
			yt = maxf(yt, base - 1.0)
		var dtop := _deck_y(xm, base) - 0.32
		if yt > -INF and dtop - yt > 0.12:
			for side: float in [-1.0, 1.0]:
				sb.block(Transform3D(sb._jit(0.5), Vector3(xm, (yt + dtop) * 0.5, z + side * (depth * 0.5 - 0.3))), Vector3(0.88, dtop - yt, 0.6), 0.05)
		x += 0.9
	# deck slabs, ramps and parapets
	x = a.BRIDGE_W - 6.0
	while x < a.BRIDGE_E + 6.0 - 0.01:
		var x0 := x
		var x1 := x + 0.95
		var y0 := _deck_y(x0, base)
		var y1 := _deck_y(x1, base)
		var mid := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z)
		var pitch := atan2(y1 - y0, x1 - x0)
		var bb := Basis(Vector3.BACK, pitch)
		for j in 3:
			var zz := z - 1.2 + j * 1.2
			sb.block(Transform3D(bb * sb._jit(0.4), mid + Vector3(0, -0.2, zz - z)), Vector3(0.93, 0.4, 1.16), sb.rng.randf() * 0.3, 0.04)
		var on_span := x0 > a.BRIDGE_W - 3.5 and x1 < a.BRIDGE_E + 3.5
		if on_span:
			var slice_i := int(round((x0 - (a.BRIDGE_W - 6.0)) / 0.95))
			for side2: float in [-1.0, 1.0]:
				var edge := mid + Vector3(0, 0, side2 * (depth * 0.5 + 0.05))
				# curb along the whole edge
				sb.block(Transform3D(bb * sb._jit(0.5), edge + Vector3(0, 0.11, 0)), Vector3(0.93, 0.22, 0.42), 0.45)
				# a post every other slice (a few have fallen), a rail between them
				if slice_i % 2 == 0 and sb.rng.randf() > 0.08:
					sb.block(Transform3D(bb * sb._jit(0.8), edge + Vector3(0, 0.62, 0)), Vector3(0.3, 0.8, 0.3), 0.3)
					sb.block(Transform3D(bb, edge + Vector3(0, 1.06, 0)), Vector3(0.38, 0.08, 0.38), 0.6)
				sb.block(Transform3D(bb * sb._jit(0.3), edge + Vector3(0, 0.94, 0)), Vector3(0.95, 0.14, 0.18), 0.5)
				sb.collider(Transform3D(bb, edge + Vector3(0, 0.55, 0)), Vector3(1.0, 1.1, 0.42))
		# walking surface: one box per slice, pitched to meet its neighbours
		sb.collider(Transform3D(bb, mid - Vector3(0, 0.2, 0)), Vector3(Vector2(x1 - x0, y1 - y0).length() + 0.04, 0.4, depth))
		x = x1
	sb.finish(root, _mat(), "OldBridge")
	stats.bridge_blocks = sb.blocks


# ------------------------------------------------------------------ waterfall
func _falls(root: Node3D) -> void:
	var lip_z := a.FALLS.y + 1.0
	var xc := a.river_x(lip_z)
	var top := a.upper_water_y()
	var foot := a.pool_water_y()
	var drop := top - foot
	var noise := Kit.noise()
	var sheets := [[0.0, 7.2, 0.0, 3.0, 0.9], [-4.7, 1.5, 0.6, 1.9, 1.1], [4.9, 1.9, 0.45, 2.2, 1.0]]   # [x off, width, start below lip, reach, speed]
	for sh in sheets:
		var m := _sheet(Vector3(xc + float(sh[0]), top - float(sh[2]), lip_z), float(sh[1]), drop - float(sh[2]) + 0.2, float(sh[3]))
		var mi := MeshInstance3D.new()
		mi.name = "Waterfall"
		mi.mesh = m
		mi.material_override = Kit.shader_mat("res://shaders/nature/stylized_waterfall.gdshader", {"noise_tex": noise, "width_m": float(sh[1]), "speed": float(sh[4])})
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	# churning foam where it lands, spreading downstream
	var foam := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(12.0, 9.0)
	q.orientation = PlaneMesh.FACE_Y
	foam.mesh = q
	foam.material_override = Kit.shader_mat("res://shaders/nature/foam_patch.gdshader", {"noise_tex": noise})
	foam.position = Vector3(xc, foot + 0.04, lip_z + 3.0 + 4.5)
	foam.rotation.y = PI      # UV.y = 0 at the impact line
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(foam)
	# mist rising from the plunge
	var mist := GPUParticles3D.new()
	mist.amount = 26
	mist.lifetime = 5.0
	mist.preprocess = 5.0
	mist.position = Vector3(xc, foot + 0.6, lip_z + 3.2)
	mist.visibility_aabb = AABB(Vector3(-8, -2, -6), Vector3(16, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(4.0, 0.3, 1.0)
	pm.direction = Vector3(0, 1, 0.6)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.15, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	mist.process_material = pm
	var mq := QuadMesh.new()
	mq.size = Vector2(3.0, 3.0)
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_color = Color(0.93, 0.97, 1.0)
	mm.albedo_texture = WoodsDressing._dot_tex()
	mm.proximity_fade_enabled = true
	mm.proximity_fade_distance = 1.0
	mq.material = mm
	mist.draw_pass_1 = mq
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mist)
	# boulders framing the lip and the pool
	var rocks := [[-5.4, -1.5, 1.5, 0.2], [6.2, -1.2, 1.8, 0.0], [-3.7, 0.2, 0.9, 0.6], [3.9, 0.3, 1.0, 0.5],
		[-8.8, 7.0, 1.2, 0.0], [9.0, 7.0, 1.5, 0.0], [2.6, 3.6, 0.7, 0.0], [-10.5, 12.5, 0.9, 0.0], [10.5, 12.5, 1.0, 0.0]]
	var by_id := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for r in rocks:
		var p := Vector2(xc + float(r[0]), lip_z + float(r[1]))
		var y := _g(p.x, p.y)
		if float(r[3]) > 0.0:
			y = top - 0.6
		var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
		if not by_id.has(id):
			by_id[id] = []
		var s: float = r[2]
		by_id[id].append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))).scaled(Vector3.ONE * s), Vector3(p.x, y - 0.35 * s, p.y)))
	# the drop's faces either side of the water: stacked mossy boulders instead of a smooth slope
	for side: float in [-1.0, 1.0]:
		for k in 7:
			var off := 5.5 + k * 1.9 + rng.randf_range(-0.4, 0.4)
			var hy := lerpf(foot + 0.5, top - 0.8, rng.randf_range(0.15, 0.85))
			# find where the steep face reaches that height (the terrain falls with +z here)
			var lo := lip_z - 4.0
			var hi := lip_z + 5.0
			for it in 14:
				var mz := (lo + hi) * 0.5
				if _g(xc + side * off, mz) > hy:
					lo = mz
				else:
					hi = mz
			var p2 := Vector2(xc + side * off, (lo + hi) * 0.5 + rng.randf_range(-0.3, 0.2))
			var id2: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
			if not by_id.has(id2):
				by_id[id2] = []
			var s2 := rng.randf_range(1.2, 1.9)
			by_id[id2].append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))).scaled(Vector3.ONE * s2), Vector3(p2.x, hy - 0.6 * s2, p2.y)))
	for id in by_id:
		NatureKit.scatter(root, NatureKit.mesh(id), by_id[id], {"shadow": true, "vis_end": 260.0, "name": "FallsRock"})


## A falling-water ribbon: leaves the lip level (bending over the edge), then plunges; reach = forward travel.
func _sheet(lip: Vector3, width: float, drop: float, reach: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 30
	var cols := 6
	var pts := []
	for i in rows + 1:
		var t := float(i) / rows
		var y := lip.y - drop * t * t
		var zz := lip.z + reach * t
		var w := width * (1.0 + 0.12 * t)
		var row := []
		for j in cols + 1:
			var u := float(j) / cols
			row.append([Vector3(lip.x + (u - 0.5) * w, y, zz), Vector2(u, t)])
		pts.append(row)
	for i in rows:
		for j in cols:
			var quad := [pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(0, 0.3, 1).normalized())
				st.set_uv(quad[k][1])
				st.add_vertex(quad[k][0])
	return st.commit()


# ------------------------------------------------------------------ pond
func _pond(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var wy: float = a.height(a.POND.x, a.POND.y) + 1.55
	var pads := []
	var pad_cols := []
	var lotus := []
	# lily pads drift in loose clusters, mostly near the shore and the spring
	for c in 9:
		var cc: Vector2 = a.POND + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, a.POND_R - 1.0)
		for i in rng.randi_range(5, 11):
			var p: Vector2 = cc + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 3.6)
			if p.distance_to(a.POND) > a.POND_R + 1.2:
				continue
			var s := rng.randf_range(1.1, 2.0)
			pads.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, wy + 0.015 + rng.randf() * 0.01, p.y)))
			pad_cols.append(Color(1, 1, 1).lerp(Color(0.8, 0.95, 0.7), rng.randf()))
			if rng.randf() < 0.22:
				lotus.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.6, 2.3)), Vector3(p.x, wy + 0.02, p.y)))
	var pad_mat := StandardMaterial3D.new()
	pad_mat.vertex_color_use_as_albedo = true
	pad_mat.roughness = 0.35
	pad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mmi in NatureKit.scatter(root, _lily_pad(), pads, {"colors": pad_cols, "vis_end": 90.0, "name": "LilyPads"}):
		(mmi as MultiMeshInstance3D).material_override = pad_mat
	var lotus_mat := StandardMaterial3D.new()
	lotus_mat.vertex_color_use_as_albedo = true
	lotus_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lotus_mat.roughness = 0.6
	lotus_mat.emission_enabled = true
	lotus_mat.emission = Color(1.0, 0.55, 0.8)
	lotus_mat.emission_energy_multiplier = 0.05
	lotus_mat.backlight_enabled = true
	lotus_mat.backlight = Color(0.6, 0.3, 0.45)
	_lotus_mat = lotus_mat
	for mmi in NatureKit.scatter(root, _lotus(), lotus, {"vis_end": 90.0, "name": "Lotus"}):
		(mmi as MultiMeshInstance3D).material_override = lotus_mat
	# reeds and tall wispy grass around the shore
	var reeds := []
	for i in 140:
		var ang := rng.randf() * TAU
		var d := a.POND_R + rng.randf_range(0.6, 3.4)
		var p2: Vector2 = a.POND + Vector2.from_angle(ang) * d
		if a.dress.trail_dist(p2.x, p2.y) < 1.2:
			continue
		reeds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.15)), Vector3(p2.x, a.height(p2.x, p2.y) - 0.05, p2.y)))
	NatureKit.scatter(root, NatureKit.mesh("Grass_Wispy_Tall"), reeds, {"vis_end": 60.0, "name": "Reeds"})
	stats.lily_pads = pads.size()
	stats.lotus = lotus.size()


var _lotus_mat: StandardMaterial3D


## Night: lotus petals glow faintly.
func set_night(v: bool) -> void:
	if _lotus_mat:
		_lotus_mat.emission_energy_multiplier = 1.4 if v else 0.05


## A lily pad: a slightly cupped disc with the characteristic notch; darker centre, light rim, veins by colour.
static func _lily_pad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 22
	var notch := 0.32
	var r := 0.6
	var centre := Color(0.16, 0.36, 0.14)
	var rim := Color(0.40, 0.62, 0.26)
	for i in segs:
		var a0 := notch * 0.5 + (TAU - notch) * i / segs
		var a1 := notch * 0.5 + (TAU - notch) * (i + 1) / segs
		var p0 := Vector3(cos(a0) * r, 0.02, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.02, sin(a1) * r)
		var vein := 0.12 if i % 3 == 0 else 0.0
		for v in [[Vector3.ZERO, centre], [p1, rim.darkened(vein)], [p0, rim.darkened(vein)]]:
			st.set_normal(Vector3.UP)
			st.set_color(v[1])
			st.add_vertex(v[0])
	return st.commit()


## A lotus: two rings of cupped petals (white tips, pink bases) around a golden centre.
static func _lotus() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [[8, 0.17, 0.95, 0.0], [6, 0.13, 0.6, 0.4]]   # count, length, tilt from vertical (rad), yaw offset
	for rg in rings:
		var n: int = rg[0]
		for i in n:
			var yaw: float = TAU * i / n + float(rg[3])
			var tilt: float = rg[2]
			var L: float = rg[1]
			var dir := Vector3(sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw))
			var side := Vector3(-sin(yaw), 0, cos(yaw)) * L * 0.32
			var base := Vector3(0, 0.03, 0)
			var mid := base + dir * L * 0.55
			var tip := base + dir * L + Vector3(0, 0.02, 0)
			var pink := Color(0.95, 0.45, 0.66)
			var white := Color(1.0, 0.92, 0.95)
			for tri in [[base, mid + side, mid - side], [mid - side, mid + side, tip]]:
				for k in 3:
					var v: Vector3 = tri[k]
					st.set_normal((v - base + Vector3(0, 0.05, 0)).normalized())
					st.set_color(pink.lerp(white, clampf((v - base).length() / L, 0.0, 1.0)))
					st.add_vertex(v)
	# centre
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		for v2 in [Vector3(0, 0.08, 0), Vector3(cos(a1) * 0.04, 0.06, sin(a1) * 0.04), Vector3(cos(a0) * 0.04, 0.06, sin(a0) * 0.04)]:
			st.set_normal(Vector3.UP)
			st.set_color(Color(1.0, 0.8, 0.25))
			st.add_vertex(v2)
	return st.commit()


# ------------------------------------------------------------------ monster den
func den_mouth() -> Vector3:
	return _v(a.DEN_MOUTH)


func _den(root: Node3D) -> void:
	var mouth := den_mouth()
	var face := Vector3(a.DEN_FACE.x, 0, a.DEN_FACE.y)   # the mouth looks down the trail
	var right := Vector3(-face.z, 0, face.x)
	var centre := mouth - face * 5.0 + Vector3(0, -1.2, 0)
	var stone: ShaderMaterial = RealKit.stone_mat("rock_pitted_mossy", false) if RealKit.enabled() else Kit.shader_mat("res://shaders/nature/stylized_stone.gdshader", {"grain_tex": load(Kit.tex_set("rock_wall_10", "1k")[0]),
		"noise_tex": Kit.noise(), "stone_a": Color(0.56, 0.54, 0.5), "stone_b": Color(0.4, 0.42, 0.42), "moss_amount": 0.75, "grain_scale": 0.22})
	var win := {"face": face, "right": right, "w": 2.5, "spring": 3.1, "crown": 4.0}
	var outer := MeshInstance3D.new()
	outer.name = "DenOutcrop"
	outer.mesh = _rock_dome(Vector3(8.0, 6.5, 7.5), 71, true, win)
	outer.material_override = stone
	outer.position = centre
	root.add_child(outer)
	var inner := MeshInstance3D.new()
	inner.name = "DenInterior"
	inner.mesh = _rock_dome(Vector3(4.7, 4.7, 4.9), 72, false, win)
	inner.material_override = Kit.shader_mat("res://shaders/nature/cave_interior.gdshader", {"noise_tex": Kit.noise(), "floor_y": mouth.y})
	inner.position = centre
	root.add_child(inner)
	# no luminous fog inside the cave (volumetric fog would light the darkness up)
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = Vector3(11.0, 9.0, 11.0)
	var fm := FogMaterial.new()
	fm.density = -1.0
	fv.material = fm
	fv.position = centre + Vector3(0, 1.5, 0)
	root.add_child(fv)
	# solid: the outcrop blocks movement except through the mouth
	var body := StaticBody3D.new()
	body.name = "DenBody"
	for o in [[-5.9, 1.0], [5.9, 1.0], [-4.6, -3.6], [4.6, -3.6], [0.0, -7.0]]:
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 3.4
		cs.shape = sp
		cs.position = centre + right * float(o[0]) + face * float(o[1]) + Vector3(0, 1.5, 0)
		body.add_child(cs)
	root.add_child(body)
	# a lintel of rough rocks framing the opening (hides where the window cuts the two shells)
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	var rocks := {}
	for i in 15:
		var t := -1.0 + 2.0 * i / 14.0
		var x := t * (float(win.w) + 0.5)
		var y: float = float(win.spring) + (float(win.crown) - float(win.spring)) * sqrt(maxf(0.0, 1.0 - t * t)) + 0.3
		if absf(t) > 0.92:
			y = lerpf(0.9, y, 0.4)
		var p := centre + face * 6.6 + right * x + Vector3(0, y, 0)
		var id: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
		if not rocks.has(id):
			rocks[id] = []
		var sc := rng.randf_range(0.42, 0.6)
		rocks[id].append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))).scaled(Vector3.ONE * sc), p - Vector3(0, 0.35 * sc, 0)))
	# low boulders at the jambs
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var p2 := centre + face * (6.8 - k * 0.5) + right * side * (float(win.w) + 0.9 + k * 1.0)
			var id2: String = ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][rng.randi() % 3]
			if not rocks.has(id2):
				rocks[id2] = []
			var sc2 := rng.randf_range(0.5, 0.8)
			rocks[id2].append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))).scaled(Vector3.ONE * sc2), Vector3(p2.x, a.height(p2.x, p2.z) - 0.3, p2.z)))
	for id in rocks:
		NatureKit.scatter(root, NatureKit.mesh(id), rocks[id], {"shadow": true, "vis_end": 200.0, "name": "DenRim"})
	# fronds hanging over the lip, bushes at the jambs
	var fronds := []
	for i in 5:
		var t2 := -0.7 + 1.4 * i / 4.0
		var p3 := centre + face * 6.9 + right * t2 * 2.6 + Vector3(0, float(win.crown) + 0.9 - absf(t2) * 0.9, 0)
		var bb := Basis.looking_at(face, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.62)
		fronds.append(Transform3D(bb.scaled(Vector3.ONE * rng.randf_range(0.8, 1.15)), p3))
	NatureKit.scatter(root, NatureKit.mesh("Fern_1", "dark"), fronds, {"vis_end": 120.0, "name": "DenFronds"})
	var feet := []
	for i in 10:
		var p4 := centre + face * rng.randf_range(7.0, 9.5) + right * rng.randf_range(-7.0, 7.0)
		if absf((p4 - centre).dot(right)) < 3.2:
			continue    # keep the way in clear
		feet.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.5)), Vector3(p4.x, a.height(p4.x, p4.z) - 0.1, p4.z)))
	NatureKit.scatter(root, NatureKit.mesh("Bush_Common", "dark"), feet, {"shadow": true, "vis_end": 120.0, "name": "DenBushes"})
	stats.den = true


## A noise-displaced dome (upper hemisphere, a little below the horizon) with an arch-shaped window cut on the
## `win.face` side (same absolute window for the outer rock and the inner cave, so the two openings line up).
## outward = rock exterior (vertex COLOR feeds the stone shader); else the cave interior (COLOR = albedo,
## darkening with depth).
func _rock_dome(radii: Vector3, seed: int, outward: bool, win: Dictionary) -> ArrayMesh:
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = 1.4
	fn.fractal_octaves = 4
	var segs := 56
	var rings := 22
	var grid := []
	for r in rings + 1:
		var phi := lerpf(0.0, PI * 0.58, float(r) / rings)
		var row := []
		for s2 in segs + 1:
			var th := TAU * s2 / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var n := fn.get_noise_3dv(d * 2.0)
			row.append([d, d * radii * (1.0 + n * (0.22 if outward else 0.12)), n])
		grid.append(row)
	var face: Vector3 = win.face
	var right: Vector3 = win.right
	var w: float = win.w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings:
		for s2 in segs:
			var q := [grid[r][s2], grid[r][s2 + 1], grid[r + 1][s2], grid[r + 1][s2 + 1]]
			var pc: Vector3 = (q[0][1] + q[1][1] + q[2][1] + q[3][1]) * 0.25
			var lx := pc.dot(right)
			if pc.dot(face) > 0.0 and absf(lx) < w:
				var top: float = float(win.spring) + (float(win.crown) - float(win.spring)) * sqrt(maxf(0.0, 1.0 - (lx / w) * (lx / w)))
				if pc.y < top:
					continue
			for tri in [[q[0], q[1], q[2]], [q[2], q[1], q[3]]]:
				var p0: Vector3 = tri[0][1]
				var p1: Vector3 = tri[1][1]
				var p2: Vector3 = tri[2][1]
				# Godot front faces are clockwise as seen by the viewer: seen from outside the right-hand cross
				# product must point inward, seen from inside it must point outward
				var out_n := (p1 - p0).cross(p2 - p0).dot(p0 + p1 + p2) > 0.0
				if out_n == outward:
					tri = [tri[0], tri[2], tri[1]]
				for v in tri:
					var pos: Vector3 = v[1]
					if outward:
						st.set_color(Color(0.5 + float(v[2]), smoothstep(0.55, 0.95, (v[0] as Vector3).y) * 0.55, clampf(pos.y / radii.y, 0.0, 1.0), 1.0))
					else:
						var front := clampf(pos.dot(face) / radii.x * 0.5 + 0.5, 0.0, 1.0)
						var k := lerpf(0.015, 0.16, front * front)
						st.set_color(Color(k, k * 0.98, k * 0.9, 1.0))
					st.add_vertex(pos)
	st.generate_normals()
	return st.commit()
