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
const MOCAP_DIR := "res://assets/animations/movelib/"
## name -> [file, loop, in_place]
const CLIPS := {
	"idle": ["standing_idle.fbx", true, true],
	"walk": ["walking.fbx", true, true],
	# runway walk and turn (Selwyn's Mixamo clips, 2026-10-19): "walk_goddess" = a phase-aligned 50/50 blend of the
	# catwalk and the normal walk (elegant, not sassy); "catwalk_turn" plays with its hip yaw moved to her root
	"catwalk": ["catwalk_walking.fbx", true, true],
	# Move Library activities (Selwyn's reference videos, mocapped: tools/mocap, MocapBake fits each girl's skeleton)
	"ml_rowing": ["mocap:rowing_seated", true, true],
	"ml_release_lantern": ["mocap:release_lantern", false, true],
	"ml_stargaze_point": ["mocap:stargaze_point", false, true],
	"ml_sit_gaze": ["mocap:sit_lean_back_gaze", false, true],
	"ml_cast_water_walk": ["mocap:cast_water_walk", false, true],     # the magic path over the lake (LakeWaterDance)
	# held poses for cinematics (probe candidates for the Starlit Harp)
	"hold_wide_a": ["wide_arm_spell_casting.fbx@0.9", true, true],
	"hold_wide_b": ["wide_arm_spell_casting.fbx@1.7", true, true],
	"hold_wide_c": ["wide_arm_spell_casting.fbx@2.5", true, true],
	"hold_point_a": ["pointing.fbx@0.7", true, true],
	"hold_point_b": ["pointing.fbx@1.2", true, true],
	"hold_cast_a": ["spell_casting.fbx@1.0", true, true],
	"hold_cast_b": ["spell_casting.fbx@2.0", true, true],
	"catwalk_turn": ["catwalk_walk_turn_180_wide.fbx", false, true],
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
	# the dance wing's party routines (the owner's Mixamo FBX, Mika-Live assets/animations/mixamo-source/dance)
	"dance_macarena": ["macarena_dance.fbx", true, true],
	"dance_chicken": ["chicken_dance.fbx", true, true],
	"dance_ymca": ["ymca_dance.fbx", true, true],
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
	"lift_off": ["ual:Jump_Start", false, true],       # Rising Air: the push off the ground
	"land_soft": ["ual:Jump_Land", false, true],       # and setting down again
	# Milestone K (V3) rest set: Quaternius Universal Animation Library (CC0), second pack. "@t" freezes a clip at
	# time t (a held pose), "~rev" plays it backwards (the get-up becomes the lie-down).
	"sit_ground_enter": ["ual_rest:Sitting_Enter", false, true],
	"sit_ground_loop": ["ual_rest:Sitting_Idle", true, true],
	"sit_ground_talk": ["ual_rest:Sitting_Talking", true, true],
	"sit_ground_exit": ["ual_rest:Sitting_Exit", false, true],
	"lie_down_mx": ["lying_down.fbx", false, true],
	"lie_down": ["ual_rest:LayToIdle~rev", false, true],
	"lie_loop": ["ual_rest:LayToIdle@0.0", true, true],
	"lie_get_up": ["ual_rest:LayToIdle", false, true],
	"crouch_loop": ["ual_rest:Crouch_Idle", true, true],
	"idle_talk": ["ual_rest:Idle_Talking", true, true],
	"kneel_fix": ["ual_rest:Fixing_Kneeling", false, true],
	# V3 continuation - believable impact and recovery (BodyReaction). "[a-b]" plays only that part of a clip.
	# Quaternius UAL (CC0) + the developer's Mixamo set; crossfaded through the "react" state machine.
	"rx_stagger": ["ual_react:Idle_Shield_Break", false, true],
	"rx_steady": ["ual_react:Idle_Shield_Break[0.5-1.04]", false, true],
	"rx_absorb": ["ual_react:Jump_Land[0.1-1.25]", false, true],
	"rx_fall_back": ["ual_react:Death01[0-1.3]", false, true],
	"rx_blown_back": ["ual:Hit_Knockback", false, true],
	"rx_down_back": ["ual_rest:LayToIdle@0.0", true, true],
	"rx_sit_up": ["ual_rest:LayToIdle[0-0.62]", false, true],
	"rx_sit_hold": ["ual_rest:LayToIdle@0.62", true, true],
	"rx_stand_from_sit": ["ual_rest:LayToIdle[0.62-1.5]", false, true],
	"rx_quick_up": ["ual_react:Slide_Exit", false, true],
	"rx_fall_fwd": ["standing_react_death_forward.fbx[0-1.45]", false, true],
	"rx_kneel_hold": ["standing_react_death_forward.fbx@1.45", true, true],
	"rx_kneel_rise": ["ual_rest:Fixing_Kneeling[4.3-5.17]", false, true],
	"rx_crouch_help": ["ual_rest:Crouch_Idle", true, true],
	"rx_reach_help": ["ual_react:Interact", false, true],
	# body language (data/motion_profiles.json): Luna's poised formal walk; a few idles
	"walk_formal": ["ual_react:Walk_Formal_Loop", true, true],
	"idle_folded": ["ual_react:Idle_FoldArms_Loop", true, true],
	"consume": ["ual_react:Consume", false, true],
}
const UAL_PACK := "res://assets/animations/ual/ual_combat.glb"
const UAL_PACKS := {"ual": "res://assets/animations/ual/ual_combat.glb", "ual_rest": "res://assets/animations/ual/ual_rest.glb",
	"ual_react": "res://assets/animations/ual/ual_react.glb"}

@export var character_id := "mika"
@export var display_name := "Mika"
@export var avatar_path := "res://assets/characters/mika/Mika.vrm"
@export var walk_speed := 1.45
@export var run_speed := 4.1
@export var turn_speed := 10.0
const STAND_TURN := 3.5         # rad/s at most while she turns on the spot (the feet step round)
const MOVE_TURN := 5.0          # rad/s at most while she walks (a half turn takes 0.6 s: the hair follows, never flies)

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
var cloth_clearance: ClothClearance   # hands kept out of her clothes (profile.clearance)
var dress_sim: DressSim               # the skirt on SpringBoneSimulator3D (profile.dress.sim, --dress-sim)
var foot_guard: FootGuard              # feet kept on top of the floor (a dance carrying her hips over a raised floor)
var foot_lock: FootLock                # planted feet do not slide while she walks / runs
var head_look: LookAtModifier3D  # eases her head toward what she reads / inspects
var eye_looks: Array[LookAtModifier3D] = []
var handler: ObjectHandler       # right-arm IK + holding objects
var _head_target: Node3D
var gaze_trace := {}            # --trace-gaze: the last head-target change {t (ticks ms), by}
var seated := false
var _gclock := 0.0   # game seconds: action deadlines must not depend on real time (Movie Maker recording runs slower)

var current_action := "idle"
var last_rejection := ""  # reason the most recent action request was refused outright
var action_detail := {}
var casting := false
var lifted := false               # Rising Air holds her in the air: the spell moves her body, not gravity or walking
var _move_input := Vector3.ZERO
## Hand-steered steps (a follower, the last steps into a talk, making room, closing in on a thing) stay on the
## walkable navmesh: a wall that is only drawn, with no collider, never lets her through (2026-10-17 live).
## The keyboard player turns it off.
var nav_bound := true
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
var reaction: BodyReaction # impact, fall and recovery (V3 continuation)


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
	reaction = BodyReaction.attach(self)
	if body_language and is_instance_valid(body_language) and not reaction.reacted.is_connected(body_language.on_hit):
		reaction.reacted.connect(body_language.on_hit)    # the rig (and its body language) was built first

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
	_repair_colliders()
	_shoulder_colliders()
	_tune_springs()
	AvatarLook.calm_springs(avatar)                # (hair and cloth chains move together: no torn mesh between them)
	var dress_mode := DressSim.mode_for(self)
	var dress_chains := DressSim.take_chains(avatar) if dress_mode == "sbs" else 0
	if not RenderProfile.options.has("no-hem-floor"):
		HemFloor.attach.call_deferred(self)          # the hem rests on the floor, never through it
	avatar.name = "Avatar"
	avatar.rotation.y = PI  # VRM 1.0 faces +Z; Godot forward is -Z
	add_child(avatar)
	skeleton = avatar.find_child("GeneralSkeleton", true, false)
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_fix_vrm1_mtoon_shading()
	_fix_open_surface_outlines()
	_natural_hair()
	_lab_hair_fix()
	_skin_tone()
	_face_shadows()
	if not RenderProfile.options.has("no-avatar-look"):
		AvatarLook.apply(self)                         # no body outline shards; hair and cloth opaque with alpha scissor
	_light_balance = Vector2(-1, -1)          # a new avatar's materials need the balance again
	_setup_animation()
	_setup_expressions()
	pose_adjust = PoseAdjust.new()
	pose_adjust.name = "PoseAdjust"
	pose_adjust.influence = 0.0
	skeleton.add_child(pose_adjust)
	var clr: Dictionary = AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("clearance", {})
	cloth_clearance = ClothClearance.attach(skeleton, clr) if not clr.is_empty() else null
	if cloth_clearance and RenderProfile.options.has("no-clearance"):
		cloth_clearance.enabled = false
	foot_guard = FootGuard.new()
	foot_guard.name = "FootGuard"
	skeleton.add_child(foot_guard)
	foot_guard.enabled = not RenderProfile.options.has("no-foot-guard")
	foot_lock = FootLock.new()                     # planted feet hold their spot on the ground (after FootGuard)
	foot_lock.name = "FootLock"
	skeleton.add_child(foot_lock)
	foot_lock.enabled = not RenderProfile.options.has("no-foot-lock")
	dress_sim = DressSim.attach(self, dress_mode) if (dress_chains > 0 or dress_mode == "guard") else null     # after the pose corrections
	HandGuard.attach(skeleton)                     # hands never inside a face or a body (self and the other girl)
	if not RenderProfile.options.has("no-seam-guard"):
		SeamGuard.attach(self)                     # skirt and hair sheets never split between neighbouring chains
	if not RenderProfile.options.has("no-hair-guard"):
		HairGuard.attach(self)                     # hair never sinks into her upper arms (after the springs)
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
	PosePipeline.of(self).arrange()                # one owner of the pose order (activity, IK, collision, cloth)
	left_hand = _attach("LeftHand")
	right_hand = _attach("RightHand")
	chest = _attach("UpperChest")
	apply_motion_profile()


