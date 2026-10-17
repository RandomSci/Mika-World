class_name ReadingLectern
extends Node3D
## A reading lectern sized for Mika (measured: eyes 1.42 m, shoulders 1.25 m, relaxed forearm reach
## ~0.43 m): reading surface centre 1.02 m above the floor, tilted 25 degrees toward the reader, a lip that
## holds the book, a turned column, brass caps and a faint engraved sigil on the front panel.
## Local frame: the reader stands on +Z and faces -Z. Use book_transform() for the open book and
## stand_point() for the interaction marker (where she stops before reading).

const SURFACE_H := 1.02
const TILT := deg_to_rad(25.0)
const BOARD := Vector2(0.62, 0.46)     # width (x), depth (z)
const READ_DISTANCE := 0.52            # board centre -> reader's root (her chest is ~0.12 m ahead of it)

var style := "wood"                    # wood | stone


func build(p_style := "wood", collide := true) -> ReadingLectern:
	style = p_style
	var wood := Kit.uvmat("dark_wooden_planks", "1k", Vector2(0.6, 0.6))
	var stone_m: Material = Kit.tri("monastery_stone_floor", "1k", 0.6, 0.15)
	var body_mat: Material = wood if style == "wood" else stone_m
	var brass := Kit.metal(Color(0.72, 0.55, 0.3), 0.35)
	# base: a stepped plinth (stone) or a carved foot (wood)
	if style == "stone":
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.62, 0.12, 0.5), 0.03), stone_m, Kit.xf(Vector3(0, 0.06, 0)))
		Kit.mesh_node(self, Kit.box_mesh(Vector3(0.48, 0.08, 0.38), 0.02), stone_m, Kit.xf(Vector3(0, 0.16, 0)))
	else:
		Kit.mesh_node(self, Kit.lathe([Vector2(0.0, 0.0), Vector2(0.26, 0.0), Vector2(0.27, 0.03), Vector2(0.2, 0.08), Vector2(0.11, 0.12), Vector2(0.0, 0.12)], 16, true, false), body_mat, Kit.xf(Vector3.ZERO))
	# turned column
	var col := Kit.lathe([Vector2(0.075, 0.0), Vector2(0.06, 0.05), Vector2(0.05, 0.2), Vector2(0.065, 0.32), Vector2(0.045, 0.5),
		Vector2(0.045, 0.64), Vector2(0.06, 0.7), Vector2(0.075, 0.74)], 14, true, false)
	Kit.mesh_node(self, col, body_mat, Kit.xf(Vector3(0, 0.12 if style == "wood" else 0.2, 0)))
	# tilted reading board with a front lip and brass corner caps
	var top := Node3D.new()
	top.name = "Board"
	top.position = Vector3(0, SURFACE_H - 0.02, 0)
	top.rotation.x = TILT
	add_child(top)
	Kit.mesh_node(top, Kit.box_mesh(Vector3(BOARD.x, 0.035, BOARD.y), 0.008), body_mat, Kit.xf(Vector3.ZERO))
	Kit.mesh_node(top, Kit.box_mesh(Vector3(BOARD.x * 0.96, 0.05, 0.025), 0.005), body_mat, Kit.xf(Vector3(0, 0.035, BOARD.y * 0.5 - 0.0125)))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Kit.mesh_node(top, Kit.box_mesh(Vector3(0.05, 0.04, 0.05), 0.006), brass, Kit.xf(Vector3(sx * (BOARD.x * 0.5 - 0.02), 0.002, sz * (BOARD.y * 0.5 - 0.02))), false)
	# engraved sigil on the front panel under the board (faint, readable at close range)
	var panel := Kit.mesh_node(self, Kit.box_mesh(Vector3(0.34, 0.24, 0.03), 0.006), body_mat, Kit.xf(Vector3(0, SURFACE_H - 0.3, 0.07)))
	panel.rotation.x = TILT * 0.4
	var sig := FX.quad("res://shaders/magic/sigil.gdshader", 0.2, {"color": Color(0.85, 0.7, 0.4), "sides": 7, "intensity": 0.35, "draw_progress": 1.0, "spin": 0.0, "seed": 3.0}, false)
	panel.add_child(sig)
	sig.position = Vector3(0, 0, 0.017)
	if collide:
		Kit.static_box(self, Vector3(0.5, SURFACE_H, 0.4), Kit.xf(Vector3(0, SURFACE_H * 0.5, 0)))
	return self


## Where the open book lies (local): on the board, pages facing up, reader on +Z.
func book_transform() -> Transform3D:
	var b := Basis(Vector3.RIGHT, TILT)
	# the open book's covers sit 0.024 below its origin; the board top is ~0.0025 below SURFACE_H
	return Transform3D(b, Vector3(0, SURFACE_H, 0) + b * Vector3(0, 0.022, 0.035))


## Interaction marker (local): where her root stops, facing the board.
func stand_point() -> Vector3:
	return Vector3(0, 0, READ_DISTANCE)


## Places for her hands to rest on the board (local), near the book's lower corners.
func hand_rests() -> Array:
	var b := Basis(Vector3.RIGHT, TILT)
	return [Vector3(0, SURFACE_H, 0) + b * Vector3(-0.2, 0.06, 0.17), Vector3(0, SURFACE_H, 0) + b * Vector3(0.2, 0.06, 0.17)]


