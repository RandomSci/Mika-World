class_name FightBodyPost
extends SkeletonModifier3D
## Combat v3, pose stage 3 (PosePipeline "FightBodyPost", after the limb IKs): fists / open hands, the wrists turned
## so the knuckles lead, the feet flat on the ground or pointed in a kick (MeleeFighter.post).

var fighter: Object


func _process_modification() -> void:
	if fighter:
		fighter.post(get_skeleton())