## Her own body language (data/motion_profiles.json, chosen by the appearance stage's profile.motion): locomotion
## clip and pace, turn and look speeds, idle glances, gesture tempo, Mika's ears.
var motion := {}
var ears: EarController
var body_language: BodyLanguage
var _glance_t := 4.0
static var _motion_data := {}


func apply_motion_profile() -> void:
	if _motion_data.is_empty():
		var f := FileAccess.open("res://data/motion_profiles.json", FileAccess.READ)
		_motion_data = JSON.parse_string(f.get_as_text()) if f else {}
	var key := String(stage_profile().get("motion", ""))
	motion = _motion_data.get(key, {})
	if motion.is_empty():
		return
	walk_speed = float(motion.get("walk_speed", walk_speed))
	run_speed = float(motion.get("run_speed", run_speed))
	turn_speed = float(motion.get("turn_speed", turn_speed))
	if head_look:
		head_look.duration = float(motion.get("head_look_s", head_look.duration))
	for el in eye_looks:
		el.duration = float(motion.get("eye_look_s", el.duration))
	var wc := String(motion.get("walk_clip", "walk"))
	if anim_tree and has_clip(wc):
		var loco := (anim_tree.tree_root as AnimationNodeBlendTree).get_node("loco") as AnimationNodeBlendSpace1D
		(loco.get_blend_point_node(1) as AnimationNodeAnimation).animation = "mx/" + wc
	if ears and is_instance_valid(ears):
		ears.queue_free()
	ears = null
	if float(motion.get("ears", 0.0)) > 0.0:
		ears = EarController.attach(self, float(motion.ears))
		PosePipeline.of(self).arrange()
	# full-body expression (posture, injury, breathing, talking hands) - before the hair springs and head posture
	if body_language == null or not is_instance_valid(body_language):
		body_language = BodyLanguage.attach(self, float(motion.get("body", 1.0)))
		if body_language:
			PosePipeline.of(self).arrange()
			if reaction and not reaction.reacted.is_connected(body_language.on_hit):
				reaction.reacted.connect(body_language.on_hit)


## Idle glances: when she stands doing nothing, she looks around now and then - Mika quickly and often, Luna rarely
## and slowly (her own profile).
func _idle_glance(delta: float) -> void:
	if motion.is_empty() or current_action != "idle" or casting or (reaction and reaction.active) or velocity.length() > 0.3:
		return
	_glance_t -= delta
	if _glance_t > 0.0:
		return
	var ge: Array = motion.get("glance_every", [5.0, 9.0])
	_glance_t = randf_range(float(ge[0]), float(ge[1]))
	if head_look and head_look.influence > 0.05:
		return              # something else is directing her gaze
	var rng_deg := float(motion.get("glance_range_deg", 60.0))
	var fwd := -global_transform.basis.z
	var dir := fwd.rotated(Vector3.UP, deg_to_rad(randf_range(-rng_deg, rng_deg)))
	look_head_at(global_position + dir * 6.0 + Vector3(0, randf_range(1.0, 2.2), 0))
	get_tree().create_timer(randf_range(1.2, 2.4)).timeout.connect(func(): if is_instance_valid(self) and current_action == "idle": look_head_at(null))


signal avatar_swapped(path: String)

## The appearance stage of the avatar she wears (data/appearances.json) and its profile overrides.
func stage() -> Dictionary:
	return AppearanceRegistry.stage_for_avatar(character_id, avatar_path)


func stage_profile() -> Dictionary:
	return stage().get("profile", {})

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
const VROID_FACE_SHADING := Vector2(0.71, 0.91)
var face_shading_restored := 0

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
					# Day 3: the Blender outfit rebuilds gave the face skin the body's toon values (-0.1, 0.88), which
					# put a hard light/shade line down the middle of the face. Faces get VRoid's own face shading back
					# (0.71, 0.91 -> lit almost everywhere, as both girls' VRoid originals are).
					if String(sm.resource_name).ends_with("_Face_00_SKIN") and s1 < VROID_FACE_SHADING.x - 0.2:
						s1 = VROID_FACE_SHADING.x
						t1 = VROID_FACE_SHADING.y
						face_shading_restored += 1
					var s0 := clampf(-s1 - (1.0 - t1), -1.0, 1.0)
					var t0 := clampf(1.0 - 2.0 * (1.0 - t1) / maxf(1.0 - s0, 0.001), 0.0, 1.0)
					sm.set_shader_parameter("_ShadeShift", s0)
					sm.set_shader_parameter("_ShadeToony", t0)
					sm.set_shader_parameter("_Vrm1Lighting", 1.0)
					sm.set_meta("vrm1_shading_converted", [s1, t1, s0, t0])
					fixed += 1
				mat = sm.next_pass
	print("[character] %s: converted VRM1 MToon shading on %d materials (VRoid face shading restored on %d)" % [character_id, fixed, face_shading_restored])


## Natural hair shading for appearance stages that ask for it (profile.hair.natural): the model's own strand texture
## and colours, with fine fibres, root depth, an anisotropic sheen band and soft tapered tips
## (shaders/characters/natural_hair.gdshader). The hairstyle itself - geometry, colour, ornaments - is untouched.
func _natural_hair() -> void:
	var hp: Dictionary = AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("hair", {})
	if not bool(hp.get("natural", false)) or RenderProfile.options.has("no-natural-hair"):
		return
	var shader: Shader = load("res://shaders/characters/natural_hair.gdshader")
	var n := 0
	# the outer hair's texture: the under layer and the cap take it too (their own darker paint shows through the
	# gaps between clumps as jagged dark wedges)
	var outer_tex: Texture2D = null
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m0: MeshInstance3D = mi
		if m0.mesh == null:
			continue
		for si in m0.mesh.get_surface_count():
			var s0 := m0.get_active_material(si) as ShaderMaterial
			if s0 and String(s0.resource_name).ends_with("_Hair") and s0.get_shader_parameter("_MainTex"):
				outer_tex = s0.get_shader_parameter("_MainTex")
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.get_active_material(si)
			var nm := String(src.resource_name) if src else ""
			if not (nm.ends_with("_Hair") or nm.ends_with("_HairUnder") or nm.ends_with("_HairCap")):
				continue
			var tex: Texture2D = null
			var sm := src as ShaderMaterial
			if sm:
				tex = sm.get_shader_parameter("_MainTex")
			if tex == null:
				continue
			var hm := ShaderMaterial.new()
			hm.shader = shader
			hm.resource_name = nm + "_natural"
			var sh: Array = hp.get("shade", [0.68, 0.64, 0.8])
			var under := nm.ends_with("_HairUnder")
			var cap := nm.ends_with("_HairCap")
			hm.set_shader_parameter("albedo_tex", outer_tex if (under or cap) and outer_tex else tex)
			# the under layer / cap shade like the outer hair: a darker under layer shows through the gaps between
			# clumps as jagged dark wedges ("messy")
			hm.set_shader_parameter("shade_tint", Color(sh[0], sh[1], sh[2]))
			var sc: Array = hp.get("sheen_color", [1.0, 0.97, 0.94])
			hm.set_shader_parameter("sheen_color", Color(sc[0], sc[1], sc[2]))
			hm.set_shader_parameter("sheen", float(hp.get("sheen", 0.55)) * (0.5 if under else 1.0))
			hm.set_shader_parameter("sheen2", float(hp.get("sheen2", 0.35)))
			hm.set_shader_parameter("fibre_density", float(hp.get("fibre_density", 260.0)))
			hm.set_shader_parameter("fibre_strength", float(hp.get("fibre_strength", 0.22)))
			hm.set_shader_parameter("detail", float(hp.get("detail", 0.35)) * (0.5 if under or cap else 1.0))
			if hp.has("mass_color"):
				var mc: Array = hp.mass_color
				hm.set_shader_parameter("mass_color", Color(mc[0], mc[1], mc[2], 1.0))
			hm.set_shader_parameter("root_dark", float(hp.get("root_dark", 0.3)))
			hm.set_shader_parameter("tip_feather", 0.0 if cap else float(hp.get("tip_feather", 0.12)))
			hm.set_shader_parameter("gain", float(hp.get("gain", 1.0)))
			m.set_surface_override_material(si, hm)
			n += 1
	if n > 0:
		print("[character] %s: natural hair shading on %d surfaces" % [character_id, n])


