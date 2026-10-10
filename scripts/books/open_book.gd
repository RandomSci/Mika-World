class_name OpenBook
extends Node3D
## A physical magical manuscript that opens on a lectern / desk while it is read.
##  * leather covers with brass corner fittings and an embossed sigil, a rounded spine, a red ribbon
##  * visible page blocks (thickness on both sides) and gently curved open pages
##  * the two open pages carry the REAL text: each is a BookPageView rendered in a SubViewport
##  * page turn: a two-sided curved leaf lifts from the right, carrying the old right page on its front
##    and the next left page on its back, while the spread updates underneath (synced with the overlay)
## Local frame: pages face +Y, the reader stands on +Z, the spine runs along Z at x = 0.

signal opened
signal turned

const W := 0.24      # one page width (m)
const H := 0.33      # page height (m)
const TEX := Vector2i(560, 770)
const BLOCK := 0.016 # page block thickness per side

var book_id := ""
var book := {}
var style := "book"
var _views: Array[BookPageView] = []
var _vps: Array[SubViewport] = []
var _page_mats: Array[StandardMaterial3D] = []
var _cover_r: Node3D
var _leaf: Node3D
var _leaf_front: StandardMaterial3D
var _leaf_back: StandardMaterial3D
var _open := 0.0
var turning := false
static var _page_mesh: ArrayMesh
static var _leaf_mesh: ArrayMesh


## Curved page surface: rises from the gutter, gentle arch, slightly lower at the outer edge.
static func _curved(flip_normals := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 14
	var y := func(u: float) -> float: return 0.014 * (1.0 - exp(-u * 9.0)) * (1.0 - 0.45 * u)
	for i in nx:
		var u0 := float(i) / nx
		var u1 := float(i + 1) / nx
		var x0 := u0 * W
		var x1 := u1 * W
		var y0: float = y.call(u0)
		var y1: float = y.call(u1)
		var n := Vector3(-(y1 - y0), x1 - x0, 0).normalized() * (-1.0 if flip_normals else 1.0)
		var quad := [[Vector3(x0, y0, -H * 0.5), Vector2(u0, 0)], [Vector3(x1, y1, -H * 0.5), Vector2(u1, 0)], [Vector3(x1, y1, H * 0.5), Vector2(u1, 1)],
			[Vector3(x0, y0, -H * 0.5), Vector2(u0, 0)], [Vector3(x1, y1, H * 0.5), Vector2(u1, 1)], [Vector3(x0, y0, H * 0.5), Vector2(u0, 1)]]
		if flip_normals:
			quad = [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
		for v in quad:
			st.set_normal(n)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


func _leather() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.33, 0.12, 0.08) if style == "book" else Color(0.62, 0.52, 0.38)
	m.roughness = 0.62
	m.normal_enabled = true
	m.normal_texture = FX.noise()
	m.normal_scale = 0.25
	m.uv1_scale = Vector3(3, 3, 3)
	return m


func build(p_book_id: String) -> void:
	book_id = p_book_id
	book = BookLibrary.book(book_id)
	style = book.get("style", "book")
	if _page_mesh == null:
		_page_mesh = _curved()
		_leaf_mesh = _curved()
	var leather := _leather()
	var brass := Kit.metal(Color(0.75, 0.58, 0.3), 0.3)
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.86, 0.8, 0.66)
	edge.roughness = 0.9
	# rounded spine
	var spine := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = BLOCK + 0.008
	cyl.bottom_radius = BLOCK + 0.008
	cyl.height = H + 0.02
	cyl.radial_segments = 12
	spine.mesh = cyl
	spine.material_override = leather
	spine.rotation.x = PI * 0.5
	spine.position = Vector3(0, -BLOCK * 0.6, 0)
	add_child(spine)
	for side in [-1, 1]:
		var hinge := Node3D.new()
		add_child(hinge)
		# cover board
		Kit.mesh_node(hinge, Kit.box_mesh(Vector3(W + 0.014, 0.008, H + 0.02), 0.003), leather, Kit.xf(Vector3(side * (W + 0.014) * 0.5, -BLOCK - 0.004, 0)))
		for sz in [-1.0, 1.0]:
			Kit.mesh_node(hinge, Kit.box_mesh(Vector3(0.028, 0.01, 0.028), 0.002), brass, Kit.xf(Vector3(side * (W + 0.002), -BLOCK - 0.004, sz * (H * 0.5 - 0.004))), false)
		# page block (visible thickness)
		Kit.mesh_node(hinge, Kit.box_mesh(Vector3(W - 0.004, BLOCK, H - 0.004), 0.002), edge, Kit.xf(Vector3(side * W * 0.5, -BLOCK * 0.5, 0)), false)
		# the text page, curved, with its SubViewport
		var vp := SubViewport.new()
		vp.size = TEX
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var view := BookPageView.new()
		view.size = Vector2(TEX)
		vp.add_child(view)
		var page := MeshInstance3D.new()
		page.mesh = _page_mesh
		var m := StandardMaterial3D.new()
		m.albedo_texture = vp.get_texture()
		m.emission_enabled = true
		m.emission_texture = vp.get_texture()
		m.emission_energy_multiplier = 0.3   # stays legible under lantern light
		m.roughness = 0.92
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		page.material_override = m
		page.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if side < 0:
			# left page: mirror the curve to the left of the spine, keep text unmirrored
			page.scale = Vector3(-1, 1, 1)
			m.uv1_scale = Vector3(-1, 1, 1)
			m.uv1_offset = Vector3(1, 0, 0)
			m.cull_mode = BaseMaterial3D.CULL_FRONT
		hinge.add_child(page)
		_views.append(view)
		_vps.append(vp)
		_page_mats.append(m)
		if side > 0:
			_cover_r = hinge
			# embossed sigil on the outer cover (seen while closed)
			var emb := FX.quad("res://shaders/magic/sigil.gdshader", 0.15, {"color": Color(0.85, 0.66, 0.32), "sides": 7, "intensity": 0.45, "draw_progress": 1.0, "spin": 0.0, "seed": 5.0}, true)
			emb.position = Vector3(W * 0.5, -BLOCK - 0.0095, 0)
			emb.rotation.x = PI
			hinge.add_child(emb)
	# ribbon bookmark hanging over the bottom edge
	var ribbon := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(0.012, 0.12)
	ribbon.mesh = rq
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.55, 0.06, 0.08)
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon.material_override = rm
	ribbon.position = Vector3(0.01, -0.03, H * 0.5 + 0.02)
	ribbon.rotation.x = -1.2
	add_child(ribbon)
	# the turning leaf: two curved faces back to back
	_leaf = Node3D.new()
	add_child(_leaf)
	_leaf_front = StandardMaterial3D.new()
	_leaf_front.roughness = 0.92
	_leaf_back = StandardMaterial3D.new()
	_leaf_back.roughness = 0.92
	_leaf_back.uv1_scale = Vector3(-1, 1, 1)
	_leaf_back.uv1_offset = Vector3(1, 0, 0)
	var f := MeshInstance3D.new()
	f.mesh = _leaf_mesh
	f.material_override = _leaf_front
	f.position.y = 0.002
	_leaf.add_child(f)
	var bk := MeshInstance3D.new()
	bk.mesh = _curved(true)
	bk.material_override = _leaf_back
	bk.position.y = 0.0005
	_leaf.add_child(bk)
	_leaf.visible = false
	_apply_open(0.0)


