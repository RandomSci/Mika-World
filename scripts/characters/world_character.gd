class_name WorldCharacter
extends CharacterBody3D
## A humanoid VRM character living in the world. Input-agnostic: a PlayerController,
## the AI ActionBridge, or (later) a companion brain all drive it through the same API:
##   set_move_input(dir, run) · navigate_to(pos) · look_at_point(pos) · cast_spell(id) · stop_action()
## Every action reports completion via `action_finished(action, ok, detail)`.

signal action_started(action: String, detail: Dictionary)
signal action_finished(action: String, ok: bool, detail: String)
signal cast_event(event: String)

const MIXAMO_DIR := "res://assets/animations/mixamo/"
## name -> [file, loop, in_place]
const CLIPS := {
	"idle": ["standing_idle.fbx", true, true],
	"walk": ["walking.fbx", true, true],
	"run": ["run_forward.fbx", true, true],
	"jog": ["jog_forward.fbx", true, true],
	"look_around": ["look_around.fbx", false, true],
	"wave": ["waving.fbx", false, true],
	"prepare_and_cast": ["prepare_and_cast.fbx", false, true],
	"spell_casting": ["spell_casting.fbx", false, true],
	"wide_arm_spell": ["wide_arm_spell_casting.fbx", false, true],
	"magic_attack_2h": ["standing_2h_magic_attack_01.fbx", false, true],
	"magic_attack_1h": ["standing_1h_magic_attack_03.fbx", false, true],
	"sit": ["sitting_idle.fbx", false, true],
	"sit_loop": ["sitting_idle.fbx", true, true],
	# Milestone I: transitions, handling, leisure, dances (all retargeted through mixamo_bonemap)
	"stand_to_sit": ["stand_to_sit.fbx", false, true],
	"sit_to_stand": ["sit_to_stand.fbx", false, true],
	"lie_down": ["lying_down.fbx", false, true],
	"pick_floor": ["picking_up_floor.fbx", false, true],
	"pick_chest": ["picking_up_object_chest_level.fbx", false, true],
	"put_down": ["putting_down.fbx", false, true],
	"pointing": ["pointing.fbx", false, true],
	"stretch_arms": ["arm_stretching.fbx", false, true],
	"stretch_neck": ["neck_stretching.fbx", false, true],
	"waking": ["waking.fbx", false, true],
	"waving": ["waving.fbx", false, true],
	"dance_step": ["step_hip_hop_dance.fbx", true, true],
	"dance_snake": ["snake_hip_hop_dance.fbx", true, true],
	"dance_booty": ["booty_hip_hop_dance.fbx", true, true],
	"dance_belly": ["belly_dance.fbx", true, true],
	# Milestone J combat set: Quaternius Universal Animation Library (CC0), retargeted via ual_bonemap
	"combat_idle": ["ual:Spell_Simple_Idle", true, true],
	"cast_quick_enter": ["ual:Spell_Simple_Enter", false, true],
	"cast_quick": ["ual:Spell_Simple_Shoot", false, true],
	"cast_quick_exit": ["ual:Spell_Simple_Exit", false, true],
	"dodge_dash": ["ual:Sprint", true, true],     # an upright evasive dash (a roll in a skirt is not stream-safe)
	"hit_chest": ["ual:Hit_Chest", false, true],
	"hit_head": ["ual:Hit_Head", false, true],
	"hit_knockback": ["ual:Hit_Knockback", false, true],
	"brace": ["ual:Sword_Block", false, true],
	"victory_nod": ["ual:Yes", false, true],
}
const UAL_PACK := "res://assets/animations/ual/ual_combat.glb"

@export var character_id := "mika"
@export var display_name := "Mika"
@export var avatar_path := "res://assets/characters/mika/Mika.vrm"
@export var walk_speed := 1.45
@export var run_speed := 4.1
@export var turn_speed := 10.0

var avatar: Node3D
var skeleton: Skeleton3D
var body_player: AnimationPlayer
var anim_tree: AnimationTree
var left_hand: BoneAttachment3D
var right_hand: BoneAttachment3D
var chest: BoneAttachment3D
var nav_agent: NavigationAgent3D
var world: Node  # the active area (magic bounce / rune floor), set by the streaming manager
var sword: SwordLayer  # optional magical-sword layer
var pose_adjust: PoseAdjust  # post-animation corrections (seated knees)
var head_look: LookAtModifier3D  # eases her head toward what she reads / inspects
var eye_looks: Array[LookAtModifier3D] = []
var handler: ObjectHandler       # right-arm IK + holding objects
var _head_target: Node3D
var seated := false

