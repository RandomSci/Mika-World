class_name EarController
extends SkeletonModifier3D
## Mika's wolf ears act (appearance profile: motion "ears" > 0). Runs after the spring bones: the base of each ear
## (J_Sec_Ear{L,R}_0) is turned by her emotion - perked and spread when excited or surprised, softly back when
## content, drooping sideways when sad or tired, flattened back when frustrated, one ear cocked when curious - and
## twitches now and then on its own. Eased (never snapping); the springs keep the tips alive on top.

var c: WorldCharacter
var amount := 1.0
var _cur := {"L": Vector2.ZERO, "R": Vector2.ZERO}   # x: droop sideways (rad, + = outward), y: tilt back (rad, + = back)
var _twitch := {"L": 0.0, "R": 0.0}
var _next_twitch := 3.0
var _t := 0.0
var _bones := {}

const POSES := {
	"neutral": [Vector2(0.0, 0.0), Vector2(0.0, 0.0)],
	"happy": [Vector2(0.05, 0.12), Vector2(0.05, 0.12)],
	"excited": [Vector2(-0.12, -0.18), Vector2(-0.12, -0.18)],
	"surprised": [Vector2(-0.18, -0.25), Vector2(-0.18, -0.25)],
	"curious": [Vector2(0.0, -0.2), Vector2(0.18, 0.05)],
	"sad": [Vector2(0.55, 0.3), Vector2(0.55, 0.3)],
	"concerned": [Vector2(0.3, 0.2), Vector2(0.3, 0.2)],
	"tired": [Vector2(0.45, 0.2), Vector2(0.45, 0.2)],
	"frustrated": [Vector2(0.15, 0.6), Vector2(0.15, 0.6)],
	"shy": [Vector2(0.3, 0.35), Vector2(0.3, 0.35)],
	"playful": [Vector2(-0.05, 0.0), Vector2(0.25, 0.15)],
	"relaxed": [Vector2(0.12, 0.1), Vector2(0.12, 0.1)],
	"laughing": [Vector2(-0.08, 0.05), Vector2(-0.08, 0.05)],
	"determined": [Vector2(-0.08, -0.08), Vector2(-0.08, -0.08)],
}


static func attach(ch: WorldCharacter, amt: float) -> EarController:
	if ch.skeleton.find_bone("J_Sec_EarL_0") < 0:
		return null
	var e := EarController.new()
	e.name = "EarController"
	e.c = ch
	e.amount = amt
	ch.skeleton.add_child(e)
	ch.skeleton.move_child(e, -1)
	return e


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or c == null:
		return
	var dt := 1.0 / 60.0
	_t += dt
	var emo := c.face.dominant() if c.face else "neutral"
	var pose: Array = POSES.get(emo, POSES.neutral)
	if _t > _next_twitch:
		_next_twitch = _t + randf_range(3.5, 9.0)
		var side := "L" if randf() < 0.5 else "R"
		_twitch[side] = 1.0
	var head := sk.find_bone("Head")
	if head < 0:
		return
	var hb := sk.get_bone_global_pose(head).basis
	var fwd := hb.z.normalized()           # VRM head forward (+Z)
	var right := hb.x.normalized()
	for side in ["L", "R"]:
		var bn := "J_Sec_Ear%s_0" % side
		if not _bones.has(bn):
			_bones[bn] = sk.find_bone(bn)
		var bi: int = _bones[bn]
		if bi < 0:
			continue
		var want: Vector2 = pose[0 if side == "L" else 1] * amount
		_cur[side] = (_cur[side] as Vector2).lerp(want, 1.0 - exp(-6.0 * dt))
		_twitch[side] = maxf(0.0, float(_twitch[side]) - dt * 4.0)
		var tw := sin(float(_twitch[side]) * PI * 3.0) * 0.18 * float(_twitch[side])
		var sgn := 1.0 if side == "L" else -1.0       # outward = away from the head's centre line
		var droop := Basis(fwd, -sgn * ((_cur[side] as Vector2).x + tw * 0.4))
		var back := Basis(right, (_cur[side] as Vector2).y + tw)
		var gp := sk.get_bone_global_pose(bi)
		var nb := droop * back * gp.basis
		var parent := sk.get_bone_parent(bi)
		var pb := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		sk.set_bone_pose_rotation(bi, (pb.inverse() * nb).get_rotation_quaternion())