## MToon's outline is an "inverted hull": the surface pushed out along its normals and drawn back-faces-only. On a
## closed mesh that is a rim; on OPEN, double-sided geometry (hair strand ribbons, sheer sleeves, skirt panels) the
## pushed-out copy lies in FRONT of the visible face and paints it the outline colour - the level 1-10 Celestial
## models' lavender/brown hair rendered navy/black. Blender's preview never showed it. Remove the outline pass from
## double-sided materials (closed meshes keep theirs). Render-time only: the VRM files are untouched.
func _fix_open_surface_outlines() -> void:
	var n := 0
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si) as ShaderMaterial
			if mat == null or mat.shader == null or mat.next_pass == null:
				continue
			if not String(mat.shader.resource_path).contains("cull_off"):
				continue
			var nxt := mat.next_pass as ShaderMaterial
			if nxt and nxt.shader and String(nxt.shader.resource_path).to_lower().contains("outline"):
				var copy := mat.duplicate() as ShaderMaterial
				copy.next_pass = null
				m.set_surface_override_material(si, copy)
				n += 1
	if n > 0:
		print("[character] %s: removed the inverted-hull outline from %d double-sided surfaces" % [character_id, n])


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
var _scene_tint_key := Vector3(-1, -1, -1)

func apply_light_balance(sun_energy: float, ambient_energy: float) -> void:
	var cfg: Dictionary = Progression.mages.get(character_id, {}).get("face", {}) if Progression.mages else {}
	var sun_target := float(cfg.get("key_light", 1.35))
	var amb_target := float(cfg.get("ambient_light", 0.6))
	var ss := clampf(sun_target / maxf(sun_energy, 0.05), 0.3, 1.0) if sun_energy > 0.05 else 1.0
	var am := clampf(amb_target / maxf(ambient_energy, 0.05), 0.35, 1.0)
	var key := Vector2(snappedf(ss, 0.01), snappedf(am, 0.01))
	# scene light match (2026-10-18, Selwyn: "she looks pasted on: flat even lighting while the world is overcast
	# grey"): her light takes the scene's colour (the sun's and the sky's, half way to white so she stays readable)
	# and a soft rim in the sky's colour - she sits inside the scene's light instead of on top of it
	var tint := Color(1, 1, 1)
	var sky := Color(0, 0, 0)
	if not RenderProfile.options.has("no-scene-light"):
		var env: Environment = get_world_3d().environment if get_world_3d() else null
		var sun_col := Color(1, 1, 1)
		for l in get_tree().root.find_children("Sun", "DirectionalLight3D", true, false):
			if (l as DirectionalLight3D).is_visible_in_tree():
				sun_col = (l as DirectionalLight3D).light_color
				break
		if env:
			var amb := env.ambient_light_color
			var w := clampf(ambient_energy / maxf(ambient_energy + sun_energy, 0.01), 0.0, 1.0)
			var mixc := sun_col.lerp(amb, w)
			var mx := maxf(mixc.r, maxf(mixc.g, mixc.b))
			if mx > 0.001:
				mixc = Color(mixc.r / mx, mixc.g / mx, mixc.b / mx)
			tint = Color(1, 1, 1).lerp(mixc, float(Progression.mages.get(character_id, {}).get("face", {}).get("scene_tint", 0.5)) if Progression.mages else 0.5)
			sky = amb * clampf(ambient_energy, 0.2, 1.2) * 0.28
	var tkey := Vector3(snappedf(tint.r, 0.02), snappedf(tint.g, 0.02), snappedf(tint.b, 0.02))
	if key == _light_balance and tkey == _scene_tint_key or avatar == null:
		return
	_light_balance = key
	_scene_tint_key = tkey
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
					sm.set_shader_parameter("_CharLightTint", Vector3(tint.r, tint.g, tint.b))
					sm.set_shader_parameter("_CharSkyRim", Vector3(sky.r, sky.g, sky.b))
				elif sm.shader and String(sm.shader.resource_path).ends_with("natural_hair.gdshader"):
					sm.set_shader_parameter("sun_scale", key.x)          # the hair sits in the same light key as her face
				mat = sm.next_pass


## The VRoid skirt's spring-bone colliders are three small spheres on the upper ~0.2 m of each thigh, so
## when the thighs are horizontal (sitting) the front skirt falls through the knee half of the legs.
## Replace them with a capsule from hip to knee (same radius family, slightly fuller) before the VRM
## secondary system builds its runtime colliders. Walking is unaffected (the capsule follows the thigh).
## Per-stage spring tuning (data/appearances.json profile.springs): {stiffness, drag, gravity} scales for every
## chain, and per-chain-prefix overrides {"chains": {"HairBack": {...}}}. Works on copies of the chain resources (the
## imported VRM stays untouched). Luna's long gown hair needs firmer, more damped springs than the lab's preview bake.
func _tune_springs() -> void:
	var sp: Dictionary = AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("springs", {})
	if sp.is_empty():
		return
	var sec = avatar.find_child("secondary", true, false)
	if sec == null or sec.get("spring_bones") == null:
		return
	var out = sec.spring_bones.duplicate()           # keeps the array's own element type
	for i in out.size():
		var c: Resource = (out[i] as Resource).duplicate()
		var k := {"stiffness": float(sp.get("stiffness", 1.0)), "drag": float(sp.get("drag", 1.0)), "gravity": float(sp.get("gravity", 1.0)), "hit_radius": 1.0}
		for pre in sp.get("chains", {}):
			if String(c.get("comment")).begins_with(String(pre)):
				var o: Dictionary = sp.chains[pre]
				for key in o:
					k[key] = o[key] if (o[key] is String or o[key] is bool) else float(o[key])
		c.set("stiffness_scale", float(c.get("stiffness_scale")) * k.stiffness)
		c.set("drag_force_scale", clampf(float(c.get("drag_force_scale")) * k.drag, 0.0, 1.0))
		c.set("gravity_scale", float(c.get("gravity_scale")) * k.gravity)
		c.set("hit_radius_scale", float(c.get("hit_radius_scale")) * k.hit_radius)
		# "body": simulate the chain in her own frame (the skeleton), not the world - a run does not leave the hair
		# behind to be dragged through her shoulders; her turns, bounce and arm swing still move it
		if bool(k.get("arms", false)):
			# collide with her arms too (a sleeve drape hangs beside the arm it belongs to)
			var arms_g = null
			for sb2 in sec.spring_bones:
				for cg in sb2.collider_groups:
					for col in cg.colliders:
						if String(col.bone).ends_with("UpperArm") and arms_g == null:
							arms_g = cg
			if arms_g != null and not (arms_g in c.get("collider_groups")):
				var groups = c.get("collider_groups").duplicate()
				groups.append(arms_g)
				c.set("collider_groups", groups)
		if bool(k.get("no_colliders", false)):
			var none = c.get("collider_groups").duplicate()
			none.clear()
			c.set("collider_groups", none)
		if bool(k.get("drop_head", false)):
			# a chain rooted ON the head (hair) must not collide with the head's own sphere: its roots start inside
			# it and are shoved out every frame (Luna's hair shook constantly once her head collider sat on her head)
			var keep = c.get("collider_groups").duplicate()
			keep.clear()
			for cg in c.get("collider_groups"):
				var has_head := false
				for col in cg.colliders:
					if String(col.bone).ends_with("Head"):
						has_head = true
				if not has_head:
					keep.append(cg)
			c.set("collider_groups", keep)
		if String(k.get("center", "")) == "body":
			var skel_node: Node = avatar.find_child("GeneralSkeleton", true, false)
			if skel_node:
				c.set("center_node", sec.get_path_to(skel_node))
		out[i] = c
	sec.spring_bones = out


## The frame her hair is simulated in: "" = the world (it trails behind a run, swings on a turn), or a bone (e.g.
## "UpperChest"): the hair hangs under real gravity but no longer lags behind her own body's motion - for dances,
## where every bounce and hip turn otherwise flung the long back hair up over her head. Re-seeds the strands once.
func set_hair_frame(bone: String) -> void:
	var sec = avatar.find_child("secondary", true, false) if avatar else null
	if sec == null or sec.get("spring_bones") == null or skeleton == null:
		return
	var b := bone
	if b != "" and skeleton.find_bone(b) < 0:
		b = "Chest" if skeleton.find_bone("Chest") >= 0 else ""
	for sb in sec.spring_bones:
		if String(sb.comment).begins_with("Hair") and String(sb.get("center_bone")) != b:
			sb.set("center_bone", b)
			sb.set("center_node", NodePath())