var current_action := "idle"
var last_rejection := ""  # reason the most recent action request was refused outright
var action_detail := {}
var casting := false
var _move_input := Vector3.ZERO
var _run := false
var _look_target = null
var _nav_active := false
var _nav_stuck_time := 0.0
var _nav_last_pos := Vector3.ZERO
var _nav_goal := Vector3.ZERO
var _action_deadline := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _expr := {}            # expression name -> Array[[MeshInstance3D, blend_idx, value]]
var _expr_weight := {}     # expression name -> current weight
var _expr_target := {}
var _blink_timer := 2.0
var _blink_phase := -1.0
var _speed_smoothed := 0.0
var face: FaceController        # Milestone K: component-level expressive face (null = legacy presets)
var head_posture: HeadPosture
var _dash := {}            # active dodge: {dir, dist, t, dur, from}
var combat_stance := false
var pace := 1.0            # walking-with-someone speed factor (FollowCompanion); feet follow via the loco time scale
var last_hit := {}         # most recent hit taken: {t, heavy, clip}


func _ready() -> void:
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(46)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.55
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.775
	add_child(cs)
	add_to_group("avoid")              # other walkers steer around her
	set_collision_mask_value(2, true)  # creatures' bodies (layer 2) are solid for her
	set_collision_mask_value(3, true)  # vegetation and boulders (layer 3; carved out of the navmesh separately)
	_build_rig()
	handler = ObjectHandler.new()
	handler.name = "ObjectHandler"
	handler.process_priority = 100   # after animation + IK, so held objects follow the final hand pose
	add_child(handler)
	handler.attach(self)

	nav_agent = NavigationAgent3D.new()
	NavQuery.configure_agent(nav_agent)   # big forest navmeshes exceed the default 4096-polygon search limit
	nav_agent.path_desired_distance = 1.0  # > navmesh voxel float (up to ~0.6 m above ground with 0.25 m cells)
	nav_agent.target_desired_distance = 0.7
	nav_agent.radius = 0.35
	nav_agent.height = 1.6
	add_child(nav_agent)


## Everything that belongs to one avatar (model, skeleton, animation tree, expressions, look-at, hand
## attachments). Built once in _ready and again by swap_avatar(); the body, navigation, voice and planner
## state stay the same character.
func _build_rig(scene: PackedScene = null, instance: Node3D = null) -> void:
	avatar = instance if instance else (scene if scene else load(avatar_path)).instantiate()
	avatar.transform = Transform3D.IDENTITY
	_extend_skirt_colliders()
	avatar.name = "Avatar"
	avatar.rotation.y = PI  # VRM 1.0 faces +Z; Godot forward is -Z
	add_child(avatar)
	skeleton = avatar.find_child("GeneralSkeleton", true, false)
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_fix_vrm1_mtoon_shading()
	_lab_hair_fix()
	_light_balance = Vector2(-1, -1)          # a new avatar's materials need the balance again
	_setup_animation()
	_setup_expressions()
	pose_adjust = PoseAdjust.new()
	pose_adjust.name = "PoseAdjust"
	pose_adjust.influence = 0.0
	skeleton.add_child(pose_adjust)
	if _head_target == null:
		_head_target = Node3D.new()
		_head_target.name = "HeadLookTarget"
		add_child(_head_target)
	eye_looks.clear()
	head_look = LookAtModifier3D.new()
	head_look.name = "HeadLook"
	head_look.bone_name = "Head"
	head_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	head_look.primary_rotation_axis = Vector3.AXIS_Y
	head_look.use_secondary_rotation = true
	head_look.use_angle_limitation = true
	head_look.symmetry_limitation = true
	head_look.primary_limit_angle = deg_to_rad(110.0)
	head_look.secondary_limit_angle = deg_to_rad(70.0)
	head_look.duration = 0.45
	head_look.transition_type = Tween.TRANS_SINE
	head_look.ease_type = Tween.EASE_IN_OUT
	head_look.influence = 0.0
	skeleton.add_child(head_look)
	head_look.target_node = head_look.get_path_to(_head_target)
	# eyes follow within a small range (after the head), so reading looks like reading
	for eb in ["LeftEye", "RightEye"]:
		if skeleton.find_bone(eb) == -1:
			continue
		var el := LookAtModifier3D.new()
		el.name = "EyeLook_" + eb
		el.bone_name = eb
		el.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
		el.primary_rotation_axis = Vector3.AXIS_Y
		el.use_secondary_rotation = true
		el.use_angle_limitation = true
		el.symmetry_limitation = true
		el.primary_limit_angle = deg_to_rad(24.0)
		el.secondary_limit_angle = deg_to_rad(18.0)
		el.duration = 0.18
		el.influence = 0.0
		skeleton.add_child(el)
		el.target_node = el.get_path_to(_head_target)
		eye_looks.append(el)
	if head_posture and is_instance_valid(head_posture):
		skeleton.move_child(head_posture, -1)      # emotional tilt applies on top of the look-at
	left_hand = _attach("LeftHand")
	right_hand = _attach("RightHand")
	chest = _attach("UpperChest")


signal avatar_swapped(path: String)

