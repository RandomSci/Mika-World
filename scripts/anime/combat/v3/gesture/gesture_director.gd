class_name GestureDirector
extends RefCounted
## Combat v3 gesture director (2026-10-20, Selwyn's body pass step 5): every spell and ultimate gesture is run by a
## LimboAI behaviour tree, one per girl, ticked in fight time by the MeleeSim. The subtree, in order:
##   Cast     HasRequest -> Face (her facing within 15 deg of where the releasing hand must point, before the gather)
##            -> Plant (standing still: her feet settle before the gather; moving: the gesture plays on her upper body
##            only, the fight rig keeps her legs) -> Perform (the clip, blended in over 0.15 s, at her own pace: 0.85 to
##            1.15 of the source) -> Gather (until the release; a hit in it breaks the gesture) -> AimRelease (Godot's
##            AimModifier3D turns her casting arm toward the target round the release frame) -> Recover (the clip
##            ends, the rig takes her back over 0.2 s)
##   Stagger  WasHitInGather -> Stagger (a stagger clip, not the small flinch: her gesture was broken)
## Variations per character: Mika is brisk (a little faster, sharp one hand gestures weighted up), Luna flowing (a
## little slower, two hand gestures weighted up); each cast also varies its pace by a few percent.
## The free hand: while one hand holds a conjured weapon, only gestures cast from the other hand are offered.
## Every cast leaves a row in `log` (the pass or fail gesture table reads it).

const PACE := {"mika": 1.05, "luna": 0.94}
const PACE_JITTER := 0.04
const FACE_DEG := 15.0
const FACE_WAIT := 0.4
const PLANT_WAIT := 0.3
const MOVING := 0.35                      # m/s of her mark: above, the gesture is upper body only
const FADE_IN := 0.15
const FADE_OUT := 0.2
const AIM_BEFORE := 0.15                  # s before the release the arm starts to aim
const AIM_AFTER := 0.25
const AIM_AMOUNT := 0.55                  # how far toward the exact aim (the clip's own shape keeps the rest)
const STAGGER := "hit_heavy_stagger"

var sim: MeleeSim
var st := {}                              # id -> the cast being directed {name, o, g, sp, phase, t_req, ...}
var players := {}                         # id -> BTInstance (the tree, ticked by hand in fight time)
var log: Array = []                       # one row per cast (see _row)
var _last_pos := {}
var speed := {}                           # id -> her mark's speed (m/s, smoothed)
var aims := {}                            # id -> {Left: AimModifier3D, Right: AimModifier3D, target: Node3D}


static func make(s: MeleeSim) -> GestureDirector:
	var g := GestureDirector.new()
	g.sim = s
	for id in s.S:
		g._build(String(id))
	return g


func _build(id: String) -> void:
	var bt := BehaviorTree.new()
	var root := BTSelector.new()
	var cast := BTSequence.new()
	cast.custom_name = "Cast"
	for path in ["bt_has_request", "bt_face", "bt_plant", "bt_perform", "bt_gather", "bt_aim_release", "bt_recover"]:
		cast.add_child(load("res://scripts/anime/combat/v3/gesture/%s.gd" % path).new())
	var stag := BTSequence.new()
	stag.custom_name = "Stagger"
	stag.add_child(load("res://scripts/anime/combat/v3/gesture/bt_was_hit.gd").new())
	stag.add_child(load("res://scripts/anime/combat/v3/gesture/bt_stagger.gd").new())
	root.add_child(cast)
	root.add_child(stag)
	bt.root_task = root
	var host := Node.new()
	host.name = "GestureBrain_" + id
	sim.add_child(host)
	# (a BTInstance straight from the tree: a BTPlayer built in code needs its scene root set by a method in LimboAI
	# 1.8.1, and the fight ticks it by hand in fight time anyway)
	var bb := Blackboard.new()
	bb.set_var(&"gd", self)
	bb.set_var(&"id", id)
	players[id] = bt.instantiate(host, bb, host, host)
	_aim_setup(id)


## The two AimModifier3D of her arms (influence 0 until a release), in the pose pipeline's activity stage.
func _aim_setup(id: String) -> void:
	var f: MeleeFighter = sim.F[id]
	var sk: Skeleton3D = f.sk
	var tg := Node3D.new()
	tg.name = "GestureAimTarget"
	sim.add_child(tg)
	aims[id] = {"target": tg}
	for side in ["Left", "Right"]:
		var am := AimModifier3D.new()
		am.name = "GestureAim_" + side
		am.set_setting_count(1)
		am.set_apply_bone_name(0, side + "UpperArm")
		am.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
		am.set_forward_axis(0, SkeletonModifier3D.BONE_AXIS_PLUS_Y)
		am.set_amount(0, 1.0)
		am.influence = 0.0
		sk.add_child(am)
		am.set_reference_node(0, am.get_path_to(tg))
		aims[id][side] = am
	PosePipeline.arrange_for(sk)