## Body colliders exported in the wrong space (profile.springs.repair_colliders): a collider whose offset lies
## metres from its own bone (Luna's oracle model: the head sphere at her feet, the chest / spine / hip / arm capsules
## as rods from ~1.3 m away to the bone) is rebuilt where it belongs, in the bone's own frame: the head sphere on the
## head, limbs along the bone to the next joint, chest and hips across the body. While the capsule collision was
## broken (see addons/vrm/vrm_collider.gd) those rods sat harmlessly at their far ends; working, they swept through
## her hair (the hair fought them every frame) while her real shoulders had none.
func _repair_colliders() -> void:
	if not bool(AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("springs", {}).get("repair_colliders", false)):
		return
	var sec = avatar.find_child("secondary", true, false)
	var sk: Skeleton3D = avatar.find_child("GeneralSkeleton", true, false)
	if sec == null or sec.get("spring_bones") == null or sk == null:
		return
	var child_of := {"Neck": "Head", "Spine": "Chest", "UpperArm": "LowerArm", "LowerArm": "Hand", "UpperLeg": "LowerLeg", "LowerLeg": "Foot"}
	var seen := {}
	var chest_spheres := 0
	var fixed := 0
	for sb in sec.spring_bones:
		for cg in sb.collider_groups:
			for col in cg.colliders:
				if seen.has(col) or col.has_meta("mika_repaired"):
					continue
				seen[col] = true
				if (col.offset as Vector3).length() < 0.4 and (col.tail as Vector3).length() < 0.6:
					continue                     # a sane collider: left as authored
				col.set_meta("mika_repaired", true)
				var bn := String(col.bone)
				var bi := sk.find_bone(bn)
				var side := "Left" if bn.begins_with("Left") or bn.contains("_L_") else ("Right" if bn.begins_with("Right") or bn.contains("_R_") else "")
				var nxt := ""
				for part in child_of:
					if bn.ends_with(String(part)):
						nxt = side + String(child_of[part])
				var ci := sk.find_bone(nxt) if nxt != "" else -1
				if ci < 0 and nxt != "":
					ci = sk.find_bone(bn.replace(bn.get_slice("_", bn.get_slice_count("_") - 1), String(child_of.get(bn.get_slice("_", bn.get_slice_count("_") - 1), ""))))
				if bn.ends_with("Head"):
					# the FRONT of the head (face and forehead): hair cannot swing through her face to the front when
					# she bends, while the hair's roots (on top of and behind the skull) lie outside it
					col.offset = Vector3(0, 0.05, 0.045)
					col.radius = minf(col.radius, 0.05)
				elif bn.ends_with("UpperChest"):
					if col.is_capsule:
						col.offset = Vector3(-0.055, 0.02, -0.005)
						col.tail = Vector3(0.055, 0.02, -0.005)
					else:
						col.offset = Vector3(0.055 if chest_spheres == 0 else -0.055, -0.01, 0.06)
						chest_spheres += 1
				elif bn.ends_with("Hips"):
					col.offset = Vector3(-0.065, -0.04, 0.0)
					col.tail = Vector3(0.065, -0.04, 0.0)
					col.radius = minf(col.radius, 0.095)        # her hips, not the authored 12 cm barrel
				elif ci >= 0 and bi >= 0:
					col.offset = Vector3.ZERO
					col.tail = sk.get_bone_rest(ci).origin
					if bn.ends_with("Spine"):
						col.radius = minf(col.radius, 0.095)
				else:
					col.offset = Vector3.ZERO
					col.tail = Vector3.ZERO
				fixed += 1
	if fixed > 0:
		print("[character] %s: rebuilt %d misplaced body colliders" % [character_id, fixed])


## Shoulder colliders for the hair (profile.springs.shoulders {radius, cap}): a model whose torso colliders stop at
## the upper chest and whose arm colliders start at the arm joint leaves the top of each shoulder bare, and long
## hair falls through it. Adds a capsule along each collarbone (shoulder joint to arm joint) and a sphere over the
## shoulder cap to every collider group the hair uses that already holds the chest. On the imported resources once
## (guarded), like the skirt's capsules.
func _shoulder_colliders() -> void:
	var cfg: Dictionary = AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("springs", {}).get("shoulders", {})
	if cfg.is_empty():
		return
	var sec = avatar.find_child("secondary", true, false)
	var sk: Skeleton3D = avatar.find_child("GeneralSkeleton", true, false)
	if sec == null or sec.get("spring_bones") == null or sk == null:
		return
	var done := {}
	# the skirt's own arm colliders (its "hands" group): forearm and hand at their real width, so a hanging hand
	# pushes the frill aside instead of passing through it (profile.springs.shoulders.forearm / .hand)
	if cfg.has("forearm"):
		for sb in sec.spring_bones:
			if not String(sb.comment).begins_with("Skirt"):
				continue
			for cg in sb.collider_groups:
				if cg.has_meta("mika_skirt_arms"):
					continue
				var has_fore := false
				for col in cg.colliders:
					if String(col.bone).ends_with("LowerArm"):
						has_fore = true
				if not has_fore:
					continue
				cg.set_meta("mika_skirt_arms", true)
				var ks: Array = cg.colliders.duplicate()
				for side in ["Left", "Right"]:
					var la := sk.find_bone(side + "LowerArm")
					var hd := sk.find_bone(side + "Hand")
					var fm := sk.find_bone(side + "MiddleProximal")
					if la < 0 or hd < 0:
						continue
					var fa = load("res://addons/vrm/vrm_collider.gd").new()
					fa.bone = sk.get_bone_name(la)
					fa.offset = Vector3.ZERO
					fa.tail = sk.get_bone_rest(hd).origin
					fa.radius = float(cfg.forearm)
					fa.is_capsule = true
					ks.append(fa)
					var hc = load("res://addons/vrm/vrm_collider.gd").new()
					hc.bone = sk.get_bone_name(hd)
					hc.offset = Vector3.ZERO
					hc.tail = (sk.get_bone_rest(fm).origin * 1.8) if fm >= 0 else Vector3(0, 0.12, 0)
					hc.radius = float(cfg.get("hand", 0.07))
					hc.is_capsule = true
					ks.append(hc)
				cg.colliders.assign(ks)
	for sb in sec.spring_bones:
		if not String(sb.comment).begins_with("Hair"):
			continue
		for cg in sb.collider_groups:
			if done.has(cg) or cg.has_meta("mika_shoulders"):
				continue
			done[cg] = true
			var chest := false
			var arms := false
			for col in cg.colliders:
				if String(col.bone).ends_with("UpperChest"):
					chest = true
				if String(col.bone).ends_with("UpperArm"):
					arms = true
			if arms and cfg.has("arm"):
				# the model's arm capsules are the bare arm (4 cm); with the sleeve and the swing of a run the hair
				# needs the arm's full width, along the whole upper arm
				cg.set_meta("mika_shoulders", true)
				var ka: Array = cg.colliders.duplicate()
				for side in ["Left", "Right"]:
					var ua := sk.find_bone(side + "UpperArm")
					if ua < 0:
						ua = sk.find_bone("J_Bip_%s_UpperArm" % side.left(1))
					var la := sk.find_bone(side + "LowerArm")
					if la < 0:
						la = sk.find_bone("J_Bip_%s_LowerArm" % side.left(1))
					if ua < 0 or la < 0:
						continue
					var cap2 = load("res://addons/vrm/vrm_collider.gd").new()
					cap2.bone = sk.get_bone_name(ua)
					cap2.offset = Vector3.ZERO
					cap2.tail = sk.get_bone_rest(la).origin
					cap2.radius = float(cfg.arm)
					cap2.is_capsule = true
					ka.append(cap2)
				cg.colliders.assign(ka)
				continue
			if not chest:
				continue
			cg.set_meta("mika_shoulders", true)
			var kept: Array = cg.colliders.duplicate()
			for side in ["Left", "Right"]:
				var arm := sk.find_bone(side + "UpperArm")
				var sh := sk.find_bone(side + "Shoulder")
				if arm < 0:
					arm = sk.find_bone("J_Bip_%s_UpperArm" % side.left(1))
					sh = sk.find_bone("J_Bip_%s_Shoulder" % side.left(1))
				if arm < 0 or sh < 0:
					continue
				var cap = load("res://addons/vrm/vrm_collider.gd").new()
				cap.bone = sk.get_bone_name(sh)
				cap.offset = Vector3.ZERO
				cap.tail = sk.get_bone_rest(arm).origin
				cap.radius = float(cfg.get("radius", 0.06))
				cap.is_capsule = true
				kept.append(cap)
				var ball = load("res://addons/vrm/vrm_collider.gd").new()
				ball.bone = sk.get_bone_name(arm)
				ball.offset = Vector3.ZERO
				ball.radius = float(cfg.get("cap", 0.065))
				kept.append(ball)
			cg.colliders.assign(kept)


## Skin tone for a stage (profile.skin {tint: [r, g, b]}): the skin materials' base colour multiplied, from the
## model's own value each time (a cached material is never tinted twice). The textures stay untouched.
func _skin_tone() -> void:
	var cfg: Dictionary = AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("skin", {})
	var tint := Color(1, 1, 1)
	if cfg.has("tint"):
		var t: Array = cfg.tint
		tint = Color(float(t[0]), float(t[1]), float(t[2]))
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			if not (mat is ShaderMaterial) or not String(mat.resource_name).ends_with("_SKIN"):
				continue
			var sm := mat as ShaderMaterial
			if sm.get_shader_parameter("_Color") == null:
				continue
			if not sm.has_meta("skin_base"):
				if cfg.is_empty():
					continue
				sm.set_meta("skin_base", sm.get_shader_parameter("_Color"))
			var base: Color = sm.get_meta("skin_base")
			sm.set_shader_parameter("_Color", Color(base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a))
			# Day 3: the skin's shade and rim colours (Luna's rebuild had an orange-brown shade and an orange rim)
			if cfg.has("shade"):
				var sh: Array = cfg.shade
				sm.set_shader_parameter("_ShadeColor", Color(float(sh[0]), float(sh[1]), float(sh[2]), 1.0))
			if cfg.has("rim"):
				var rc: Array = cfg.rim
				sm.set_shader_parameter("_RimColor", Color(float(rc[0]), float(rc[1]), float(rc[2]), 1.0))
			# one skin tone (2026-10-18, Selwyn: "face almost white, legs and hands bright pink"): the body's skin
			# gets the face's soft shading (profile.skin.body_shading = [shift, toony] in MToon 0.x terms; the face
			# is at about -0.80 / 0.90 after the VRM1 conversion) so arms and legs are not mostly in the pink shade
			if cfg.has("body_shading") and String(sm.resource_name).ends_with("_Body_00_SKIN"):
				var bs: Array = cfg.body_shading
				sm.set_shader_parameter("_ShadeShift", float(bs[0]))
				sm.set_shader_parameter("_ShadeToony", float(bs[1]))
	_face_colors()