## A closed book (or rolled scroll) resting where the open book will appear; hidden while it is read.
static func closed_prop(style_of_book: String) -> Node3D:
	var n := Node3D.new()
	if style_of_book == "scroll":
		var paper := StandardMaterial3D.new()
		paper.albedo_color = Color(0.86, 0.78, 0.6)
		paper.roughness = 0.9
		var roll := Kit.mesh_node(n, Kit.lathe([Vector2(0.032, -0.2), Vector2(0.032, 0.2)], 12, true, true), paper, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.008, 0)), false)
		roll.name = "Roll"
		for sx in [-1.0, 1.0]:
			Kit.mesh_node(n, Kit.lathe([Vector2(0.012, 0.0), Vector2(0.012, 0.035), Vector2(0.02, 0.045)], 8, true, false),
				Kit.uvmat("dark_wooden_planks"), Transform3D(Basis(Vector3.FORWARD, -sx * PI * 0.5), Vector3(sx * 0.2, 0.008, 0)), false)
		return n
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.33, 0.12, 0.08)
	leather.roughness = 0.62
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.86, 0.8, 0.66)
	edge.roughness = 0.9
	var thick := OpenBook.BLOCK * 2.0 + 0.016
	Kit.mesh_node(n, Kit.box_mesh(Vector3(OpenBook.W + 0.014, thick, OpenBook.H + 0.02), 0.004), leather, Kit.xf(Vector3(-OpenBook.W * 0.5, 0, 0)), false)
	Kit.mesh_node(n, Kit.box_mesh(Vector3(OpenBook.W - 0.004, thick - 0.012, OpenBook.H - 0.004), 0.002), edge, Kit.xf(Vector3(-OpenBook.W * 0.5 - 0.01, 0, 0)), false)
	var brass := Kit.metal(Color(0.75, 0.58, 0.3), 0.3)
	for sz in [-1.0, 1.0]:
		Kit.mesh_node(n, Kit.box_mesh(Vector3(0.028, thick + 0.004, 0.028), 0.002), brass, Kit.xf(Vector3(-OpenBook.W - 0.002, 0, sz * (OpenBook.H * 0.5 - 0.004))), false)
	var emb := FX.quad("res://shaders/magic/sigil.gdshader", 0.15, {"color": Color(0.85, 0.66, 0.32), "sides": 7, "intensity": 0.45, "draw_progress": 1.0, "spin": 0.0, "seed": 5.0}, true)
	emb.position = Vector3(-OpenBook.W * 0.5, thick * 0.5 + 0.001, 0)
	n.add_child(emb)
	return n


## Put a lectern into an area and point an interactable's reading setup at it.
## pos: floor point (parent-local); yaw: the reader stands on the lectern's local +Z, i.e. at
## pos + Basis(UP, yaw) * (0, 0, READ_DISTANCE), facing back toward it.
static func install(parent: Node3D, it: Interactable, pos: Vector3, yaw: float, p_style := "wood") -> ReadingLectern:
	var l := ReadingLectern.new()
	l.name = "Lectern_" + it.id
	l.position = pos
	l.rotation.y = yaw
	parent.add_child(l)
	l.build(p_style)
	_point_interactable(parent, it, l.transform * l.book_transform(), l.transform * l.stand_point())
	return l


## A slanted reading stand that sits on a desk top (surface point in parent space, reader on the stand's +Z).
## Raises and tilts the book toward a standing reader instead of leaving it flat at hip height.
static func install_desk_stand(parent: Node3D, it: Interactable, surface: Vector3, yaw: float) -> Node3D:
	var root := Node3D.new()
	root.name = "DeskStand_" + it.id
	root.position = surface
	root.rotation.y = yaw
	parent.add_child(root)
	var wood := Kit.uvmat("dark_wooden_planks", "1k", Vector2(0.6, 0.6))
	var tilt := deg_to_rad(28.0)
	var board := Node3D.new()
	board.position = Vector3(0, 0.11, 0)
	board.rotation.x = tilt
	root.add_child(board)
	Kit.mesh_node(board, Kit.box_mesh(Vector3(0.58, 0.025, 0.4), 0.006), wood, Kit.xf(Vector3.ZERO))
	Kit.mesh_node(board, Kit.box_mesh(Vector3(0.56, 0.04, 0.02), 0.004), wood, Kit.xf(Vector3(0, 0.025, 0.19)), false)
	for sx in [-0.24, 0.24]:
		var leg := Kit.mesh_node(root, Kit.box_mesh(Vector3(0.03, 0.2, 0.3), 0.004), wood, Kit.xf(Vector3(sx, 0.08, -0.04)), false)
		leg.rotation.x = tilt * 0.5
	var b := Basis(Vector3.RIGHT, tilt)
	var book_local := Transform3D(b, Vector3(0, 0.11, 0) + b * Vector3(0, 0.037, 0.0))
	var reader_local := Vector3(0, -surface.y, 0.75)
	_point_interactable(parent, it, root.transform * book_local, root.transform * reader_local)
	return root


static func _point_interactable(parent: Node3D, it: Interactable, book_xf: Transform3D, stand: Vector3) -> void:
	for bp in it.book_props:
		if is_instance_valid(bp):
			bp.queue_free()
	var prop := closed_prop(BookLibrary.book(it.book_id).get("style", "book"))
	prop.transform = book_xf
	parent.add_child(prop)
	it.book_props = [prop]
	it.book_xf = book_xf
	it.stand_point = stand
	it.face_point = book_xf.origin
