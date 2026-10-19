class_name MoveCatalog
extends RefCounted
## Combat v3 move book, part 2: every Move Library clip (v1 31, v2 53, v2 ultimates 20, v3 life 60 = 164), mocapped
## with BlendArMocap's MediaPipe (tools/mocap/extract_landmarks.py -> assets/animations/movelib/<name>.json, baked
## per skeleton by MocapBake, played as "ml_<name>"), tagged for the fight brain, the taunt / mischief system, the
## world-magic and leisure behaviours. The procedural strikes stay in MeleeBook (key poses + IK on the real limb).
##
## use:   "body"  - the full-body mocap plays as is (wide moves, gestures, footwork, reactions read well)
##        "upper" - arms / torso / head from the mocap, legs from the fight rig (the camera crops or the feet slide)
##        "ref"   - timing and key-pose reference for a procedural move: forward strikes lose depth from a front
##                  camera (MediaPipe), so the IK system re-creates them (MeleeBook) at these key times
## who:   both / mika / luna (whose personality it fits best; anyone may still use it)
## tags:  free words the brain filters on: cat words below, plus hands (one / two), height (high / mid / low),
##        energy (small / big), mood (serious / playful / elegant / cheeky), travel, aerial, ground, loop ...
## Props in the clips (bow, stick, lantern, bench, fan) are ignored: mocap reads the body only.

