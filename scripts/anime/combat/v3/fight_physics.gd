class_name FightPhysics
extends RefCounted
## Combat v3 partial physics on hits: the struck chain (head / chest / stomach / a side / the legs) goes loose for
## 0.2 - 0.4 s and blends back to the animation, so no two hits look alike.
##
## Each bone of the chain is a damped angular spring (a pendulum about its joint): the blow is an impulse on the struck
## bone (half on its neighbours) turning it away from the blow, with a random share of twist and strength; the springs
## ring out (8 Hz, damping 0.35) inside a cone per joint, and the whole layer fades back to the animation. Applied as a
## pose stage ("FightPhysics", 19: after the rig, before the trace) that only TURNS bones about their joints - nothing
## is moved or stretched.
##
## (Tried first and dropped, 2026-10-20: Godot's PhysicalBoneSimulator3D with partial simulation. Standing still it
## worked, but during knock-backs and launches its write-back jolted the hips / spine for a frame and the skirt and
## hair springs - which follow those bones - flew out like planks in every moving reaction. This layer keeps the same
## idea - real dynamics on the struck part only - inside our own pose pipeline.)

## bone -> [cone deg, inertia factor]
const BONES := {
	"Spine": [14.0, 1.6], "Chest": [12.0, 1.4], "UpperChest": [12.0, 1.2], "Neck": [20.0, 0.6], "Head": [26.0, 0.8],
	"LeftShoulder": [14.0, 0.6], "RightShoulder": [14.0, 0.6], "LeftUpperArm": [22.0, 0.7], "RightUpperArm": [22.0, 0.7],
}
const CHAINS := {
	"head": ["Neck", "Head"],
	"chest": ["Chest", "UpperChest", "Neck", "Head"],
	"stomach": ["Spine", "Chest", "UpperChest", "Neck", "Head"],
	"left": ["Chest", "UpperChest", "LeftShoulder", "LeftUpperArm", "Neck", "Head"],
	"right": ["Chest", "UpperChest", "RightShoulder", "RightUpperArm", "Neck", "Head"],
	"legs": ["Spine", "Chest", "Head"],
}
const ORDER := ["Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm", "Neck", "Head"]
## (2026-10-20, Selwyn: "their bodies are trembling so bad during battle". At 8 Hz and damping 0.35 the struck chain
## rang a full shake every 3.75 frames at 30 fps, integrated at w*dt 1.67 near its stability edge, so it flipped back
## and forth frame to frame; the head's shake after this layer was 19.5 deg per frame. Now one lurch away from the blow
## and a slow settle, critically damped, integrated in 1/120 s steps.)
const FREQ := 2.2                         # Hz: how fast a struck bone swings back
const DAMP := 1.0
const SUBSTEP := 1.0 / 120.0

var sk: Skeleton3D
var k := 1.0
var mod: Mod
var rng := RandomNumberGenerator.new()
var state := {}                           # bone -> [angle vector (skeleton space, rad), angular velocity]
var _t := -1.0
var _len := 0.3
var sim: Mod:                             # (QA probes read sim.influence)
	get:
		return mod


class Mod extends SkeletonModifier3D:
	var owner_ref: FightPhysics

	func _process_modification() -> void:
		if owner_ref:
			owner_ref._apply(get_skeleton())


static func make(skel: Skeleton3D, scale_k: float) -> FightPhysics:
	var f := FightPhysics.new()
	f.sk = skel
	f.k = scale_k
	f.rng.randomize()
	f.mod = Mod.new()
	f.mod.name = "FightPhysics"
	f.mod.owner_ref = f
	f.mod.influence = 0.0
	skel.add_child(f.mod)
	PosePipeline.arrange_for(skel)
	return f


## A blow on `zone` travelling `dir` (world), power 0..1: the chain gets an impulse and rings for 0.2 - 0.4 s.
func hit(zone: String, dir: Vector3, power: float) -> void:
	var chain: Array = CHAINS.get(zone, CHAINS.chest)
	var p := clampf(power, 0.0, 1.0)
	_len = lerpf(0.2, 0.4, p)
	_t = 0.0
	var ld := sk.global_transform.basis.inverse() * Vector3(dir.x, 0.0, dir.z).normalized()
	var struck: String = chain[chain.size() - 1] if zone == "head" else chain[0]
	for b in chain:
		var bi := sk.find_bone(b)
		if bi < 0:
			continue
		var spec: Array = BONES.get(b, [16.0, 1.0])
		# the bone turns away from the blow: about (its up) x (the blow), plus a random share of twist
		var up := (sk.get_bone_global_pose(bi).basis * Vector3.UP).normalized()
		var axis := up.cross(ld)
		if axis.length() < 0.05:
			axis = Vector3(1, 0, 0)
		axis = (axis.normalized() + up * rng.randf_range(-0.35, 0.35)).normalized()
		var share := 1.0 if b == struck else 0.5
		var speed := deg_to_rad(lerpf(160.0, 420.0, p) if RenderProfile.options.has("fight-legacy-motion") else lerpf(90.0, 240.0, p)) * share * rng.randf_range(0.8, 1.2) / float(spec[1])
		var st: Array = state.get(b, [Vector3.ZERO, Vector3.ZERO])
		st[1] = (st[1] as Vector3) + axis * speed
		state[b] = st


func update(dt: float) -> void:
	if _t < 0.0:
		return
	_t += dt
	var legacy := RenderProfile.options.has("fight-legacy-motion")     # (QA: the old ringing, for before renders)
	var w0 := TAU * (8.0 if legacy else FREQ)
	var damp := 0.35 if legacy else DAMP
	var n := 1 if legacy else maxi(int(ceil(dt / SUBSTEP)), 1)
	var h := dt / float(n)
	for b in state:
		var st: Array = state[b]
		var th: Vector3 = st[0]
		var om: Vector3 = st[1]
		for _i in n:
			om += (-th * w0 * w0 - om * 2.0 * damp * w0) * h
			th += om * h
		var lim := deg_to_rad(float(BONES.get(b, [16.0])[0]))
		if th.length() > lim:
			th = th.normalized() * lim                  # (the joint's cone: it stops there, the push dies)
			om -= th.normalized() * maxf(om.dot(th.normalized()), 0.0)
		st[0] = th
		st[1] = om
	var u := _t / _len
	mod.influence = 1.0 - smoothstep(0.55, 1.0, u)
	if u >= 1.0:
		mod.influence = 0.0
		state.clear()
		_t = -1.0


func _apply(s: Skeleton3D) -> void:
	# parents first, so a loose spine carries the chest, the chest the neck ...
	for b in ORDER:
		if not state.has(b):
			continue
		var th: Vector3 = state[b][0]
		if th.length() < 0.0005:
			continue
		var bi := s.find_bone(b)
		var g := s.get_bone_global_pose(bi)
		s.set_bone_global_pose(bi, Transform3D(Basis(th.normalized(), th.length()) * g.basis, g.origin))


## (kept for the trace: nothing to do - this layer never moves a bone)
func keep_lengths() -> void:
	pass


func teardown() -> void:
	if is_instance_valid(mod):
		mod.queue_free()