## Ask her to cast `name` at o (the director decides when and how her body does it). False if she is already busy.
func request(s: Dictionary, o: Dictionary, name: String, over := {}) -> bool:
	var id := String(s.id)
	if st.has(id) and String(st[id].phase) != "done":
		return false
	var sp: Dictionary = over if not over.is_empty() else SpellBook.SPELLS[name]
	var g := GestureBook.of(String(sp.clip))
	if g.is_empty():
		return false
	var pace := clampf(float(g.speed) * float(PACE.get(id, 1.0)) * (1.0 + sim.rng.randf_range(-PACE_JITTER, PACE_JITTER)), 0.85, 1.15)
	if bool(sp.get("ultimate", false)):
		pace = float(g.speed)                     # (an ultimate at the source pace: its slow motion is the camera's)
	st[id] = {"name": name, "s": s, "o": o, "over": over, "sp": sp, "g": g, "clip": String(sp.clip), "phase": "face",
		"t_req": sim.t, "pace": pace, "use": String(g.use), "hit_in_gather": false, "row": {}}
	sim.action_starts.append(sim.t)                # (her action starts as she turns and plants for it)
	s.state = "attack"                             # (busy: the sim's choices wait for her gesture)
	return true


## Gestures cast from a hand she holds a weapon in are not offered (her free hand casts).
func hand_free(s: Dictionary, clip: String) -> bool:
	var held := String(s.get("weapon_hand", ""))
	if held == "":
		return true
	var hand := String(GestureBook.of(clip).get("hand", "rh"))
	return hand != held and hand != "both"


## Her weighting of a gesture (variation per character).
func taste(id: String, clip: String) -> float:
	var hand := String(GestureBook.of(clip).get("hand", "rh"))
	if id == "mika":
		return 1.3 if hand in ["rh", "lh"] else 0.85
	return 1.3 if hand == "both" else 0.9


func busy(id: String) -> bool:
	return st.has(id) and String(st[id].phase) != "done"


## Called by the MeleeSim each frame (fight time).
func update(dt: float) -> void:
	for id in sim.S:
		var p: Vector3 = sim.d.pos(id)
		if _last_pos.has(id) and dt > 0.0005:
			var v := MeleeSim._flat(p - (_last_pos[id] as Vector3)).length() / dt
			speed[id] = lerpf(float(speed.get(id, 0.0)), v, 0.3)
		_last_pos[id] = p
	for id in players:
		(players[id] as BTInstance).update(dt)
	for id in aims:
		_aim_follow(String(id))


func _aim_follow(id: String) -> void:
	if not st.has(id):
		return
	var o: Dictionary = st[id].o
	if o.is_empty():
		return
	var of: MeleeFighter = sim.F[o.id]
	(aims[id].target as Node3D).global_position = of.trace.get("UpperChest", sim.d.bone(String(o.id), "UpperChest"))


## Her facing error (deg) from where the gesture needs her to face (the opponent turned by the gesture's aim).
func face_error(id: String) -> float:
	var c: WorldCharacter = sim.d.F[id].c
	var want := FightDirector.yaw_for(c, MeleeSim._flat(sim.d.pos(String(sim.d.F[id].other)) - sim.d.pos(id))) + float(sim.d.F[id].yaw_extra)
	return absf(rad_to_deg(angle_difference(c.rotation.y, want)))


## The releasing hand's direction against the line to the target at this moment (deg).
func aim_error(id: String) -> float:
	var e: Dictionary = st[id]
	var f: MeleeFighter = sim.F[id]
	var side := "Left" if String(e.g.hand) == "lh" else "Right"
	var la: Vector3 = f.trace.get(side + "LowerArm", Vector3.ZERO)
	var h: Vector3 = f.trace.get(side + "Hand", Vector3.ZERO)
	var tgt: Vector3 = (aims[id].target as Node3D).global_position
	if la == h:
		return 180.0
	return rad_to_deg((h - la).angle_to(tgt - h))


func set_aim(id: String, w: float) -> void:
	if not aims.has(id) or not st.has(id):
		return
	var hand := String(st[id].g.hand)
	for side in ["Left", "Right"]:
		var on: bool = (side == "Left" and hand in ["lh", "both"]) or (side == "Right" and hand in ["rh", "both"])
		(aims[id][side] as AimModifier3D).influence = clampf(w, 0.0, 1.0) * AIM_AMOUNT if on else 0.0


func finish(id: String, how: String) -> void:
	if not st.has(id):
		return
	var e: Dictionary = st[id]
	e.phase = "done"
	set_aim(id, 0.0)
	var row: Dictionary = e.row
	row.merge({"id": id, "spell": e.name, "clip": e.clip, "end": how, "pace": snappedf(float(e.pace), 0.01),
		"use": e.use, "t": snappedf(float(e.t_req), 0.01)}, true)
	log.append(row)
	print("[gesture] %s" % JSON.stringify(row))