const CLIPS := {
	# ---------------------------------------------------------------------------------------------- v1 (31)
	"dash_palm_strike": {"lib": "v1", "cat": "strike", "use": "ref", "who": "both", "tags": ["attack", "light", "travel", "palm", "rush"]},
	"three_hit_combo": {"lib": "v1", "cat": "combo", "use": "ref", "who": "both", "tags": ["attack", "combo", "punch", "mid"]},
	"front_kick": {"lib": "v1", "cat": "strike", "use": "ref", "who": "both", "tags": ["attack", "light", "kick", "mid"]},
	"crescent_kick": {"lib": "v1", "cat": "strike", "use": "ref", "who": "luna", "tags": ["attack", "heavy", "kick", "high", "elegant"]},
	"spin_back_kick": {"lib": "v1", "cat": "strike", "use": "ref", "who": "both", "tags": ["attack", "heavy", "kick", "spin", "separator"]},
	"jump_spin_kick": {"lib": "v1", "cat": "strike", "use": "body", "who": "mika", "tags": ["attack", "heavy", "kick", "aerial", "spin", "acrobatic"]},
	"low_sweep": {"lib": "v1", "cat": "strike", "use": "ref", "who": "both", "tags": ["attack", "low", "kick", "knockdown"]},
	"uppercut_launcher": {"lib": "v1", "cat": "strike", "use": "ref", "who": "mika", "tags": ["attack", "launcher", "punch", "high"]},
	"overhead_slam": {"lib": "v1", "cat": "strike", "use": "body", "who": "both", "tags": ["attack", "heavy", "aerial", "slam", "two"]},
	"finisher_combo": {"lib": "v1", "cat": "combo", "use": "ref", "who": "both", "tags": ["attack", "finisher", "combo"]},
	"dodge_left": {"lib": "v1", "cat": "evade", "use": "body", "who": "both", "tags": ["dodge", "side", "left"]},
	"dodge_right": {"lib": "v1", "cat": "evade", "use": "body", "who": "both", "tags": ["dodge", "side", "right"]},
	"backstep_evade": {"lib": "v1", "cat": "evade", "use": "body", "who": "both", "tags": ["dodge", "back", "subtle"]},
	"roll_dodge": {"lib": "v1", "cat": "evade", "use": "body", "who": "mika", "tags": ["dodge", "roll", "ground", "acrobatic"]},
	"block_high": {"lib": "v1", "cat": "defence", "use": "upper", "who": "both", "tags": ["block", "high"]},
	"parry_counter": {"lib": "v1", "cat": "defence", "use": "upper", "who": "luna", "tags": ["parry", "counter", "elegant"]},
	"cast_one_hand": {"lib": "v1", "cat": "spell", "use": "body", "who": "both", "tags": ["cast", "one", "small", "bolt"]},
	"cast_two_hand_blast": {"lib": "v1", "cat": "spell", "use": "body", "who": "both", "tags": ["cast", "two", "big", "blast"]},
	"beam_channel": {"lib": "v1", "cat": "spell", "use": "body", "who": "both", "tags": ["cast", "two", "beam", "hold", "loop"]},
	"charge_up": {"lib": "v1", "cat": "spell", "use": "body", "who": "both", "tags": ["charge", "big", "stance_change"]},
	"hit_light": {"lib": "v1", "cat": "reaction", "use": "upper", "who": "both", "tags": ["hit", "light", "flinch", "subtle"]},
	"hit_heavy_stagger": {"lib": "v1", "cat": "reaction", "use": "body", "who": "both", "tags": ["hit", "heavy", "stagger", "back"]},
	"knockdown_getup": {"lib": "v1", "cat": "reaction", "use": "body", "who": "both", "tags": ["knockdown", "getup", "ground"], "note": "camera jump in the second half"},
	"fight_idle": {"lib": "v1", "cat": "stance", "use": "upper", "who": "both", "tags": ["stance", "loop", "idle"]},
	"taunt_beckon": {"lib": "v1", "cat": "taunt", "use": "body", "who": "both", "tags": ["taunt", "beckon", "cheeky", "one"]},
	"victory_pose": {"lib": "v1", "cat": "emote", "use": "body", "who": "both", "tags": ["victory", "aftermath"]},
	"rowing_seated": {"lib": "v1", "cat": "activity", "use": "body", "who": "both", "tags": ["boat", "seated", "loop"]},
	"release_lantern": {"lib": "v1", "cat": "activity", "use": "body", "who": "both", "tags": ["lantern", "two", "gentle"]},
	"stargaze_point": {"lib": "v1", "cat": "activity", "use": "body", "who": "both", "tags": ["point", "sky", "one"]},
	"sit_lean_back_gaze": {"lib": "v1", "cat": "activity", "use": "body", "who": "both", "tags": ["seated", "gaze", "loop"]},
	"bow_greeting": {"lib": "v1", "cat": "emote", "use": "body", "who": "both", "tags": ["greet", "bow", "respect"]},
	# ---------------------------------------------------------------------------------------------- v2 spell gestures (18)
	"sign_weave_fast": {"lib": "v2", "cat": "spell", "use": "upper", "who": "mika", "tags": ["cast", "two", "sign", "fast", "gather"]},
	"domain_expand": {"lib": "v2", "cat": "spell", "use": "body", "who": "both", "tags": ["cast", "two", "big", "domain", "ultimate_part"]},
	"array_ground_summon": {"lib": "v2", "cat": "spell", "use": "body", "who": "luna", "tags": ["cast", "one", "ground", "array", "kneel", "big"]},
	"array_air_draw": {"lib": "v2", "cat": "spell", "use": "upper", "who": "luna", "tags": ["cast", "one", "draw", "array", "elegant"]},
	"sky_call_point": {"lib": "v2", "cat": "spell", "use": "body", "who": "mika", "tags": ["cast", "one", "sky", "point", "meteor"]},
	"orb_gather": {"lib": "v2", "cat": "spell", "use": "upper", "who": "both", "tags": ["cast", "two", "orb", "gather", "small"]},
	"spear_conjure_throw": {"lib": "v2", "cat": "weapon", "use": "body", "who": "mika", "tags": ["conjure", "spear", "throw", "one", "star_spear"]},
	"barrier_raise": {"lib": "v2", "cat": "spell", "use": "body", "who": "luna", "tags": ["cast", "two", "barrier", "defence", "wide"]},
	"arm_sweep_wave": {"lib": "v2", "cat": "spell", "use": "body", "who": "both", "tags": ["cast", "one", "wave", "sweep", "wide"]},
	"finger_snap_point": {"lib": "v2", "cat": "taunt", "use": "upper", "who": "mika", "tags": ["taunt", "snap", "point", "cheeky", "cast", "one", "small"]},
	"pillar_raise": {"lib": "v2", "cat": "spell", "use": "upper", "who": "luna", "tags": ["cast", "two", "pillar", "ground", "rise", "big"], "note": "camera moves in: legs from the rig"},
	"stomp_cast": {"lib": "v2", "cat": "spell", "use": "body", "who": "mika", "tags": ["cast", "stomp", "ground", "spikes", "ice"]},
	"vortex_spin_cast": {"lib": "v2", "cat": "spell", "use": "body", "who": "luna", "tags": ["cast", "two", "spin", "vortex", "elegant"]},
	"iaido_draw_slash": {"lib": "v2", "cat": "weapon", "use": "body", "who": "mika", "tags": ["conjure", "blade", "draw", "slash", "ice_blade"]},
	"sword_combo_invisible": {"lib": "v2", "cat": "weapon", "use": "body", "who": "mika", "tags": ["blade", "combo", "slash", "ice_blade"]},
	"bow_draw_release": {"lib": "v2", "cat": "weapon", "use": "body", "who": "mika", "tags": ["conjure", "bow", "shoot", "ranged"]},
	"meteor_call": {"lib": "v2", "cat": "spell", "use": "body", "who": "mika", "tags": ["cast", "two", "sky", "meteor", "big"]},
	"seal_finish": {"lib": "v2", "cat": "spell", "use": "upper", "who": "luna", "tags": ["sign", "two", "seal", "finish", "elegant"]},
	# ---------------------------------------------------------------------------------------------- v2 ultimates basic (3)
	"ultimate_charge": {"lib": "v2", "cat": "ultimate_part", "use": "body", "who": "both", "tags": ["charge", "two", "big", "stance_change", "wind"]},
	"ultimate_release": {"lib": "v2", "cat": "ultimate_part", "use": "body", "who": "both", "tags": ["release", "two", "big", "push"]},
	"ultimate_rising_strike": {"lib": "v2", "cat": "ultimate_part", "use": "body", "who": "both", "tags": ["rise", "aerial", "strike", "big"]},
	# ---------------------------------------------------------------------------------------------- v2 footwork (10)
	"footwork_shuffle_advance": {"lib": "v2", "cat": "footwork", "use": "body", "who": "both", "tags": ["step", "forward", "loop"]},
	"footwork_strafe_left": {"lib": "v2", "cat": "footwork", "use": "body", "who": "both", "tags": ["step", "left", "circle"]},
	"footwork_strafe_right": {"lib": "v2", "cat": "footwork", "use": "body", "who": "both", "tags": ["step", "right", "circle"]},
	"footwork_switch_stance": {"lib": "v2", "cat": "footwork", "use": "body", "who": "both", "tags": ["switch", "stance"]},
	"footwork_retreat": {"lib": "v2", "cat": "footwork", "use": "body", "who": "both", "tags": ["step", "back"]},
	"lunge_dash_in": {"lib": "v2", "cat": "footwork", "use": "body", "who": "both", "tags": ["dash", "forward", "low", "rush", "travel"]},
	"slide_low_dash": {"lib": "v2", "cat": "footwork", "use": "body", "who": "mika", "tags": ["dash", "slide", "low", "ground", "travel"]},
	"cartwheel_evade": {"lib": "v2", "cat": "evade", "use": "upper", "who": "mika", "tags": ["dodge", "side", "acrobatic", "aerial", "playful"], "note": "legs unreliable in the source (leg length varies 15 %): legs from the rig"},
	"backflip_evade": {"lib": "v2", "cat": "evade", "use": "body", "who": "mika", "tags": ["dodge", "back", "acrobatic", "aerial", "flip"]},
	"aerial_flip_kick": {"lib": "v2", "cat": "strike", "use": "body", "who": "mika", "tags": ["attack", "kick", "aerial", "flip", "acrobatic", "launcher"]},
	# ---------------------------------------------------------------------------------------------- v2 combos and strikes (10)
	"combo_jab_cross_hook": {"lib": "v2", "cat": "combo", "use": "ref", "who": "mika", "tags": ["attack", "combo", "punch", "fast"]},
	"combo_kick_punch_spin": {"lib": "v2", "cat": "combo", "use": "ref", "who": "both", "tags": ["attack", "combo", "kick", "punch", "spin"]},
	"combo_elbow_knee": {"lib": "v2", "cat": "combo", "use": "ref", "who": "both", "tags": ["attack", "combo", "elbow", "knee", "close"]},
	"combo_launcher_air": {"lib": "v2", "cat": "combo", "use": "body", "who": "mika", "tags": ["attack", "combo", "launcher", "aerial", "jump"]},
	"combo_palm_flurry": {"lib": "v2", "cat": "combo", "use": "ref", "who": "luna", "tags": ["attack", "combo", "palm", "fast", "elegant"]},
	"combo_sweep_axe": {"lib": "v2", "cat": "combo", "use": "body", "who": "both", "tags": ["attack", "combo", "sweep", "axe", "low", "high"]},
	"axe_kick": {"lib": "v2", "cat": "strike", "use": "ref", "who": "both", "tags": ["attack", "heavy", "kick", "high", "chop"]},
	"hook_kick": {"lib": "v2", "cat": "strike", "use": "ref", "who": "luna", "tags": ["attack", "heavy", "kick", "high", "spin", "elegant"]},
	"jump_knee": {"lib": "v2", "cat": "strike", "use": "body", "who": "mika", "tags": ["attack", "knee", "aerial", "jump", "close"]},
	"double_palm_push": {"lib": "v2", "cat": "strike", "use": "ref", "who": "luna", "tags": ["attack", "palm", "two", "push", "separator"]},
	# ---------------------------------------------------------------------------------------------- v2 defence and reactions (9)
	"block_low": {"lib": "v2", "cat": "defence", "use": "upper", "who": "both", "tags": ["block", "low"]},
	"block_side_left": {"lib": "v2", "cat": "defence", "use": "upper", "who": "both", "tags": ["block", "side", "left"]},
	"block_side_right": {"lib": "v2", "cat": "defence", "use": "upper", "who": "both", "tags": ["block", "side", "right"]},
	"duck_under": {"lib": "v2", "cat": "evade", "use": "body", "who": "both", "tags": ["dodge", "duck", "low"]},
	"lean_back_dodge": {"lib": "v2", "cat": "evade", "use": "body", "who": "luna", "tags": ["dodge", "lean", "back", "high", "elegant"]},
	"hit_from_left": {"lib": "v2", "cat": "reaction", "use": "body", "who": "both", "tags": ["hit", "medium", "side", "left"]},
	"hit_from_right": {"lib": "v2", "cat": "reaction", "use": "body", "who": "both", "tags": ["hit", "medium", "side", "right"]},
	"guard_break_stagger": {"lib": "v2", "cat": "reaction", "use": "body", "who": "both", "tags": ["guard_break", "stagger", "block"]},
	"launched_land": {"lib": "v2", "cat": "reaction", "use": "upper", "who": "both", "tags": ["launch", "air", "flip", "landing", "hard"], "note": "legs unreliable in the source (leg length varies 17 %): legs from the rig"},
	# ---------------------------------------------------------------------------------------------- v2 teamwork (3)
	"cover_step_in": {"lib": "v2", "cat": "team", "use": "body", "who": "both", "tags": ["team", "cover", "protect", "step"]},
	"boost_hands_cupped": {"lib": "v2", "cat": "team", "use": "body", "who": "both", "tags": ["team", "boost", "launch_partner", "two", "crouch"]},
	"call_partner_signal": {"lib": "v2", "cat": "team", "use": "upper", "who": "both", "tags": ["team", "call", "signal", "one"]},
	# ---------------------------------------------------------------------------------------------- v2 ultimates (20): see ULTIMATES
	"ult_starfall_conductor": {"lib": "v2u", "cat": "ultimate", "use": "upper", "who": "mika", "tags": ["ultimate", "two", "sky", "star"], "note": "opens close on her: legs from the rig for the first second"},
	"ult_moon_crescent_cleave": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "luna", "tags": ["ultimate", "weapon", "scythe", "slash", "moon"]},
	"ult_frozen_spike_field": {"lib": "v2u", "cat": "ultimate", "use": "upper", "who": "mika", "tags": ["ultimate", "ground", "ice", "spikes", "kneel"], "note": "opens close (crouched): legs unreliable in the source (leg length varies 11 %), legs from the rig"},
	"ult_twin_hand_sigil": {"lib": "v2u", "cat": "ultimate", "use": "upper", "who": "luna", "tags": ["ultimate", "sign", "two", "sigil"]},
	"ult_spiral_ascension": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "mika", "tags": ["ultimate", "spin", "rise", "ice", "aerial"]},
	"ult_heaven_spear": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "mika", "tags": ["ultimate", "weapon", "spear", "throw", "star_spear"]},
	"ult_blooming_domain": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "luna", "tags": ["ultimate", "domain", "kneel", "rise", "flowers"]},
	"ult_thousand_palms": {"lib": "v2u", "cat": "ultimate", "use": "ref", "who": "mika", "tags": ["ultimate", "palm", "flurry", "fast", "close"]},
	"ult_eclipse_ring": {"lib": "v2u", "cat": "ultimate", "use": "upper", "who": "luna", "tags": ["ultimate", "ring", "moon", "two"]},
	"ult_comet_dive_kick": {"lib": "v2u", "cat": "ultimate", "use": "upper", "who": "mika", "tags": ["ultimate", "kick", "aerial", "dive", "acrobatic"], "note": "legs unreliable in the source (leg length varies 15 %): legs from the rig"},
	"ult_mirror_afterimage": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "luna", "tags": ["ultimate", "afterimage", "dash", "precise"]},
	"ult_gravity_press": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "luna", "tags": ["ultimate", "gravity", "one", "press", "ground"]},
	"ult_lunar_waltz": {"lib": "v2u", "cat": "ultimate", "use": "upper", "who": "luna", "tags": ["ultimate", "spin", "dance", "elegant", "moon"], "note": "ends in a close-up: legs from the rig after 3.5 s"},
	"ult_sky_rending_slash": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "luna", "tags": ["ultimate", "slash", "overhead", "two", "kneel_finish"]},
	"ult_crossed_arms_burst": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "mika", "tags": ["ultimate", "burst", "two", "nova"]},
	"ult_final_seal_bow": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "luna", "tags": ["ultimate", "seal", "bow", "elegant", "finisher"]},
	"ult_storm_rider_flip": {"lib": "v2u", "cat": "ultimate", "use": "upper", "who": "mika", "tags": ["ultimate", "flip", "aerial", "acrobatic", "landing"], "note": "legs unreliable in the source (leg length varies 11 %): legs from the rig"},
	"ult_star_archer": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "mika", "tags": ["ultimate", "bow", "shoot", "star"]},
	"ult_duo_back_to_back_left": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "both", "tags": ["ultimate", "duo", "back_to_back", "mirror_for_partner"]},
	"ult_duo_hand_join_push": {"lib": "v2u", "cat": "ultimate", "use": "body", "who": "both", "tags": ["ultimate", "duo", "hand_join", "push", "mirror_for_partner"]},
	# ---------------------------------------------------------------------------------------------- v3 dance for the lake song (20)
	"dance_arm_wave_flow": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "arms", "wave", "loop"]},
	"dance_wrist_sway": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "wrist", "sway"]},
	"dance_turn_open": {"lib": "v3", "cat": "dance", "use": "upper", "who": "both", "tags": ["dance", "turn", "open_arms"], "note": "camera pushes in at the end"},
	"dance_reach_moon": {"lib": "v3", "cat": "dance", "use": "body", "who": "luna", "tags": ["dance", "reach", "sky", "moon"]},
	"dance_cup_light": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "cup", "light", "two"]},
	"dance_lantern_lift": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "lantern", "lift", "prop"]},
	"dance_lantern_spin": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "lantern", "spin", "prop"]},
	"dance_kneel_bloom": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "kneel", "bloom", "rise"]},
	"dance_soft_pirouette": {"lib": "v3", "cat": "dance", "use": "body", "who": "luna", "tags": ["dance", "pirouette", "spin", "elegant"]},
	"dance_side_step_trail": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "step", "side", "trail"]},
	"dance_fan_sweep": {"lib": "v3", "cat": "dance", "use": "body", "who": "luna", "tags": ["dance", "fan", "sweep", "prop"]},
	"dance_mirror_left": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "mirror", "partner_half"]},
	"dance_twirl_hand_held": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "twirl", "partner_half", "hand_held"]},
	"dance_back_to_back": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "back_to_back", "partner_half"]},
	"dance_sway_step": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "sway", "step", "loop"]},
	"dance_spiral_down": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "spiral", "low"]},
	"dance_climax_pose": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "climax", "leap", "pose"]},
	"dance_end_bow": {"lib": "v3", "cat": "dance", "use": "body", "who": "both", "tags": ["dance", "end", "bow"]},
	"dance_hair_toss_turn": {"lib": "v3", "cat": "taunt", "use": "upper", "who": "luna", "tags": ["dance", "hair_toss", "turn", "taunt", "elegant", "cheeky"], "note": "ends in a close-up"},
	"dance_skip_circle": {"lib": "v3", "cat": "dance", "use": "body", "who": "mika", "tags": ["dance", "skip", "circle", "playful"]},
	# ---------------------------------------------------------------------------------------------- v3 leisure (12)
	"stroll_look_around": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["walk", "look", "loop"]},
	"smell_flower": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["flower", "bend", "smell"]},
	"pick_flower_tuck_hair": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["flower", "pick", "hair", "crouch"]},
	"touch_tree_bark": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["tree", "touch", "one"]},
	"lean_rail_view": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["lean", "view", "rest"]},
	"stretch_arms_sky": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["stretch", "sky", "two"]},
	"sit_dangle_feet": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["seated", "dangle", "loop", "bench"]},
	"lie_down_grass": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["lie", "ground", "rest"]},
	"catch_falling_petal": {"lib": "v3", "cat": "leisure", "use": "body", "who": "both", "tags": ["petal", "catch", "two"]},
	"dip_hand_water": {"lib": "v3", "cat": "leisure", "use": "upper", "who": "both", "tags": ["water", "kneel", "dip"], "note": "close, kneeling"},
	"photo_frame_hands": {"lib": "v3", "cat": "leisure", "use": "upper", "who": "both", "tags": ["photo", "frame", "two"]},
	"wave_hello_far": {"lib": "v3", "cat": "emote", "use": "body", "who": "both", "tags": ["wave", "greet", "far", "one"]},
	# ---------------------------------------------------------------------------------------------- v3 shaping the world (12)
	"cast_grow_plants": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "luna", "tags": ["cast", "grow", "plants", "crouch", "rise"]},
	"cast_water_rise": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "both", "tags": ["cast", "water", "rise", "two"]},
	"cast_water_walk": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "both", "tags": ["cast", "water", "walk", "loop"]},
	"cast_light_orbs_scatter": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "mika", "tags": ["cast", "orbs", "scatter", "light"]},
	"cast_build_shape": {"lib": "v3", "cat": "world_magic", "use": "upper", "who": "both", "tags": ["cast", "build", "shape", "two"]},
	"cast_stone_lift": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "both", "tags": ["cast", "stone", "lift", "one"]},
	"cast_bridge_draw": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "luna", "tags": ["cast", "bridge", "draw", "one", "wide"]},
	"cast_rain_call": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "luna", "tags": ["cast", "rain", "sky", "two"]},
	"cast_fireflies_release": {"lib": "v3", "cat": "world_magic", "use": "upper", "who": "both", "tags": ["cast", "fireflies", "seated", "release"], "note": "kneeling, close"},
	"cast_flower_ring": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "luna", "tags": ["cast", "flowers", "ring", "spin"]},
	"cast_wind_gust": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "mika", "tags": ["cast", "wind", "gust", "push"]},
	"cast_ice_sculpture": {"lib": "v3", "cat": "world_magic", "use": "body", "who": "mika", "tags": ["cast", "ice", "sculpture", "one"]},
	# ---------------------------------------------------------------------------------------------- v3 playful mischief (16)
	"poke_tree_laugh": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["poke", "laugh", "playful"]},
	"kick_tree_shake": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["kick", "tree", "terrain", "playful"]},
	"punch_tree_ouch": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["punch", "tree", "ouch", "silly"]},
	"sneak_up_scare": {"lib": "v3", "cat": "mischief", "use": "upper", "who": "mika", "tags": ["sneak", "scare", "playful"], "note": "ends close"},
	"splash_water_tease": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["splash", "water", "tease", "terrain", "cheeky"]},
	"throw_pebble_skip": {"lib": "v3", "cat": "mischief", "use": "body", "who": "both", "tags": ["throw", "pebble", "water"]},
	"tickle_magic_poke": {"lib": "v3", "cat": "mischief", "use": "body", "who": "both", "tags": ["tickle", "magic", "poke", "cheeky", "sparkles"]},
	"pull_hair_tease": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["pull", "hair", "ribbon", "tease", "cheeky"]},
	"hide_behind_peek": {"lib": "v3", "cat": "mischief", "use": "body", "who": "both", "tags": ["hide", "peek", "cover", "terrain"]},
	"spin_dizzy_fall": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["spin", "dizzy", "fall", "silly", "pout_ground"]},
	"jump_puddle": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["jump", "puddle", "water", "playful"]},
	"stick_sword_play": {"lib": "v3", "cat": "mischief", "use": "body", "who": "mika", "tags": ["sword", "play", "prop", "playful"]},
	"roll_eyes_shove": {"lib": "v3", "cat": "taunt", "use": "body", "who": "luna", "tags": ["taunt", "roll_eyes", "shove", "cheeky"]},
	"chase_run_laugh": {"lib": "v3", "cat": "mischief", "use": "body", "who": "both", "tags": ["run", "chase", "laugh", "travel"]},
	"blow_raspberry_run": {"lib": "v3", "cat": "taunt", "use": "body", "who": "mika", "tags": ["taunt", "raspberry", "tongue", "run", "cheeky"]},
	"victory_dance_silly": {"lib": "v3", "cat": "taunt", "use": "body", "who": "mika", "tags": ["taunt", "victory", "dance", "silly", "aftermath"]},
}