## Change her appearance to another VRM of the same humanoid (a transformation form, or back to base).
## Refused while casting or holding something. `scene` may be a preloaded PackedScene (no hitch).
func swap_avatar(path: String, scene: PackedScene = null, instance: Node3D = null) -> bool:
	if casting or (handler and handler.held != null):
		return false
	if scene == null and instance == null:
		if not ResourceLoader.exists(path):
			push_warning("[character] %s: no avatar at %s" % [character_id, path])
			return false
		scene = load(path)
	var old := avatar
	old.name = "AvatarOld"
	remove_child(old)
	old.queue_free()
	_expr.clear()
	_expr_weight.clear()
	_expr_target.clear()
	avatar_path = path
	_build_rig(scene, instance)
	if handler:
		handler.rebind()
	if sword:
		var had := sword
		sword = SwordLayer.attach(self)
		had.queue_free()
	avatar_swapped.emit(path)
	print("[character] %s: avatar -> %s" % [character_id, path.get_file()])
	return true


## VRM 1.0 → MToon 0.x shading conversion (fixes the "black face" in point-lit interiors).
## godot-vrm copies VRM1 shadingShiftFactor/shadingToonyFactor straight into the 0.x shader's
## _ShadeShift/_ShadeToony, but the conventions differ:
##   VRM1:  s = N·L + shift;   lit = linearstep(-1 + toony, 1 - toony, s)   (positive shift = MORE lit)
##   MToon0: lit = clamp((N·L - S0) / ((1 - S0) * (1 - T0)))                  (positive shift = MORE shaded)
## Matching the ramp centre and width gives  S0 = -shift - (1 - toony),  T0 = 1 - 2(1 - toony) / (1 - S0).
## Mika's face (0.71, 0.91) becomes (-0.80, 0.90): lit almost everywhere, as VRoid intends.
func _fix_vrm1_mtoon_shading() -> void:
	var meta = avatar.get("vrm_meta")
	var spec: String = str(meta.get("spec_version")) if meta else ""
	if not spec.begins_with("1") or RenderProfile.options.has("mtoon-legacy"):
		return
	var fixed := 0
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			while mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				if not sm.has_meta("vrm1_shading_converted") and sm.get_shader_parameter("_ShadeShift") != null:
					var s1: float = sm.get_shader_parameter("_ShadeShift")
					var t1: float = sm.get_shader_parameter("_ShadeToony")
					var s0 := clampf(-s1 - (1.0 - t1), -1.0, 1.0)
					var t0 := clampf(1.0 - 2.0 * (1.0 - t1) / maxf(1.0 - s0, 0.001), 0.0, 1.0)
					sm.set_shader_parameter("_ShadeShift", s0)
					sm.set_shader_parameter("_ShadeToony", t0)
					sm.set_shader_parameter("_Vrm1Lighting", 1.0)
					sm.set_meta("vrm1_shading_converted", [s1, t1, s0, t0])
					fixed += 1
				mat = sm.next_pass
	print("[character] %s: converted VRM1 MToon shading on %d materials" % [character_id, fixed])


## Character Lab hair correction, applied at render time (the VRM files are untouched; several are marked
## modification-prohibited): VRoid exported the hair with a strong coloured EMISSIVE and a pure-white shade colour,
## so it renders flat, tinted and can never show form. Replace with a small neutral lift and a real shade tone
## (the lab's values: emissive 0.14, shade a cool 0.78-0.88 tint of the hair's own colour).
func _lab_hair_fix() -> void:
	var n := 0
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			if mat == null or not ("_HAIR" in mat.resource_name):
				continue
			while mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				if sm.get_shader_parameter("_EmissionColor") != null:
					sm.set_shader_parameter("_EmissionColor", Color(0.14, 0.14, 0.15))
					sm.set_shader_parameter("_ShadeColor", Color(0.8, 0.77, 0.86))
					n += 1
				mat = sm.next_pass
	if n > 0:
		print("[character] %s: lab hair correction on %d materials" % [character_id, n])


## Character light balance (Milestone K, from the Character Lab): MToon saturates under the sun + sky ambient that
## the PBR world needs. Scale the sun's and the ambient's effect on HER materials toward a balanced anime key
## (effective sun ~1.35, ambient ~0.6). Called when the light changes (area load, day/night).
var _light_balance := Vector2(-1, -1)

func apply_light_balance(sun_energy: float, ambient_energy: float) -> void:
	var cfg: Dictionary = Progression.mages.get(character_id, {}).get("face", {}) if Progression.mages else {}
	var sun_target := float(cfg.get("key_light", 1.35))
	var amb_target := float(cfg.get("ambient_light", 0.6))
	var ss := clampf(sun_target / maxf(sun_energy, 0.05), 0.3, 1.0) if sun_energy > 0.05 else 1.0
	var am := clampf(amb_target / maxf(ambient_energy, 0.05), 0.35, 1.0)
	var key := Vector2(snappedf(ss, 0.01), snappedf(am, 0.01))
	if key == _light_balance or avatar == null:
		return
	_light_balance = key
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			while mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				if sm.get_shader_parameter("_ShadeShift") != null:
					sm.set_shader_parameter("_CharSunScale", key.x)
					sm.set_shader_parameter("_CharAmbientScale", key.y)
				mat = sm.next_pass