## Day 3, per stage (profile.face): the brows' colour (Luna's rebuild tinted them navy) and the face outline's width
## (profile.face.outline_width, the material's own units: Mika's face is 0.056).
func _face_colors() -> void:
	var fc: Dictionary = AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("face", {})
	if not (fc.has("brow_color") or fc.has("outline_width")):
		return
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			var nm := String(mat.resource_name) if mat else ""
			if fc.has("brow_color") and nm.ends_with("_FaceBrow_00_FACE") and mat is ShaderMaterial:
				var bc: Array = fc.brow_color
				(mat as ShaderMaterial).set_shader_parameter("_Color", Color(float(bc[0]), float(bc[1]), float(bc[2]), 1.0))
				(mat as ShaderMaterial).set_shader_parameter("_ShadeColor", Color(float(bc[0]), float(bc[1]), float(bc[2]), 1.0))
			if fc.has("outline_width") and nm.ends_with("_Face_00_SKIN"):
				while mat is ShaderMaterial:
					if (mat as ShaderMaterial).get_shader_parameter("_OutlineWidth") != null:
						(mat as ShaderMaterial).set_shader_parameter("_OutlineWidth", float(fc.outline_width))
					mat = (mat as ShaderMaterial).next_pass


## Cast shadows on the face (anime convention): the face, eyes, brows and mouth take only a trace of the shadows other
## things cast on them (profile.face.receive_shadow, default 0.15). The hair fringe, crowns, tiaras, high collars and
## leaves otherwise drop hard dark patches over her face; her own toon shading (light direction) is unchanged.
## (From 7977bef on the outfit branch; only this function and its call are taken.)
func _face_shadows() -> void:
	var rate := float(AppearanceRegistry.stage_for_avatar(character_id, avatar_path).get("profile", {}).get("face", {}).get("receive_shadow", 0.15))
	var n := 0
	for mi in avatar.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			var nm := String(mat.resource_name) if mat else ""
			if not (String(m.name).begins_with("Face") or "_Face" in nm or "_Eye" in nm):
				continue
			while mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				if sm.get_shader_parameter("_ReceiveShadowRate") != null:
					sm.set_shader_parameter("_ReceiveShadowRate", rate)
					n += 1
				mat = sm.next_pass
	print("[character] %s: face receives %.2f of cast shadows (%d materials)" % [character_id, rate, n])


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
	if RenderProfile.options.has("trace-gaze"):
		var st := get_stack()
		var caller := ("%s:%d %s" % [String(st[1].source).get_file(), int(st[1].line), String(st[1].function)]) if st.size() > 1 else "?"
		print("[gaze] %.2f %s look_head_at %s by %s" % [Time.get_ticks_msec() / 1000.0, character_id, "null" if p == null else "point", caller])
		gaze_trace = {"t": Time.get_ticks_msec(), "by": caller + ("(release)" if p == null else "")}
	var tw := create_tween()
	if p == null:
		# back to looking ahead gently (a quick release read as the head swinging back and forth)
		tw.tween_property(head_look, "influence", 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		for el in eye_looks:
			tw.parallel().tween_property(el, "influence", 0.0, 0.6)
		return
	_head_target.global_position = p
	tw.tween_property(head_look, "influence", 0.85, 0.5)
	for el in eye_looks:
		tw.parallel().tween_property(el, "influence", 0.9, 0.4)


## How far the head follows the gaze (0..1); the eyes keep following fully. Reading uses ~0.35: the eyes travel the
## lines, the head only drifts (a head that followed every line swung left and right all page long).
func set_head_share(share: float, seconds := 0.4) -> void:
	if head_look:
		create_tween().tween_property(head_look, "influence", clampf(share, 0.0, 1.0), seconds)


## Shift the gaze target without changing influence (reading lines, glancing).
func gaze_to(p: Vector3, seconds := 0.25) -> void:
	if RenderProfile.options.has("trace-gaze"):
		var st := get_stack()
		print("[gaze] %.2f %s gaze_to by %s" % [Time.get_ticks_msec() / 1000.0, character_id, ("%s:%d" % [String(st[1].source).get_file(), int(st[1].line)]) if st.size() > 1 else "?"])
		gaze_trace = {"t": Time.get_ticks_msec(), "by": ("gaze_to %s:%d" % [String(st[1].source).get_file(), int(st[1].line)]) if st.size() > 1 else "gaze_to"}
	var tw := create_tween()
	tw.tween_property(_head_target, "global_position", p, seconds).set_trans(Tween.TRANS_SINE)


## Seated posture on/off: blends the knee correction in or out over `seconds`.
func set_seated(on: bool, seconds := 0.7) -> void:
	seated = on
	var tw := create_tween()
	tw.tween_property(pose_adjust, "influence", 1.0 if on else 0.0, seconds)


## Milestone K (V3): resting on the ground. "sit" lowers the visual root so the floor-sit clip (authored at chair
## height) sits on the grass, with the legs folded by PoseAdjust; "lie" keeps the root and adds breathing;
## "" restores standing. The physics body never moves (she stands up where she lay down).
var ground_pose := ""
## Lie down on the back where she stands (the get-up clip backwards, then the held pose with breathing).
func lie_down(speed := 0.6) -> void:
	if ground_pose == "lie" or not has_clip("lie_down"):
		return
	play_gesture("lie_down", 0.25, 0.4)
	set_gesture_speed(speed)
	await get_tree().create_timer(animation_length("lie_down") / speed - 0.1).timeout
	set_gesture_speed(1.0)
	play_gesture("lie_loop", 0.3, 0.6)
	set_ground_pose("lie", 0.6)
	# hair and dress settle on the grass (ground collider, lying spring tuning) once the pose has settled
	await get_tree().create_timer(0.7).timeout
	if ground_pose == "lie" and not RenderProfile.options.has("no-lying-springs"):
		LyingSprings.apply(self)


## Get up from lying (the real get-up clip), back to standing idle.
func get_up() -> void:
	if ground_pose != "lie":
		return
	LyingSprings.restore(self)
	end_gesture()
	set_ground_pose("", 0.8)
	play_gesture("lie_get_up", 0.2, 0.5)
	await get_tree().create_timer(animation_length("lie_get_up") + 0.3).timeout


func set_ground_pose(p: String, seconds := 0.8) -> void:
	ground_pose = p
	pose_adjust.mode = p
	pose_adjust.floor_y = 0.33 if p == "sit" else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(avatar, "position:y", -0.33 if p == "sit" else (0.08 if p == "lie" else 0.0), seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pose_adjust, "influence", 1.0 if p != "" else 0.0, seconds)


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
## Reaction clips' own hip travel (x, z per 1/30 s, from their first frame; source units): BodyReaction moves the
## body by it (root motion) while the clip itself plays in place, so a fall carries her over the ground for real.
static var root_curves := {}


static func _hip_curve(anim: Animation) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ti := -1
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and String(anim.track_get_path(t)).ends_with(":Hips"):
			ti = t
	if ti < 0:
		return out
	var first := anim.position_track_interpolate(ti, 0.0)
	var tt := 0.0
	while tt <= anim.length + 1e-4:
		var v := anim.position_track_interpolate(ti, tt) - first
		out.append(Vector2(v.x, v.z))
		tt += 1.0 / 30.0
	return out


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
	var packs := {}        # pack id -> AnimationPlayer
	var pack_srcs := []
	for pid in UAL_PACKS:
		if ResourceLoader.exists(UAL_PACKS[pid]):
			var src_node: Node = load(UAL_PACKS[pid]).instantiate()
			pack_srcs.append(src_node)
			packs[pid] = src_node.find_child("AnimationPlayer", true, false)
	for clip_name in CLIPS:
		var spec: Array = CLIPS[clip_name]
		var anim: Animation
		var src_spec := String(spec[0])
		var freeze_at := -1.0
		var reverse := false
		var rng_a := -1.0
		var rng_b := -1.0
		if src_spec.ends_with("]") and src_spec.contains("["):
			var r := src_spec.get_slice("[", 1).trim_suffix("]")
			rng_a = float(r.get_slice("-", 0))
			rng_b = float(r.get_slice("-", 1))
			src_spec = src_spec.get_slice("[", 0)
		if src_spec.contains("@"):
			freeze_at = float(src_spec.get_slice("@", 1))
			src_spec = src_spec.get_slice("@", 0)
		if src_spec.ends_with("~rev"):
			reverse = true
			src_spec = src_spec.trim_suffix("~rev")
		if src_spec.begins_with("mocap:"):
			anim = MocapBake.bake(skeleton, MOCAP_DIR + src_spec.trim_prefix("mocap:") + ".json")
			if anim == null:
				continue
		elif src_spec.contains(":") and not src_spec.ends_with(".fbx"):
			var pid := src_spec.get_slice(":", 0)
			var an := src_spec.get_slice(":", 1)
			var ual: AnimationPlayer = packs.get(pid)
			if ual == null or not ual.has_animation(an):
				push_warning("[character] missing %s clip %s; '%s' unavailable" % [pid, an, clip_name])
				continue
			anim = ual.get_animation(an).duplicate(true)
		else:
			if not ResourceLoader.exists(MIXAMO_DIR + src_spec):
				push_warning("[character] missing clip %s (run tools/setup_local_assets.sh); '%s' unavailable" % [src_spec, clip_name])
				continue
			var src: Node = load(MIXAMO_DIR + src_spec).instantiate()
			var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
			anim = ap.get_animation("mixamo_com").duplicate(true)
			src.free()
		if freeze_at >= 0.0:
			anim = _bake_variant(anim, "freeze", freeze_at)
		elif reverse:
			anim = _bake_variant(anim, "reverse", 0.0)
		elif rng_a >= 0.0:
			anim = _bake_variant(anim, "range", rng_a, rng_b)
		if clip_name.begins_with("rx_"):
			root_curves[clip_name] = _hip_curve(anim)
		_retarget_paths(anim, skel_path, spec[2])
		anim.loop_mode = Animation.LOOP_LINEAR if spec[1] else Animation.LOOP_NONE
		lib.add_animation(clip_name, anim)
	for src_node in pack_srcs:
		src_node.free()
	if lib.has_animation("walk") and lib.has_animation("catwalk"):
		var gw := _blend_cycles(lib.get_animation("walk"), lib.get_animation("catwalk"), 0.5)
		gw.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("walk_goddess", gw)
	if lib.has_animation("catwalk_turn"):
		turn_yaw_curves["catwalk_turn"] = _strip_hip_yaw(lib.get_animation("catwalk_turn"))
	return lib


static var turn_yaw_curves := {}

## The left thigh's most forward swing (largest x of its rotation): the phase anchor of a walk cycle.
static func _cycle_anchor(anim: Animation) -> float:
	var ti := -1
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D and String(anim.track_get_path(t)).ends_with(":LeftUpperLeg"):
			ti = t
	if ti < 0:
		return 0.0
	var best := -INF
	var at := 0.0
	for k in 120:
		var tt := anim.length * k / 120.0
		var q := anim.rotation_track_interpolate(ti, tt)
		if q.x > best:
			best = q.x
			at = tt
	return at


## Two walk cycles blended at weight w (0 = a, 1 = b), sampled by phase from each one's own anchor so the feet stay in
## step: rotations slerped, positions lerped, 30 Hz, length between the two.
static func _blend_cycles(a: Animation, b: Animation, w: float) -> Animation:
	var out := Animation.new()
	var la := a.length
	var lb := b.length
	var L := lerpf(la, lb, w)
	var oa := _cycle_anchor(a)
	var ob := _cycle_anchor(b)
	var paths_b := {}
	for t in b.get_track_count():
		paths_b[str(b.track_get_path(t)) + "|" + str(b.track_get_type(t))] = t
	var step := 1.0 / 30.0
	for ti in a.get_track_count():
		var type := a.track_get_type(ti)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var key := str(a.track_get_path(ti)) + "|" + str(type)
		var tb: int = paths_b.get(key, -1)
		var nt := out.add_track(type)
		out.track_set_path(nt, a.track_get_path(ti))
		var tt := 0.0
		while tt <= L + 1e-4:
			var u := tt / L
			var ta := fmod(oa + u * la, la)
			var tbb := fmod(ob + u * lb, lb)
			if type == Animation.TYPE_POSITION_3D:
				var va := a.position_track_interpolate(ti, ta)
				out.position_track_insert_key(nt, tt, va.lerp(b.position_track_interpolate(tb, tbb), w) if tb >= 0 else va)
			else:
				var qa := a.rotation_track_interpolate(ti, ta)
				out.rotation_track_insert_key(nt, tt, qa.slerp(b.rotation_track_interpolate(tb, tbb), w) if tb >= 0 else qa)
			tt += step
	out.length = L
	return out


## A turn clip's hip yaw is taken out of the clip (the hips keep their pitch and roll) and returned as a curve (radians
## per 1/30 s from the start) for the character's root to follow - she ends the clip facing the new way without the
## blend back to idle snapping her round.
static func _strip_hip_yaw(anim: Animation) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var ti := -1
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D and String(anim.track_get_path(t)).ends_with(":Hips"):
			ti = t
	if ti < 0:
		return out
	var yaw0 := (anim.rotation_track_interpolate(ti, 0.0) * Vector3.FORWARD)
	var a0 := atan2(-yaw0.x, -yaw0.z)
	var prev := 0.0
	var acc := 0.0
	var keys := anim.track_get_key_count(ti)
	# the curve, unwrapped
	var tt := 0.0
	while tt <= anim.length + 1e-4:
		var f := anim.rotation_track_interpolate(ti, tt) * Vector3.FORWARD
		var ang := atan2(-f.x, -f.z) - a0
		var d := wrapf(ang - prev, -PI, PI)
		acc += d
		prev = ang
		out.append(acc)
		tt += 1.0 / 30.0
	# strip it from the keys
	for k in keys:
		var kt := anim.track_get_key_time(ti, k)
		var q: Quaternion = anim.track_get_key_value(ti, k)
		var f := q * Vector3.FORWARD
		var ang := wrapf(atan2(-f.x, -f.z) - a0, -PI, PI)
		anim.track_set_key_value(ti, k, Quaternion(Vector3.UP, -ang) * q)
	return out


## Plays a turn clip with its yaw on her root (see _strip_hip_yaw).
func play_turn(clip := "catwalk_turn", fade_in := 0.3, fade_out := 0.4) -> bool:
	var curve: PackedFloat32Array = turn_yaw_curves.get(clip, PackedFloat32Array())
	if curve.is_empty() or not play_gesture(clip, fade_in, fade_out):
		return false
	# the yaw goes on the avatar node (her own facing logic steers the body's rotation.y and would fight a tween);
	# when the clip ends the turn is handed to the body in one step, invisible because the sum is unchanged
	# (BodyReaction owns the avatar's rest rotation, _avatar_q, and restores it every frame: the turn goes through it)
	var av := avatar
	var base := av.rotation.y
	var set_yaw := func(y: float):
		var q := Quaternion(Vector3.UP, y)
		if reaction and is_instance_valid(reaction):
			reaction.set("_avatar_q", q)
		av.quaternion = q
	var tw := create_tween()
	tw.tween_method(func(i: float): set_yaw.call(base + curve[clampi(int(i), 0, curve.size() - 1)]), 0.0, float(curve.size() - 1), (curve.size() - 1) / 30.0)
	tw.tween_callback(func():
		var total := curve[curve.size() - 1]
		set_yaw.call(base)
		rotation.y += total
		_look_target = global_position - global_transform.basis.z * 3.0)
	return true


## Swap the walk cycle the locomotion uses ("walk", "walk_goddess", ...).
func set_walk_clip(clip: String) -> void:
	if anim_tree and has_clip(clip):
		var loco := (anim_tree.tree_root as AnimationNodeBlendTree).get_node("loco") as AnimationNodeBlendSpace1D
		(loco.get_blend_point_node(1) as AnimationNodeAnimation).animation = "mx/" + clip


## A held pose (freeze at time t, 0.1 s loop) or the clip played backwards, baked at 30 Hz from the sampled
## position/rotation tracks (so blending and retargeting treat it like any other clip).
static func _bake_variant(anim: Animation, mode: String, t: float, t2 := 0.0) -> Animation:
	var out := Animation.new()
	var L := anim.length
	var step := 1.0 / 30.0
	for ti in anim.get_track_count():
		var type := anim.track_get_type(ti)
		if type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_ROTATION_3D:
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, anim.track_get_path(ti))
		if mode == "freeze":
			var tt := clampf(t, 0.0, L)
			if type == Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(nt, 0.0, anim.position_track_interpolate(ti, tt))
				out.position_track_insert_key(nt, 0.1, anim.position_track_interpolate(ti, tt))
			else:
				out.rotation_track_insert_key(nt, 0.0, anim.rotation_track_interpolate(ti, tt))
				out.rotation_track_insert_key(nt, 0.1, anim.rotation_track_interpolate(ti, tt))
		elif mode == "range":
			var tt := 0.0
			var span := clampf(t2, t, L) - t
			while tt <= span + 1e-4:
				var src := clampf(t + tt, 0.0, L)
				if type == Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(nt, tt, anim.position_track_interpolate(ti, src))
				else:
					out.rotation_track_insert_key(nt, tt, anim.rotation_track_interpolate(ti, src))
				tt += step
		else:
			var tt := 0.0
			while tt <= L + 1e-4:
				var src := clampf(L - tt, 0.0, L)
				if type == Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(nt, tt, anim.position_track_interpolate(ti, src))
				else:
					out.rotation_track_insert_key(nt, tt, anim.rotation_track_interpolate(ti, src))
				tt += step
	out.length = 0.1 if mode == "freeze" else ((clampf(t2, t, L) - t) if mode == "range" else L)
	return out


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
	# the reaction layer (BodyReaction): a state machine of impact / fall / recovery clips that crossfade into one
	# another, mixed over everything else by "react_mix" (0 = normal life, 1 = the reaction owns the body)
	var rsm := AnimationNodeStateMachine.new()
	var rnames: Array[String] = []
	for clip in CLIPS:
		if String(clip).begins_with("rx_") or clip in ["hit_chest", "hit_head"]:
			if not body_player.has_animation("mx/" + clip):
				continue
			var an := AnimationNodeAnimation.new()
			an.animation = "mx/" + clip
			rsm.add_node(clip, an, Vector2(rnames.size() * 120, 0))
			rnames.append(clip)
	for a in rnames:
		for b in rnames:
			if a != b:
				var tr := AnimationNodeStateMachineTransition.new()
				tr.xfade_time = 0.3
				tr.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				rsm.add_transition(a, b, tr)
	bt.add_node("react_sm", rsm, Vector2(400, 400))
	bt.add_node("react_speed", AnimationNodeTimeScale.new(), Vector2(550, 400))
	bt.add_node("react_mix", AnimationNodeBlend2.new(), Vector2(700, 0))
	bt.connect_node("react_speed", 0, "react_sm")
	bt.connect_node("react_mix", 0, "cast")
	bt.connect_node("react_mix", 1, "react_speed")
	bt.connect_node("output", 0, "react_mix")
	anim_tree.tree_root = bt
	anim_tree.set("parameters/react_speed/scale", 1.0)
	anim_tree.set("parameters/react_mix/blend_amount", 0.0)
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
	anim_tree.set("parameters/gesture_speed/scale", scale * float(motion.get("gesture_tempo", 1.0)))


