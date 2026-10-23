class_name TeleportGuard
extends Node
## The no-teleportation rule, watched (V3 continuation: "Mika, Luna and ordinary NPCs must NOT possess teleportation
## ... No unexplained companion teleporting. No magical relocation used to hide navigation failures.").
## Every physics frame it compares each visible mage's position with the last frame's. A jump farther than anyone can
## move in one frame (1.5 m at any frame rate: a sprint is ~0.15 m, the strongest blast push ~0.2 m) is a teleport
## and is recorded with what was going on. Exempt: area loads (the masked streaming transition places the travelling
## mage at the gate she walked through) and explicit developer staging (tests/tools call allow()).

const MAX_STEP := 1.5

var main: Node
var violations: Array = []
var frames := 0
var _last := {}
var _allowed := {}


func setup(m: Node) -> void:
	main = m


var folds: Array = []          # learned Fold Steps (the Weaver's spell): legitimate, recorded with their reason


## A mage cast the Fold Step she learned (MagicSystem.fold_step): the jump that follows is magic she owns, not a
## teleport of convenience. Recorded in `folds` (who, from, to, when), never in violations.
func authorize_fold(c: Node, from: Vector3, to: Vector3) -> void:
	_allowed[c.get_instance_id()] = Engine.get_physics_frames() + 2
	folds.append({"who": String(c.get("character_id")), "from": [snappedf(from.x, 0.1), snappedf(from.y, 0.1), snappedf(from.z, 0.1)],
		"to": [snappedf(to.x, 0.1), snappedf(to.y, 0.1), snappedf(to.z, 0.1)], "metres": snappedf(from.distance_to(to), 0.1), "clock": WorldState.clock_text()})


## A developer utility (test staging / tools) is about to place `c`: not a violation.
func allow(c: Node) -> void:
	_allowed[c.get_instance_id()] = Engine.get_physics_frames() + 2


func _physics_process(_delta: float) -> void:
	if main == null or main.get("characters") == null:
		return
	var loading: bool = main.get("streaming") != null and main.streaming.state != "idle"
	frames += 1
	for who in main.characters:
		var c: WorldCharacter = main.characters[who]
		if c == null or not is_instance_valid(c) or not c.visible or not c.is_inside_tree():
			_last.erase(who)
			continue
		var p := c.global_position
		var id := c.get_instance_id()
		if _last.has(who) and not loading and Engine.get_physics_frames() > int(_allowed.get(id, -1)):
			var d := (p - (_last[who] as Vector3)).length()
			if d > MAX_STEP:
				violations.append({"who": who, "jump_m": snappedf(d, 0.01), "frame": Engine.get_physics_frames(),
					"area": main.streaming.current_id if main.get("streaming") else "", "action": c.current_action,
					"reaction": c.reaction.phase if c.reaction else ""})
				push_warning("[teleport_guard] %s moved %.2f m in one frame" % [who, d])
		_last[who] = p
		_fall_check(who, c, loading)


## Falling out of the world (2026-10-23 live: Mika ran a race off the ground at Lantern Lake and fell for 21 minutes,
## the camera following her down into an empty purple screen). Where she last stood on the floor is remembered; well
## below it with no floor under her, she is put back there and whatever she was doing is stopped. Logged, not hidden.
const FALL_BELOW_M := 6.0
var _floor := {}
var falls: Array = []


func _fall_check(who: String, c: WorldCharacter, loading: bool) -> void:
	if loading:
		_floor.erase(who)
		return
	if c.is_on_floor():
		_floor[who] = c.global_position
		return
	if not _floor.has(who):
		return
	var back: Vector3 = _floor[who]
	if c.global_position.y > back.y - FALL_BELOW_M:
		return
	falls.append({"who": who, "from": [snappedf(back.x, 0.1), snappedf(back.y, 0.1), snappedf(back.z, 0.1)],
		"area": main.streaming.current_id if main.get("streaming") else "", "action": c.current_action, "clock": WorldState.clock_text()})
	push_warning("[fall_guard] %s fell out of the world during '%s': put back where she last stood %s" % [who, c.current_action, back.snapped(Vector3.ONE * 0.1)])
	c.stop_action()
	allow(c)
	c.global_position = back + Vector3(0, 0.05, 0)
	c.velocity = Vector3.ZERO
	_last[who] = c.global_position