## The VRoid skirt's spring-bone colliders are three small spheres on the upper ~0.2 m of each thigh, so
## when the thighs are horizontal (sitting) the front skirt falls through the knee half of the legs.
## Replace them with a capsule from hip to knee (same radius family, slightly fuller) before the VRM
## secondary system builds its runtime colliders. Walking is unaffected (the capsule follows the thigh).
func _extend_skirt_colliders() -> void:
	var sec = avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return
	var sk: Skeleton3D = avatar.find_child("GeneralSkeleton", true, false)
	var done := {}
	for sb in sec.spring_bones:
		if not String(sb.comment).begins_with("Skirt"):
			continue
		for cg in sb.collider_groups:
			if done.has(cg) or cg.has_meta("mika_extended"):
				continue
			done[cg] = true
			cg.set_meta("mika_extended", true)
			var legs := {}
			for c in cg.colliders:
				if String(c.bone).ends_with("UpperLeg"):
					legs[c.bone] = c.radius
			if legs.is_empty():
				continue
			var kept: Array = []
			for c in cg.colliders:
				if not legs.has(c.bone):
					kept.append(c)
			for bone in legs:
				var knee := sk.find_bone(String(bone).replace("Upper", "Lower"))
				var thigh_len := sk.get_bone_rest(knee).origin.length() if knee >= 0 else 0.4
				var cap = load("res://addons/vrm/vrm_collider.gd").new()
				cap.bone = bone
				cap.offset = Vector3.ZERO
				cap.tail = Vector3(0, thigh_len * 0.97, 0)
				cap.radius = maxf(float(legs[bone]) * 1.15, 0.08)
				cap.is_capsule = true
				kept.append(cap)
			cg.colliders.assign(kept)


## Turn her head toward a world point (books, objects, speakers); null releases it smoothly.
func look_head_at(p) -> void:
	var tw := create_tween()
	if p == null:
		tw.tween_property(head_look, "influence", 0.0, 0.5)
		for el in eye_looks:
			tw.parallel().tween_property(el, "influence", 0.0, 0.4)
		return
	_head_target.global_position = p
	tw.tween_property(head_look, "influence", 0.85, 0.5)
	for el in eye_looks:
		tw.parallel().tween_property(el, "influence", 0.9, 0.4)


## Shift the gaze target without changing influence (reading lines, glancing).
func gaze_to(p: Vector3, seconds := 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(_head_target, "global_position", p, seconds).set_trans(Tween.TRANS_SINE)


## Seated posture on/off: blends the knee correction in or out over `seconds`.
func set_seated(on: bool, seconds := 0.7) -> void:
	seated = on
	var tw := create_tween()
	tw.tween_property(pose_adjust, "influence", 1.0 if on else 0.0, seconds)


func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	ba.name = bone + "Attach"
	skeleton.add_child(ba)
	return ba


# ------------------------------------------------------------------ animation
## Retargeted clips depend only on the skeleton's path and bone set, which every VRoid VRM here shares, so
## the library is built once and reused (avatar swaps / a second mage cost no re-import of 13 FBX clips).
static var _lib_cache := {}


func skeleton_signature() -> String:
	var names := PackedStringArray()
	for i in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(i))
	return String(avatar.get_path_to(skeleton)) + "|" + str(hash(",".join(names)))


func _setup_animation() -> void:
	body_player = AnimationPlayer.new()
	body_player.name = "BodyPlayer"
	avatar.add_child(body_player)
	body_player.root_node = body_player.get_path_to(avatar)
	var sig := skeleton_signature()
	var lib: AnimationLibrary = _lib_cache.get(sig)
	if lib == null:
		lib = _build_library()
		_lib_cache[sig] = lib
	body_player.add_animation_library("mx", lib)
	_build_tree()


func _build_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var skel_path := String(avatar.get_path_to(skeleton))
	var ual: AnimationPlayer = null
	var ual_src: Node = null
	if ResourceLoader.exists(UAL_PACK):
		ual_src = load(UAL_PACK).instantiate()
		ual = ual_src.find_child("AnimationPlayer", true, false)
	for clip_name in CLIPS:
		var spec: Array = CLIPS[clip_name]
		var anim: Animation
		if String(spec[0]).begins_with("ual:"):
			var an := String(spec[0]).trim_prefix("ual:")
			if ual == null or not ual.has_animation(an):
				push_warning("[character] missing UAL clip %s; '%s' unavailable" % [an, clip_name])
				continue
			anim = ual.get_animation(an).duplicate(true)
		else:
			if not ResourceLoader.exists(MIXAMO_DIR + spec[0]):
				push_warning("[character] missing clip %s (run tools/setup_local_assets.sh); '%s' unavailable" % [spec[0], clip_name])
				continue
			var src: Node = load(MIXAMO_DIR + spec[0]).instantiate()
			var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
			anim = ap.get_animation("mixamo_com").duplicate(true)
			src.free()
		_retarget_paths(anim, skel_path, spec[2])
		anim.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		lib.add_animation(clip_name, anim)
	if ual_src:
		ual_src.free()
	return lib