func _apply_open(v: float) -> void:
	_open = v
	_cover_r.rotation.z = lerpf(PI, 0.0, v)   # closed: the right half (cover + pages) lies over the left
	scale = Vector3.ONE * lerpf(0.97, 1.0, v)


func show_spread(first_page: int) -> void:
	var pages: Array = (book.get("pages", []) as Array).filter(func(pg): return not pg.has("requires_knowledge") or WorldState.knowledge.has(pg.requires_knowledge))
	var title: String = book.get("title", book_id)
	for side in 2:
		var i := first_page + side
		if i < pages.size():
			_views[side].show_page(style, title, pages[i], i, pages.size())
		else:
			_views[side].show_page(style, title, {"heading": "", "text": ""}, i, pages.size())
		_vps[side].render_target_update_mode = SubViewport.UPDATE_ONCE


func open_book(seconds := 0.9) -> void:
	show_spread(0)
	var tw := create_tween()
	tw.tween_method(_apply_open, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	opened.emit()


func turn_to(first_page: int, seconds := 0.9) -> void:
	# the leaf carries the current right page on its front; the next left page appears on its back
	turning = true
	_leaf_front.albedo_texture = ImageTexture.create_from_image(_vps[1].get_texture().get_image())
	show_spread(first_page)
	await get_tree().process_frame
	await get_tree().process_frame
	_leaf_back.albedo_texture = ImageTexture.create_from_image(_vps[0].get_texture().get_image())
	_leaf.visible = true
	_leaf.rotation.z = 0.0
	var tw := create_tween()
	tw.tween_property(_leaf, "rotation:z", PI, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_leaf.visible = false
	turning = false
	turned.emit()


func close_book(seconds := 0.7) -> void:
	var tw := create_tween()
	tw.tween_method(_apply_open, 1.0, 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished


## Centre of the open spread in world space (camera / head look target).
func centre() -> Vector3:
	return global_transform * Vector3(0, 0.02, 0)


## Points on the pages (world) for the eyes to follow while reading: page (0 left / 1 right), line 0..1.
func read_point(side: int, line: float) -> Vector3:
	var x := (-1.0 if side == 0 else 1.0) * W * 0.5
	return global_transform * Vector3(x, 0.012, lerpf(-H * 0.32, H * 0.32, line))


## Outer bottom corner of the right page (world): where her hand goes to turn it.
func turn_corner() -> Vector3:
	return global_transform * Vector3(W * 0.88, 0.02, H * 0.36)
