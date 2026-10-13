class_name ObjectHandler
extends Node
## Physical object handling for a WorldCharacter: right-arm two-bone IK (shoulder-elbow-wrist) blended on
## top of the animation, so her hand really travels to the object; a grasped object then follows her palm
## every frame (kept upright, or tilted when pouring) until it is placed back.
##   reach(point) -> grasp(obj) -> carry_to(point) -> tilt(angle) -> place(obj, home) -> release
## Every step is awaited, so the AI and tests get truthful completion and failure (out of reach, busy).

const REACH_MAX := 0.95          # metres from the shoulder the hand can comfortably reach
const PALM := Vector3(0.0, 0.07, 0.025)   # palm centre in the hand bone's local frame (VRM humanoid)

var c: WorldCharacter
var ik: TwoBoneIK3D
var target: Node3D
var pole: Node3D
var held: HoldableObject = null
var ik_left: TwoBoneIK3D            # second arm, used for two-handed poses (resting on a lectern)
var target_left: Node3D
var pole_left: Node3D
var tilt := 0.0                  # pour tilt (radians) applied to the held object
var busy := false
var _shoulder := -1


func attach(character: WorldCharacter) -> void:
	c = character
	target = Node3D.new()
	target.name = "HandTarget"
	c.add_child(target)
	pole = Node3D.new()
	pole.name = "ElbowPole"
	c.add_child(pole)
	ik = TwoBoneIK3D.new()
	ik.name = "RightArmIK"
	c.skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, "RightUpperArm")
	ik.set_middle_bone_name(0, "RightLowerArm")
	ik.set_end_bone_name(0, "RightHand")
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.influence = 0.0
	_shoulder = c.skeleton.find_bone("RightUpperArm")
	target_left = Node3D.new()
	target_left.name = "HandTargetL"
	c.add_child(target_left)
	pole_left = Node3D.new()
	pole_left.name = "ElbowPoleL"
	c.add_child(pole_left)
	ik_left = TwoBoneIK3D.new()
	ik_left.name = "LeftArmIK"
	c.skeleton.add_child(ik_left)
	ik_left.setting_count = 1
	ik_left.set_root_bone_name(0, "LeftUpperArm")
	ik_left.set_middle_bone_name(0, "LeftLowerArm")
	ik_left.set_end_bone_name(0, "LeftHand")
	ik_left.set_target_node(0, ik_left.get_path_to(target_left))
	ik_left.set_pole_node(0, ik_left.get_path_to(pole_left))
	ik_left.influence = 0.0


## After the character's avatar was swapped (transformation): the old IK nodes died with the old skeleton;
## build them again on the new one, reusing the same targets and poles.
func rebind() -> void:
	ik = _make_ik("RightArmIK", "Right", target, pole)
	ik_left = _make_ik("LeftArmIK", "Left", target_left, pole_left)
	_shoulder = c.skeleton.find_bone("RightUpperArm")


func _make_ik(n: String, side: String, t: Node3D, p: Node3D) -> TwoBoneIK3D:
	var k := TwoBoneIK3D.new()
	k.name = n
	c.skeleton.add_child(k)
	k.setting_count = 1
	k.set_root_bone_name(0, side + "UpperArm")
	k.set_middle_bone_name(0, side + "LowerArm")
	k.set_end_bone_name(0, side + "Hand")
	k.set_target_node(0, k.get_path_to(t))
	k.set_pole_node(0, k.get_path_to(p))
	k.influence = 0.0
	return k


func shoulder() -> Vector3:
	return (c.skeleton.global_transform * c.skeleton.get_bone_global_pose(_shoulder)).origin


func palm() -> Vector3:
	return c.right_hand.global_transform * PALM


func can_reach(p: Vector3) -> bool:
	return shoulder().distance_to(p) <= REACH_MAX


func _place_pole(p: Vector3) -> void:
	var fwd := -c.global_transform.basis.z
	var right := Vector3(-fwd.z, 0, fwd.x)
	pole.global_position = shoulder().lerp(p, 0.5) + right * 0.45 - fwd * 0.25 + Vector3(0, -0.45, 0)  # elbow down and out