func _build_tree() -> void:
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimTree"
	avatar.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(body_player)
	anim_tree.root_node = anim_tree.get_path_to(avatar)
	anim_tree.deterministic = false
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	for p in [["mx/idle", 0.0, "idle"], ["mx/walk", 1.0, "walk"], ["mx/run", 2.0, "run"]]:
		var an := AnimationNodeAnimation.new()
		an.animation = p[0]
		loco.add_blend_point(an, p[1], -1, p[2])
	loco.min_space = 0.0
	loco.max_space = 2.0
	bt.add_node("loco", loco, Vector2(0, 0))
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("loco_speed", ts, Vector2(200, 0))
	var cast_anim := AnimationNodeAnimation.new()
	cast_anim.animation = "mx/prepare_and_cast"
	bt.add_node("cast_anim", cast_anim, Vector2(200, 200))
	var gspeed := AnimationNodeTimeScale.new()
	bt.add_node("gesture_speed", gspeed, Vector2(300, 200))
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.35
	shot.fadeout_time = 0.55
	shot.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	bt.add_node("cast", shot, Vector2(400, 0))
	bt.connect_node("loco_speed", 0, "loco")
	bt.connect_node("cast", 0, "loco_speed")
	bt.connect_node("gesture_speed", 0, "cast_anim")
	bt.connect_node("cast", 1, "gesture_speed")
	bt.connect_node("output", 0, "cast")
	anim_tree.tree_root = bt
	anim_tree.active = true
	anim_tree.set("parameters/gesture_speed/scale", 1.0)


## Point tracks at Mika's skeleton, drop bones she doesn't have, and make clips in-place.
func _retarget_paths(anim: Animation, skel_path: String, in_place: bool) -> void:
	for t in range(anim.get_track_count() - 1, -1, -1):
		var path := String(anim.track_get_path(t))
		var bone := path.get_slice(":", 1)
		if bone == "" or skeleton.find_bone(bone) == -1:
			anim.remove_track(t)
			continue
		anim.track_set_path(t, NodePath(skel_path + ":" + bone))
		if in_place and bone == "Hips" and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
			var first: Vector3 = anim.track_get_key_value(t, 0)
			for k in anim.track_get_key_count(t):
				var v: Vector3 = anim.track_get_key_value(t, k)
				anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))


## Playback rate of the current gesture / dance clip (1 = authored speed).
func set_gesture_speed(scale: float) -> void:
	anim_tree.set("parameters/gesture_speed/scale", scale)


func has_clip(clip: String) -> bool:
	return body_player.has_animation("mx/" + clip)


func animation_length(clip: String) -> float:
	return body_player.get_animation("mx/" + clip).length


# ------------------------------------------------------------------ expressions (VRM blend shapes)
func _setup_expressions() -> void:
	_expr.clear()
	_expr_weight.clear()
	_expr_target.clear()
	var cfg: Dictionary = Progression.mages.get(character_id, {}).get("face", {}) if Progression.mages else {}
	face = FaceController.attach(self, avatar, cfg)
	if face:
		head_posture = HeadPosture.new()
		head_posture.name = "HeadPosture"
		head_posture.face = face
		skeleton.add_child(head_posture)
		return
	var vrm_ap: AnimationPlayer = avatar.find_child("AnimationPlayer", false, false)
	if vrm_ap == null:
		return
	for ex in ["blink", "happy", "relaxed", "surprised", "aa", "angry"]:
		if not vrm_ap.has_animation(ex):
			continue
		var anim := vrm_ap.get_animation(ex)
		var binds := []
		for t in anim.get_track_count():
			if anim.track_get_type(t) != Animation.TYPE_BLEND_SHAPE or anim.track_get_key_count(t) == 0:
				continue
			var np := anim.track_get_path(t)
			var mi := vrm_ap.get_node(vrm_ap.root_node).get_node_or_null(NodePath(String(np).get_slice(":", 0))) as MeshInstance3D
			if mi == null:
				continue
			var idx := mi.find_blend_shape_by_name(String(np).get_slice(":", 1))
			if idx >= 0:
				binds.append([mi, idx, float(anim.track_get_key_value(t, anim.track_get_key_count(t) - 1))])
		_expr[ex] = binds
		_expr_weight[ex] = 0.0
		_expr_target[ex] = 0.0


func set_expression(ex: String, weight: float) -> void:
	if face:
		face.legacy(ex, weight)
		return
	if _expr_target.has(ex):
		_expr_target[ex] = clampf(weight, 0.0, 1.0)


