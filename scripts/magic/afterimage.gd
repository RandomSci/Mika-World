class_name Afterimage
extends RefCounted
## A ghost copy of a rig's skinned meshes in the pose of this instant, left in the world and fading out
## (fast dashes of human rivals, a mage's Fold Step, every dash and dodge of a duel). The ghost is skinned on the GPU:
## a bare copy of her skeleton frozen in this instant's pose, carrying her own meshes and skins (shared, nothing
## copied). Baking the meshes on the CPU (bake_mesh_from_current_skeleton_pose, still there with --cpu-ghosts) cost
## 60-145 ms per ghost with the girls' 30-40k-vertex hair and skirts: four ghosts per dash stalled every fight.

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
	fill(holder, model, mat)
	made += 1
	var tw := holder.create_tween()
	tw.tween_method(func(k: float) -> void: mat.set_shader_parameter("fade", 1.0 - k), 0.0, 1.0, life)
	tw.tween_callback(holder.queue_free)


## The ghost's meshes under `holder`: each skinned mesh on a frozen copy of its skeleton (GPU skinning), the others
## as they are. `skip` (mesh -> bool) leaves some out (the fight's ghosts drop the face: its eyes went black).
static func fill(holder: Node3D, model: Node3D, mat: Material, skip := Callable()) -> void:
	var frozen := {}                                     # source skeleton -> its frozen copy
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree() or (skip.is_valid() and bool(skip.call(m))):
			continue
		var g := MeshInstance3D.new()
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sk := m.get_node_or_null(m.skeleton) as Skeleton3D if m.skin != null and m.skeleton != NodePath("") else null
		if sk != null and RenderProfile.options.has("cpu-ghosts"):
			g.mesh = m.bake_mesh_from_current_skeleton_pose()
			holder.add_child(g)
			g.global_transform = m.global_transform
			continue
		if sk == null:
			g.mesh = m.mesh
			holder.add_child(g)
			g.global_transform = m.global_transform
			continue
		if not frozen.has(sk):
			frozen[sk] = _freeze(sk, holder)
		var fz: Skeleton3D = frozen[sk]
		g.mesh = m.mesh
		g.skin = m.skin
		fz.add_child(g)
		g.global_transform = m.global_transform
		g.skeleton = g.get_path_to(fz)


## A bare skeleton (no modifiers, no animation) in `sk`'s pose of this instant.
static func _freeze(sk: Skeleton3D, holder: Node3D) -> Skeleton3D:
	var fz := Skeleton3D.new()
	for bi in sk.get_bone_count():
		fz.add_bone(sk.get_bone_name(bi))
	for bi in sk.get_bone_count():
		fz.set_bone_parent(bi, sk.get_bone_parent(bi))
		fz.set_bone_rest(bi, sk.get_bone_rest(bi))
		fz.set_bone_pose_position(bi, sk.get_bone_pose_position(bi))
		fz.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi))
		fz.set_bone_pose_scale(bi, sk.get_bone_pose_scale(bi))
	holder.add_child(fz)
	fz.global_transform = sk.global_transform
	return fz
