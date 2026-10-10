class_name OpenBook
extends Node3D
## A physical open book that appears on a lectern / desk while it is read. Its two pages are real
## text: each page is a BookPageView rendered in a SubViewport and used as the page texture, so a
## camera close-up shows the actual words. Covers hinge open, a leaf turns over for page turns.
## Local frame: pages face +Y, the reader stands on the +Z side, the spine runs along Z at x = 0.

signal opened
signal turned

const W := 0.25      # one page width (m)
const H := 0.34      # page height (m)
const TEX := Vector2i(560, 760)

var book_id := ""
var book := {}
var style := "book"
var _views: Array[BookPageView] = []
var _vps: Array[SubViewport] = []
var _pages: Array[MeshInstance3D] = []
var _cover_l: Node3D
var _cover_r: Node3D
var _leaf: Node3D
var _open := 0.0


func build(p_book_id: String) -> void:
	book_id = p_book_id
	book = BookLibrary.book(book_id)
	style = book.get("style", "book")
	var cover_mat := StandardMaterial3D.new()
	cover_mat.albedo_color = Color(0.32, 0.12, 0.08) if style == "book" else Color(0.72, 0.62, 0.45)
	cover_mat.roughness = 0.7
	for side in [-1, 1]:
		var hinge := Node3D.new()
		add_child(hinge)
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(W + 0.015, 0.012, H + 0.02)
		board.mesh = bm
		board.material_override = cover_mat
		board.position = Vector3(side * (W + 0.015) * 0.5, -0.006, 0)
		hinge.add_child(board)
		if side < 0:
			_cover_l = hinge
		else:
			_cover_r = hinge
		# text page lying on the board
		var vp := SubViewport.new()
		vp.size = TEX
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var view := BookPageView.new()
		view.size = Vector2(TEX)
		view.scale_text = 1.0
		vp.add_child(view)
		var page := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(W, H)
		page.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_texture = vp.get_texture()
		m.emission_enabled = true
		m.emission_texture = vp.get_texture()
		m.emission_energy_multiplier = 0.35   # stays legible under dim lantern light
		m.roughness = 0.9
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		page.material_override = m
		page.position = Vector3(side * W * 0.5, 0.004, 0)
		page.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hinge.add_child(page)
		_views.append(view)
		_vps.append(vp)
		_pages.append(page)
	# the turning leaf (blank parchment both sides)
	_leaf = Node3D.new()
	add_child(_leaf)
	var leaf_mi := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(W, H)
	leaf_mi.mesh = lm
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.92, 0.86, 0.71)
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mi.material_override = leaf_mat
	leaf_mi.position = Vector3(W * 0.5, 0.006, 0)
	_leaf.add_child(leaf_mi)
	_leaf.visible = false
	_apply_open(0.0)


func _apply_open(v: float) -> void:
	_open = v
	# closed: right cover folded over the left (rotated -180 deg about the spine); open: both flat
	_cover_r.rotation.z = lerpf(PI, 0.0, v)
	_cover_l.rotation.z = lerpf(0.0, 0.0, v)
	scale = Vector3.ONE * lerpf(0.96, 1.0, v)


func show_spread(first_page: int) -> void:
	var pages: Array = book.get("pages", [])
	var title: String = book.get("title", book_id)
	for side in 2:
		var i := first_page + side
		if i < pages.size():
			_views[side].show_page(style, title, pages[i], i, pages.size())
			_pages[side].visible = true
		else:
			_views[side].show_page(style, title, {"heading": "", "text": ""}, i, pages.size())
		_vps[side].render_target_update_mode = SubViewport.UPDATE_ONCE


func open_book(seconds := 0.8) -> void:
	show_spread(0)
	var tw := create_tween()
	tw.tween_method(_apply_open, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	opened.emit()


func turn_to(first_page: int, seconds := 0.7) -> void:
	_leaf.visible = true
	_leaf.rotation.z = 0.0
	var tw := create_tween()
	tw.tween_property(_leaf, "rotation:z", PI * 0.5, seconds * 0.5).set_trans(Tween.TRANS_SINE)
	await tw.finished
	show_spread(first_page)   # contents swap while the leaf stands upright
	var tw2 := create_tween()
	tw2.tween_property(_leaf, "rotation:z", PI, seconds * 0.5).set_trans(Tween.TRANS_SINE)
	await tw2.finished
	_leaf.visible = false
	turned.emit()


func close_book(seconds := 0.6) -> void:
	var tw := create_tween()
	tw.tween_method(_apply_open, 1.0, 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished


## Centre of the open spread in world space (camera / head look target).
func centre() -> Vector3:
	return global_transform * Vector3(0, 0.02, 0)
