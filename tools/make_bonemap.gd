extends SceneTree
# Builds res://assets/animations/mixamo_bonemap.tres mapping Mixamo bones -> SkeletonProfileHumanoid.
func _init():
	var m := {
		"Hips":"Hips","Spine":"Spine","Chest":"Spine1","UpperChest":"Spine2","Neck":"Neck","Head":"Head",
		"LeftShoulder":"LeftShoulder","LeftUpperArm":"LeftArm","LeftLowerArm":"LeftForeArm","LeftHand":"LeftHand",
		"RightShoulder":"RightShoulder","RightUpperArm":"RightArm","RightLowerArm":"RightForeArm","RightHand":"RightHand",
		"LeftUpperLeg":"LeftUpLeg","LeftLowerLeg":"LeftLeg","LeftFoot":"LeftFoot","LeftToes":"LeftToeBase",
		"RightUpperLeg":"RightUpLeg","RightLowerLeg":"RightLeg","RightFoot":"RightFoot","RightToes":"RightToeBase",
	}
	for side in ["Left", "Right"]:
		m[side + "ThumbMetacarpal"] = side + "HandThumb1"
		m[side + "ThumbProximal"] = side + "HandThumb2"
		m[side + "ThumbDistal"] = side + "HandThumb3"
		for f in [["Index","Index"],["Middle","Middle"],["Ring","Ring"],["Little","Pinky"]]:
			m[side + f[0] + "Proximal"] = side + "Hand" + f[1] + "1"
			m[side + f[0] + "Intermediate"] = side + "Hand" + f[1] + "2"
			m[side + f[0] + "Distal"] = side + "Hand" + f[1] + "3"
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	for k in m: bm.set_skeleton_bone_name(k, "mixamorig_" + m[k])
	print(ResourceSaver.save(bm, "res://assets/animations/mixamo_bonemap.tres"))
	quit()
