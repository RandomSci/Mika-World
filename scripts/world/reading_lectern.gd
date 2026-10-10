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
	return Transform3D(b, Vector3(0, SURFACE_H, 0) + b * Vector3(0, 0.035, -0.02))


## Interaction marker (local): where her root stops, facing the board.
func stand_point() -> Vector3:
	return Vector3(0, 0, READ_DISTANCE)


## Places for her hands to rest on the board (local), near the book's lower corners.
func hand_rests() -> Array:
	var b := Basis(Vector3.RIGHT, TILT)
	return [Vector3(0, SURFACE_H, 0) + b * Vector3(-0.2, 0.06, 0.17), Vector3(0, SURFACE_H, 0) + b * Vector3(0.2, 0.06, 0.17)]
