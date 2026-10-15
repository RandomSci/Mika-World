class_name Afterimage
extends RefCounted
## A ghost copy of a rig's skinned meshes in the pose of this instant, left in the world and fading out
## (fast dashes of human rivals; MeshInstance3D.bake_mesh_from_current_skeleton_pose on the CPU). Cheap enough
## for a handful per dash: the baked meshes are freed after `life` seconds.

const SHADER := preload("res://shaders/fx/afterimage.gdshader")
static var made := 0


static func spawn(rig: ClipRig, color: Color, life := 0.32) -> void:
	if rig == null or not is_instance_valid(rig) or rig.model == null or not rig.is_inside_tree():
		return
	spawn_model(rig.model, color, life)


## The same for any posed model (a mage's VRM avatar: the Fold Step leaves her shape behind as she steps across).
static func spawn_model(model: Node3D, color: Color, life := 0.32) -> void:
	if model == null or not is_instance_valid(model) or not model.is_inside_tree():
		return
	var root := model.get_tree().current_scene
	var holder := Node3D.new()
	holder.name = "Afterimage"
	root.add_child(holder)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("color", color)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var g := MeshInstance3D.new()
		g.mesh = m.bake_mesh_from_current_skeleton_pose() if m.skin != null or m.skeleton != NodePath("") else m.mesh
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(g)
		g.global_transform = m.global_transform
	made += 1
	var tw := holder.create_tween()
	tw.tween_method(func(k: float) -> void: mat.set_shader_parameter("fade", 1.0 - k), 0.0, 1.0, life)
	tw.tween_callback(holder.queue_free)
