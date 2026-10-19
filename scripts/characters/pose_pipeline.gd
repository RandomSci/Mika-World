class_name PosePipeline
extends Node
## The one owner of her final pose (2026-10-19, Selwyn approved: "a single pose pipeline with one owner and a clear
## order (activity pose, then IK, then collision, then cloth) and remove the stacked correctors").
##
## Every pose modifier on her skeleton belongs to exactly one stage, and this node alone decides their order:
##   1 ACTIVITY  the clip and what shapes it: the dance/fight decks, body language, the seated knee turn, breathing
##               and overlap (BodyLife), the softness pass on arms (SoftArms)
##   2 IK        where hands, feet and eyes must be: the seated reach/feet (SeatPose), hands resting at her waist or
##               lap (ClothClearance), feet on the floor (FootGuard), the head and eye look-at, head posture,
##               held-object arm IK, ears
##   3 COLLISION hands never inside a body (HandGuard)
##   4 CLOTH     the skirt sim, the drape, cords, (the VRM springs always run last)
## and it settles the overlaps that used to fight each other, every frame:
##   - one look owner: an activity's gaze target drives the head/eye look-at (BodyLife no longer turns the head);
##   - the seated feet IK owns the feet (FootGuard steps back while it is on);
##   - an action's reach owns that hand (ClothClearance lets go of it, HandGuard does not push it off its target);
##   - seated outfit state: while she sits, the long skirt panels fold away past SEATED_PANEL m (no floor-length
##     cloth through seats, hulls or the other girl).
## Anyone adding a pose modifier calls PosePipeline.of(character).arrange() - nothing else reorders the skeleton.

const STAGES := {
	"DanceDeck": 10, "FightDeck": 11, "BodyLanguage": 12, "PoseAdjust": 13, "BodyLife": 14, "SoftArms": 15,
	"FightBody": 16, "FightIK": 17, "FightBodyPost": 18,
	"SeatPose": 20, "ClothClearance": 21, "FootGuard": 22, "FootLock": 22, "HeadLook": 23, "EyeLook_LeftEye": 24, "EyeLook_RightEye": 25,
	"HeadPosture": 26, "RightArmIK": 27, "LeftArmIK": 28, "EarController": 29,
	"HandGuard": 30,
	"DressSim": 40, "DressSprings": 41, "DressSpeedLimit": 42, "SkirtDrape": 43, "TasselSway": 44,
}
const SEATED_PANEL := 0.42               # m of each skirt panel kept while seated (lap and over the seat's edge)

var c: Node                              # the WorldCharacter
var look: Callable                       # an activity's gaze: () -> world point or Vector3.INF
var _panel_cut := {}                     # bone -> true (collapsed while seated)


static func of(ch: Node) -> PosePipeline:
	for n in ch.get_children():
		if n is PosePipeline:
			return n
	var p := PosePipeline.new()
	p.name = "PosePipeline"
	p.c = ch
	ch.add_child(p)
	return p


static func stage_of(n: Node) -> int:
	var nm := String(n.name)
	if STAGES.has(nm):
		return int(STAGES[nm])
	for k in STAGES:
		if nm.begins_with(String(k)):
			return int(STAGES[k])
	if nm.begins_with("Trace") or nm.begins_with("BoneGrab") or nm.begins_with("DanceProbe"):
		return 90                        # (QA probes read the final pose)
	return 5                             # unknown pose modifiers run first, before the activity shaping


## The pipeline of whoever owns this skeleton, ordered again (call after adding a pose modifier).
static func arrange_for(sk: Skeleton3D) -> void:
	var n: Node = sk
	while n and not (n is WorldCharacter):
		n = n.get_parent()
	if n:
		PosePipeline.of(n).arrange()


## Order the skeleton's modifiers by stage (stable within a stage).
func arrange() -> void:
	var sk: Skeleton3D = c.get("skeleton")
	if sk == null:
		return
	var mods := []
	for n in sk.get_children():
		if n is SkeletonModifier3D:
			mods.append(n)
	var ranked := []
	for i in mods.size():
		ranked.append([stage_of(mods[i]), i, mods[i]])
	ranked.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var slots := []
	for m in mods:
		slots.append((m as Node).get_index())
	slots.sort()
	for k in ranked.size():
		sk.move_child(ranked[k][2], slots[k])


func _find(cls: String) -> Node:
	var sk: Skeleton3D = c.get("skeleton")
	if sk == null:
		return null
	for n in sk.get_children():
		if n.get_class() == cls or (n.get_script() and String(n.get_script().get_global_name()) == cls):
			return n
	return null


func _process(_delta: float) -> void:
	if c == null or not is_instance_valid(c):
		return
	var sk: Skeleton3D = c.get("skeleton")
	if sk == null:
		return
	var seat: SeatPose = _find("SeatPose")
	var guard: HandGuard = _find("HandGuard")
	var foot: Node = _find("FootGuard")
	var clear: Node = _find("ClothClearance")
	var life: BodyLife = _find("BodyLife")
	# the feet: the seated IK owns them while it is on
	var feet_ik := seat != null and (float(seat.leg.Left.w) > 0.1 or float(seat.leg.Right.w) > 0.1)
	if foot and foot.get("enabled") != null:
		foot.set("enabled", not feet_ik and not RenderProfile.options.has("no-foot-guard"))
	# the hands: an action's reach owns that hand
	var held := {"Left": false, "Right": false}
	if seat:
		for s in held:
			held[s] = float(seat.arm[s].w) > 0.3
	if guard:
		guard.skip = held
	if clear and clear.get("weight") is Dictionary:
		for s in held:
			if held[s]:
				(clear.get("weight") as Dictionary)[s] = 0.0
		if held.Left and held.Right:
			clear.set("allow", false)
	# one look owner: an activity's gaze (or BodyLife's, routed here) drives the head and eye look-at
	var want := Vector3.INF
	if look.is_valid():
		want = look.call()
	elif life and life.look.is_valid():
		want = life.look.call()
	if life:
		life.look_enabled = false
	var target: Node3D = c.get("_head_target")
	var hl: LookAtModifier3D = c.get("head_look")
	if target and hl and want != Vector3.INF:
		target.global_position = want
		hl.influence = move_toward(hl.influence, 1.0, 0.05)
		for el in c.get("eye_looks"):
			(el as LookAtModifier3D).influence = move_toward((el as LookAtModifier3D).influence, 1.0, 0.05)
	# seated outfit state: the long panels fold away while she sits
	_seated_panels(sk, bool(c.get("seated")))


func _seated_panels(sk: Skeleton3D, on: bool) -> void:
	var drape: SkirtDrape = _find("SkirtDrape")
	if drape == null:
		return
	for ids in drape.chains:
		var acc := 0.0
		var cut := false
		for k in range(1, (ids as Array).size()):
			var b: int = ids[k]
			acc += sk.get_bone_rest(b).origin.length()
			var want_cut := on and acc > SEATED_PANEL and not cut
			if want_cut:
				cut = true
				_panel_cut[b] = true
				sk.set_bone_pose_scale(b, Vector3.ONE * 0.02)
			elif _panel_cut.has(b) and not on:
				_panel_cut.erase(b)
				sk.set_bone_pose_scale(b, Vector3.ONE)