## Move the hand (palm) to `p` over `seconds`, blending the IK in.
func reach(p: Vector3, seconds := 0.7) -> bool:
	if not can_reach(p):
		return false
	var start := palm() if ik.influence > 0.01 else c.right_hand.global_position
	target.global_position = start
	_place_pole(p)
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ik, "influence", 1.0, seconds * 0.6)
	# the IK end is the wrist; aim the wrist so the palm lands on the point
	tw.tween_method(func(v: Vector3): target.global_position = v; _place_pole(v), start, p - (palm() - c.right_hand.global_position) * 0.6, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	return true


func grasp(obj: HoldableObject) -> bool:
	if held != null or not can_reach(obj.grasp_point()):
		return false
	if not await reach(obj.grasp_point()):
		return false
	held = obj
	obj.on_grasped(c)
	if AudioDirector.instance:
		AudioDirector.instance.on_interaction(obj, "grasp", c)
	return true


## Carry the held object so its base ends up over `p` (e.g. above the bowl).
func carry_to(p: Vector3, seconds := 0.8) -> bool:
	if held == null:
		return false
	var hand_goal := p + Vector3(0, held.grasp_height, 0)
	if not can_reach(hand_goal):
		return false
	return await reach(hand_goal, seconds)


func set_tilt(angle: float, seconds := 0.6) -> void:
	var tw := c.create_tween()
	tw.tween_property(self, "tilt", angle, seconds).set_trans(Tween.TRANS_SINE)
	await tw.finished


## Put the held object down at `xf` (its home slot or a new place) and let go.
func place(xf: Transform3D, seconds := 0.8) -> bool:
	if held == null:
		return false
	var obj := held
	if not await reach(xf.origin + Vector3(0, obj.grasp_height, 0), seconds):
		return false
	held = null
	tilt = 0.0
	obj.on_placed(xf)
	if AudioDirector.instance:
		AudioDirector.instance.on_interaction(obj, "place", c)
	return true


## Rest both hands on a surface (e.g. the lectern board beside the book), elbows down and out.
func rest_hands(left: Vector3, right: Vector3, seconds := 0.8) -> void:
	var fwd := -c.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var side := Vector3(-fwd.z, 0, fwd.x)
	target.global_position = c.right_hand.global_position
	target_left.global_position = c.left_hand.global_position
	pole.global_position = right + side * 0.35 - fwd * 0.35 + Vector3(0, -0.4, 0)
	pole_left.global_position = left - side * 0.35 - fwd * 0.35 + Vector3(0, -0.4, 0)
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ik, "influence", 0.85, seconds)
	tw.tween_property(ik_left, "influence", 0.85, seconds)
	tw.tween_property(target, "global_position", right, seconds).set_trans(Tween.TRANS_SINE)
	tw.tween_property(target_left, "global_position", left, seconds).set_trans(Tween.TRANS_SINE)
	await tw.finished


## Move only the right hand (page turns) while the left stays where it is.
func move_right(p: Vector3, seconds := 0.45) -> void:
	var tw := c.create_tween()
	tw.tween_property(target, "global_position", p, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func release_hands(seconds := 0.6) -> void:
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ik, "influence", 0.0, seconds)
	tw.tween_property(ik_left, "influence", 0.0, seconds)
	await tw.finished


## Bring the arm back to the animation (no IK).
func relax(seconds := 0.5) -> void:
	var tw := c.create_tween()
	tw.tween_property(ik, "influence", 0.0, seconds)
	await tw.finished


func _process(_delta: float) -> void:
	if held == null or c == null:
		return
	var fwd := -c.global_transform.basis.z
	fwd.y = 0
	var up_basis := Basis.looking_at(fwd.normalized(), Vector3.UP)
	var right := up_basis.x
	var b := Basis(right, -tilt) * up_basis if absf(tilt) > 0.001 else up_basis
	held.global_transform = Transform3D(b, palm() - b * Vector3(0, held.grasp_height, 0))
