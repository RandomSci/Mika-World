class_name HoldableObject
extends Node3D
## A small object Mika can physically handle. Declares what it supports, where it lives (home slot),
## how to hold it (grasp height above its base) and what it contains. State is reported verbatim.

var id := ""
var label := ""
var supports := ["inspect", "pick_up", "place", "return"]   # + "pour", "use", "combine", "store", "read"
var grasp_height := 0.12          # palm height above the object's base
var contents := ""                # e.g. "moonwater"; "" = empty or not a vessel
var amount := 1.0                 # vessel fill 0..1
var description := ""
var home := Transform3D.IDENTITY  # global home slot
var holder: Node = null
var state := "in place"


func setup(p_id: String, p_label: String, p_desc: String, p_contents := "", p_supports: Array = []) -> void:
	id = p_id
	label = p_label
	description = p_desc
	contents = p_contents
	if not p_supports.is_empty():
		supports = p_supports
	name = "Holdable_" + id


func remember_home() -> void:
	home = global_transform


func grasp_point() -> Vector3:
	return global_position + Vector3(0, grasp_height, 0)


func on_grasped(by: Node) -> void:
	holder = by
	state = "held"


func on_placed(xf: Transform3D) -> void:
	holder = null
	global_transform = xf
	state = "in place" if xf.origin.distance_to(home.origin) < 0.05 else "moved"


func describe() -> Dictionary:
	return {"id": id, "label": label, "description": description, "supports": supports, "contents": contents,
		"amount": snappedf(amount, 0.01), "state": state}