func has_clip(clip: String) -> bool:
	return body_player.has_animation("mx/" + clip)


func animation_length(clip: String) -> float:
	return body_player.get_animation("mx/" + clip).length


# ------------------------------------------------------------------ expressions (VRM blend shapes)
func _setup_expressions() -> void:
	_expr.clear()
	_expr_weight.clear()
	_expr_target.clear()
	var cfg: Dictionary = (Progression.mages.get(character_id, {}).get("face", {}) if Progression.mages else {}).duplicate()
	cfg.merge(stage_profile().get("face", {}), true)          # this appearance stage's own face settings
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


var _nav_trace_t := 0


func navigate_to(target: Vector3, run := false) -> void:
	if RenderProfile.options.has("trace-nav") and Time.get_ticks_msec() - _nav_trace_t > 250:
		_nav_trace_t = Time.get_ticks_msec()      # (who sends her where: at most 4 lines a second)
		var st := get_stack()
		print("[navtrace] %s -> %s from %s" % [name, str(target.snapped(Vector3.ONE * 0.1)), " < ".join(st.slice(1, 4).map(func(f): return "%s:%d %s" % [String(f.source).get_file(), int(f.line), String(f.function)]))])
	if reaction and reaction.blocks_actions():
		last_rejection = "recovering from a blow (%s)" % reaction.phase
		action_finished.emit("navigate_to", false, last_rejection)
		return
	if casting:
		action_finished.emit("navigate_to", false, "busy casting")
		return
	if RenderProfile.options.has("trace-nav"):
		var st1 := get_stack()
		print("[trace-nav] %s navigate_to %s by %s" % [character_id, str(target.snappedf(0.1)), " < ".join(st1.slice(1, 4).map(func(f): return "%s:%d %s" % [String(f.source).get_file(), int(f.line), String(f.function)]))])
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
	# as long as the walk really takes (a long road up a mountain), never a flat 90 s; being stuck is caught apart
	var plen := 0.0
	var pth := NavigationServer3D.map_get_path(map, global_position, reachable, true)
	for i in range(1, pth.size()):
		plen += pth[i - 1].distance_to(pth[i])
	_action_deadline = _gclock + maxf(90.0, plen / maxf(run_speed if run else walk_speed, 0.5) * 1.8 + 20.0)
	_begin_action("navigate_to", {"target": [target.x, target.y, target.z], "run": run})