func _update_expressions(delta: float) -> void:
	if face:
		face.update(delta)
		return
	# natural blinking
	_blink_timer -= delta
	if _blink_timer <= 0.0 and _blink_phase < 0.0:
		_blink_phase = 0.0
		_blink_timer = randf_range(2.2, 5.5)
	var blink := 0.0
	if _blink_phase >= 0.0:
		_blink_phase += delta / 0.16
		blink = sin(clampf(_blink_phase, 0.0, 1.0) * PI)
		if _blink_phase >= 1.0:
			_blink_phase = -1.0
	var weights := {}
	for ex in _expr:
		_expr_weight[ex] = move_toward(_expr_weight[ex], _expr_target[ex], delta * 3.0)
		weights[ex] = _expr_weight[ex]
	if weights.has("blink"):
		weights["blink"] = maxf(blink * (1.0 - weights.get("happy", 0.0)), 0.0)
	var totals := {}
	for ex in _expr:
		for b in _expr[ex]:
			var key: String = str(b[0].get_instance_id()) + ":" + str(b[1])
			totals[key] = [b[0], b[1], minf(totals.get(key, [null, 0, 0.0])[2] + b[2] * weights[ex], 1.0)]
	for key in totals:
		var e: Array = totals[key]
		(e[0] as MeshInstance3D).set_blend_shape_value(e[1], e[2])


# ------------------------------------------------------------------ public control API
func set_move_input(dir: Vector3, run: bool) -> void:
	_move_input = Vector3(dir.x, 0, dir.z).limit_length(1.0)
	_run = run
	if _move_input.length() > 0.1 and (_nav_active or current_action == "look_at"):
		_finish_action(false, "interrupted by player input")


