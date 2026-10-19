class_name FightPhysics
extends RefCounted
## Combat v3 partial physics on hits: a PhysicalBoneSimulator3D on each fighter (pose stage "FightPhysics", 19 - after
## the rig, before the final-pose trace) with physical bones on her spine, neck, head and shoulders (kinematic hips
## as the anchor). A blow simulates only the struck chain for 0.2 - 0.4 s: an impulse at the hit, the simulator's
## influence rising to a peak and blending back to the animation - so no two hits look the same. The bodies collide
## with nothing (layer / mask 0): pure joint dynamics, the cone joints keep every bone inside a human range.

## bone -> [child bone (its length), radius m at k = 1, cone swing deg, twist deg, mass kg]
const BONES := {
	"Hips": ["Spine", 0.13, 0.0, 0.0, 10.0],
	"Spine": ["Chest", 0.12, 14.0, 8.0, 6.0],
	"Chest": ["UpperChest", 0.12, 12.0, 8.0, 6.0],
	"UpperChest": ["Neck", 0.12, 12.0, 8.0, 5.0],
	"Neck": ["Head", 0.05, 22.0, 18.0, 1.5],
	"Head": ["", 0.09, 26.0, 22.0, 4.5],
	"LeftShoulder": ["LeftUpperArm", 0.05, 16.0, 6.0, 1.5],
	"RightShoulder": ["RightUpperArm", 0.05, 16.0, 6.0, 1.5],
}
## the zone a blow landed on -> the chain that goes loose
const CHAINS := {
	"head": ["Neck", "Head"],
	"chest": ["Chest", "UpperChest", "Neck", "Head"],
	"stomach": ["Spine", "Chest", "UpperChest", "Neck", "Head"],
	"left": ["Chest", "UpperChest", "LeftShoulder", "Neck", "Head"],
	"right": ["Chest", "UpperChest", "RightShoulder", "Neck", "Head"],
	"legs": ["Spine", "Chest"],
}

var sim: PhysicalBoneSimulator3D
var sk: Skeleton3D
var k := 1.0
var pb := {}                              # bone -> PhysicalBone3D
var _t := 0.0                             # time into the current blow (-1: idle)
var _len := 0.3
var _peak := 0.5
var _impulse := {}                        # applied on the first physics frame of a blow


static func make(skel: Skeleton3D, scale_k: float) -> FightPhysics:
	var f := FightPhysics.new()
	f.sk = skel
	f.k = scale_k
	f._build()
	return f


func _build() -> void:
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "FightPhysics"
	sim.influence = 0.0
	sk.add_child(sim)
	for bone in BONES:
		var bi := sk.find_bone(bone)
		if bi < 0:
			continue
		var spec: Array = BONES[bone]
		var origin := sk.get_bone_global_rest(bi).origin
		var length := 0.12 * k
		if String(spec[0]) != "" and sk.find_bone(spec[0]) >= 0:
			length = maxf(origin.distance_to(sk.get_bone_global_rest(sk.find_bone(spec[0])).origin), 0.04 * k)
		var r := float(spec[1]) * k
		var b := PhysicalBone3D.new()
		b.name = "PB_" + bone
		b.bone_name = bone
		b.collision_layer = 0
		b.collision_mask = 0
		b.mass = float(spec[4])
		b.gravity_scale = 0.25
		b.linear_damp = 4.0
		b.angular_damp = 7.0
		# the body sits half way along the bone (local +Y runs along every VRM bone); the joint at the bone's root
		b.body_offset = Transform3D(Basis(), Vector3(0, length * 0.5, 0))
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = maxf(length, r * 2.0 + 0.001)
		cs.shape = cap
		b.add_child(cs)
		if bone != "Hips":
			b.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			b.joint_offset = Transform3D(Basis(), Vector3(0, -length * 0.5, 0))
			b.set("joint_constraints/swing_span", float(spec[2]))
			b.set("joint_constraints/twist_span", float(spec[3]))
			b.set("joint_constraints/bias", 0.6)
			b.set("joint_constraints/softness", 0.8)
			b.set("joint_constraints/relaxation", 1.0)
		sim.add_child(b)
		pb[bone] = b
	PosePipeline.arrange_for(sk)
	_t = -1.0


## A blow on `zone` from world direction `dir` (where it travels), power 0..1: the chain goes loose for 0.2 - 0.4 s.
func hit(zone: String, dir: Vector3, power: float) -> void:
	var chain: Array = CHAINS.get(zone, CHAINS.chest)
	var names: Array[StringName] = []
	for b in chain:
		if pb.has(b):
			names.append(StringName(b))
	if names.is_empty():
		return
	sim.physical_bones_stop_simulation()
	sim.physical_bones_start_simulation(names)
	_len = lerpf(0.2, 0.4, clampf(power, 0.0, 1.0))
	_peak = lerpf(0.35, 0.7, clampf(power, 0.0, 1.0))
	_t = 0.0
	var top: String = chain[chain.size() - 1] if zone == "head" else chain[0]
	_impulse = {"bone": top, "v": dir.normalized() * lerpf(1.2, 3.2, power) * float((pb[top] as PhysicalBone3D).mass if pb.has(top) else 1.0)}


func update(dt: float) -> void:
	if _t < 0.0:
		return
	if not _impulse.is_empty() and pb.has(_impulse.bone):
		(pb[_impulse.bone] as PhysicalBone3D).apply_central_impulse(_impulse.v)
		_impulse = {}
	_t += dt
	var u := _t / _len
	# rises fast (a third of the time), falls back smoothly to the animation
	sim.influence = _peak * (smoothstep(0.0, 0.33, u) if u < 0.33 else 1.0 - smoothstep(0.33, 1.0, u))
	if u >= 1.0:
		sim.influence = 0.0
		sim.physical_bones_stop_simulation()
		_t = -1.0


func teardown() -> void:
	if is_instance_valid(sim):
		sim.physical_bones_stop_simulation()
		sim.queue_free()
