class_name PhoenixGaze
extends SkeletonModifier3D
## Runs after the clip: eases Oriel's neck and head toward what she regards (shared over three bones so the
## S-curve stays a curve), opens the lower beak for her speech (VoiceService envelope) and her call, and
## keeps the eyes with the head. Works for both rigs: `chain` lists the bones from the base to the head.

var chain: Array[String] = ["Neck2", "Neck3", "Head"]
var beak_bone := "Beak_Lower"
var target := Vector3.ZERO           # world space
var weight := 0.0                    # 0 = the clip alone
var max_angle := deg_to_rad(70.0)
var mouth := 0.0                     # 0..1 beak opening added on top of the clip
var _w := 0.0


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_w = lerpf(_w, weight, 0.12)
	if _w > 0.002:
		var local_target := sk.global_transform.affine_inverse() * target
		var share := 1.0 / maxf(chain.size(), 1)
		for bn in chain:
			var idx := sk.find_bone(bn)
			if idx < 0:
				continue
			var gp := sk.get_bone_global_pose(idx)
			var fwd := (gp.basis * Vector3(0, 1, 0)).normalized()
			var want := (local_target - gp.origin).normalized()
			if want.length_squared() < 0.5:
				continue
			var q := Quaternion(fwd, want)
			var ang := minf(q.get_angle(), max_angle * share)
			if q.get_angle() < 1e-4:
				continue
			var axis := q.get_axis().normalized()
			var step := Quaternion(axis, ang * share * 1.8 * _w)
			var new_basis := Basis(step) * gp.basis
			var parent := sk.get_bone_parent(idx)
			var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var local_basis := pb.inverse() * new_basis
			sk.set_bone_pose_rotation(idx, local_basis.get_rotation_quaternion())
			sk.force_update_bone_child_transform(idx)
	if mouth > 0.001:
		var bi := sk.find_bone(beak_bone)
		if bi >= 0:
			var r := sk.get_bone_pose_rotation(bi)
			sk.set_bone_pose_rotation(bi, r * Quaternion(Vector3(1, 0, 0), -deg_to_rad(26.0) * clampf(mouth, 0.0, 1.0)))
			sk.force_update_bone_child_transform(bi)