## Local avoidance while walking a path: a sideways push away from nearby characters / creatures (group
## "avoid"), strongest when close and when they are ahead of her, so two mages pass instead of shoving.
func _steer_around(desired: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("avoid"):
		if n == self or not (n as Node3D).is_visible_in_tree():
			continue
		var away := global_position - (n as Node3D).global_position
		away.y = 0
		var d := away.length()
		var reach := 1.7 if n is WorldCharacter else 1.0 + float(n.get("def").get("radius", 0.5) if n.get("def") else 0.5)
		if d < 0.01 or d > reach:
			continue
		var ahead := maxf(0.0, -away.normalized().dot(desired))
		var side := Vector3(-desired.z, 0, desired.x)
		if side.dot(away) < 0.0:
			side = -side
		push += (away.normalized() * 0.5 + side * ahead) * (1.0 - d / reach)
	if push == Vector3.ZERO:
		return desired
	return (desired + push * 1.4).normalized()


func navigate_to(target: Vector3, run := false) -> void:
	if casting:
		action_finished.emit("navigate_to", false, "busy casting")
		return
	_finish_action(false, "superseded by navigate_to")
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		last_rejection = "navigation not ready yet"
		action_finished.emit("navigate_to", false, last_rejection)
		return
	var reachable := NavigationServer3D.map_get_closest_point(map, target)
	if reachable.distance_to(target) > 2.0:
		last_rejection = "unreachable: nearest walkable point is %.1f m from target" % reachable.distance_to(target)
		action_finished.emit("navigate_to", false, last_rejection)
		return
	_nav_goal = target
	nav_agent.target_position = target
	_nav_active = true
	_run = run
	_nav_stuck_time = 0.0
	_nav_last_pos = global_position
	_action_deadline = Time.get_ticks_msec() / 1000.0 + 90.0
	_begin_action("navigate_to", {"target": [target.x, target.y, target.z], "run": run})


func look_at_point(target: Vector3) -> void:
	_finish_action(false, "superseded by look_at")
	_look_target = target
	_action_deadline = Time.get_ticks_msec() / 1000.0 + 6.0
	_begin_action("look_at", {"target": [target.x, target.y, target.z]})


func stop_action() -> void:
	if casting:
		anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_finish_action(false, "stopped")
	set_move_input(Vector3.ZERO, false)


## Begins a cast; the spell node drives the visuals and calls `end_cast()` when resolved.
func cast_spell(spell_scene: Script, clip := "prepare_and_cast") -> Node:
	anim_tree.set("parameters/gesture_speed/scale", 1.0)   # a dance tempo must never slow a spell
	if casting or not is_on_floor():
		action_finished.emit("cast_spell", false, "already casting" if casting else "not on the ground")
		return null
	_finish_action(false, "superseded by cast")
	if sword and sword.drawn:
		sword.sheathe()  # spells use both hands; keeps the original cast sequence unchanged
	casting = true
	_nav_active = false
	var shot := (anim_tree.tree_root as AnimationNodeBlendTree).get_node("cast") as AnimationNodeOneShot
	shot.fadein_time = 0.35
	shot.fadeout_time = 0.55
	(anim_tree.tree_root as AnimationNodeBlendTree).get_node("cast_anim").animation = "mx/" + clip
	anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_begin_action("cast_spell", {"clip": clip})
	set_expression("relaxed", 0.0)
	var spell: Node3D = spell_scene.new()
	get_parent().add_child(spell)
	spell.call("start", self, clip)
	return spell


## Play a one-off body gesture (study, practice, look around...) through the same one-shot slot as casting.
func play_gesture(clip: String, fade_in := 0.35, fade_out := 0.55) -> bool:
	if casting or not CLIPS.has(clip) or not has_clip(clip):
		return false
	var bt := anim_tree.tree_root as AnimationNodeBlendTree
	var shot := bt.get_node("cast") as AnimationNodeOneShot
	shot.fadein_time = fade_in
	shot.fadeout_time = fade_out
	bt.get_node("cast_anim").animation = "mx/" + clip
	anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


## Ends a looping gesture (seated loop) with the one-shot's fade-out.
func end_gesture() -> void:
	anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Combat stance (Milestone J): her idle becomes a ready, hands-up stance while a fight is on.
func set_combat_stance(on: bool) -> void:
	if on == combat_stance or anim_tree == null:
		return
	combat_stance = on and has_clip("combat_idle")
	var loco := (anim_tree.tree_root as AnimationNodeBlendTree).get_node("loco") as AnimationNodeBlendSpace1D
	(loco.get_blend_point_node(0) as AnimationNodeAnimation).animation = "mx/combat_idle" if combat_stance else "mx/idle"


## A real evasive move (Milestone J): she turns into the escape direction and rolls/steps there - the
## body actually travels (collision + floor), it is not an animation played in place. Awaitable; returns
## the distance really covered. Refused while casting (a cast is a commitment) or seated.
func dodge(to: Vector3, dur := 0.6) -> float:
	if casting or seated or not is_on_floor():
		return 0.0
	var d := Vector3(to.x - global_position.x, 0, to.z - global_position.z)
	if d.length() < 0.3:
		return 0.0
	_finish_action(false, "superseded by dodge")
	_nav_active = false
	var from := global_position
	_dash = {"dir": d.normalized(), "dist": d.length(), "t": 0.0, "dur": dur, "from": from}
	rotation.y = atan2(-d.x, -d.z)            # commit to the direction: a burst of speed, upright
	set_gesture_speed(1.35)
	play_gesture("dodge_dash", 0.08, 0.25)
	_begin_action("dodge", {"to": [to.x, to.y, to.z]})
	while not _dash.is_empty():
		await get_tree().physics_frame
	end_gesture()
	set_gesture_speed(1.0)
	var moved := Vector2(global_position.x - from.x, global_position.z - from.z).length()
	_finish_action(moved > 0.5, "dodged %.1f m" % moved)
	return moved


## Struck by a creature (Milestone J): a visible reaction - a flinch for a light blow, a stagger back for a
## heavy one (real push-back through collision). While casting she only flinches (the cast goes on).
func take_hit(from: Vector3, heavy := false) -> void:
	var away := Vector3(global_position.x - from.x, 0, global_position.z - from.z)
	away = away.normalized() if away.length() > 0.05 else global_transform.basis.z
	set_expression("surprised", 0.9)
	get_tree().create_timer(0.7).timeout.connect(func(): set_expression("surprised", 0.0))
	var clip := "hit_knockback" if heavy else ("hit_chest" if randf() < 0.6 else "hit_head")
	last_hit = {"t": Time.get_ticks_msec() / 1000.0, "heavy": heavy, "clip": clip}
	if casting or seated or not _dash.is_empty():
		return
	_finish_action(false, "struck")
	_nav_active = false
	play_gesture(clip, 0.05, 0.35)
	if heavy:
		_dash = {"dir": away, "dist": 1.1, "t": 0.0, "dur": 0.45, "from": global_position, "keep_facing": true}


func end_cast(ok: bool, detail: String) -> void:
	casting = false
	set_expression("happy", 0.0)
	set_expression("surprised", 0.0)
	if current_action == "cast_spell":
		_finish_action(ok, detail)


func _begin_action(action: String, detail: Dictionary) -> void:
	current_action = action
	action_detail = detail
	action_started.emit(action, detail)


func _finish_action(ok: bool, detail: String) -> void:
	if current_action == "idle":
		return
	var a := current_action
	current_action = "idle"
	action_detail = {}
	_nav_active = false
	_look_target = null
	if a == "navigate_to" or a == "look_at":
		_run = false
	action_finished.emit(a, ok, detail)


# ------------------------------------------------------------------ simulation
func _physics_process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var desired := _move_input
	if _nav_active:
		if nav_agent.is_navigation_finished():
			var miss := Vector2(global_position.x - _nav_goal.x, global_position.z - _nav_goal.z).length()
			if miss <= 1.2:
				_finish_action(true, "arrived (%.2f m from target)" % miss)
			else:
				_finish_action(false, "stopped %.2f m short of target (blocked)" % miss)
			desired = Vector3.ZERO
		else:
			var next := nav_agent.get_next_path_position()
			desired = (next - global_position)
			desired.y = 0
			desired = desired.normalized()
			desired = _steer_around(desired)
			# window-based progress check: less than 0.5 m in 3 s while trying to move = stuck
			_nav_stuck_time += delta
			if _nav_stuck_time >= 3.0:
				if global_position.distance_to(_nav_last_pos) < 0.5:
					_finish_action(false, "stuck: under 0.5 m of progress in 3 s near %s" % str(global_position.snapped(Vector3.ONE * 0.1)))
				_nav_stuck_time = 0.0
				_nav_last_pos = global_position
			elif now > _action_deadline:
				_finish_action(false, "timeout")
	if casting:
		desired = Vector3.ZERO
	if not _dash.is_empty():
		# a dodge / knock-back: ease-out travel along the chosen line, through collision and floor
		_dash.t = float(_dash.t) + delta
		var k := clampf(float(_dash.t) / float(_dash.dur), 0.0, 1.0)
		var v := float(_dash.dist) / float(_dash.dur) * 2.0 * (1.0 - k)      # integral of 2(1-k) over [0,1] = 1
		velocity.x = (_dash.dir as Vector3).x * v
		velocity.z = (_dash.dir as Vector3).z * v
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		if not _dash.get("keep_facing", false):
			rotation.y = lerp_angle(rotation.y, atan2(-(_dash.dir as Vector3).x, -(_dash.dir as Vector3).z), 1.0 - exp(-20.0 * delta))
		anim_tree.set("parameters/loco/blend_position", 0.0)
		if k >= 1.0:
			_dash = {}
			velocity = Vector3(0, velocity.y, 0)
		return
	var speed := (run_speed if _run else walk_speed) * pace
	var target_vel := desired * speed
	var accel := 10.0 if desired.length() > 0.01 else 12.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * speed)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * speed)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	var before := global_position
	var was_on_floor := is_on_floor()
	move_and_slide()
	var wanted := Vector3(velocity.x, 0, velocity.z) if target_vel.length() < 0.01 else Vector3(target_vel.x, 0, target_vel.z)
	if was_on_floor and is_on_wall() and wanted.length() > 0.3:
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		if moved < wanted.length() * delta * 0.5:
			_try_step_up(wanted.normalized())

	# orientation: face travel direction, or the look target
	var face_dir := Vector3.ZERO
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() > 0.2:
		face_dir = hv.normalized()
	elif _look_target != null:
		face_dir = (_look_target as Vector3 - global_position)
		face_dir.y = 0
		if face_dir.length() > 0.01:
			face_dir = face_dir.normalized()
			var ang := absf(angle_difference(rotation.y, atan2(-face_dir.x, -face_dir.z)))
			if ang < 0.05:
				_finish_action(true, "facing target")
			elif now > _action_deadline:
				_finish_action(false, "timeout")
	if face_dir != Vector3.ZERO:
		var target_yaw := atan2(-face_dir.x, -face_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

	# locomotion blend: 0 idle, 1 walk, 2 run; time scale keeps feet planted
	var spd := hv.length()
	_speed_smoothed = lerpf(_speed_smoothed, spd, 1.0 - exp(-8.0 * delta))
	var blend := 0.0
	if _speed_smoothed < walk_speed:
		blend = _speed_smoothed / walk_speed
	else:
		blend = 1.0 + clampf((_speed_smoothed - walk_speed) / (run_speed - walk_speed), 0.0, 1.0)
	anim_tree.set("parameters/loco/blend_position", blend)
	var ref := 1.0
	if blend > 0.05 and blend <= 1.0:
		ref = clampf(_speed_smoothed / walk_speed, 0.6, 1.3)
	elif blend > 1.0:
		ref = clampf(_speed_smoothed / lerpf(walk_speed, run_speed, blend - 1.0), 0.7, 1.25)
	anim_tree.set("parameters/loco_speed/scale", ref)


## Step-up for small ledges (rock lips, disc rims, kerbs) that navigation treats as climbable
## (agent_max_climb 0.25 m). CharacterBody3D has no built-in step-up.
const STEP_HEIGHT := 0.34


func _try_step_up(dir: Vector3) -> void:
	var t := global_transform
	if test_move(t, Vector3(0, STEP_HEIGHT, 0)):
		return  # no headroom
	var up := t.translated(Vector3(0, STEP_HEIGHT, 0))
	var fwd := dir * 0.18
	if test_move(up, fwd):
		return  # still a wall at step height: a real obstacle
	var over := up.translated(fwd)
	var col := KinematicCollision3D.new()
	if test_move(over, Vector3(0, -STEP_HEIGHT - 0.05, 0), col) and col.get_normal().y > 0.7:
		global_position = over.origin + col.get_travel()
		velocity.y = 0.0


func _process(delta: float) -> void:
	_update_expressions(delta)


# ------------------------------------------------------------------ observation
func observe() -> Dictionary:
	var p := global_position
	var fwd := -global_transform.basis.z
	return {
		"id": character_id,
		"name": display_name,
		"position": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"facing_yaw_deg": snappedf(rad_to_deg(rotation.y), 0.1),
		"forward": [snappedf(fwd.x, 0.01), snappedf(fwd.z, 0.01)],
		"speed": snappedf(Vector3(velocity.x, 0, velocity.z).length(), 0.01),
		"on_floor": is_on_floor(),
		"current_action": current_action,
		"action_detail": action_detail,
		"casting": casting,
	}
