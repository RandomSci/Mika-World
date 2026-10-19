class_name FightBody
extends SkeletonModifier3D
## Combat v3, pose stage 1 (PosePipeline "FightBody", after the decks): her hips, spine, shoulders and head from the
## procedural fight rig (MeleeFighter.apply), and the targets of her four limb IKs (the TwoBoneIK3D "FightIK_*" nodes
## right after it).

var fighter: Object


func _process_modification() -> void:
	if fighter:
		fighter.apply(get_skeleton())