func look_at_point(target: Vector3) -> void:
	_finish_action(false, "superseded by look_at")
	_look_target = target
	_action_deadline = _gclock + 6.0
	_begin_action("look_at", {"target": [target.x, target.y, target.z]})


func stop_action() -> void:
	if casting:
		anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_finish_action(false, "stopped")
	set_move_input(Vector3.ZERO, false)


## Begins a cast; the spell node drives the visuals and calls `end_cast()` when resolved.
func cast_spell(spell_scene: Script, clip := "prepare_and_cast") -> Node:
	anim_tree.set("parameters/gesture_speed/scale", 1.0)   # a dance tempo must never slow a spell
	if reaction and reaction.blocks_actions():
		action_finished.emit("cast_spell", false, "recovering from a blow")
		return null
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
var current_gesture := ""      # the clip of the last gesture started ("" after end_gesture)
var gesture_seq := 0          # counts gestures started (who started what last, cheaply, also on stream)
var gesture_trace := {}         # the last gesture asked for {clip, by, t} (QA: who started what she is doing)


func play_gesture(clip: String, fade_in := 0.35, fade_out := 0.55) -> bool:
	if RenderProfile.options.has("trace-gaze") or RenderProfile.options.has("mktest"):
		var st0 := get_stack()
		gesture_trace = {"clip": clip, "by": ("%s:%d %s" % [String(st0[1].source).get_file(), int(st0[1].line), String(st0[1].function)]) if st0.size() > 1 else "?", "t": Time.get_ticks_msec()}
	if (reaction and reaction.blocks_actions()) or casting or not CLIPS.has(clip) or not has_clip(clip):
		return false
	# lying / sitting on the ground: only the ground's own clips (and reactions, waking). A wave or a point replaced the
	# lying loop and she was drawn standing beside her friend for the rest of a stargaze (stage check 2026-10-17)
	if ground_pose != "" and not (clip.begins_with(ground_pose) or clip.begins_with("rx_") or clip == "waking"):
		return false
	# seated (a bench, the boat): only the seat's own clips and reactions. A level-up dance replaced Luna's sitting loop
	# in the boat and she hovered 21 cm over the cushion, hands off the oars (boat check 2026-10-19)
	if seated and not (clip.begins_with("sit") or clip.begins_with("rx_")):
		return false
	var bt := anim_tree.tree_root as AnimationNodeBlendTree
	var shot := bt.get_node("cast") as AnimationNodeOneShot
	shot.fadein_time = fade_in
	shot.fadeout_time = fade_out
	bt.get_node("cast_anim").animation = "mx/" + clip
	anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	gesture_seq += 1
	current_gesture = clip
	return true


## Ends a looping gesture (seated loop) with the one-shot's fade-out.
func end_gesture() -> void:
	anim_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	current_gesture = ""


## Combat stance (Milestone J): her idle becomes a ready, hands-up stance while a fight is on.
func set_combat_stance(on: bool) -> void:
	if on == combat_stance or anim_tree == null:
		return
	combat_stance = on and has_clip("combat_idle")
	var want := "combat_idle" if combat_stance else "idle"
	# the idle under her is swapped in ONE frame: covered by the same clip played over it first (faded in), swapped
	# underneath, then the cover fades out onto the identical pose - no pop. (Swapped bare, both mages' bodies jumped
	# ~12 cm at the start and the end of every spar, 2026-10-17.)
	var covered := not casting and ground_pose == "" and play_gesture(want, 0.3, 0.35)
	var my_seq := gesture_seq
	if covered:
		await get_tree().create_timer(0.33).timeout
		if combat_stance != (want == "combat_idle"):
			return                                  # changed again meanwhile: that call does the swap
	var loco := (anim_tree.tree_root as AnimationNodeBlendTree).get_node("loco") as AnimationNodeBlendSpace1D
	(loco.get_blend_point_node(0) as AnimationNodeAnimation).animation = "mx/" + want
	if covered and gesture_seq == my_seq:            # nothing else started meanwhile (a cast keeps its clip)
		end_gesture()


## A real evasive move (Milestone J): she turns into the escape direction and rolls/steps there - the
## body actually travels (collision + floor), it is not an animation played in place. Awaitable; returns
## the distance really covered. Refused while casting (a cast is a commitment) or seated.
func dodge(to: Vector3, dur := 0.6) -> float:
	if casting or seated or not is_on_floor() or (reaction and reaction.blocks_actions()):
		return 0.0
	var d := Vector3(to.x - global_position.x, 0, to.z - global_position.z)
	if d.length() < 0.3:
		return 0.0
	_finish_action(false, "superseded by dodge")
	_nav_active = false
	var from := global_position
	# (the old "fights are fast" x0.75 made every spar dodge a blur at 30 FPS: the full duration now)
	_dash = {"dir": d.normalized(), "dist": d.length(), "t": 0.0, "dur": dur, "from": from}
	# (no instant turn: the dash eases her round within ~0.1 s - snapped in one frame, the body jumped 13-45 cm on
	# screen at every dodge of a spar, 2026-10-17)
	_dash_fx(d.normalized(), dur)
	set_gesture_speed(1.35)
	play_gesture("dodge_dash", 0.14, 0.3)
	_begin_action("dodge", {"to": [to.x, to.y, to.z]})
	while not _dash.is_empty():
		await get_tree().physics_frame
	end_gesture()
	set_gesture_speed(1.0)
	var moved := Vector2(global_position.x - from.x, global_position.z - from.z).length()
	_finish_action(moved > 0.5, "dodged %.1f m" % moved)
	return moved