## The ultimates: name on screen, owner, when it may fire, and its camera and effect plan (Phantom Camera shots, the
## time / light / world changes, the layered effect). Every ultimate runs 3 - 6 s: charge (time slows, the sky turns
## to her colour) -> close-ups (eyes, hands forming the sign, low hero angle) -> grand release (shaped effect, flash
## pair, ground shockwave, the camera pulls back wide) -> aftermath (frozen / scorched decal, a beat of silence).
## Earned only: her meter full, or her health under 30 %. Mika ice blue + star white; Luna violet + moon silver.
const ULTIMATES := {
	"ult_starfall_conductor": {"name": "Starfall Conductor", "owner": "mika",
		"camera": "crash zoom to her eyes -> low hero angle as both arms rise -> wide overhead as the stars fall",
		"effect": "sky darkens ice blue; star points gather at both fingertips; arms conduct a rain of shaped star shards that land in a ring with frost bursts; ground frost decal"},
	"ult_frozen_spike_field": {"name": "Glacier Thorn Field", "owner": "mika",
		"camera": "close on her palm touching the ground -> overhead as the spike field spreads -> low wide past the spikes",
		"effect": "frost runs out from her palm in a noise-dissolve ring; faceted ice spikes erupt in waves toward the target; shatter sparks; frozen ground decal that thaws over 20 s"},
	"ult_heaven_spear": {"name": "Heaven's Star Spear", "owner": "mika",
		"camera": "low hero angle as she raises her hand -> close on the spear forming in her grip -> tracking shot along the throw -> wide impact",
		"effect": "a star spear conjured from light (draw effect from the hand, a shaped mesh with a bright core and soft edge), a long trail on the throw, a flash pair and a star-shaped crater shockwave"},
	"ult_comet_dive_kick": {"name": "Comet Dive", "owner": "mika",
		"camera": "tracking shot up with her jump -> brief hang-time freeze from below -> whip down with the dive -> wide shockwave",
		"effect": "ice-blue comet trail from her kicking leg (GPUTrail), afterimages on the rise, an impact frame on landing, a crater ring of frost and dust"},
	"ult_storm_rider_flip": {"name": "Aurora Storm Rider", "owner": "mika",
		"camera": "orbit around her flip -> slow motion at the top -> tracking low as she lands",
		"effect": "aurora ribbons trail her limbs through the flip, wind blows her hair and skirt, a star-burst landing ring, sparkles kicked up"},
	"ult_star_archer": {"name": "Polaris Archer", "owner": "mika",
		"camera": "over the shoulder down the drawn bow -> close on her eye along the arrow -> wide as the arrow splits into a star volley",
		"effect": "a bow conjured from starlight (dissolves after), an arrow of light that splits into a fan of star bolts, each leaving a trail and frost hit sparks"},
	"ult_thousand_palms": {"name": "Thousand Star Palms", "owner": "mika",
		"camera": "medium two-shot from the side -> speed ramp into the flurry -> held key pose on the final palm -> wide knockback",
		"effect": "afterimage palms (pooled ghosts), small star bursts on every contact, a final big palm with a shaped shockwave cone and impact flash"},
	"ult_crossed_arms_burst": {"name": "Nova Burst", "owner": "mika",
		"camera": "close on her crossed arms -> low hero angle -> camera knocked back wide as the nova blooms",
		"effect": "energy gathers in the crossed forearms, the arms throw open into a spherical star-ice nova (layered shell + sparks + light), ground shockwave flattens grass"},
	"ult_spiral_ascension": {"name": "Spiral Ascension", "owner": "mika",
		"camera": "low angle orbit as she spins -> tilt up following the spiral -> wide as the ice spiral peaks",
		"effect": "an ice spiral climbs around her spin into the sky, snow swirl particles, a falling frost ring when it breaks"},
	"ult_moon_crescent_cleave": {"name": "Crescent Moon Cleave", "owner": "luna",
		"camera": "close on her hand as the violet scythe forms -> low hero angle on the raised blade -> whip pan with the cleave -> wide on the crescent wave",
		"effect": "a violet scythe conjured from moonlight (draw effect, dissolves after), a crescent slash wave (shaped mesh, noise dissolve edge), moon-silver sparks, a scorched crescent decal"},
	"ult_eclipse_ring": {"name": "Eclipse Ring", "owner": "luna",
		"camera": "close on her eyes -> hands forming the ring sign -> wide as the eclipse ring expands",
		"effect": "a black-violet eclipse disc with a silver corona rises behind her, a ring shockwave expands across the ground, the light dims to violet during the charge"},
	"ult_lunar_waltz": {"name": "Lunar Waltz", "owner": "luna",
		"camera": "orbit with her waltz -> slow motion on the last turn -> close on her outstretched hand -> wide on the release",
		"effect": "moon petals and violet ribbons trail her spins, each turn leaves a crescent afterimage, the final turn releases a ring of moon blades"},
	"ult_gravity_press": {"name": "Violet Gravity Press", "owner": "luna",
		"camera": "low hero angle as her hand rises -> overhead as she presses down -> wide on the crater",
		"effect": "a violet gravity well (distorted dark sphere with a bright rim) slams onto the target, the ground cracks in a ring, debris lifts and falls"},
	"ult_blooming_domain": {"name": "Moonlit Blooming Domain", "owner": "luna",
		"camera": "close on her clasped hands while kneeling -> rising with her -> wide overhead as the domain blooms",
		"effect": "the domain: the sky turns deep violet, a moon rises, a flower ring of light blooms outward across the ground, fireflies and petals; it stays for the climax"},
	"ult_mirror_afterimage": {"name": "Mirror of the Moon", "owner": "luna",
		"camera": "medium side two-shot -> freeze as the mirror images appear -> whip pans between strikes -> wide",
		"effect": "silver mirror afterimages (pooled ghosts) strike from several sides, each strike a crescent spark, the images shatter like glass at the end"},
	"ult_sky_rending_slash": {"name": "Sky-Rending Crescent", "owner": "luna",
		"camera": "low angle as both arms rise overhead -> crash zoom to her eyes -> wide as the sky splits",
		"effect": "a vertical violet crescent slash splits the sky (impact frame: white then inverted), a line of light cuts the ground, wind and dust blast outward"},
	"ult_final_seal_bow": {"name": "Final Seal", "owner": "luna",
		"camera": "close on her hands forming the final sign -> medium as she bows -> wide as the seal locks",
		"effect": "a moon-sigil circle seals around the target with runic rings, a silver flash pair, then calm: petals drift down in the silence"},
	"ult_twin_hand_sigil": {"name": "Twin Sigil of Night", "owner": "luna",
		"camera": "close on each hand drawing a sigil (split screen) -> low hero -> wide as the sigils fire",
		"effect": "two violet sigils drawn in the air by her hands, each fires a moon beam (bright core, soft violet edge) that cross at the target"},
	"ult_duo_back_to_back_left": {"name": "Twin Stars, One Sky", "owner": "duo",
		"camera": "orbit around both back to back -> split close-up (Mika's eyes left, Luna's eyes right) -> wide as both arms point out",
		"effect": "ice-blue and violet auras rise and merge into a white-silver spiral, both fire at once from opposite sides, the beams braid into one; Luna plays the mirrored clip"},
	"ult_duo_hand_join_push": {"name": "Binary Star Push", "owner": "duo",
		"camera": "close on their joined hands -> low hero two-shot -> camera pulled back wide by the blast",
		"effect": "their joined hands gather blue and violet light that merges into one binary star, pushed out as a huge shaped blast with a flash pair and a ground shockwave; Luna plays the mirrored clip"},
}


static func clip(name: String) -> Dictionary:
	return CLIPS.get(name, {})


## Every clip whose tags hold all of `want` (and, given, whose category is `cat` / fits `who`).
static func find(want: Array, cat := "", who := "") -> Array:
	var out := []
	for n in CLIPS:
		var c: Dictionary = CLIPS[n]
		if cat != "" and String(c.cat) != cat:
			continue
		if who != "" and not (String(c.who) in ["both", who]):
			continue
		var ok := true
		for w in want:
			if not (w in (c.tags as Array)) and String(c.cat) != String(w):
				ok = false
				break
		if ok:
			out.append(n)
	return out


## The ultimates a girl may use (her own and the duo ones).
static func ultimates_of(who: String) -> Array:
	var out := []
	for n in ULTIMATES:
		if String(ULTIMATES[n].owner) in [who, "duo"]:
			out.append(n)
	return out