## The dash reads: dust kicked up where she pushes off, a pale wind streak trailing her for the burst.
func _dash_fx(dir: Vector3, dur: float) -> void:
	var host := get_parent()
	if host == null:
		return
	FX.burst(host, global_position + Vector3(0, 0.1, 0), 14, 0.9, FX.pm_puff("dust"), FX.puff_mesh(0.28))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.18, 0.55, 0.18)
	pm.direction = -dir
	pm.spread = 8.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3.ZERO
	pm.color_ramp = FX.ramp([Color(0.9, 0.95, 1.0, 0.0), Color(0.85, 0.92, 1.0, 0.55), Color(0.8, 0.9, 1.0, 0.0)], [0.0, 0.25, 1.0])
	var p := FX.particles(48, 0.35, pm, FX.mote_mesh(0.04, true))
	p.position = Vector3(0, 0.9, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(dur).timeout.connect(func(): if is_instance_valid(p): p.emitting = false)
	get_tree().create_timer(dur + 1.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())


## Struck by a creature (Milestone J): a visible reaction - a flinch for a light blow, a stagger back for a
## heavy one (real push-back through collision). While casting she only flinches (the cast goes on).
## V3 continuation: every blow goes through BodyReaction (flinch / stagger / a real fall and get-up).
func take_hit(from: Vector3, heavy := false, severity := -1.0) -> Dictionary:
	var sev := severity if severity >= 0.0 else (0.7 if heavy else 0.28)
	var r := reaction.receive(from, sev, {"kind": "blow"}) if reaction else {}
	last_hit = {"t": _gclock, "heavy": heavy, "tier": r.get("tier", ""), "severity": sev}
	return r


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
	_gclock += delta
	if cloth_clearance:
		# hands rest folded in front only while they would otherwise hang into the frill: not while she casts,
		# holds something, has the sword out, sits / lies, runs or is knocked about
		var spd := Vector2(velocity.x, velocity.z).length()
		# on a seat (the knees-together correction on, no ground pose): hands on her lap, above the skirt
		cloth_clearance.seated = pose_adjust.influence > 0.5 and pose_adjust.mode == ""
		cloth_clearance.allow = not casting and not (handler and handler.held != null) and not (sword and sword.drawn) \
			and (pose_adjust.influence < 0.05 or cloth_clearance.seated) and spd < walk_speed * 1.35 \
			and not (reaction and reaction.active) and not lifted \
			and not bool(anim_tree.get("parameters/cast/active") if anim_tree else false)   # a gesture / dance owns her arms
	if reaction:
		reaction.physics(delta)
		if reaction.active:
			return                     # the fall / the getting up owns her body
	if lifted:
		velocity = Vector3.ZERO
		anim_tree.set("parameters/loco/blend_position", 0.0)
		return
	var now := _gclock
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
	elif nav_bound and desired.length() > 0.01:
		desired = _keep_on_walkable(desired)
	if casting:
		desired = Vector3.ZERO
	if not _dash.is_empty():
		# a dodge / knock-back: ease-out travel along the chosen line, through collision and floor
		_dash.t = float(_dash.t) + delta
		var k := clampf(float(_dash.t) / float(_dash.dur), 0.0, 1.0)
		# ease in AND out (pi/2 sin(pi k), integral 1): starting at twice the mean speed (2(1-k)) she shot off at
		# ~6.7 m/s in the first frame - a zip, not a dodge (spars, 2026-10-17)
		var v := float(_dash.dist) / float(_dash.dur) * (PI * 0.5) * sin(PI * k)
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
	# how she feels sets her pace: a hurt or tired girl goes slower, an excited one quicker (the gait follows)
	var mood_pace := body_language.tempo() if body_language and is_instance_valid(body_language) else 1.0
	var speed := (run_speed if _run else walk_speed) * pace * mood_pace
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
	if casting and has_meta("cast_target") and is_instance_valid(get_meta("cast_target")):
		# a target that moves while she casts: she keeps turning to it, even while stepping aside (a cast is never
		# thrown sideways or behind her)
		var ct: Node3D = get_meta("cast_target")
		face_dir = ct.global_position - global_position
		face_dir.y = 0
		if face_dir.length() > 0.01:
			face_dir = face_dir.normalized()
		elif hv.length() > 0.2:
			face_dir = hv.normalized()
	elif hv.length() > 0.2:
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
		var to_yaw := lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
		if hv.length() <= 0.2 and not casting:
			# standing: a turn on the spot is a few steps round, never a spin on planted feet (a half turn took 0.3 s,
			# 21 rad/s: the feet were dragged 25-36 cm)
			var d := angle_difference(rotation.y, to_yaw)
			to_yaw = rotation.y + clampf(d, -STAND_TURN * delta, STAND_TURN * delta)
		elif hv.length() > 0.2 and not casting:
			# walking: a turn is a curve, never a whip round (2026-10-23 live: Luna's hair flew when a re-planned path
			# turned her about in a few frames)
			var dm := angle_difference(rotation.y, to_yaw)
			to_yaw = rotation.y + clampf(dm, -MOVE_TURN * delta, MOVE_TURN * delta)
		rotation.y = to_yaw

	# a held LOOPING gesture (a talking idle, folded arms ...) never rides on a moving body: it overrides the whole
	# skeleton, so she would slide along with no walk cycle (2026-10-17 stream). The dodge's sprint is the exception.
	if hv.length() > 0.6 and current_gesture != "" and current_gesture != "dodge_dash" and ground_pose == "" and not lifted \
			and CLIPS.has(current_gesture) and bool(CLIPS[current_gesture][1]) and bool(anim_tree.get("parameters/cast/active")):
		end_gesture()
	# locomotion from the ground she REALLY covers: pressed against a wall, a rail or a friend, velocity can stay up
	# while she does not move - the walk cycle then treads in place (moving platforms carry her: not her own steps)
	var real := get_real_velocity() - get_platform_velocity()
	_update_loco(delta, minf(hv.length(), Vector2(real.x, real.z).length()))


## Locomotion blend (0 idle, 1 walk, 2 run) and the time scale that keeps planted feet planted, from her ground speed.
## Settles into idle quicker than it leaves it: a girl who stops is standing within ~0.3 s, not treading on.
func _update_loco(delta: float, spd: float) -> void:
	if anim_tree == null:
		return
	if spd < 0.05:
		spd = 0.0
	_speed_smoothed = lerpf(_speed_smoothed, spd, 1.0 - exp(-(8.0 if spd > _speed_smoothed else 14.0) * delta))
	if spd == 0.0 and _speed_smoothed < 0.03:
		_speed_smoothed = 0.0
	var blend := 0.0
	if _speed_smoothed < walk_speed:
		# the full walk clip from 85 % of walk speed up (a blend of 7 % idle into it shortened her stride while she
		# travelled at full speed: planted feet slid 0.22 m/s, the walk read as a glide - 2026-10-17)
		blend = clampf(_speed_smoothed / (walk_speed * 0.85), 0.0, 1.0)
	else:
		blend = 1.0 + clampf((_speed_smoothed - walk_speed) / (run_speed - walk_speed), 0.0, 1.0)
	anim_tree.set("parameters/loco/blend_position", blend)
	var ref := 1.0
	if blend > 0.05 and blend <= 1.0:
		# the stride shrinks with the walk's weight in the idle mix: the tempo follows the speed per unit of stride (a slow
		# walk beside a friend at the full tempo slid her planted feet 0.18-0.20 m/s; at this one 0.13 - foot_slide sweep)
		ref = clampf(_speed_smoothed / (blend * walk_speed), 0.6, 1.3)
	elif blend > 1.0:
		ref = clampf(_speed_smoothed / lerpf(walk_speed, run_speed, blend - 1.0), 0.7, 1.25)
	anim_tree.set("parameters/loco_speed/scale", ref * float(motion.get("loco_tempo", 1.0)))


## A hand-steered step that would leave the navmesh slides along its edge instead (toward the nearest walkable
## point ahead), or stops when the edge is square across her way. Off the mesh already (a seat, a ledge) she is left
## alone so she can step back on.
func _keep_on_walkable(d: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0 or RenderProfile.options.has("no-nav-bound"):
		return d
	var here := NavigationServer3D.map_get_closest_point(map, global_position)
	if Vector2(here.x - global_position.x, here.z - global_position.z).length() > 0.6:
		return d
	var dir := d.normalized()
	var ahead := global_position + dir * 0.4
	var on := NavigationServer3D.map_get_closest_point(map, ahead)
	if Vector2(on.x - ahead.x, on.z - ahead.z).length() < 0.15:
		return d
	var slide := Vector3(on.x - global_position.x, 0, on.z - global_position.z)
	if slide.length() < 0.08 or slide.normalized().dot(dir) < 0.25:
		return Vector3.ZERO
	return slide.normalized() * d.length()


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
	_idle_glance(delta)
	if not is_physics_processing():
		# placed, not simulated (a scene stood her there and turned her physics off): she is not walking under her own
		# power, so the locomotion settles into idle - the blend used to freeze on whatever the last physics frame left
		# (Luna treading a walk cycle in place on the pier, 2026-10-19)
		velocity.x = 0.0
		velocity.z = 0.0
		_update_loco(delta, 0.0)


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
